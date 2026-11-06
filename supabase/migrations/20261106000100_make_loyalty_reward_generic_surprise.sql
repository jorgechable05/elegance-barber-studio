-- Keep the fifth-visit reward flexible; the barber shop may choose the surprise.
ALTER TABLE public.barber_loyalty_rewards
  ALTER COLUMN reward_type SET DEFAULT 'sorpresa_especial';
