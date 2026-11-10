const app = document.querySelector('#app');
const title = document.querySelector('#title');
const context = document.querySelector('#context');
const counter = document.querySelector('#counter');
const totalPrice = document.querySelector('#total-price');
const cardsElement = document.querySelector('#cards');
const viewport = document.querySelector('#viewport');
const backButton = document.querySelector('#back');
const cameraZone = document.querySelector('#camera-zone');
const serviceProgress = document.querySelector('#service-progress');
const serviceLabel = document.querySelector('#service-label');
const serviceFill = document.querySelector('#service-fill');
const colorPicker = document.querySelector('#color-picker');
const colorTitle = document.querySelector('#color-title');
const colorShop = document.querySelector('#color-shop');
const colorPreview = document.querySelector('#color-preview');
const colorNative = document.querySelector('#color-native');
const colorHex = document.querySelector('#color-hex');
const colorPalette = document.querySelector('#color-palette');
const colorNote = document.querySelector('#color-note');
const colorClose = document.querySelector('#color-close');
const colorCancel = document.querySelector('#color-cancel');
const colorApply = document.querySelector('#color-apply');

let data = null;
let view = 'main';
let activeSection = null;
let activeOption = null;
let selectedIndex = 0;
let renderedCards = [];
let changeQueue = Promise.resolve();
let pendingChanges = 0;
let finishing = false;
let colorSelection = null;
let selectedColor = { hex: '#168ED2', index: null };
let ignoreCardClicksUntil = 0;

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_mecanico';
const post = (action, payload = {}) => fetch(`https://${resource}/${action}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload),
});
const focusCamera = payload => post('cameraFocus', payload).catch(() => {});
const updateTotal = () => {
  if (totalPrice) totalPrice.textContent = data?.totalPriceLabel || '$0';
};

const svg = body => `<svg viewBox="0 0 48 48" aria-hidden="true">${body}</svg>`;
const icons = {
  performance: svg('<path d="M8 32a17 17 0 1 1 32 0"/><path d="m24 26 10-9"/><circle cx="24" cy="27" r="3"/><path d="M13 34h22"/>'),
  body: svg('<path d="M7 28h34l-3-9a5 5 0 0 0-5-3H18a6 6 0 0 0-5 3l-3 9"/><path d="M6 28v7h5l2-3h22l2 3h5v-7"/><circle cx="15" cy="29" r="2"/><circle cx="34" cy="29" r="2"/>'),
  wheels: svg('<circle cx="24" cy="24" r="17"/><circle cx="24" cy="24" r="5"/><path d="m24 19-5-9m10 11 9-5m-9 11 7 8m-14-6-7 8m4-14-10-2"/>'),
  visual: svg('<path d="M24 7a17 17 0 1 0 0 34h3a4 4 0 0 0 0-8h-2a3 3 0 0 1 0-6h7a9 9 0 0 0 9-9C41 11 33 7 24 7Z"/><circle cx="15" cy="19" r="2"/><circle cx="21" cy="14" r="2"/><circle cx="29" cy="15" r="2"/>'),
  apply: svg('<path d="M9 25 19 35 40 13"/>'),
  exit: svg('<path d="M21 9h18v30H21"/><path d="M29 24H7m6-6-6 6 6 6"/>'),
  engine: svg('<path d="M8 18h7l4-5h13l4 5h5v17H12V23H8Z"/><path d="M18 21h13v8H18z"/>'),
  brakes: svg('<circle cx="24" cy="24" r="15"/><circle cx="24" cy="24" r="5"/><path d="M36 14v20"/>'),
  transmission: svg('<circle cx="24" cy="24" r="8"/><path d="M24 6v7m0 22v7M6 24h7m22 0h7M11 11l5 5m16 16 5 5m0-26-5 5M16 32l-5 5"/>'),
  suspension: svg('<path d="M8 12h8l-7 6 14 6-14 6 7 6H8m32-24h-8l7 6-14 6 14 6-7 6h8"/>'),
  armor: svg('<path d="M24 6 39 12v11c0 9-6 15-15 19C15 38 9 32 9 23V12Z"/><path d="m17 24 5 5 10-11"/>'),
  turbo: svg('<circle cx="24" cy="24" r="16"/><path d="M24 24c-9-1-11-7-8-12m8 12c1-9 7-11 12-8m-12 8c9 1 11 7 8 12m-8-12c-1 9-7 11-12 8"/><circle cx="24" cy="24" r="3"/>'),
  exhaust: svg('<path d="M7 31h21c5 0 8-3 8-8v-5h6"/><path d="M36 14h6m-6 8h6"/><path d="M7 27v8"/>'),
  window_tint: svg('<path d="M9 34 15 13h22l4 21Z"/><path d="M15 29h22M20 13l-5 16"/>'),
  neon: svg('<path d="M9 28h30l-4-10H16l-4 10"/><path d="M12 33h24"/><path d="M16 38h16"/>'),
  wrench: svg('<path d="M30 9a10 10 0 0 0-11 13L8 33a4 4 0 0 0 6 6l11-11A10 10 0 0 0 38 17l-7 7-6-2-2-6Z"/>'),
};

const optionIcon = key => icons[key]
  || (String(key).startsWith('wheel_') ? icons.wheels : null)
  || (key === 'neon_enabled' ? icons.neon : null)
  || (['primary', 'secondary', 'paint_type_primary', 'paint_type_secondary', 'pearlescent', 'wheel_color', 'livery'].includes(key) ? icons.visual : null)
  || (['spoiler', 'front_bumper', 'rear_bumper', 'side_skirt', 'grille', 'hood', 'roof'].includes(key) ? icons.body : null)
  || icons.wrench;

const knownNativePalette = [
  [0, '#0D1116'], [1, '#1C1D21'], [2, '#32383D'], [3, '#454B4F'], [4, '#999DA0'], [5, '#C2C4C6'],
  [6, '#979A97'], [7, '#637380'], [8, '#63625C'], [9, '#3C3F47'], [10, '#444E54'], [11, '#1D2129'],
  [12, '#13181F'], [13, '#26282A'], [14, '#515554'], [15, '#151921'], [18, '#8C9095'], [20, '#506272'],
  [27, '#C00E1A'], [28, '#DA1918'], [29, '#B6111B'], [30, '#A51E23'], [31, '#7B1A22'], [32, '#8E1B1F'],
  [33, '#6F1818'], [34, '#49111D'], [35, '#B60F25'], [36, '#D44A17'], [37, '#C2944F'], [38, '#F78616'],
  [39, '#CF1F21'], [40, '#732021'], [41, '#F27D20'], [42, '#FFC91F'], [43, '#9C1016'], [44, '#DE0F18'],
  [49, '#132428'], [50, '#122E2B'], [51, '#12383C'], [52, '#31423F'], [53, '#155C2D'], [54, '#1B6770'],
  [55, '#66B81F'], [56, '#22383E'], [57, '#1D5A3F'], [58, '#2D423F'], [59, '#45594B'], [60, '#65867F'],
  [61, '#222E46'], [62, '#233155'], [63, '#304C7E'], [64, '#47578F'], [65, '#637BA7'], [66, '#394762'],
  [67, '#D6E7F1'], [68, '#76AFBE'], [69, '#345E72'], [70, '#0B9CF1'], [71, '#2F2D52'], [72, '#282C4D'],
  [73, '#2354A1'], [74, '#6EA3C6'], [75, '#112552'], [76, '#1B203E'], [77, '#275190'], [78, '#608592'],
  [79, '#2446A8'], [80, '#4271E1'], [81, '#3B39E0'], [82, '#1F2852'], [83, '#253AA7'], [84, '#1C3551'],
  [85, '#4C5F81'], [86, '#58688E'], [87, '#74B5D8'], [88, '#FFCF20'], [89, '#FBE212'], [90, '#916532'],
  [91, '#E0E13D'], [92, '#98D223'], [93, '#9B8C78'], [94, '#503218'], [95, '#473F2B'], [96, '#221B19'],
  [97, '#653F23'], [98, '#775C3E'], [99, '#AC9975'], [100, '#6C6B4B'], [101, '#402E2B'], [102, '#A4965F'],
  [103, '#46231A'], [104, '#752B19'], [105, '#BFAE7B'], [106, '#DFD5B2'], [107, '#F7EDD5'], [111, '#FFFFF6'],
  [112, '#EAEAEA'], [113, '#B0AB94'], [114, '#8E8C84'], [115, '#E7E7E7'], [116, '#989896'], [120, '#5A5752'],
];

function hslToHex(hue, saturation, lightness) {
  const saturationValue = saturation / 100;
  const lightnessValue = lightness / 100;
  const chroma = (1 - Math.abs((2 * lightnessValue) - 1)) * saturationValue;
  const segment = hue / 60;
  const secondary = chroma * (1 - Math.abs((segment % 2) - 1));
  let red = 0, green = 0, blue = 0;
  if (segment < 1) [red, green] = [chroma, secondary];
  else if (segment < 2) [red, green] = [secondary, chroma];
  else if (segment < 3) [green, blue] = [chroma, secondary];
  else if (segment < 4) [green, blue] = [secondary, chroma];
  else if (segment < 5) [red, blue] = [secondary, chroma];
  else [red, blue] = [chroma, secondary];
  const match = lightnessValue - (chroma / 2);
  const channel = value => Math.round((value + match) * 255).toString(16).padStart(2, '0');
  return `#${channel(red)}${channel(green)}${channel(blue)}`.toUpperCase();
}

