\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_token uuid := '22222222-2222-4222-8222-222222222277';
  v_walkin_promo uuid := '44444444-4444-4444-8444-444444444401';
  v_booking_promo uuid := '44444444-4444-4444-8444-444444444402';
  v_result jsonb;
  v_sale_id bigint;
  v_reservation_id uuid;
  v_total numeric;
  v_subtotal numeric;
  v_discount numeric;
  v_cash numeric;
  v_card numeric;
  v_uses integer;
  v_sales_before bigint;
  v_blocked boolean := false;
BEGIN
  INSERT INTO public.barber_admin_sessions(token,username,expires_at)
  VALUES(v_token,'pos-promo-ci',now()+interval '1 day');

  INSERT INTO public.barber_promotions(
    id,title,description,status,discount_type,discount_value,starts_at,ends_at,
    weekdays,start_time,end_time,source,max_uses,uses_count,approved_at
  ) VALUES
    (v_walkin_promo,'POS walk-in 10%','Synthetic isolated promotion','approved','percent',10,
     now()-interval '1 day',now()+interval '2 days',ARRAY[0,1,2,3,4,5,6]::smallint[],
     null,null,'manual',2,0,now()),
    (v_booking_promo,'Booked 10%','Synthetic booking promotion','approved','percent',10,
     now()-interval '1 day',now()+interval '2 days',ARRAY[0,1,2,3,4,5,6]::smallint[],
     null,null,'manual',null,1,now());
  INSERT INTO public.barber_promotion_services(promotion_id,service_id)
  VALUES(v_walkin_promo,1),(v_booking_promo,1);

  -- Walk-in cash sale: subtotal 160, promotion discount 16, total 144, change 6.
  v_result:=public.barber_admin_create_walkin_sale_with_promotion(
    v_token,'POS QA Cash',1,1,'Efectivo',150,null,null,v_walkin_promo
  );
  IF round((v_result->>'subtotal')::numeric,2)<>160
    OR round((v_result->>'descuento')::numeric,2)<>16
    OR round((v_result->>'total')::numeric,2)<>144
    OR round((v_result->>'cambio')::numeric,2)<>6
    OR v_result->>'promotion_title'<>'POS walk-in 10%' THEN
    RAISE EXCEPTION 'Walk-in promotion price/ticket breakdown is incorrect: %',v_result;
  END IF;
  v_sale_id:=(v_result->>'id')::bigint;
  SELECT total,subtotal,descuento INTO v_total,v_subtotal,v_discount
  FROM public.barber_sales WHERE id=v_sale_id;
  IF v_total<>144 OR v_subtotal<>160 OR v_discount<>16 THEN
    RAISE EXCEPTION 'Walk-in promotion was not persisted in sales ledger';
  END IF;
  SELECT uses_count INTO v_uses FROM public.barber_promotions WHERE id=v_walkin_promo;
  IF v_uses<>1 THEN RAISE EXCEPTION 'Expected one use after walk-in sale, got %',v_uses; END IF;

  -- Mixed payment validates the discounted total, not the pre-discount subtotal.
  v_result:=public.barber_admin_create_walkin_sale_with_promotion(
    v_token,'POS QA Mixed',1,1,'Mixto',144,100,44,v_walkin_promo
  );
  IF round((v_result->>'total')::numeric,2)<>144
    OR round((v_result->>'efectivo')::numeric,2)<>100
    OR round((v_result->>'tarjeta')::numeric,2)<>44 THEN
    RAISE EXCEPTION 'Mixed payment did not retain the promotion total/split: %',v_result;
  END IF;
  v_sale_id:=(v_result->>'id')::bigint;
  SELECT efectivo,tarjeta INTO v_cash,v_card FROM public.barber_sales WHERE id=v_sale_id;
  IF v_cash<>100 OR v_card<>44 THEN RAISE EXCEPTION 'Mixed payment split not persisted'; END IF;

  -- Invalid split must roll back and cannot consume another promotion use.
  SELECT count(*) INTO v_sales_before FROM public.barber_sales;
  v_blocked:=false;
  BEGIN
    PERFORM public.barber_admin_create_walkin_sale_with_promotion(
      v_token,'POS QA Invalid',1,1,'Mixto',150,100,50,null
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Invalid mixed split was accepted'; END IF;
  IF (SELECT count(*) FROM public.barber_sales)<>v_sales_before THEN
    RAISE EXCEPTION 'Invalid mixed split left a persisted sale';
  END IF;

  -- Appointment-time promotion metadata must be present on the completed sale/ticket.
  INSERT INTO public.reservas(
    nombre,telefono,wa,serv,servicio,precio,barbero,fecha,hora,estado,stock_key,
    promotion_id,servicio_id,precio_base
  ) VALUES (
    'POS QA Booked','9990000000','9990000000','Corte Clásico','Corte Clásico',144,
    'EdgarMay',current_date,'13:30','confirmada','ci-pos-booked',
    v_booking_promo,1,160
  ) RETURNING id INTO v_reservation_id;

  v_result:=public.barber_admin_create_sale_with_promotion_info(
    v_token,v_reservation_id,'Efectivo',150
  );
  IF round((v_result->>'total')::numeric,2)<>144
    OR round((v_result->>'subtotal')::numeric,2)<>160
    OR round((v_result->>'descuento')::numeric,2)<>16
    OR v_result->>'promotion_title'<>'Booked 10%' THEN
    RAISE EXCEPTION 'Reserved sale wrapper lost booking-time promotion detail: %',v_result;
  END IF;
  v_sale_id:=(v_result->>'id')::bigint;
  IF NOT EXISTS(
    SELECT 1 FROM public.barber_sales
    WHERE id=v_sale_id AND promotion_id=v_booking_promo
      AND subtotal=160 AND descuento=16 AND total=144
  ) THEN RAISE EXCEPTION 'Booking promotion metadata not persisted on reserved sale'; END IF;
END $$;
ROLLBACK;
