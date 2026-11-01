\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_token uuid := '22222222-2222-4222-8222-222222222255';
  v_bad_token uuid := '22222222-2222-4222-8222-222222222256';
  v_source uuid := '33333333-3333-4333-8333-333333333301';
  v_delete uuid := '33333333-3333-4333-8333-333333333302';
  v_copy public.barber_promotions;
  v_settings public.barber_promotion_suggestion_settings;
  v_created integer;
  v_count bigint;
  v_revenue numeric;
  v_blocked boolean := false;
BEGIN
  INSERT INTO public.barber_admin_sessions(token,username,expires_at)
  VALUES(v_token,'lifecycle-ci',now()+interval '1 day');

  INSERT INTO public.barber_promotions(
    id,title,description,status,discount_type,discount_value,starts_at,ends_at,
    weekdays,start_time,end_time,source,max_uses,uses_count,approved_at
  ) VALUES
    (v_source,'Lifecycle source','Synthetic test','approved','percent',10,now()-interval '1 hour',
     now()+interval '1 day',ARRAY[0,1,2,3,4,5,6]::smallint[],'13:30','20:30','manual',10,1,now()),
    (v_delete,'Unused offer','Synthetic test','draft','percent',5,now()+interval '1 day',
     now()+interval '2 days',ARRAY[0,1,2,3,4,5,6]::smallint[],null,null,'manual',null,0,null);
  INSERT INTO public.barber_promotion_services(promotion_id,service_id)
  VALUES(v_source,1),(v_delete,2);

  UPDATE public.barber_promotion_suggestion_settings
    SET enabled=true,discount_percent=12,max_suggestions_per_day=2,
        opportunity_window_hours=36,updated_at=now()
    WHERE id=1;
  SELECT * INTO v_settings
    FROM public.barber_promotion_suggestion_settings_admin_get(v_token);
  IF v_settings.discount_percent<>12 OR v_settings.max_suggestions_per_day<>2
     OR v_settings.opportunity_window_hours<>36 THEN
    RAISE EXCEPTION 'Daily suggestion settings did not round-trip';
  END IF;

  v_copy := public.barber_promotion_admin_duplicate(v_token,v_source);
  IF v_copy.status<>'draft' OR v_copy.approved_at IS NOT NULL OR v_copy.uses_count<>0 THEN
    RAISE EXCEPTION 'Duplicated promotion must be a clean, unapproved draft';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.barber_promotion_services
                 WHERE promotion_id=v_copy.id AND service_id=1) THEN
    RAISE EXCEPTION 'Promotion duplicate did not retain selected services';
  END IF;

  INSERT INTO public.reservas(nombre,telefono,wa,serv,servicio,precio,barbero,fecha,hora,estado,stock_key,promotion_id)
  VALUES('CI metrics','9990000000','9990000000','Corte','Corte',144,'EdgarMay',current_date,'13:30','pendiente','ci-metrics',v_source);
  SELECT m.reservation_count,m.booked_revenue INTO v_count,v_revenue
    FROM public.barber_promotions_admin_metrics(v_token) m WHERE m.id=v_source;
  IF v_count<>1 OR v_revenue<>144 THEN
    RAISE EXCEPTION 'Metrics do not match the synthetic reservation: count %, amount %',v_count,v_revenue;
  END IF;

  IF NOT public.barber_promotion_admin_delete(v_token,v_delete) THEN
    RAISE EXCEPTION 'Unused promotion should be deleted successfully';
  END IF;
  BEGIN
    PERFORM public.barber_promotion_admin_delete(v_token,v_source);
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Promotion with reservation history must be protected from hard deletion';
  END IF;

  -- Scheduled/manual generator must consume the saved settings while keeping every
  -- suggestion pending review. Rollback at end ensures all fixtures disappear.
  DELETE FROM public.barber_promotions
  WHERE source='daily_suggestion'
    AND (created_at at time zone 'America/Merida')::date=(now() at time zone 'America/Merida')::date;
  v_created := public.barber_promotions_generate_daily_suggestions_internal();
  IF v_created<1 OR v_created>2 THEN
    RAISE EXCEPTION 'Configured generator should create at most two suggestions, got %',v_created;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.barber_promotions
    WHERE source='daily_suggestion'
      AND (created_at at time zone 'America/Merida')::date=(now() at time zone 'America/Merida')::date
      AND (status<>'pending_review' OR discount_value<>12)
  ) THEN
    RAISE EXCEPTION 'Generator ignored configured discount or published a suggestion';
  END IF;
  IF public.barber_promotions_generate_daily_suggestions_internal()<>0 THEN
    RAISE EXCEPTION 'Daily generator should be idempotent';
  END IF;

  v_blocked := false;
  BEGIN
    PERFORM public.barber_promotions_admin_metrics(v_bad_token);
  EXCEPTION WHEN SQLSTATE '28000' THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Metrics RPC accepted an invalid admin session';
  END IF;
END $$;
ROLLBACK;
