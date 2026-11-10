const app = document.querySelector('#app');
const shopEl = document.querySelector('#shop');
const adminEl = document.querySelector('#admin');
const title = document.querySelector('#title');
const subtitle = document.querySelector('#subtitle');

let mode = null;
let data = null;
let selectedShop = null;
let imageConfig = { baseUrl: '', fallback: 'carro.png' };

const post = (name, payload = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload)
});

const money = value => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
}[char]));

const normalizeBase = value => {
  const base = String(value || '').trim();
  return base ? `${base.replace(/\/+$/, '')}/` : '';
};

const fallbackImage = () => {
  const fallback = String(imageConfig.fallback || 'carro.png').trim();
  return /^https?:\/\//i.test(fallback)
    ? fallback
    : `${normalizeBase(imageConfig.baseUrl)}${fallback.replace(/^\/+/, '')}`;
};

const vehicleImage = model => `${normalizeBase(imageConfig.baseUrl)}${encodeURIComponent(String(model || '').toLowerCase())}.png`;

function setImageConfig(config) {
  imageConfig = { ...imageConfig, ...(config || {}) };
}

function useFallback(image) {
  if (image.dataset.fallback === '1') return;
  image.dataset.fallback = '1';
  image.src = fallbackImage();
}

function preloadImages(models) {
  [...new Set(models || [])].forEach(model => {
    const image = new Image();
    image.onerror = () => {
      image.onerror = null;
      image.src = fallbackImage();
    };
    image.src = vehicleImage(model);
  });
}

document.querySelector('#close').onclick = () => post('close');
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') post('close');
});

function renderShop() {
  title.textContent = data.shop.label;
  subtitle.textContent = data.shop.shopType === 'player' ? 'Concessionária de jogador' : 'Concessionária pública';
  adminEl.classList.add('hidden');
  shopEl.classList.remove('hidden');

  setImageConfig(data.images);
  const cars = data.vehicles || [];
  preloadImages(cars.map(vehicle => vehicle.model));

  shopEl.innerHTML = `
    <div class="overview">
      <div><small>CATÁLOGO</small><p>${cars.length} veículo(s) disponível(is)</p></div>
      <div class="balance">DINHEIRO FÍSICO<b>${money(data.cash)}</b></div>
    </div>
    ${cars.length ? `<div class="cars">${cars.map(vehicle => `
      <article class="car">
        <img class="car-image" src="${escapeHtml(vehicleImage(vehicle.model))}" alt="${escapeHtml(vehicle.label)}">
        <span class="model">${escapeHtml(vehicle.model)}</span>
        <h3>${escapeHtml(vehicle.label)}</h3>
        <p>${escapeHtml(vehicle.category)} · Estoque: ${vehicle.stock}</p>
        <strong class="price">${money(vehicle.price)}</strong>
        <div class="actions">
          <button data-test="${vehicle.id}" ${vehicle.stock < 1 ? 'disabled' : ''}>Testar</button>
          <button data-buy="${vehicle.id}" ${vehicle.stock < 1 ? 'disabled' : ''}>Comprar</button>
        </div>
      </article>`).join('')}</div>` : '<div class="empty">Nenhum veículo está disponível nesta concessionária.</div>'}`;

  shopEl.querySelectorAll('.car-image').forEach(image => {
    image.addEventListener('error', () => useFallback(image));
  });
  shopEl.querySelectorAll('[data-buy]').forEach(button => {
    button.onclick = () => post('buy', { vehicleId: Number(button.dataset.buy) });
  });
  shopEl.querySelectorAll('[data-test]').forEach(button => {
    button.onclick = () => post('test', { vehicleId: Number(button.dataset.test) });
  });
}

function chosen() {
  return (data.shops || []).find(shop => Number(shop.id) === Number(selectedShop)) || null;
}

function editor(shop) {
  return `
    <div class="section">
      <h2>${escapeHtml(shop.label)} <small>#${shop.id} · ${shop.shopType === 'player' ? 'Jogador' : 'Pública'}</small></h2>
      <p>Vá até o lugar desejado e grave cada ponto. A entrada abre com <b>E</b>.</p>
      <div class="actions">
        <button data-point="access">Salvar entrada aqui</button>
        <button data-point="delivery">Salvar entrega aqui</button>
        <button data-point="test">Salvar teste aqui</button>
        <button class="danger" id="deleteShop">Excluir loja</button>
      </div>
    </div>
    <div class="section">
      <h2>Adicionar ou atualizar veículo</h2>
      <div class="form">
        <label>MODELO<input id="vehicleModel" list="models" placeholder="sultan"></label>
        <label>NOME<input id="vehicleLabel" placeholder="Karin Sultan"></label>
        <label>CATEGORIA<input id="vehicleCategory" placeholder="Esportivo"></label>
        <label>PREÇO<input id="vehiclePrice" type="number" min="0" placeholder="85000"></label>
        <label>ESTOQUE<input id="vehicleStock" type="number" min="0" value="1"></label>
      </div>
      <datalist id="models">${(data.suggested || []).map(vehicle => `<option value="${escapeHtml(vehicle.model)}">${escapeHtml(vehicle.label)}</option>`).join('')}</datalist>
      <div class="actions"><button id="saveVehicle">Salvar no catálogo</button></div>
    </div>
    <div class="section">
      <h2>Catálogo atual</h2>
      ${(shop.vehicles || []).length ? `<table class="vehicle-table"><thead><tr><th>VEÍCULO</th><th>PREÇO</th><th>ESTOQUE</th><th></th></tr></thead><tbody>${shop.vehicles.map(vehicle => `
        <tr><td><b>${escapeHtml(vehicle.label)}</b><br><small>${escapeHtml(vehicle.model)} · ${escapeHtml(vehicle.category)}</small></td><td>${money(vehicle.price)}</td><td>${vehicle.stock}</td><td><button class="danger" data-delete-vehicle="${vehicle.id}">Remover</button></td></tr>`).join('')}</tbody></table>` : '<p>Nenhum veículo cadastrado.</p>'}
    </div>`;
}

