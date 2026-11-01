-- Additive payment-split contract for the POS.
-- Draft only: validate in isolated PostgreSQL before any hosted application.
-- Existing four-/six-argument RPCs remain unchanged for non-mixed payments and legacy clients.

alter table public.barber_sales
  add column if not exists efectivo numeric(12,2),
  add column if not exists tarjeta numeric(12,2);

do $constraints$
begin
  if not exists (select 1 from pg_constraint where conname='barber_sales_payment_split_pair_ck') then
    alter table public.barber_sales
      add constraint barber_sales_payment_split_pair_ck
      check ((efectivo is null) = (tarjeta is null));
  end if;
  if not exists (select 1 from pg_constraint where conname='barber_sales_payment_split_total_ck') then
    alter table public.barber_sales
      add constraint barber_sales_payment_split_total_ck
      check (efectivo is null or (
        metodo='Mixto' and efectivo >= 0 and tarjeta >= 0
        and round(efectivo + tarjeta, 2) = round(total, 2)
      ));
  end if;
end
$constraints$;

-- Mixed payment overload for reservation sales. The legacy function performs
-- session, reservation-lock, duplicate-sale and reservation-state checks. Any
-- validation error below rolls its writes back in the same transaction.
create or replace function public.barber_admin_create_sale(
  p_token uuid, p_reserva_id uuid, p_metodo text, p_recibido numeric,
  p_efectivo numeric, p_tarjeta numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_result jsonb;
  v_total numeric(12,2);
  v_sale_id bigint;
begin
  if p_metodo <> 'Mixto' then
    raise exception 'Esta variante solo acepta pago Mixto' using errcode='22023';
  end if;
  if p_efectivo is null or p_tarjeta is null
     or p_efectivo < 0 or p_tarjeta < 0 then
    raise exception 'Importes del pago mixto inválidos' using errcode='22023';
  end if;

  v_result := public.barber_admin_create_sale(
    p_token, p_reserva_id, p_metodo, p_recibido
  );
  v_sale_id := (v_result->>'id')::bigint;
  v_total := (v_result->>'total')::numeric;

  if round(p_efectivo + p_tarjeta, 2) <> round(v_total, 2) then
    raise exception 'Efectivo + tarjeta debe ser igual al total' using errcode='22023';
  end if;

  update public.barber_sales
     set efectivo=round(p_efectivo,2), tarjeta=round(p_tarjeta,2)
   where id=v_sale_id;

  return v_result || jsonb_build_object(
    'efectivo', round(p_efectivo,2),
    'tarjeta', round(p_tarjeta,2),
    'cambio', 0
  );
end;
$$;

-- Mixed payment overload for walk-in sales. The legacy RPC remains the source
-- of truth for service/barber validation and the current catalogue prices.
create or replace function public.barber_admin_create_walkin_sale(
  p_token uuid, p_cliente text, p_servicio_id integer, p_barbero_id integer,
  p_metodo text, p_recibido numeric, p_efectivo numeric, p_tarjeta numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_result jsonb;
  v_total numeric(12,2);
  v_sale_id bigint;
begin
  if p_metodo <> 'Mixto' then
    raise exception 'Esta variante solo acepta pago Mixto' using errcode='22023';
  end if;
  if p_efectivo is null or p_tarjeta is null
     or p_efectivo < 0 or p_tarjeta < 0 then
    raise exception 'Importes del pago mixto inválidos' using errcode='22023';
  end if;

  v_result := public.barber_admin_create_walkin_sale(
    p_token, p_cliente, p_servicio_id, p_barbero_id, p_metodo, p_recibido
  );
  v_sale_id := (v_result->>'id')::bigint;
  v_total := (v_result->>'total')::numeric;

  if round(p_efectivo + p_tarjeta, 2) <> round(v_total, 2) then
    raise exception 'Efectivo + tarjeta debe ser igual al total' using errcode='22023';
  end if;

  update public.barber_sales
     set efectivo=round(p_efectivo,2), tarjeta=round(p_tarjeta,2)
   where id=v_sale_id;

  return v_result || jsonb_build_object(
    'efectivo', round(p_efectivo,2),
    'tarjeta', round(p_tarjeta,2),
    'cambio', 0
  );
end;
$$;

revoke all on function public.barber_admin_create_sale(uuid,uuid,text,numeric,numeric,numeric) from public;
revoke all on function public.barber_admin_create_walkin_sale(uuid,text,integer,integer,text,numeric,numeric,numeric) from public;
grant execute on function public.barber_admin_create_sale(uuid,uuid,text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.barber_admin_create_walkin_sale(uuid,text,integer,integer,text,numeric,numeric,numeric) to anon, authenticated;
