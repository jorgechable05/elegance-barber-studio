import assert from "node:assert/strict";
import http from "node:http";
import { readFile } from "node:fs/promises";
import { createHmac } from "node:crypto";
import { dirname, extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const packageDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(packageDir, "..");
const productionSupabaseHost = "bvcbticzboknkmtgfkgw.supabase.co";
const mockOrigin = "https://mock.supabase.test";
const useLocalPostgrest = Boolean(process.env.PGRST_URL);
const jwtSecret = process.env.PGRST_JWT_SECRET || "";
const browserErrors = [];
const productionRequests = [];
const calls = [];
const observedRpcCalls = [];
let appBaseUrl = "";
function base64url(value) { return Buffer.from(value).toString("base64url"); }
function makeAnonJwt(secret) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = base64url(JSON.stringify({alg:"HS256",typ:"JWT"})) + "." +
    base64url(JSON.stringify({role:"anon",iat:now,exp:now+300,iss:"elegance-browser-ci"}));
  return unsigned + "." + createHmac("sha256", secret).update(unsigned).digest("base64url");
}
const browserApiKey = useLocalPostgrest
  ? (assert.ok(Buffer.byteLength(jwtSecret) >= 32, "test-only JWT secret required"), makeAnonJwt(jwtSecret))
  : "test-publishable-key-not-real";

const services = [
  {id:1,name:"Corte Clásico",description:"Corte clásico",duration_minutes:30,price:160,is_active:true,display_order:1},
  {id:2,name:"Corte Desvanecido",description:"Desvanecido",duration_minutes:30,price:180,is_active:true,display_order:2},
  {id:3,name:"Corte Infantil",description:"Corte infantil",duration_minutes:25,price:130,is_active:true,display_order:3},
  {id:4,name:"Alineación de Ceja",description:"Alineación de ceja",duration_minutes:20,price:40,is_active:true,display_order:4},
  {id:5,name:"Alineación de Barba",description:"Alineación de barba",duration_minutes:20,price:80,is_active:true,display_order:5},
  {id:6,name:"Corte + Masaje",description:"Corte y masaje",duration_minutes:45,price:280,is_active:true,display_order:6},
  {id:7,name:"Corte y Lavado de Cabello",description:"Corte y lavado",duration_minutes:45,price:250,is_active:true,display_order:7},
  {id:8,name:"VIP",description:"Servicio VIP",duration_minutes:60,price:400,is_active:true,display_order:8},
  {id:9,name:"Premium",description:"Servicio premium",duration_minutes:90,price:550,is_active:true,display_order:9},
];
const schedule = ["13:30","14:00","14:30","15:00","15:30","16:00","16:30","17:00","17:30","18:00","18:30","19:00","19:30","20:00","20:30"]
  .map(hora => ({hora, disponible:true}));
const promotion = {
  id:"promo-test-1",
  title:"Promoción de prueba",
  description:"Descuento aislado para prueba",
  status:"approved",
  service_ids:[1],
  starts_at:"2025-01-01T00:00:00-06:00",
  ends_at:"2030-01-01T00:00:00-06:00",
  weekdays:[0,1,2,3,4,5,6],
  start_time:"13:00:00",
  end_time:"21:00:00",
  discount_type:"percent",
  discount_value:10,
  uses_count:0,
  max_uses:null
};

function rpcFixture(name, args = {}) {
  calls.push({name,args});
  switch (name) {
    case "barber_admin_login":
      return {token:"mock-session-for-browser-tests"};
    case "barber_admin_reservations":
    case "barber_admin_sales":
    case "barber_promotions_admin_list":
      return [];
    case "barber_services_admin_list":
    case "barber_services_public":
      return services;
    case "barber_public_schedule":
      return schedule;
    case "barber_promotions_public":
      return [promotion];
    case "barber_promotions_generate_daily_suggestions":
      return 0;
    case "barber_create_reservation_with_promotion":
      return {id:"QA-RESERVATION-001",precio:144};
    case "barber_admin_create_walkin_sale":
      return {folio:"QA-WALKIN-001",total:160,cliente:args.p_cliente||"Cliente QA",servicio:"Corte Clásico",barbero:"EdgarMay",metodo:args.p_metodo||"Efectivo",efectivo:Number(args.p_efectivo||0),tarjeta:Number(args.p_tarjeta||0)};
    default:
      return {};
  }
}

