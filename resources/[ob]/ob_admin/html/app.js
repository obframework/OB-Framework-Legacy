const root = document.getElementById('admin');
const playerList = document.getElementById('player-list');
const countLabel = document.getElementById('online-count');
const emptyState = document.getElementById('empty-state');
const details = document.getElementById('player-details');
const selectedName = document.getElementById('selected-name');
const selectedCharacter = document.getElementById('selected-character');
const selectedSource = document.getElementById('selected-source');
const selectedUserId = document.getElementById('selected-user-id');
const selectedPing = document.getElementById('selected-ping');
const selectedStatus = document.getElementById('selected-status');
const slots = document.getElementById('slots');
const roleControl = document.getElementById('role-control');
const roleSelect = document.getElementById('role');
const slotControl = document.querySelector('.slot-control');
const actionButtons = Array.from(document.querySelectorAll('[data-action]'));
const utilityButtons = Array.from(document.querySelectorAll('[data-utility]'));
const kickButton = document.getElementById('kick');
const blockButton = document.getElementById('block-character');
const deleteButton = document.getElementById('delete-character');
const carControl = document.getElementById('car-control');
const vehicleModel = document.getElementById('vehicle-model');
const confirmModal = document.getElementById('confirm-modal');
const confirmTitle = document.getElementById('confirm-title');
const confirmMessage = document.getElementById('confirm-message');
const confirmCancel = document.getElementById('confirm-cancel');
const confirmAccept = document.getElementById('confirm-accept');

let players = [];
let selectedId = null;
let maxCharacterSlots = 1;
let permissions = {};
let roles = [];
let pendingConfirmation = null;
let activeTab = 'actions';
const searchInput = document.getElementById('player-search');
const tabs = Array.from(document.querySelectorAll('[data-tab]'));

