-- Remove a name-specific exclusion from loyalty visit recording.
-- Every registered customer may earn visits; sale/payment/service checks remain mandatory.
DO $$
DECLARE v_definition text; v_start integer; v_relative_end integer; v_end integer;
BEGIN
  v_definition := pg_get_functiondef('public.barber_loyalty_record_visit(uuid,uuid,bigint,text)'::regprocedure);
  v_start := strpos(v_definition, ' if lower(regexp_replace(trim(v_customer.full_name)');
  v_relative_end := strpos(substring(v_definition FROM v_start), ' select * into v_sale');
  IF v_start = 0 OR v_relative_end = 0 THEN
    RAISE EXCEPTION 'Expected name-specific exclusion was not found; refusing migration';
  END IF;
  v_end := v_start + v_relative_end - 1;
  v_definition := left(v_definition, v_start - 1) || substring(v_definition FROM v_end);
  EXECUTE v_definition;
END $$;