function rpcCallSeen(name) {
  return calls.some(call => call.name === name) || observedRpcCalls.some(call => call.name === name);
}
async function waitForRpcCall(name, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (!rpcCallSeen(name) && Date.now() < deadline) {
    await new Promise(resolveWait => setTimeout(resolveWait, 25));
  }
  assert.ok(rpcCallSeen(name), "Timed out waiting for RPC " + name);
}

const mimeTypes = {
  ".js":"text/javascript; charset=utf-8",
  ".mjs":"text/javascript; charset=utf-8",
  ".html":"text/html; charset=utf-8",
  ".json":"application/json; charset=utf-8",
  ".css":"text/css; charset=utf-8"
};
const mockSupabaseSdk = `
window.supabase = {
  createClient: function (url, key) {
    return {
      rpc: async function (name, args) {
        const response = await fetch(url + "/rpc/" + name, {
          method: "POST",
          headers: { apikey: key, authorization: "Bearer " + key, "content-type": "application/json" },
          body: JSON.stringify(args || {})
        });
        const data = await response.json();
        return response.ok ? { data: data, error: null } : { data: null, error: data };
      }
    };
  }
};
`;

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", "http://127.0.0.1");
    if (url.pathname.startsWith("/rest/v1/rpc/") || url.pathname.startsWith("/rpc/")) {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      let args = {};
      try { args = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"); } catch {}
      const rpcName = decodeURIComponent(url.pathname.split("/").pop());
      observedRpcCalls.push({name:rpcName,args});
      if (useLocalPostgrest) {
        // Supabase clients call /rest/v1/rpc/*; standalone PostgREST serves /rpc/*.
        const upstreamPath = url.pathname.replace(/^\/rest\/v1/, "");
        const upstreamUrl = process.env.PGRST_URL.replace(/\/$/, "") + upstreamPath + url.search;
        const forwardedBody = Buffer.from(JSON.stringify(args));
        const upstream = await fetch(upstreamUrl, {
          method: req.method,
          headers: {
            ...(req.headers.authorization ? {authorization:req.headers.authorization} : {}),
            ...(req.headers.apikey ? {apikey:req.headers.apikey} : {}),
            "content-type": req.headers["content-type"] || "application/json"
          },
          ...(req.method === "GET" || req.method === "HEAD" ? {} : {body:forwardedBody})
        });
        const upstreamBody = Buffer.from(await upstream.arrayBuffer());
        res.writeHead(upstream.status, {
          "content-type": upstream.headers.get("content-type") || "application/json; charset=utf-8"
        });
        res.end(upstreamBody);
      } else {
        res.writeHead(200, {"content-type":"application/json; charset=utf-8"});
        res.end(JSON.stringify(rpcFixture(rpcName, args)));
      }
      return;
    }
    let filePath;
    if (["/admin","/admin/","/admin.html"].includes(url.pathname)) {
      filePath = resolve(repoRoot, "web-recovery/admin.html");
    } else if (["/cliente","/cliente/","/cliente.html"].includes(url.pathname)) {
      filePath = resolve(repoRoot, "web-recovery/cliente.html");
    } else if (["/pos","/pos/","/pos.html"].includes(url.pathname)) {
      let html = await readFile(resolve(repoRoot, "web-recovery/pos.html"), "utf8");
      // Inject an ephemeral local/mock endpoint only into the in-memory test response.
      const apiUrl = useLocalPostgrest ? appBaseUrl : mockOrigin;
      const runtimeConfig = 'window.ELEGANCE_SUPABASE_URL = ' + JSON.stringify(apiUrl) +
        '; window.ELEGANCE_SUPABASE_ANON_KEY = ' + JSON.stringify(browserApiKey) + ';';
      html = html.replace("const URL=window.ELEGANCE_SUPABASE_URL||'',KEY=window.ELEGANCE_SUPABASE_ANON_KEY||'';", runtimeConfig + " const URL=window.ELEGANCE_SUPABASE_URL||'',KEY=window.ELEGANCE_SUPABASE_ANON_KEY||'';");
      res.writeHead(200, {"content-type":"text/html; charset=utf-8"});
      res.end(html);
      return;
    } else if (url.pathname === "/config.js") {
      res.writeHead(200, {"content-type":"text/javascript; charset=utf-8"});
      const apiUrl = useLocalPostgrest ? appBaseUrl : mockOrigin;
      res.end('const SUPABASE_URL = ' + JSON.stringify(apiUrl) +
        '; const SUPABASE_KEY = ' + JSON.stringify(browserApiKey) + ';');
      return;
    } else if (url.pathname === "/sw.js") {
      res.writeHead(404);
      res.end("service worker disabled in isolated browser test");
      return;
    } else if (url.pathname === "/favicon.ico") {
      res.writeHead(204);
      res.end();
      return;
    } else if (url.pathname.startsWith("/web-promotion-package/")) {
      const relative = decodeURIComponent(url.pathname.slice(1));
      filePath = resolve(repoRoot, relative);
      if (!filePath.startsWith(resolve(repoRoot, "web-promotion-package") + sep)) {
        res.writeHead(403);
        res.end("forbidden");
        return;
      }
    } else {
      res.writeHead(404);
      res.end("not found");
      return;
    }
    const body = await readFile(filePath);
    res.writeHead(200, {"content-type":mimeTypes[extname(filePath)] || "application/octet-stream"});
    res.end(body);
  } catch (error) {
    res.writeHead(500, {"content-type":"text/plain; charset=utf-8"});
    res.end(String(error?.stack || error));
  }
});