function bindEditor(shop) {
  adminEl.querySelectorAll('[data-point]').forEach(button => {
    button.onclick = () => post('setPoint', { shopId: shop.id, point: button.dataset.point });
  });
  adminEl.querySelector('#deleteShop').onclick = () => {
    if (confirm('Excluir esta concessionária e o catálogo?')) post('deleteShop', { shopId: shop.id });
  };

  const model = adminEl.querySelector('#vehicleModel');
  model.onchange = () => {
    const vehicle = (data.suggested || []).find(item => item.model === model.value);
    if (!vehicle) return;
    adminEl.querySelector('#vehicleLabel').value = vehicle.label;
    adminEl.querySelector('#vehicleCategory').value = vehicle.category;
    adminEl.querySelector('#vehiclePrice').value = vehicle.price;
  };

  adminEl.querySelector('#saveVehicle').onclick = () => post('saveVehicle', {
    shopId: shop.id,
    model: model.value,
    label: adminEl.querySelector('#vehicleLabel').value,
    category: adminEl.querySelector('#vehicleCategory').value,
    price: adminEl.querySelector('#vehiclePrice').value,
    stock: adminEl.querySelector('#vehicleStock').value
  });

  adminEl.querySelectorAll('[data-delete-vehicle]').forEach(button => {
    button.onclick = () => {
      if (confirm('Remover este veículo do catálogo?')) {
        post('deleteVehicle', { shopId: shop.id, id: Number(button.dataset.deleteVehicle) });
      }
    };
  });
}

function renderAdmin() {
  title.textContent = 'Editor de concessionárias';
  subtitle.textContent = 'Crie lojas, pontos de entrega e estoque sem editar arquivos.';
  shopEl.classList.add('hidden');
  adminEl.classList.remove('hidden');
  const shop = chosen();

  adminEl.innerHTML = `
    <div class="admin-grid">
      <aside class="sidebar">
        <div class="section">
          <h2>1. Criar concessionária</h2>
          <div class="form">
            <label>NOME<input id="newLabel" maxlength="80" placeholder="Ex.: Premium Motors"></label>
            <label>TIPO<select id="newType"><option value="public">Pública</option><option value="player">De jogador</option></select></label>
            <label>DONO (ID fixo, opcional)<input id="newOwner" type="number" min="1" placeholder="user_id"></label>
          </div>
          <div class="actions"><button id="createShop">Criar na minha posição</button></div>
        </div>
        <small>CONCESSIONÁRIAS</small>
        <div>${(data.shops || []).map(item => `<button class="shop-row ${Number(item.id) === Number(selectedShop) ? 'active' : ''}" data-shop="${item.id}">#${item.id} · ${escapeHtml(item.label)}<br><small>${item.shopType === 'player' ? 'Jogador' : 'Pública'}</small></button>`).join('') || '<p>Crie a primeira loja acima.</p>'}</div>
      </aside>
      <main>${shop ? editor(shop) : '<div class="empty">Primeiro crie uma concessionária. Depois selecione-a aqui para definir entrada, entrega, teste e estoque.</div>'}</main>
    </div>`;

  adminEl.querySelector('#createShop').onclick = () => post('createShop', {
    label: adminEl.querySelector('#newLabel').value,
    shopType: adminEl.querySelector('#newType').value,
    ownerUserId: adminEl.querySelector('#newOwner').value
  });
  adminEl.querySelectorAll('[data-shop]').forEach(button => {
    button.onclick = () => {
      selectedShop = Number(button.dataset.shop);
      renderAdmin();
    };
  });
  if (shop) bindEditor(shop);
}

window.addEventListener('message', event => {
  const message = event.data || {};
  if (message.action === 'close') {
    app.classList.add('hidden');
    mode = null;
    return;
  }
  if (message.action === 'preloadImages') {
    setImageConfig(message.images);
    preloadImages(message.models || []);
    return;
  }
  if (message.action === 'openShop') {
    mode = 'shop';
    data = message.data;
    app.classList.remove('hidden');
    renderShop();
    return;
  }
  if (message.action === 'openAdmin') {
    mode = 'admin';
    data = message.data;
    selectedShop = data.shops?.[0]?.id || null;
    app.classList.remove('hidden');
    renderAdmin();
    return;
  }
  if (message.action === 'adminData' && mode === 'admin') {
    data = message.data;
    if (!data.shops?.some(shop => Number(shop.id) === Number(selectedShop))) {
      selectedShop = data.shops?.[0]?.id || null;
    }
    renderAdmin();
    return;
  }
  if (message.action === 'cash' && mode === 'shop') {
    data.cash = message.cash;
    renderShop();
  }
});
