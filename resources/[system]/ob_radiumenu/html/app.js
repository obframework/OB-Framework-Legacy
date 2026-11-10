const app = document.getElementById('app');
const radial = document.getElementById('radial');
const panel = document.getElementById('outfit-panel');
const list = document.getElementById('outfit-list');
const resource = GetParentResourceName();

function post(action, data = {}) {
  return fetch(`https://${resource}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
}
function close() { app.classList.add('hidden'); panel.classList.add('hidden'); radial.classList.remove('hidden'); post('close'); }
function showOutfits(data = []) {
  const saved = new Map(data.map(item => [Number(item.slot), item]));
  list.innerHTML = '';
  for (let slot = 1; slot <= 5; slot++) {
    const outfit = saved.get(slot);
    const row = document.createElement('div'); row.className = `outfit${outfit ? '' : ' empty'}`;
    row.innerHTML = outfit
      ? `<span class="number">${slot}</span><span class="name">${escapeHtml(outfit.label)}</span><button data-load="${slot}">Vestir</button>`
      : `<span class="number">${slot}</span><span class="name">Espaço vazio</span>`;
    list.appendChild(row);
  }
  radial.classList.add('hidden'); panel.classList.remove('hidden');
}
function escapeHtml(value) { const node = document.createElement('span'); node.textContent = value || 'Roupa'; return node.innerHTML; }

document.addEventListener('click', event => {
  const closeButton = event.target.closest('[data-close], #close');
  if (closeButton) return close();
  if (event.target.closest('[data-back]')) { panel.classList.add('hidden'); radial.classList.remove('hidden'); return; }
  const load = event.target.closest('[data-load]');
  if (load) return post('action', { action: 'loadOutfit', slot: Number(load.dataset.load) });
  const action = event.target.closest('[data-action]');
  if (action) post('action', { action: action.dataset.action });
});
document.getElementById('save-form').addEventListener('submit', event => {
  event.preventDefault();
  post('action', { action: 'saveOutfit', slot: Number(document.getElementById('slot').value), label: document.getElementById('label').value });
});
window.addEventListener('message', event => {
  const data = event.data || {};
  if (data.action === 'open') {
    app.classList.remove('hidden'); radial.classList.remove('hidden'); panel.classList.add('hidden');
  }
  if (data.action === 'close') { app.classList.add('hidden'); }
  if (data.action === 'outfits') showOutfits(data.data || []);
});
document.addEventListener('keydown', event => { if (event.key === 'Escape' || event.key === 'F1') { event.preventDefault(); close(); } });
