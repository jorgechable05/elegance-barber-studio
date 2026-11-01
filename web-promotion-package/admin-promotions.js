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
  const packagesTab = el("button", {}, "Paquetes");
  const historyTab = el("button", {}, "Demanda y margen");
  tabs.append(servicesTab, promotionsTab, packagesTab, historyTab);
  host.append(tabs);

  const content = el("div");
  host.append(content);
  root.append(host);

  let services = [];
  let promotions = [];
  let packages = [];
  let historyMetrics = [];
  let metrics = [];
  let suggestionSettings = {enabled:true, discount_percent:10, max_suggestions_per_day:3, opportunity_window_hours:24};
  let view = "services";
  let editingPromotionId = null;
  let editingPackageId = null;

  const formField = (label, input) => {
    const wrapper = el("label");
    wrapper.append(el("span", {}, label), input);
    return wrapper;
  };

  async function refresh() {
    try {
      const [serviceRows, promotionRows, packageRows] = await Promise.all([
        rpc("barber_services_admin_list", {p_token:token}),
        rpc("barber_promotions_admin_list", {p_token:token}),
        rpc("barber_service_package_admin_list", {p_token:token}),
      ]);
      services = Array.isArray(serviceRows) ? serviceRows : [];
      promotions = Array.isArray(promotionRows) ? promotionRows : [];
      packages = Array.isArray(packageRows) ? packageRows : [];
      const [metricRows, settingsRows, historyRows] = await Promise.all([
        rpc("barber_promotions_admin_metrics", {p_token:token}).catch(() => null),
        rpc("barber_promotion_suggestion_settings_admin_get", {p_token:token}).catch(() => null),
        rpc("barber_service_sales_history_admin_list", {p_token:token,p_lookback_days:30}).catch(() => null),
      ]);
      metrics = Array.isArray(metricRows) ? metricRows : [];
      historyMetrics = Array.isArray(historyRows) ? historyRows : [];
      if (Array.isArray(settingsRows) && settingsRows[0]) suggestionSettings = settingsRows[0];
      else if (settingsRows && !Array.isArray(settingsRows)) suggestionSettings = settingsRows;
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
    const unitCost = el("input", {type:"number", min:"0", step:"0.01", placeholder:"Déjalo vacío si el costo es desconocido"});
    const order = el("input", {type:"number", min:"0", step:"1", value:"100"});
    const active = el("input", {type:"checkbox"});
    const activeWrap = formField("Servicio activo", active);
    form.append(formField("Nombre",name), formField("Descripción",desc), formField("Duración (minutos)",duration), formField("Precio normal",price), formField("Costo unitario real (opcional)",unitCost), formField("Orden",order), activeWrap);
    const save = el("button", {type:"submit"}, "Crear servicio");
    const status = el("p", {className:"eb-muted"});
    form.append(save);
    content.append(el("h3", {}, "Catálogo de servicios"), form, status);
    form.onsubmit = async event => {
      event.preventDefault();
      try {
        const savedService = await rpc("barber_service_admin_save", {
          p_token:token, p_id:null, p_name:name.value.trim(), p_description:desc.value.trim(),
          p_duration_minutes:Number(duration.value), p_price:Number(price.value),
          p_is_active:active.checked, p_display_order:Number(order.value)
        });
        if (unitCost.value.trim() !== "") {
          await rpc("barber_service_unit_cost_admin_save", {p_token:token,p_service_id:savedService.id,p_unit_cost:Number(unitCost.value)});
        }
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
        order.value = service.display_order; active.checked = !!service.is_active; unitCost.value = service.unit_cost ?? "";
        const originalSubmit = form.onsubmit;
        form.onsubmit = async event => {
          event.preventDefault();
          try {
            await rpc("barber_service_admin_save", {
              p_token:token, p_id:service.id, p_name:name.value.trim(), p_description:desc.value.trim(),
              p_duration_minutes:Number(duration.value), p_price:Number(price.value),
              p_is_active:active.checked, p_display_order:Number(order.value)
            });
            if (unitCost.value.trim() !== "") {
              await rpc("barber_service_unit_cost_admin_save", {p_token:token,p_service_id:service.id,p_unit_cost:Number(unitCost.value)});
            }
            form.onsubmit = originalSubmit; await refresh();
          } catch(error) { status.textContent=error.message; onError(error); }
        };
        save.textContent = "Guardar cambios";
      };
      row.append(edit); content.append(row);
    }
  }


  function renderPackages() {
    content.replaceChildren();
    const form=el("form",{className:"eb-grid"});
    const name=el("input",{type:"text",required:true});
    const description=el("textarea");
    const price=el("input",{type:"number",min:"0",step:"0.01",required:true,value:"0"});
    const active=el("input",{type:"checkbox"});active.checked=true;
    const serviceSelect=el("select");serviceSelect.multiple=true;
    for(const service of services.filter(s=>s.is_active)) serviceSelect.append(el("option",{value:String(service.id)},service.name+" — $"+Number(service.price).toFixed(2)));
    const status=el("p",{className:"eb-muted"},"Un paquete requiere dos o más servicios activos y un precio no mayor que su suma. La validación final ocurre en el servidor.");
    const save=el("button",{type:"submit"},editingPackageId?"Guardar paquete":"Crear paquete");
    const cancel=el("button",{type:"button"},"Cancelar edición");cancel.hidden=!editingPackageId;
    form.append(formField("Nombre del paquete",name),formField("Descripción",description),formField("Precio conjunto",price),formField("Servicios incluidos (mínimo 2)",serviceSelect),formField("Paquete activo",active),save,cancel);
    content.append(el("h3",{},editingPackageId?"Editar paquete":"Paquetes de varios servicios"),form,status);
    cancel.onclick=()=>{editingPackageId=null;renderPackages();};
    form.onsubmit=async event=>{
      event.preventDefault();
      try {
        const ids=Array.from(serviceSelect.selectedOptions).map(o=>Number(o.value));
        if(ids.length<2) throw new Error("Selecciona al menos dos servicios.");
        await rpc("barber_service_package_admin_save",{p_token:token,p_id:editingPackageId,p_name:name.value.trim(),
          p_description:description.value.trim(),p_price:Number(price.value),p_is_active:active.checked,p_service_ids:ids});
        editingPackageId=null;await refresh();
      } catch(error){status.textContent=error.message;onError(error);}
    };
    for(const pack of packages){
      const row=el("div",{className:"eb-item"});
      row.append(el("strong",{},pack.name),el("p",{},(pack.service_names||[]).join(" + ")),
        el("p",{},`Precio paquete ${Number(pack.price).toFixed(2)} · Precio por separado ${Number(pack.base_total).toFixed(2)} · Ahorro ${(Number(pack.base_total)-Number(pack.price)).toFixed(2)} · Duración ${Number(pack.duration_minutes)} min · ${pack.is_active?"Activo":"Inactivo"}`));
      const edit=el("button",{},"Editar");
      edit.onclick=()=>{editingPackageId=pack.id;name.value=pack.name;description.value=pack.description||"";price.value=pack.price;active.checked=!!pack.is_active;
        const selected=new Set((pack.service_ids||[]).map(String));Array.from(serviceSelect.options).forEach(o=>o.selected=selected.has(o.value));
        save.textContent="Guardar paquete";cancel.hidden=false;form.scrollIntoView({behavior:"smooth",block:"start"});};
      row.append(edit);content.append(row);
    }
  }

  function renderHistory() {
    content.replaceChildren();
    content.append(el("h3",{},"Ventas y margen estimado por servicio"));
    content.append(el("p",{className:"eb-muted"},"Periodo: últimos 30 días. El ingreso se atribuye desde ventas y artículos de paquete. El margen solo se calcula cuando existe costo unitario capturado en el momento de la venta; las ventas antiguas sin ese dato no se rellenan retrospectivamente."));
    for(const item of historyMetrics){
      const row=el("div",{className:"eb-item"});
      const margin=item.margin_percent==null?"No disponible":Number(item.margin_percent).toFixed(1)+"%";
      const coverage=Number(item.margin_coverage_percent||0).toFixed(0)+"%";
      row.append(el("strong",{},item.service_name),
        el("p",{},`Ventas: ${Number(item.sales_count||0)} · Ingreso atribuido: ${Number(item.revenue||0).toFixed(2)}`),
        el("p",{},`Margen estimado: ${item.estimated_margin==null?"no disponible":"$"+Number(item.estimated_margin).toFixed(2)} · % margen: ${margin} · Cobertura de costos: ${coverage} · Muestra de costos: ${Number(item.margin_sample_count||0)}`));
      content.append(row);
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
    content.append(el("h3",{},editingPromotionId ? "Editar promoción" : "Crear promoción"));

    const settingsForm = el("form",{className:"eb-grid"});
    const suggestionsEnabled = el("input",{type:"checkbox"});
    suggestionsEnabled.checked = suggestionSettings.enabled !== false;
    const suggestionPercent = el("input",{type:"number",min:"1",max:"90",step:"0.5",value:String(suggestionSettings.discount_percent ?? 10)});
    const suggestionLimit = el("input",{type:"number",min:"1",max:"10",step:"1",value:String(suggestionSettings.max_suggestions_per_day ?? 3)});
    const suggestionWindow = el("input",{type:"number",min:"1",max:"168",step:"1",value:String(suggestionSettings.opportunity_window_hours ?? 24)});
    const saveSettings = el("button",{type:"submit"},"Guardar reglas diarias");
    const settingsStatus = el("p",{className:"eb-muted"},"Las sugerencias priorizan ventas del periodo y margen estimado con costos capturados al cobrar. Ventas antiguas sin costo guardado no se usan para inventar márgenes; con datos insuficientes, la sugerencia queda identificada como heurística.");
    settingsForm.append(
      formField("Generar sugerencias diariamente",suggestionsEnabled),
      formField("Descuento sugerido (%)",suggestionPercent),
      formField("Máximo de sugerencias por día",suggestionLimit),
      formField("Ventana de oportunidad (horas)",suggestionWindow),
      saveSettings
    );
    settingsForm.onsubmit = async event => {
      event.preventDefault();
      try {
        const saved = await rpc("barber_promotion_suggestion_settings_admin_save",{
          p_token:token,p_enabled:suggestionsEnabled.checked,
          p_discount_percent:Number(suggestionPercent.value),
          p_max_suggestions_per_day:Number(suggestionLimit.value),
          p_opportunity_window_hours:Number(suggestionWindow.value)
        });
        suggestionSettings = saved || {enabled:suggestionsEnabled.checked,discount_percent:Number(suggestionPercent.value),max_suggestions_per_day:Number(suggestionLimit.value),opportunity_window_hours:Number(suggestionWindow.value)};
        settingsStatus.textContent = "Reglas diarias guardadas.";
      } catch(error) { settingsStatus.textContent = error.message; onError(error); }
    };
    content.append(el("h3",{},"Reglas de sugerencias diarias"),settingsForm,settingsStatus,
      el("p",{className:"eb-muted"},"Métricas de promociones · reservas asociadas e importe reservado; no representa ventas cobradas."));
    form.append(save);
    content.append(form,cancelEdit,suggest,message);
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
      const metric = metrics.find(item => String(item.id) === String(promo.id));
      if (metric) {
        row.append(el("p",{className:"eb-muted"},`Reservas: ${Number(metric.reservation_count||0)} · Importe reservado: ${Number(metric.booked_revenue||0).toFixed(2)} · Contador de usos: ${Number(metric.usage_counter||0)} · ${promo.suggestion_evidence?.basis || "sin evidencia de sugerencia"}`));
      }
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
      const duplicate=el("button",{},"Duplicar");
      duplicate.onclick=async()=>{
        try {
          await rpc("barber_promotion_admin_duplicate",{p_token:token,p_id:promo.id});
          await refresh();
        } catch(error) { onError(error); }
      };
      row.append(duplicate);
      const remove=el("button",{},"Eliminar");
      remove.onclick=async()=>{
        if (!window.confirm("¿Eliminar esta promoción? Solo se pueden borrar ofertas sin uso ni reservas asociadas.")) return;
        try {
          await rpc("barber_promotion_admin_delete",{p_token:token,p_id:promo.id});
          await refresh();
        } catch(error) { onError(error); }
      };
      row.append(remove);
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
    else if (view==="promotions") renderPromotions();
    else if (view==="packages") renderPackages();
    else renderHistory();
  }
  servicesTab.onclick=()=>{view="services";render();};
  promotionsTab.onclick=()=>{view="promotions";render();};
  packagesTab.onclick=()=>{view="packages";render();};
  historyTab.onclick=()=>{view="history";render();};
  renderServices();
  refresh();
  return { refresh, destroy:()=>host.remove() };
}
