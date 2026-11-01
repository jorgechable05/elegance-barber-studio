-- ELEGANCE BARBER STUDIO: multi-service packages, reservation conflict protection,
-- sale-level item snapshots and demand/margin-aware promotion suggestions.
-- DRAFT: run only on an isolated, non-production Elegance database after review.

-- A cost is optional until the owner has entered a verified value. NULL means unknown,
-- never zero. Sales snapshot this cost at the time of sale for honest margin analysis.
alter table public.barber_services
  add column if not exists unit_cost numeric(10,2)
    check (unit_cost is null or unit_cost >= 0);

alter table public.barber_promotion_suggestion_settings
  add column if not exists lookback_days integer not null default 30
    check (lookback_days between 7 and 180),
  add column if not exists minimum_margin_percent numeric(5,2) not null default 20
    check (minimum_margin_percent between 0 and 95),
  add column if not exists minimum_margin_sample integer not null default 3
    check (minimum_margin_sample between 1 and 100);

alter table public.barber_promotions
  add column if not exists suggestion_evidence jsonb;

create table if not exists public.barber_service_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(trim(name)) > 0)
);

create table if not exists public.barber_service_package_items (
  package_id uuid not null references public.barber_service_packages(id) on delete cascade,
  service_id integer not null references public.barber_services(id) on delete restrict,
  position integer not null default 0 check (position >= 0),
  primary key (package_id, service_id),
  unique (package_id, position)
);

alter table public.reservas
  add column if not exists package_id uuid references public.barber_service_packages(id) on delete set null,
  add column if not exists duracion_minutos integer
    check (duracion_minutos is null or duracion_minutos between 5 and 960),
  add column if not exists reservation_group_id uuid;

alter table public.barber_sales
  add column if not exists package_id uuid references public.barber_service_packages(id) on delete set null,
  add column if not exists service_cost_snapshot numeric(12,2)
    check (service_cost_snapshot is null or service_cost_snapshot >= 0);

create table if not exists public.barber_reservation_items (
  reservation_id uuid not null references public.reservas(id) on delete cascade,
  package_id uuid not null references public.barber_service_packages(id) on delete restrict,
  service_id integer not null references public.barber_services(id) on delete restrict,
  position integer not null check (position >= 0),
  service_name_snapshot text not null,
  base_price numeric(12,2) not null check (base_price >= 0),
  booked_net_price numeric(12,2) not null check (booked_net_price >= 0),
  duration_minutes integer not null check (duration_minutes between 5 and 480),
  primary key (reservation_id, service_id),
  unique (reservation_id, position)
);

create table if not exists public.barber_sale_items (
  sale_id bigint not null references public.barber_sales(id) on delete cascade,
  service_id integer not null references public.barber_services(id) on delete restrict,
  position integer not null check (position >= 0),
  service_name_snapshot text not null,
  catalog_price_snapshot numeric(12,2) not null check (catalog_price_snapshot >= 0),
  net_amount numeric(12,2) not null check (net_amount >= 0),
  discount_amount numeric(12,2) not null check (discount_amount >= 0),
  unit_cost_snapshot numeric(12,2) check (unit_cost_snapshot is null or unit_cost_snapshot >= 0),
  primary key (sale_id, service_id),
  unique (sale_id, position),
  check (round(catalog_price_snapshot-discount_amount,2)=round(net_amount,2))
);

create index if not exists barber_service_package_items_service_idx
  on public.barber_service_package_items(service_id);
create index if not exists barber_reservation_items_package_idx
  on public.barber_reservation_items(package_id,reservation_id);
create index if not exists barber_sale_items_service_idx
  on public.barber_sale_items(service_id,sale_id);

alter table public.barber_service_packages enable row level security;
alter table public.barber_service_package_items enable row level security;
alter table public.barber_reservation_items enable row level security;
alter table public.barber_sale_items enable row level security;
revoke all on public.barber_service_packages, public.barber_service_package_items,
  public.barber_reservation_items, public.barber_sale_items from public, anon, authenticated;
grant select on public.barber_service_packages, public.barber_service_package_items to anon, authenticated;
grant select, insert, update, delete on public.barber_service_packages, public.barber_service_package_items,
  public.barber_reservation_items, public.barber_sale_items to service_role;