function installNetworkStubs(page) {
  page.on("pageerror", error => browserErrors.push(error.message));
  page.on("request", request => {
    if (request.url().includes(productionSupabaseHost)) productionRequests.push(request.url());
    try {
      const requestUrl = new URL(request.url());
      const match = requestUrl.pathname.match(/\/(?:rest\/v1\/)?rpc\/([^/]+)$/);
      if (match && request.method() === "POST") {
        let args = {};
        try { args = request.postDataJSON() || {}; } catch {}
        observedRpcCalls.push({name:decodeURIComponent(match[1]),args});
      }
    } catch {}
  });
  return page.route("**/*", async route => {
    const requestUrl = new URL(route.request().url());
    if (["127.0.0.1","localhost"].includes(requestUrl.hostname)) {
      await route.continue();
      return;
    }
    if (requestUrl.hostname === "cdn.jsdelivr.net" && requestUrl.pathname.includes("supabase-js")) {
      await route.fulfill({status:200,headers:{"content-type":"text/javascript; charset=utf-8"},body:mockSupabaseSdk});
      return;
    }
    if (requestUrl.hostname === "mock.supabase.test") {
      const headers = {
        "content-type":"application/json; charset=utf-8",
        "access-control-allow-origin":"*",
        "access-control-allow-methods":"POST, OPTIONS",
        "access-control-allow-headers":"apikey, authorization, content-type"
      };
      if (route.request().method() === "OPTIONS") {
        await route.fulfill({status:204,headers,body:""});
        return;
      }
      let args = {};
      try { args = route.request().postDataJSON() || {}; } catch {}
      const name = requestUrl.pathname.split("/").pop();
      await route.fulfill({status:200,headers,body:JSON.stringify(rpcFixture(name,args))});
      return;
    }
    // Block images, font/CDN requests and all other external traffic. This suite
    // must never connect to the real backend or create production records.
    await route.fulfill({status:204,body:""});
  });
}