const nativePalette = Array.from({ length: 160 }, (_, index) => knownNativePalette.find(entry => entry[0] === index)
  || [index, hslToHex((index * 47) % 360, 28 + ((index * 13) % 55), 24 + ((index * 7) % 58))]);

const tonePalette = [
  ...Array.from({ length: 11 }, (_, index) => {
    const channel = Math.round((index / 10) * 255).toString(16).padStart(2, '0');
    return `#${channel}${channel}${channel}`.toUpperCase();
  }),
  ...Array.from({ length: 12 }, (_, hueIndex) => [24, 38, 52, 66, 80].map(lightness => hslToHex(hueIndex * 30, 92, lightness))).flat(),
];

function normalizeHex(value) {
  const match = String(value || '').trim().match(/^#?([0-9a-f]{6})$/i);
  return match ? `#${match[1].toUpperCase()}` : null;
}

function hexToRgb(value) {
  const hex = normalizeHex(value) || '#000000';
  return {
    r: parseInt(hex.slice(1, 3), 16),
    g: parseInt(hex.slice(3, 5), 16),
    b: parseInt(hex.slice(5, 7), 16),
  };
}

function nativeColorByIndex(index) {
  return nativePalette.find(entry => entry[0] === Number(index)) || nativePalette[0];
}

function nearestNativeColor(value) {
  const target = hexToRgb(value);
  return nativePalette.reduce((nearest, entry) => {
    const color = hexToRgb(entry[1]);
    const distance = ((target.r - color.r) ** 2) + ((target.g - color.g) ** 2) + ((target.b - color.b) ** 2);
    return !nearest || distance < nearest.distance ? { entry, distance } : nearest;
  }, null).entry;
}

function optionColorHex(option) {
  const explicit = normalizeHex(option?.colorHex);
  if (explicit) return explicit;
  if (option?.colorIndex !== undefined && option?.colorIndex !== null) return nativeColorByIndex(option.colorIndex)[1];
  return '#168ED2';
}

function updateColorSelection(hex, index = null) {
  const normalized = normalizeHex(hex);
  if (!normalized) return false;
  if (colorSelection?.colorMode === 'indexed') {
    const native = index === null ? nearestNativeColor(normalized) : nativeColorByIndex(index);
    selectedColor = { hex: native[1], index: native[0] };
  } else {
    selectedColor = { hex: normalized, index: null };
  }
  colorNative.value = selectedColor.hex;
  colorHex.value = selectedColor.hex;
  colorPreview.style.backgroundColor = selectedColor.hex;
  colorPalette.querySelectorAll('.tone').forEach(tone => {
    const toneIndex = tone.dataset.index === '' ? null : Number(tone.dataset.index);
    const matches = colorSelection?.colorMode === 'indexed'
      ? toneIndex === selectedColor.index
      : tone.dataset.hex === selectedColor.hex;
    tone.classList.toggle('selected', matches);
  });
  return true;
}

function renderColorPalette() {
  const entries = colorSelection?.colorMode === 'indexed'
    ? nativePalette.map(([index, hex]) => ({ index, hex }))
    : tonePalette.map(hex => ({ index: null, hex }));
  colorPalette.innerHTML = '';
  entries.forEach(entry => {
    const tone = document.createElement('button');
    tone.type = 'button';
    tone.className = 'tone';
    tone.dataset.hex = entry.hex;
    tone.dataset.index = entry.index === null ? '' : String(entry.index);
    tone.style.backgroundColor = entry.hex;
    tone.title = entry.index === null ? entry.hex : `${entry.hex} · GTA ${entry.index}`;
    tone.onclick = () => updateColorSelection(entry.hex, entry.index);
    colorPalette.append(tone);
  });
}

function openColorPicker(option) {
  if (finishing) return;
  focusCamera({ key: option.key });
  colorSelection = option;
  colorShop.textContent = data?.title || 'OB CUSTOMS';
  colorTitle.textContent = option.label;
  colorNote.textContent = option.colorMode === 'indexed'
    ? 'Esta peça usa a tabela original do GTA. Um HEX digitado é aproximado para o tom nativo mais próximo.'
    : 'Escolha um tom da grade ou digite qualquer cor hexadecimal.';
  renderColorPalette();
  updateColorSelection(optionColorHex(option), option.colorMode === 'indexed' ? Number(option.colorIndex) : null);
  colorPicker.classList.remove('hidden');
  app.classList.add('picker-open');
  requestAnimationFrame(() => colorHex.focus());
}

function closeColorPicker() {
  colorPicker.classList.add('hidden');
  app.classList.remove('picker-open');
  colorSelection = null;
}

function sectionSubtitle(section) {
  if (section.id === 'performance') return 'Motor e dirigibilidade';
  if (section.id === 'body') return 'Peças e acabamento externo';
  if (section.id === 'wheels') return 'Famílias e modelos do GTA';
  if (section.id === 'visual') return 'Cores, película e iluminação';
  return `${section.options?.length || 0} opções disponíveis`;
}

function createCard({ id, label, subtitle, icon, tone, swatch, selected, activate }) {
  const card = document.createElement('button');
  card.type = 'button';
  card.className = `menu-card${tone ? ` ${tone}` : ''}${selected ? ' current' : ''}`;
  card.dataset.id = id;
  card.setAttribute('aria-label', label);

  const iconElement = document.createElement('div');
  iconElement.className = 'card-icon';
  iconElement.innerHTML = icon || icons.wrench;
  const copy = document.createElement('div');
  copy.className = 'card-copy';
  const cardLabel = document.createElement('strong');
  cardLabel.textContent = label;
  const cardSubtitle = document.createElement('span');
  cardSubtitle.textContent = subtitle || '';
  copy.append(cardLabel, cardSubtitle);
  card.append(iconElement, copy);

  if (swatch) {
    const swatchElement = document.createElement('i');
    swatchElement.className = 'card-swatch';
    swatchElement.style.backgroundColor = swatch;
    card.append(swatchElement);
  }

  if (selected) {
    const check = document.createElement('b');
    check.className = 'current-check';
    check.textContent = '✓';
    check.setAttribute('aria-label', 'Selecionado');
    card.append(check);
  }

  const entry = { element: card, activate };
  card.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    if (finishing || performance.now() < ignoreCardClicksUntil) return;
    activate();
  });
  card.onmouseenter = () => selectCard(renderedCards.indexOf(entry), false);
  card.onfocus = () => selectCard(renderedCards.indexOf(entry), false);
  card.onkeydown = event => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      event.stopPropagation();
      if (!finishing) activate();
    }
  };
  return entry;
}

