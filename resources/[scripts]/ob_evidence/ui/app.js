const terminal=document.querySelector('#terminal');
const detail=document.querySelector('#detail');
const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'ob_evidence';
let state={};
let currentView='dashboard';
const post=(name,data={})=>fetch(`https://${resource}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
const esc=value=>String(value??'').replace(/[&<>'"]/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
const date=value=>value?new Date(Number(value)*1000).toLocaleString('pt-BR'):'nao informado';
const shortDate=value=>value?new Date(Number(value)*1000).toLocaleDateString('pt-BR'):'-';
const empty=text=>`<div class="empty">${esc(text)}</div>`;

function setView(view){
  currentView=view;
  document.querySelectorAll('.nav').forEach(button=>button.classList.toggle('active',button.dataset.view===view));
  document.querySelectorAll('.view').forEach(page=>page.classList.toggle('active',page.dataset.page===view));
}

function renderWeapons(){
  const select=document.querySelector('#weaponSelect');
  const previous=select.value;
  const weapons=Array.isArray(state.weapons)?state.weapons:[];
  select.innerHTML='<option value="">Selecione uma arma guardada...</option>'+weapons.map(weapon=>{
    const value=`${Number(weapon.slot)||0}|${encodeURIComponent(weapon.itemName||'')}`;
    return `<option value="${esc(value)}">Slot ${Number(weapon.slot)||0} · ${esc(weapon.label)} · ${esc(weapon.serial)}</option>`;
  }).join('');
  if([...select.options].some(option=>option.value===previous))select.value=previous;
  document.querySelector('#kitStatus').textContent=(state.forensicKitCount||0)>0?'Kit disponivel':'Kit ausente';
  document.querySelector('#kitStatus').classList.toggle('ok',(state.forensicKitCount||0)>0);
  document.querySelector('#scanWeapon').disabled=!state.databaseReady||!(state.forensicKitCount>0)||weapons.length===0||!select.value;
}

function renderArchive(filter=''){
  const term=filter.trim().toLowerCase();
  const rows=(Array.isArray(state.archive)?state.archive:[]).filter(row=>`${row.id} ${row.ammo_type}`.toLowerCase().includes(term));
  document.querySelector('#archiveRows').innerHTML=rows.length?rows.map(row=>`<div class="table-row ballistic"><span class="code">#${Number(row.id)||0}</span><strong>${esc(row.ammo_type||'desconhecido')}</strong><span class="muted">${date(row.created_at)}</span><span class="muted">${date(row.expires_at)}</span></div>`).join(''):empty('Nenhum estojo ativo encontrado.');
}

function renderFingerprints(filter=''){
  const term=filter.trim().toLowerCase();
  const rows=(Array.isArray(state.registrations)?state.registrations:[]).filter(row=>`${row.fingerprint_code} ${row.person_name} ${row.user_id}`.toLowerCase().includes(term));
  document.querySelector('#fingerprintRows').innerHTML=rows.length?rows.map(row=>`<div class="table-row fingerprints"><span class="code">${esc(row.fingerprint_code)}</span><strong>${esc(row.person_name)}</strong><span class="muted">${esc(row.user_id)}</span><span class="muted">${date(row.registered_at)}</span></div>`).join(''):empty('Nenhuma digital cadastrada.');
}

function reportReference(report){return report.serial||report.archiveId&&`Arquivo #${report.archiveId}`||report.fingerprintCode||report.weaponItem||'Sem referencia'}
function renderReports(filter=''){
  const term=filter.trim().toLowerCase();
  const reports=(Array.isArray(state.reports)?state.reports:[]).filter(report=>`${report.id} ${report.reportType} ${reportReference(report)} ${report.description}`.toLowerCase().includes(term));
  document.querySelector('#reportRows').innerHTML=reports.length?reports.map(report=>`<div class="table-row reports"><span class="code">#${Number(report.id)||0}</span><strong>${esc(report.reportType)}</strong><span class="muted">${esc(reportReference(report))}</span><span class="muted">${date(report.createdAt)}</span><button class="row-button" data-report="${Number(report.id)||0}">›</button></div>`).join(''):empty('Nenhum laudo encontrado.');
  document.querySelectorAll('[data-report]').forEach(button=>button.onclick=()=>openReport(Number(button.dataset.report)));
}

function renderRecent(){
  const reports=(Array.isArray(state.reports)?state.reports:[]).slice(0,5);
  document.querySelector('#recentReports').innerHTML=reports.length?reports.map(report=>`<div class="compact-row"><b>#${Number(report.id)||0}</b><div><strong>${esc(report.reportType)}</strong><small>${esc(reportReference(report))}</small></div><time>${shortDate(report.createdAt)}</time></div>`).join(''):empty('Nenhum laudo emitido.');
}

