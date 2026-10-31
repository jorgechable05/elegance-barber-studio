import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const base = new URL(".", import.meta.url);
const util = await import(pathToFileURL(resolve(new URL(".", import.meta.url).pathname, "customer-promotion-utils.js")));
const adminSource = await readFile(new URL("./admin-promotions.js", base), "utf8");

test("Admin adapter is an additive module and does not replace existing page", () => {
  assert.match(adminSource, /mountPromotionsAdmin/);
  assert.match(adminSource, /barber_services_admin_list/);
  assert.match(adminSource, /barber_promotion_admin_review/);
  assert.match(adminSource, /pending_review/);
});

test("approved, valid promotions apply and pending suggestions do not", () => {
  const p = {
    status: "approved", service_ids: [1], starts_at: "2026-10-01T00:00:00-06:00",
    ends_at: "2026-11-30T23:59:59-06:00", weekdays: [0,1,2,3,4,5,6],
    start_time: "13:30:00", end_time: "20:30:00", discount_type:"percent",discount_value:10
  };
  assert.equal(util.isPromotionApplicable(p, 1, "2026-10-31T15:00:00-06:00"), true);
  assert.equal(util.isPromotionApplicable({...p,status:"pending_review"},1,"2026-10-31T15:00:00-06:00"), false);
});

test("calculation rejects invalid discounts", () => {
  assert.equal(util.calculatePromotionPrice(160,{discount_type:"percent",discount_value:10}),144);
  assert.throws(()=>util.calculatePromotionPrice(160,{discount_type:"percent",discount_value:101}),RangeError);
});