function selectCard(index, scroll = true) {
  if (!renderedCards.length) return;
  selectedIndex = Math.max(0, Math.min(renderedCards.length - 1, Number(index) || 0));
  renderedCards.forEach((entry, entryIndex) => entry.element.classList.toggle('selected', entryIndex === selectedIndex));
  counter.textContent = `${selectedIndex + 1}/${renderedCards.length}`;
  if (scroll) {
    const card = renderedCards[selectedIndex].element;
    const target = card.offsetLeft - ((viewport.clientWidth - card.offsetWidth) / 2);
    viewport.scrollTo({ left: Math.max(0, target), behavior: 'smooth' });
  }
}

function mountCards(entries) {
  renderedCards = entries;
  cardsElement.replaceChildren(...entries.map(entry => entry.element));
  viewport.scrollLeft = 0;
  selectCard(Math.min(selectedIndex, Math.max(0, entries.length - 1)), false);
  requestAnimationFrame(() => {
    renderedCards[selectedIndex]?.element.focus({ preventScroll: true });
    selectCard(selectedIndex, true);
  });
}

function renderMain() {
  view = 'main';
  app.classList.remove('list-view');
  activeSection = null;
  activeOption = null;
  selectedIndex = 0;
  context.textContent = 'Menu principal';
  focusCamera({ key: 'overview' });
  backButton.classList.add('concealed');
  viewport.scrollLeft = 0;
  const entries = (data.sections || []).map(section => createCard({
    id: section.id,
    label: section.label,
    subtitle: sectionSubtitle(section),
    icon: icons[section.id] || icons.wrench,
    activate: () => openSection(section.id),
  }));
  entries.push(createCard({
    id: 'apply', label: 'Aplicar', subtitle: 'Salvar todas as alterações', icon: icons.apply, tone: 'confirm', activate: applyTuning,
  }));
  entries.push(createCard({
    id: 'exit', label: 'Sair', subtitle: 'Descartar toda a prévia', icon: icons.exit, tone: 'exit', activate: cancelTuning,
  }));
  mountCards(entries);
}

