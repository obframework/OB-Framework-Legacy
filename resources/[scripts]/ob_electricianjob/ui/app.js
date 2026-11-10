const app = document.querySelector('#app');
const nav = [...document.querySelectorAll('.nav')];
const tabs = [...document.querySelectorAll('.tab')];
let data = null;
let previewLevel = 1;
let rankMode = 'xp';

const post = (name, payload = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
}).catch(() => {});
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const money = value => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

function setTab(id) {
  tabs.forEach(tab => tab.classList.toggle('active', tab.id === id));
  nav.forEach(button => button.classList.toggle('active', button.dataset.tab === id));
  document.querySelector('#title').textContent = { overview: 'Visão geral', progress: 'Progresso', group: 'Dupla', ranking: 'Ranking', tutorial: 'Tutorial' }[id] || 'Eletricista';
}

function person(entry) {
  const name = String(entry.name || `ID ${entry.id}`);
  return `<article class="person"><span class="avatar">${esc(name.slice(0, 1).toUpperCase())}</span><span class="name">${esc(name)}${entry.leader ? '<small>Líder</small>' : ''}</span></article>`;
}

function tutorial(value) {
  const url = String(value?.youtubeUrl || '');
  const match = url.match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:watch\?v=|embed\/|shorts\/))([^?&#/]+)/i);
  const frame = document.querySelector('#tutorialVideo');
  document.querySelector('#tutorialTitle').textContent = value?.title || 'Tutorial';
  frame.src = match ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(match[1])}?rel=0` : '';
  frame.style.display = match ? 'block' : 'none';
  document.querySelector('#tutorialEmpty').style.display = match ? 'none' : 'block';
}

function renderLevelPreview() {
  const progress = data?.progress || {};
  const maxLevel = Number(progress.maxLevel || 10);
  const step = Number(progress.xpRequired || 500);
  const bonusStep = Number(progress.paymentBonusStep || 2.5);
  previewLevel = Math.max(1, Math.min(maxLevel, previewLevel));
  const bonus = Math.min(Number(progress.maxPaymentBonus || 22.5), (previewLevel - 1) * bonusStep);
  document.querySelector('#previewTitle').textContent = `Nível: ${previewLevel}`;
  document.querySelector('#previewXp').textContent = `${(previewLevel - 1) * step} XP`;
  document.querySelector('#previewMoney').textContent = `+${Number.isInteger(bonus) ? bonus : bonus.toFixed(1)}%`;
  document.querySelector('#previewBenefit').textContent = previewLevel === 1
    ? 'Pagamento base do serviço e reparos em caixas elétricas liberados.'
    : `Pagamento de cada reparo aumentado em ${Number.isInteger(bonus) ? bonus : bonus.toFixed(1)}%.`;
  document.querySelector('#previewPrev').disabled = previewLevel <= 1;
  document.querySelector('#previewNext').disabled = previewLevel >= maxLevel;
}

function renderRanking(board) {
  const repairs = rankMode === 'repairs';
  const current = board?.[repairs ? 'repairs' : 'xp'] || {};
  document.querySelector('#rankRepairs').classList.toggle('active-mini', repairs);
  document.querySelector('#rankXp').classList.toggle('active-mini', !repairs);
  document.querySelector('#rankValueTitle').textContent = repairs ? 'Reparos' : 'XP';
  document.querySelector('#rankSideTitle').textContent = repairs ? 'Mais reparos' : 'Mais experiência';
  document.querySelector('#myRank').textContent = current.myRank ? `#${current.myRank}` : '#-';
  document.querySelector('#myRankValue').textContent = `${current.myValue || 0} ${repairs ? 'reparos' : 'XP'}`;
  document.querySelector('#leaderboard').innerHTML = (current.list || []).map(entry => `
    <div class="ranking-row"><span>#${entry.rank || '-'}</span><span>${esc(entry.name || 'Desconhecido')}</span><b>${repairs ? (entry.repairs || 0) : `${entry.xp || 0} XP`}</b></div>
  `).join('') || '<div class="empty">Ainda não há dados no ranking.</div>';
}