async function main() {
  if (useLocalPostgrest) {
    const upstream = new URL(process.env.PGRST_URL);
    assert.ok(["127.0.0.1","localhost"].includes(upstream.hostname),
      "Browser-to-RPC test only permits loopback PostgREST; hosted backends are forbidden");
  }
  await new Promise((resolveListen, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const address = server.address();
  const baseUrl = "http://127.0.0.1:" + address.port;
  appBaseUrl = baseUrl;
  const browser = await chromium.launch({headless:true});
  try {
    // Admin: existing mock login, promotion panel mounting, and promotion tab.
    const adminContext = await browser.newContext({timezoneId:"America/Merida"});
    const admin = await adminContext.newPage();
    await installNetworkStubs(admin);
    await admin.addInitScript(() => {
      window.alert = () => {};
      window.open = () => null;
    });
    await admin.goto(baseUrl + "/admin", {waitUntil:"domcontentloaded"});
    await admin.locator("#user").fill("local-qa-user");
    await admin.locator("#pass").fill("local-qa-password-not-a-credential");
    await admin.locator("#loginBtn").click();
    await admin.waitForFunction(() => {
      const app = document.querySelector("#app");
      const message = document.querySelector("#loginMsg");
      return (app && getComputedStyle(app).display !== "none") || (message && message.textContent.trim() !== "");
    }, { timeout: 10000 }).catch(() => {});
    if (!(await admin.locator("#app").isVisible())) {
      throw new Error("Admin mock login did not open #app. loginMsg=" +
        JSON.stringify(await admin.locator("#loginMsg").textContent()) +
        "; observedRpcCalls=" + JSON.stringify(observedRpcCalls) +
        "; pageErrors=" + JSON.stringify(browserErrors));
    }
    await admin.locator("#promotionsToggle").click();
    await admin.getByRole("button", {name:"Promociones y sugerencias"}).click();
    await admin.getByText("Crear promoción").waitFor({state:"visible"});
    await waitForRpcCall("barber_promotions_admin_list");
    assert.ok(rpcCallSeen("barber_promotions_admin_list"),
      "Admin should request the promotions list through the active RPC endpoint");
    if (useLocalPostgrest) {
      await admin.getByText("CI browser promotion integration").waitFor({state:"visible",timeout:10000});
    }

    // Customer: public services/schedule, approved offer display, reservation call
    // sends identifiers to the server but does not send a trusted client price.
    const clientContext = await browser.newContext({timezoneId:"America/Merida"});
    const client = await clientContext.newPage();
    await installNetworkStubs(client);
    await client.addInitScript(() => {
      window.alert = () => {};
      window.open = () => null;
    });
    await client.goto(baseUrl + "/cliente", {waitUntil:"domcontentloaded"});
    if (useLocalPostgrest) {
      await client.locator("#dates .date-card:not(.dom)").nth(1).click();
    }
    await client.locator(".hora.libre").first().waitFor({state:"visible",timeout:10000});
    const availableTime = client.locator(".hora.libre").filter({hasText:"13:30"}).first();
    await availableTime.click();
    await client.locator("#promotionOffer").waitFor({state:"visible",timeout:10000});
    assert.match(await client.locator("#promotionOffer").innerText(), /PROMOCIÓN DISPONIBLE/);
    assert.match(await client.locator("#promotionOffer").innerText(), /\$144/);
    await client.locator("#nombre").fill("Cliente QA local");
    await client.locator("#tel").fill("9990000000");
    await client.getByRole("button", {name:"Reservar por WhatsApp"}).click();
    await client.getByText("Reserva realizada").waitFor({state:"visible",timeout:10000});
    const reservationCall = [...observedRpcCalls,...calls].find(call => call.name === "barber_create_reservation_with_promotion");
    assert.ok(reservationCall, "Customer should invoke the server reservation RPC");
    assert.equal(Number(reservationCall.args.p_servicio_id), 1);
    assert.ok(reservationCall.args.p_promotion_id, "reservation RPC should include the selected promotion ID");
    assert.equal(Object.hasOwn(reservationCall.args, "p_precio"), false,
      "Client must not send an authoritative reservation price");

    // POS: current layout, login, walk-in modal and print-ticket flow, with API
    // completely stubbed. No payment or sale reaches the real service.
    const posContext = await browser.newContext({timezoneId:"America/Merida"});
    const pos = await posContext.newPage();
    await installNetworkStubs(pos);
    await pos.addInitScript(() => {
      window.alert = () => {};
      window.open = () => null;
      window.print = () => { window.__qaPrintCalled = true; };
    });
    await pos.goto(baseUrl + "/pos", {waitUntil:"domcontentloaded"});
    await pos.locator("#u").fill("local-qa-user");
    await pos.locator("#p").fill("local-qa-password-not-a-credential");
    await pos.locator("#go").click();
    await pos.locator("#app").waitFor({state:"visible"});
    const printCss = (await pos.locator("style").allTextContents()).join("\n");
    assert.match(printCss, /@page\s*\{[^}]*size:\s*58mm auto/i,
      "POS receipt must retain its 58mm thermal print layout");
    const methods = ["Efectivo", "Transferencia", "Tarjeta", "Mixto"];
    const methodOptions = await pos.locator("#wmethod option").allTextContents();
    for (const method of methods) assert.ok(methodOptions.includes(method), "Missing POS payment method: " + method);
    for (const method of methods) {
      await pos.locator("#openWalkin").click();
      await pos.locator("#walkinModal").waitFor({state:"visible"});
      await pos.locator("#wname").fill("Cliente QA local");
      await pos.locator("#wservice").selectOption("1");
      await pos.locator("#wmethod").selectOption({label:method});
      if(method==="Mixto"){await pos.locator("#wcashPart").fill("100");await pos.locator("#wcardPart").fill("60");}else{await pos.locator("#wreceived").fill("160");}
      await pos.evaluate(() => { window.__qaPrintCalled = false; });
      await pos.locator("#walkCharge").click();
      await pos.locator("#walkinModal").waitFor({state:"hidden"});
      const latestWalkinCall = observedRpcCalls.filter(call => call.name === "barber_admin_create_walkin_sale").at(-1);
      assert.ok(latestWalkinCall, "POS should invoke the walk-in sale RPC for " + method);
      assert.equal(latestWalkinCall.args.p_metodo, method, "POS should preserve selected payment method");
      if(method==="Mixto"){assert.equal(Number(latestWalkinCall.args.p_efectivo),100);assert.equal(Number(latestWalkinCall.args.p_tarjeta),60);assert.match(await pos.locator("#ticketPrint").innerText(),/EFECTIVO:\s*\$100\.00/);assert.match(await pos.locator("#ticketPrint").innerText(),/TARJETA:\s*\$60\.00/);}
      assert.equal(await pos.evaluate(() => window.__qaPrintCalled), true,
        "POS should invoke the ticket-print flow for " + method);
    }

    assert.deepEqual(productionRequests, [],
      "Browser test must make zero requests to the production Supabase project");
    assert.deepEqual(browserErrors, [], "Browser pages should not throw uncaught JavaScript errors");

    console.log("PASS: Admin login and promotion panel mount (" + (useLocalPostgrest ? "local PostgREST RPC" : "mocked RPC") + ")");
    console.log("PASS: Cliente shows a 10% approved offer and calls reservation RPC (" + (useLocalPostgrest ? "local PostgREST RPC" : "mocked RPC") + ")");
    console.log("PASS: POS walk-in checkout reaches ticket print flow (" + (useLocalPostgrest ? "CI-only no-write RPC fixture" : "mocked RPC") + ")");
    console.log("PASS: zero browser requests to production Supabase; API base is " + (useLocalPostgrest ? "local test proxy" : "local mock"));
  } finally {
    await browser.close();
    await new Promise(resolveClose => server.close(resolveClose));
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
  server.close();
});