function renderSection(keepSelection = false) {
  const section = (data.sections || []).find(entry => entry.id === activeSection);
  if (!section) return renderMain();
  view = 'section';
  app.classList.remove('list-view');
  activeOption = null;
  if (!keepSelection) selectedIndex = 0;
  if (!keepSelection) viewport.scrollLeft = 0;
  context.textContent = section.label;
  if (!keepSelection) focusCamera({ section: section.id });
  backButton.classList.remove('concealed');
  const entries = (section.options || []).map(option => {
    const usesPicker = option.colorMode === 'rgb' || option.colorMode === 'indexed';
    const price = Number(option.price) > 0 ? ` · ${option.priceLabel || `$${option.price}`}` : '';
    return createCard({
      id: option.key,
      label: option.label,
      subtitle: usesPicker ? `${option.display} · abrir paleta${price}` : `${option.display} · ver opções${price}`,
      icon: optionIcon(option.key),
      swatch: usesPicker ? optionColorHex(option) : null,
      activate: usesPicker ? () => openColorPicker(option) : () => openChoices(option),
    });
  });
  mountCards(entries);
}

function openSection(id) {
  activeSection = id;
  renderSection(false);
}

async function openChoices(option) {
  if (finishing) return;
  focusCamera({ key: option.key });
  activeOption = option;
  view = 'choices';
  app.classList.remove('list-view');
  app.classList.add('changing');
  context.textContent = option.label;
  backButton.classList.remove('concealed');
  selectedIndex = 0;
  mountCards([createCard({
    id: 'loading', label: 'Carregando peças...', subtitle: 'Consultando este veículo', icon: optionIcon(option.key), activate: () => {},
  })]);
  try {
    const response = await post('choices', { key: option.key });
    const payload = await response.json();
    if (!payload.ok || activeOption?.key !== option.key) return;
    if (data) {
      data.totalPrice = payload.totalPrice;
      data.totalPriceLabel = payload.totalPriceLabel;
      updateTotal();
    }
    renderChoices(payload.choices || [], false);
  } catch (_) {
    renderChoices([], false);
  } finally {
    app.classList.remove('changing');
  }
}

