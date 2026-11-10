const app = document.querySelector('#app');
const list = document.querySelector('#list');
const vehicleView = document.querySelector('#vehicle-view');
const adminView = document.querySelector('#admin-view');
const vehicleActions = document.querySelector('#vehicle-actions');
const adminActions = document.querySelector('#admin-actions');
const captureHud = document.querySelector('#capture-hud');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_garage';

const post = (name, data = {}) => fetch(`https://${resource}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
}).then(response => response.json());
const pct = (value, max) => Math.max(0, Math.min(100, Math.round((Number(value) || 0) / max * 100)));
const money = value => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(Number(value) || 0);
const date = timestamp => timestamp ? new Date(Number(timestamp) * 1000).toLocaleDateString('pt-BR') : '';
const clone = value => JSON.parse(JSON.stringify(value ?? null));
const escapeHtml = value => {
  const node = document.createElement('span');
  node.textContent = String(value ?? '');
  return node.innerHTML;
};

let mode = 'garage';
let images = { baseUrl: '/orbis/cars/', extension: '.png', default: 'carro.png', preload: true };
let adminData = { garages: [], limits: {}, defaults: {} };
let draft = null;
let selectedGarageId = null;
let deleteArmed = false;
const requested = new Set();
const missing = new Set();

const modelName = model => String(model || '').toLowerCase().replace(/[^a-z0-9_]/g, '');
const join = (base, file) => `${String(base || '').replace(/\/+$/, '')}/${file}`;
const fallback = () => join(images.baseUrl, images.default || 'carro.png');
const imageFor = model => {
  const name = modelName(model);
  return !name || missing.has(name) ? fallback() : join(images.baseUrl, `${name}${images.extension || '.png'}`);
};

function preload(url) {
  if (!images.preload || requested.has(url)) return;
  requested.add(url);
  const image = new Image();
  image.src = url;
}

function preloadVehicles(vehicles) {
  preload(fallback());
  (vehicles || []).forEach(vehicle => preload(imageFor(vehicle.model)));
}

function render(vehicles) {
  if (!vehicles.length) {
    list.innerHTML = '<div class="empty">Nenhum veículo nesta garagem.</div>';
    return;
  }
  preloadVehicles(vehicles);
  list.innerHTML = vehicles.map(vehicle => {
    if (vehicle.catalog === true) {
      const isFree = vehicle.vehicleType === 'free';
      const inUse = isFree && vehicle.inUse === true;
      const catalogTax = vehicle.taxExempt
        ? 'Sem cobrança periódica'
        : `IPVA: ${vehicle.taxRate}% (${money(vehicle.taxAmount)}) a cada ${vehicle.taxIntervalDays} dias`;
      return `<article class="vehicle catalog">
        <div class="preview"><img src="${imageFor(vehicle.model)}" data-model="${modelName(vehicle.model)}" alt="${escapeHtml(vehicle.model)}"></div>
        <div><div class="name">${escapeHtml(vehicle.label)}</div>
          <div class="sub">${escapeHtml(vehicle.model)} · ${isFree ? 'uso temporário gratuito' : `aquisição única: <b>${money(vehicle.price)}</b>`}</div>
          <div class="tax ${vehicle.taxExempt ? 'exempt' : ''}">${isFree ? 'Não entra na garagem pessoal' : catalogTax}</div>
        </div>
        <div class="vehicle-actions single"><button class="acquire" data-acquire="${modelName(vehicle.model)}" ${inUse ? 'disabled' : ''}>${inUse ? 'EM USO' : isFree ? 'RETIRAR' : 'ADQUIRIR'}</button></div>
      </article>`;
    }
    const stored = Number(vehicle.stored) === 1;
    const name = modelName(vehicle.model);
    const bars = [['Combustível', pct(vehicle.fuel, 100)], ['Lataria', pct(vehicle.body, 1000)], ['Motor', pct(vehicle.engine, 1000)]]
      .map(([label, value]) => `<div class="bar"><small>${label} ${value}%</small><div class="track"><i style="width:${value}%"></i></div></div>`).join('');
    const tax = vehicle.taxExempt
      ? '<div class="tax exempt">Sem IPVA</div>'
      : vehicle.taxDue
        ? `<div class="tax due">IPVA vencido: <b>${money(vehicle.taxAmount)}</b><br>
            ${vehicle.taxExpired ? 'Prazo encerrado. Veículo recolhido por falta de pagamento.' :
              `Retirada bloqueada · ${Number(vehicle.taxOverdueDays) || 0} dia(s) de atraso.<br>
               Pague antes de <b>${date(vehicle.taxRemovalUnix)}</b>: perda do veículo após ${Number(vehicle.deleteAfterOverdueDays) || 14} dias em atraso.`}</div>`
        : `<div class="tax">Próximo IPVA: <b>${date(vehicle.taxDueUnix)}</b> · ${money(vehicle.taxAmount)}</div>`;
    return `<article class="vehicle">
      <div class="preview"><img src="${imageFor(vehicle.model)}" data-model="${name}" alt="${escapeHtml(vehicle.model)}"></div>
      <div><div class="name">${escapeHtml(vehicle.label)}</div><div class="sub">${escapeHtml(vehicle.model)} · Placa: <b>${escapeHtml(vehicle.plate)}</b> · <span class="${stored ? '' : 'out'}">${stored ? 'GUARDADO' : 'FORA DA GARAGEM'}</span></div>${tax}<div class="bars">${bars}</div></div>
      <div class="vehicle-actions">
        <button class="take" ${stored && !vehicle.taxDue ? '' : 'disabled'} data-id="${vehicle.id}">${vehicle.taxDue ? 'IPVA VENCIDO' : stored ? 'RETIRAR' : 'EM USO'}</button>
        <button class="track-button" ${stored ? 'disabled' : ''} data-track="${vehicle.id}">RASTREAR</button>
        ${vehicle.taxDue && !vehicle.taxExpired ? `<button class="tax-button" data-tax="${vehicle.id}">PAGAR IPVA ${money(vehicle.taxAmount)}</button>` : ''}
      </div>
    </article>`;
  }).join('');

  document.querySelectorAll('.take[data-id]').forEach(button => { button.onclick = () => post('take', { id: Number(button.dataset.id) }); });
  document.querySelectorAll('.track-button[data-track]').forEach(button => { button.onclick = () => post('track', { id: Number(button.dataset.track) }); });
  document.querySelectorAll('.acquire[data-acquire]').forEach(button => { button.onclick = () => post('acquire', { model: button.dataset.acquire }); });
  document.querySelectorAll('.tax-button[data-tax]').forEach(button => { button.onclick = () => post('payTax', { id: Number(button.dataset.tax) }); });
  document.querySelectorAll('img[data-model]').forEach(image => {
    image.onerror = () => {
      const model = image.dataset.model;
      if (model) missing.add(model);
      image.onerror = null;
      image.src = fallback();
    };
  });
}

const numberValue = (selector, fallback = 0) => {
  const value = document.querySelector(selector).value;
  return value === '' ? fallback : Number(value);
};
const pointLabel = point => point
  ? `${Number(point.x).toFixed(3)}, ${Number(point.y).toFixed(3)}, ${Number(point.z).toFixed(3)}${point.w === undefined ? '' : ` · ${Number(point.w).toFixed(1)}°`}`
  : 'Não capturado';

function blankDraft() {
  const defaults = adminData.defaults || {};
  const openSize = defaults.OpenSize || { x: 4, y: 4, z: 3 };
  const storeSize = defaults.StoreSize || { x: 7, y: 7, z: 3 };
  const blip = defaults.Blip || { sprite: 357, color: 3, scale: 0.82 };
  return {
    id: '', label: '', coords: null, storeCoords: null, spawns: [], permission: '', requireDuty: false,
    vehicleType: 'personal', sharedGroup: '', economyAccount: '', taxRatePercent: null, taxExempt: false,
    size: clone(openSize), storeSize: clone(storeSize), storeDistance: Number(defaults.StoreDistance) || 16,
    spawnClearRadius: Number(defaults.SpawnClearRadius) || 1.75,
    blipEnabled: true, blip: { label: 'Garagem', sprite: Number(blip.sprite) || 357, color: Number(blip.color) || 3, scale: Number(blip.scale) || 0.82 },
    vehicles: [],
  };
}

function showAdminFeedback(message = '', type = 'error') {
  const feedback = document.querySelector('#admin-feedback');
  feedback.textContent = message;
  feedback.className = message ? `admin-feedback ${type}` : 'admin-feedback hidden';
}

function renderGarageList() {
  const container = document.querySelector('#garage-list');
  const garages = adminData.garages || [];
  container.innerHTML = garages.length ? garages.map(garage => `<button type="button" data-garage-id="${escapeHtml(garage.id)}" class="${selectedGarageId === garage.id ? 'selected' : ''}">
    <b>${escapeHtml(garage.label)}</b><span>${escapeHtml(garage.id)} · ${(garage.spawns || []).length} vaga(s)</span>
  </button>`).join('') : '<div class="empty compact">Nenhuma garagem cadastrada.</div>';
  container.querySelectorAll('[data-garage-id]').forEach(button => {
    button.onclick = () => selectGarage(button.dataset.garageId);
  });
}

function renderSpawns() {
  const container = document.querySelector('#spawn-list');
  const spawns = draft.spawns || [];
  container.innerHTML = spawns.length ? spawns.map((point, index) => `<article class="editor-row">
    <div><b>Vaga ${index + 1}</b><span>${pointLabel(point)}</span></div>
    <div><button type="button" data-teleport-spawn="${index}" ${selectedGarageId ? '' : 'disabled'}>Teleportar</button><button type="button" data-recapture-spawn="${index}">Recapturar</button><button type="button" class="danger ghost" data-remove-spawn="${index}">Remover</button></div>
  </article>`).join('') : '<div class="empty compact">Capture pelo menos uma vaga de saída.</div>';
  container.querySelectorAll('[data-recapture-spawn]').forEach(button => { button.onclick = () => capture('spawn', Number(button.dataset.recaptureSpawn)); });
  container.querySelectorAll('[data-teleport-spawn]').forEach(button => { button.onclick = () => teleportToGarage('spawn', Number(button.dataset.teleportSpawn) + 1); });
  container.querySelectorAll('[data-remove-spawn]').forEach(button => {
    button.onclick = () => { draft.spawns.splice(Number(button.dataset.removeSpawn), 1); renderSpawns(); };
  });
}

function renderCatalog() {
  const container = document.querySelector('#catalog-list');
  const vehicles = draft.vehicles || [];
  container.innerHTML = vehicles.length ? vehicles.map((vehicle, index) => `<article class="catalog-row" data-catalog-index="${index}">
    <label>Modelo<input data-vehicle-field="model" maxlength="64" value="${escapeHtml(vehicle.model || '')}" placeholder="ambulance"></label>
    <label>Nome<input data-vehicle-field="label" maxlength="96" value="${escapeHtml(vehicle.label || '')}" placeholder="Ambulância"></label>
    <label>Preço jogador<input data-vehicle-field="price" type="number" min="0" value="${Number(vehicle.price) || 0}"></label>
    <label>Custo departamento<input data-vehicle-field="departmentPrice" type="number" min="0" value="${Number(vehicle.departmentPrice) || 0}"></label>
    <label>IPVA (%)<input data-vehicle-field="taxRatePercent" type="number" min="0" max="100" step="0.1" value="${vehicle.taxRatePercent ?? ''}" placeholder="Padrão"></label>
    <label class="check-field mini"><input data-vehicle-field="taxExempt" type="checkbox" ${vehicle.taxExempt ? 'checked' : ''}> Sem IPVA</label>
    <button type="button" class="danger ghost remove-catalog">Remover</button>
  </article>`).join('') : '<div class="empty compact">Nenhum veículo no catálogo.</div>';
  container.querySelectorAll('.catalog-row').forEach(row => {
    const index = Number(row.dataset.catalogIndex);
    row.querySelectorAll('[data-vehicle-field]').forEach(input => {
      input.oninput = () => {
        const field = input.dataset.vehicleField;
        draft.vehicles[index][field] = input.type === 'checkbox' ? input.checked
          : input.type === 'number' ? (input.value === '' ? null : Number(input.value)) : input.value;
      };
    });
    row.querySelector('.remove-catalog').onclick = () => { draft.vehicles.splice(index, 1); renderCatalog(); };
  });
}

function renderEditor() {
  if (!draft) draft = blankDraft();
  const editing = Boolean(selectedGarageId);
  document.querySelectorAll('[data-teleport]').forEach(button => { button.disabled = !editing; });
  document.querySelector('#editor-id').value = draft.id || '';
  document.querySelector('#editor-id').disabled = editing;
  document.querySelector('#editor-label').value = draft.label || '';
  document.querySelector('#editor-permission').value = draft.access?.permission || draft.permission || '';
  document.querySelector('#editor-duty').checked = draft.access?.requireDuty === true || draft.requireDuty === true;
  document.querySelector('#editor-type').value = draft.vehicleType || 'personal';
  document.querySelector('#editor-shared-group').value = draft.sharedGroup || '';
  const knownGroups = [...new Set((adminData.garages || []).flatMap(garage => [garage.sharedGroup, garage.id]).filter(Boolean))].sort();
  document.querySelector('#garage-group-options').innerHTML = knownGroups.map(group => `<option value="${escapeHtml(group)}"></option>`).join('');
  document.querySelector('#editor-account').value = draft.economyAccount || '';
  document.querySelector('#editor-tax-rate').value = draft.taxRatePercent ?? '';
  document.querySelector('#editor-tax-exempt').checked = draft.taxExempt === true;
  document.querySelector('#open-point').textContent = pointLabel(draft.coords);
  document.querySelector('#store-point').textContent = pointLabel(draft.storeCoords);
  document.querySelector('#open-size-x').value = draft.size?.x ?? 4;
  document.querySelector('#open-size-y').value = draft.size?.y ?? 4;
  document.querySelector('#store-size-x').value = draft.storeSize?.x ?? 7;
  document.querySelector('#store-size-y').value = draft.storeSize?.y ?? 7;
  document.querySelector('#store-distance').value = draft.storeDistance ?? 16;
  document.querySelector('#spawn-radius').value = draft.spawnClearRadius ?? 1.75;
  document.querySelector('#blip-enabled').checked = draft.blipEnabled === true || Boolean(draft.blip);
  document.querySelector('#blip-label').value = draft.blip?.label || 'Garagem';
  document.querySelector('#blip-sprite').value = draft.blip?.sprite ?? 357;
  document.querySelector('#blip-color').value = draft.blip?.color ?? 3;
  document.querySelector('#blip-scale').value = draft.blip?.scale ?? 0.82;
  document.querySelector('#blip-fields').classList.toggle('hidden', !document.querySelector('#blip-enabled').checked);
  const protectedId = String(adminData.limits?.protectedGarage || 'central');
  document.querySelector('#delete-garage').classList.toggle('hidden', !editing || draft.id === protectedId);
  deleteArmed = false;
  document.querySelector('#delete-garage').textContent = 'Remover garagem';
  renderSpawns();
  renderCatalog();
  renderGarageList();
  showAdminFeedback('');
}

function selectGarage(id) {
  const garage = (adminData.garages || []).find(entry => entry.id === id);
  if (!garage) return;
  selectedGarageId = garage.id;
  draft = clone(garage);
  renderEditor();
}

function newGarage() {
  selectedGarageId = null;
  draft = blankDraft();
  renderEditor();
  document.querySelector('#editor-id').focus();
}

function readEditor() {
  draft.id = document.querySelector('#editor-id').value.trim().toLowerCase();
  draft.label = document.querySelector('#editor-label').value.trim();
  draft.permission = document.querySelector('#editor-permission').value.trim().toLowerCase();
  draft.requireDuty = document.querySelector('#editor-duty').checked;
  draft.vehicleType = document.querySelector('#editor-type').value;
  draft.sharedGroup = document.querySelector('#editor-shared-group').value.trim().toLowerCase();
  draft.economyAccount = document.querySelector('#editor-account').value.trim().toLowerCase();
  draft.taxRatePercent = document.querySelector('#editor-tax-rate').value === '' ? null : numberValue('#editor-tax-rate');
  draft.taxExempt = document.querySelector('#editor-tax-exempt').checked;
  draft.size = { x: numberValue('#open-size-x', 4), y: numberValue('#open-size-y', 4), z: Number(draft.size?.z) || 3 };
  draft.storeSize = { x: numberValue('#store-size-x', 7), y: numberValue('#store-size-y', 7), z: Number(draft.storeSize?.z) || 3 };
  draft.storeDistance = numberValue('#store-distance', 16);
  draft.spawnClearRadius = numberValue('#spawn-radius', 1.75);
  draft.blipEnabled = document.querySelector('#blip-enabled').checked;
  draft.blip = draft.blipEnabled ? {
    label: document.querySelector('#blip-label').value.trim() || 'Garagem',
    sprite: numberValue('#blip-sprite', 357), color: numberValue('#blip-color', 3), scale: numberValue('#blip-scale', 0.82),
  } : null;
  return draft;
}

async function refreshAdmin(selectId = selectedGarageId) {
  const response = await post('adminRefresh');
  if (!response.ok) return showAdminFeedback(response.error || 'Não foi possível atualizar as garagens.');
  adminData = response.data || adminData;
  const selected = (adminData.garages || []).find(entry => entry.id === selectId);
  if (selected) {
    selectedGarageId = selected.id;
    draft = clone(selected);
    renderEditor();
  } else {
    newGarage();
  }
}

async function capture(kind, index = 0) {
  readEditor();
  const response = await post('adminCapture', { kind, index });
  if (!response.ok) showAdminFeedback(response.error || 'Não foi possível iniciar a captura.');
}

async function teleportToGarage(kind, index = 0) {
  if (!selectedGarageId) return showAdminFeedback('Salve a garagem antes de teleportar.');
  const result = await post('adminTeleport', { id: selectedGarageId, kind, index });
  if (!result.ok) showAdminFeedback(result.error || 'Não foi possível teleportar.');
}
document.querySelectorAll('[data-teleport]').forEach(button => { button.onclick = () => teleportToGarage(button.dataset.teleport); });
document.querySelector('#new-garage').onclick = newGarage;
document.querySelectorAll('[data-capture]').forEach(button => { button.onclick = () => capture(button.dataset.capture); });
document.querySelector('#add-spawn').onclick = () => {
  const maximum = Number(adminData.limits?.maxSpawns) || 20;
  if ((draft.spawns || []).length >= maximum) return showAdminFeedback(`Limite de ${maximum} vagas atingido.`);
  capture('spawn', (draft.spawns || []).length);
};
document.querySelector('#add-catalog').onclick = () => {
  const maximum = Number(adminData.limits?.maxVehicles) || 100;
  if ((draft.vehicles || []).length >= maximum) return showAdminFeedback(`Limite de ${maximum} veículos atingido.`);
  draft.vehicles.push({ model: '', label: '', price: 0, departmentPrice: 0, taxRatePercent: null, taxExempt: false });
  renderCatalog();
  document.querySelector('.catalog-row:last-of-type input')?.focus();
};
document.querySelector('#blip-enabled').onchange = event => { document.querySelector('#blip-fields').classList.toggle('hidden', !event.target.checked); };

document.querySelector('#garage-editor').onsubmit = async event => {
  event.preventDefault();
  const payload = readEditor();
  showAdminFeedback('Salvando e sincronizando...', 'success');
  const response = await post('adminSave', payload);
  if (!response.ok) return showAdminFeedback(response.error || 'Não foi possível salvar a garagem.');
  const savedId = response.data?.id || payload.id;
  await refreshAdmin(savedId);
  showAdminFeedback(response.message || 'Garagem salva e sincronizada.', 'success');
};

document.querySelector('#delete-garage').onclick = async event => {
  if (!selectedGarageId) return;
  if (!deleteArmed) {
    deleteArmed = true;
    event.currentTarget.textContent = 'Clique novamente para confirmar';
    setTimeout(() => {
      deleteArmed = false;
      const button = document.querySelector('#delete-garage');
      if (button) button.textContent = 'Remover garagem';
    }, 5000);
    return;
  }
  const response = await post('adminDelete', { id: selectedGarageId });
  if (!response.ok) return showAdminFeedback(response.error || 'Não foi possível remover a garagem.');
  await refreshAdmin(null);
  showAdminFeedback(response.message || 'Garagem removida.', 'success');
};

window.addEventListener('message', event => {
  const data = event.data || {};
  if (data.action === 'open') {
    mode = 'garage';
    const config = data.imageConfig || {};
    images = { baseUrl: config.BaseUrl || images.baseUrl, extension: config.Extension || images.extension, default: config.Default || images.default, preload: config.Preload !== false };
    preload(fallback());
    app.className = '';
    vehicleView.classList.remove('hidden'); adminView.classList.add('hidden');
    vehicleActions.classList.remove('hidden'); adminActions.classList.add('hidden');
    document.querySelector('#subtitle').classList.add('hidden');
    document.querySelector('#title').textContent = data.title || 'Garagem';
  } else if (data.action === 'openAdmin') {
    mode = 'admin';
    adminData = data.data || adminData;
    app.className = 'admin-mode';
    vehicleView.classList.add('hidden'); adminView.classList.remove('hidden');
    vehicleActions.classList.add('hidden'); adminActions.classList.remove('hidden');
    document.querySelector('#title').textContent = 'Editor de garagens';
    const subtitle = document.querySelector('#subtitle');
    subtitle.textContent = 'Crie e publique pontos, vagas, permissões, blips e catálogos sem reiniciar'; subtitle.classList.remove('hidden');
    const first = (adminData.garages || [])[0];
    if (first) selectGarage(first.id); else newGarage();
  } else if (data.action === 'close') {
    app.classList.add('hidden'); captureHud.classList.add('hidden');
  } else if (data.action === 'vehicles') {
    render(data.vehicles || []);
  } else if (data.action === 'captureStart') {
    app.classList.add('hidden'); captureHud.classList.remove('hidden');
  } else if (data.action === 'captureResult') {
    captureHud.classList.add('hidden'); app.classList.remove('hidden');
    if (data.cancelled) return showAdminFeedback('Captura cancelada.');
    if (!data.point || !draft) return;
    if (data.kind === 'open') draft.coords = data.point;
    if (data.kind === 'store') draft.storeCoords = data.point;
    if (data.kind === 'spawn') draft.spawns[Number(data.index) || 0] = data.point;
    renderEditor();
    showAdminFeedback('Posição capturada.', 'success');
  }
});

document.querySelector('#close').onclick = () => post('close');
document.querySelector('#admin-close').onclick = () => post('close');
document.querySelector('#refresh').onclick = () => post('refresh');
document.querySelector('#store').onclick = () => post('store');
document.querySelector('#store-nearby').onclick = () => post('storeNearby');
document.onkeyup = event => { if (event.key === 'Escape' && !app.classList.contains('hidden')) post('close'); };
