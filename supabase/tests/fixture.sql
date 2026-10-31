-- Minimal PostgreSQL contract fixture for CI; never connected to production.
create role anon nologin;
create role authenticated nologin;
create table public.barber_admin_sessions (
  token uuid primary key,
  username text not null default 'ci',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 day',
  revoked_at timestamptz
);
