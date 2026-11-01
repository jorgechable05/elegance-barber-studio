/**
 * Adaptador de UI para una nueva pestaña/área de promociones en Admin.
 *
 * No reemplaza la vista Admin existente. El consumidor debe invocarlo solo después
 * de autenticar en el flujo actual y proporcionar el token de sesión.
 *
 * No conecta hasta que existan las RPC de promociones en un entorno aislado.
 */
export function mountPromotionsAdmin({
  root,
  rpc,
  token,
  onError = (error) => console.error(error),
}) {
  if (!root || typeof rpc !== "function" || !token) {
    throw new TypeError("Se requiere root, RPC y sesión administrativa activa");
  }

  const el = (tag, attrs = {}, text = "") => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (key === "className") node.className = value;
      else if (key.startsWith("aria-") || key === "role") node.setAttribute(key, String(value));
      else if (key in node) node[key] = value;
    }
    if (text) node.textContent = text;
    return node;
  };

  const host = el("section", {className:"eb-promotions-admin", "aria-label":"Administración de promociones"});
  const style = el("style");
  style.textContent = `
    .eb-promotions-admin{margin:16px 0;padding:16px;border:1px solid #d4af37;border-radius:13px;background:#111;color:#f5f5f5;font:14px Arial,sans-serif}
    .eb-promotions-admin h2{color:#d4af37;margin:0 0 12px;font-size:19px}
    .eb-promotions-admin .eb-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}
    .eb-promotions-admin label{display:grid;gap:5px;color:#ddd;font-size:12px}
    .eb-promotions-admin input,.eb-promotions-admin textarea,.eb-promotions-admin select{width:100%;padding:9px;background:#080808;border:1px solid #444;border-radius:7px;color:#fff}
    .eb-promotions-admin button{background:#d4af37;color:#111;border:0;border-radius:7px;padding:9px 12px;margin:6px 6px 6px 0;font-weight:700;cursor:pointer}
    .eb-promotions-admin .eb-muted{color:#aaa;font-size:12px}
    .eb-promotions-admin .eb-item{border:1px solid #333;border-radius:9px;padding:12px;margin-top:10px}
    .eb-promotions-admin .eb-status{color:#e6cf7a;font-size:12px}
  `;
  host.append(style, el("h2", {}, "Servicios y promociones"));
  host.append(el("p", {className:"eb-muted"}, "Esta sección adicional no altera la gestión de citas existente. Los cambios de promoción quedan en borrador hasta aprobación."));

  const tabs = el("div", {role:"group", "aria-label":"Secciones"});
  const servicesTab = el("button", {}, "Servicios");
  const promotionsTab = el("button", {}, "Promociones y sugerencias");
  tabs.append(servicesTab, promotionsTab);
  host.append(tabs);

  const content = el("div");
  host.append(content);
  root.append(host);

  let services = [];
  let promotions = [];
  let view = "services";
  let editingPromotionId = null;

  const formField = (label, input) => {
    const wrapper = el("label");
    wrapper.append(el("span", {}, label), input);
    return wrapper;
  };

  async function refresh() {
    try {
      const [serviceRows, promotionRows] = await Promise.all([
        rpc("barber_services_admin_list", {p_token:token}),
        rpc("barber_promotions_admin_list", {p_token:token}),
      ]);
      services = Array.isArray(serviceRows) ? serviceRows : [];
      promotions = Array.isArray(promotionRows) ? promotionRows : [];
      render();
    } catch (error) { onError(error); }
  }

  function renderServices() {
    content.replaceChildren();
    const form = el("form", {className:"eb-grid"});
    const name = el("input", {type:"text", value:""});
    const desc = el("textarea");
    const duration = el("input", {type:"number", min:"5", step:"5", value:"30"});
    const price = el("input", {type:"number", min:"0", step:"0.01", value:"0"});
    const order = el("input", {type:"number", min:"0", step:"1", value:"100"});
    const active = el("input", {type:"checkbox"});
    const activeWrap = formField("Servicio activo", active);
    form.append(formField("Nombre",name), formField("Descripción",desc), formField("Duración (minutos)",duration), formField("Precio normal",price), formField("Orden",order), activeWrap);
    const save = el("button", {type:"submit"}, "Crear servicio");
    const status = el("p", {className:"eb-muted"});
    form.append(save);
    content.append(el("h3", {}, "Catálogo de servicios"), form, status);
    form.onsubmit = async event => {
      event.preventDefault();
      try {
        await rpc("barber_service_admin_save", {
          p_token:token, p_id:null, p_name:name.value.trim(), p_description:desc.value.trim(),
          p_duration_minutes:Number(duration.value), p_price:Number(price.value),
          p_is_active:active.checked, p_display_order:Number(order.value)
        });
        status.textContent = "Servicio guardado.";
        await refresh();
      } catch(error) { status.textContent = error.message; onError(error); }
    };
    for (const service of services) {
      const row = el("div", {className:"eb-item"});
      row.append(el("strong", {}, service.name), el("p", {className:"eb-muted"}, service.description || "Sin descripción"));
      row.append(el("p", {}, `${service.duration_minutes} min · $${Number(service.price).toFixed(2)} · ${service.is_active ? "Activo" : "Inactivo"}`));
      const edit = el("button", {}, "Editar");
      edit.onclick = () => {
        name.value = service.name || ""; desc.value = service.description || "";
        duration.value = service.duration_minutes; price.value = service.price;
        order.value = service.display_order; active.checked = !!service.is_active;
        const originalSubmit = form.onsubmit;
        form.onsubmit = async event => {
          event.preventDefault();
          try {
            await rpc("barber_service_admin_save", {
              p_token:token, p_id:service.id, p_name:name.value.trim(), p_description:desc.value.trim(),
              p_duration_minutes:Number(duration.value), p_price:Number(price.value),
              p_is_active:active.checked, p_display_order:Number(order.value)
            });
            form.onsubmit = originalSubmit; await refresh();
          } catch(error) { status.textContent=error.message; onError(error); }
        };
        save.textContent = "Guardar cambios";
      };
      row.append(edit); content.append(row);
    }
  }

  function renderPromotions() {
    content.replaceChildren();
    const form = el("form", {className:"eb-grid"});
    const title = el("input", {type:"text"});
    const desc = el("textarea");
    const type = el("select");
    type.append(el("option",{value:"percent"},"Descuento porcentual"), el("option",{value:"fixed_price"},"Precio especial"));
    const value = el("input", {type:"number",min:"0.01",step:"0.01",value:"10"});
    const start = el("input", {type:"datetime-local"});
    const end = el("input", {type:"datetime-local"});
    const fromTime = el("input", {type:"time",value:"13:30"});
    const toTime = el("input", {type:"time",value:"20:30"});
    const days = el("div", {role:"group", "aria-label":"Días aplicables"});
    const dayChecks = [];
    for (const [day,label] of [[0,"Dom"],[1,"Lun"],[2,"Mar"],[3,"Mié"],[4,"Jue"],[5,"Vie"],[6,"Sáb"]]) {
      const input = el("input",{type:"checkbox",value:String(day)});
      input.checked = day !== 0;
      dayChecks.push(input);
      days.append(formField(label,input));
    }
    const servicesSelect = el("select");
    servicesSelect.multiple = true;
    for (const s of services.filter(item=>item.is_active)) servicesSelect.append(el("option",{value:s.id},s.name));
    const maxUses = el("input",{type:"number",min:"1",step:"1",placeholder:"Sin límite"});
    form.append(formField("Título",title), formField("Descripción",desc), formField("Tipo",type), formField("Valor",value),
      formField("Desde (fecha y hora)",start), formField("Hasta (fecha y hora)",end),
      formField("Hora inicial diaria",fromTime), formField("Hora final diaria",toTime),
      formField("Servicios activos (selecciona uno o más)",servicesSelect), formField("Usos máximos (opcional)",maxUses),
      formField("Días (hora local del negocio)",days));
    const save = el("button",{type:"submit"},editingPromotionId ? "Guardar cambios como borrador" : "Guardar como borrador");
    const cancelEdit = el("button",{type:"button"},"Cancelar edición");
    cancelEdit.hidden = !editingPromotionId;
    const suggest = el("button",{type:"button"},"Generar sugerencias para revisión");
    const message = el("p",{className:"eb-muted"});
    form.append(save);
    content.append(el("h3",{},editingPromotionId ? "Editar promoción" : "Crear promoción"),form,cancelEdit,suggest,message);
    cancelEdit.onclick = () => { editingPromotionId = null; renderPromotions(); };
    form.onsubmit = async event => {
      event.preventDefault();
      try {
        const serviceIds = Array.from(servicesSelect.selectedOptions).map(o=>o.value);
        if (!serviceIds.length) throw new Error("Selecciona al menos un servicio.");
        const weekDays = dayChecks.filter(c=>c.checked).map(c=>Number(c.value));
        await rpc("barber_promotion_admin_save",{
          p_token:token,p_id:editingPromotionId,p_title:title.value.trim(),p_description:desc.value.trim(),
          p_discount_type:type.value,p_discount_value:Number(value.value),
          p_starts_at:new Date(start.value).toISOString(),p_ends_at:new Date(end.value).toISOString(),
          p_weekdays:weekDays,p_start_time:fromTime.value||null,p_end_time:toTime.value||null,
          p_service_ids:serviceIds,p_max_uses:maxUses.value?Number(maxUses.value):null
        });
        message.textContent="Guardada como borrador. No aparece al público hasta aprobación.";
        editingPromotionId = null;
        await refresh();
      } catch(error) { message.textContent=error.message; onError(error); }
    };
    suggest.onclick = async () => {
      try {
        // This admin-triggered RPC is suitable only for isolated validation. A daily
        // scheduler must use a separate restricted internal function, never a public token.
        const count = await rpc("barber_promotions_generate_daily_suggestions",{p_token:token});
        message.textContent=`Se generaron ${Number(count)||0} sugerencias pendientes de revisión.`;
        await refresh();
      } catch(error) { message.textContent=error.message; onError(error); }
    };
    for (const promo of promotions) {
      const row = el("div",{className:"eb-item"});
      row.append(el("strong",{},promo.title), el("p",{className:"eb-status"},`Estado: ${promo.status} · ${promo.discount_type==="percent"?promo.discount_value+"%":"$"+promo.discount_value}`));
      row.append(el("p",{className:"eb-muted"},`${new Date(promo.starts_at).toLocaleString()} — ${new Date(promo.ends_at).toLocaleString()}`));
      const edit=el("button",{},"Editar");
      edit.onclick=()=>{
        editingPromotionId=promo.id;
        title.value=promo.title||"";
        desc.value=promo.description||"";
        type.value=promo.discount_type;
        value.value=promo.discount_value;
        const asLocalInput=(raw)=>{
          const d=new Date(raw);
          if(!Number.isFinite(d.getTime())) return "";
          const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);
          return local.toISOString().slice(0,16);
        };
        start.value=asLocalInput(promo.starts_at);
        end.value=asLocalInput(promo.ends_at);
        fromTime.value=promo.start_time ? String(promo.start_time).slice(0,5) : "";
        toTime.value=promo.end_time ? String(promo.end_time).slice(0,5) : "";
        dayChecks.forEach(check=>check.checked=(promo.weekdays||[]).map(Number).includes(Number(check.value)));
        const selected=new Set((promo.service_ids||[]).map(String));
        Array.from(servicesSelect.options).forEach(option=>option.selected=selected.has(option.value));
        maxUses.value=promo.max_uses ?? "";
        save.textContent="Guardar cambios como borrador";
        cancelEdit.hidden=false;
        content.querySelector("h3").textContent="Editar promoción";
        form.scrollIntoView({behavior:"smooth",block:"start"});
      };
      row.append(edit);
      if (promo.status==="pending_review" || promo.status==="draft") {
        const approve=el("button",{},"Aprobar");
        approve.onclick=()=>review(promo.id,"approved");
        const reject=el("button",{},"Rechazar");
        reject.onclick=()=>review(promo.id,"rejected");
        const pause=el("button",{},"Pausar");
        pause.onclick=()=>review(promo.id,"paused");
        row.append(approve,reject,pause);
      } else if (promo.status==="approved") {
        const pause=el("button",{},"Pausar");
        pause.onclick=()=>review(promo.id,"paused"); row.append(pause);
      }
      content.append(row);
    }
  }

  async function review(id, decision) {
    try {
      await rpc("barber_promotion_admin_review",{p_token:token,p_id:id,p_decision:decision});
      await refresh();
    } catch(error) { onError(error); }
  }

  function render() {
    if (view==="services") renderServices();
    else renderPromotions();
  }
  servicesTab.onclick=()=>{view="services";render();};
  promotionsTab.onclick=()=>{view="promotions";render();};
  renderServices();
  refresh();
  return { refresh, destroy:()=>host.remove() };
}
