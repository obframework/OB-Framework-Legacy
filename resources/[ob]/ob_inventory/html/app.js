const app = document.getElementById('inventory');
const ownSlots = document.getElementById('own-slots');
const rightSlots = document.getElementById('right-slots');
const ownWeight = document.getElementById('own-weight');
const ownProgress = document.getElementById('own-progress');
const rightTitle = document.getElementById('right-title');
const rightName = document.getElementById('right-name');
const rightWeight = document.getElementById('right-weight');
const rightProgress = document.getElementById('right-progress');
const selectedIcon = document.getElementById('selected-icon');
const selectedName = document.getElementById('selected-name');
const amount = document.getElementById('amount');
const useButton = document.getElementById('use');
const sendButton = document.getElementById('send');
const commerceApp = document.getElementById('commerce');
const commerceBody = document.getElementById('commerce-body');
const commerceFeedback = document.getElementById('commerce-feedback');

let inventory = null;
let ground = null;
let shop = null;
let other = null;
let selected = null;
let commerceData = null;
let commerceSelected = null;
let drag = null;
let dragGhost = null;
let itemImages = {
  baseUrl: '/orbis/icons/',
  extension: '.png',
  preload: true,
  localFallback: false,
  localPath: 'assets/items',
  aliases: {},
};
const requestedIcons = new Set();
const missingIcons = new Set();
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_inventory';
const post = (event, data = {}) => fetch(`https://${resource}/${event}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
});
const kg = (value) => `${(Number(value || 0) / 1000).toFixed(1)} kg`;
const escapeHtml = (value) => String(value || '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

function durabilityInfo(item) {
  const expiresAt = Number(item?.durability?.expiresAt || 0);
  const createdAt = Number(item?.durability?.createdAt || 0);
  if (!expiresAt || !createdAt) return null;
  const total = Math.max(1, expiresAt - createdAt);
  const remaining = Math.max(0, expiresAt - Math.floor(Date.now() / 1000));
  return { percent: Math.max(0, Math.min(100, (remaining / total) * 100)), expired: remaining <= 0, remaining };
}

function durabilityLabel(info) {
  if (!info) return '';
  if (info.expired) return 'Durabilidade: vencido';
  const days = Math.floor(info.remaining / 86400);
  const hours = Math.ceil((info.remaining % 86400) / 3600);
  return `Durabilidade: ${Math.round(info.percent)}% (${days}d ${hours}h)`;
}

function sideItems(side) {
  if (side === 'own') return inventory?.items || {};
  if (side === 'ground') return ground?.items || {};
  if (side === 'shop') return shop?.items || [];
  if (side === 'other') return other?.inventory?.items || {};
  return {};
}

function itemAt(side, index) {
  const list = sideItems(side);
  // O encoder do FiveM pode entregar o catalogo como array ou como tabela
  // indexada. No array, o slot 1 corresponde ao indice 0; a ordem anterior
  // lia o indice 1 e repetia o segundo item (powerbank).
  if (side === 'shop') {
    if (Array.isArray(list)) return list[Number(index) - 1] || null;
    return list[String(index)] || list[index] || null;
  }
  return list[index] || list[String(index)] || null;
}

function normalizeIconBase(base) {
  const value = String(base || '').trim();
  return value ? (value.endsWith('/') ? value : `${value}/`) : '';
}

function localItemImage(item) {
  if (item?.image) return item.image;
  const name = String(item?.name || '').trim().toLowerCase();
  if (!name || !itemImages.localFallback) return '';
  const path = String(itemImages.localPath || 'assets/items').replace(/\/+$/, '');
  return `${path}/${encodeURIComponent(name)}${itemImages.extension || '.png'}`;
}

function remoteItemImage(item) {
  const name = String(item?.name || '').trim().toLowerCase();
  if (!name || item?.image || !itemImages.baseUrl || missingIcons.has(name)) return localItemImage(item);
  const fileName = itemImages.aliases[name] || name;
  return `${normalizeIconBase(itemImages.baseUrl)}${encodeURIComponent(fileName)}${itemImages.extension || '.png'}`;
}

function preloadItemIcon(item) {
  if (!itemImages.preload || item?.image) return;
  const name = String(item?.name || '').trim().toLowerCase();
  const url = remoteItemImage(item);
  if (!name || !url || requestedIcons.has(url) || missingIcons.has(name)) return;
  requestedIcons.add(url);
  const image = new Image();
  image.onerror = () => missingIcons.add(name);
  image.src = url;
}

function preloadVisibleIcons() {
  const lists = [inventory?.items, ground?.items, shop?.items, other?.inventory?.items];
  lists.forEach((items) => Object.values(items || {}).forEach(preloadItemIcon));
}

function setItemImageConfig(config) {
  if (!config) return;
  itemImages = {
    baseUrl: config.BaseUrl || itemImages.baseUrl,
    extension: config.Extension || itemImages.extension,
    preload: config.Preload !== false,
    localFallback: config.LocalFallback === true,
    localPath: config.LocalPath || itemImages.localPath,
    aliases: config.Aliases || {},
  };
}

function preloadCatalogIcons(names) {
  const list = Array.isArray(names) ? names : [];
  let index = 0;
  const loadBatch = () => {
    const limit = Math.min(index + 8, list.length);
    while (index < limit) preloadItemIcon({ name: list[index++] });
    if (index < list.length) setTimeout(loadBatch, 60);
  };
  loadBatch();
}

function itemIcon(className, item) {
  const image = remoteItemImage(item);
  const fallback = localItemImage(item);
  const imageElement = image
    ? `<img src="${escapeHtml(image)}" data-icon-name="${escapeHtml(item.name)}" data-icon-fallback="${escapeHtml(fallback)}" alt="" draggable="false">`
    : '';
  return `<span class="${className}"><b>${escapeHtml(item.icon || '?')}</b>${imageElement}</span>`;
}

const itemChangeQueue = [];
function showItemChanges(changes) {
  for (const item of Array.isArray(changes) ? changes : []) {
    if (!item?.name || !Number.isFinite(Number(item.amount)) || Number(item.amount) <= 0) continue;
    if (itemChangeQueue.length < 60) itemChangeQueue.push(item);
  }
  drainItemChanges();
}
function drainItemChanges() {
  const container = document.querySelector('#item-changes');
  while (container.childElementCount < 3 && itemChangeQueue.length) {
    const item = itemChangeQueue.shift();
    const card = document.createElement('div');
    card.className = `item-change${item.added === true ? '' : ' removed'}`;
    card.innerHTML = `${itemIcon('item-change-icon', item)}<span class="item-change-info"><strong>${escapeHtml(item.label || item.name)}</strong><small>${item.added === true ? '+' : '−'}${Number(item.amount).toLocaleString('pt-BR')} ×</small></span>`;
    container.appendChild(card);
    applyIconFallbacks(card);
    setTimeout(() => {
      card.classList.add('leaving');
      setTimeout(() => { card.remove(); drainItemChanges(); }, 200);
    }, 2600);
  }
}

function applyIconFallbacks(root = document) {
  root.querySelectorAll('img[data-icon-name]').forEach((image) => {
    if (image.dataset.iconBound === '1') return;
    image.dataset.iconBound = '1';
    const showImage = () => image.parentElement?.classList.add('has-image');
    const handleError = () => {
      image.parentElement?.classList.remove('has-image');
      const name = String(image.dataset.iconName || '').toLowerCase();
      if (name) missingIcons.add(name);
      const fallback = image.dataset.iconFallback || '';
      const source = image.getAttribute('src') || '';
      // So tenta o arquivo local quando essa reserva foi habilitada e o caminho
      // e diferente da imagem que acabou de falhar.
      if (!fallback || fallback === source || image.dataset.fallbackApplied === '1') return image.remove();
      image.dataset.fallbackApplied = '1';
      image.src = fallback;
    };
    image.addEventListener('load', showImage);
    image.addEventListener('error', handleError);
    if (image.complete) {
      if (image.naturalWidth > 0) showImage();
      else handleError();
    }
  });
}

function itemTooltip(item) {
  const info = durabilityInfo(item);
  const uses = item.maxUses ? `<small>Usos restantes: ${Math.max(0, Number(item.metadata?.usesRemaining ?? item.maxUses))}/${Number(item.maxUses)}</small>` : '';
  const carry = Number(item.maxCarry) > 0 ? `<small>Limite na mochila: ${Number(item.maxCarry).toLocaleString('pt-BR')}</small>` : '';
  const hasStock = Object.prototype.hasOwnProperty.call(item || {}, 'stock');
  const stock = hasStock ? `<small class="tooltip-stock">Estoque: ${Math.max(0, Number(item.stock) || 0).toLocaleString('pt-BR')}</small>` : '';
  return `<span class="item-tooltip"><b>${escapeHtml(item.label || item.name)}</b><em>${escapeHtml(item.description || item.label || item.name)}</em>${stock}${carry}${uses}${info ? `<small>${durabilityLabel(info)}</small>` : ''}</span>`;
}

function setSelectedIcon(item) {
  selectedIcon.innerHTML = itemIcon('selected-icon-content', item);
}

function slotAmountText(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || Math.abs(amount) < 1000) return `${value}x`;
  const units = [[1e12, 'T'], [1e9, 'B'], [1e6, 'M'], [1e3, 'k']];
  let unitIndex = units.findIndex(([limit]) => Math.abs(amount) >= limit);
  if (unitIndex > 0 && Math.abs(amount / units[unitIndex][0]) >= 999.5) unitIndex -= 1;
  const [size, suffix] = units[unitIndex];
  const scaled = amount / size;
  const digits = Math.abs(scaled) < 10 ? 1 : 0;
  return `${scaled.toLocaleString('pt-BR', { maximumFractionDigits: digits })}${suffix}x`;
}

function selectedAmount(item, maximum) {
  const value = Math.floor(Number(amount.value || 1));
  return Math.max(1, Math.min(maximum || Number(item.amount || 1), value));
}

function shopItemMaximum(item) {
  const purchaseLimit = Math.max(1, Math.floor(Number(item?.maxPurchase) || 10));
  if (shop?.owned !== true) return purchaseLimit;
  return Math.max(0, Math.min(purchaseLimit, Math.floor(Number(item?.stock) || 0)));
}

function shopItemOutOfStock(item, side) {
  return side === 'shop' && shop?.owned === true && shopItemMaximum(item) < 1;
}

function selectItem(side, index) {
  const item = itemAt(side, index);
  if (!item) return;
  selected = { side, index: Number(index) };
  amount.value = 1;
  amount.max = side === 'shop' ? Math.max(1, shopItemMaximum(item)) : Number(item.amount || 1);
  render();
}

function slot(item, index, side, locked = false) {
  const active = selected && selected.side === side && Number(selected.index) === Number(index);
  if (!item) return `<button class="slot empty ${locked ? 'locked' : ''}" data-side="${side}" data-index="${index}" data-locked="${locked ? '1' : '0'}" aria-label="Slot ${index} vazio"><span class="slot-number">${index}</span></button>`;
  const fullAmount = Number(item.amount).toLocaleString('pt-BR');
  const outOfStock = shopItemOutOfStock(item, side);
  const amountLabel = side === 'shop'
    ? `<span class="slot-amount shop-stock ${outOfStock ? 'empty-stock' : ''}" title="${shop?.owned === true ? `Estoque: ${Math.max(0, Number(item.stock) || 0).toLocaleString('pt-BR')}` : 'Estoque ilimitado'}">${shop?.owned === true ? `${Math.max(0, Number(item.stock) || 0).toLocaleString('pt-BR')}x` : '∞'}</span>`
    : `<span class="slot-amount" title="${escapeHtml(fullAmount)} itens">${escapeHtml(slotAmountText(item.amount))}</span>`;
  const priceLabel = side === 'shop' ? `<span class="slot-price">${money(item.price)}</span>` : '';
  const durability = durabilityInfo(item);
  const bar = durability ? `<i class="durability ${durability.expired ? 'expired' : ''}" style="width:${durability.percent}%"></i>` : '';
  return `<button class="slot ${active ? 'selected' : ''} ${locked ? 'locked' : ''} ${outOfStock ? 'out-of-stock' : ''} ${durability?.expired ? 'item-expired' : ''}" data-side="${side}" data-index="${index}" data-locked="${locked ? '1' : '0'}" data-out-of-stock="${outOfStock ? '1' : '0'}" aria-disabled="${outOfStock ? 'true' : 'false'}"><span class="slot-number">${index}</span>${itemIcon('item-icon', item)}<span class="slot-label">${item.label || item.name}</span>${amountLabel}${priceLabel}${bar}${itemTooltip(item)}</button>`;
}

function renderSlots(element, data, side, count, activeCount = count) {
  const previousScroll = element.scrollTop;
  let html = '';
  for (let index = 1; index <= count; index += 1) html += slot(itemAt(side, index), index, side, index > Number(activeCount || count));
  element.innerHTML = html;
  element.scrollTop = previousScroll;
  element.querySelectorAll('button[data-index]').forEach((button) => {
    button.addEventListener('pointerdown', (event) => beginPointerDrag(event, button.dataset.side, Number(button.dataset.index)));
    button.addEventListener('contextmenu', (event) => {
      event.preventDefault();
      const side = button.dataset.side;
      const index = Number(button.dataset.index);
      const item = itemAt(side, index);
      if (side !== 'own' || !item) return;
      selected = { side, index };
      post('use', {
        slot: index,
        amount: event.ctrlKey === true ? Number(item.amount || 1) : 1,
        loadMaximum: event.ctrlKey === true,
      });
    });
    button.addEventListener('mouseenter', () => positionTooltip(button));
    button.addEventListener('mouseleave', () => resetTooltip(button));
  });
}

function positionTooltip(button) {
  const tooltip = button.querySelector('.item-tooltip');
  if (!tooltip) return;
  const rect = button.getBoundingClientRect();
  const bounds = tooltip.getBoundingClientRect();
  const margin = 8;
  const left = Math.max(margin, Math.min(window.innerWidth - bounds.width - margin, rect.left + (rect.width - bounds.width) / 2));
  let top = rect.top - bounds.height - margin;
  if (top < margin) top = Math.min(window.innerHeight - bounds.height - margin, rect.bottom + margin);
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
}

function resetTooltip(button) {
  const tooltip = button.querySelector('.item-tooltip');
  if (tooltip) tooltip.removeAttribute('style');
}

function renderSelected() {
  const item = selected && itemAt(selected.side, selected.index);
  if (!item) {
    selected = null;
    selectedIcon.textContent = '?';
    selectedName.textContent = 'Selecione um item';
    useButton.disabled = true; sendButton.disabled = true;
    return;
  }

  setSelectedIcon(item);
  selectedName.textContent = item.label || item.name;
  amount.max = selected.side === 'shop' ? Math.max(1, shopItemMaximum(item)) : item.amount;
  if (Number(amount.value) > Number(amount.max)) amount.value = amount.max;

  const usable = ['medical', 'medical_supply', 'medical_stretcher', 'consumable', 'weapon', 'weapon_component', 'weapon_ammo', 'backpack', 'armor', 'lockpick', 'mechanic_repair', 'mechanic_tyre', 'phone', 'powerbank', 'parachute', 'document', 'forensic_kit'];
  useButton.disabled = Boolean(other) || selected.side !== 'own' || (!usable.includes(item.type) && item.name !== 'emstablet') || item.name === 'adrenaline' || durabilityInfo(item)?.expired;
  sendButton.disabled = Boolean(other) || selected.side !== 'own';
}

function render() {
  const own = inventory || { slots: 30, items: {}, weight: 0, maxWeight: 20000 };
  renderSlots(ownSlots, own.items, 'own', Number(own.slots || 30), Number(own.activeSlots || own.slots || 30));
  ownWeight.textContent = `${kg(own.weight)} / ${kg(own.maxWeight)}`;
  ownProgress.style.width = `${Math.min(100, (Number(own.weight || 0) / Number(own.maxWeight || 1)) * 100)}%`;

  if (other) {
    const viewed = other.inventory || { slots: 30, items: {}, weight: 0, maxWeight: 20000 };
    renderSlots(rightSlots, viewed.items || {}, 'other', Number(viewed.slots || 30), Number(viewed.activeSlots || viewed.slots || 30));
    rightSlots.classList.toggle('read-only', other.mode === 'readonly');
    rightTitle.textContent = other.mode === 'police' ? 'REVISTA POLICIAL'
      : other.mode === 'container' ? 'BAÚ DA ORGANIZAÇÃO'
        : other.mode === 'discard' ? 'DESCARTE INFINITO' : 'VISUALIZAÇÃO';
    rightName.textContent = other.label || 'Outra pessoa';
    rightWeight.textContent = other.mode === 'discard' ? 'Itens colocados aqui são apagados' : `${kg(viewed.weight)} / ${kg(viewed.maxWeight)}`;
    rightProgress.style.width = other.mode === 'discard' ? '100%' : `${Math.min(100, (Number(viewed.weight || 0) / Number(viewed.maxWeight || 1)) * 100)}%`;
  } else if (shop) {
    rightSlots.classList.remove('read-only');
    const items = shop.items || {};
    const itemCount = Object.keys(items).length;
    renderSlots(rightSlots, items, 'shop', Math.max(5, itemCount));
    rightTitle.textContent = 'LOJA';
    rightName.textContent = shop.label || 'Catalogo';
    if (shop.owned === true) {
      const stockTotal = Object.values(items).reduce((total, item) => total + Math.max(0, Number(item?.stock) || 0), 0);
      rightWeight.textContent = `${stockTotal.toLocaleString('pt-BR')} unidade${stockTotal === 1 ? '' : 's'} em estoque`;
    } else {
      rightWeight.textContent = 'Estoque ilimitado';
    }
    rightProgress.style.width = '100%';
  } else {
    rightSlots.classList.remove('read-only');
    const items = ground?.items || {};
    renderSlots(rightSlots, items, 'ground', 30);
    const itemCount = Object.values(items).reduce((total, item) => total + Number(item?.amount || 0), 0);
    rightTitle.textContent = 'CHÃO';
    rightName.textContent = ground ? 'Itens no chão' : 'Nenhum item';
    rightWeight.textContent = `${itemCount} item${itemCount === 1 ? '' : 's'}`;
    rightProgress.style.width = ground ? '100%' : '0%';
  }
  renderSelected();
  applyIconFallbacks();
  preloadVisibleIcons();
}

function setData(data) {
  setItemImageConfig(data.imageConfig);
  inventory = data.inventory || inventory;
  ground = data.ground || null;
  if (Object.prototype.hasOwnProperty.call(data, 'shop')) shop = data.shop || null;
  if (Object.prototype.hasOwnProperty.call(data, 'other')) other = data.other || null;
  if (selected && !itemAt(selected.side, selected.index)) selected = null;
  render();
}

function dragAmount(item, side, index, allItems) {
  const maximum = side === 'shop' ? shopItemMaximum(item) : Number(item.amount || 1);
  if (allItems) return maximum;
  const requested = Math.floor(Number(amount.value || 1));
  if (requested > 1) return Math.max(1, Math.min(maximum, requested));
  if (selected && selected.side === side && Number(selected.index) === Number(index)) return selectedAmount(item, maximum);
  return 1;
}

function lockedSlot(side, index) {
  const source = side === 'own' ? inventory : side === 'other' ? other?.inventory : null;
  if (!source) return false;
  return Number(index) > Number(source.activeSlots || source.slots || 0);
}

function beginPointerDrag(event, side, index) {
  if (event.button !== 0) return;
  const item = itemAt(side, index);
  if (!item) return;
  if (shopItemOutOfStock(item, side)) return;
  drag = { side, index, item, amount: dragAmount(item, side, index, event.ctrlKey === true), x: event.clientX, y: event.clientY, moved: false };
  window.addEventListener('pointermove', movePointerDrag);
  window.addEventListener('pointerup', endPointerDrag, { once: true });
}

function makeDragGhost(item) {
  const ghost = document.createElement('div');
  ghost.className = 'drag-ghost';
  ghost.innerHTML = `${itemIcon('item-icon', item)}<b>${item.label || item.name}</b>`;
  document.body.appendChild(ghost);
  applyIconFallbacks(ghost);
  return ghost;
}

function movePointerDrag(event) {
  if (!drag) return;
  if (!drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 7) {
    drag.moved = true;
    dragGhost = makeDragGhost(drag.item);
  }
  if (dragGhost) {
    dragGhost.style.left = `${event.clientX + 14}px`;
    dragGhost.style.top = `${event.clientY + 14}px`;
  }
}

function endPointerDrag(event) {
  window.removeEventListener('pointermove', movePointerDrag);
  if (!drag) return;
  const dropped = drag;
  drag = null;
  if (dragGhost) { dragGhost.remove(); dragGhost = null; }
  if (!dropped.moved) return selectItem(dropped.side, dropped.index);

  const target = document.elementFromPoint(event.clientX, event.clientY);
  const targetSlot = target && target.closest('.slot[data-side][data-index]');
  const targetSide = targetSlot && targetSlot.dataset.side;
  const targetIndex = targetSlot && Number(targetSlot.dataset.index);
  const targetLocked = targetSlot?.dataset.locked === '1';
  const sourceLocked = lockedSlot(dropped.side, dropped.index);

  if (dropped.side === 'own') {
    if (targetSide === 'own' && !targetLocked && targetIndex !== dropped.index && !(sourceLocked && itemAt('own', targetIndex))) post('move', { fromSlot: dropped.index, toSlot: targetIndex });
    else if (targetSide === 'other' && !targetLocked && (other?.mode === 'container' || other?.mode === 'discard')) post('containerPut', { slot: dropped.index, amount: dropped.amount, targetSlot: targetIndex });
    else if (target && target.closest('#right-slots') && !shop && !other) post('drop', { slot: dropped.index, amount: dropped.amount });
    return;
  }
  if (dropped.side === 'ground' && targetSide === 'own' && !targetLocked) {
    post('pickup', { index: dropped.index, amount: dropped.amount, targetSlot: targetIndex });
    return;
  }
  if (dropped.side === 'shop' && targetSide === 'own' && !targetLocked) {
    post('shopBuy', { item: dropped.item.name, amount: dropped.amount, targetSlot: targetIndex });
    return;
  }
  if (dropped.side === 'other' && targetSide === 'own' && !targetLocked && other?.mode === 'police') {
    post('otherTake', { slot: dropped.index, amount: dropped.amount, targetSlot: targetIndex });
    return;
  }
  if (dropped.side === 'other' && targetSide === 'own' && !targetLocked && other?.mode === 'container') {
    post('containerTake', { slot: dropped.index, amount: dropped.amount, targetSlot: targetIndex });
    return;
  }
  if (dropped.side === 'other' && targetSide === 'other' && !targetLocked && targetIndex !== dropped.index && !(sourceLocked && itemAt('other', targetIndex)) && other?.mode === 'container') {
    post('containerMove', { fromSlot: dropped.index, toSlot: targetIndex });
  }
}

async function commercePost(event, payload = {}) {
  try { return await (await post(event, payload)).json(); }
  catch (_) { return { ok: false, message: 'Falha de comunicacao.' }; }
}
function commerceMessage(message = '', success = false) {
  commerceFeedback.textContent = message;
  commerceFeedback.className = success ? 'commerce-success' : '';
}
function renderCommerce() {
  if (!commerceData) return;
  const commerceTitle = commerceApp.querySelector('h1');
  if (commerceTitle) commerceTitle.textContent = commerceData.scoped ? 'Gestao desta loja' : 'Gestao de lojas';
  const stores = commerceData.stores || [];
  if (!commerceSelected || !stores.some(store => store.shop_id === commerceSelected)) commerceSelected = stores[0]?.shop_id || null;
  const current = stores.find(store => store.shop_id === commerceSelected);
  const offer = commerceData.offer ? `<section class="commerce-offer"><h2>Loja disponivel</h2><p><b>${escapeHtml(commerceData.offer.label)}</b> por ${money(commerceData.offer.price)}</p><div class="commerce-form"><label>Nome da sua loja<input id="commerce-buy-name" maxlength="80" value="${escapeHtml(commerceData.offer.label)}"></label><button id="commerce-buy">Comprar loja</button></div></section>` : '';
  const list = stores.map(store => `<button data-commerce-store="${escapeHtml(store.shop_id)}" class="${store.shop_id === commerceSelected ? 'active' : ''}"><b>${escapeHtml(store.custom_name)}</b><small>${escapeHtml(store.shop_id)}</small></button>`).join('') || '<p>Voce ainda nao possui lojas.</p>';
  let content = '<p>Selecione uma loja para administrar.</p>';
  if (current) {
    const stock = (current.stock || []).map(item => `<tr><td>${escapeHtml(item.item_name)}</td><td>${Number(item.quantity).toLocaleString('pt-BR')} / ${Number(item.max_stock).toLocaleString('pt-BR')}</td><td>${money(item.wholesale_price)}</td><td><form class="commerce-price" data-item="${escapeHtml(item.item_name)}"><input type="number" min="1" max="100000000" value="${Number(item.sale_price)}"><button>Salvar</button></form></td></tr>`).join('');
    const orderItems = (current.stock || []).map(item => `<label>${escapeHtml(item.item_name)}<input class="commerce-order-qty" data-item="${escapeHtml(item.item_name)}" type="number" min="0" max="1000" value="0"></label>`).join('');
    const checks = stores.map(store => `<label><input class="commerce-order-shop" type="checkbox" value="${escapeHtml(store.shop_id)}" ${store.shop_id === current.shop_id ? 'checked' : ''}>${escapeHtml(store.custom_name)}</label>`).join('');
    const activeOrder = current.activeOrder ? `<div class="commerce-order-active"><span>Pedido #${Number(current.activeOrder.id)} em andamento (${current.activeOrder.method === 'pickup' ? 'retirada propria' : 'motorista'}).</span><div><button id="commerce-track-order" data-order-id="${Number(current.activeOrder.id)}">Rastrear entrega</button><button id="commerce-cancel-order" data-order-id="${Number(current.activeOrder.id)}">Cancelar e estornar</button></div></div>` : '';
    const fiscalButton = commerceData.fiscalAvailable ? '<button type="button" id="commerce-fiscal" class="commerce-secondary">Contabilidade fiscal</button>' : '';
    content = `<div class="commerce-content"><div class="commerce-heading"><h2>${escapeHtml(current.custom_name)}</h2>${fiscalButton}</div><div class="commerce-stats"><div><small>Caixa</small><b>${money(current.balance)}</b></div><div><small>Vendas</small><b>${money(current.total_sales)}</b></div><div><small>Impostos</small><b>${money(current.total_tax)}</b></div></div>
      <form id="commerce-rename" class="commerce-form"><label>Novo nome<input maxlength="80" value="${escapeHtml(current.custom_name)}"></label><button>Renomear</button></form>
      <form id="commerce-withdraw" class="commerce-form"><label>Sacar do caixa<input type="number" min="1" value="1"></label><button>Sacar</button></form><form id="commerce-deposit" class="commerce-form"><label>Depositar dinheiro no caixa<input type="number" min="1" value="1"></label><button>Depositar</button></form>
      <table class="commerce-stock"><thead><tr><th>Produto</th><th>Estoque</th><th>Custo</th><th>Preco de venda</th></tr></thead><tbody>${stock}</tbody></table>
      <section class="commerce-order"><h3>Novo pedido para uma ou varias lojas</h3>${activeOrder}<div class="commerce-checks">${checks}</div><div class="commerce-order-items">${orderItems}</div><p>O valor sai do caixa de cada loja. O motorista cobra taxa de entrega; a retirada propria possui desconto.</p><div class="commerce-order-actions"><button id="commerce-order-npc" ${current.activeOrder ? 'disabled' : ''}>Entrega por motorista</button><button id="commerce-order-pickup" class="commerce-secondary" ${current.activeOrder ? 'disabled' : ''}>Retirar com caminhao (-10%)</button></div></section></div>`;
  }
  commerceBody.innerHTML = `${offer}<div class="commerce-grid"><aside class="commerce-list"><h3>${commerceData.scoped ? 'Esta loja' : 'Minhas lojas'}</h3>${list}</aside>${content}</div>`;
  commerceBody.querySelectorAll('[data-commerce-store]').forEach(button => button.onclick = () => { commerceSelected = button.dataset.commerceStore; renderCommerce(); });
  const buy = document.getElementById('commerce-buy'); if (buy) buy.onclick = async () => { const result = await commercePost('commercePurchase', { shopId: commerceData.offer.id, name: document.getElementById('commerce-buy-name').value }); commerceMessage(result.message, result.ok); };
  const rename = document.getElementById('commerce-rename'); if (rename) rename.onsubmit = async event => { event.preventDefault(); const result = await commercePost('commerceRename', { shopId: current.shop_id, name: rename.querySelector('input').value }); commerceMessage(result.message, result.ok); };
  const fiscal = document.getElementById('commerce-fiscal'); if (fiscal) fiscal.onclick = async () => { const result = await commercePost('commerceFiscal', { shopId: current.shop_id }); if (!result.ok) commerceMessage(result.message, false); };
  const withdraw = document.getElementById('commerce-withdraw'); if (withdraw) withdraw.onsubmit = async event => { event.preventDefault(); const result = await commercePost('commerceWithdraw', { shopId: current.shop_id, amount: Number(withdraw.querySelector('input').value) }); commerceMessage(result.message, result.ok); };
  const deposit = document.getElementById('commerce-deposit'); if (deposit) deposit.onsubmit = async event => { event.preventDefault(); const result = await commercePost('commerceDeposit', { shopId: current.shop_id, amount: Number(deposit.querySelector('input').value) }); commerceMessage(result.message, result.ok); };
  commerceBody.querySelectorAll('.commerce-price').forEach(form => form.onsubmit = async event => { event.preventDefault(); const result = await commercePost('commerceSetPrice', { shopId: current.shop_id, item: form.dataset.item, price: Number(form.querySelector('input').value) }); commerceMessage(result.message, result.ok); });
  const createOrder = async (method) => { const shopIds = [...commerceBody.querySelectorAll('.commerce-order-shop:checked')].map(input => input.value); const items = {}; commerceBody.querySelectorAll('.commerce-order-qty').forEach(input => items[input.dataset.item] = Number(input.value)); const result = await commercePost('commerceOrder', { shopIds, items, method }); commerceMessage(result.message, result.ok); };
  const npcOrder = document.getElementById('commerce-order-npc'); if (npcOrder) npcOrder.onclick = () => createOrder('npc');
  const pickupOrder = document.getElementById('commerce-order-pickup'); if (pickupOrder) pickupOrder.onclick = () => createOrder('pickup');
  const cancelOrder = document.getElementById('commerce-cancel-order'); if (cancelOrder) cancelOrder.onclick = async () => { const result = await commercePost('commerceCancelOrder', { orderId: Number(cancelOrder.dataset.orderId) }); commerceMessage(result.message, result.ok); };
  const trackOrder = document.getElementById('commerce-track-order'); if (trackOrder) trackOrder.onclick = async () => { const result = await commercePost('commerceTrackOrder', { orderId: Number(trackOrder.dataset.orderId) }); commerceMessage(result.message, result.ok); };
}

