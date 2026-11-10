const app = document.getElementById('app');
const callsPanel = document.getElementById('callsPanel');
const pageTitle = document.getElementById('pageTitle');
const tutorialTitleEl = document.getElementById('tutorialTitle');
const tutorialEmptyEl = document.getElementById('tutorialEmpty');
const tutorialVideoEl = document.getElementById('tutorialVideo');

const levelEl = document.getElementById('level');
const ridesEl = document.getElementById('rides');
const earnedEl = document.getElementById('earned');
const totalRidesEl = document.getElementById('totalRides');
const rewardProgressEl = document.getElementById('rewardProgress');
const shiftStateEl = document.getElementById('shiftState');
const repHudEl = document.getElementById('repHud');
const repHudWrapEl = document.getElementById('repHudWrap');
const repHudLabelEl = document.getElementById('repHudLabel');
const repHudValueEl = document.getElementById('repHudValue');
const meterHudEl = document.getElementById('meterHud');
const meterFareEl = document.getElementById('meterFare');
const meterDistanceEl = document.getElementById('meterDistance');
const meterTimeEl = document.getElementById('meterTime');
const xpTextEl = document.getElementById('xpText');
const xpFillEl = document.getElementById('xpFill');
const xpPercentEl = document.getElementById('xpPercent');
const levelTextEl = document.getElementById('levelText');
const xpBonusEl = document.getElementById('xpBonus');
const moneyBonusEl = document.getElementById('moneyBonus');
const vehicleCardsEl = document.getElementById('vehicleCards');
const previewLevelTitleEl = document.getElementById('previewLevelTitle');
const previewPrevEl = document.getElementById('previewPrev');
const previewNextEl = document.getElementById('previewNext');
const unlocksListEl = document.getElementById('unlocksList');

const closeBtn = document.getElementById('closeBtn');
const startBtn = document.getElementById('startBtn');
const stopBtn = document.getElementById('stopBtn');

const closeCallsBtn = document.getElementById('closeCallsBtn');
const cityTabsEl = document.getElementById('cityTabs');
const callsListEl = document.getElementById('callsList');
const lbModeRidesEl = document.getElementById('lbModeRides');
const lbModeXpEl = document.getElementById('lbModeXp');
const lbHeaderValueEl = document.getElementById('lbHeaderValue');
const leaderboardBodyEl = document.getElementById('leaderboardBody');
const lbSideTitleEl = document.getElementById('lbSideTitle');
const lbMyRankEl = document.getElementById('lbMyRank');
const lbMyValueEl = document.getElementById('lbMyValue');
const lbPrevPageEl = document.getElementById('lbPrevPage');
const lbNextPageEl = document.getElementById('lbNextPage');
const lbPageInfoEl = document.getElementById('lbPageInfo');

const tabs = document.querySelectorAll('.tab');
const navButtons = document.querySelectorAll('.nav-btn');

let panelCache = null;
let selectedVehicleModel = null;
let selectedCityId = null;
let levelPreview = [];
let previewIndex = 0;
let leaderboardMode = 'xp';
let pendingStartAfterSelect = false;
const LB_PAGE_SIZE = 10;
const leaderboardPages = { xp: 1, rides: 1 };

function setReputation(value) {
  const rep = Math.max(0, Math.min(100, Number(value || 0)));
  const rounded = Math.floor(rep * 10) / 10;
  repHudValueEl.textContent = `${rounded}%`;
  repHudLabelEl.textContent = 'Reputação';
  repHudWrapEl.classList.toggle('danger', rep < 10);
}

function setReputationVisible(show) {
  repHudEl.classList.toggle('hidden', !show);
}

