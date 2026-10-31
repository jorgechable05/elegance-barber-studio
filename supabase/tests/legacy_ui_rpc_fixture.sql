-- CI ONLY: disposable stubs for legacy UI RPCs not included in the promotion migration fixture.
-- Never apply this file to any hosted Supabase project. Credentials and outputs are synthetic.
create or replace function public.barber_admin_login(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_token constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
begin
  if p_username <> 'local-qa-user'
     or p_password <> 'local-qa-password-not-a-credential' then
    raise exception 'Credenciales de prueba inválidas' using errcode = '28000';
  end if;

  insert into public.barber_admin_sessions(token, username, expires_at, revoked_at)
  values (v_token, 'local-qa-user', now() + interval '1 hour', null)
  on conflict (token) do update
    set username = excluded.username,
        expires_at = excluded.expires_at,
        revoked_at = null;

  return jsonb_build_object('token', v_token::text);
end;
$$;

create or replace function public.barber_admin_reservations(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token = p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de prueba inválida o vencida' using errcode = '28000';
  end if;
  return '[]'::jsonb;
end;
$$;

create or replace function public.barber_admin_sales(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token = p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de prueba inválida o vencida' using errcode = '28000';
  end if;
  return '[]'::jsonb;
end;
$$;

create or replace function public.barber_admin_create_walkin_sale(
  p_token uuid, p_cliente text, p_servicio_id integer, p_barbero_id integer,
  p_metodo text, p_recibido numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token = p_token and s.revoked_at is null and s.expires_at > now()
  ) then
    raise exception 'Sesión de prueba inválida o vencida' using errcode = '28000';
  end if;
  if p_servicio_id not between 1 and 9 or p_barbero_id not between 1 and 2
     or p_metodo not in ('Efectivo', 'Transferencia', 'Tarjeta', 'Mixto')
     or p_recibido < 0 then
    raise exception 'Datos de venta de prueba inválidos' using errcode = '22023';
  end if;
  -- This is a response fixture only: intentionally no sale/transaction row is written.
  return jsonb_build_object(
    'folio', 'QA-WALKIN-HTTP-001',
    'total', 160,
    'cliente', coalesce(nullif(trim(p_cliente), ''), 'Cliente QA'),
    'servicio', 'Corte Clásico',
    'barbero', case when p_barbero_id = 1 then 'EdgarMay' else 'Staff 2' end,
    'metodo', p_metodo
  );
end;
$$;

create or replace function public.barber_public_schedule(p_fecha date, p_barbero_id integer)
returns table (hora text, disponible boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select h.hora, true
  from unnest(array[
    '13:30','14:00','14:30','15:00','15:30','16:00','16:30','17:00',
    '17:30','18:00','18:30','19:00','19:30','20:00','20:30'
  ]::text[]) as h(hora)
  where p_fecha is not null and p_barbero_id in (1,2)
  order by h.hora;
$$;

grant execute on function public.barber_admin_login(text,text) to anon, authenticated;
grant execute on function public.barber_public_schedule(date,integer) to anon, authenticated;
grant execute on function public.barber_admin_reservations(uuid) to anon, authenticated;
grant execute on function public.barber_admin_sales(uuid) to anon, authenticated;
grant execute on function public.barber_admin_create_walkin_sale(uuid,text,integer,integer,text,numeric) to anon, authenticated;
