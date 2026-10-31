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
