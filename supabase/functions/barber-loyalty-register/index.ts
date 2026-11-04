const cors = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const allowedOrigins = new Set([
  "https://elegance-barber-piste-i7g9vw7xt-dell-723c.vercel.app",
  "https://elegance-barber-piste-5j0r0px29-dell-723c.vercel.app",
  "https://elegance-barber-piste-4lnwar1ue-dell-723c.vercel.app",
  "https://elegance-barber-piste.vercel.app",
]);

function response(status: number, body: Record<string, unknown>, origin: string | null) {
  const headers = new Headers(cors);
  if (origin && allowedOrigins.has(origin)) headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Vary", "Origin");
  return new Response(status === 204 ? null : JSON.stringify(body), { status, headers });
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") {
    if (origin && !allowedOrigins.has(origin)) return response(403, { error: "Origin not allowed" }, null);
    return response(204, {}, origin);
  }
  if (req.method !== "POST") return response(405, { error: "Method not allowed" }, origin);
  if (origin && !allowedOrigins.has(origin)) return response(403, { error: "Origin not allowed" }, null);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const turnstileSecret = Deno.env.get("CLOUDFLARE_TURNSTILE_SECRET");
  if (!supabaseUrl || !serviceKey || !turnstileSecret) {
    return response(503, { error: "La protección anti-bots aún no está configurada." }, origin);
  }
  try {
    const body = await req.json();
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const phone = typeof body.phone === "string" ? body.phone : "";
    const consent = body.consent === true;
    const captchaToken = typeof body.captchaToken === "string" ? body.captchaToken : "";
    if (name.length < 2 || name.length > 100 || phone.length < 8 || phone.length > 18 || !consent || !captchaToken) {
      return response(400, { error: "Completa los datos, acepta el aviso y verifica el control anti-bots." }, origin);
    }
    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip");
    if (!ip) return response(400, { error: "No se pudo validar el origen de la solicitud." }, origin);
    const headers = { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" };
    const rate = await fetch(supabaseUrl + "/rest/v1/rpc/barber_loyalty_allow_registration", {
      method: "POST", headers, body: JSON.stringify({ p_ip_hash: await sha256(ip.trim()) }),
    });
    if (!rate.ok) return response(503, { error: "No se pudo validar el límite de registros. Intenta más tarde." }, origin);
    if (await rate.json() !== true) return response(429, { error: "Has alcanzado el límite de registros. Intenta de nuevo más tarde." }, origin);
    const form = new FormData();
    form.append("secret", turnstileSecret);
    form.append("response", captchaToken);
    form.append("remoteip", ip.trim());
    const verification = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
    const verdict = await verification.json();
    if (!verdict.success) return response(403, { error: "No se pudo verificar el control anti-bots. Intenta nuevamente." }, origin);
    const registration = await fetch(supabaseUrl + "/rest/v1/rpc/barber_loyalty_register_customer", {
      method: "POST", headers,
      body: JSON.stringify({ p_name: name, p_phone: phone, p_consent: consent }),
    });
    const result = await registration.json();
    if (!registration.ok) return response(400, { error: result.message || "No se pudo completar el registro." }, origin);
    return response(200, result, origin);
  } catch {
    return response(400, { error: "Solicitud inválida. Revisa los datos e intenta nuevamente." }, origin);
  }
});