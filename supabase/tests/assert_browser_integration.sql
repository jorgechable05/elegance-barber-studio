-- CI ONLY: verify the local Playwright flow persisted the expected test reservation, then clean it up.
DO $$
DECLARE
  v_promo uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_price integer;
  v_uses integer;
  v_reservations integer;
BEGIN
  SELECT uses_count INTO v_uses
  FROM public.barber_promotions
  WHERE id = v_promo AND title = 'CI browser promotion integration' AND status = 'approved';
  IF NOT FOUND THEN RAISE EXCEPTION 'Browser test promotion is missing'; END IF;
  IF v_uses <> 1 THEN RAISE EXCEPTION 'Expected browser RPC to consume one promotion use, got %', v_uses; END IF;

  SELECT precio INTO v_price
  FROM public.reservas
  WHERE nombre = 'Cliente QA local' AND promotion_id = v_promo;
  IF v_price <> 144 THEN
    RAISE EXCEPTION 'Expected browser-created reservation price 144, got %', v_price;
  END IF;

  SELECT count(*) INTO v_reservations
  FROM public.reservas WHERE promotion_id = v_promo;
  IF v_reservations <> 1 THEN
    RAISE EXCEPTION 'Expected one browser-created reservation, got %', v_reservations;
  END IF;

  RAISE NOTICE 'PASS: Playwright browser RPC persisted reservation price %, promotion uses %, rows %',
    v_price, v_uses, v_reservations;

  DELETE FROM public.reservas WHERE promotion_id = v_promo OR nombre = 'Cliente QA local';
  DELETE FROM public.barber_promotions WHERE id = v_promo;
  DELETE FROM public.barber_admin_sessions WHERE username = 'local-qa-user';
END $$;