function formatDuration(ms) {
  const totalSeconds = Math.max(0, Math.floor((Number(ms || 0)) / 1000));
  const mm = Math.floor(totalSeconds / 60);
  const ss = totalSeconds % 60;
  return `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
}

function setMeterVisible(show) {
  meterHudEl.classList.toggle('hidden', !show);
}

function updateMeter(payload) {
  const fare = Math.max(0, Math.floor(Number(payload?.fare || 0)));
  const distance = Math.max(0, Number(payload?.distance || 0));
  const elapsed = Math.max(0, Number(payload?.elapsed || 0));
  meterFareEl.textContent = money(fare);
  meterDistanceEl.textContent = `${(distance / 1000).toFixed(2)} km`;
  meterTimeEl.textContent = formatDuration(elapsed);
}

function post(action, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).catch(() => {});
}

function money(value) {
  return window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;
}

function youtubeEmbedUrl(value) {
  try {
    const url = new URL(String(value || '').trim());
    const host = url.hostname.replace(/^www\./, '').toLowerCase();
    let id = '';
    if (host === 'youtu.be') id = url.pathname.split('/').filter(Boolean)[0] || '';
    if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) id = url.searchParams.get('v') || (url.pathname.match(/\/(?:embed|shorts)\/([^/?#]+)/) || [])[1] || '';
    return id ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(id)}?rel=0` : '';
  } catch (_) { return ''; }
}

function setTutorial(tutorial) {
  const embed = youtubeEmbedUrl(tutorial?.youtubeUrl);
  tutorialTitleEl.textContent = tutorial?.title || 'Tutorial';
  tutorialEmptyEl.style.display = embed ? 'none' : 'block';
  tutorialVideoEl.style.display = embed ? 'block' : 'none';
  tutorialVideoEl.src = embed;
}

function setTab(tabName) {
  tabs.forEach((tab) => {
    tab.classList.toggle('active', tab.id === `tab-${tabName}`);
  });

  navButtons.forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });

  const titleMap = {
    overview: 'Visão geral',
    progress: 'Progresso',
    vehicles: 'Veículos',
    leaderboard: 'Ranking',
    tutorial: 'Tutorial',
  };

  pageTitle.textContent = titleMap[tabName] || 'Visão geral';
}

function renderVehicles(meta) {
  vehicleCardsEl.innerHTML = '';
  const vehicles = meta?.vehicles || [];

  vehicles.forEach((entry) => {
    const isUnlocked = !!entry.unlocked;
    const isSelected = selectedVehicleModel && selectedVehicleModel.toLowerCase() === String(entry.model).toLowerCase();

    const el = document.createElement('article');
    el.className = 'card vehicle-card';
    el.innerHTML = `
      <div class="vehicle-image-wrap">
        <img class="vehicle-image" src="${entry.image || 'vehicles/default.svg'}" alt="${entry.label || entry.model}">
      </div>
      <span class="sub">${entry.label || entry.model}</span>
      <div class="vehicle-meta">
        <p>Modelo: ${(entry.model || '').toUpperCase()}</p>
        <p>${entry.seats || 4} lugares</p>
        <p>${isUnlocked ? `Aluguel ${money(entry.rent || 0)}` : `Bloqueado | Nível ${entry.requiredLevel || 1}`}</p>
      </div>
      <div class="actions-inline vehicle-meta">
        <button class="btn select-vehicle" ${!isUnlocked ? 'disabled' : ''} data-model="${entry.model}">
          ${isSelected ? 'Selecionado' : 'Selecionar'}
        </button>
      </div>
    `;

    vehicleCardsEl.appendChild(el);

    const img = el.querySelector('.vehicle-image');
    if (img) {
      img.addEventListener('error', () => {
        if (img.dataset.fallback === '1') {
          return;
        }
        img.dataset.fallback = '1';
        img.src = 'vehicles/default.svg';
      });
    }
  });

  vehicleCardsEl.querySelectorAll('.select-vehicle').forEach((btn) => {
    btn.addEventListener('click', () => {
      const model = btn.dataset.model;
      selectedVehicleModel = model;
      post('selectVehicle', { model });
      if (panelCache) {
        renderVehicles(panelCache.meta);
      }

      if (pendingStartAfterSelect) {
        pendingStartAfterSelect = false;
        post('startShift', { model: selectedVehicleModel });
      }
    });
  });
}

