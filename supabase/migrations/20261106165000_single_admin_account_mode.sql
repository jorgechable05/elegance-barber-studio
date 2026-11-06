-- Simplify Elegance Barber to one ADMIN account shared by Admin and POS.
-- Employee tables and historical rows are retained for safe compatibility; no employee login is required.
create or replace function public.barber_admin_login(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $function$
declare
  v_token uuid;
  v_hash text;
  v_username text;
begin
  if nullif(trim(coalesce(p_username,'')),'') is null
     or p_password is null or length(p_password)>128 then
    raise exception 'Usuario o contraseña incorrectos' using errcode='28000';
  end if;

  select username,pin_hash into v_username,v_hash
    from public.barber_admin_config
   where id=true and lower(username)=lower(trim(p_username));

  if v_hash is null or extensions.crypt(p_password,v_hash) is distinct from v_hash then
    raise exception 'Usuario o contraseña incorrectos' using errcode='28000';
  end if;

  insert into public.barber_admin_sessions(username,expires_at)
  values(v_username,now()+interval '12 hours')
  returning token into v_token;

  return jsonb_build_object(
    'token',v_token,
    'expires_at',now()+interval '12 hours',
    'username',v_username,
    'display_name',v_username,
    'role','ADMINISTRADOR'
  );
end;
$function$;

create or replace function public.barber_session_identity(p_token uuid)
returns table(employee_id uuid, username text, display_name text, role text)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  return query
  select null::uuid,s.username,s.username,'ADMINISTRADOR'::text
    from public.barber_admin_sessions s
   where s.token=p_token
     and s.revoked_at is null
     and s.expires_at>now();

  if not found then
    raise exception 'Sesión administrativa inválida o vencida' using errcode='28000';
  end if;
end;
$function$;

revoke all on function public.barber_admin_login(text,text) from public, anon, authenticated;
grant execute on function public.barber_admin_login(text,text) to service_role;
revoke all on function public.barber_session_identity(uuid) from public, anon, authenticated;
grant execute on function public.barber_session_identity(uuid) to service_role;
