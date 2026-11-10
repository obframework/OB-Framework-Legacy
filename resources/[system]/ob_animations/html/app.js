const app = document.getElementById('app');
const list = document.getElementById('emotes');
const search = document.getElementById('search');
const category = document.getElementById('category');
let emotes = [];

const resource = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'ob_animations';

function post(event, data) {
  return fetch('https://' + resource + '/' + event, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  });
}

function categories() {
  return Array.from(new Set(emotes.map(function (entry) {
    return String(entry.category || 'Outros');
  }))).sort();
}

function renderCategories() {
  const current = category.value;
  category.innerHTML = '';
  const all = document.createElement('option');
  all.value = '';
  all.textContent = 'Todas as categorias';
  category.appendChild(all);
  categories().forEach(function (name) {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name;
    category.appendChild(option);
  });
  if (Array.from(category.options).some(function (option) { return option.value === current; })) {
    category.value = current;
  }
}

function render() {
  const term = search.value.trim().toLocaleLowerCase('pt-BR');
  const selectedCategory = category.value;
  const filtered = emotes.filter(function (entry) {
    const matchesText = !term || String(entry.label || entry.id || '').toLocaleLowerCase('pt-BR').includes(term);
    const matchesCategory = !selectedCategory || String(entry.category || 'Outros') === selectedCategory;
    return matchesText && matchesCategory;
  });

  list.innerHTML = '';
  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'Nenhuma animação encontrada.';
    list.appendChild(empty);
    return;
  }
  filtered.forEach(function (entry) {
    const button = document.createElement('button');
    const title = document.createElement('b');
    const group = document.createElement('small');
    button.type = 'button';
    button.className = 'emote';
    title.textContent = entry.label || entry.id;
    group.textContent = entry.category || 'Outros';
    button.appendChild(title);
    button.appendChild(group);
    button.addEventListener('click', function () { post('play', { id: entry.id }); });
    list.appendChild(button);
  });
}

document.getElementById('close').addEventListener('click', function () { post('close'); });
document.getElementById('stop').addEventListener('click', function () { post('stop'); });
search.addEventListener('input', render);
category.addEventListener('change', render);
window.addEventListener('keyup', function (event) {
  if (event.key === 'Escape') post('close');
});
window.addEventListener('message', function (event) {
  const data = event.data;
  if (!data) return;
  if (data.action === 'open') {
    emotes = Array.isArray(data.emotes) ? data.emotes : [];
    search.value = '';
    renderCategories();
    render();
    app.classList.remove('hidden');
  } else if (data.action === 'close') {
    app.classList.add('hidden');
  }
});
