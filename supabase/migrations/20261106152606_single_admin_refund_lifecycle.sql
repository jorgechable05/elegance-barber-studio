alter table public.barber_sale_refunds
  drop constraint if exists barber_sale_refunds_requested_by_fkey,
  drop constraint if exists barber_sale_refunds_reviewed_by_fkey;
alter table public.barber_sale_refunds
  alter column requested_by drop not null,
  add column if not exists requested_by_label text,
  add column if not exists reviewed_by_label text;

create table if not exists public.barber_refund_incidents (
  id uuid primary key default gen_random_uuid(),
  sale_id bigint not null references public.barber_sales(id) on delete restrict,
  refund_id uuid references public.barber_sale_refunds(id) on delete restrict,
  customer_id uuid references public.barber_loyalty_customers(id) on delete restrict,
  reward_id uuid references public.barber_loyalty_rewards(id) on delete restrict,
  incident_type text not null check (incident_type in ('redeemed_reward_after_full_refund')),
  status text not null default 'open' check (status in ('open','resolved')),
  details jsonb not null default '{}'::jsonb,
  created_by_label text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_label text
);
create index if not exists barber_refund_incidents_sale_id_idx on public.barber_refund_incidents(sale_id);
create unique index if not exists barber_refund_incidents_refund_reward_uq
  on public.barber_refund_incidents(refund_id,reward_id)
  where refund_id is not null and reward_id is not null;
alter table public.barber_refund_incidents enable row level security;
revoke all on public.barber_refund_incidents from anon, authenticated, public;
grant all on public.barber_refund_incidents to service_role;

create or replace function public.barber_admin_request_refund(
 p_token uuid,p_sale_id bigint,p_amount numeric,p_refund_method text,p_reason text
) returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','pg_temp' as $$
declare v_actor record; v_sale public.barber_sales; v_pending numeric(12,2); v_refund public.barber_sale_refunds;
begin
 select * into v_actor from public.barber_session_identity(p_token);
 if v_actor.role<>'ADMINISTRADOR' then raise exception 'Solo ADMIN puede solicitar devoluciones' using errcode='42501'; end if;
 if p_amount is null or p_amount<=0 or p_amount>1000000 then raise exception 'Importe de devolución no válido' using errcode='22023'; end if;
 if p_refund_method not in ('Efectivo','Transferencia','Tarjeta') then raise exception 'Método de devolución no válido' using errcode='22023'; end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'El motivo debe tener entre 3 y 500 caracteres' using errcode='22023'; end if;
 select * into v_sale from public.barber_sales where id=p_sale_id for update;
 if not found then raise exception 'Venta no encontrada' using errcode='P0002'; end if;
 if v_sale.payment_status not in ('paid','partially_refunded') then raise exception 'La venta ya está totalmente devuelta' using errcode='23514'; end if;
 select coalesce(sum(amount),0) into v_pending from public.barber_sale_refunds where sale_id=p_sale_id and status in ('requested','approved','paid');
 if round(v_pending+p_amount,2)>round(v_sale.total,2) then raise exception 'El importe supera el saldo disponible para devolver' using errcode='23514'; end if;
 insert into public.barber_sale_refunds(sale_id,amount,refund_method,reason,status,requested_by,requested_by_label)
 values(p_sale_id,round(p_amount,2),p_refund_method,trim(p_reason),'requested',null,v_actor.display_name) returning * into v_refund;
 insert into public.barber_sale_audit(sale_id,action,after_data,reason,actor_employee_id,actor_label)
 values(p_sale_id,'refund_requested',to_jsonb(v_refund),trim(p_reason),null,v_actor.display_name);
 return jsonb_build_object('refund_id',v_refund.id,'sale_id',p_sale_id,'amount',v_refund.amount,'status',v_refund.status);
end $$;

create or replace function public.barber_admin_review_refund(
 p_token uuid,p_refund_id uuid,p_decision text,p_reason text default null
) returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','pg_temp' as $$
declare v_actor record; v_refund public.barber_sale_refunds;
begin
 select * into v_actor from public.barber_session_identity(p_token);
 if v_actor.role<>'ADMINISTRADOR' then raise exception 'Solo ADMIN puede revisar devoluciones' using errcode='42501'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decisión no válida' using errcode='22023'; end if;
 select * into v_refund from public.barber_sale_refunds where id=p_refund_id for update;
 if not found then raise exception 'Devolución no encontrada' using errcode='P0002'; end if;
 if v_refund.status<>'requested' then raise exception 'La devolución ya fue revisada' using errcode='23514'; end if;
 if p_decision='rejected' and length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica el motivo del rechazo' using errcode='22023'; end if;
 update public.barber_sale_refunds set status=p_decision,reviewed_by=null,reviewed_by_label=v_actor.display_name,reviewed_at=now(),
 reason=case when p_decision='rejected' then left(v_refund.reason||' | Rechazo: '||trim(p_reason),500) else v_refund.reason end
 where id=p_refund_id returning * into v_refund;
 insert into public.barber_sale_audit(sale_id,action,before_data,after_data,reason,actor_employee_id,actor_label)
 values(v_refund.sale_id,'refund_'||p_decision,to_jsonb(v_refund),to_jsonb(v_refund),coalesce(nullif(trim(p_reason),''),v_refund.reason),null,v_actor.display_name);
 return jsonb_build_object('refund_id',v_refund.id,'status',v_refund.status);
