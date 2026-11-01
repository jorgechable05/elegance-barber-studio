-- Additive draft: promotion lifecycle, truthful booking metrics, and configurable suggestions.
-- Apply only in isolated/non-production Supabase after review. Never apply to production directly.

create table if not exists public.barber_promotion_suggestion_settings (
  id smallint primary key default 1 check (id = 1),
  enabled boolean not null default true,
  discount_percent numeric(5,2) not null default 10
    check (discount_percent > 0 and discount_percent <= 90),
  max_suggestions_per_day integer not null default 3
    check (max_suggestions_per_day between 1 and 10),
  opportunity_window_hours integer not null default 24
    check (opportunity_window_hours between 1 and 168),
  updated_at timestamptz not null default now()
);
insert into public.barber_promotion_suggestion_settings(id) values (1)
on conflict (id) do nothing;
alter table public.barber_promotion_suggestion_settings enable row level security;
revoke all on public.barber_promotion_suggestion_settings from public, anon, authenticated;
grant select, insert, update on public.barber_promotion_suggestion_settings to service_role;

create or replace function public.barber_promotion_suggestion_settings_admin_get(p_token uuid)
returns table(enabled boolean, discount_percent numeric, max_suggestions_per_day integer,
              opportunity_window_hours integer, updated_at timestamptz)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query select c.enabled,c.discount_percent,c.max_suggestions_per_day,
                      c.opportunity_window_hours,c.updated_at
    from public.barber_promotion_suggestion_settings c where c.id=1;
end;
$$;

create or replace function public.barber_promotion_suggestion_settings_admin_save(
  p_token uuid, p_enabled boolean, p_discount_percent numeric,
  p_max_suggestions_per_day integer, p_opportunity_window_hours integer
)
returns public.barber_promotion_suggestion_settings
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_promotion_suggestion_settings;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_enabled is null or p_discount_percent is null
     or p_discount_percent<=0 or p_discount_percent>90
     or p_max_suggestions_per_day not between 1 and 10
     or p_opportunity_window_hours not between 1 and 168 then
    raise exception 'Configuración diaria inválida. Descuento entre 0 y 90 por ciento, sugerencias 1-10 y ventana 1-168 horas.' using errcode='22023';
  end if;
  update public.barber_promotion_suggestion_settings
     set enabled=p_enabled, discount_percent=p_discount_percent,
         max_suggestions_per_day=p_max_suggestions_per_day,
         opportunity_window_hours=p_opportunity_window_hours, updated_at=now()
   where id=1 returning * into v_row;
  return v_row;
end;
$$;

-- Duplicate an offer into an unpublished draft, preserving its service selection and schedule.
create or replace function public.barber_promotion_admin_duplicate(p_token uuid, p_id uuid)
returns public.barber_promotions
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_source public.barber_promotions; v_copy public.barber_promotions;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_source from public.barber_promotions where id=p_id for share;
  if not found then raise exception 'Promoción no encontrada' using errcode='P0002'; end if;
  insert into public.barber_promotions(
    title,description,status,discount_type,discount_value,starts_at,ends_at,
    weekdays,start_time,end_time,source,max_uses,uses_count,approved_at
  ) values (
    left(v_source.title || ' (copia)',200),v_source.description,'draft',
    v_source.discount_type,v_source.discount_value,v_source.starts_at,v_source.ends_at,
    v_source.weekdays,v_source.start_time,v_source.end_time,'manual',v_source.max_uses,0,null
  ) returning * into v_copy;
  insert into public.barber_promotion_services(promotion_id,service_id)
    select v_copy.id,service_id from public.barber_promotion_services where promotion_id=v_source.id;
  return v_copy;
end;
$$;

