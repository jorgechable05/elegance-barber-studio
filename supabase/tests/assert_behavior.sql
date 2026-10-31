\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_promo uuid := '11111111-1111-4111-8111-111111111111';
  v_pending uuid := '11111111-1111-4111-8111-111111111112';
  v_expired_token uuid := '22222222-2222-4222-8222-222222222221';
  v_revoked_token uuid := '22222222-2222-4222-8222-222222222222';
  v_date date;
  v_reservation uuid;
  v_price integer;
  v_uses integer;
  v_blocked boolean;
  v_status text;
BEGIN
  v_date := current_date + 1;
  WHILE extract(isodow FROM v_date) = 7 LOOP v_date := v_date + 1; END LOOP;

  INSERT INTO public.barber_promotions(
    id,title,description,status,discount_type,discount_value,starts_at,ends_at,
    weekdays,source,max_uses,uses_count
  ) VALUES (
    v_promo,'CI special-price rounding','Temporary isolated test','approved',
    'fixed_price',149.50,now()-interval '1 day',now()+interval '14 days',
    ARRAY[0,1,2,3,4,5,6]::smallint[],'manual',1,0
  );
  INSERT INTO public.barber_promotion_services(promotion_id,service_id) VALUES (v_promo,1);

  v_reservation := public.barber_create_reservation_with_promotion(
    1,v_date,'13:30','CI price test','',1,'5550000000',v_promo
  );
  SELECT precio INTO v_price FROM public.reservas WHERE id=v_reservation;
  SELECT uses_count INTO v_uses FROM public.barber_promotions WHERE id=v_promo;
  IF v_price <> 150 THEN
    RAISE EXCEPTION 'Price rounding mismatch: expected 150 whole pesos, got %',v_price;
  END IF;
  IF v_uses <> 1 THEN
    RAISE EXCEPTION 'Promotion usage count mismatch: expected 1, got %',v_uses;
  END IF;

  v_blocked := false;
  BEGIN
    PERFORM public.barber_create_reservation_with_promotion(
      2,v_date,'13:30','CI exhausted promo','',1,'5550000001',v_promo
    );
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Exhausted single-use promotion was accepted'; END IF;
  SELECT count(*) INTO v_uses FROM public.reservas WHERE promotion_id=v_promo;
  IF v_uses <> 1 THEN RAISE EXCEPTION 'Expected one reservation for single-use promotion, found %',v_uses; END IF;

  v_reservation := public.barber_create_reservation_with_promotion(
    2,v_date,'15:00','CI base-price test','',2,'5550000002',NULL
  );
  SELECT precio INTO v_price FROM public.reservas WHERE id=v_reservation;
  IF v_price <> 180 THEN RAISE EXCEPTION 'Base price mismatch: expected 180, got %',v_price; END IF;

  INSERT INTO public.barber_promotions(
    id,title,description,status,discount_type,discount_value,starts_at,ends_at,
    weekdays,source,max_uses,uses_count
  ) VALUES (
    v_pending,'CI pending suggestion','Must not be public','pending_review',
    'percent',10,now()-interval '1 day',now()+interval '14 days',
    ARRAY[0,1,2,3,4,5,6]::smallint[],'daily_suggestion',5,0
  );
  INSERT INTO public.barber_promotion_services(promotion_id,service_id) VALUES (v_pending,2);
  v_blocked := false;
  BEGIN
    PERFORM public.barber_create_reservation_with_promotion(
      1,v_date,'16:00','CI pending promo','',2,'5550000003',v_pending
    );
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Pending suggestion was accepted at booking'; END IF;

  INSERT INTO public.barber_admin_sessions(token,username,expires_at,revoked_at)
    VALUES (v_expired_token,'ci-expired',now()-interval '1 minute',NULL);
  INSERT INTO public.barber_admin_sessions(token,username,expires_at,revoked_at)
    VALUES (v_revoked_token,'ci-revoked',now()+interval '1 day',now());

  v_blocked := false;
  BEGIN
    PERFORM public.barber_promotion_admin_save(
      v_expired_token,NULL,'CI forbidden save','','percent',10,
      now(),now()+interval '1 day',ARRAY[0,1,2,3,4,5,6]::smallint[],
      NULL,NULL,ARRAY[1]::integer[],NULL
    );
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Expired admin session was accepted by save RPC'; END IF;
  IF EXISTS (SELECT 1 FROM public.barber_promotions WHERE title='CI forbidden save') THEN
    RAISE EXCEPTION 'Expired session wrote a promotion';
  END IF;

  v_blocked := false;
  BEGIN
    PERFORM public.barber_promotion_admin_review(v_revoked_token,v_pending,'approved');
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Revoked admin session was accepted by review RPC'; END IF;
  SELECT status INTO v_status FROM public.barber_promotions WHERE id=v_pending;
  IF v_status <> 'pending_review' THEN
    RAISE EXCEPTION 'Revoked session changed promotion state to %',v_status;
  END IF;
END $$;
ROLLBACK;