function update(payload) {
  if (!payload) return;
  data = payload;
  const p = payload.progress || {};
  const w = payload.work || {};
  const g = payload.group || { members: [], maxMembers: 2, isLeader: true };
  const percent = Math.min(100, 100 * Number(p.xpInLevel || 0) / Math.max(1, Number(p.xpRequired || 1)));
  document.querySelector('#level').textContent = p.level || 1;
  document.querySelector('#xpText').textContent = `${p.xpInLevel || 0} / ${p.xpRequired || 500} XP`;
  document.querySelector('#xpBar').style.width = `${percent}%`;
  document.querySelector('#progressBar').style.width = `${percent}%`;
  document.querySelector('#progressLevel').textContent = `Nível: ${p.level || 1}`;
  document.querySelector('#progressText').textContent = `${Math.floor(percent)}%`;
  document.querySelector('#repairs').textContent = p.completed || 0;
  document.querySelector('#earned').textContent = money(p.totalEarned);
  document.querySelector('#bonus').textContent = `+${p.paymentBonus || 0}%`;
  document.querySelector('#status').textContent = w.active ? 'Em turno' : 'Fora de turno';
  document.querySelector('#statusInfo').textContent = w.active ? `Rota: ${w.batchCompleted || 0}/${w.batchSize || 5} serviços | ${w.repaired ? 'Finalize no caminhão' : `${w.stage || 1}/${w.stepCount || 3}: ${w.stepLabel || 'Reparo pendente'}`}` : 'Fale com o encarregado';
  document.querySelector('#start').textContent = w.active ? 'Finalizar turno' : 'Iniciar turno';
  document.querySelector('#start').classList.toggle('danger', !!w.active);
  document.querySelector('#start').disabled = g.isLeader === false;
  document.querySelector('#truck').classList.toggle('hidden', !w.active || !!w.vehicleNetId || g.isLeader === false);
  const members = g.members || [];
  document.querySelector('#groupCount').textContent = `${members.length}/${g.maxMembers || 2}`;
  document.querySelector('#members').innerHTML = members.map(person).join('') || '<div class="empty">Nenhum integrante.</div>';
  document.querySelector('#leaveGroup').classList.toggle('hidden', members.length <= 1 || !!w.active);
  const nearby = (payload.nearby || []).filter(entry => !members.some(member => Number(member.id) === Number(entry.id)));
  document.querySelector('#nearby').innerHTML = nearby.length ? nearby.map(entry => `<article class="person"><span class="avatar">${esc(String(entry.name).slice(0, 1).toUpperCase())}</span><span class="name">${esc(entry.name)}</span>${g.isLeader && !w.active && members.length < (g.maxMembers || 2) ? `<button class="invite" data-id="${Number(entry.id)}">Convidar</button>` : ''}</article>`).join('') : '<div class="empty">Ninguém próximo para convidar.</div>';
  document.querySelectorAll('.invite').forEach(button => { button.onclick = () => post('invite', { id: Number(button.dataset.id) }); });
  renderRanking(payload.leaderboard);
  renderLevelPreview();
}

nav.forEach(button => { button.onclick = () => setTab(button.dataset.tab); });
document.querySelector('#close').onclick = () => post('close');
document.querySelector('#start').onclick = () => post(data?.work?.active ? 'stop' : 'start');
document.querySelector('#truck').onclick = () => post('truck');
document.querySelector('#leaveGroup').onclick = () => post('leaveGroup');
document.querySelector('#previewPrev').onclick = () => { previewLevel -= 1; renderLevelPreview(); };
document.querySelector('#previewNext').onclick = () => { previewLevel += 1; renderLevelPreview(); };
document.querySelector('#rankRepairs').onclick = () => { rankMode = 'repairs'; renderRanking(data?.leaderboard); };
document.querySelector('#rankXp').onclick = () => { rankMode = 'xp'; renderRanking(data?.leaderboard); };
addEventListener('keydown', event => { if (event.key === 'Escape' && !app.classList.contains('hidden')) post('close'); });
addEventListener('message', event => {
  const { action, payload } = event.data || {};
  if (action === 'jobHud') {
    document.querySelector('#jobHud').classList.toggle('hidden', !payload);
    if (payload) {
      document.querySelector('#hudRoute').textContent = `ELETRICISTA · ROTA ${payload.completed}/${payload.batch}`;
      document.querySelector('#hudTitle').textContent = payload.title;
      document.querySelector('#hudStep').textContent = `${payload.stage}/${payload.total} · ${payload.step}`;
      document.querySelector('#hudInstruction').textContent = payload.instruction;
    }
  }
  if (action === 'open') {
    app.classList.remove('hidden');
    tutorial(payload?.tutorial);
    previewLevel = Number(payload?.progress?.level || 1);
    update(payload);
    setTab('overview');
  } else if (action === 'update') update(payload);
  else if (action === 'close') app.classList.add('hidden');
});
