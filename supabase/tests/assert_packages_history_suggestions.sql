\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_token uuid := 'a1000000-0000-4000-8000-000000000001';
  v_package uuid;
  v_reservation uuid;
  v_sale jsonb;
  v_sale_id bigint;
  v_count bigint;
  v_history record;
  v_created integer;
  v_blocked boolean := false;
BEGIN
  INSERT INTO public.barber_admin_sessions(token,username,expires_at)
    VALUES(v_token,'package-history-ci',now()+interval '1 day');

  UPDATE public.barber_services SET unit_cost=CASE id WHEN 1 THEN 40 WHEN 2 THEN 70 ELSE unit_cost END
    WHERE id in (1,2);
  SELECT * INTO STRICT v_history
    FROM public.barber_service_sales_history_admin_list(v_token,30) WHERE service_id=1;
  IF v_history.sales_count<>0 THEN RAISE EXCEPTION 'Unexpected sales before package QA'; END IF;

  INSERT INTO public.barber_service_packages(name,description,price,is_active)
    VALUES('CI Package Hair + Beard','Synthetic package fixture only',300,true)
    RETURNING id INTO v_package;
  INSERT INTO public.barber_service_package_items(package_id,service_id,position)
    VALUES(v_package,1,0),(v_package,2,1);

  IF NOT EXISTS(SELECT 1 FROM public.barber_service_package_public()
    WHERE id=v_package AND cardinality(service_ids)=2 AND base_total=340 AND price=300 AND duration_minutes=60) THEN
    RAISE EXCEPTION 'Public package RPC did not expose a validated multi-service package';
  END IF;
  v_reservation:=public.barber_create_package_reservation(
    1,current_date+2,'13:00','CI package reservation','5550001001',v_package,null
  );
  IF NOT EXISTS(SELECT 1 FROM public.reservas r
    WHERE r.id=v_reservation AND r.package_id=v_package AND r.duracion_minutos=60
      AND r.precio=300 AND r.precio_base=340 AND r.reservation_group_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Package reservation did not persist total, duration or group id';
  END IF;
  IF (SELECT count(*) FROM public.barber_reservation_items WHERE reservation_id=v_reservation)<>2 THEN
    RAISE EXCEPTION 'Package reservation items were not snapshotted';
  END IF;

  -- A service beginning inside the one-hour package must be rejected, even though
  -- its start time differs from the package start time.
  v_blocked:=false;
  BEGIN
    PERFORM public.barber_create_reservation_with_promotion(
      1,current_date+2,'13:15','CI overlap','',1,'5550001002',null
    );
  EXCEPTION WHEN OTHERS THEN v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Overlapping reservation was not rejected'; END IF;

  v_sale:=public.barber_admin_create_package_sale(
    v_token,'CI walk-in package',v_package,1,'Mixto',300,180,120
  );
  v_sale_id:=(v_sale->>'id')::bigint;
  IF round((v_sale->>'subtotal')::numeric,2)<>340
    OR round((v_sale->>'descuento')::numeric,2)<>40
    OR round((v_sale->>'total')::numeric,2)<>300
    OR round((v_sale->>'efectivo')::numeric,2)<>180
    OR round((v_sale->>'tarjeta')::numeric,2)<>120 THEN
    RAISE EXCEPTION 'Package sale pricing or split is incorrect: %',v_sale;
  END IF;
  IF (SELECT count(*) FROM public.barber_sale_items WHERE sale_id=v_sale_id)<>2 THEN
    RAISE EXCEPTION 'POS package sale items not persisted';
  END IF;
  IF round((SELECT sum(net_amount) FROM public.barber_sale_items WHERE sale_id=v_sale_id),2)<>300 THEN
    RAISE EXCEPTION 'Package line allocation does not equal the paid total';
  END IF;
  IF EXISTS(SELECT 1 FROM public.barber_sale_items WHERE sale_id=v_sale_id AND unit_cost_snapshot IS NULL) THEN
    RAISE EXCEPTION 'Known service costs were not snapshotted at sale time';
  END IF;

  SELECT * INTO STRICT v_history FROM public.barber_service_sales_history_admin_list(v_token,30) WHERE service_id=1;
  IF v_history.sales_count<>1 OR v_history.margin_sample_count<>1 OR v_history.estimated_margin IS NULL THEN
    RAISE EXCEPTION 'Package sale not included in service demand/margin history: %',row_to_json(v_history);
  END IF;
  IF v_history.estimated_margin<>round((SELECT net_amount-unit_cost_snapshot FROM public.barber_sale_items WHERE sale_id=v_sale_id AND service_id=1),2) THEN
    RAISE EXCEPTION 'Calculated margin differs from saved sale-time costs';
  END IF;

  SELECT count(*) INTO v_count FROM public.barber_sales;
  v_blocked:=false;
  BEGIN
    PERFORM public.barber_admin_create_package_sale(v_token,'CI bad split',v_package,1,'Mixto',300,180,119.99);
  EXCEPTION WHEN SQLSTATE '22023' THEN v_blocked:=true;
  END;
  IF NOT v_blocked OR (SELECT count(*) FROM public.barber_sales)<>v_count THEN
    RAISE EXCEPTION 'Invalid package mixed payment persisted a sale';
  END IF;

  -- The historical generator selects from real recorded sales and costs when available;
  -- without a minimum cost sample it explicitly marks each pending offer as heuristic.
  v_created:=public.barber_promotions_generate_daily_suggestions(v_token);
  IF v_created<1 OR v_created>3 THEN RAISE EXCEPTION 'Expected bounded suggestion generation, got %',v_created; END IF;
  IF EXISTS(SELECT 1 FROM public.barber_promotions
    WHERE source='daily_suggestion' AND (created_at at time zone 'America/Merida')::date=(now() at time zone 'America/Merida')::date
      AND (status<>'pending_review' OR suggestion_evidence is null
        OR suggestion_evidence->>'basis' not in ('history_demand_margin','history_demand_only','fallback_low_data'))) THEN
    RAISE EXCEPTION 'Suggestion evidence or unpublished status missing';
  END IF;
  IF public.barber_promotions_generate_daily_suggestions_internal()<>0 THEN
    RAISE EXCEPTION 'Daily suggestions are not idempotent';
  END IF;
END $$;
ROLLBACK;
