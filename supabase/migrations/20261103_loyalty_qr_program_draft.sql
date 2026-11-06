-- ELEGANCE BARBER: customer loyalty program (draft; apply only to isolated QA first)
begin;

create table if not exists public.barber_loyalty_customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) between 2 and 100),
  phone text not null unique check (phone ~ '^[0-9]{10,13}$'),
  consent_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.barber_sales add column if not exists loyalty_customer_id uuid references public.barber_loyalty_customers(id) on delete restrict;

create table if not exists public.barber_loyalty_visits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.barber_loyalty_customers(id) on delete restrict,
  sale_id bigint not null unique references public.barber_sales(id) on delete restrict,
  cycle_number integer not null check (cycle_number > 0),
  visit_number smallint not null check (visit_number between 1 and 5),
  registered_by text not null,
  created_at timestamptz not null default now(),
  unique(customer_id, cycle_number, visit_number)
);

create table if not exists public.barber_loyalty_rewards (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.barber_loyalty_customers(id) on delete restrict,
  cycle_number integer not null check (cycle_number > 0),
  reward_type text not null default 'corte_cortesia' check (reward_type = 'corte_cortesia'),
  status text not null default 'pending' check (status in ('pending','redeemed','cancelled')),
  earned_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by text,
  unique(customer_id, cycle_number),
  check ((status = 'redeemed') = (redeemed_at is not null))
);

create index if not exists barber_loyalty_visits_customer_idx
  on public.barber_loyalty_visits(customer_id, cycle_number, visit_number);
create index if not exists barber_loyalty_rewards_pending_idx
  on public.barber_loyalty_rewards(status, earned_at desc);

alter table public.barber_loyalty_customers enable row level security;
alter table public.barber_loyalty_visits enable row level security;
alter table public.barber_loyalty_rewards enable row level security;

revoke all on public.barber_loyalty_customers from anon, authenticated;
revoke all on public.barber_loyalty_visits from anon, authenticated;
revoke all on public.barber_loyalty_rewards from anon, authenticated;

