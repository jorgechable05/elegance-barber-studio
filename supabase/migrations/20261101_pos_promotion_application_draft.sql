-- POS promotion application, receipt breakdown and reservation-price history.
-- Draft only: validate on isolated PostgreSQL and a non-production Supabase project first.
-- Historical reservations are not repriced. Existing rows keep NULL base price/service ID.

alter table public.reservas
  add column if not exists servicio_id integer references public.barber_services(id) on delete set null,
  add column if not exists precio_base numeric(10,2);

alter table public.barber_sales
  add column if not exists promotion_id uuid references public.barber_promotions(id) on delete set null,
  add column if not exists subtotal numeric(12,2),
  add column if not exists descuento numeric(12,2);

do $constraints$
begin
  if not exists(select 1 from pg_constraint where conname='barber_sales_subtotal_discount_pair_ck') then
    alter table public.barber_sales add constraint barber_sales_subtotal_discount_pair_ck
      check ((subtotal is null) = (descuento is null));
  end if;
  if not exists(select 1 from pg_constraint where conname='barber_sales_discount_total_ck') then
    alter table public.barber_sales add constraint barber_sales_discount_total_ck
      check (subtotal is null or (
        subtotal >= 0 and descuento >= 0 and descuento <= subtotal
        and round(subtotal-descuento,2)=round(total,2)
      ));
  end if;
end
$constraints$;