create or replace function public.barber_service_package_admin_list(p_token uuid)
returns table(
  id uuid, name text, description text, price numeric, is_active boolean,
  service_ids integer[], service_names text[], base_total numeric, duration_minutes integer
)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query
  select p.id,p.name,p.description,p.price,p.is_active,
    coalesce(array_agg(s.id order by i.position) filter(where s.id is not null),'{}'::integer[]),
    coalesce(array_agg(s.name order by i.position) filter(where s.id is not null),'{}'::text[]),
    coalesce(sum(s.price),0)::numeric,coalesce(sum(s.duration_minutes),0)::integer
  from public.barber_service_packages p
  left join public.barber_service_package_items i on i.package_id=p.id
  left join public.barber_services s on s.id=i.service_id
  group by p.id
  order by p.created_at desc;
end;
$$;

create or replace function public.barber_service_package_public()
returns table(
  id uuid, name text, description text, price numeric,
  service_ids integer[], service_names text[], base_total numeric, duration_minutes integer
)
language sql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select p.id,p.name,p.description,p.price,
    coalesce(array_agg(s.id order by i.position) filter(where s.id is not null),'{}'::integer[]),
    coalesce(array_agg(s.name order by i.position) filter(where s.id is not null),'{}'::text[]),
    coalesce(sum(s.price),0)::numeric,coalesce(sum(s.duration_minutes),0)::integer
  from public.barber_service_packages p
  left join public.barber_service_package_items i on i.package_id=p.id
  left join public.barber_services s on s.id=i.service_id and s.is_active
  where p.is_active
  group by p.id
  order by p.name;
$$;

create or replace function public.barber_service_package_admin_save(
  p_token uuid,p_id uuid,p_name text,p_description text,p_price numeric,
  p_is_active boolean,p_service_ids integer[]
)
returns public.barber_service_packages
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_service_packages; v_count integer; v_base numeric;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if nullif(trim(p_name),'') is null or p_price is null or p_price<0
    or coalesce(array_length(p_service_ids,1),0)<2 then
    raise exception 'El paquete requiere nombre, precio válido y al menos dos servicios' using errcode='22023';
  end if;
  if (select count(distinct x) from unnest(p_service_ids) x)<>cardinality(p_service_ids) then
    raise exception 'No repitas servicios dentro del paquete' using errcode='22023';
  end if;
  select count(*),coalesce(sum(s.price),0) into v_count,v_base
  from public.barber_services s
  where s.id=any(p_service_ids) and s.is_active;
  if v_count<>cardinality(p_service_ids) then
    raise exception 'Todos los servicios del paquete deben existir y estar activos' using errcode='22023';
  end if;
  if p_price>v_base then
    raise exception 'El precio del paquete no puede superar la suma de los servicios incluidos' using errcode='22023';
  end if;
  if p_id is null then
    insert into public.barber_service_packages(name,description,price,is_active)
    values(trim(p_name),coalesce(p_description,''),round(p_price,2),coalesce(p_is_active,true))
    returning * into v_row;
  else
    update public.barber_service_packages set name=trim(p_name),description=coalesce(p_description,''),
      price=round(p_price,2),is_active=coalesce(p_is_active,true),updated_at=now()
      where id=p_id returning * into v_row;
    if not found then raise exception 'Paquete no encontrado' using errcode='P0002'; end if;
    delete from public.barber_service_package_items where package_id=v_row.id;
  end if;
  insert into public.barber_service_package_items(package_id,service_id,position)
    select v_row.id,x,ord-1 from unnest(p_service_ids) with ordinality q(x,ord);
  return v_row;
end;
$$;


-- Dedicated settings API avoids changing the existing RPC result/signature contract.
create or replace function public.barber_promotion_history_settings_admin_get(p_token uuid)
returns table(lookback_days integer,minimum_margin_percent numeric,minimum_margin_sample integer)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query select c.lookback_days,c.minimum_margin_percent,c.minimum_margin_sample
    from public.barber_promotion_suggestion_settings c where c.id=1;
end;
$$;

