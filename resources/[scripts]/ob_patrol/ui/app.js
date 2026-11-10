const app = document.querySelector('#app');
let panelData = {};
const post = (action, payload = {}) => fetch(`https://${GetParentResourceName()}/${action}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
}).catch(() => {});
const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]);
const routeLabel = (region) => { const amount = Number(region?.routes || 0); return `${amount} ${amount === 1 ? 'rota disponivel' : 'rotas disponiveis'}`; };

function renderRoutes(routes) {
  const list = document.querySelector('#routeList');
  list.innerHTML = (routes || []).map((route) => `<article class="route-card" data-id="${Number(route.id)}"><div class="route-fields"><input class="route-name" maxlength="64" value="${escapeHtml(route.label)}"><select class="route-region"><option value="south" ${route.region === 'south' ? 'selected' : ''}>Sul</option><option value="north" ${route.region === 'north' ? 'selected' : ''}>Norte</option></select><span>${Number(route.points)} pontos</span></div><div class="route-actions"><button class="save-route">Salvar dados</button><button class="record-route">Regravar pontos</button><button class="delete-route danger">Excluir</button></div></article>`).join('') || '<div class="empty">Nenhuma rota cadastrada.</div>';
  list.querySelectorAll('.route-card').forEach((card) => {
    const id = Number(card.dataset.id);
    const data = () => ({ id, routeId: id, label: card.querySelector('.route-name').value.trim(), region: card.querySelector('.route-region').value });
    card.querySelector('.save-route').addEventListener('click', () => post('adminUpdateRoute', data()));
    card.querySelector('.record-route').addEventListener('click', () => post('adminStartRecording', data()));
    card.querySelector('.delete-route').addEventListener('click', () => { if (window.confirm('Excluir esta rota e todos os pontos dela?')) post('adminDeleteRoute', { id }); });
  });
}

function update(payload) {
  panelData = payload || {};
  const current = panelData.group || { members: [], isLeader: true, maxMembers: 4 };
  const members = current.members || [];
  const active = panelData.work?.active === true;
  const adminOnly = panelData.adminOnly === true;
  document.querySelector('#southRoutes').textContent = routeLabel(panelData?.regions?.south);
  document.querySelector('#northRoutes').textContent = routeLabel(panelData?.regions?.north);
  const normalLimit = Number(panelData?.speedLimit || 60);
  document.querySelector('#speedLimit').textContent = panelData.limiterEnabled === false ? 'Desativado' : `${normalLimit} km/h`;
  document.querySelector('#groupCount').textContent = `${members.length || 1}/${current.maxMembers || 4} integrantes`;
  document.querySelector('#members').innerHTML = members.map((member) => `<div class="person"><span><b>${escapeHtml(member.name)}</b><small>${member.leader ? 'Lider' : 'Integrante'}</small></span><em>${member.leader ? '👑' : '🛡️'}</em></div>`).join('');
  const memberIds = new Set(members.map((member) => Number(member.id)));
  const nearby = (panelData.nearby || []).filter((player) => !memberIds.has(Number(player.id)));
  document.querySelector('#nearby').innerHTML = nearby.length ? nearby.map((player) => `<div class="person"><span><b>${escapeHtml(player.name)}</b><small>ID ${Number(player.id)}</small></span><button class="invite" data-id="${Number(player.id)}" ${!current.isLeader || active || members.length >= current.maxMembers ? 'disabled' : ''}>Convidar</button></div>`).join('') : '<div class="empty">Nenhum policial proximo.</div>';
  document.querySelectorAll('.invite').forEach((button) => button.addEventListener('click', () => post('invite', { id: Number(button.dataset.id) })));
  document.querySelectorAll('.region').forEach((button) => { button.disabled = !current.isLeader || active; });
  document.querySelector('#leaveGroup').disabled = active || members.length <= 1;
  document.querySelector('#patrolPanel').classList.toggle('hidden', adminOnly);
  document.querySelector('#patrolFooter').classList.toggle('hidden', adminOnly);
  document.querySelector('#activeStatus').classList.toggle('hidden', !active || adminOnly);
  document.querySelector('#stopPatrol').classList.toggle('hidden', !active || !current.isLeader);
  document.querySelector('#title').textContent = adminOnly ? 'Gerenciador de rotas' : (active ? 'Patrulha em andamento' : 'Iniciar patrulha');
  document.querySelector('#subtitle').textContent = adminOnly ? 'Painel separado da staff para administrar os trajetos da patrulha.' : (active ? 'A ronda continua automaticamente ate o lider encerra-la.' : 'Escolha a regiao. A ronda continuara trocando de rota automaticamente.');
  if (active) {
    document.querySelector('#activeRoute').textContent = panelData.work.routeLabel || 'Rota atual';
    document.querySelector('#activeProgress').textContent = `Checkpoint ${panelData.work.checkpoint}/${panelData.work.total}`;
  }
  document.querySelector('#routeAdmin').classList.toggle('hidden', !adminOnly);
  if (adminOnly) renderRoutes(panelData.staffRoutes || []);
}

document.querySelectorAll('.region').forEach((button) => button.addEventListener('click', () => post('selectRegion', { region: button.dataset.region })));
document.querySelector('#close').addEventListener('click', () => post('close'));
document.querySelector('#leaveGroup').addEventListener('click', () => post('leaveGroup'));
document.querySelector('#stopPatrol').addEventListener('click', () => post('stopPatrol'));
document.querySelector('#newRoute').addEventListener('click', () => {
  const label = document.querySelector('#newRouteLabel').value.trim();
  const region = document.querySelector('#newRouteRegion').value;
  if (label.length >= 3) post('adminStartRecording', { label, region });
});
window.addEventListener('keydown', (event) => { if (event.key === 'Escape') post('close'); });
window.addEventListener('message', (event) => {
  const { action, payload } = event.data || {};
  if (action === 'open') { update(payload); app.classList.remove('hidden'); }
  if (action === 'update') update(payload);
  if (action === 'close') app.classList.add('hidden');
});
