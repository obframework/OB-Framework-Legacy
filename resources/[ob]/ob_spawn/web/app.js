const root = document.getElementById('spawn');
const options = document.getElementById('options');
const markers = document.getElementById('markers');
const selected = document.getElementById('selected');
const confirm = document.getElementById('confirm');
const mapCaption = document.getElementById('map-caption');

// Calibracao deste mapa. As coordenadas deixam de ser porcentagens manuais:
// qualquer novo ponto enviado pelo Lua e projetado automaticamente.
const mapBounds = { west: -4140, east: 4860, north: 8000, south: -4000 };

let selectedOption = null;
let submitting = false;

function mapPosition(coords) {
  if (!coords || !Number.isFinite(Number(coords.x)) || !Number.isFinite(Number(coords.y))) return null;
  const x = (Number(coords.x) - mapBounds.west) / (mapBounds.east - mapBounds.west) * 100;
  const y = (mapBounds.north - Number(coords.y)) / (mapBounds.north - mapBounds.south) * 100;
  return { x: Math.max(2, Math.min(98, x)), y: Math.max(2, Math.min(98, y)) };
}

async function selectSpawn(id) {
  if (submitting) return;
  submitting = true;
  confirm.disabled = true;
  confirm.classList.add('loading');
  confirm.textContent = 'Preparando chegada...';
  try {
    const response = await fetch(`https://${GetParentResourceName()}/selectSpawn`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ id })
    });
    const result = await response.json();
    if (!result?.ok) throw new Error('Local indisponível');
  } catch (_) {
    submitting = false;
    confirm.classList.remove('loading');
    confirm.disabled = !selectedOption;
    confirm.textContent = selectedOption ? `Chegar em ${selectedOption.label}` : 'Confirmar local';
  }
}

function choose(option) {
  selectedOption = option;
  selected.classList.remove('empty');
  selected.innerHTML = `<span class="selected-icon">✓</span><div><small>LOCAL ESCOLHIDO</small><strong></strong><p></p></div>`;
  selected.querySelector('strong').textContent = option.label;
  selected.querySelector('p').textContent = option.description || 'Ponto de chegada selecionado';
  confirm.disabled = false;
  confirm.textContent = `Chegar em ${option.label}`;
  mapCaption.lastElementChild.textContent = `${option.label} selecionado`;

  document.querySelectorAll('.option, .marker').forEach((element) => {
    const active = element.dataset.id === option.id;
    element.classList.toggle('active', active);
    element.setAttribute('aria-pressed', String(active));
  });
}

function createOption(option) {
  const button = document.createElement('button');
  button.className = 'option';
  button.dataset.id = option.id;

  const title = document.createElement('strong');
  title.textContent = option.label;
  const description = document.createElement('small');
  description.textContent = option.description || '';
  const check = document.createElement('span');
  check.className = 'option-check';
  check.textContent = '✓';
  const copy = document.createElement('span');
  copy.className = 'option-copy';
  copy.append(title, description);
  button.append(copy, check);
  button.addEventListener('click', () => choose(option));
  button.addEventListener('dblclick', () => { choose(option); selectSpawn(option.id); });
  return button;
}

function createMarker(option, position) {
  const button = document.createElement('button');
  button.className = 'marker';
  button.dataset.id = option.id;
  button.style.left = `${position.x}%`;
  button.style.top = `${position.y}%`;
  button.setAttribute('aria-label', option.label);
  button.setAttribute('aria-pressed', 'false');
  button.title = option.label;
  button.innerHTML = '<span class="marker-radar"></span><i></i><b></b><em></em>';
  button.querySelector('em').textContent = option.isLast ? 'Última localização' : option.label;
  button.addEventListener('click', () => choose(option));
  button.addEventListener('dblclick', () => { choose(option); selectSpawn(option.id); });
  markers.appendChild(button);
}

confirm.addEventListener('click', () => {
  if (selectedOption) selectSpawn(selectedOption.id);
});

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'close') {
    root.classList.add('hidden');
    options.replaceChildren();
    markers.replaceChildren();
    selectedOption = null;
    submitting = false;
    selected.className = 'selected empty';
    selected.innerHTML = '<span class="selected-icon">⌖</span><div><small>LOCAL ESCOLHIDO</small><strong>Selecione um ponto</strong><p>Use o mapa ou a lista abaixo</p></div>';
    mapCaption.lastElementChild.textContent = 'Selecione um marcador no mapa';
    confirm.classList.remove('loading');
    confirm.textContent = 'Confirmar local';
    confirm.disabled = true;
    return;
  }
  if (data.action !== 'open') return;

  options.replaceChildren();
  markers.replaceChildren();
  selectedOption = null;
  submitting = false;
  selected.className = 'selected empty';
  selected.innerHTML = '<span class="selected-icon">⌖</span><div><small>LOCAL ESCOLHIDO</small><strong>Selecione um ponto</strong><p>Use o mapa ou a lista abaixo</p></div>';
  mapCaption.lastElementChild.textContent = 'Selecione um marcador no mapa';
  confirm.classList.remove('loading');
  confirm.textContent = 'Confirmar local';
  confirm.disabled = true;

  for (const option of data.options || []) {
    options.appendChild(createOption(option));
    const position = mapPosition(option.coords);
    if (position) createMarker(option, position);
  }
  root.classList.remove('hidden');
  const initial = (data.options || [])[0];
  if (initial) choose(initial);
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && selectedOption && !root.classList.contains('hidden')) selectSpawn(selectedOption.id);
});
