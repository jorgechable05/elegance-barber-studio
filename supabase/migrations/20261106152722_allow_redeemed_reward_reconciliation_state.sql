alter table public.barber_loyalty_rewards drop constraint if exists barber_loyalty_rewards_check;
alter table public.barber_loyalty_rewards add constraint barber_loyalty_rewards_check
check ((status in ('redeemed','reconciliation_required')) = (redeemed_at is not null));