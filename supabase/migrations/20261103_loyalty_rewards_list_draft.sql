-- Staff-only pending and historical reward list for Admin/POS.
create or replace function public.barber_loyalty_list_rewards(p_token uuid)
returns table(
  reward_id uuid, customer_name text, phone_masked text, cycle_number integer,
  status text, earned_at timestamptz, redeemed_at timestamptz, redeemed_by text
)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists(select 1 from public.barber_admin_sessions s
    where s.token=p_token and s.revoked_at is null and s.expires_at>now()) then
    raise exception 'Sesión de personal inválida o vencida' using errcode='28000';
  end if;
  return query
  select r.id,c.full_name,'••••'||right(c.phone,4),r.cycle_number,
    r.status,r.earned_at,r.redeemed_at,r.redeemed_by
  from public.barber_loyalty_rewards r
  join public.barber_loyalty_customers c on c.id=r.customer_id
  order by case when r.status='pending' then 0 else 1 end,r.earned_at desc;
end;
$$;
revoke all on function public.barber_loyalty_list_rewards(uuid) from public;
grant execute on function public.barber_loyalty_list_rewards(uuid) to anon,authenticated;
