import assert from "node:assert/strict";
import { chromium } from "playwright";

const base = (process.env.PREVIEW_URL || "").replace(/\/$/, "");
assert.ok(base, "PREVIEW_URL is required");
const preview = new URL(base);
assert.equal(preview.protocol, "https:");
assert.ok(preview.hostname.endsWith(".vercel.app"), "Only a unique Vercel preview URL is permitted");
assert.notEqual(preview.hostname, "elegance-barber-piste.vercel.app", "The production alias is forbidden");

const productionRequests = [];
const pageErrors = [];
const requestFailures = [];
const browser = await chromium.launch({headless:true});

function watch(page) {
  page.on("pageerror", e => pageErrors.push(e.message));
  page.on("requestfailed", req => requestFailures.push({url:req.url(),failure:req.failure()?.errorText}));
  page.on("request", req => {
    const url = req.url();
    if (/bvcbticzboknkmtgfkgw\.supabase\.co|supabase\.co\/rest\/v1/i.test(url)) {
      productionRequests.push(url);
    }
  });
}
async function closeBannerCheck(page) {
  await page.getByText("VISTA PREVIA QA · DATOS SIMULADOS").waitFor({state:"visible",timeout:10000});
}

try {
  const admin = await browser.newPage({timezoneId:"America/Merida"});
  watch(admin);
  await admin.addInitScript(() => { window.alert=()=>{}; window.open=()=>null; });
  await admin.goto(base+"/admin",{waitUntil:"domcontentloaded"});
  await closeBannerCheck(admin);
  await admin.locator("#user").fill("preview-qa-user");
  await admin.locator("#pass").fill("preview-only-not-a-credential");
  await admin.locator("#loginBtn").click();
  await admin.locator("#app").waitFor({state:"visible",timeout:10000});
  await admin.locator("#promotionsToggle").click();
  await admin.getByRole("button",{name:"Promociones y sugerencias"}).click();
  await admin.getByText("Crear promoción").waitFor({state:"visible",timeout:10000});
  console.log("PASS: deployed Admin route, mock login, and promotions module");

  const client = await browser.newPage({timezoneId:"America/Merida"});
  watch(client);
  await client.addInitScript(() => { window.alert=()=>{}; window.open=()=>null; });
  await client.goto(base+"/cliente",{waitUntil:"domcontentloaded"});
  await closeBannerCheck(client);
  await client.locator("#dates .date-card:not(.dom)").nth(1).click();
  await client.locator(".hora.libre").first().waitFor({state:"visible",timeout:10000});
  await client.locator(".hora.libre").filter({hasText:"13:30"}).first().click();
  await client.locator("#promotionOffer").waitFor({state:"visible",timeout:10000});
  assert.match(await client.locator("#promotionOffer").innerText(),/PROMOCIÓN DISPONIBLE/);
  assert.match(await client.locator("#promotionOffer").innerText(),/\$144/);
  await client.locator("#nombre").fill("Cliente QA vista previa");
  await client.locator("#tel").fill("9990000000");
  await client.getByRole("button",{name:"Reservar por WhatsApp"}).click();
  await client.getByText("Reserva realizada").waitFor({state:"visible",timeout:10000});
  console.log("PASS: deployed Cliente route, promotion price, and simulated reservation RPC");

  const pos = await browser.newPage({timezoneId:"America/Merida"});
  watch(pos);
  await pos.addInitScript(() => { window.alert=()=>{}; window.open=()=>null; window.print=()=>{window.__qaPrintCalled=true;}; });
  await pos.goto(base+"/pos",{waitUntil:"domcontentloaded"});
  await closeBannerCheck(pos);
  await pos.locator("#u").fill("preview-qa-user");
  await pos.locator("#p").fill("preview-only-not-a-credential");
  await pos.locator("#go").click();
  await pos.locator("#app").waitFor({state:"visible",timeout:10000});
  await pos.locator("#openWalkin").click();
  await pos.locator("#walkinModal").waitFor({state:"visible"});
  await pos.locator("#wname").fill("Cliente QA vista previa");
  await pos.locator("#wservice").selectOption("1");
  await pos.locator("#wmethod").selectOption({label:"Mixto"});
  await pos.locator("#wcashPart").fill("100");
  await pos.locator("#wcardPart").fill("60");
  await pos.locator("#walkCharge").click();
  await pos.locator("#walkinModal").waitFor({state:"hidden",timeout:10000});
  assert.equal(Number(await pos.locator("#ticketPrint").innerText().then(t => (t.match(/EFECTIVO:\s*\$([0-9.]+)/)||[])[1])),100);
  assert.equal(Number(await pos.locator("#ticketPrint").innerText().then(t => (t.match(/TARJETA:\s*\$([0-9.]+)/)||[])[1])),60);
  assert.equal(await pos.evaluate(()=>window.__qaPrintCalled),true);
  console.log("PASS: deployed POS route, mixed payment validation, and 58mm ticket breakdown");

  assert.deepEqual(productionRequests, [], "No request may reach Supabase or the active backend");
  assert.deepEqual(pageErrors, [], "No uncaught page errors are allowed");
  console.log("PASS: zero requests to Supabase production hosts");
  if (requestFailures.length) console.log("INFO: failed requests (non-blocking assets may be external):",JSON.stringify(requestFailures));
} finally {
  await browser.close();
}
