\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_first integer;
  v_second integer;
  v_today date := (now() at time zone 'America/Merida')::date;
  v_rows integer;
  v_job_exists boolean;
BEGIN
  IF has_function_privilege('anon',
       'public.barber_promotions_generate_daily_suggestions_internal()', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.barber_promotions_generate_daily_suggestions_internal()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Internal scheduler RPC must not be executable by anon/authenticated';
  END IF;
  IF NOT has_function_privilege('service_role',
       'public.barber_promotions_generate_daily_suggestions_internal()', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must be able to execute the internal scheduler RPC';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    EXECUTE $query$
      SELECT EXISTS (
        SELECT 1 FROM cron.job
        WHERE jobname='elegance-promotion-suggestions-daily'
          AND schedule='0 12 * * *'
          AND command='select public.barber_promotions_generate_daily_suggestions_internal();'
      )
    $query$ INTO v_job_exists;
    IF NOT v_job_exists THEN
      RAISE EXCEPTION 'pg_cron is installed but the daily promotion job is missing or misconfigured';
    END IF;
  END IF;

  v_first := public.barber_promotions_generate_daily_suggestions_internal();
  IF v_first < 1 OR v_first > 3 THEN
    RAISE EXCEPTION 'Expected 1-3 pending suggestions on first run, got %', v_first;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.barber_promotions
    WHERE source='daily_suggestion'
      AND (created_at at time zone 'America/Merida')::date=v_today
      AND status <> 'pending_review'
  ) THEN
    RAISE EXCEPTION 'Scheduler published a suggestion without admin approval';
  END IF;

  v_second := public.barber_promotions_generate_daily_suggestions_internal();
  IF v_second <> 0 THEN
    RAISE EXCEPTION 'Scheduler is not idempotent within the same day; second run created % suggestions', v_second;
  END IF;

  SELECT count(*) INTO v_rows
  FROM public.barber_promotions
  WHERE source='daily_suggestion'
    AND (created_at at time zone 'America/Merida')::date=v_today;
  IF v_rows <> v_first THEN
    RAISE EXCEPTION 'Daily suggestion duplicate/count mismatch: first run %, rows %', v_first, v_rows;
  END IF;
END $$;
ROLLBACK;
