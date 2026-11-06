const allowedOrigins = new Set(["https://elegance-barber-piste-6mexwt17r-dell-723c.vercel.app","https://elegance-barber-piste-2r1trtfud-dell-723c.vercel.app","https://elegance-barber-piste-lmmazprne-dell-723c.vercel.app","https://elegance-barber-piste-git-feat-lealtad-qr-clientes-dell-723c.vercel.app","https://elegance-barber-piste-5j0r0px29-dell-723c.vercel.app","https://elegance-barber-piste-4lnwar1ue-dell-723c.vercel.app","https://elegance-barber-piste.vercel.app"]);
const cors = {"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
function reply(status:number,body:Record<string,unknown>,origin:string|null){const h=new Headers(cors);if(origin&&allowedOrigins.has(origin))h.set("Access-Control-Allow-Origin",origin);h.set("Vary","Origin");return new Response(status===204?null:JSON.stringify(body),{status,headers:h});}
async function hashIp(ip:string){const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(ip));return Array.from(new Uint8Array(d)).map(x=>x.toString(16).padStart(2,"0")).join("");}
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get("origin");
 if(req.method==="OPTIONS"){if(origin&&!allowedOrigins.has(origin))return reply(403,{message:"Origin not allowed"},null);return reply(204,{},origin);}
 if(req.method!=="POST")return reply(405,{message:"Method not allowed"},origin);
 if(origin&&!allowedOrigins.has(origin))return reply(403,{message:"Origin not allowed"},null);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return reply(503,{message:"Backend no configurado"},origin);
 try{
  const body=await req.json();const username=typeof body.username==="string"?body.username.trim():"";const password=typeof body.password==="string"?body.password:"";
  if(!username||!password||password.length>128)return reply(400,{message:"Usuario o contraseña inválidos"},origin);
  const ip=req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip");
  if(!ip)return reply(400,{message:"No se pudo validar el origen"},origin);
  const headers={apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"};
  const limited=await fetch(url+"/rest/v1/rpc/barber_admin_allow_login",{method:"POST",headers,body:JSON.stringify({p_ip_hash:await hashIp(ip.trim())})});
  if(!limited.ok)return reply(503,{message:"No se pudo validar el límite de acceso"},origin);
  if(await limited.json()!==true)return reply(429,{message:"Demasiados intentos. Intenta de nuevo en una hora."},origin);
  const auth=await fetch(url+"/rest/v1/rpc/barber_admin_login",{method:"POST",headers,body:JSON.stringify({p_username:username,p_password:password})});
  const data=await auth.json();
  if(!auth.ok)return reply(401,{message:data.message||"Usuario o contraseña incorrectos"},origin);
  return reply(200,data,origin);
 }catch{return reply(400,{message:"Solicitud inválida"},origin);}
});