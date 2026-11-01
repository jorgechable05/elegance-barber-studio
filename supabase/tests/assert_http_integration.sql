-- CI ONLY: assert results written by rpc-http-integration-tests.mjs, then clean them up.
-- This file must run only against the disposable GitHub Actions PostgreSQL database.
DO $$
DECLARE
  v_promo_id uuid;
  v_price integer;
  v_uses integer;
  v_reservations integer;
BEGIN
  SELECT id, uses_count INTO v_promo_id, v_uses
  FROM public.barber_promotions
  WHERE title = 'CI HTTP promotion integration' AND source = 'manual';

  IF v_promo_id IS NULL THEN
    RAISE EXCEPTION 'HTTP integration promotion was not persisted by the RPC';
  END IF;
  IF v_uses <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one promotion use after HTTP RPC, got %', v_uses;
  END IF;

  SELECT precio INTO v_price
  FROM public.reservas
  WHERE nombre = 'CI HTTP promotion reservation'
    AND promotion_id = v_promo_id;

  IF v_price <> 144 THEN
    RAISE EXCEPTION 'Expected HTTP-created reservation price 144, got %', v_price;
  END IF;

  SELECT count(*) INTO v_reservations
  FROM public.reservas
  WHERE promotion_id = v_promo_id;

  IF v_reservations <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one reservation linked to HTTP promotion, got %', v_reservations;
  END IF;

  RAISE NOTICE 'PASS: actual PostgREST RPC persisted price %, uses %, reservations %',
    v_price, v_uses, v_reservations;

  DELETE FROM public.reservas
  WHERE promotion_id = v_promo_id
     OR nombre IN ('CI HTTP promotion reservation', 'CI HTTP exhausted promotion');
  DELETE FROM public.barber_promotions WHERE id = v_promo_id;
  DELETE FROM public.barber_admin_sessions WHERE username = 'local-qa-user';
END $$;