create or replace function public.barber_promotion_history_settings_admin_save(
  p_token uuid,p_lookback_days integer,p_minimum_margin_percent numeric,p_minimum_margin_sample integer
)
returns public.barber_promotion_suggestion_settings
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_promotion_suggestion_settings;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_lookback_days not between 7 and 180 or p_minimum_margin_percent not between 0 and 95
     or p_minimum_margin_sample not between 1 and 100 then
    raise exception 'Reglas de demanda y margen inválidas' using errcode='22023';
  end if;
  update public.barber_promotion_suggestion_settings set lookback_days=p_lookback_days,
    minimum_margin_percent=p_minimum_margin_percent,minimum_margin_sample=p_minimum_margin_sample,updated_at=now()
  where id=1 returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.barber_promotions_suggestion_evidence_admin_list(p_token uuid)
returns table(id uuid,suggestion_evidence jsonb)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query select p.id,p.suggestion_evidence from public.barber_promotions p where p.source='daily_suggestion';
end;
$$;

create or replace function public.barber_service_unit_cost_admin_clear(p_token uuid,p_service_id integer)
returns public.barber_services
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_services;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  update public.barber_services set unit_cost=null,updated_at=now()
    where id=p_service_id returning * into v_row;
  if not found then raise exception 'Servicio no encontrado' using errcode='P0002'; end if;
  return v_row;
end;
$$;

create or replace function public.barber_service_unit_cost_admin_save(
  p_token uuid,p_service_id integer,p_unit_cost numeric
)
returns public.barber_services
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_services;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_unit_cost is null or p_unit_cost<0 then
    raise exception 'El costo unitario debe ser un importe no negativo' using errcode='22023';
  end if;
  update public.barber_services set unit_cost=round(p_unit_cost,2),updated_at=now()
    where id=p_service_id returning * into v_row;
  if not found then raise exception 'Servicio no encontrado' using errcode='P0002'; end if;
  return v_row;
end;
$$;

