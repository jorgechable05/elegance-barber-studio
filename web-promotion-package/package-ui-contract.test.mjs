import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const admin = await readFile(new URL("../web-promotion-package/admin-promotions.js", import.meta.url), "utf8");
const pos = await readFile(new URL("../web-recovery/pos.html", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261102_packages_history_suggestions_draft.sql", import.meta.url), "utf8");

test("Admin exposes package editor and server-side validation contracts", () => {
  assert.match(admin, /Paquetes/);
  assert.match(admin, /barber_service_package_admin_list/);
  assert.match(admin, /barber_service_package_admin_save/);
  assert.match(admin, /al menos dos servicios/);
  assert.match(admin, /Demanda y margen/);
  assert.match(admin, /barber_service_sales_history_admin_list/);
  assert.match(admin, /barber_promotion_history_settings_admin_save/);
  assert.match(admin, /barber_service_unit_cost_admin_save/);
});

test("POS exposes package sale choice, mixed payment, and per-service receipt detail", () => {
  assert.match(pos, /id="wkind"/);
  assert.match(pos, /id="wpackage"/);
  assert.match(pos, /barber_service_package_public/);
  assert.match(pos, /barber_admin_create_package_sale/);
  assert.match(pos, /wcardPart/);
  assert.match(pos, /service_names/);
  assert.match(pos, /INCLUYE:/);
});

test("Database contracts snapshot package pricing and preserve history-based suggestion evidence", () => {
  assert.match(migration, /barber_create_package_reservation/);
  assert.match(migration, /barber_reservation_overlap_guard/);
  assert.match(migration, /barber_reservation_items/);
  assert.match(migration, /barber_sale_items/);
  assert.match(migration, /suggestion_evidence/);
  assert.match(migration, /fallback_low_data/);
  assert.match(migration, /revoke all on function public\.barber_promotions_generate_daily_suggestions_internal\(\) from public,anon,authenticated/);
});