function renderChoices(choices, keepSelection = false) {
  if (!activeOption) return renderSection(false);
  const optionKey = activeOption.key;
  view = 'choices';
  app.classList.remove('list-view');
  context.textContent = activeOption.label;
  backButton.classList.remove('concealed');
  if (!keepSelection) {
    const currentIndex = choices.findIndex(choice => choice.selected === true);
    selectedIndex = currentIndex >= 0 ? currentIndex : 0;
    viewport.scrollLeft = 0;
  }
  const entries = choices.map((choice, index) => createCard({
    id: `${activeOption.key}:${choice.value}`,
    label: choice.label,
    subtitle: choice.selected ? 'Instalado no veículo' : `Opção ${index + 1}${Number(choice.price) > 0 ? ` · ${choice.priceLabel || `$${choice.price}`}` : ''}`,
    icon: optionIcon(activeOption.key),
    selected: choice.selected === true,
    activate: () => selectChoice(optionKey, choice.value),
  }));
  if (!entries.length) {
    entries.push(createCard({
      id: 'empty', label: 'Nenhuma peça disponível', subtitle: 'Este veículo não aceita esta modificação', icon: optionIcon(activeOption.key), activate: () => {},
    }));
  }
  mountCards(entries);
}

function selectChoice(key, value) {
  if (finishing) return;
  const preservedIndex = selectedIndex;
  pendingChanges += 1;
  app.classList.add('changing');
  changeQueue = changeQueue.then(async () => {
    const selectionResponse = await post('selectChoice', { key, value });
    const selection = await selectionResponse.json();
    if (!selection.ok) return;
    const response = await post('state');
    data = await response.json();
    updateTotal();
    selectedIndex = preservedIndex;
    renderChoices(selection.choices || [], true);
  }).catch(() => {}).finally(() => {
    pendingChanges = Math.max(0, pendingChanges - 1);
    if (pendingChanges === 0) app.classList.remove('changing');
  });
}

