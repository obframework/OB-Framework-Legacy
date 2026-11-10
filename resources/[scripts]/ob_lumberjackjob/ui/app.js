const app = document.querySelector('#app');
const tabs = [...document.querySelectorAll('.tab')];
const nav = [...document.querySelectorAll('.nav')];
let panelData = null;
let previewLevel = 1;

const post = (action, payload = {}) => fetch(`https://${GetParentResourceName()}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }).catch(() => {});
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;
const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]);

function setTutorial(tutorial) {
  const value = String(tutorial?.youtubeUrl || '').trim();
  const match = value.match(/(?:youtu\.be\/|(?:youtube(?:-nocookie)?\.com)\/(?:watch\?v=|embed\/|shorts\/))([^?&#/]+)/i);
  const embed = match ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(match[1])}?rel=0` : '';
  document.querySelector('#tutorialTitle').textContent = tutorial?.title || 'Tutorial';
  document.querySelector('#tutorialEmpty').style.display = embed ? 'none' : 'block';
  const frame = document.querySelector('#tutorialVideo');
  frame.style.display = embed ? 'block' : 'none';
  frame.src = embed;
}

function selectTab(id) {
  tabs.forEach((node) => node.classList.toggle('active', node.id === id));
  nav.forEach((node) => node.classList.toggle('active', node.dataset.tab === id));
  document.querySelector('#title').textContent = ({ overview: 'Visão geral', progress: 'Progresso', cargo: 'Carga', group: 'Dupla', ranking: 'Ranking', tutorial: 'Tutorial' })[id];
}

function renderGroup(data) {
  const current = data.group || { members: [], isLeader: true, maxMembers: 2 };
  const members = current.members || [];
  const active = data.work?.active === true;
  document.querySelector('#groupCount').textContent = `${members.length || 1}/${current.maxMembers || 2}`;
  document.querySelector('#groupMembers').innerHTML = members.map((member) => `<div class="person"><span><b>${esc(member.name)}</b><small>${member.leader ? 'Líder' : 'Parceiro'}</small></span><em>${member.leader ? '👑' : '🪓'}</em></div>`).join('') || '<div class="empty">Você está trabalhando sozinho.</div>';
  const memberIds = new Set(members.map((member) => Number(member.id)));
  const nearby = (data.nearby || []).filter((player) => !memberIds.has(Number(player.id)));
  document.querySelector('#nearbyPlayers').innerHTML = nearby.length
    ? nearby.map((player) => `<div class="person"><span><b>${esc(player.name)}</b><small>ID ${Number(player.id)}</small></span><button class="invite" data-id="${Number(player.id)}" ${!current.isLeader || active || members.length >= current.maxMembers ? 'disabled' : ''}>Convidar</button></div>`).join('')
    : '<div class="empty">Nenhum jogador próximo.</div>';
  document.querySelectorAll('.invite').forEach((button) => button.addEventListener('click', () => post('invite', { id: Number(button.dataset.id) })));
  const leave = document.querySelector('#leaveGroup');
  leave.disabled = active || members.length <= 1;
  leave.title = active ? 'Finalize o trabalho primeiro' : '';
}

function renderPreview(progress) {
  previewLevel = Math.max(1, Math.min(10, previewLevel));
  const bonus = (previewLevel - 1) * Number(progress.paymentBonusStep || 3);
  document.querySelector('#previewTitle').textContent = `Nível: ${previewLevel}`;
  document.querySelector('#previewXp').textContent = `${(previewLevel - 1) * Number(progress.xpRequired || 600)} XP`;
  document.querySelector('#previewBonus').textContent = `+${bonus}%`;
  document.querySelector('#previewText').textContent = previewLevel === 1 ? 'Pagamento padrão da serraria.' : `+${bonus}% no pagamento das cargas entregues.`;
  document.querySelector('#prev').disabled = previewLevel === 1;
  document.querySelector('#next').disabled = previewLevel === 10;
}

