#!/usr/bin/env bash
set -euo pipefail

PROMO_ID="33333333-3333-4333-8333-333333333333"
TEST_DATE="$(psql -X -A -t -q -v ON_ERROR_STOP=1 -c "SELECT d::date FROM generate_series(current_date + 1, current_date + 8, interval '1 day') AS d WHERE extract(isodow FROM d) <> 7 LIMIT 1")"
if [[ -z "$TEST_DATE" ]]; then echo "Could not choose a non-Sunday test date" >&2; exit 1; fi

psql -X -v ON_ERROR_STOP=1 <<SQL
INSERT INTO public.barber_promotions(
  id,title,description,status,discount_type,discount_value,starts_at,ends_at,
  weekdays,source,max_uses,uses_count
) VALUES (
  '$PROMO_ID','CI concurrent single use','Isolated concurrency test','approved',
  'percent',10,now()-interval '1 day',now()+interval '14 days',
  ARRAY[0,1,2,3,4,5,6]::smallint[],'manual',1,0
);
INSERT INTO public.barber_promotion_services(promotion_id,service_id)
VALUES ('$PROMO_ID',2);
SQL

reserve() {
  local barber_id="$1"
  psql -X -v ON_ERROR_STOP=1 -q <<SQL
BEGIN;
SELECT public.barber_create_reservation_with_promotion(
  $barber_id,'$TEST_DATE'::date,'14:00','CI concurrent reservation','',
  2,'5550000010','$PROMO_ID'::uuid
);
SELECT pg_sleep(2);
COMMIT;
SQL
}

set +e
reserve 1 >/tmp/elegance-promo-concurrent-a.log 2>&1 &
PID_A=$!
sleep 0.25
reserve 2 >/tmp/elegance-promo-concurrent-b.log 2>&1
STATUS_B=$?
wait "$PID_A"
STATUS_A=$?
set -e

SUCCESSES=0
[[ "$STATUS_A" -eq 0 ]] && SUCCESSES=$((SUCCESSES+1))
[[ "$STATUS_B" -eq 0 ]] && SUCCESSES=$((SUCCESSES+1))
if [[ "$SUCCESSES" -ne 1 ]]; then
  echo "Expected exactly one concurrent reservation to succeed; got $SUCCESSES" >&2
  cat /tmp/elegance-promo-concurrent-a.log /tmp/elegance-promo-concurrent-b.log >&2
  exit 1
fi

psql -X -v ON_ERROR_STOP=1 <<SQL
DO \$\$
DECLARE v_uses integer; v_reservations integer;
BEGIN
  SELECT uses_count INTO v_uses FROM public.barber_promotions WHERE id='$PROMO_ID';
  SELECT count(*) INTO v_reservations FROM public.reservas WHERE promotion_id='$PROMO_ID';
  IF v_uses <> 1 OR v_reservations <> 1 THEN
    RAISE EXCEPTION 'Concurrent use cap failed: uses %, reservations %',v_uses,v_reservations;
  END IF;
END
\$\$;
SQL

echo "PASS: exactly one of two concurrent reservations consumed the single promotion use."
