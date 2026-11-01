import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {isPromotionApplicable,calculatePromotionPrice} from "./customer-promotion-utils.js";
const admin=await readFile(new URL("./admin-promotions.js",import.meta.url),"utf8");
test("admin adapter remains isolated with approval controls",()=>{assert.match(admin,/mountPromotionsAdmin/);assert.match(admin,/barber_services_admin_list/);assert.match(admin,/barber_promotion_admin_review/);assert.match(admin,/pending_review/)});
test("admin can edit an existing promotion without publishing it automatically",()=>{assert.match(admin,/let editingPromotionId = null/);assert.match(admin,/p_id:editingPromotionId/);assert.match(admin,/Guardar cambios como borrador/);assert.match(admin,/No aparece al público hasta aprobación/);assert.match(admin,/const edit=el\("button",\{\},"Editar"\)/)});
test("approved promotion applies but pending suggestion does not",()=>{const p={status:"approved",service_ids:[1],starts_at:"2026-10-01T00:00:00-06:00",ends_at:"2026-11-30T23:59:59-06:00",weekdays:[0,1,2,3,4,5,6],start_time:"13:30:00",end_time:"20:30:00",discount_type:"percent",discount_value:10};assert.equal(isPromotionApplicable(p,1,"2026-10-31T15:00:00-06:00"),true);assert.equal(isPromotionApplicable({...p,status:"pending_review"},1,"2026-10-31T15:00:00-06:00"),false)});
test("price rejects invalid percentages",()=>{assert.equal(calculatePromotionPrice(160,{discount_type:"percent",discount_value:10}),144);assert.throws(()=>calculatePromotionPrice(160,{discount_type:"percent",discount_value:101}),RangeError)});