create or replace function public.barber_service_sales_history_admin_list(p_token uuid,p_lookback_days integer default 30)
returns table(
  service_id integer,service_name text,sales_count bigint,revenue numeric,
  estimated_margin numeric,margin_percent numeric,margin_sample_count bigint,
  margin_coverage_percent numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_lookback_days not between 7 and 180 then
    raise exception 'El periodo debe estar entre 7 y 180 días' using errcode='22023';
  end if;
  return query
  with line_history as (
    select svc.id service_id, s.id sale_id, round(s.total,2) net_amount,
      s.service_cost_snapshot cost_snapshot
    from public.barber_sales s
    join public.barber_services svc on svc.name=s.servicio
    where s.package_id is null and s.creado>=now()-make_interval(days=>p_lookback_days)
    union all
    select si.service_id,si.sale_id,si.net_amount,si.unit_cost_snapshot
    from public.barber_sale_items si
    join public.barber_sales s on s.id=si.sale_id
    where s.creado>=now()-make_interval(days=>p_lookback_days)
  ), aggregated as (
    select h.service_id,count(distinct h.sale_id) sales_count,
      coalesce(sum(h.net_amount),0)::numeric revenue,
      coalesce(sum(h.net_amount-h.cost_snapshot) filter(where h.cost_snapshot is not null),0)::numeric estimated_margin,
      avg(100*(h.net_amount-h.cost_snapshot)/nullif(h.net_amount,0)) filter(where h.cost_snapshot is not null)::numeric margin_percent,
      count(*) filter(where h.cost_snapshot is not null) margin_sample_count
    from line_history h group by h.service_id
  )
  select svc.id,svc.name,coalesce(a.sales_count,0),coalesce(a.revenue,0),
    case when coalesce(a.margin_sample_count,0)>0 then a.estimated_margin else null end,
    a.margin_percent,coalesce(a.margin_sample_count,0),
    case when coalesce(a.sales_count,0)>0 then round(100.0*coalesce(a.margin_sample_count,0)/a.sales_count,2) else 0 end
  from public.barber_services svc left join aggregated a on a.service_id=svc.id
  order by svc.display_order,svc.name;
end;
$$;

-- Serializes reservation writes by barber/date and rejects overlapping appointment windows,
-- including bookings created through the legacy RPC. Unknown legacy service rows use 30 min.
create or replace function public.barber_reservation_overlap_guard()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_start timestamp; v_end timestamp;
begin
  if new.fecha is null or nullif(trim(new.hora),'') is null then return new; end if;
  if new.duracion_minutos is null then
    select s.duration_minutes into new.duracion_minutos
      from public.barber_services s
      where (new.servicio_id is not null and s.id=new.servicio_id)
        or (new.servicio_id is null and s.name=coalesce(nullif(trim(new.servicio),''),new.serv))
      order by case when new.servicio_id is not null then 0 else 1 end
      limit 1;
    new.duracion_minutos:=coalesce(new.duracion_minutos,30);
  end if;
  if new.duracion_minutos not between 5 and 960 then
    raise exception 'Duración de reserva fuera de rango' using errcode='22023';
  end if;
  begin v_start:=(new.fecha::text||' '||left(trim(new.hora),5))::timestamp;
  exception when others then raise exception 'Hora de reserva inválida' using errcode='22023'; end;
  v_end:=v_start+make_interval(mins=>new.duracion_minutos);
  perform pg_advisory_xact_lock(hashtextextended(coalesce(new.barbero,'')||':'||new.fecha::text,0));
  if exists(
    select 1 from public.reservas r
    left join public.barber_services s on
      (r.servicio_id is not null and s.id=r.servicio_id)
      or (r.servicio_id is null and s.name=coalesce(nullif(trim(r.servicio),''),r.serv))
    where r.barbero=new.barbero and r.fecha=new.fecha
      and (new.id is null or r.id<>new.id)
      and lower(coalesce(r.estado,'pendiente')) not in ('rechazada','cancelada','atendida')
      and (r.fecha + left(trim(r.hora),5)::time)
          < v_end
      and v_start < ((r.fecha + left(trim(r.hora),5)::time)
        + make_interval(mins=>coalesce(r.duracion_minutos,s.duration_minutes,30)))
  ) then
    raise exception 'El horario se cruza con otra cita para este barbero' using errcode='23P01';
  end if;
  return new;
end;
$$;

drop trigger if exists barber_reservation_overlap_guard_trg on public.reservas;
create trigger barber_reservation_overlap_guard_trg
before insert or update of fecha,hora,barbero,servicio,serv,servicio_id,package_id,duracion_minutos,estado
on public.reservas for each row execute function public.barber_reservation_overlap_guard();

-- New package reservations occupy one real appointment row, with a duration equal to
-- the sum of included services. Item snapshots preserve names, order and booking price.
create or replace function public.barber_create_package_reservation(
  p_barbero_id integer,p_fecha date,p_hora text,p_nombre text,p_telefono text,
  p_package_id uuid,p_promotion_id uuid default null
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_package public.barber_service_packages; v_barbero text; v_group_id uuid:=gen_random_uuid();
  v_reservation uuid; v_base numeric(12,2); v_final numeric(12,2); v_discount numeric(12,2);
  v_time time; v_start timestamptz; v_weekday smallint; v_promo public.barber_promotions;
  v_item record; v_position integer:=0; v_allocated numeric(12,2):=0; v_net numeric(12,2);
begin
  if p_barbero_id not in (1,2) then raise exception 'Barbero no válido' using errcode='22023'; end if;
  v_barbero:=case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end;
  select * into v_package from public.barber_service_packages where id=p_package_id and is_active;
  if not found then raise exception 'Paquete no válido o inactivo' using errcode='22023'; end if;
  select sum(s.price),sum(s.duration_minutes) into v_base,v_discount
    from public.barber_service_package_items i join public.barber_services s on s.id=i.service_id and s.is_active
    where i.package_id=p_package_id;
  if (select count(*) from public.barber_service_package_items where package_id=p_package_id)<2
    or v_base is null or v_package.price>v_base then
    raise exception 'El paquete ya no es válido tras cambios en el catálogo' using errcode='22023';
  end if;
  if p_fecha is null or p_fecha<current_date or extract(isodow from p_fecha)=7 then
    raise exception 'La fecha no está disponible' using errcode='22023';
  end if;
  begin v_time:=left(trim(p_hora),5)::time;
  exception when others then raise exception 'Horario no válido' using errcode='22023'; end;
  v_start:=(p_fecha::text||' '||v_time::text||' America/Merida')::timestamptz;
  v_final:=v_package.price; v_weekday:=extract(dow from p_fecha)::smallint;
  if p_promotion_id is not null then
    select p.* into v_promo from public.barber_promotions p
    where p.id=p_promotion_id and p.status='approved'
      and v_start>=p.starts_at and v_start<p.ends_at
      and (cardinality(p.weekdays)=0 or v_weekday=any(p.weekdays))
      and (p.start_time is null or v_time>=p.start_time)
      and (p.end_time is null or v_time<p.end_time)
      and (p.max_uses is null or p.uses_count<p.max_uses)
    for update;
    if not found then raise exception 'Promoción no válida para esta cita' using errcode='22023'; end if;
    if exists(
      select 1 from public.barber_service_package_items pi
      where pi.package_id=p_package_id and not exists(
        select 1 from public.barber_promotion_services ps
        where ps.promotion_id=p_promotion_id and ps.service_id=pi.service_id
      )
    ) then raise exception 'La promoción no cubre todos los servicios del paquete' using errcode='22023'; end if;
    if v_promo.discount_type='percent' then
      v_final:=round(v_package.price*(1-v_promo.discount_value/100),2);
    elsif v_promo.discount_type='fixed_price' then
      if v_promo.discount_value>v_package.price then raise exception 'El precio especial supera el precio del paquete'; end if;
      v_final:=v_promo.discount_value;
    else raise exception 'Tipo de promoción inválido' using errcode='22023'; end if;
  end if;
  if v_final<0 or v_final>v_base then raise exception 'Precio final inválido' using errcode='22023'; end if;
  insert into public.reservas(nombre,telefono,wa,serv,servicio,precio,barbero,fecha,hora,estado,stock_key,
    promotion_id,servicio_id,precio_base,package_id,duracion_minutos,reservation_group_id)
  values(trim(p_nombre),trim(p_telefono),trim(p_telefono),v_package.name,v_package.name,round(v_final)::integer,
    v_barbero,p_fecha,left(trim(p_hora),5),'pendiente',
    p_fecha::text||'_'||v_barbero||'_'||left(trim(p_hora),5),p_promotion_id,null,v_base,
    p_package_id,v_discount,v_group_id) returning id into v_reservation;
  for v_item in
    select i.position,s.id,s.name,s.price,s.duration_minutes
    from public.barber_service_package_items i join public.barber_services s on s.id=i.service_id
    where i.package_id=p_package_id order by i.position
  loop
    v_position:=v_position+1;
    if v_position=(select count(*) from public.barber_service_package_items where package_id=p_package_id) then
      v_net:=round(v_final,2)-v_allocated;
    else
      v_net:=round(v_final*v_item.price/nullif(v_base,0),2);v_allocated:=v_allocated+v_net;
    end if;
    insert into public.barber_reservation_items(reservation_id,package_id,service_id,position,
      service_name_snapshot,base_price,booked_net_price,duration_minutes)
    values(v_res,p_package_id,v_item.id,v_item.position,v_item.name,v_item.price,v_net,v_item.duration_minutes);
  end loop;
  if p_promotion_id is not null then
    update public.barber_promotions set uses_count=uses_count+1,updated_at=now()
      where id=p_promotion_id and status='approved' and (max_uses is null or uses_count<max_uses);
    if not found then raise exception 'La promoción alcanzó su límite de usos' using errcode='22023'; end if;
  end if;
  return v_res;
end;
$$;

-- Single atomic walk-in package checkout; payment split is computed against package price,
-- and service-level sale items preserve the actual allocation and cost snapshot.
create or replace function public.barber_admin_create_package_sale(
  p_token uuid,p_cliente text,p_package_id uuid,p_barbero_id integer,p_metodo text,
  p_recibido numeric,p_efectivo numeric,p_tarjeta numeric
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_package public.barber_service_packages; v_sale public.barber_sales; v_base numeric(12,2);
  v_total numeric(12,2); v_received numeric(12,2); v_cash numeric(12,2); v_card numeric(12,2);
  v_change numeric(12,2):=0; v_barbero text; v_items integer;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_metodo not in ('Efectivo','Transferencia','Tarjeta','Mixto') or p_barbero_id not in (1,2) then
    raise exception 'Método de pago o barbero inválido' using errcode='22023';
  end if;
  select * into v_package from public.barber_service_packages where id=p_package_id and is_active for share;
  if not found then raise exception 'Paquete no disponible' using errcode='22023'; end if;
  select count(*),coalesce(sum(s.price),0) into v_items,v_base
    from public.barber_service_package_items i join public.barber_services s on s.id=i.service_id and s.is_active
    where i.package_id=p_package_id;
  if v_items<2 or v_package.price>v_base then raise exception 'El paquete requiere dos servicios activos y un precio válido' using errcode='22023'; end if;
  v_total:=round(v_package.price,2);
  if p_metodo='Mixto' then
    if p_efectivo is null or p_tarjeta is null or p_efectivo<0 or p_tarjeta<0
       or round(p_efectivo+p_tarjeta,2)<>v_total then
      raise exception 'Pago mixto inválido: efectivo + tarjeta debe ser igual al total del paquete' using errcode='22023';
    end if;
    v_cash:=round(p_efectivo,2);v_card:=round(p_tarjeta,2);v_received:=v_total;
  else
    v_cash:=null;v_card:=null;v_received:=coalesce(p_recibido,v_total);
    if p_metodo='Efectivo' and v_received<v_total then raise exception 'Efectivo recibido insuficiente' using errcode='22023'; end if;
    if p_metodo<>'Efectivo' then v_received:=v_total; end if;
    if p_metodo='Efectivo' then v_change:=greatest(v_received-v_total,0); end if;
  end if;
  insert into public.barber_sales(cliente,servicio,barbero,total,metodo,recibido,cambio,
    subtotal,descuento,efectivo,tarjeta,package_id)
  values(coalesce(nullif(trim(p_cliente),''),'Cliente mostrador'),v_package.name,
    case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end,v_total,p_metodo,v_received,v_change,
    v_base,round(v_base-v_total,2),v_cash,v_card,p_package_id)
  returning * into v_sale;
  return jsonb_build_object('id',v_sale.id,'folio',v_sale.folio,'total',v_total,'subtotal',v_base,
    'descuento',round(v_base-v_total,2),'paquete',v_package.name,'metodo',p_metodo,
    'recibido',v_received,'cambio',v_change,'efectivo',v_cash,'tarjeta',v_card,'package_id',v_package.id);
end;
$$;

-- Enrich sales from package reservations at checkout; the original sale RPC remains in use.
create or replace function public.barber_sales_package_before_insert()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_res public.reservas; v_service public.barber_services;
begin
  if new.reserva_id is not null then
    select * into v_res from public.reservas where id=new.reserva_id;
    if found and v_res.package_id is not null then
      new.package_id:=v_res.package_id;
      new.subtotal:=coalesce(v_res.precio_base,v_res.precio);
      new.descuento:=greatest(round(new.subtotal-coalesce(v_res.precio,0),2),0);
      new.service_cost_snapshot:=null;
    end if;
  end if;
  if new.package_id is null then
    select * into v_service from public.barber_services where name=new.servicio limit 1;
    if found then new.service_cost_snapshot:=v_service.unit_cost; end if;
  end if;
  return new;
end;
$$;

create or replace function public.barber_sales_package_after_insert()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_res public.reservas; v_item record; v_count integer; v_pos integer:=0;
  v_base numeric(12,2); v_allocated numeric(12,2):=0; v_net numeric(12,2);
begin
  if new.package_id is null then return new; end if;
  if new.reserva_id is not null then
    select * into v_res from public.reservas where id=new.reserva_id;
    if found and exists(select 1 from public.barber_reservation_items where reservation_id=v_res.id) then
      for v_item in
        select ri.*,s.unit_cost from public.barber_reservation_items ri
        join public.barber_services s on s.id=ri.service_id
        where ri.reservation_id=v_res.id order by ri.position
      loop
        insert into public.barber_sale_items(sale_id,service_id,position,service_name_snapshot,
          catalog_price_snapshot,net_amount,discount_amount,unit_cost_snapshot)
        values(new.id,v_item.service_id,v_item.position,v_item.service_name_snapshot,
          v_item.base_price,v_item.booked_net_price,round(v_item.base_price-v_item.booked_net_price,2),v_item.unit_cost);
      end loop;
      return new;
    end if;
  end if;
  select count(*),coalesce(sum(s.price),0) into v_count,v_base
    from public.barber_service_package_items i join public.barber_services s on s.id=i.service_id
    where i.package_id=new.package_id;
  for v_item in
    select i.position,s.id,s.name,s.price,s.unit_cost
    from public.barber_service_package_items i join public.barber_services s on s.id=i.service_id
    where i.package_id=new.package_id order by i.position
  loop
    v_pos:=v_pos+1;
    if v_pos=v_count then v_net:=round(new.total,2)-v_allocated;
    else v_net:=round(new.total*v_item.price/nullif(v_base,0),2);v_allocated:=v_allocated+v_net; end if;
    insert into public.barber_sale_items(sale_id,service_id,position,service_name_snapshot,
      catalog_price_snapshot,net_amount,discount_amount,unit_cost_snapshot)
    values(new.id,v_item.id,v_item.position,v_item.name,v_item.price,v_net,
      round(v_item.price-v_net,2),v_item.unit_cost);
  end loop;
  return new;
end;
$$;

drop trigger if exists barber_sales_package_before_insert_trg on public.barber_sales;
create trigger barber_sales_package_before_insert_trg
before insert on public.barber_sales for each row execute function public.barber_sales_package_before_insert();
drop trigger if exists barber_sales_package_after_insert_trg on public.barber_sales;
create trigger barber_sales_package_after_insert_trg
after insert on public.barber_sales for each row execute function public.barber_sales_package_after_insert();

-- Suggested promotions use observed sale volumes first and recorded, sale-time costs when enough
-- snapshots exist. Data insufficiency is included in suggestion_evidence rather than fabricated.
create or replace function public.barber_promotions_generate_daily_suggestions_internal()
returns integer language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_cfg public.barber_promotion_suggestion_settings;
  v_service record; v_promo_id uuid; v_created integer:=0;
  v_today date; v_lock_key bigint:=hashtext('elegance-promotion-scheduler')::bigint;
begin
  perform pg_advisory_xact_lock(v_lock_key);
  select * into v_cfg from public.barber_promotion_suggestion_settings where id=1;
  if not found or not v_cfg.enabled then return 0; end if;
  v_today:=(now() at time zone 'America/Merida')::date;
  if exists(select 1 from public.barber_promotions p where p.source='daily_suggestion'
    and (p.created_at at time zone 'America/Merida')::date=v_today) then return 0; end if;
  for v_service in
    with sale_lines as (
      select svc.id service_id,s.id sale_id,round(s.total,2) net_amount,s.service_cost_snapshot cost_snapshot
      from public.barber_sales s join public.barber_services svc on svc.name=s.servicio
      where s.package_id is null and s.creado>=now()-make_interval(days=>v_cfg.lookback_days)
      union all
      select si.service_id,si.sale_id,si.net_amount,si.unit_cost_snapshot
      from public.barber_sale_items si join public.barber_sales s on s.id=si.sale_id
      where s.creado>=now()-make_interval(days=>v_cfg.lookback_days)
    ), agg as (
      select l.service_id,count(distinct l.sale_id) sales_count,
        coalesce(sum(l.net_amount),0)::numeric revenue,
        (avg(100*(l.net_amount-l.cost_snapshot)/nullif(l.net_amount,0))
          filter(where l.cost_snapshot is not null and l.net_amount>0))::numeric margin_pct,
        count(*) filter(where l.cost_snapshot is not null) margin_samples
      from sale_lines l group by l.service_id
    )
    select s.id,s.name,coalesce(a.sales_count,0) sales_count,a.margin_pct,
      coalesce(a.margin_samples,0) margin_samples,
      coalesce(a.revenue,0)::numeric revenue
    from public.barber_services s left join agg a on a.service_id=s.id
    where s.is_active and not exists(
      select 1 from public.barber_promotion_services ps join public.barber_promotions p on p.id=ps.promotion_id
      where ps.service_id=s.id and p.status='approved'
        and p.starts_at<now()+make_interval(hours=>v_cfg.opportunity_window_hours) and p.ends_at>now()
    )
    order by coalesce(a.sales_count,0) asc,
      case when a.margin_samples>=v_cfg.minimum_margin_sample and a.margin_pct>=v_cfg.minimum_margin_percent then 0 else 1 end,
      a.margin_pct desc nulls last,s.display_order,s.name
    limit v_cfg.max_suggestions_per_day
  loop
    insert into public.barber_promotions(title,description,status,discount_type,discount_value,
      starts_at,ends_at,weekdays,source,suggestion_evidence)
    values('Sugerencia diaria: '||v_service.name,
      case when v_service.sales_count>0 and v_service.margin_samples>=v_cfg.minimum_margin_sample
        then 'Propuesta basada en demanda observada y margen estimado; revisión del administrador obligatoria.'
        when v_service.sales_count>0 then 'Demanda histórica disponible; la muestra de margen/costo es insuficiente. Revisar manualmente.'
        else 'Sin historial suficiente. Sugerencia heurística de respaldo; no representa predicción de demanda o margen.'
      end,
      'pending_review','percent',v_cfg.discount_percent,now(),
      now()+make_interval(hours=>v_cfg.opportunity_window_hours),
      array[extract(dow from now() at time zone 'America/Merida')::smallint],
      'daily_suggestion',
      jsonb_build_object('basis',case when v_service.sales_count>0 and v_service.margin_samples>=v_cfg.minimum_margin_sample
        then 'history_demand_margin' when v_service.sales_count>0 then 'history_demand_only' else 'fallback_low_data' end,
        'lookback_days',v_cfg.lookback_days,'sales_count',v_service.sales_count,'revenue',v_service.revenue,
        'margin_samples',v_service.margin_samples,'estimated_margin_percent',v_service.margin_pct,
        'minimum_margin_percent',v_cfg.minimum_margin_percent,'required_margin_sample',v_cfg.minimum_margin_sample))
    returning id into v_promo_id;
    insert into public.barber_promotion_services(promotion_id,service_id) values(v_promo_id,v_service.id);
    v_created:=v_created+1;
  end loop;
  return v_created;
end;
$$;

create or replace function public.barber_promotions_generate_daily_suggestions(p_token uuid)
returns integer language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return public.barber_promotions_generate_daily_suggestions_internal();
end;
$$;

-- Safe privileges: only RPCs for package catalog/admin. Sale/reservation writes remain server validated.
revoke all on function public.barber_service_package_admin_list(uuid) from public;
revoke all on function public.barber_service_package_public() from public;
revoke all on function public.barber_service_package_admin_save(uuid,uuid,text,text,numeric,boolean,integer[]) from public;
revoke all on function public.barber_service_unit_cost_admin_save(uuid,integer,numeric) from public;
revoke all on function public.barber_service_unit_cost_admin_clear(uuid,integer) from public;
revoke all on function public.barber_promotion_history_settings_admin_get(uuid) from public;
revoke all on function public.barber_promotion_history_settings_admin_save(uuid,integer,numeric,integer) from public;
revoke all on function public.barber_promotions_suggestion_evidence_admin_list(uuid) from public;
revoke all on function public.barber_service_sales_history_admin_list(uuid,integer) from public;
revoke all on function public.barber_create_package_reservation(integer,date,text,text,text,uuid,uuid) from public;
revoke all on function public.barber_admin_create_package_sale(uuid,text,uuid,integer,text,numeric,numeric,numeric) from public;
revoke all on function public.barber_promotions_generate_daily_suggestions_internal() from public,anon,authenticated;
grant execute on function public.barber_service_package_admin_list(uuid) to anon,authenticated;
grant execute on function public.barber_service_package_public() to anon,authenticated;
grant execute on function public.barber_service_package_admin_save(uuid,uuid,text,text,numeric,boolean,integer[]) to anon,authenticated;
grant execute on function public.barber_service_unit_cost_admin_save(uuid,integer,numeric) to anon,authenticated;
grant execute on function public.barber_service_unit_cost_admin_clear(uuid,integer) to anon,authenticated;
grant execute on function public.barber_promotion_history_settings_admin_get(uuid) to anon,authenticated;
grant execute on function public.barber_promotion_history_settings_admin_save(uuid,integer,numeric,integer) to anon,authenticated;
grant execute on function public.barber_promotions_suggestion_evidence_admin_list(uuid) to anon,authenticated;
grant execute on function public.barber_service_sales_history_admin_list(uuid,integer) to anon,authenticated;
grant execute on function public.barber_create_package_reservation(integer,date,text,text,text,uuid,uuid) to anon,authenticated;
grant execute on function public.barber_admin_create_package_sale(uuid,text,uuid,integer,text,numeric,numeric,numeric) to anon,authenticated;
grant execute on function public.barber_promotions_generate_daily_suggestions_internal() to service_role;
