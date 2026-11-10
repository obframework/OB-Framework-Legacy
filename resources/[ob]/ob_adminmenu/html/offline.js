(() => {
  const page = document.querySelector('#offline-page');
  const results = document.querySelector('#offline-results');
  const detail = document.querySelector('#offline-detail');
  const feedback = document.querySelector('#offline-feedback');
  const query = document.querySelector('#offline-query');
  const wipeButton = document.querySelector('#offline-wipe-open');
  let bootstrap = null;
  let selected = null;

  const esc = value => escapeHtml(value);
  const fmt = value => value ? new Date(value).toLocaleString('pt-BR') : 'Nao informado';
  const call = (name, data={}) => post(name, data);
  const say = (message, type='error') => {
    feedback.textContent = message || '';
    feedback.className = message ? `feedback ${type}` : 'feedback hidden';
  };
  const tag = (label, kind='') => `<span class="offline-tag ${kind}">${esc(label)}</span>`;

  async function open() {
    homePage.classList.add('hidden'); garagePage.classList.add('hidden'); blackoutPage.classList.add('hidden'); page.classList.remove('hidden');
    title.textContent = 'Jogadores offline'; description.textContent = 'Contas, personagens e operacoes administrativas protegidas';
    say(''); detail.innerHTML = '<p>Selecione um personagem para consultar os dados.</p>';
    const response = await call('offlineBootstrap');
    if (!response.ok) return say(response.error || 'Nao foi possivel abrir o gerenciador.');
    bootstrap = response.data; wipeButton.classList.toggle('hidden', bootstrap.isOwner !== true);
    query.focus(); await search();
  }

  async function search() {
    say(''); results.innerHTML = '<p>Consultando...</p>';
    const response = await call('offlineSearch', { query: query.value.trim() });
    if (!response.ok) { results.innerHTML = '<p>Consulta indisponivel.</p>'; return say(response.error); }
    const rows = response.data || [];
    results.innerHTML = rows.length ? '' : '<p>Nenhum jogador encontrado.</p>';
    rows.forEach(row => {
      const button = document.createElement('button');
      button.type='button'; button.className='offline-result'; button.dataset.userId=row.user_id || '';
      const name = row.user_id ? `${row.firstname || ''} ${row.lastname || ''}`.trim() : (row.display_name || 'Conta sem personagem');
      const tags = [row.online && tag('ONLINE','success'), row.banned && tag('BANIDA','danger'), row.admin_role && tag(row.admin_role), row.deleted_at && tag('EXCLUIDO','danger'), row.blocked_at && tag('BLOQUEADO','danger')].filter(Boolean).join('');
      button.innerHTML=`<strong>${esc(name || 'Sem nome')}</strong><span>Conta #${esc(row.player_id)}${row.user_id ? ` · ID fixo ${esc(row.user_id)}` : ''}</span><div class="offline-tags">${tags}</div>`;
      button.disabled=!row.user_id;
      button.onclick=()=>load(row.user_id,button);
      results.append(button);
    });
  }

  function inventoryHtml(items) {
    if (!items.length) return '<p>Inventario vazio ou ainda nao criado.</p>';
    return `<div class="offline-items">${items.map(item=>`<div class="offline-item" title="${esc(JSON.stringify(item.metadata || {}))}"><code>#${esc(item.slot)}</code><strong>${esc(item.name)}</strong><span>${esc(item.amount)}x</span></div>`).join('')}</div>`;
  }

  function roleOptions(current) {
    return (bootstrap.roles || []).map(role=>`<option value="${esc(role.key)}" ${role.key===current?'selected':''}>${esc(role.label)}</option>`).join('');
  }

  function render(data) {
    selected=data; const a=data.account,c=data.character, banned=!!data.ban;
    const characters=(data.characters||[]).map(row=>`<div class="offline-character"><strong>${esc(`${row.firstname||''} ${row.lastname||''}`.trim()||'Sem nome')}</strong> · ID ${esc(row.user_id)} · ${esc(row.admin_role||'player')}${row.online?' · ONLINE':''}${row.deleted_at?' · excluido':''}${row.blocked_at?' · bloqueado':''}</div>`).join('');
    detail.innerHTML=`
      <div class="offline-heading"><div><small>CONTA #${esc(a.playerId)}</small><h2>${esc(`${c.firstname||''} ${c.lastname||''}`.trim())}</h2><p>ID fixo ${esc(c.userId)} · ${a.online?'online':'offline'}</p></div>${banned?tag('CONTA BANIDA','danger'):''}</div>
      <div class="offline-account"><div class="offline-stat"><small>NOME CFX</small><strong>${esc(a.displayName||'Nao informado')}</strong></div><div class="offline-stat"><small>PRIMEIRO ACESSO</small><strong>${esc(fmt(a.firstSeen))}</strong></div><div class="offline-stat"><small>ULTIMO ACESSO</small><strong>${esc(fmt(a.lastSeen))}</strong></div></div>
      <div class="offline-section"><div class="offline-section-title"><h3>Personagens da conta</h3><small>${(data.characters||[]).length} registro(s)</small></div><div class="offline-character-list">${characters||'<p>Nenhum personagem.</p>'}</div></div>
      <div class="offline-section"><div class="offline-section-title"><h3>Inventario offline</h3><small>${(data.inventory||[]).length} slot(s)</small></div>${inventoryHtml(data.inventory||[])}</div>
      ${data.isOwner?`<div class="offline-section"><div class="offline-section-title"><h3>Cargo administrativo</h3><small>somente owner</small></div><div class="offline-role-row"><label>Cargo<select id="offline-role">${roleOptions(c.role)}</select></label><button id="offline-role-save" type="button">Salvar cargo</button></div></div>`:''}
      ${data.canBan?`<div class="offline-section"><div class="offline-section-title"><h3>Banimento da conta</h3><small>${banned?`Ativo · ${esc(data.ban.reason)}`:'Sem ban ativo'}</small></div>${banned?'<button id="offline-unban" type="button">Remover banimento</button>':`<div class="offline-ban-grid"><label>Motivo<input id="offline-ban-reason" maxlength="255" placeholder="Motivo obrigatorio"></label><label>Horas (0 = permanente)<input id="offline-ban-hours" type="number" min="0" max="87600" value="0"></label><button id="offline-ban" class="offline-danger" type="button">Banir conta</button></div>`}</div>`:''}
      ${data.canDeleteCharacter&&!c.deleted?`<div class="offline-section"><h3>Excluir personagem</h3><p class="offline-warning">Exclusao logica e recuperavel. O personagem precisa estar offline e sem cargo de staff.</p><div class="offline-confirm-row"><label>Digite EXCLUIR PERSONAGEM ${esc(c.userId)}<input id="offline-character-confirm"></label><button id="offline-character-delete" class="offline-danger" type="button">Excluir personagem</button></div></div>`:''}
      ${data.isOwner?`<div class="offline-section offline-wipe"><h3>Excluir conta inteira</h3><p class="offline-warning">Cria arquivo de seguranca, exclui personagens e dados vinculados, remove ban e solicita a desvinculacao do Discord. IDs intermediarios nao sao reciclados automaticamente.</p><div class="offline-confirm-row"><label>Digite EXCLUIR CONTA ${esc(a.playerId)}<input id="offline-account-confirm"></label><button id="offline-account-delete" class="offline-danger" type="button">Excluir conta</button></div></div>`:''}`;
    bindActions();
  }

  async function load(userId,button) {
    document.querySelectorAll('.offline-result').forEach(node=>node.classList.remove('active')); button?.classList.add('active');
    detail.innerHTML='<p>Carregando conta e inventario...</p>'; say('');
    const response=await call('offlineDetails',{userId});
    if(!response.ok){detail.innerHTML='<p>Nao foi possivel carregar.</p>';return say(response.error);}
    render(response.data);
  }

  async function refresh(message) {
    const userId=selected?.character?.userId; if(!userId)return;
    const response=await call('offlineDetails',{userId});
    if(response.ok){render(response.data);say(message||'Dados atualizados.','success');await search();}else say(response.error);
  }

  function bindActions() {
    document.querySelector('#offline-role-save')?.addEventListener('click',async()=>{const r=await call('offlineSetRole',{userId:selected.character.userId,role:document.querySelector('#offline-role').value});r.ok?refresh(r.message):say(r.error);});
    document.querySelector('#offline-ban')?.addEventListener('click',async()=>{const r=await call('offlineBan',{userId:selected.character.userId,reason:document.querySelector('#offline-ban-reason').value,hours:document.querySelector('#offline-ban-hours').value});r.ok?refresh(r.message):say(r.error);});
    document.querySelector('#offline-unban')?.addEventListener('click',async()=>{const r=await call('offlineUnban',{userId:selected.character.userId});r.ok?refresh(r.message):say(r.error);});
    document.querySelector('#offline-character-delete')?.addEventListener('click',async()=>{const r=await call('offlineDeleteCharacter',{userId:selected.character.userId,confirm:document.querySelector('#offline-character-confirm').value});r.ok?refresh(r.message):say(r.error);});
    document.querySelector('#offline-account-delete')?.addEventListener('click',async()=>{const r=await call('offlineDeleteAccount',{playerId:selected.account.playerId,confirm:document.querySelector('#offline-account-confirm').value});if(r.ok){selected=null;detail.innerHTML='<p>Conta excluida.</p>';say(r.message,'success');await search();}else say(r.error);});
  }

  async function wipeDialog() {
    const status=await call('offlineWipeStatus');
    if(!status.ok)return say(status.error);
    const confirmation=status.data.confirmation||'ATIVAR MODO WIPE';
    detail.innerHTML=`<div class="offline-section offline-wipe"><small>OPERACAO CRITICA</small><h2>Modo wipe</h2><p class="offline-warning">Ao confirmar, todos os outros jogadores serao expulsos imediatamente. O owner que iniciou o processo permanecera conectado e sua conta sera protegida. Novas conexoes serao bloqueadas enquanto todas as contas sem personagem staff forem arquivadas e excluidas. Contas que possuam ao menos um personagem staff tambem serao preservadas.</p><p class="offline-wipe-state">${status.data.running?'O modo wipe ja esta em andamento.':'O processo comeca imediatamente e nao pode ser cancelado pelo painel.'}</p><div class="offline-confirm-row"><label>Digite exatamente <strong>${esc(confirmation)}</strong><input id="offline-wipe-confirm" autocomplete="off" spellcheck="false"></label><button id="offline-wipe-run" class="offline-danger" type="button" ${status.data.running?'disabled':''}>Ativar modo wipe</button></div></div>`;
    document.querySelector('#offline-wipe-run')?.addEventListener('click',async()=>{
      const button=document.querySelector('#offline-wipe-run');
      button.disabled=true;
      const r=await call('offlineWipe',{confirm:document.querySelector('#offline-wipe-confirm').value});
      if(r.ok){say(r.message,'success');detail.innerHTML='<div class="offline-section offline-wipe"><h2>Modo wipe iniciado</h2><p>Os outros jogadores serao desconectados e a exclusao das contas nao-staff comecara automaticamente. Sua conta permanecera protegida e conectada.</p></div>';}
      else{button.disabled=false;say(r.error);}
    });
  }

  document.querySelector('#offline-search').onsubmit=event=>{event.preventDefault();search();};
  document.querySelector('#offline-back').onclick=showHome;
  wipeButton.onclick=wipeDialog;
  window.addEventListener('message',event=>{if((event.data||{}).action==='offlineOpen')open();});
})();
