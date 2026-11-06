-- Isolated QA hardening for the QR loyalty signup.
create table if not exists public.barber_loyalty_registration_attempts(
 id bigint generated always as identity primary key,
 ip_hash text not null,
 attempted_at timestamptz not null default now()
);
create index if not exists barber_loyalty_attempts_ip_time_idx
 on public.barber_loyalty_registration_attempts(ip_hash,attempted_at desc);
alter table public.barber_loyalty_registration_attempts enable row level security;
revoke all on public.barber_loyalty_registration_attempts from public,anon,authenticated;
grant select,insert,delete on public.barber_loyalty_registration_attempts to service_role;
drop policy if exists barber_loyalty_attempts_deny_clients on public.barber_loyalty_registration_attempts;
create policy barber_loyalty_attempts_deny_clients on public.barber_loyalty_registration_attempts
 for all to anon,authenticated using(false) with check(false);

create index if not exists barber_promotion_services_service_idx on public.barber_promotion_services(service_id);
create index if not exists barber_sales_promotion_id_idx on public.barber_sales(promotion_id);
create index if not exists barber_sales_loyalty_customer_id_idx on public.barber_sales(loyalty_customer_id);
create index if not exists reservas_promotion_id_idx on public.reservas(promotion_id);
create index if not exists reservas_servicio_id_idx on public.reservas(servicio_id);

do $policies$
declare t text;
begin
 foreach t in array array[
  'barber_admin_config','barber_admin_sessions','barber_sales','reservas',
  'barber_loyalty_customers','barber_loyalty_visits','barber_loyalty_rewards',
  'barber_promotion_suggestion_settings'
 ] loop
  execute format('drop policy if exists %I on public.%I',t||'_deny_clients',t);
  execute format('create policy %I on public.%I for all to anon,authenticated using(false) with check(false)',t||'_deny_clients',t);
 end loop;
end
$policies$;

revoke all on function public.barber_loyalty_register_customer(text,text,boolean) from public,anon,authenticated;
grant execute on function public.barber_loyalty_register_customer(text,text,boolean) to service_role;

create or replace function public.barber_loyalty_allow_registration(p_ip_hash text)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_count integer;
begin
 if p_ip_hash is null or length(p_ip_hash)<>64 or p_ip_hash !~ '^[0-9a-f]{64}$' then
  raise exception 'Identificador de origen no válido' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_ip_hash,0));
 delete from public.barber_loyalty_registration_attempts where attempted_at<now()-interval '24 hours';
 select count(*) into v_count from public.barber_loyalty_registration_attempts
  where ip_hash=p_ip_hash and attempted_at>now()-interval '1 hour';
 if v_count>=5 then return false; end if;
 insert into public.barber_loyalty_registration_attempts(ip_hash) values(p_ip_hash);
 return true;
end;
$$;
revoke all on function public.barber_loyalty_allow_registration(text) from public,anon,authenticated;
grant execute on function public.barber_loyalty_allow_registration(text) to service_role;

do $revoke$
declare f record;
begin
 for f in select p.oid::regprocedure as signature
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef
 loop
  execute format('revoke execute on function %s from public',f.signature);
 end loop;
end
$revoke$;