function render(data){
  state=data||{};
  document.querySelector('#labName').textContent=state.label||'Laboratorio pericial';
  document.querySelector('#offline').classList.toggle('hidden',state.databaseReady!==false);
  document.querySelector('#connectionText').textContent=state.databaseReady===false?'ARQUIVO OFFLINE':'TERMINAL SEGURO';
  document.querySelector('#navCasing').textContent=state.casingCount||0;
  document.querySelector('#navFingerprint').textContent=state.fingerprintCount||0;
  document.querySelector('#statCasings').textContent=state.casingCount||0;
  document.querySelector('#statFingerprints').textContent=state.fingerprintCount||0;
  document.querySelector('#statWeapons').textContent=(state.weapons||[]).length;
  document.querySelector('#statReports').textContent=(state.reports||[]).length;
  document.querySelector('#casingCount').textContent=state.casingCount||0;
  document.querySelector('#fingerprintCount').textContent=state.fingerprintCount||0;
  document.querySelector('#retention').textContent=`${state.retentionDays||4} dias`;
  document.querySelector('#footerStats').textContent=`${(state.archive||[]).length} vestigios · ${(state.reports||[]).length} laudos carregados`;
  document.querySelector('#analyzeCasing').disabled=!state.databaseReady||!(state.casingCount>0);
  document.querySelector('#analyzeFingerprint').disabled=!state.databaseReady||!(state.fingerprintCount>0);
  renderWeapons();renderArchive(document.querySelector('#ballisticSearch').value);renderFingerprints(document.querySelector('#fingerprintSearch').value);renderReports(document.querySelector('#reportSearch').value);renderRecent();
}

function openReport(id){
  const report=(state.reports||[]).find(entry=>Number(entry.id)===Number(id));
  if(!report)return;
  document.querySelector('#detailTitle').textContent=`Laudo #${report.id} · ${report.reportType}`;
  document.querySelector('#detailMeta').innerHTML=`<span>${esc(reportReference(report))}</span><span>${date(report.createdAt)}</span>`;
  document.querySelector('#detailText').innerHTML=esc(report.description||'Laudo sem descricao.').replace(/\n/g,'<br>');
  detail.classList.remove('hidden');
}

window.addEventListener('message',event=>{
  const message=event.data||{};
  if(message.action==='close'){document.body.classList.remove('open');terminal.classList.add('hidden');detail.classList.add('hidden');terminal.setAttribute('aria-hidden','true');return;}
  if(message.action==='open'){document.body.classList.add('open');terminal.classList.remove('hidden');terminal.setAttribute('aria-hidden','false');setView('dashboard');render(message.payload);return;}
  if(message.action==='update')render(message.payload);
});

document.querySelectorAll('.nav').forEach(button=>button.onclick=()=>setView(button.dataset.view));
document.querySelectorAll('[data-go]').forEach(button=>button.onclick=()=>setView(button.dataset.go));
document.querySelectorAll('.refresh').forEach(button=>button.onclick=()=>post('refresh'));
document.querySelector('#close').onclick=()=>post('close');
document.querySelector('#detailClose').onclick=()=>detail.classList.add('hidden');
document.querySelector('#analyzeCasing').onclick=()=>post('analyzeCasing');
document.querySelector('#analyzeFingerprint').onclick=()=>post('analyzeFingerprint');
document.querySelector('#scanWeapon').onclick=()=>{
  const value=document.querySelector('#weaponSelect').value;
  if(!value)return;
  const separator=value.indexOf('|');
  post('scanWeapon',{slot:Number(value.slice(0,separator)),itemName:decodeURIComponent(value.slice(separator+1))});
};
document.querySelector('#weaponSelect').onchange=event=>{
  document.querySelector('#scanWeapon').disabled=!state.databaseReady||!(state.forensicKitCount>0)||!event.target.value;
};
document.querySelector('#ballisticSearch').oninput=event=>renderArchive(event.target.value);
document.querySelector('#fingerprintSearch').oninput=event=>renderFingerprints(event.target.value);
document.querySelector('#reportSearch').oninput=event=>renderReports(event.target.value);
window.addEventListener('keydown',event=>{if(event.key==='Escape'){if(!detail.classList.contains('hidden'))detail.classList.add('hidden');else post('close')}});
setInterval(()=>{document.querySelector('#clock').textContent=new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})},1000);
