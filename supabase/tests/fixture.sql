-- Minimal PostgreSQL contract fixture for CI; never connected to production.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create table public.barber_admin_sessions (
  token uuid primary key,
  username text not null default 'ci',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 day',
  revoked_at timestamptz
);

-- Minimal legacy reservation table contract for the additive reservation RPC.
create table public.reservas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  telefono text,
  wa text,
  serv text,
  servicio text,
  precio integer,
  barbero text,
  fecha date,
  hora text,
  estado text,
  stock_key text
);

-- CI-only pg_cron contract double. It verifies scheduler configuration without
-- installing or running an operating-system cron worker in the disposable DB.
create schema cron;
create table cron.job (
  jobid bigint generated always as identity primary key,
  jobname text unique,
  schedule text not null,
  command text not null
);
create or replace function cron.unschedule(p_jobid bigint)
returns boolean language plpgsql as $$
begin
  delete from cron.job where jobid=p_jobid;
  return found;
end;
$$;
create or replace function cron.schedule(p_jobname text, p_schedule text, p_command text)
returns bigint language plpgsql as $$
declare v_jobid bigint;
begin
  insert into cron.job(jobname,schedule,command)
  values(p_jobname,p_schedule,p_command)
  on conflict(jobname) do update set schedule=excluded.schedule, command=excluded.command
  returning jobid into v_jobid;
  return v_jobid;
end;
$$;
