import assert from "node:assert/strict";
import { createHmac } from "node:crypto";

const apiBase = (process.env.PGRST_URL || "http://127.0.0.1:3000").replace(/\/$/, "");
const jwtSecret = process.env.PGRST_JWT_SECRET;
assert.ok(jwtSecret && Buffer.byteLength(jwtSecret) >= 32,
  "PGRST_JWT_SECRET must be a test-only secret of at least 32 bytes");

function b64url(value) {
  return Buffer.from(value).toString("base64url");
}
function makeAnonJwt(secret) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64url(JSON.stringify({alg:"HS256",typ:"JWT"})) + "." +
    b64url(JSON.stringify({role:"anon",iat:now,exp:now+300,iss:"elegance-ci"}));
  return unsigned + "." + createHmac("sha256", secret).update(unsigned).digest("base64url");
}

const anonJwt = makeAnonJwt(jwtSecret);

async function rpc(name, args = {}) {
  const response = await fetch(apiBase + "/rpc/" + name, {
    method: "POST",
    headers: {
      apikey: anonJwt,
      authorization: "Bearer " + anonJwt,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const raw = await response.text();
  let body;
  try { body = raw ? JSON.parse(raw) : null; }
  catch { body = raw; }
  if (!response.ok) {
    const message = typeof body === "string" ? body : JSON.stringify(body);
    const error = new Error("RPC " + name + " failed (" + response.status + "): " + message);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

async function expectRpcFailure(name, args, label) {
  let didFail = false;
  try { await rpc(name, args); }
  catch (error) {
    didFail = true;
    assert.ok(error.status >= 400, label + " should fail through a non-2xx HTTP response");
  }
  assert.equal(didFail, true, label + " should be rejected by the server");
}

function nextSaturdayInMerida() {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone:"America/Merida", year:"numeric", month:"2-digit", day:"2-digit"
    }).formatToParts(new Date()).map(p => [p.type,p.value])
  );
  const today = parts.year + "-" + parts.month + "-" + parts.day;
  const localNoonAsDate = new Date(today + "T12:00:00-06:00");
  let days = (6 - localNoonAsDate.getUTCDay() + 7) % 7;
  if (days < 2) days += 7;
  localNoonAsDate.setUTCDate(localNoonAsDate.getUTCDate() + days);
  const result = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone:"America/Merida", year:"numeric", month:"2-digit", day:"2-digit"
    }).formatToParts(localNoonAsDate).map(p => [p.type,p.value])
  );
  return result.year + "-" + result.month + "-" + result.day;
}

function singleRow(value) {
  if (Array.isArray(value)) return value[0];
  return value;
}

