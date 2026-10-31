import test from "node:test";
import assert from "node:assert/strict";
import {
  isPromotionApplicable,
  calculatePromotionPrice,
  applicablePromotions,
} from "./customer-promotion-utils.js";

const promotion = {
  status: "approved",
  service_ids: [1, "2"],
  starts_at: "2026-10-01T00:00:00-06:00",
  ends_at: "2026-11-30T23:59:59-06:00",
  weekdays: [0,1,2,3,4,5,6],
  start_time: "13:30:00",
  end_time: "20:30:00",
  discount_type: "percent",
  discount_value: 10,
};

test("allows approved promotion for its service, date and time", () => {
  assert.equal(isPromotionApplicable(promotion, 1, "2026-10-31T15:00:00-06:00"), true);
});

test("does not expose pending suggestions", () => {
  assert.equal(isPromotionApplicable({...promotion, status:"pending_review"}, 1, "2026-10-31T15:00:00-06:00"), false);
});

test("rejects outside service, date or hour", () => {
  assert.equal(isPromotionApplicable(promotion, 9, "2026-10-31T15:00:00-06:00"), false);
  assert.equal(isPromotionApplicable({...promotion, ends_at:"2026-10-01T12:00:00-06:00"}, 1, "2026-10-31T15:00:00-06:00"), false);
  assert.equal(isPromotionApplicable(promotion, 1, "2026-10-31T22:00:00-06:00"), false);
});

test("rejects invalid overnight interval rather than applying it by accident", () => {
  assert.equal(isPromotionApplicable({...promotion, start_time:"22:00",end_time:"02:00"}, 1, "2026-10-31T23:00:00-06:00"), false);
});

test("calculates percentage discount to cents", () => {
  assert.equal(calculatePromotionPrice(180, promotion), 162);
});

test("calculates special price and validates limits", () => {
  assert.equal(calculatePromotionPrice(180, {...promotion, discount_type:"fixed_price",discount_value:149.5}), 149.5);
  assert.throws(() => calculatePromotionPrice(180, {...promotion, discount_type:"fixed_price",discount_value:181}), RangeError);
  assert.throws(() => calculatePromotionPrice(180, {...promotion, discount_value:101}), RangeError);
});

test("lists only promotions applicable at booking date/time", () => {
  assert.equal(applicablePromotions([promotion, {...promotion,status:"pending_review"}], 1, "2026-10-31T15:00:00-06:00").length, 1);
});