function update(data) {
  if (!data) return;
  panelData = data;
  const progress = data.progress || {};
  const work = data.work || {};
  const progressPercent = Math.min(100, 100 * Number(progress.xpInLevel || 0) / Math.max(1, Number(progress.xpRequired || 1)));
  const cargoPercent = Math.min(100, 100 * Number(work.loaded || 0) / Math.max(1, Number(work.maxWood || 1)));
  document.querySelector('#level').textContent = progress.level || 1;
  document.querySelector('#xpText').textContent = `${progress.xpInLevel || 0} / ${progress.xpRequired || 0} XP`;
  document.querySelector('#xpBar').style.width = `${progressPercent}%`;
  document.querySelector('#completed').textContent = progress.completed || 0;
  document.querySelector('#earned').textContent = money(progress.totalEarned);
  document.querySelector('#bonus').textContent = `+${progress.paymentBonus || 0}%`;
  document.querySelector('#progressLevel').textContent = `Nível: ${progress.level || 1}`;
  document.querySelector('#progressBar').style.width = `${progressPercent}%`;
  document.querySelector('#progressDetails').textContent = `${Math.floor(progressPercent)}%`;
  document.querySelector('#workStatus').textContent = work.returning ? 'Devolvendo caminhão' : (work.active ? 'Em serviço' : 'Fora de serviço');
  document.querySelector('#workInfo').textContent = work.returning ? 'Retorne o caminhão ao pátio para receber.' : (work.active ? `Carga atual: ${work.loaded || 0}/${work.maxWood || 0} madeiras` : 'Fale com o responsável para começar');
  document.querySelector('#startWork').textContent = work.active ? 'Finalizar serviço' : 'Iniciar serviço';
  document.querySelector('#startWork').disabled = !data.group?.isLeader;
  document.querySelector('#cargoAmount').textContent = `${work.loaded || 0} / ${work.maxWood || 0}`;
  document.querySelector('#cargoBar').style.width = `${cargoPercent}%`;
  document.querySelector('#deliveryState').textContent = Number(work.loaded || 0) >= Number(work.maxWood || 1) ? 'Carga pronta para a serraria' : 'Aguardando carga completa';
  const board = data.leaderboard || {};
  const list = board.list || [];
  document.querySelector('#leaderboard').innerHTML = list.length ? list.map((entry) => `<div class="ranking-row"><span>#${entry.rank}</span><span>${entry.name || 'Desconhecido'}</span><b>${entry.xp || 0} XP</b></div>`).join('') : '<div class="empty">Ainda não há dados no ranking.</div>';
  document.querySelector('#rank').textContent = board.myRank ? `#${board.myRank}` : '#-';
  document.querySelector('#rankValue').textContent = `${board.myValue || 0} XP`;
  renderGroup(data);
  renderPreview(progress);
}

nav.forEach((button) => button.addEventListener('click', () => selectTab(button.dataset.tab)));
nav.forEach((button) => button.addEventListener('click', () => {
  if (button.dataset.tab === 'tutorial') document.querySelector('#title').textContent = 'Tutorial';
}));
document.querySelector('#close').addEventListener('click', () => post('close'));
document.querySelector('#startWork').addEventListener('click', () => post(panelData?.work?.active ? 'stop' : 'start'));
document.querySelector('#leaveGroup').addEventListener('click', () => post('leaveGroup'));
document.querySelector('#prev').addEventListener('click', () => { previewLevel--; renderPreview(panelData?.progress || {}); });
document.querySelector('#next').addEventListener('click', () => { previewLevel++; renderPreview(panelData?.progress || {}); });
window.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !app.classList.contains('hidden')) post('close'); });
window.addEventListener('message', (event) => {
  const { action, payload } = event.data || {};
  if (action === 'open') { app.classList.remove('hidden'); previewLevel = payload?.progress?.level || 1; setTutorial(payload?.tutorial); update(payload); selectTab('overview'); }
  if (action === 'update') update(payload);
  if (action === 'close') app.classList.add('hidden');
});