-- Preserve legacy reservation identifiers and persist the base price at booking time.
create or replace function public.barber_create_reservation_with_promotion(
  p_barbero_id integer,
  p_fecha date,
  p_hora text,
  p_nombre text,
  p_notas text,
  p_servicio_id integer,
  p_telefono text,
  p_promotion_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_barbero text;
  v_servicio text;
  v_base_price numeric(10,2);
  v_final_price integer;
  v_uses_count integer;
  v_promo public.barber_promotions;
  v_start_at timestamptz;
  v_weekday smallint;
  v_time time;
begin
  if p_barbero_id = 1 then v_barbero := 'EdgarMay';
  elsif p_barbero_id = 2 then v_barbero := 'Staff 2';
  else raise exception 'Barbero no válido'; end if;

  select s.name, s.price
    into v_servicio, v_base_price
    from public.barber_services s
   where s.id = p_servicio_id and s.is_active;
  if v_servicio is null then raise exception 'Servicio no válido o inactivo'; end if;

  if p_fecha is null or p_fecha < current_date then raise exception 'La fecha ya pasó'; end if;
  if extract(isodow from p_fecha) = 7 then raise exception 'Domingo cerrado'; end if;
  if nullif(trim(p_hora),'') is null then raise exception 'Horario no válido'; end if;
  begin
    v_time := left(trim(p_hora),5)::time;
  exception when others then
    raise exception 'Horario no válido';
  end;
  v_start_at := (p_fecha::text || ' ' || v_time::text || ' America/Merida')::timestamptz;
  v_weekday := extract(dow from p_fecha)::smallint;

  if exists (
    select 1 from public.reservas r
     where r.fecha=p_fecha and r.hora=left(trim(p_hora),5) and r.barbero=v_barbero
       and lower(coalesce(r.estado,'pendiente')) not in ('rechazada','cancelada','atendida')
  ) then raise exception 'Ese horario ya fue reservado'; end if;

  -- Legacy reservas.precio is INTEGER: the booking price contract is whole MXN pesos.
  -- The customer utility uses the same PostgreSQL-compatible rounding rule.
  v_final_price := round(v_base_price)::integer;
  if p_promotion_id is not null then
    select p.* into v_promo
      from public.barber_promotions p
      join public.barber_promotion_services ps on ps.promotion_id=p.id
     where p.id=p_promotion_id
       and ps.service_id=p_servicio_id
       and p.status='approved'
       and v_start_at >= p.starts_at and v_start_at < p.ends_at
       and (p.max_uses is null or p.uses_count < p.max_uses)
       and (cardinality(p.weekdays)=0 or v_weekday=any(p.weekdays))
       and (p.start_time is null or v_time >= p.start_time)
       and (p.end_time is null or v_time < p.end_time)
     for update of p;
    if not found then raise exception 'La promoción ya no está disponible para esa cita'; end if;
    if v_promo.discount_type='percent' then
      if v_promo.discount_value <= 0 or v_promo.discount_value > 100 then raise exception 'Descuento no válido'; end if;
      v_final_price := round(v_base_price * (1 - v_promo.discount_value / 100))::integer;
    elsif v_promo.discount_type='fixed_price' then
      if v_promo.discount_value < 0 or v_promo.discount_value > v_base_price then raise exception 'Precio especial no válido'; end if;
      v_final_price := round(v_promo.discount_value)::integer;
    else raise exception 'Tipo de promoción no válido'; end if;
  end if;

  insert into public.reservas(
    nombre,telefono,wa,serv,servicio,precio,barbero,fecha,hora,estado,stock_key,promotion_id,servicio_id,precio_base
  ) values (
    trim(p_nombre),trim(p_telefono),trim(p_telefono),v_servicio,v_servicio,v_final_price,
    v_barbero,p_fecha,left(trim(p_hora),5),'pendiente',
    p_fecha::text || '_' || v_barbero || '_' || left(trim(p_hora),5),p_promotion_id,
    p_servicio_id,v_base_price
  ) returning id into v_id;

  if p_promotion_id is not null then
    -- Keep the row lock held above and re-check the limit in the UPDATE as a
    -- second guard. If a competing transaction has consumed the last use, the
    -- reservation insert and counter update are rolled back together.
    update public.barber_promotions
       set uses_count=uses_count+1, updated_at=now()
     where id=p_promotion_id
       and status='approved'
       and (max_uses is null or uses_count < max_uses)
     returning uses_count into v_uses_count;
    if not found then
      raise exception 'La promoción ya alcanzó su límite de usos';
    end if;
  end if;
  return v_id;
end;
$$;

revoke all on function public.barber_create_reservation_with_promotion(integer,date,text,text,text,integer,text,uuid) from public;
grant execute on function public.barber_create_reservation_with_promotion(integer,date,text,text,text,integer,text,uuid) to anon, authenticated;


create or replace function public.barber_admin_reservations_with_promotions(p_token uuid)
returns table(
  id uuid, nombre text, telefono text, servicio text, serv text, servicio_id integer,
  precio integer, precio_base numeric, promotion_id uuid, promotion_title text,
  barbero text, fecha date, hora text, estado text
)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query
  select r.id,r.nombre,r.telefono,r.servicio,r.serv,r.servicio_id,r.precio,
         coalesce(r.precio_base,r.precio)::numeric,r.promotion_id,p.title,
         r.barbero,r.fecha,r.hora,r.estado
  from public.reservas r
  left join public.barber_promotions p on p.id=r.promotion_id
  where r.fecha=(now() at time zone 'America/Merida')::date
  order by r.hora,r.barbero,r.nombre;
end;
$$;

revoke all on function public.barber_admin_reservations_with_promotions(uuid) from public;
grant execute on function public.barber_admin_reservations_with_promotions(uuid) to anon,authenticated;

-- For booked appointments, the booking-time promotion and base price are immutable history.
-- The legacy sale RPC still owns the existing sale/duplicate/session checks; this wrapper adds
-- only the attributable subtotal/discount metadata in the same transaction.
create or replace function public.barber_admin_create_sale_with_promotion_info(
  p_token uuid,p_reserva_id uuid,p_metodo text,p_recibido numeric
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_res public.reservas;
  v_result jsonb;
  v_sale_id bigint;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2);
  v_promo_title text;
begin
  if p_metodo='Mixto' then raise exception 'Usa el contrato de pago mixto' using errcode='22023'; end if;
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_res from public.reservas r where r.id=p_reserva_id for update;
  if not found then raise exception 'Reserva no encontrada' using errcode='P0002'; end if;

  v_result:=public.barber_admin_create_sale(p_token,p_reserva_id,p_metodo,p_recibido);
  v_sale_id:=(v_result->>'id')::bigint;
  v_subtotal:=coalesce(v_res.precio_base,v_res.precio)::numeric;
  v_discount:=greatest(round(v_subtotal-coalesce(v_res.precio,0),2),0);
  select p.title into v_promo_title from public.barber_promotions p where p.id=v_res.promotion_id;
  update public.barber_sales
    set promotion_id=v_res.promotion_id,subtotal=v_subtotal,descuento=v_discount
    where id=v_sale_id;
  return v_result || jsonb_build_object(
    'promotion_id',v_res.promotion_id,'promotion_title',v_promo_title,
    'subtotal',v_subtotal,'descuento',v_discount
  );
end;
$$;

revoke all on function public.barber_admin_create_sale_with_promotion_info(uuid,uuid,text,numeric) from public;
grant execute on function public.barber_admin_create_sale_with_promotion_info(uuid,uuid,text,numeric) to anon,authenticated;

-- Mixed-payment appointment wrapper adds the same booking-time metadata to the already
-- validated cash/card split contract without changing the legacy 4-argument sale RPC.
create or replace function public.barber_admin_create_sale_with_promotion_info_mixed(
  p_token uuid,p_reserva_id uuid,p_metodo text,p_recibido numeric,p_efectivo numeric,p_tarjeta numeric
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_res public.reservas;
  v_result jsonb;
  v_sale_id bigint;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2);
  v_promo_title text;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_res from public.reservas r where r.id=p_reserva_id for update;
  if not found then raise exception 'Reserva no encontrada' using errcode='P0002'; end if;
  v_result:=public.barber_admin_create_sale(p_token,p_reserva_id,p_metodo,p_recibido,p_efectivo,p_tarjeta);
  v_sale_id:=(v_result->>'id')::bigint;
  v_subtotal:=coalesce(v_res.precio_base,v_res.precio)::numeric;
  v_discount:=greatest(round(v_subtotal-coalesce(v_res.precio,0),2),0);
  select p.title into v_promo_title from public.barber_promotions p where p.id=v_res.promotion_id;
  update public.barber_sales
    set promotion_id=v_res.promotion_id,subtotal=v_subtotal,descuento=v_discount
    where id=v_sale_id;
  return v_result || jsonb_build_object(
    'promotion_id',v_res.promotion_id,'promotion_title',v_promo_title,
    'subtotal',v_subtotal,'descuento',v_discount
  );
end;
$$;

revoke all on function public.barber_admin_create_sale_with_promotion_info_mixed(uuid,uuid,text,numeric,numeric,numeric) from public;
grant execute on function public.barber_admin_create_sale_with_promotion_info_mixed(uuid,uuid,text,numeric,numeric,numeric) to anon,authenticated;

-- Walk-in sale with server-validated promotion and exact payment split.
create or replace function public.barber_admin_create_walkin_sale_with_promotion(
  p_token uuid,p_cliente text,p_servicio_id integer,p_barbero_id integer,p_metodo text,
  p_recibido numeric,p_efectivo numeric,p_tarjeta numeric,p_promotion_id uuid default null
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_service public.barber_services;
  v_promo public.barber_promotions;
  v_now_local timestamp without time zone;
  v_weekday smallint;
  v_time time;
  v_barber text;
  v_subtotal numeric(12,2);
  v_total numeric(12,2);
  v_discount numeric(12,2):=0;
  v_cash numeric(12,2);
  v_card numeric(12,2);
  v_received numeric(12,2);
  v_change numeric(12,2):=0;
  v_sale public.barber_sales;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_metodo not in ('Efectivo','Transferencia','Tarjeta','Mixto') then
    raise exception 'Método de pago inválido' using errcode='22023';
  end if;
  select * into v_service from public.barber_services
    where id=p_servicio_id and is_active for share;
  if not found or p_barbero_id not in (1,2) then
    raise exception 'Servicio o barbero inválido' using errcode='22023';
  end if;
  v_barber:=case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end;
  v_subtotal:=round(v_service.price,2);
  v_total:=v_subtotal;

  if p_promotion_id is not null then
    v_now_local:=now() at time zone 'America/Merida';
    v_weekday:=extract(dow from v_now_local)::smallint;
    v_time:=v_now_local::time;
    select p.* into v_promo
      from public.barber_promotions p
      join public.barber_promotion_services ps on ps.promotion_id=p.id
     where p.id=p_promotion_id and ps.service_id=p_servicio_id
       and p.status='approved'
       and p.starts_at<=now() and now()<p.ends_at
       and (cardinality(p.weekdays)=0 or v_weekday=any(p.weekdays))
       and (p.start_time is null or v_time>=p.start_time)
       and (p.end_time is null or v_time<p.end_time)
       and (p.max_uses is null or p.uses_count<p.max_uses)
     for update of p;
    if not found then raise exception 'La promoción no está vigente para este servicio en este momento' using errcode='22023'; end if;
    if v_promo.discount_type='percent' then
      if v_promo.discount_value<=0 or v_promo.discount_value>100 then
        raise exception 'Porcentaje de descuento no válido' using errcode='22023';
      end if;
      v_total:=round(v_subtotal*(1-v_promo.discount_value/100),2);
    elsif v_promo.discount_type='fixed_price' then
      if v_promo.discount_value<0 or v_promo.discount_value>v_subtotal then
        raise exception 'Precio especial no válido' using errcode='22023';
      end if;
      v_total:=round(v_promo.discount_value,2);
    else
      raise exception 'Tipo de promoción no admitido por esta venta' using errcode='22023';
    end if;
    v_discount:=round(v_subtotal-v_total,2);
  end if;

  if p_metodo='Mixto' then
    if p_efectivo is null or p_tarjeta is null or p_efectivo<0 or p_tarjeta<0
       or round(p_efectivo+p_tarjeta,2)<>v_total then
      raise exception 'Pago mixto inválido: efectivo + tarjeta debe igualar el total' using errcode='22023';
    end if;
    v_cash:=round(p_efectivo,2); v_card:=round(p_tarjeta,2);
    v_received:=v_total;
  else
    v_cash:=null; v_card:=null;
    v_received:=coalesce(p_recibido,v_total);
    if p_metodo='Efectivo' and v_received<v_total then
      raise exception 'El efectivo recibido es insuficiente' using errcode='22023';
    end if;
    if p_metodo<>'Efectivo' then v_received:=v_total; end if;
    if p_metodo='Efectivo' then v_change:=greatest(v_received-v_total,0); end if;
  end if;

  insert into public.barber_sales(
    cliente,servicio,barbero,total,metodo,recibido,cambio,
    promotion_id,subtotal,descuento,efectivo,tarjeta
  ) values (
    coalesce(nullif(trim(p_cliente),''),'Cliente mostrador'),v_service.name,v_barber,
    v_total,p_metodo,v_received,v_change,p_promotion_id,v_subtotal,v_discount,v_cash,v_card
  ) returning * into v_sale;

  if p_promotion_id is not null then
    update public.barber_promotions
      set uses_count=uses_count+1,updated_at=now()
      where id=p_promotion_id and status='approved'
        and (max_uses is null or uses_count<max_uses);
    if not found then raise exception 'La promoción alcanzó su límite de usos' using errcode='22023'; end if;
  end if;

  return jsonb_build_object(
    'id',v_sale.id,'folio',v_sale.folio,'total',v_total,'cliente',v_sale.cliente,
    'servicio',v_service.name,'barbero',v_barber,'metodo',p_metodo,
    'recibido',v_received,'cambio',v_change,'promotion_id',p_promotion_id,
    'promotion_title',case when p_promotion_id is null then null else v_promo.title end,
    'subtotal',v_subtotal,'descuento',v_discount,
    'efectivo',v_cash,'tarjeta',v_card
  );
end;
$$;

revoke all on function public.barber_admin_create_walkin_sale_with_promotion(uuid,text,integer,integer,text,numeric,numeric,numeric,uuid) from public;
grant execute on function public.barber_admin_create_walkin_sale_with_promotion(uuid,text,integer,integer,text,numeric,numeric,numeric,uuid) to anon,authenticated;



-- Return today's reservation rows with booking-time promotion details to the POS.
-- The existing public Client reservation layout is not modified by this RPC.

-- Wrappers preserve existing sale RPC behavior while persisting booking-time discount attribution.
create or replace function public.barber_admin_create_sale_with_promotion_info(
  p_token uuid,p_reserva_id uuid,p_metodo text,p_recibido numeric
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_res public.reservas; v_result jsonb; v_sale_id bigint;
  v_subtotal numeric(12,2); v_discount numeric(12,2); v_promo_title text;
begin
  if p_metodo='Mixto' then raise exception 'Usa el contrato de pago mixto' using errcode='22023'; end if;
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_res from public.reservas r where r.id=p_reserva_id for update;
  if not found then raise exception 'Reserva no encontrada' using errcode='P0002'; end if;
  v_result:=public.barber_admin_create_sale(p_token,p_reserva_id,p_metodo,p_recibido);
  v_sale_id:=(v_result->>'id')::bigint;
  v_subtotal:=coalesce(v_res.precio_base,v_res.precio)::numeric;
  v_discount:=greatest(round(v_subtotal-coalesce(v_res.precio,0),2),0);
  select p.title into v_promo_title from public.barber_promotions p where p.id=v_res.promotion_id;
  update public.barber_sales set promotion_id=v_res.promotion_id,subtotal=v_subtotal,descuento=v_discount
    where id=v_sale_id;
  return v_result||jsonb_build_object('promotion_id',v_res.promotion_id,'promotion_title',v_promo_title,
    'subtotal',v_subtotal,'descuento',v_discount);
end;
$$;
revoke all on function public.barber_admin_create_sale_with_promotion_info(uuid,uuid,text,numeric) from public;
grant execute on function public.barber_admin_create_sale_with_promotion_info(uuid,uuid,text,numeric) to anon,authenticated;

create or replace function public.barber_admin_create_sale_with_promotion_info_mixed(
  p_token uuid,p_reserva_id uuid,p_metodo text,p_recibido numeric,p_efectivo numeric,p_tarjeta numeric
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_res public.reservas; v_result jsonb; v_sale_id bigint;
  v_subtotal numeric(12,2); v_discount numeric(12,2); v_promo_title text;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_res from public.reservas r where r.id=p_reserva_id for update;
  if not found then raise exception 'Reserva no encontrada' using errcode='P0002'; end if;
  v_result:=public.barber_admin_create_sale(p_token,p_reserva_id,p_metodo,p_recibido,p_efectivo,p_tarjeta);
  v_sale_id:=(v_result->>'id')::bigint;
  v_subtotal:=coalesce(v_res.precio_base,v_res.precio)::numeric;
  v_discount:=greatest(round(v_subtotal-coalesce(v_res.precio,0),2),0);
  select p.title into v_promo_title from public.barber_promotions p where p.id=v_res.promotion_id;
  update public.barber_sales set promotion_id=v_res.promotion_id,subtotal=v_subtotal,descuento=v_discount
    where id=v_sale_id;
  return v_result||jsonb_build_object('promotion_id',v_res.promotion_id,'promotion_title',v_promo_title,
    'subtotal',v_subtotal,'descuento',v_discount);
end;
$$;
revoke all on function public.barber_admin_create_sale_with_promotion_info_mixed(uuid,uuid,text,numeric,numeric,numeric) from public;
grant execute on function public.barber_admin_create_sale_with_promotion_info_mixed(uuid,uuid,text,numeric,numeric,numeric) to anon,authenticated;

-- Walk-in sales apply an optional currently-valid promotion in one server transaction.
create or replace function public.barber_admin_create_walkin_sale_with_promotion(
  p_token uuid,p_cliente text,p_servicio_id integer,p_barbero_id integer,p_metodo text,
  p_recibido numeric,p_efectivo numeric,p_tarjeta numeric,p_promotion_id uuid default null
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_service public.barber_services; v_promo public.barber_promotions;
  v_local timestamp without time zone; v_weekday smallint; v_time time; v_barber text;
  v_subtotal numeric(12,2); v_total numeric(12,2); v_discount numeric(12,2):=0;
  v_cash numeric(12,2); v_card numeric(12,2); v_received numeric(12,2);
  v_change numeric(12,2):=0; v_sale public.barber_sales;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_metodo not in ('Efectivo','Transferencia','Tarjeta','Mixto') then
    raise exception 'Método de pago inválido' using errcode='22023';
  end if;
  select * into v_service from public.barber_services where id=p_servicio_id and is_active for share;
  if not found or p_barbero_id not in (1,2) then raise exception 'Servicio o barbero inválido' using errcode='22023'; end if;
  v_barber:=case when p_barbero_id=1 then 'EdgarMay' else 'Staff 2' end;
  v_subtotal:=round(v_service.price,2); v_total:=v_subtotal;

  if p_promotion_id is not null then
    v_local:=now() at time zone 'America/Merida';
    v_weekday:=extract(dow from v_local)::smallint; v_time:=v_local::time;
    select p.* into v_promo
      from public.barber_promotions p
      join public.barber_promotion_services ps on ps.promotion_id=p.id
     where p.id=p_promotion_id and ps.service_id=p_servicio_id and p.status='approved'
       and p.starts_at<=now() and now()<p.ends_at
       and (cardinality(p.weekdays)=0 or v_weekday=any(p.weekdays))
       and (p.start_time is null or v_time>=p.start_time)
       and (p.end_time is null or v_time<p.end_time)
       and (p.max_uses is null or p.uses_count<p.max_uses)
     for update of p;
    if not found then raise exception 'La promoción no está vigente para este servicio en este momento' using errcode='22023'; end if;
    if v_promo.discount_type='percent' then
      if v_promo.discount_value<=0 or v_promo.discount_value>100 then raise exception 'Porcentaje no válido' using errcode='22023'; end if;
      v_total:=round(v_subtotal*(1-v_promo.discount_value/100),2);
    elsif v_promo.discount_type='fixed_price' then
      if v_promo.discount_value<0 or v_promo.discount_value>v_subtotal then raise exception 'Precio especial no válido' using errcode='22023'; end if;
      v_total:=round(v_promo.discount_value,2);
    else raise exception 'Tipo de promoción no admitido por esta venta' using errcode='22023'; end if;
    v_discount:=round(v_subtotal-v_total,2);
  end if;

  if p_metodo='Mixto' then
    if p_efectivo is null or p_tarjeta is null or p_efectivo<0 or p_tarjeta<0 or round(p_efectivo+p_tarjeta,2)<>v_total then
      raise exception 'Pago mixto inválido: efectivo + tarjeta debe igualar el total' using errcode='22023';
    end if;
    v_cash:=round(p_efectivo,2); v_card:=round(p_tarjeta,2); v_received:=v_total;
  else
    v_cash:=null; v_card:=null; v_received:=coalesce(p_recibido,v_total);
    if p_metodo='Efectivo' and v_received<v_total then raise exception 'El efectivo recibido es insuficiente' using errcode='22023'; end if;
    if p_metodo<>'Efectivo' then v_received:=v_total; end if;
    if p_metodo='Efectivo' then v_change:=greatest(v_received-v_total,0); end if;
  end if;

  insert into public.barber_sales(
    cliente,servicio,barbero,total,metodo,recibido,cambio,
    promotion_id,subtotal,descuento,efectivo,tarjeta
  ) values(
    coalesce(nullif(trim(p_cliente),''),'Cliente mostrador'),v_service.name,v_barber,
    v_total,p_metodo,v_received,v_change,p_promotion_id,v_subtotal,v_discount,v_cash,v_card
  ) returning * into v_sale;

  if p_promotion_id is not null then
    update public.barber_promotions set uses_count=uses_count+1,updated_at=now()
     where id=p_promotion_id and status='approved' and (max_uses is null or uses_count<max_uses);
    if not found then raise exception 'La promoción alcanzó su límite de usos' using errcode='22023'; end if;
  end if;

  return jsonb_build_object(
    'id',v_sale.id,'folio',v_sale.folio,'total',v_total,'cliente',v_sale.cliente,
    'servicio',v_service.name,'barbero',v_barber,'metodo',p_metodo,'recibido',v_received,'cambio',v_change,
    'promotion_id',p_promotion_id,'promotion_title',case when p_promotion_id is null then null else v_promo.title end,
    'subtotal',v_subtotal,'descuento',v_discount,'efectivo',v_cash,'tarjeta',v_card
  );
end;
$$;
revoke all on function public.barber_admin_create_walkin_sale_with_promotion(uuid,text,integer,integer,text,numeric,numeric,numeric,uuid) from public;
grant execute on function public.barber_admin_create_walkin_sale_with_promotion(uuid,text,integer,integer,text,numeric,numeric,numeric,uuid) to anon,authenticated;
