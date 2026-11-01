\set ON_ERROR_STOP on
DO $$
DECLARE n integer; bad integer;
BEGIN
  SELECT count(*) INTO n FROM public.barber_services;
  IF n <> 9 THEN RAISE EXCEPTION 'Expected 9 legacy service IDs, got %', n; END IF;
  SELECT count(*) INTO bad FROM public.barber_services
    WHERE id NOT BETWEEN 1 AND 9 OR price < 0 OR duration_minutes < 5;
  IF bad <> 0 THEN RAISE EXCEPTION 'Invalid seeded services: %', bad; END IF;
  IF (SELECT price FROM public.barber_services WHERE id=1) <> 160 THEN
    RAISE EXCEPTION 'Legacy service 1 price changed';
  END IF;
  IF (SELECT price FROM public.barber_services WHERE id=9) <> 550 THEN
    RAISE EXCEPTION 'Legacy service 9 price changed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='barber_promotions_public') THEN
    RAISE EXCEPTION 'Public promotion RPC missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='barber_promotion_admin_save') THEN
    RAISE EXCEPTION 'Admin promotion save RPC missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='barber_create_reservation_with_promotion') THEN
    RAISE EXCEPTION 'Compatible reservation-with-promotion RPC missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='barber_sales' AND column_name='efectivo')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='barber_sales' AND column_name='tarjeta') THEN
    RAISE EXCEPTION 'Payment split columns missing';
  END IF;
  IF to_regprocedure('public.barber_admin_create_sale(uuid,uuid,text,numeric,numeric,numeric)') IS NULL THEN
    RAISE EXCEPTION 'Mixed-payment reservation RPC overload missing';
  END IF;
  IF to_regprocedure('public.barber_admin_create_walkin_sale(uuid,text,integer,integer,text,numeric,numeric,numeric)') IS NULL THEN
    RAISE EXCEPTION 'Mixed-payment walk-in RPC overload missing';
  END IF;
  IF has_function_privilege('anon','public.barber_promotions_generate_daily_suggestions_internal()','EXECUTE')
     OR has_function_privilege('authenticated','public.barber_promotions_generate_daily_suggestions_internal()','EXECUTE') THEN
    RAISE EXCEPTION 'Internal daily suggestion function is exposed to client roles';
  END IF;
END $$;
