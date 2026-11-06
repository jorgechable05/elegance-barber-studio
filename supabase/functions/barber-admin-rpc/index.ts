const allowedOrigins = new Set(["https://elegance-barber-piste-git-feat-lealtad-qr-clientes-dell-723c.vercel.app","https://elegance-barber-piste-5j0r0px29-dell-723c.vercel.app","https://elegance-barber-piste-4lnwar1ue-dell-723c.vercel.app","https://elegance-barber-piste.vercel.app"]);
const allowedRpcs = new Set(["barber_admin_set_status","barber_admin_reservations","barber_admin_reservations_with_promotions","barber_admin_sales","barber_admin_create_sale","barber_admin_create_sale_with_promotion_info","barber_admin_create_sale_with_promotion_info_mixed","barber_admin_create_walkin_sale","barber_admin_create_walkin_sale_with_promotion","barber_services_admin_list","barber_service_admin_save","barber_promotions_admin_list","barber_promotions_admin_metrics","barber_promotion_suggestion_settings_admin_get","barber_promotion_suggestion_settings_admin_save","barber_promotion_admin_save","barber_promotions_generate_daily_suggestions","barber_promotion_admin_duplicate","barber_promotion_admin_delete","barber_promotion_admin_review","barber_loyalty_list_customers","barber_loyalty_list_rewards","barber_loyalty_lookup_customer","barber_loyalty_record_visit","barber_loyalty_redeem_reward"]);
const cors = {"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
function reply(status:number,body:unknown,origin:string|null){const h=new Headers(cors);if(origin&&allowedOrigins.has(origin))h.set("Access-Control-Allow-Origin",origin);h.set("Vary","Origin");return new Response(status===204?null:JSON.stringify(body),{status,headers:h});}
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get("origin");
 if(req.method==="OPTIONS"){if(origin&&!allowedOrigins.has(origin))return reply(403,{message:"Origin not allowed"},null);return reply(204,{},origin);}
 if(req.method!=="POST")return reply(405,{message:"Method not allowed"},origin);
 if(origin&&!allowedOrigins.has(origin))return reply(403,{message:"Origin not allowed"},null);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return reply(503,{message:"Backend no configurado"},origin);
 try{
  const body=await req.json();const name=typeof body.name==="string"?body.name:"";const args=body.args;
  if(!allowedRpcs.has(name)||!args||typeof args!=="object"||Array.isArray(args))return reply(400,{message:"Operación no permitida"},origin);
  const token=typeof args.p_token==="string"?args.p_token:"";
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token))return reply(401,{message:"Sesión inválida o vencida"},origin);
  const headers={apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"};
  const qs=new URLSearchParams({token:"eq."+token,revoked_at:"is.null",expires_at:"gt."+new Date().toISOString(),select:"token",limit:"1"});
  const session=await fetch(url+"/rest/v1/barber_admin_sessions?"+qs.toString(),{headers});
  if(!session.ok)return reply(503,{message:"No se pudo validar la sesión"},origin);
  const rows=await session.json();if(!Array.isArray(rows)||rows.length!==1)return reply(401,{message:"Sesión inválida o vencida"},origin);
  const result=await fetch(url+"/rest/v1/rpc/"+name,{method:"POST",headers,body:JSON.stringify(args)});
  const data=await result.json();
  if(!result.ok)return reply(result.status,{message:data.message||data.error_description||"La operación no pudo completarse",code:data.code},origin);
  return reply(200,data,origin);
 }catch{return reply(400,{message:"Solicitud inválida"},origin);}
});