function renderLevelPreviewCard() {
  if (!levelPreview.length) {
    previewLevelTitleEl.textContent = 'Nível: 1';
    xpBonusEl.textContent = '0%';
    moneyBonusEl.textContent = '0%';
    unlocksListEl.innerHTML = '<div class="unlock-empty">Sem desbloqueios configurados.</div>';
    previewPrevEl.disabled = true;
    previewNextEl.disabled = true;
    return;
  }

  if (previewIndex < 0) previewIndex = 0;
  if (previewIndex > levelPreview.length - 1) previewIndex = levelPreview.length - 1;

  const item = levelPreview[previewIndex];
  previewLevelTitleEl.textContent = `Nível: ${item.level}`;
  xpBonusEl.textContent = `${Number(item.xpBonus || 0)}%`;
  moneyBonusEl.textContent = `${Number(item.moneyBonus || 0)}%`;

  const unlocks = Array.isArray(item.unlocks) ? item.unlocks : [];
  if (!unlocks.length) {
    unlocksListEl.innerHTML = '<div class="unlock-empty">Nenhum desbloqueio neste nivel.</div>';
  } else {
    unlocksListEl.innerHTML = unlocks.map((u) => `<div class="unlock-item">- ${u}</div>`).join('');
  }

  previewPrevEl.disabled = previewIndex <= 0;
  previewNextEl.disabled = previewIndex >= levelPreview.length - 1;
}

function formatLeaderboardValue(mode, entry) {
  if (mode === 'rides') {
    return Number(entry?.rides || 0);
  }
  return Number(entry?.xp || 0);
}

function renderLeaderboard(meta) {
  const board = meta?.leaderboard || {};
  const mode = leaderboardMode === 'rides' ? 'rides' : 'xp';
  const modeData = board[mode] || { list: [], myRank: 0, myValue: 0 };
  const rows = Array.isArray(modeData.list) ? modeData.list : [];
  const maxPages = Math.max(1, Math.ceil(rows.length / LB_PAGE_SIZE));
  let currentPage = Number(leaderboardPages[mode] || 1);
  if (currentPage < 1) currentPage = 1;
  if (currentPage > maxPages) currentPage = maxPages;
  leaderboardPages[mode] = currentPage;

  lbModeXpEl.classList.toggle('active-lb-btn', mode === 'xp');
  lbModeRidesEl.classList.toggle('active-lb-btn', mode === 'rides');

  if (mode === 'xp') {
    lbHeaderValueEl.textContent = 'Mais experiência';
    lbSideTitleEl.textContent = 'Mais experiência';
    lbMyValueEl.textContent = `${Number(modeData.myValue || 0)} XP`;
  } else {
    lbHeaderValueEl.textContent = 'Corridas concluídas';
    lbSideTitleEl.textContent = 'Corridas concluídas';
    lbMyValueEl.textContent = `${Number(modeData.myValue || 0)} corridas`;
  }

  lbMyRankEl.textContent = `#${Number(modeData.myRank || 0)}`;
  lbPageInfoEl.textContent = `Pagina ${currentPage}/${maxPages}`;
  lbPrevPageEl.disabled = currentPage <= 1;
  lbNextPageEl.disabled = currentPage >= maxPages;

  if (!rows.length) {
    leaderboardBodyEl.innerHTML = `
      <tr>
        <td colspan="3">Sem dados ainda.</td>
      </tr>
    `;
    return;
  }

  const start = (currentPage - 1) * LB_PAGE_SIZE;
  const pageRows = rows.slice(start, start + LB_PAGE_SIZE);

  leaderboardBodyEl.innerHTML = pageRows.map((entry) => `
    <tr>
      <td>${Number(entry.rank || 0)}</td>
      <td>${entry.name || 'Desconhecido'}</td>
      <td>${formatLeaderboardValue(mode, entry)}</td>
    </tr>
  `).join('');
}

