const app = document.getElementById('app');
const identity = document.getElementById('identity');
const items = document.getElementById('items');
const empty = document.getElementById('empty');
const resource = GetParentResourceName();

function post(action, data = {}) {
  return fetch(`https://${resource}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
}

function close() {
  app.classList.add('hidden');
  post('close');
}

function render(entries = []) {
  items.replaceChildren();
  empty.classList.toggle('hidden', entries.length !== 0);
  entries.forEach(item => {
    const row = document.createElement('article');
    row.className = 'item';

    const slot = document.createElement('span');
    slot.className = 'slot';
    slot.textContent = String(item.slot || '?');

    const name = document.createElement('div');
    name.className = 'name';
    const label = document.createElement('strong');
    label.textContent = item.label || item.name || 'Item';
    const type = document.createElement('span');
    type.textContent = `${item.name || 'item'} · disponível: ${Number(item.amount || 0)}`;
    name.append(label, type);

    const amount = document.createElement('input');
    amount.className = 'amount';
    amount.type = 'number';
    amount.min = '1';
    amount.max = String(Math.max(1, Number(item.amount || 1)));
    amount.value = '1';

    const seize = document.createElement('button');
    seize.className = 'seize';
    seize.textContent = 'Apreender';
    seize.addEventListener('click', () => {
      const value = Math.max(1, Math.min(Number(item.amount || 1), Math.floor(Number(amount.value || 1))));
      post('seize', { slot: Number(item.slot), amount: value });
    });

    row.append(slot, name, amount, seize);
    items.appendChild(row);
  });
}

document.getElementById('close').addEventListener('click', close);
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
});

window.addEventListener('message', event => {
  const data = event.data || {};
  if (data.action === 'open') {
    const target = data.target || {};
    identity.textContent = `${target.name || 'Desconhecido'} · ID ${target.userId || 'n/a'}`;
    render(data.items || []);
    app.classList.remove('hidden');
  } else if (data.action === 'items') {
    render(data.items || []);
  } else if (data.action === 'close') {
    app.classList.add('hidden');
  }
});