async function main() {
  const baseHealth = await fetch(apiBase + "/");
  assert.ok(baseHealth.status > 0, "PostgREST HTTP listener should answer");
  console.log("PASS: local PostgREST listener is reachable");

  const services = await rpc("barber_services_public");
  assert.equal(services.length, 9, "public services RPC should return 9 legacy numeric IDs");
  assert.deepEqual(services.map(s => Number(s.id)).sort((a,b)=>a-b), [1,2,3,4,5,6,7,8,9]);
  assert.equal(Number(services.find(s => Number(s.id) === 1).price), 160);
  console.log("PASS: barber_services_public responds over HTTP with numeric service IDs 1-9");

  const login = await rpc("barber_admin_login", {
    p_username: "local-qa-user",
    p_password: "local-qa-password-not-a-credential",
  });
  const token = login && login.token;
  assert.ok(typeof token === "string" && /^[0-9a-f-]{36}$/i.test(token),
    "test-only Admin login should return a UUID session token");

  const initialPromotions = await rpc("barber_promotions_admin_list", {p_token:token});
  assert.ok(Array.isArray(initialPromotions), "admin promotions list should return rows");
  assert.equal(initialPromotions.length, 0, "the ephemeral integration DB should start without promotions");
  await expectRpcFailure("barber_promotions_admin_list",
    {p_token:"99999999-9999-4999-8999-999999999999"},
    "invalid Admin session");
  console.log("PASS: Admin login and session guard are exercised through HTTP RPC");

  const now = Date.now();
  const saveResult = await rpc("barber_promotion_admin_save", {
    p_token: token,
    p_id: null,
    p_title: "CI HTTP promotion integration",
    p_description: "Temporary PostgREST integration fixture; not a customer offer",
    p_discount_type: "percent",
    p_discount_value: 10,
    p_starts_at: new Date(now - 24 * 60 * 60 * 1000).toISOString(),
    p_ends_at: new Date(now + 30 * 24 * 60 * 60 * 1000).toISOString(),
    p_weekdays: [0,1,2,3,4,5,6],
    p_start_time: "13:00:00",
    p_end_time: "21:00:00",
    p_service_ids: [1],
    p_max_uses: 1,
  });
  const saved = singleRow(saveResult);
  assert.ok(saved && saved.id, "promotion save RPC should return the saved row");
  assert.equal(saved.status, "draft", "promotion save must not publish automatically");
  const beforeApproval = await rpc("barber_promotions_public");
  assert.equal(beforeApproval.some(p => p.id === saved.id), false,
    "a draft promotion must not be visible to the public RPC");

  const approvedResult = await rpc("barber_promotion_admin_review", {
    p_token: token,
    p_id: saved.id,
    p_decision: "approved",
  });
  const approved = singleRow(approvedResult);
  assert.equal(approved.status, "approved");
  const publicPromotions = await rpc("barber_promotions_public");
  const visiblePromotion = publicPromotions.find(p => p.id === saved.id);
  assert.ok(visiblePromotion, "only after approval should the promotion appear publicly");
  assert.deepEqual(visiblePromotion.service_ids.map(Number), [1]);
  console.log("PASS: draft -> Admin approval -> public promotion visibility works over HTTP RPC");

  const appointmentDate = nextSaturdayInMerida();
  const reservation = await rpc("barber_create_reservation_with_promotion", {
    p_barbero_id: 1,
    p_fecha: appointmentDate,
    p_hora: "13:30",
    p_nombre: "CI HTTP promotion reservation",
    p_notas: "Ephemeral automated integration fixture",
    p_servicio_id: 1,
    p_telefono: "5550000987",
    p_promotion_id: saved.id,
  });
  assert.ok(reservation, "the server-side reservation RPC should return a reservation ID");

  await expectRpcFailure("barber_create_reservation_with_promotion", {
    p_barbero_id: 2,
    p_fecha: appointmentDate,
    p_hora: "14:00",
    p_nombre: "CI HTTP exhausted promotion",
    p_notas: "Expected rejection after the single test use",
    p_servicio_id: 1,
    p_telefono: "5550000988",
    p_promotion_id: saved.id,
  }, "a second reservation after max_uses=1");

  const visibleAfterLimit = await rpc("barber_promotions_public");
  assert.equal(visibleAfterLimit.some(p => p.id === saved.id), false,
    "a consumed single-use promotion should disappear from public results");
  await expectRpcFailure("barber_promotion_admin_review", {
    p_token: "99999999-9999-4999-8999-999999999999",
    p_id: saved.id,
    p_decision: "paused",
  }, "promotion review with invalid Admin session");
  console.log("PASS: reservation RPC consumes the single promotion use and rejects reuse over HTTP");

  // Legacy UI RPCs here are explicitly test-only fixtures. They do not persist sales.
  const reservations = await rpc("barber_admin_reservations", {p_token:token});
  const sales = await rpc("barber_admin_sales", {p_token:token});
  assert.deepEqual(reservations, []);
  assert.deepEqual(sales, []);
  const posResult = await rpc("barber_admin_create_walkin_sale", {
    p_token: token,
    p_cliente: "Cliente QA HTTP local",
    p_servicio_id: 1,
    p_barbero_id: 1,
    p_metodo: "Efectivo",
    p_recibido: 160,
  });
  assert.equal(posResult.folio, "QA-WALKIN-HTTP-001");
  assert.equal(Number(posResult.total), 160);
  console.log("PASS: legacy Admin/POS HTTP endpoints route correctly through CI-only no-write fixtures");
  console.log("PASS: all calls above used local PostgREST + temporary PostgreSQL, never hosted Supabase");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
