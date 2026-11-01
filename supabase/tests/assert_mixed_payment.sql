\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_token uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaa101';
  v_bad_token uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaa102';
  v_res uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbb101';
  v_bad_res uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbb102';
  v_result jsonb;
  v_count integer;
  v_blocked boolean;
  v_sale_id bigint;
BEGIN
  INSERT INTO public.barber_admin_sessions(token,username,expires_at,revoked_at)
  VALUES(v_token,'payment-ci',now()+interval '1 hour',null),
        (v_bad_token,'payment-ci-invalid',now()-interval '1 hour',null);

  INSERT INTO public.reservas(id,nombre,servicio,serv,precio,barbero,fecha,hora,estado)
  VALUES(v_res,'CI mixed reservation','Corte Clásico','Corte Clásico',160,'EdgarMay',current_date+2,'13:30','confirmada'),
        (v_bad_res,'CI invalid split reservation','Corte Clásico','Corte Clásico',160,'EdgarMay',current_date+2,'14:00','confirmada');

  -- A valid split is persisted and returned exactly.
  v_result := public.barber_admin_create_sale(v_token,v_res,'Mixto',160,60,100);
  IF (v_result->>'efectivo')::numeric <> 60 OR (v_result->>'tarjeta')::numeric <> 100
     OR (v_result->>'cambio')::numeric <> 0 THEN
    RAISE EXCEPTION 'Reservation mixed-payment response mismatch: %',v_result;
  END IF;
  v_sale_id := (v_result->>'id')::bigint;
  IF NOT EXISTS(SELECT 1 FROM public.barber_sales WHERE id=v_sale_id AND efectivo=60 AND tarjeta=100 AND total=160) THEN
    RAISE EXCEPTION 'Reservation mixed-payment split was not persisted';
  END IF;

  -- A split that does not equal the total must roll back the base sale and reservation update.
  SELECT count(*) INTO v_count FROM public.barber_sales;
  v_blocked := false;
  BEGIN
    PERFORM public.barber_admin_create_sale(v_token,v_bad_res,'Mixto',160,80,79.99);
  EXCEPTION WHEN OTHERS THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Mismatched reservation split was accepted'; END IF;
  IF (SELECT count(*) FROM public.barber_sales) <> v_count THEN
    RAISE EXCEPTION 'Rejected reservation split left a sale behind';
  END IF;
  IF (SELECT estado FROM public.reservas WHERE id=v_bad_res) <> 'confirmada' THEN
    RAISE EXCEPTION 'Rejected reservation split changed reservation state';
  END IF;

  -- Duplicate reservation charges and invalid sessions must be rejected.
  v_blocked := false;
  BEGIN
    PERFORM public.barber_admin_create_sale(v_token,v_res,'Mixto',160,60,100);
  EXCEPTION WHEN OTHERS THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Duplicate reservation charge was accepted'; END IF;

  v_blocked := false;
  BEGIN
    PERFORM public.barber_admin_create_sale(v_bad_token,v_bad_res,'Mixto',160,60,100);
  EXCEPTION WHEN OTHERS THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Expired session was accepted for reservation payment'; END IF;

  -- Walk-in uses the current service catalogue and persists the split.
  v_result := public.barber_admin_create_walkin_sale(v_token,'CI walk-in',1,1,'Mixto',160,75,85);
  v_sale_id := (v_result->>'id')::bigint;
  IF (v_result->>'efectivo')::numeric <> 75 OR (v_result->>'tarjeta')::numeric <> 85
     OR NOT EXISTS(SELECT 1 FROM public.barber_sales WHERE id=v_sale_id AND efectivo=75 AND tarjeta=85 AND total=160) THEN
    RAISE EXCEPTION 'Walk-in mixed-payment split mismatch: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.barber_sales;
  v_blocked := false;
  BEGIN
    PERFORM public.barber_admin_create_walkin_sale(v_token,'CI invalid walk-in',1,1,'Mixto',160,70,70);
  EXCEPTION WHEN OTHERS THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Mismatched walk-in split was accepted'; END IF;
  IF (SELECT count(*) FROM public.barber_sales) <> v_count THEN
    RAISE EXCEPTION 'Rejected walk-in split left a sale behind';
  END IF;
END $$;
ROLLBACK;
