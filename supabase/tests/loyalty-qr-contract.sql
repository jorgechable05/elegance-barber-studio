\set ON_ERROR_STOP on
\i supabase/tests/fixture.sql
\i supabase/tests/legacy_ui_rpc_fixture.sql
\i supabase/migrations/20261103_loyalty_qr_program_draft.sql
\i supabase/migrations/20261103_loyalty_rewards_list_draft.sql

insert into public.barber_admin_sessions(token,username,expires_at)
values('11111111-1111-4111-8111-111111111111','qa-loyalty',now()+interval '1 day');

do $$
declare
  v_customer uuid;
  v_sale bigint;
  v_result jsonb;
  v_count integer;
  v_cycle integer;
  i integer;
begin
  perform public.barber_loyalty_register_customer('Cliente QA','+52 999 123 4567',true);
  select id into v_customer from public.barber_loyalty_customers where phone='9991234567';
  if v_customer is null then raise exception 'Registration failed or phone normalization failed'; end if;

  perform public.barber_loyalty_register_customer('Nombre duplicado','9991234567',true);
  if (select count(*) from public.barber_loyalty_customers where phone='9991234567')<>1 then
    raise exception 'Duplicate phone created a second customer';
  end if;

  for i in 1..5 loop
    insert into public.barber_sales(cliente,servicio,barbero,total,metodo,recibido)
    values('Cliente QA','Corte clásico','EdgarMay',160,'Efectivo',160)
    returning id into v_sale;
    v_result:=public.barber_loyalty_record_visit(
      '11111111-1111-4111-8111-111111111111',v_customer,v_sale,'QA Staff'
    );
    if (v_result->>'visit_number')::integer<>i then
      raise exception 'Expected visit %, got %',i,v_result;
    end if;
  end loop;

  if not exists(select 1 from public.barber_loyalty_rewards
    where customer_id=v_customer and cycle_number=1 and status='pending') then
    raise exception 'Fifth visit did not create a pending courtesy reward';
  end if;

  v_result:=public.barber_loyalty_record_visit(
    '11111111-1111-4111-8111-111111111111',v_customer,v_sale,'QA Staff'
  );
  if (v_result->>'already_recorded')::boolean is not true then
    raise exception 'Duplicate sale was not idempotent';
  end if;

  perform public.barber_loyalty_redeem_reward(
    '11111111-1111-4111-8111-111111111111',
    (select id from public.barber_loyalty_rewards where customer_id=v_customer and cycle_number=1),
    'QA Staff'
  );

  insert into public.barber_sales(cliente,servicio,barbero,total,metodo,recibido)
  values('Cliente QA','Corte clásico','EdgarMay',160,'Efectivo',160)
  returning id into v_sale;
  v_result:=public.barber_loyalty_record_visit(
    '11111111-1111-4111-8111-111111111111',v_customer,v_sale,'QA Staff'
  );
  if (v_result->>'cycle_number')::integer<>2 or (v_result->>'visit_number')::integer<>1 then
    raise exception 'Next cycle did not restart at 1/5: %',v_result;
  end if;

  select cycle_number,visits_in_cycle into v_cycle,v_count
  from public.barber_loyalty_lookup_customer(
    '11111111-1111-4111-8111-111111111111','9991234567'
  );
  if v_cycle<>2 or v_count<>1 then raise exception 'Incorrect progress after reward redemption'; end if;

  if has_table_privilege('anon','public.barber_loyalty_customers','SELECT') then
    raise exception 'anon unexpectedly has direct customer table access';
  end if;
end $$;

select 'LOYALTY_QA_PASS' as result;