-- Hard delete only unused/unreferenced promotions. Offers with history are retained for audit.
create or replace function public.barber_promotion_admin_delete(p_token uuid, p_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_promo public.barber_promotions;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  select * into v_promo from public.barber_promotions where id=p_id for update;
  if not found then raise exception 'Promoción no encontrada' using errcode='P0002'; end if;
  if v_promo.uses_count>0 or exists(select 1 from public.reservas r where r.promotion_id=p_id) then
    raise exception 'Esta promoción tiene historial; paúsala para conservar la auditoría' using errcode='55000';
  end if;
  delete from public.barber_promotions where id=p_id;
  return true;
end;
$$;

-- Validate promotion state transitions on the server, including the final approval decision.
create or replace function public.barber_promotion_admin_review(p_token uuid, p_id uuid, p_decision text)
returns public.barber_promotions
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_row public.barber_promotions;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if p_decision not in ('approved','rejected','paused','pending_review','draft') then
    raise exception 'Decisión no válida' using errcode='22023';
  end if;
  select * into v_row from public.barber_promotions where id=p_id for update;
  if not found then raise exception 'Promoción no encontrada' using errcode='P0002'; end if;

  if p_decision='approved' then
    if v_row.ends_at<=now() then
      raise exception 'No se puede aprobar una promoción vencida' using errcode='22023';
    end if;
    if v_row.starts_at is null or v_row.ends_at<=v_row.starts_at then
      raise exception 'La vigencia de la promoción no es válida' using errcode='22023';
    end if;
    if not exists(select 1 from public.barber_promotion_services ps where ps.promotion_id=p_id) then
      raise exception 'Selecciona al menos un servicio antes de aprobar' using errcode='22023';
    end if;
    if v_row.discount_type='percent' and (v_row.discount_value<=0 or v_row.discount_value>100) then
      raise exception 'El porcentaje de descuento no es válido' using errcode='22023';
    end if;
    if v_row.discount_type='fixed_price' and exists (
      select 1 from public.barber_promotion_services ps
      join public.barber_services s on s.id=ps.service_id
      where ps.promotion_id=p_id and v_row.discount_value>s.price
    ) then
      raise exception 'El precio especial supera el precio normal de un servicio incluido' using errcode='22023';
    end if;
  end if;

  update public.barber_promotions
     set status=p_decision,
         approved_at=case when p_decision='approved' then now() else null end,
         updated_at=now()
   where id=p_id returning * into v_row;
  return v_row;
end;
$$;

-- Truthful metrics from reservation records only. This schema cannot yet attribute completed sales
-- or calculate discount savings because sales do not carry promotion_id/base price.
create or replace function public.barber_promotions_admin_metrics(p_token uuid)
returns table(
  id uuid, title text, status text, usage_counter integer,
  reservation_count bigint, booked_revenue numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query
    select p.id,p.title,p.status,p.uses_count,count(r.id),
           coalesce(sum(r.precio),0)::numeric
      from public.barber_promotions p
      left join public.reservas r on r.promotion_id=p.id
     group by p.id
     order by count(r.id) desc,p.created_at desc;
end;
$$;

-- Both manual and scheduled suggestion generation consume the same admin-configurable rules.
-- Suggestions are pending_review only; this heuristic does not claim to model demand or margins
-- because no reliable demand/cost/margin source exists in the current schema.
create or replace function public.barber_promotions_generate_daily_suggestions(p_token uuid)
returns integer
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_cfg public.barber_promotion_suggestion_settings;
  v_service record; v_promo_id uuid; v_created integer:=0;
  v_today date; v_lock_key bigint:=hashtext('elegance-promotion-scheduler')::bigint;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  perform pg_advisory_xact_lock(v_lock_key);
  select * into v_cfg from public.barber_promotion_suggestion_settings where id=1;
  if not found or not v_cfg.enabled then return 0; end if;
  v_today := (now() at time zone 'America/Merida')::date;
  if exists (
    select 1 from public.barber_promotions p
    where p.source='daily_suggestion'
      and (p.created_at at time zone 'America/Merida')::date=v_today
  ) then return 0; end if;

  for v_service in
    select s.id,s.name from public.barber_services s
    where s.is_active
      and not exists (
        select 1 from public.barber_promotion_services ps
        join public.barber_promotions p on p.id=ps.promotion_id
        where ps.service_id=s.id and p.status='approved'
          and p.starts_at<now()+make_interval(hours=>v_cfg.opportunity_window_hours)
          and p.ends_at>now()
      )
    order by s.display_order,s.name
    limit v_cfg.max_suggestions_per_day
  loop
    insert into public.barber_promotions(
      title,description,status,discount_type,discount_value,starts_at,ends_at,
      weekdays,source
    ) values (
      'Sugerencia diaria: '||v_service.name,
      'Propuesta heurística del '||v_cfg.discount_percent||'%. Revisar y ajustar antes de aprobar.',
      'pending_review','percent',v_cfg.discount_percent,now(),
      now()+make_interval(hours=>v_cfg.opportunity_window_hours),
      array[extract(dow from now() at time zone 'America/Merida')::smallint],
      'daily_suggestion'
    ) returning id into v_promo_id;
    insert into public.barber_promotion_services(promotion_id,service_id)
      values(v_promo_id,v_service.id);
    v_created:=v_created+1;
  end loop;
  return v_created;
end;
$$;

create or replace function public.barber_promotions_generate_daily_suggestions_internal()
returns integer
language plpgsql security definer
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
  v_today := (now() at time zone 'America/Merida')::date;
  if exists (
    select 1 from public.barber_promotions p
    where p.source='daily_suggestion'
      and (p.created_at at time zone 'America/Merida')::date=v_today
  ) then return 0; end if;

  for v_service in
    select s.id,s.name from public.barber_services s
    where s.is_active
      and not exists (
        select 1 from public.barber_promotion_services ps
        join public.barber_promotions p on p.id=ps.promotion_id
        where ps.service_id=s.id and p.status='approved'
          and p.starts_at<now()+make_interval(hours=>v_cfg.opportunity_window_hours)
          and p.ends_at>now()
      )
    order by s.display_order,s.name
    limit v_cfg.max_suggestions_per_day
  loop
    insert into public.barber_promotions(
      title,description,status,discount_type,discount_value,starts_at,ends_at,
      weekdays,source
    ) values (
      'Sugerencia diaria: '||v_service.name,
      'Propuesta heurística del '||v_cfg.discount_percent||'%. Revisar y ajustar antes de aprobar.',
      'pending_review','percent',v_cfg.discount_percent,now(),
      now()+make_interval(hours=>v_cfg.opportunity_window_hours),
      array[extract(dow from now() at time zone 'America/Merida')::smallint],
      'daily_suggestion'
    ) returning id into v_promo_id;
    insert into public.barber_promotion_services(promotion_id,service_id)
      values(v_promo_id,v_service.id);
    v_created:=v_created+1;
  end loop;
  return v_created;
end;
$$;

revoke all on function public.barber_promotion_suggestion_settings_admin_get(uuid) from public;
revoke all on function public.barber_promotion_suggestion_settings_admin_save(uuid,boolean,numeric,integer,integer) from public;
revoke all on function public.barber_promotion_admin_duplicate(uuid,uuid) from public;
revoke all on function public.barber_promotion_admin_delete(uuid,uuid) from public;
revoke all on function public.barber_promotions_admin_metrics(uuid) from public;
revoke all on function public.barber_promotions_generate_daily_suggestions_internal() from public,anon,authenticated;
grant execute on function public.barber_promotion_suggestion_settings_admin_get(uuid) to anon,authenticated;
grant execute on function public.barber_promotion_suggestion_settings_admin_save(uuid,boolean,numeric,integer,integer) to anon,authenticated;
grant execute on function public.barber_promotion_admin_duplicate(uuid,uuid) to anon,authenticated;
grant execute on function public.barber_promotion_admin_delete(uuid,uuid) to anon,authenticated;
grant execute on function public.barber_promotions_admin_metrics(uuid) to anon,authenticated;
grant execute on function public.barber_promotions_generate_daily_suggestions(uuid) to anon,authenticated;
grant execute on function public.barber_promotions_generate_daily_suggestions_internal() to service_role;

-- Replace the existing job without creating duplicates, and fail if pg_cron is unavailable.
do $schedule$
declare v_job_id bigint;
begin
  if to_regclass('cron.job') is null then
    raise exception 'pg_cron must be enabled before applying the promotions scheduler migration';
  end if;
  for v_job_id in select jobid from cron.job where jobname='elegance-promotion-suggestions-daily'
  loop perform cron.unschedule(v_job_id); end loop;
  perform cron.schedule('elegance-promotion-suggestions-daily','0 12 * * *',
    'select public.barber_promotions_generate_daily_suggestions_internal();');
end
$schedule$;