-- Public QR registration stores only the minimum information and returns no customer
-- identifier or existing-customer data. Existing phone numbers are not duplicated.
create or replace function public.barber_loyalty_register_customer(
  p_name text, p_phone text, p_consent boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_name text := trim(coalesce(p_name,''));
  v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if length(v_phone)=12 and left(v_phone,2)='52' then v_phone:=substring(v_phone from 3);
  elsif length(v_phone)=13 and left(v_phone,3)='521' then v_phone:=substring(v_phone from 4);
  end if;
  if p_consent is distinct from true then
    raise exception 'Se requiere aceptar el aviso de privacidad' using errcode='22023';
  end if;
  if length(v_name) < 2 or length(v_name) > 100 then
    raise exception 'Escribe un nombre válido' using errcode='22023';
  end if;
  if length(v_phone) < 10 or length(v_phone) > 13 then
    raise exception 'Escribe un teléfono válido con lada' using errcode='22023';
  end if;

  insert into public.barber_loyalty_customers(full_name, phone, consent_at)
  values(v_name, v_phone, now())
  on conflict(phone) do nothing;

  return jsonb_build_object(
    'accepted', true,
    'message', 'Registro recibido. Si ya formas parte del programa, el equipo podrá localizar tu cuenta.'
  );
end;
$$;

-- Staff lookup: token must belong to a live admin/POS session. PII is returned only here.
create or replace function public.barber_loyalty_lookup_customer(
  p_token uuid, p_phone text
)
returns table(
  customer_id uuid, full_name text, phone_masked text,
  cycle_number integer, visits_in_cycle integer, pending_rewards integer,
  total_visits bigint
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if length(v_phone)=12 and left(v_phone,2)='52' then v_phone:=substring(v_phone from 3);
  elsif length(v_phone)=13 and left(v_phone,3)='521' then v_phone:=substring(v_phone from 4);
  end if;
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de personal inválida o vencida' using errcode='28000';
  end if;

  return query
  with c as (
    select lc.* from public.barber_loyalty_customers lc where lc.phone=v_phone
  ), last_cycle as (
    select c.id, case when count(r.id)=0 then 1
      when bool_or(r.status='pending') then max(r.cycle_number)
      else max(r.cycle_number)+1 end as cycle_number
    from c left join public.barber_loyalty_rewards r on r.customer_id=c.id
    group by c.id
  )
  select c.id, c.full_name,
    '••••' || right(c.phone,4),
    lc.cycle_number,
    coalesce((select count(*)::integer from public.barber_loyalty_visits v
      where v.customer_id=c.id and v.cycle_number=lc.cycle_number),0),
    (select count(*)::integer from public.barber_loyalty_rewards rw
      where rw.customer_id=c.id and rw.status='pending'),
    (select count(*) from public.barber_loyalty_visits v where v.customer_id=c.id)
  from c join last_cycle lc on lc.id=c.id;
end;
$$;

-- A completed sale can be credited once. The customer row lock serializes concurrent
-- checkouts; unique sale_id and (customer,cycle,visit) are a second idempotency barrier.
create or replace function public.barber_loyalty_record_visit(
  p_token uuid, p_customer_id uuid, p_sale_id bigint, p_employee text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_customer public.barber_loyalty_customers;
  v_sale public.barber_sales;
  v_cycle integer;
  v_visit integer;
  v_existing public.barber_loyalty_visits;
  v_reward_id uuid;
begin
  if not exists (
    select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()
  ) then
    raise exception 'Sesión de personal inválida o vencida' using errcode='28000';
  end if;
  if nullif(trim(coalesce(p_employee,'')),'') is null then
    raise exception 'Falta identificar al empleado' using errcode='22023';
  end if;

  select * into v_customer from public.barber_loyalty_customers
   where id=p_customer_id for update;
  if not found then raise exception 'Cliente de lealtad no encontrado' using errcode='P0002'; end if;

  select * into v_sale from public.barber_sales where id=p_sale_id for update;
  if not found then raise exception 'La venta no existe; registra la visita después de cobrar' using errcode='P0002'; end if;
  if v_sale.loyalty_customer_id is not null and v_sale.loyalty_customer_id<>p_customer_id then
    raise exception 'Esta venta ya pertenece a otro cliente del programa' using errcode='23505';
  end if;

  select * into v_existing from public.barber_loyalty_visits where sale_id=p_sale_id;
  if found then
    if v_existing.customer_id<>p_customer_id then
      raise exception 'Esta venta ya fue asociada a otro cliente' using errcode='23505';
    end if;
    return jsonb_build_object(
      'already_recorded',true,'visit_number',v_existing.visit_number,
      'cycle_number',v_existing.cycle_number,
      'reward_earned',exists(select 1 from public.barber_loyalty_rewards r
        where r.customer_id=p_customer_id and r.cycle_number=v_existing.cycle_number)
    );
  end if;

  select case when count(*)=0 then 1
      when bool_or(status='pending') then max(cycle_number)
      else max(cycle_number)+1 end into v_cycle
    from public.barber_loyalty_rewards where customer_id=p_customer_id;
  select count(*)::integer into v_visit
    from public.barber_loyalty_visits
   where customer_id=p_customer_id and cycle_number=v_cycle;
  if v_visit>=5 then
    raise exception 'El ciclo anterior ya completó cinco visitas; revisa el premio pendiente' using errcode='23514';
  end if;
  v_visit:=v_visit+1;

  update public.barber_sales set loyalty_customer_id=p_customer_id where id=p_sale_id;
  insert into public.barber_loyalty_visits(customer_id,sale_id,cycle_number,visit_number,registered_by)
  values(p_customer_id,p_sale_id,v_cycle,v_visit,trim(p_employee));

  if v_visit=5 then
    insert into public.barber_loyalty_rewards(customer_id,cycle_number)
    values(p_customer_id,v_cycle)
    on conflict(customer_id,cycle_number) do nothing
    returning id into v_reward_id;
  end if;

  return jsonb_build_object(
    'already_recorded',false,'visit_number',v_visit,'cycle_number',v_cycle,
    'reward_earned',(v_visit=5),'reward_id',v_reward_id
  );
end;
$$;

create or replace function public.barber_loyalty_list_customers(p_token uuid)
returns table(
  customer_id uuid, full_name text, phone_masked text,
  cycle_number integer, visits_in_cycle integer, pending_rewards integer,
  total_visits bigint, created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de personal inválida o vencida' using errcode='28000';
  end if;
  return query
  with cycles as (
    select c.id, case when count(r.id)=0 then 1
      when bool_or(r.status='pending') then max(r.cycle_number)
      else max(r.cycle_number)+1 end as cycle_number
    from public.barber_loyalty_customers c
    left join public.barber_loyalty_rewards r on r.customer_id=c.id
    group by c.id
  )
  select c.id,c.full_name,'••••'||right(c.phone,4),cy.cycle_number,
    (select count(*)::integer from public.barber_loyalty_visits v
      where v.customer_id=c.id and v.cycle_number=cy.cycle_number),
    (select count(*)::integer from public.barber_loyalty_rewards rw
      where rw.customer_id=c.id and rw.status='pending'),
    (select count(*) from public.barber_loyalty_visits v where v.customer_id=c.id),
    c.created_at
  from public.barber_loyalty_customers c join cycles cy on cy.id=c.id
  order by c.created_at desc;
end;
$$;

create or replace function public.barber_loyalty_redeem_reward(
  p_token uuid, p_reward_id uuid, p_employee text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_reward public.barber_loyalty_rewards;
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de personal inválida o vencida' using errcode='28000';
  end if;
  select * into v_reward from public.barber_loyalty_rewards
    where id=p_reward_id for update;
  if not found then raise exception 'Premio no encontrado' using errcode='P0002'; end if;
  if v_reward.status<>'pending' then
    raise exception 'El premio ya fue entregado o cancelado' using errcode='23514';
  end if;
  if nullif(trim(coalesce(p_employee,'')),'') is null then
    raise exception 'Falta identificar al empleado' using errcode='22023';
  end if;
  update public.barber_loyalty_rewards
    set status='redeemed',redeemed_at=now(),redeemed_by=trim(p_employee)
    where id=p_reward_id;
  return jsonb_build_object('redeemed',true,'customer_id',v_reward.customer_id,
    'cycle_number',v_reward.cycle_number,'reward_type',v_reward.reward_type);
end;
$$;

revoke all on function public.barber_loyalty_register_customer(text,text,boolean) from public;
revoke all on function public.barber_loyalty_lookup_customer(uuid,text) from public;
revoke all on function public.barber_loyalty_record_visit(uuid,uuid,bigint,text) from public;
revoke all on function public.barber_loyalty_list_customers(uuid) from public;
revoke all on function public.barber_loyalty_redeem_reward(uuid,uuid,text) from public;

grant execute on function public.barber_loyalty_register_customer(text,text,boolean) to anon,authenticated;
grant execute on function public.barber_loyalty_lookup_customer(uuid,text) to anon,authenticated;
grant execute on function public.barber_loyalty_record_visit(uuid,uuid,bigint,text) to anon,authenticated;
grant execute on function public.barber_loyalty_list_customers(uuid) to anon,authenticated;
grant execute on function public.barber_loyalty_redeem_reward(uuid,uuid,text) to anon,authenticated;

commit;
