const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function mountLoyaltyStaff({root,rpc,token,role='staff'}) {
  if(!root || typeof rpc!=='function' || !token) throw new Error('Falta sesión o conexión para fidelidad.');
  const qrUrl = `${window.location.origin}/fidelidad`;
  root.innerHTML = `
    <section style="background:#111;color:#f5f5f5;border:1px solid #39332a;border-radius:14px;padding:16px;margin:12px 0;font-family:Arial,sans-serif">
      <div style="display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:center">
        <div><h2 style="margin:0;color:#d4af37">Programa de fidelidad</h2><p style="color:#aaa;font-size:12px">Un solo QR para todos los clientes · 5 visitas = sorpresa especial</p></div>
        <button id="loyaltyRefresh" class="btn gold">Actualizar clientes</button>
      </div>
      <div style="display:grid;grid-template-columns:180px minmax(220px,1fr);gap:16px;align-items:center;margin:12px 0">
        <div style="background:#fff;padding:10px;border-radius:8px;text-align:center"><div id="loyaltyQr"></div><small style="color:#222;word-break:break-all">QR permanente</small></div>
        <div><b>Enlace público</b><p style="font-size:12px;color:#bbb;word-break:break-all">${escapeHtml(qrUrl)}</p><button id="loyaltyCopy" class="act">Copiar enlace</button><p style="font-size:12px;color:#aaa">El cliente registra nombre y teléfono. Las visitas solo las confirma el personal después del cobro.</p></div>
      </div>
      <hr style="border:0;border-top:1px solid #333;margin:16px 0">
      <h3>Buscar cliente y registrar visita</h3>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:8px">
        <input id="loyaltyPhone" class="input" placeholder="Teléfono del cliente">
        <button id="loyaltyFind" class="btn gold">Buscar cliente</button>
      </div>
      <div id="loyaltyCustomer" style="font-size:13px;color:#ddd;margin:10px 0">Busca al cliente por teléfono para ver su avance.</div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px">
        <input id="loyaltySaleId" class="input" type="number" min="1" step="1" placeholder="Folio/ID de venta ya cobrada">
        <input id="loyaltyEmployee" class="input" maxlength="80" placeholder="Empleado que atendió">
        <button id="loyaltyRecord" class="btn gold" disabled>Registrar visita cobrada</button>
      </div>
      <div id="loyaltyNotice" style="font-size:12px;margin:10px 0;color:#d4af37" role="status"></div>
      <hr style="border:0;border-top:1px solid #333;margin:16px 0">
      <h3>Clientes registrados</h3><div id="loyaltyList" style="font-size:12px;color:#bbb">Cargando…</div><h3>Premios de cortesía</h3><div id="loyaltyRewards" style="font-size:12px;color:#bbb">Cargando…</div>
    </section>`;
  let customer=null;
  const el=id=>root.querySelector('#'+id);
  if(window.QRCode) new QRCode(el('loyaltyQr'),{text:qrUrl,width:150,height:150,colorDark:'#000000',colorLight:'#ffffff',correctLevel:QRCode.CorrectLevel.M});
  else el('loyaltyQr').textContent='Carga QRCode para generar el código.';
  el('loyaltyCopy').onclick=async()=>{try{await navigator.clipboard.writeText(qrUrl);el('loyaltyNotice').textContent='Enlace copiado.';}catch{el('loyaltyNotice').textContent=qrUrl;}};
  async function refresh(){
    const rows=await rpc('barber_loyalty_list_customers',{p_token:token});
    el('loyaltyList').innerHTML=rows.length?rows.map(c=>`<div style="padding:9px;border-bottom:1px solid #333"><b>${escapeHtml(c.full_name)}</b> · ${escapeHtml(c.phone_masked)}<br>Visitas del ciclo: ${Number(c.visits_in_cycle)}/5 · Premios pendientes: ${Number(c.pending_rewards)} · Visitas históricas: ${Number(c.total_visits)}</div>`).join(''):'Todavía no hay clientes registrados.';
    const rewards=await rpc('barber_loyalty_list_rewards',{p_token:token});
    el('loyaltyRewards').innerHTML=rewards.length?rewards.map(r=>`<div style="padding:9px;border-bottom:1px solid #333"><b>${escapeHtml(r.customer_name)}</b> · ${escapeHtml(r.phone_masked)} · Ciclo ${Number(r.cycle_number)}<br>Estado: ${escapeHtml(r.status)} · ${new Date(r.earned_at).toLocaleDateString('es-MX')}${r.status==='pending'?` <button class="act ok" data-redeem="${escapeHtml(r.reward_id)}">Marcar sorpresa entregada</button>`:''}</div>`).join(''):'Todavía no hay premios generados.';
    el('loyaltyRewards').querySelectorAll('[data-redeem]').forEach(button=>button.addEventListener('click',async()=>{
      const employee=el('loyaltyEmployee').value.trim();
      if(!employee){el('loyaltyNotice').textContent='Escribe el nombre del empleado antes de entregar el premio.';return;}
      if(!confirm('¿Confirmas que la sorpresa especial ya fue entregada?'))return;
      try{await rpc('barber_loyalty_redeem_reward',{p_token:token,p_reward_id:button.dataset.redeem,p_employee:employee});el('loyaltyNotice').textContent='Premio marcado como entregado. El siguiente ciclo comienza desde cero.';await refresh();}
      catch(error){el('loyaltyNotice').textContent=error.message;}
    }));
  }
  async function find(){
    const rows=await rpc('barber_loyalty_lookup_customer',{p_token:token,p_phone:el('loyaltyPhone').value});
    customer=rows?.[0]||null;
    if(!customer){el('loyaltyCustomer').textContent='No encontramos ese teléfono. El cliente debe registrarse escaneando el QR único.';el('loyaltyRecord').disabled=true;return;}
    el('loyaltyCustomer').innerHTML=`<b>${escapeHtml(customer.full_name)}</b> · ${escapeHtml(customer.phone_masked)}<br>Progreso del ciclo ${Number(customer.cycle_number)}: <b>${Number(customer.visits_in_cycle)}/5</b> · Premios pendientes: ${Number(customer.pending_rewards)}`;
    el('loyaltyRecord').disabled=false;
  }
  el('loyaltyFind').onclick=()=>find().catch(e=>el('loyaltyNotice').textContent=e.message);
  el('loyaltyRecord').onclick=async()=>{
    if(!customer)return;
    const saleId=Number(el('loyaltySaleId').value);
    if(!Number.isSafeInteger(saleId)||saleId<1){el('loyaltyNotice').textContent='Ingresa el ID de una venta ya cobrada.';return;}
    try{
      const result=await rpc('barber_loyalty_record_visit',{p_token:token,p_customer_id:customer.customer_id,p_sale_id:saleId,p_employee:el('loyaltyEmployee').value.trim()});
      el('loyaltyNotice').textContent=result.reward_earned?'🎉 ¡Quinta visita! Se generó una sorpresa especial pendiente.':result.already_recorded?'Esta venta ya estaba contabilizada; no se duplicó.':`Visita ${result.visit_number} de 5 registrada.`;
      await find();await refresh();
    }catch(e){el('loyaltyNotice').textContent=e.message;}
  };
  el('loyaltyRefresh').onclick=()=>refresh().catch(e=>el('loyaltyNotice').textContent=e.message);
  refresh().catch(e=>el('loyaltyNotice').textContent=e.message);
}