function selectTab(name) {
  activeTab = name;
  tabs.forEach(button => {
    const active = button.dataset.tab === name;
    button.setAttribute('aria-selected', String(active));
    button.tabIndex = active ? 0 : -1;
  });
  document.querySelectorAll('[data-pane]').forEach(pane => show(pane, pane.dataset.pane === name));
  const pane = document.querySelector('[data-pane="' + name + '"]');
  const available = pane && Array.from(pane.querySelectorAll('button')).some(button => {
    for (let node = button; node && node !== pane; node = node.parentElement) {
      if (node.classList.contains('hidden')) return false;
    }
    return true;
  });
  show(document.getElementById('no-actions'), !available);
  document.querySelector('.tab-content').scrollTop = 0;
}
tabs.forEach((button, index) => {
  button.onclick = () => selectTab(button.dataset.tab);
  button.onkeydown = event => {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
    event.preventDefault();
    const next = tabs[(index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length];
    next.focus(); selectTab(next.dataset.tab);
  };
});

const iconPaths = {
  goto: 'M5 12h14m-6-6 6 6-6 6', bring: 'M19 12H5m6-6-6 6 6 6',
  heal: 'M12 4v16M4 12h16', revive_full: 'M3 12h4l3-7 4 14 3-7h4',
  fix_vehicle: 'M14 5a5 5 0 0 0-6 6L3 16a3 3 0 0 0 5 4l5-6a5 5 0 0 0 6-6l-4 3-3-3 3-4',
  noclip: 'M12 3v18M3 12h18M8 7l4-4 4 4M8 17l4 4 4-4',
  wall: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6',
  wallmap: 'm3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Zm6-3v15m6-12v15',
  dv: 'M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 11v6m4-6v6',
  dvarea: 'M3 6h18M6 10h12M9 14h6M11 18h2',
  kick: 'M10 4H4v16h6m4-13 5 5-5 5m-6-5h11',
  'block-character': 'M4 4l16 16M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18',
  'delete-character': 'M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 11v6m4-6v6',
};
[...actionButtons, ...utilityButtons, kickButton, blockButton, deleteButton].forEach(button => {
  const path = iconPaths[button.dataset.action || button.dataset.utility || button.id];
  if (!path) return;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('class', 'action-icon'); svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = '<path d="' + path + '" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>';
  const label = document.createElement('span'); label.textContent = button.textContent;
  button.replaceChildren(svg, label);
});

function post(action, data = {}) {
  return fetch('https://' + GetParentResourceName() + '/' + action, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).catch(() => undefined);
}

function selectedPlayer() {
  return players.find((player) => Number(player.source) === Number(selectedId));
}

function can(permission) {
  return permissions[permission] === true;
}

function show(element, visible) {
  element.classList.toggle('hidden', !visible);
}

function closeConfirmation(accepted = false) {
  confirmModal.classList.add('hidden');
  const resolve = pendingConfirmation;
  pendingConfirmation = null;
  if (resolve) resolve(accepted);
}

function requestConfirmation(title, message) {
  if (pendingConfirmation) closeConfirmation(false);
  confirmTitle.textContent = title;
  confirmMessage.textContent = message;
  confirmModal.classList.remove('hidden');
  confirmAccept.focus();
  return new Promise((resolve) => { pendingConfirmation = resolve; });
}

const actionPermissions = {
  goto: 'player.goto',
  bring: 'player.bring',
  heal: 'player.heal',
  revive: 'player.revive',
  revive_full: 'player.revive_full',
  reset_appearance: 'player.appearance',
  fix_vehicle: 'vehicle.fix',
};

const utilityPermissions = {
  dv: 'vehicle.delete',
  dvarea: 'vehicle.delete',
  noclip: 'tools.noclip',
  wall: 'tools.wall',
  wallmap: 'tools.wallmap',
};

function renderDetails() {
  const player = selectedPlayer();
  const hasPlayer = Boolean(player);
  emptyState.classList.toggle('hidden', hasPlayer);
  details.classList.toggle('hidden', !hasPlayer);
  if (!player) return;

  selectedName.textContent = player.name || 'Sem nome';
  document.getElementById('selected-avatar').textContent = (player.name || 'OB').trim().slice(0, 2).toUpperCase();
  selectedCharacter.textContent = player.characterName || 'Selecionando personagem';
  selectedSource.textContent = String(player.source);
  selectedUserId.textContent = player.userId ? String(player.userId) : '--';
  selectedPing.textContent = String(player.ping || 0) + ' ms';
  selectedStatus.textContent = player.spawned ? 'Na cidade' : 'Selecionando';

  slots.replaceChildren();
  for (let amount = 1; amount <= maxCharacterSlots; amount += 1) {
    const option = document.createElement('option');
    option.value = String(amount);
    option.textContent = String(amount) + (amount === 1 ? ' personagem' : ' personagens');
    option.selected = Number(player.slots) === amount;
    slots.append(option);
  }

  actionButtons.forEach((button) => {
    const allowed = can(actionPermissions[button.dataset.action]);
    show(button, allowed);
    const appearanceAction = button.dataset.action === 'reset_appearance';
    button.disabled = appearanceAction && player.canResetAppearance !== true;
    button.title = button.disabled ? 'Nao e permitido editar outro staff, independentemente do cargo.' : '';
    button.onclick = async () => {
      if (button.disabled) return;
      if (appearanceAction && !await requestConfirmation('Refazer aparência', 'Abrir somente a aparencia? Nome, idade e demais dados permanecem iguais.')) return;
      post('action', { action: button.dataset.action, target: player.source });
    };
  });

  utilityButtons.forEach((button) => {
    const allowed = can(utilityPermissions[button.dataset.utility]);
    show(button, allowed);
    button.onclick = () => post('utility', { action: button.dataset.utility });
  });
  show(carControl, can('vehicle.spawn'));
  document.getElementById('spawn-vehicle').onclick = () => {
    post('utility', { action: 'car', value: vehicleModel.value.trim() });
  };

  show(slotControl, can('character.slots'));
  document.getElementById('save-slots').onclick = () => {
    post('action', { action: 'slots', target: player.source, value: Number(slots.value) });
  };

  show(kickButton, can('player.kick'));
  kickButton.onclick = async () => {
    if (await requestConfirmation('Expulsar jogador', 'Deseja realmente expulsar este jogador?')) {
      post('action', { action: 'kick', target: player.source });
    }
  };

  show(blockButton, can('character.block'));
  blockButton.onclick = async () => {
    if (await requestConfirmation('Bloquear personagem', 'Ele nao aparecera mais na selecao e a vaga sera liberada.')) {
      post('action', { action: 'block_character', target: player.source });
    }
  };

  show(deleteButton, can('character.delete'));
  deleteButton.onclick = async () => {
    if (await requestConfirmation('Excluir personagem', 'Esta acao remove o personagem da conta e nao pode ser desfeita.')) {
      post('action', { action: 'delete_character', target: player.source });
    }
  };

  const mayManageRole = can('roles.manage') && player.userId && player.role !== 'owner';
  show(roleControl, mayManageRole);
  roleSelect.replaceChildren();
  roles.filter((role) => role.key !== 'owner').forEach((role) => {
    const option = document.createElement('option');
    option.value = role.key;
    option.textContent = role.label;
    option.selected = player.role === role.key || (!player.role && role.key === 'admin');
    roleSelect.append(option);
  });
  document.getElementById('save-role').onclick = () => {
    post('setRole', { target: player.source, role: roleSelect.value });
  };
  selectTab(activeTab);
}

function renderPlayers() {
  playerList.replaceChildren();
  countLabel.textContent = players.length + (players.length === 1 ? ' jogador online' : ' jogadores online');

  if (!players.some((player) => Number(player.source) === Number(selectedId))) {
    selectedId = players[0] ? players[0].source : null;
  }

  const query = searchInput.value.trim().toLocaleLowerCase('pt-BR');
  const visiblePlayers = players.filter(player =>
    [player.name, player.characterName, player.userId, player.source].some(value => String(value ?? '').toLocaleLowerCase('pt-BR').includes(query)));
  if (!visiblePlayers.length) {
    const message = document.createElement('p');
    message.className = 'list-empty'; message.textContent = query ? 'Nenhum jogador encontrado.' : 'Nenhum jogador online.';
    playerList.append(message);
  }
  visiblePlayers.forEach((player) => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'player-row' + (Number(player.source) === Number(selectedId) ? ' active' : '');

    const id = document.createElement('span');
    id.className = 'player-id';
    id.textContent = player.userId ? String(player.userId) : '--';
    id.title = 'ID fixo do personagem';

    const copy = document.createElement('span');
    copy.className = 'player-copy';
    const name = document.createElement('strong');
    name.textContent = player.name || 'Sem nome';
    const character = document.createElement('small');
    const characterName = player.characterName || 'Selecionando personagem';
    character.textContent = 'ID da sessao ' + String(player.source) + ' · ' + characterName;
    copy.append(name, character);

    const ping = document.createElement('span');
    ping.className = 'player-ping';
    ping.textContent = String(player.ping || 0) + ' ms';

    row.append(id, copy, ping);
    row.addEventListener('click', () => {
      selectedId = player.source;
      renderPlayers();
    });
    playerList.append(row);
  });

  renderDetails();
}

document.getElementById('close').addEventListener('click', () => post('close'));
document.getElementById('refresh').addEventListener('click', () => post('refresh'));
searchInput.addEventListener('input', renderPlayers);
confirmCancel.addEventListener('click', () => closeConfirmation(false));
confirmAccept.addEventListener('click', () => closeConfirmation(true));

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    if (!confirmModal.classList.contains('hidden')) closeConfirmation(false);
    else post('close');
  }
});

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') root.classList.remove('hidden');
  if (data.action === 'close') {
    closeConfirmation(false);
    root.classList.add('hidden');
    searchInput.value = '';
    selectedId = null;
    activeTab = 'actions';
  }
  if (data.action === 'players') {
    players = Array.isArray(data.players) ? data.players : [];
    maxCharacterSlots = Math.max(1, Number(data.maxCharacterSlots) || 1);
    permissions = data.permissions && typeof data.permissions === 'object' ? data.permissions : {};
    roles = Array.isArray(data.roles) ? data.roles : [];
    renderPlayers();
  }
});
