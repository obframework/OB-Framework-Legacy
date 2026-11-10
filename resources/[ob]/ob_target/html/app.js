const target = document.getElementById('target');
const indicator = document.getElementById('indicator');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_target';

// Os recursos podem enviar classes Font Awesome, mas o NUI do target nao
// importa essa fonte. Nunca exiba o nome da classe como texto na tela.
const fontAwesomeIcons = {
  'fa-taxi': 'T',
  'fa-bus': 'B',
  'fa-bus-simple': 'B',
  'fa-recycle': '♻',
  'fa-truck': '▰',
  'fa-tree': '◆',
  'fa-cow': '◉',
  'fa-industry': '▣',
  'fa-box': '□',
  'fa-boxes-stacked': '▣',
  'fa-box-open': '□',
  'fa-truck-ramp-box': '▰',
  'fa-warehouse': '▣',
};

const displayIcon = (value) => {
  if (typeof value !== 'string' || !value.trim()) return '+';
  if (!value.includes('fa-')) return value;

  for (const [className, symbol] of Object.entries(fontAwesomeIcons)) {
    if (value.includes(className)) return symbol;
  }

  return '+';
};

const post = (event, data = {}) => fetch(`https://${resource}/${event}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(data),
});

target.addEventListener('click', e => {
  const button = e.target.closest('[data-option]');
  if (button) post('select', {id: button.dataset.option});
});
window.addEventListener('keyup', (event) => {
  if (event.key === 'Escape') post('close');
});

window.addEventListener('message', ({ data }) => {
  if (!data) return;
  if (data.action === 'show') {
    target.replaceChildren();
    for (const option of data.options || [data]) {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'target-option'; button.dataset.option = option.id || '';
      const icon = document.createElement('div'); icon.className = 'icon'; icon.textContent = displayIcon(option.icon);
      const copy = document.createElement('div'); copy.className = 'copy';
      const caption = document.createElement('small'); caption.textContent = 'OPCAO';
      const label = document.createElement('strong'); label.textContent = option.label || 'Interagir';
      copy.append(caption,label); button.append(icon,copy); target.append(button);
    }
    target.classList.remove('hidden');
  }
  if (data.action === 'hide') target.classList.add('hidden');
  if (data.action === 'indicator') {
    indicator.classList.toggle('hidden', !data.visible);
    indicator.classList.toggle('active', data.active === true);
  }
});
