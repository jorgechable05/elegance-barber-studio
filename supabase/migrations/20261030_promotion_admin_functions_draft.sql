-- ELEGANCE BARBER STUDIO: admin promotion operations (draft migration).
-- Must be reviewed and tested in a non-production Supabase project before applying.

create or replace function public.barber_promotions_admin_list(p_token uuid)
returns table (
  id uuid, title text, description text, status text, discount_type text,
  discount_value numeric, starts_at timestamptz, ends_at timestamptz,
  weekdays smallint[], start_time time, end_time time, source text,
  max_uses integer, uses_count integer, service_ids integer[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  return query
    select p.id, p.title, p.description, p.status, p.discount_type, p.discount_value,
           p.starts_at, p.ends_at, p.weekdays, p.start_time, p.end_time, p.source,
           p.max_uses, p.uses_count,
           coalesce(array_agg(ps.service_id) filter (where ps.service_id is not null), '{}'::integer[])
    from public.barber_promotions p
    left join public.barber_promotion_services ps on ps.promotion_id=p.id
    group by p.id
    order by p.created_at desc;
end;
$$;

create or replace function public.barber_promotion_admin_save(
  p_token uuid, p_id uuid, p_title text, p_description text,
  p_discount_type text, p_discount_value numeric,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_weekdays smallint[], p_start_time time, p_end_time time,
  p_service_ids integer[], p_max_uses integer
)
returns public.barber_promotions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.barber_promotions;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;
  if nullif(trim(p_title),'') is null or p_starts_at is null or p_ends_at <= p_starts_at
     or p_discount_type not in ('percent','fixed_price') or p_discount_value <= 0
     or (p_discount_type='percent' and p_discount_value > 100)
     or coalesce(array_length(p_service_ids,1),0)=0
     or (p_max_uses is not null and p_max_uses <= 0) then
    raise exception 'Datos de promoción inválidos' using errcode='22023';
  end if;
  if (p_start_time is null) <> (p_end_time is null) then
    raise exception 'Indica la hora inicial y final, o deja ambos campos vacíos' using errcode='22023';
  end if;
  if p_start_time is not null and p_end_time is not null and p_end_time <= p_start_time then
    raise exception 'El horario final debe ser posterior al inicial' using errcode='22023';
  end if;
  if p_discount_type = 'fixed_price' and exists (
    select 1 from unnest(p_service_ids) sid
    join public.barber_services s on s.id=sid
    where p_discount_value > s.price
  ) then
    raise exception 'El precio especial no puede superar el precio normal de ninguno de los servicios seleccionados' using errcode='22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_weekdays,'{}'::smallint[])) d where d < 0 or d > 6
  ) then
    raise exception 'Los días de semana deben estar entre 0 y 6' using errcode='22023';
  end if;
  if exists (
    select 1 from unnest(p_service_ids) sid
    left join public.barber_services s on s.id=sid
    where s.id is null
  ) then
    raise exception 'Uno o más servicios no existen' using errcode='22023';
  end if;

  if p_id is null then
    insert into public.barber_promotions(
      title,description,status,discount_type,discount_value,starts_at,ends_at,
      weekdays,start_time,end_time,source,max_uses
    ) values (
      trim(p_title),coalesce(p_description,''),'draft',p_discount_type,p_discount_value,
      p_starts_at,p_ends_at,coalesce(p_weekdays,array[0,1,2,3,4,5,6]::smallint[]),
      p_start_time,p_end_time,'manual',p_max_uses
    ) returning * into v_row;
  else
    update public.barber_promotions
      set title=trim(p_title), description=coalesce(p_description,''), status='draft',
          discount_type=p_discount_type, discount_value=p_discount_value,
          starts_at=p_starts_at, ends_at=p_ends_at,
          weekdays=coalesce(p_weekdays,array[0,1,2,3,4,5,6]::smallint[]),
          start_time=p_start_time, end_time=p_end_time, source='manual',
          max_uses=p_max_uses, approved_at=null, updated_at=now()
      where id=p_id returning * into v_row;
    if not found then raise exception 'Promoción no encontrada' using errcode='P0002'; end if;
  end if;

  delete from public.barber_promotion_services where promotion_id=v_row.id;
  insert into public.barber_promotion_services(promotion_id,service_id)
    select v_row.id, sid from unnest(p_service_ids) sid
    on conflict do nothing;
  return v_row;
end;
$$;

-- Generates pending suggestions, never publishes them.
-- Intended for a once-daily scheduler after the service catalogue has been populated.
-- Current heuristic: suggest 10% off one active service with no approved promo in the next 24h.
create or replace function public.barber_promotions_generate_daily_suggestions(p_token uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_service record; v_promo_id uuid; v_created integer := 0;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de administrador inválida o vencida' using errcode='28000';
  end if;

  for v_service in
    select s.id, s.name
    from public.barber_services s
    where s.is_active
      and not exists (
        select 1
        from public.barber_promotion_services ps
        join public.barber_promotions p on p.id=ps.promotion_id
        where ps.service_id=s.id and p.status='approved'
          and p.starts_at < now()+interval '24 hours' and p.ends_at > now()
      )
      and not exists (
        select 1 from public.barber_promotion_services ps
        join public.barber_promotions p on p.id=ps.promotion_id
        where ps.service_id=s.id and p.source='daily_suggestion'
          and p.created_at::date=(now() at time zone 'America/Mexico_City')::date
      )
    order by s.display_order, s.name
    limit 3
  loop
    insert into public.barber_promotions(
      title,description,status,discount_type,discount_value,starts_at,ends_at,
      weekdays,source
    ) values (
      'Sugerencia diaria: '||v_service.name,
      'Propuesta automática del 10%. Revisa y ajusta antes de aprobar.',
      'pending_review','percent',10,now(),now()+interval '24 hours',
      array[extract(dow from now() at time zone 'America/Mexico_City')::smallint],
      'daily_suggestion'
    ) returning id into v_promo_id;
    insert into public.barber_promotion_services(promotion_id,service_id)
      values (v_promo_id,v_service.id);
    v_created := v_created+1;
  end loop;
  return v_created;
end;
$$;

-- Internal no-session variant for a trusted scheduler. Never executable by anon/authenticated.
create or replace function public.barber_promotions_generate_daily_suggestions_internal()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_service record;
  v_promo_id uuid;
  v_created integer := 0;
  v_today date;
  v_lock_key bigint := hashtext('elegance-promotion-scheduler')::bigint;
begin
  -- Serialize this job and skip today's run if any daily suggestions already exist.
  perform pg_advisory_xact_lock(v_lock_key);
  v_today := (now() at time zone 'America/Merida')::date;

  if exists (
    select 1
    from public.barber_promotions p
    where p.source = 'daily_suggestion'
      and (p.created_at at time zone 'America/Merida')::date = v_today
  ) then
    return 0;
  end if;

  for v_service in
    select s.id, s.name
    from public.barber_services s
    where s.is_active
      and not exists (
        select 1
        from public.barber_promotion_services ps
        join public.barber_promotions p on p.id=ps.promotion_id
        where ps.service_id=s.id and p.status='approved'
          and p.starts_at < now()+interval '24 hours' and p.ends_at > now()
      )
    order by s.display_order, s.name
    limit 3
  loop
    insert into public.barber_promotions(
      title,description,status,discount_type,discount_value,starts_at,ends_at,
      weekdays,source
    ) values (
      'Sugerencia diaria: '||v_service.name,
      'Propuesta automática del 10%. Revisa y ajusta antes de aprobar.',
      'pending_review','percent',10,now(),now()+interval '24 hours',
      array[extract(dow from now() at time zone 'America/Merida')::smallint],
      'daily_suggestion'
    ) returning id into v_promo_id;
    insert into public.barber_promotion_services(promotion_id,service_id)
      values (v_promo_id,v_service.id);
    v_created := v_created+1;
  end loop;
  return v_created;
end;
$$;

revoke all on function public.barber_promotions_generate_daily_suggestions_internal() from public, anon, authenticated;
grant execute on function public.barber_promotions_generate_daily_suggestions_internal() to service_role;

-- Schedule at 12:00 UTC (~06:00 in Yucatán).
-- Fail loudly if pg_cron is not enabled: a successful migration must not silently omit the daily job.
-- Remove an existing job first so rerunning this block remains idempotent.
do $schedule$
declare v_job_id bigint;
begin
  if to_regclass('cron.job') is null then
    raise exception 'pg_cron must be enabled before applying the promotions scheduler migration';
  end if;

  for v_job_id in
    select jobid from cron.job where jobname='elegance-promotion-suggestions-daily'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'elegance-promotion-suggestions-daily',
    '0 12 * * *',
    'select public.barber_promotions_generate_daily_suggestions_internal();'
  );
end
$schedule$;

grant execute on function public.barber_promotions_admin_list(uuid) to anon, authenticated;
grant execute on function public.barber_promotion_admin_save(uuid,uuid,text,text,text,numeric,timestamptz,timestamptz,smallint[],time,time,integer[],integer) to anon, authenticated;
grant execute on function public.barber_promotions_generate_daily_suggestions(uuid) to anon, authenticated;
