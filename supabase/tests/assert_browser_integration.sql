-- CI ONLY: verify the local Playwright flow persisted the expected test reservation, then clean it up.
DO $$
DECLARE
  v_promo uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_price integer;
  v_uses integer;
  v_reservations integer;
  v_pos_sales integer;
  v_mixed_sales integer;
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

  -- The local POS Playwright path now calls the real CI-only sale contract.
  SELECT count(*) INTO v_pos_sales FROM public.barber_sales WHERE cliente='Cliente QA local';
  IF v_pos_sales <> 4 THEN
    RAISE EXCEPTION 'Expected four isolated POS walk-in sales, got %',v_pos_sales;
  END IF;
  SELECT count(*) INTO v_mixed_sales
    FROM public.barber_sales
   WHERE cliente='Cliente QA local' AND metodo='Mixto'
     AND efectivo=100 AND tarjeta=60 AND total=160
     AND subtotal=160 AND descuento=0;
  IF v_mixed_sales <> 1 THEN
    RAISE EXCEPTION 'Expected one persisted mixed POS payment split with ticket breakdown, got %',v_mixed_sales;
  END IF;
  RAISE NOTICE 'PASS: POS test sales and mixed-payment split persisted in isolated PostgreSQL';

  DELETE FROM public.barber_sales WHERE cliente='Cliente QA local';
  DELETE FROM public.reservas WHERE promotion_id = v_promo OR nombre = 'Cliente QA local';
  DELETE FROM public.barber_promotions WHERE id = v_promo;
  DELETE FROM public.barber_admin_sessions WHERE username = 'local-qa-user';
END $$;