function applySelectedColor() {
  if (!colorSelection || finishing) return;
  const option = colorSelection;
  const color = selectedColor;
  const rgb = hexToRgb(color.hex);
  const preservedIndex = selectedIndex;
  closeColorPicker();
  pendingChanges += 1;
  app.classList.add('changing');
  changeQueue = changeQueue.then(async () => {
    await post('setColor', { key: option.key, r: rgb.r, g: rgb.g, b: rgb.b, index: color.index });
    const response = await post('state');
    data = await response.json();
    updateTotal();
    selectedIndex = preservedIndex;
    renderSection(true);
  }).catch(() => {}).finally(() => {
    pendingChanges = Math.max(0, pendingChanges - 1);
    if (pendingChanges === 0) app.classList.remove('changing');
  });
}

function applyTuning() {
  finishTuning('apply');
}

function cancelTuning() {
  finishTuning('cancel');
}

function finishTuning(action) {
  if (finishing) return;
  finishing = true;
  app.classList.add('finishing');
  changeQueue.then(async () => {
    if (!data) return;
    const response = await post(action);
    const result = await response.json();
    if (result?.ok === false && data) {
      finishing = false;
      app.classList.remove('finishing');
    }
  }).catch(() => {
    finishing = false;
    app.classList.remove('finishing');
  });
}

function goBack() {
  if (view === 'choices') renderSection(false);
  else if (view === 'section') renderMain();
  else cancelTuning();
}

function setServiceProgress(open, label, duration) {
  if (!open) {
    serviceProgress.classList.add('hidden');
    serviceFill.style.transition = 'none';
    serviceFill.style.width = '0%';
    return;
  }
  serviceLabel.textContent = label || 'Processando...';
  serviceProgress.classList.remove('hidden');
  serviceFill.style.transition = 'none';
  serviceFill.style.width = '0%';
  requestAnimationFrame(() => requestAnimationFrame(() => {
    serviceFill.style.transition = `width ${Math.max(1, Number(duration) || 1)}ms linear`;
    serviceFill.style.width = '100%';
  }));
}

window.addEventListener('message', event => {
  const message = event.data || {};
  if (message.action === 'open') {
    data = message.data || { sections: [] };
    finishing = false;
    pendingChanges = 0;
    changeQueue = Promise.resolve();
    app.classList.remove('hidden', 'finishing', 'changing', 'picker-open', 'list-view');
    closeColorPicker();
    app.dataset.station = data.stationId || '';
    title.textContent = data.title || 'Oficina';
    updateTotal();
    renderMain();
    return;
  }
  if (message.action === 'close') {
    app.classList.add('hidden');
    app.classList.remove('finishing', 'changing');
    closeColorPicker();
    finishing = false;
    data = null;
    renderedCards = [];
    return;
  }
  if (message.action === 'serviceProgress') setServiceProgress(message.open === true, message.label, message.duration);
});