function setPreviewLevelByCurrentLevel(level) {
  if (!Array.isArray(levelPreview) || !levelPreview.length) {
    previewIndex = 0;
    return;
  }

  const idx = levelPreview.findIndex((entry) => Number(entry.level) === Number(level));
  previewIndex = idx >= 0 ? idx : 0;
}

function getAvailableCityTabs(meta) {
  return (meta?.cityTabs || []).map((tab) => ({
    id: tab.id,
    label: tab.label,
    unlocked: !!tab.unlocked,
    minLevel: Number(tab.minLevel || 1),
  }));
}

function ensureSelectedCity(meta) {
  const tabsData = getAvailableCityTabs(meta);
  if (!tabsData.length) {
    selectedCityId = null;
    return tabsData;
  }

  const selected = tabsData.find((tab) => tab.id === selectedCityId);
  if (selected && selected.unlocked) return tabsData;

  const firstUnlocked = tabsData.find((tab) => tab.unlocked);
  selectedCityId = firstUnlocked ? firstUnlocked.id : tabsData[0].id;
  return tabsData;
}

function renderCityTabs(meta) {
  cityTabsEl.innerHTML = '';
  const tabsData = ensureSelectedCity(meta);

  tabsData.forEach((tab) => {
    const btn = document.createElement('button');
    btn.className = `city-tab${tab.unlocked ? '' : ' locked'}${selectedCityId === tab.id ? ' active' : ''}`;
    btn.textContent = tab.unlocked ? tab.label : `Nível ${tab.minLevel}`;
    btn.disabled = !tab.unlocked;
    btn.addEventListener('click', () => {
      selectedCityId = tab.id;
      renderTaxiCalls(panelCache);
    });
    cityTabsEl.appendChild(btn);
  });
}

function renderTaxiCalls(data) {
  if (!data) return;

  renderCityTabs(data.meta);

  const calls = (data.calls || []).filter((entry) => entry.cityId === selectedCityId);
  const shift = data.shift || {};

  callsListEl.innerHTML = '';
  if (!calls.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-calls';
    empty.textContent = 'Sem rotas disponiveis nesta cidade.';
    callsListEl.appendChild(empty);
    return;
  }

  calls.forEach((entry) => {
    const item = document.createElement('article');
    item.className = 'route-card';

    const routeBusy = !!shift.hasActiveRide;
    item.innerHTML = `
      <div class="route-top">
        <strong class="route-name">${entry.customerName}</strong>
        <div class="route-reward">
          <span class="money">${money(entry.fare)}</span>
          <span class="xp">${entry.xp} XP</span>
        </div>
      </div>
      <div class="route-meta">${entry.category}</div>
      <div class="route-meta">${entry.city}</div>
      <div class="route-actions">
        <button class="btn start-route" data-id="${entry.id}" ${routeBusy ? 'disabled' : ''}>
          ${routeBusy ? 'Rota ativa' : 'Iniciar corrida'}
        </button>
      </div>
    `;
    callsListEl.appendChild(item);
  });

  callsListEl.querySelectorAll('.start-route').forEach((btn) => {
    btn.addEventListener('click', () => {
      post('acceptCall', { id: btn.dataset.id });
    });
  });
}

