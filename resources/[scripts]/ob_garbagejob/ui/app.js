const app = document.getElementById('app');
const tabs = [...document.querySelectorAll('.tab')];
const navs = [...document.querySelectorAll('.nav')];
let data = null;
let routeData = null;
let previewLevel = 1;
let leaderboardMode = 'xp';

const post = (action, payload = {}) => fetch(`https://${GetParentResourceName()}/${action}`, { method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'}, body:JSON.stringify(payload) }).catch(() => {});
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

function setTutorial(tutorial) {
  const value = String(tutorial?.youtubeUrl || '').trim();
  const match = value.match(/(?:youtu\.be\/|(?:youtube(?:-nocookie)?\.com)\/(?:watch\?v=|embed\/|shorts\/))([^?&#/]+)/i);
  const embed = match ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(match[1])}?rel=0` : '';
  document.getElementById('tutorialTitle').textContent = tutorial?.title || 'Tutorial';
  document.getElementById('tutorialEmpty').style.display = embed ? 'none' : 'block';
  const frame = document.getElementById('tutorialVideo');
  frame.style.display = embed ? 'block' : 'none';
  frame.src = embed;
}

function setTab(tab) {
  tabs.forEach((el) => el.classList.toggle('active', el.id === tab));
  navs.forEach((el) => el.classList.toggle('active', el.dataset.tab === tab));
  document.getElementById('title').textContent = ({ overview:'Visão geral', progress:'Progresso', group:'Grupo', ranking:'Ranking' })[tab] || 'Lixeiro';
}

function person(member) {
  const name = String(member.name || `ID ${member.id}`);
  return `<article class="person"><span class="avatar">${name.slice(0,1).toUpperCase()}</span><span class="name">${name}${member.leader ? '<small class="leader">Líder</small>' : ''}</span></article>`;
}

function renderLevelPreview(progress) {
  const step = Number(progress.paymentBonusStep || 2.5);
  const xpStep = Number(progress.xpRequired || 800);
  previewLevel = Math.max(1, Math.min(10, Number(previewLevel || 1)));
  const bonus = (previewLevel - 1) * step;
  document.getElementById('previewTitle').textContent = `Nível: ${previewLevel}`;
  document.getElementById('previewXp').textContent = `${(previewLevel - 1) * xpStep} XP`;
  document.getElementById('previewMoney').textContent = `+${Number(bonus.toFixed(1))}%`;
  document.getElementById('previewBenefit').textContent = previewLevel === 1
    ? 'Pagamento base da coleta liberado.'
    : `O pagamento individual das rotas recebe +${Number(bonus.toFixed(1))}%.`;
  document.getElementById('previewPrev').disabled = previewLevel <= 1;
  document.getElementById('previewNext').disabled = previewLevel >= 10;
}

function renderLeaderboard(board) {
  const mode = leaderboardMode === 'routes' ? 'routes' : 'xp';
  const rankData = (board || {})[mode] || {};
  const list = Array.isArray(rankData.list) ? rankData.list : [];
  const showingRoutes = mode === 'routes';
  document.getElementById('rankRoutes').classList.toggle('active-mini', showingRoutes);
  document.getElementById('rankXp').classList.toggle('active-mini', !showingRoutes);
  document.getElementById('rankingValueHead').textContent = showingRoutes ? 'Rotas' : 'XP';
  document.getElementById('rankSideTitle').textContent = showingRoutes ? 'Mais rotas' : 'Mais experiência';
  document.getElementById('myRank').textContent = rankData.myRank ? `#${rankData.myRank}` : '#-';
  document.getElementById('myRankValue').textContent = `${rankData.myValue || 0} ${showingRoutes ? 'rotas' : 'XP'}`;
  document.getElementById('leaderboard').innerHTML = list.length ? list.map((entry) => `<div class="ranking-row"><span>#${entry.rank || '-'}</span><span>${entry.name || 'Desconhecido'}</span><b>${showingRoutes ? (entry.routes || 0) : (entry.xp || 0)}${showingRoutes ? '' : ' XP'}</b></div>`).join('') : '<div class="empty">Ainda não há dados no ranking.</div>';
}

function update(payload) {
  if (!payload) return;
  data = payload;
  renderRouteHud(payload.route);
  const p = payload.progress || {};
  const g = payload.group || { members:[], maxMembers:4 };
  const r = payload.route;
  const pct = Math.max(0, Math.min(100, (Number(p.xpInLevel || 0) / Math.max(1, Number(p.xpRequired || 1))) * 100));
  document.getElementById('level').textContent = p.level || 1;
  document.getElementById('xpText').textContent = `${p.xpInLevel || 0} / ${p.xpRequired || 0} XP`;
  document.getElementById('xpBar').style.width = `${pct}%`;
  document.getElementById('routesCompleted').textContent = p.routesCompleted || 0;
  document.getElementById('earned').textContent = money(p.totalEarned);
  document.getElementById('bonus').textContent = `+${p.paymentBonus || 0}%`;
  document.getElementById('progressLevel').textContent = `Nível: ${p.level || 1}`;
  document.getElementById('progressBar').style.width = `${pct}%`;
  document.getElementById('progressDetails').textContent = `${Math.floor(pct)}%`;
  renderLevelPreview(p);
  renderLeaderboard(payload.leaderboard);
  document.getElementById('groupCount').textContent = `${(g.members || []).length}/${g.maxMembers || 4}`;
  document.getElementById('teamInfo').textContent = `Equipe: ${(g.members || []).length}/${g.maxMembers || 4}`;
  document.getElementById('members').innerHTML = (g.members || []).map(person).join('') || '<div class="empty">Nenhum integrante.</div>';
  document.getElementById('groupDescription').textContent = g.isLeader ? 'Convide trabalhadores que estejam próximos.' : 'Você participa da equipe deste líder.';
  document.getElementById('leaveGroup').classList.toggle('hidden', !g.members?.length);

  const nearby = (payload.nearby || []).filter((entry) => !(g.members || []).some((member) => Number(member.id) === Number(entry.id)));
  document.getElementById('nearby').innerHTML = nearby.length ? nearby.map((entry) => `<article class="person"><span class="avatar">${String(entry.name).slice(0,1).toUpperCase()}</span><span class="name">${entry.name}</span>${g.isLeader && (g.members || []).length < (g.maxMembers || 4) ? `<button class="invite" data-id="${entry.id}">Convidar</button>` : ''}</article>`).join('') : '<div class="empty">Ninguém próximo para convidar.</div>';
  document.querySelectorAll('.invite').forEach((button) => button.addEventListener('click', () => post('invite', { id:Number(button.dataset.id) })));

  const routeStatus = document.getElementById('routeStatus');
  const routeInfo = document.getElementById('routeInfo');
  const start = document.getElementById('startRoute');
  const cancel = document.getElementById('cancelRoute');
  if (r && (r.active || r.finished)) {
    routeStatus.textContent = r.finished ? 'Rota concluída' : 'Em coleta';
    routeInfo.textContent = r.finished ? 'Vá ao ponto de descarga com o caminhão.' : `${r.completedStops || 0}/${r.totalStops || 0} paradas | ${r.remainingBagsTotal || 0} sacos restantes`;
    start.classList.add('hidden');
    cancel.classList.toggle('hidden', !g.isLeader);
  } else { routeStatus.textContent = 'Fora de turno'; routeInfo.textContent = 'Escolha uma rota na central'; start.classList.toggle('hidden', !g.isLeader); cancel.classList.add('hidden'); }
}

function renderRouteHud(route) {
  routeData = route || null;
  const hud = document.getElementById('routeHud');
  const activeRoute = route && (route.active || route.finished);
  const menuOpen = !app.classList.contains('hidden');
  hud.classList.toggle('hidden', !activeRoute || menuOpen);
  if (!activeRoute) return;

  document.getElementById('hudStatus').textContent = route.finished
    ? 'Vá ao ponto de descarga'
    : `Parada ${Math.min((route.completedStops || 0) + 1, route.totalStops || 0)}/${route.totalStops || 0}`;
  document.getElementById('hudStopBags').textContent = route.finished ? '0' : (route.bags || 0);
  document.getElementById('hudTotalBags').textContent = route.remainingBagsTotal || 0;
}

navs.forEach((button) => button.addEventListener('click', () => setTab(button.dataset.tab)));
navs.forEach((button) => button.addEventListener('click', () => {
  if (button.dataset.tab === 'tutorial') document.getElementById('title').textContent = 'Tutorial';
}));
document.getElementById('close').addEventListener('click', () => post('close'));
document.getElementById('startRoute').addEventListener('click', () => post('startRoute'));
document.getElementById('cancelRoute').addEventListener('click', () => post('cancelRoute'));
document.getElementById('leaveGroup').addEventListener('click', () => post('leaveGroup'));
document.getElementById('previewPrev').addEventListener('click', () => { previewLevel -= 1; renderLevelPreview(data?.progress || {}); });
document.getElementById('previewNext').addEventListener('click', () => { previewLevel += 1; renderLevelPreview(data?.progress || {}); });
document.getElementById('rankRoutes').addEventListener('click', () => { leaderboardMode = 'routes'; renderLeaderboard(data?.leaderboard); });
document.getElementById('rankXp').addEventListener('click', () => { leaderboardMode = 'xp'; renderLeaderboard(data?.leaderboard); });
window.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !app.classList.contains('hidden')) post('close'); });
window.addEventListener('message', (event) => { const { action, payload } = event.data || {}; if (action === 'open') { app.classList.remove('hidden'); previewLevel = Number(payload?.progress?.level || 1); setTutorial(payload?.tutorial); update(payload); setTab('overview'); } if (action === 'update') update(payload); if (action === 'close') { app.classList.add('hidden'); renderRouteHud(routeData); } if (action === 'routeProgress') renderRouteHud(payload); });