document.getElementById('commerce-close').addEventListener('click', () => post('commerceClose'));
document.getElementById('close').addEventListener('click', () => post('close'));
useButton.addEventListener('click', (event) => {
  if (selected?.side !== 'own') return;
  const item = itemAt('own', selected.index);
  if (!item) return;
  post('use', {
    slot: selected.index,
    amount: selectedAmount(item, Number(item.amount || 1)),
    loadMaximum: event.ctrlKey === true,
  });
});
sendButton.addEventListener('click', () => {
  if (!selected || selected.side !== 'own') return;
  post('transfer', { slot: selected.index, amount: selectedAmount(itemAt('own', selected.index)) });
});

window.addEventListener('keyup', (event) => { if (event.key === 'Escape') commerceApp.classList.contains('hidden') ? post('close') : post('commerceClose'); });
window.addEventListener('message', ({ data }) => {
  if (!data) return;
  if (data.action === 'itemChanges') {
    setItemImageConfig(data.imageConfig);
    showItemChanges(data.changes);
  }
  if (data.action === 'commerceOpen') { commerceData = data.data; commerceSelected = commerceData.stores?.[0]?.shop_id || null; commerceApp.classList.remove('hidden'); commerceMessage(); renderCommerce(); }
  if (data.action === 'commerceData') { commerceData = data.data; renderCommerce(); }
  if (data.action === 'commerceClose') { commerceApp.classList.add('hidden'); commerceData = null; commerceSelected = null; }
  if (data.action === 'open') {
    app.classList.remove('hidden');
    ownSlots.scrollTop = 0;
    rightSlots.scrollTop = 0;
    inventory = data.inventory || null;
    ground = data.ground || null;
    shop = data.shop || null;
    other = data.other || null;
    setItemImageConfig(data.imageConfig);
    selected = null;
    render();
  }
  if (data.action === 'close') { app.classList.add('hidden'); selected = null; other = null; }
  if (data.action === 'setData') setData(data);
  if (data.action === 'preloadIcons') {
    setItemImageConfig(data.imageConfig);
    preloadCatalogIcons(data.items);
  }
});

setInterval(() => { if (!app.classList.contains('hidden')) render(); }, 60000);
