-- CI ONLY: one synthetic approved promotion for the local Playwright/RPC integration.
-- Never run this fixture against a hosted Supabase project.
INSERT INTO public.barber_promotions(
  id,title,description,status,discount_type,discount_value,starts_at,ends_at,
  weekdays,start_time,end_time,source,max_uses,uses_count,approved_at
) VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'CI browser promotion integration',
  'Temporary local Playwright fixture; not a real customer offer',
  'approved','percent',10,
  now()-interval '1 day',now()+interval '14 days',
  ARRAY[0,1,2,3,4,5,6]::smallint[],
  '13:00:00','21:00:00','manual',NULL,0,now()
);
INSERT INTO public.barber_promotion_services(promotion_id,service_id)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1);