function updatePanel(data) {
  if (!data || !data.stats || !data.shift) return;

  panelCache = data;

  const stats = data.stats;
  const shift = data.shift;
  const meta = data.meta || {};

  if (!selectedVehicleModel) {
    selectedVehicleModel = shift.selectedVehicleModel || shift.vehicleModel || null;
  }

  levelEl.textContent = String(stats.level || 1);
  ridesEl.textContent = String(stats.rides || 0);
  totalRidesEl.textContent = String(stats.rides || 0);
  earnedEl.textContent = money(stats.totalEarned || 0);

  shiftStateEl.textContent = shift.working
    ? `Em turno (${shift.vehiclePlate || 'Sem placa'})`
    : 'Fora de turno';

  const xpInLevel = Number(stats.xpInLevel || 0);
  const xpRequired = Number(stats.xpRequired || 1);
  const xpPercent = Math.max(0, Math.min(100, (xpInLevel / xpRequired) * 100));

  xpTextEl.textContent = `${xpInLevel} / ${xpRequired}`;
  xpFillEl.style.width = `${xpPercent}%`;
  document.querySelectorAll('.overview-bar i').forEach((bar) => { bar.style.width = `${xpPercent}%`; });
  xpPercentEl.textContent = `${Math.floor(xpPercent)}%`;
  levelTextEl.textContent = `Nível: ${stats.level || 1}`;
  rewardProgressEl.textContent = `${stats.rides || 0} corridas para recompensa`;
  startBtn.disabled = !!shift.working;
  stopBtn.disabled = !shift.working;

  levelPreview = Array.isArray(meta.levelPreview) ? meta.levelPreview : [];
  setPreviewLevelByCurrentLevel(stats.level || 1);
  renderLevelPreviewCard();
  renderLeaderboard(meta);

  renderVehicles(meta);
}

window.addEventListener('message', (event) => {
  const { action, payload } = event.data || {};

  if (action === 'open') {
    app.classList.remove('hidden');
    pendingStartAfterSelect = false;
    setTutorial(payload?.tutorial);
    updatePanel(payload);
    setTab('overview');
  }

  if (action === 'update') {
    updatePanel(payload);
  }

  if (action === 'reputation') {
    setReputation(payload?.value ?? 100);
  }

  if (action === 'reputationVisibility') {
    setReputationVisible(!!payload?.show);
  }

  if (action === 'meterVisibility') {
    setMeterVisible(!!payload?.show);
  }

  if (action === 'meterUpdate') {
    updateMeter(payload || {});
  }

  if (action === 'close') {
    app.classList.add('hidden');
    pendingStartAfterSelect = false;
  }

  if (action === 'openCalls') {
    panelCache = payload;
    callsPanel.classList.remove('hidden');
    renderTaxiCalls(payload);
  }

  if (action === 'updateCalls') {
    panelCache = payload;
    if (!callsPanel.classList.contains('hidden')) {
      renderTaxiCalls(payload);
    }
  }

  if (action === 'closeCalls') {
    callsPanel.classList.add('hidden');
  }
});

navButtons.forEach((btn) => {
  btn.addEventListener('click', () => setTab(btn.dataset.tab));
});

closeBtn.addEventListener('click', () => post('close'));
closeCallsBtn.addEventListener('click', () => post('closeCalls'));
startBtn.addEventListener('click', () => {
  if (!selectedVehicleModel) {
    pendingStartAfterSelect = true;
    setTab('vehicles');
    return;
  }
  pendingStartAfterSelect = false;
  post('startShift', { model: selectedVehicleModel });
});
stopBtn.addEventListener('click', () => post('stopShift'));
previewPrevEl.addEventListener('click', () => {
  previewIndex -= 1;
  renderLevelPreviewCard();
});
previewNextEl.addEventListener('click', () => {
  previewIndex += 1;
  renderLevelPreviewCard();
});
lbModeXpEl.addEventListener('click', () => {
  leaderboardMode = 'xp';
  renderLeaderboard(panelCache?.meta || {});
});
lbModeRidesEl.addEventListener('click', () => {
  leaderboardMode = 'rides';
  renderLeaderboard(panelCache?.meta || {});
});
lbPrevPageEl.addEventListener('click', () => {
  leaderboardPages[leaderboardMode] = Number(leaderboardPages[leaderboardMode] || 1) - 1;
  renderLeaderboard(panelCache?.meta || {});
});
lbNextPageEl.addEventListener('click', () => {
  leaderboardPages[leaderboardMode] = Number(leaderboardPages[leaderboardMode] || 1) + 1;
  renderLeaderboard(panelCache?.meta || {});
});

document.addEventListener('keydown', (ev) => {
  if (ev.key !== 'Escape') return;

  if (!callsPanel.classList.contains('hidden')) {
    post('closeCalls');
    return;
  }

  if (!app.classList.contains('hidden')) {
    post('close');
  }
});