backButton.onclick = goBack;
viewport.addEventListener('wheel', event => {
  if (!data) return;
  event.preventDefault();
  viewport.scrollLeft += event.deltaY || event.deltaX;
}, { passive: false });

let menuDrag = null;
viewport.addEventListener('mousedown', event => {
  if (!data || event.button !== 0) return;
  menuDrag = {
    startX: event.clientX,
    previousX: event.clientX,
    moved: false,
  };
});
window.addEventListener('mousemove', event => {
  if (!menuDrag) return;
  const total = event.clientX - menuDrag.startX;
  if (!menuDrag.moved && Math.abs(total) >= 8) {
    menuDrag.moved = true;
    viewport.classList.add('dragging');
  }
  if (!menuDrag.moved) return;
  event.preventDefault();
  viewport.scrollLeft -= event.clientX - menuDrag.previousX;
  menuDrag.previousX = event.clientX;
});
function finishMenuDrag() {
  if (!menuDrag) return;
  if (menuDrag.moved) ignoreCardClicksUntil = performance.now() + 180;
  menuDrag = null;
  viewport.classList.remove('dragging');
}
window.addEventListener('mouseup', finishMenuDrag);
window.addEventListener('blur', finishMenuDrag);

let cameraDrag = null;
let pendingCameraDelta = { x: 0, y: 0 };
let cameraFrame = 0;
async function flushCameraRotation() {
  cameraFrame = 0;
  const movement = pendingCameraDelta;
  pendingCameraDelta = { x: 0, y: 0 };
  if (movement.x || movement.y) {
    try {
      const response = await post('cameraRotate', movement);
      await response.json();
    } catch (_) {}
  }
}
cameraZone.addEventListener('pointerdown', event => {
  if (!data || event.button !== 0) return;
  cameraDrag = { id: event.pointerId, x: event.clientX, y: event.clientY };
  cameraZone.classList.add('dragging');
  cameraZone.setPointerCapture(event.pointerId);
});
cameraZone.addEventListener('pointermove', event => {
  if (!cameraDrag || cameraDrag.id !== event.pointerId) return;
  pendingCameraDelta.x += event.clientX - cameraDrag.x;
  pendingCameraDelta.y += event.clientY - cameraDrag.y;
  cameraDrag.x = event.clientX;
  cameraDrag.y = event.clientY;
  if (!cameraFrame) cameraFrame = requestAnimationFrame(flushCameraRotation);
});
function finishCameraDrag(event) {
  if (!cameraDrag || cameraDrag.id !== event.pointerId) return;
  cameraDrag = null;
  cameraZone.classList.remove('dragging');
}
cameraZone.addEventListener('pointerup', finishCameraDrag);
cameraZone.addEventListener('pointercancel', finishCameraDrag);
colorClose.onclick = closeColorPicker;
colorCancel.onclick = closeColorPicker;
colorApply.onclick = applySelectedColor;
colorNative.oninput = () => updateColorSelection(colorNative.value);
colorHex.oninput = () => {
  const valid = normalizeHex(colorHex.value);
  colorHex.classList.toggle('invalid', !valid);
  if (valid) updateColorSelection(valid);
};

document.addEventListener('keydown', event => {
  if (!data || app.classList.contains('hidden')) return;
  const key = event.key.toLowerCase();
  if (!colorPicker.classList.contains('hidden')) {
    if (key === 'escape') { event.preventDefault(); closeColorPicker(); }
    else if (key === 'enter') { event.preventDefault(); applySelectedColor(); }
    return;
  }
  if (key === 'escape' || key === 'backspace') {
    event.preventDefault();
    goBack();
    return;
  }
  if (key === 'arrowup' || key === 'arrowleft') {
    event.preventDefault();
    selectCard(selectedIndex - 1);
    return;
  }
  if (key === 'arrowdown' || key === 'arrowright') {
    event.preventDefault();
    selectCard(selectedIndex + 1);
    return;
  }
  if (key === 'enter') {
    event.preventDefault();
    renderedCards[selectedIndex]?.activate?.();
  }
});