end $$;

create or replace function public.barber_admin_pay_refund(p_token uuid,p_refund_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','pg_temp' as $$
declare v_actor record; v_refund public.barber_sale_refunds; v_sale public.barber_sales;
 v_visit public.barber_loyalty_visits; v_reward public.barber_loyalty_rewards; v_paid numeric(12,2);
begin
 select * into v_actor from public.barber_session_identity(p_token);
 if v_actor.role<>'ADMINISTRADOR' then raise exception 'Solo ADMIN puede confirmar devoluciones' using errcode='42501'; end if;
 select * into v_refund from public.barber_sale_refunds where id=p_refund_id for update;
 if not found then raise exception 'Devolución no encontrada' using errcode='P0002'; end if;
 if v_refund.status<>'approved' then raise exception 'Solo se pueden pagar devoluciones aprobadas' using errcode='23514'; end if;
 select * into v_sale from public.barber_sales where id=v_refund.sale_id for update;
 update public.barber_sale_refunds set status='paid',paid_at=now() where id=p_refund_id returning * into v_refund;
 select coalesce(sum(amount),0) into v_paid from public.barber_sale_refunds where sale_id=v_sale.id and status='paid';
 if round(v_paid,2)>=round(v_sale.total,2) then
  update public.barber_sales set payment_status='refunded' where id=v_sale.id;
  select * into v_visit from public.barber_loyalty_visits where sale_id=v_sale.id and status='active' for update;
  if found then
   update public.barber_loyalty_visits set status='reversed',reversed_at=now(),reversed_by=null,reversal_reason='Devolución total de la venta '||v_sale.folio where id=v_visit.id;
   select * into v_reward from public.barber_loyalty_rewards where customer_id=v_visit.customer_id and cycle_number=v_visit.cycle_number for update;
   if found and v_reward.status='redeemed' then
    update public.barber_loyalty_rewards set status='reconciliation_required' where id=v_reward.id;
    insert into public.barber_refund_incidents(sale_id,refund_id,customer_id,reward_id,incident_type,details,created_by_label)
    values(v_sale.id,v_refund.id,v_visit.customer_id,v_reward.id,'redeemed_reward_after_full_refund',
     jsonb_build_object('sale_folio',v_sale.folio,'reward_type',v_reward.reward_type,'note','Conservar historial; requiere conciliación administrativa manual.'),v_actor.display_name)
    on conflict (refund_id,reward_id) where refund_id is not null and reward_id is not null do nothing;
   end if;
  end if;
 else update public.barber_sales set payment_status='partially_refunded' where id=v_sale.id;
 end if;
 insert into public.barber_sale_audit(sale_id,action,before_data,after_data,reason,actor_employee_id,actor_label)
 values(v_sale.id,'refund_paid',to_jsonb(v_sale),to_jsonb(v_refund),v_refund.reason,null,v_actor.display_name);
 return jsonb_build_object('refund_id',v_refund.id,'status',v_refund.status,'sale_id',v_sale.id,
  'payment_status',case when round(v_paid,2)>=round(v_sale.total,2) then 'refunded' else 'partially_refunded' end,
  'total_refunded',v_paid,'loyalty_reversed',exists(select 1 from public.barber_loyalty_visits where sale_id=v_sale.id and status='reversed'));
end $$;

revoke all on function public.barber_admin_request_refund(uuid,bigint,numeric,text,text) from public,anon,authenticated;
revoke all on function public.barber_admin_review_refund(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.barber_admin_pay_refund(uuid,uuid) from public,anon,authenticated;
grant execute on function public.barber_admin_request_refund(uuid,bigint,numeric,text,text) to service_role;
grant execute on function public.barber_admin_review_refund(uuid,uuid,text,text) to service_role;
grant execute on function public.barber_admin_pay_refund(uuid,uuid) to service_role;
