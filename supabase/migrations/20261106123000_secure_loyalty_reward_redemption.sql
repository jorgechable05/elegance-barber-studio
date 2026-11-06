-- Bind reward redemption to the validated employee session, never to browser-supplied identity.
create or replace function public.barber_loyalty_redeem_reward(
  p_token uuid,
  p_reward_id uuid,
  p_employee text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_actor record;
  v_reward public.barber_loyalty_rewards;
begin
  select * into v_actor from public.barber_session_identity(p_token);

  if v_actor.role not in ('DUEÑO','ADMINISTRADOR','ENCARGADO') then
    raise exception 'Tu rol no puede entregar premios de fidelidad' using errcode='42501';
  end if;

  select * into v_reward
    from public.barber_loyalty_rewards
   where id = p_reward_id
   for update;

  if not found then
    raise exception 'Premio no encontrado' using errcode='P0002';
  end if;

  if v_reward.status <> 'pending' then
    raise exception 'El premio ya fue entregado, cancelado o requiere conciliación' using errcode='23514';
  end if;

  update public.barber_loyalty_rewards
     set status = 'redeemed',
         redeemed_at = now(),
         redeemed_by = v_actor.display_name
   where id = p_reward_id;

  return jsonb_build_object(
    'redeemed', true,
    'customer_id', v_reward.customer_id,
    'cycle_number', v_reward.cycle_number,
    'reward_type', v_reward.reward_type,
    'redeemed_by', v_actor.display_name
  );
end;
$function$;

revoke all on function public.barber_loyalty_redeem_reward(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.barber_loyalty_redeem_reward(uuid,uuid,text) to service_role;
