const app = document.getElementById('app');
const sectionsEl = document.getElementById('sections');
const categoriesEl = document.getElementById('categories');
const itemsEl = document.getElementById('items');
const titleEl = document.getElementById('title');
const pageInfo = document.getElementById('pageInfo');
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

const btnSave = document.getElementById('btnSave');
const btnCancel = document.getElementById('btnCancel');
const btnPrev = document.getElementById('btnPrev');
const btnNext = document.getElementById('btnNext');
const btnRotateLeft = document.getElementById('btnRotateLeft');
const btnRotateRight = document.getElementById('btnRotateRight');
const btnZoomIn = document.getElementById('btnZoomIn');
const btnZoomOut = document.getElementById('btnZoomOut');
const totalPriceEl = document.getElementById('totalPrice');
const btnBack = document.getElementById('btnBack');
const categoryBar = document.getElementById('categoryBar');
const categoryTitle = document.getElementById('categoryTitle');
const adjustBar = document.getElementById('adjustBar');
const textureBlock = document.getElementById('textureBlock');
const colorBlock = document.getElementById('colorBlock');
const textureValue = document.getElementById('textureValue');
const colorValue = document.getElementById('colorValue');
const btnTexPrev = document.getElementById('btnTexPrev');
const btnTexNext = document.getElementById('btnTexNext');
const btnColorPrev = document.getElementById('btnColorPrev');
const btnColorNext = document.getElementById('btnColorNext');
const mainContent = document.getElementById('mainContent');
const mainFooter = document.getElementById('mainFooter');
const creatorSteps = document.getElementById('creatorSteps');
const creatorPanels = document.getElementById('creatorPanels');
const creatorIdentity = document.getElementById('creatorIdentity');
const creatorParents = document.getElementById('creatorParents');
const creatorFace = document.getElementById('creatorFace');
const faceList = document.getElementById('faceList');
const identityFirst = document.getElementById('identityFirst');
const identityLast = document.getElementById('identityLast');
const identityNation = document.getElementById('identityNation');
const identityGender = document.getElementById('identityGender');
const identityBirth = document.getElementById('identityBirth');
const btnIdentityNext = document.getElementById('btnIdentityNext');
const motherPreview = document.getElementById('motherPreview');
const fatherPreview = document.getElementById('fatherPreview');
const btnSelectMother = document.getElementById('btnSelectMother');
const btnSelectFather = document.getElementById('btnSelectFather');
const blendRange = document.getElementById('blendRange');
const blendValue = document.getElementById('blendValue');
const parentModal = document.getElementById('parentModal');
const parentModalTitle = document.getElementById('parentModalTitle');
const parentModalClose = document.getElementById('parentModalClose');
const parentGrid = document.getElementById('parentGrid');
const confirmModal = document.getElementById('confirmModal');
const confirmTitle = document.getElementById('confirmTitle');
const confirmBody = document.getElementById('confirmBody');
const confirmYes = document.getElementById('confirmYes');
const confirmNo = document.getElementById('confirmNo');
const alertModal = document.getElementById('alertModal');
const alertTitle = document.getElementById('alertTitle');
const alertBody = document.getElementById('alertBody');
const alertOk = document.getElementById('alertOk');

let uiData = null;
let activeSectionId = null;
let activeCategoryId = null;
let currentPage = 1;
let totalPages = 1;
let categoriesPage = 1;
let categoriesTotalPages = 1;
let categoriesList = [];
const CATEGORIES_PER_PAGE = 9;
let selectedItemId = null;
let imageBaseUrl = '';
let allowedSections = null;
let activeCategoryFocus = null;
let viewMode = 'categories';
let imageProxyEnabled = false;
let uiOptions = { saveLabel: 'Comprar', cancelLabel: 'Cancelar', showTotal: true };
let creatorMode = false;
let creatorStep = 'parents';
let identityDone = false;
let identityData = null;
let parentsData = { mothers: [], fathers: [] };
let selectedMother = 0;
let selectedFather = 0;
let shapeMix = 0.5;
let skinMix = 0.5;
let faceFeatures = {};
let faceLabels = [];
let parentTarget = 'mother';
let validationConfig = {};
let pendingConfirmData = null;

const resource = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'ob_creator';

function postNui(action, data = {}) {
  return fetch(`https://${resource}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  })
    .then((res) => res.json().catch(() => ({})))
    .catch(() => ({}));
}

function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
}

function normalizeBase(base) {
  if (!base) return '';
  const clean = String(base).trim();
  if (!clean) return '';
  return clean.endsWith('/') ? clean : `${clean}/`;
}

function resolveImg(path, kind) {
  if (!path) return '';
  if (/^https?:\/\//i.test(path)) return path;
  const base = normalizeBase(imageBaseUrl);
  const baseIsRemote = /^https?:\/\//i.test(base);
  if (path.startsWith('nui://')) {
    if (!base || !baseIsRemote) return path;
    return path.replace(/^nui:\/\/[^/]+\//, base);
  }
  if (base) return base + path.replace(/^\//, '');
  return path;
}

function normalizeNameKey(value) {
  if (!value) return '';
  let key = String(value).trim().toLowerCase();
  if (key.normalize) {
    key = key.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }
  return key.replace(/\s+/g, '');
}

function isBlacklisted(value, list) {
  if (!value || !Array.isArray(list) || list.length === 0) return false;
  const key = normalizeNameKey(value);
  return list.some((item) => normalizeNameKey(item) === key);
}

function parseBirthdate(value) {
  if (!value) return null;
  const text = String(value).trim();
  let match = text.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  let day, month, year;
  if (match) {
    day = Number(match[1]);
    month = Number(match[2]);
    year = Number(match[3]);
  } else {
    match = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!match) return null;
    year = Number(match[1]);
    month = Number(match[2]);
    day = Number(match[3]);
  }
  if (!year || !month || !day) return null;
  return { year, month, day };
}

function calculateAge(dateParts) {
  if (!dateParts) return null;
  const today = new Date();
  let age = today.getFullYear() - dateParts.year;
  const m = today.getMonth() + 1;
  const d = today.getDate();
  if (m < dateParts.month || (m === dateParts.month && d < dateParts.day)) {
    age -= 1;
  }
  return age;
}

function formatBirthdate(value) {
  const parts = parseBirthdate(value);
  if (!parts) return value || '';
  const dd = String(parts.day).padStart(2, '0');
  const mm = String(parts.month).padStart(2, '0');
  return `${dd}/${mm}/${parts.year}`;
}

function toIsoDate(parts) {
  if (!parts) return '';
  const dd = String(parts.day).padStart(2, '0');
  const mm = String(parts.month).padStart(2, '0');
  return `${parts.year}-${mm}-${dd}`;
}

function setImageSrc(img, path, kind) {
  const src = resolveImg(path, kind);
  if (!src) return;
  img.src = src;
  img.onerror = () => postNui('img_error', { src: img.src, kind });
}

function setView(mode) {
  viewMode = mode;
  const showCategories = mode === 'categories';
  app.classList.toggle('view-categories', showCategories);
  categoriesEl.classList.toggle('hidden', !showCategories);
  itemsEl.classList.toggle('hidden', showCategories);
  categoryBar.classList.toggle('hidden', showCategories);
  adjustBar.classList.toggle('hidden', showCategories);
  updatePager();
}

function setCreatorMode(enabled) {
  creatorMode = enabled;
  app.classList.toggle('creator-mode', enabled);
  if (!enabled) app.classList.remove('creator-face');
  if (creatorSteps) creatorSteps.classList.toggle('hidden', !enabled);
  if (creatorPanels) creatorPanels.classList.toggle('hidden', !enabled);
  if (!enabled) {
    if (mainContent) mainContent.classList.remove('hidden');
    if (mainFooter) mainFooter.classList.remove('hidden');
    setView('categories');
    return;
  }
  identityDone = true;
  if (creatorSteps) creatorSteps.querySelector('[data-step="identity"]')?.classList.toggle('hidden', uiOptions.mode === 'appearance');
  setCreatorStep(uiOptions.mode === 'appearance' ? 'parents' : 'identity');
}

function setCreatorStep(step) {
  if (uiOptions.mode === 'appearance' && step === 'identity') step = 'parents';
  creatorStep = step;
  app.classList.toggle('creator-face', creatorMode && step === 'face');
  if (creatorSteps) {
    creatorSteps.querySelectorAll('.step').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.step === step);
    });
  }
  const showDetails = step === 'details';
  if (mainContent) mainContent.classList.toggle('hidden', !showDetails);
  if (creatorIdentity) creatorIdentity.classList.toggle('hidden', step !== 'identity');
  if (creatorParents) creatorParents.classList.toggle('hidden', step !== 'parents');
  if (creatorFace) creatorFace.classList.toggle('hidden', step !== 'face');
  if (showDetails) {
    setView('categories');
  }

  if (creatorMode) {
    const focusMap = {
      identity: 'head',
      parents: 'head',
      face: 'head',
      details: 'full'
    };
    postNui('focus', { focus: focusMap[step] || 'full' });
  }
}

function updateBlendDisplay() {
  if (blendValue) blendValue.textContent = `${Math.round(shapeMix * 100)}%`;
  if (blendRange) blendRange.value = Math.round(shapeMix * 100);
}

function updateParentPreviews() {
  if (motherPreview) setImageSrc(motherPreview, `nui://${resource}/creator/parents/${selectedMother}.png`, 'parent');
  if (fatherPreview) setImageSrc(fatherPreview, `nui://${resource}/creator/parents/${selectedFather}.png`, 'parent');
}

function openParentModal(target) {
  parentTarget = target;
  if (parentModalTitle) {
    parentModalTitle.textContent = target === 'mother' ? 'Selecionar Mae' : 'Selecionar Pai';
  }
  renderParentGrid();
  parentModal.classList.remove('hidden');
}

function closeParentModal() {
  parentModal.classList.add('hidden');
}

function showAlert(message, title) {
  if (!alertModal || !alertBody) return;
  alertTitle.textContent = title || (validationConfig.messages && validationConfig.messages.alertTitle) || 'Aviso';
  alertBody.textContent = message || '';
  alertModal.classList.remove('hidden');
}

function closeAlert() {
  if (alertModal) alertModal.classList.add('hidden');
}

function showConfirm(data) {
  if (!confirmModal || !confirmBody) return;
  const messages = validationConfig.messages || {};
  confirmTitle.textContent = messages.confirmTitle || 'Confirmar cadastro';
  if (confirmYes) confirmYes.textContent = messages.confirmYes || 'Sim';
  if (confirmNo) confirmNo.textContent = messages.confirmNo || 'Nao';

  confirmBody.innerHTML = '';
  const subtitle = document.createElement('div');
  subtitle.className = 'muted';
  subtitle.textContent = messages.confirmBody || 'Confirma os dados abaixo?';
  confirmBody.appendChild(subtitle);

  const nameLine = document.createElement('div');
  nameLine.textContent = `Nome: ${data.firstname} ${data.lastname}`;
  confirmBody.appendChild(nameLine);

  if (data.nationality) {
    const natLine = document.createElement('div');
    natLine.textContent = `Nacionalidade: ${data.nationality}`;
    confirmBody.appendChild(natLine);
  }

  if (data.gender) {
    const genderLine = document.createElement('div');
    genderLine.textContent = `Genero: ${data.gender === 'female' ? 'Feminino' : 'Masculino'}`;
    confirmBody.appendChild(genderLine);
  }

  if (data.birthdate) {
    const birthLine = document.createElement('div');
    birthLine.textContent = `Nascimento: ${formatBirthdate(data.birthdate)}`;
    confirmBody.appendChild(birthLine);
  }

  pendingConfirmData = JSON.parse(JSON.stringify(data || {}));
  if (confirmYes) confirmYes.disabled = false;
  confirmModal.classList.remove('hidden');
}

function closeConfirm() {
  if (confirmModal) confirmModal.classList.add('hidden');
  pendingConfirmData = null;
  if (confirmYes) confirmYes.disabled = false;
}

function validateIdentity(data) {
  const cfg = validationConfig || {};
  const messages = cfg.messages || {};
  const first = (data.firstname || '').trim();
  const last = (data.lastname || '').trim();
  const birth = (data.birthdate || '').trim();

  if ((cfg.requireName !== false && first === '') || (cfg.requireSurname !== false && last === '')) {
    return { ok: false, message: messages.missingName || 'Preencha nome e sobrenome.' };
  }

  if (cfg.requireBirthdate !== false && birth === '') {
    return { ok: false, message: messages.missingBirthdate || 'Informe a data de nascimento.' };
  }

  if (isBlacklisted(first, cfg.blacklist && cfg.blacklist.names)
      || isBlacklisted(last, cfg.blacklist && cfg.blacklist.surnames)) {
    return { ok: false, message: messages.blacklisted || 'Nome ou sobrenome nao permitido.' };
  }

  const minAge = Number(cfg.minAge || 0);
  if (minAge > 0 && birth) {
    const parts = parseBirthdate(birth);
    if (!parts) {
      return { ok: false, message: messages.invalidBirthdate || 'Data de nascimento invalida.' };
    }
    const age = calculateAge(parts);
    if (age === null || age < minAge) {
      return { ok: false, message: messages.underage || 'Voce precisa ter 18 anos ou mais.' };
    }
  }

  return { ok: true };
}

function collectIdentityData() {
  return {
    firstname: identityFirst ? identityFirst.value.trim() : '',
    lastname: identityLast ? identityLast.value.trim() : '',
    nationality: identityNation ? identityNation.value.trim() : '',
    gender: identityGender ? identityGender.value : 'male',
    birthdate: identityBirth ? identityBirth.value.trim() : ''
  };
}

function renderParentGrid() {
  if (!parentGrid) return;
  clear(parentGrid);
  const list = parentTarget === 'mother' ? parentsData.mothers : parentsData.fathers;
  const selected = parentTarget === 'mother' ? selectedMother : selectedFather;
  list.forEach((id) => {
    const card = document.createElement('div');
    card.className = 'modal-card';
    if (id === selected) card.classList.add('selected');

    const img = document.createElement('img');
    img.alt = '';
    img.referrerPolicy = 'no-referrer';
    img.crossOrigin = 'anonymous';
    setImageSrc(img, `nui://${resource}/creator/parents/${id}.png`, 'parent');
    card.appendChild(img);

    card.addEventListener('click', () => {
      if (parentTarget === 'mother') {
        selectedMother = id;
      } else {
        selectedFather = id;
      }
      updateParentPreviews();
      postNui('creatob_set_parents', { mother: selectedMother, father: selectedFather, shapeMix, skinMix });
      renderParentGrid();
    });
    parentGrid.appendChild(card);
  });
}

function renderFaceList() {
  if (!faceList) return;
  clear(faceList);
  faceLabels.forEach((item) => {
    const row = document.createElement('div');
    row.className = 'face-row';
    const label = document.createElement('div');
    label.className = 'face-label';
    label.textContent = item.label || item.id;
    row.appendChild(label);

    const range = document.createElement('input');
    range.type = 'range';
    range.min = -1;
    range.max = 1;
    range.step = 0.1;
    range.value = faceFeatures[item.id] ?? 0;
    row.appendChild(range);

    const value = document.createElement('div');
    value.className = 'face-value';
    value.textContent = Number(range.value).toFixed(1);
    row.appendChild(value);

    range.addEventListener('input', () => {
      const val = Number(range.value);
      faceFeatures[item.id] = val;
      value.textContent = val.toFixed(1);
      postNui('creatob_set_face_feature', { feature: item.id, value: val });
    });

    faceList.appendChild(row);
  });
}

function setActiveSection(sectionId) {
  activeSectionId = sectionId;
  selectedItemId = null;

  const section = uiData.sections.find(s => s.id === sectionId);
  renderCategories(section);
  setView('categories');

  Array.from(sectionsEl.children).forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.id === sectionId);
  });
}

function setActiveCategory(categoryId) {
  activeCategoryId = categoryId;
  selectedItemId = null;
  currentPage = 1;

  Array.from(categoriesEl.children).forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.id === categoryId);
  });

  const section = uiData.sections.find(s => s.id === activeSectionId);
  const category = section.categories.find(c => c.id === categoryId);
  activeCategoryFocus = category && category.focus ? category.focus : null;
  if (categoryTitle) categoryTitle.textContent = category ? category.label : '';
  if (textureBlock) textureBlock.classList.add('hidden');
  if (colorBlock) colorBlock.classList.add('hidden');

  if (activeCategoryFocus) {
    postNui('focus', { focus: activeCategoryFocus });
  }

  loadItems(true);
  setView('items');
}

function renderSections(data) {
  clear(sectionsEl);
  const sectionsToRender = allowedSections
    ? data.sections.filter(s => allowedSections.includes(s.id))
    : data.sections;

  sectionsToRender.forEach((section) => {
    const btn = document.createElement('div');
    btn.className = 'section';
    btn.dataset.id = section.id;
    btn.textContent = section.label;
    btn.addEventListener('click', () => setActiveSection(section.id));
    sectionsEl.appendChild(btn);
  });

  app.classList.toggle('single-section', sectionsToRender.length <= 1);
  if (sectionsToRender.length === 1) {
    sectionsEl.style.display = 'none';
  } else {
    sectionsEl.style.display = '';
  }
}

function renderCategories(section) {
  categoriesList = section && Array.isArray(section.categories) ? section.categories : [];
  categoriesTotalPages = Math.max(1, Math.ceil(categoriesList.length / CATEGORIES_PER_PAGE));
  categoriesPage = 1;
  renderCategoriesPage(true);
}

function renderCategoriesPage(autoSelect = false) {
  clear(categoriesEl);
  const start = (categoriesPage - 1) * CATEGORIES_PER_PAGE;
  const pageItems = categoriesList.slice(start, start + CATEGORIES_PER_PAGE);

  pageItems.forEach((category) => {
    const btn = document.createElement('div');
    btn.className = 'category';
    btn.dataset.id = category.id;

    if (category.icon) {
      const img = document.createElement('img');
      img.alt = '';
      img.referrerPolicy = 'no-referrer';
      img.crossOrigin = 'anonymous';
      img.onerror = () => { img.remove(); postNui('img_error', { src: img.src, kind: 'category' }); };
      setImageSrc(img, category.icon, 'category');
      btn.appendChild(img);
    }

    const label = document.createElement('span');
    label.textContent = category.label;
    btn.appendChild(label);

    btn.addEventListener('click', () => setActiveCategory(category.id));
    categoriesEl.appendChild(btn);
  });

  if (autoSelect && pageItems.length > 0) {
    activeCategoryId = pageItems[0].id;
    const section = uiData.sections.find(s => s.id === activeSectionId);
    const category = section && section.categories.find(c => c.id === activeCategoryId);
    activeCategoryFocus = category && category.focus ? category.focus : null;
    loadItems(true);
  }
  updatePager();
}

function renderItems(items, selectedId) {
  clear(itemsEl);
  let selectedEl = null;

  items.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'card';
    card.dataset.id = item.id;

    if (item.none) {
      card.classList.add('none');
    }

    if (item.img) {
      const img = document.createElement('img');
      img.alt = '';
      img.referrerPolicy = 'no-referrer';
      img.crossOrigin = 'anonymous';
      img.onerror = () => { img.remove(); postNui('img_error', { src: img.src, kind: 'item' }); };
      setImageSrc(img, item.img, 'item');
      card.appendChild(img);
    }

    const label = document.createElement('div');
    label.className = 'label';
    label.textContent = item.label || '';
    card.appendChild(label);

    card.addEventListener('click', () => {
      selectedItemId = item.id;

      if (activeCategoryFocus) {
        postNui('focus', { focus: activeCategoryFocus });
      }

      postNui('select_item', {
        sectionId: activeSectionId,
        categoryId: activeCategoryId,
        item: item
      });

      Array.from(itemsEl.children).forEach((el) => {
        el.classList.toggle('selected', el.dataset.id === item.id);
      });
    });

    itemsEl.appendChild(card);
    if (selectedId && String(item.id) === String(selectedId)) {
      card.classList.add('selected');
      selectedEl = card;
    }
  });

  if (selectedEl) {
    requestAnimationFrame(() => {
      selectedEl.scrollIntoView({ block: 'center' });
    });
  }
}

async function loadItems(autoSelect = false) {
  if (!activeSectionId || !activeCategoryId) return;

  const data = await postNui('get_items', {
    sectionId: activeSectionId,
    categoryId: activeCategoryId,
    page: autoSelect ? 0 : currentPage,
    perPage: 60,
    autoSelect
  });

  totalPages = data.totalPages || 1;
  currentPage = data.page || 1;

  selectedItemId = data.selectedId || selectedItemId;
  renderItems(data.items || [], selectedItemId);
  updatePager();
}

function updatePager() {
  const pager = document.getElementById('pager');
  if (!pager) return;

  if (viewMode === 'categories') {
    const show = categoriesTotalPages > 1;
    pager.classList.toggle('hidden', !show);
    if (show) pageInfo.textContent = `Categorias ${categoriesPage} / ${categoriesTotalPages}`;
    return;
  }

  const show = totalPages > 1;
  pager.classList.toggle('hidden', !show);
  if (show) pageInfo.textContent = `Pagina ${currentPage} / ${totalPages}`;
}

function openUi(data, defaultSection, baseUrl, sectionsAllowed, titleOverride, proxyEnabled, options) {
  uiData = data;
  imageBaseUrl = baseUrl || '';
  imageProxyEnabled = !!proxyEnabled;
  allowedSections = sectionsAllowed || null;
  uiOptions = Object.assign({ saveLabel: 'Comprar', cancelLabel: 'Cancelar', showTotal: true }, options || {});
  validationConfig = uiOptions.validation || {};
  if (btnSave) btnSave.textContent = uiOptions.saveLabel || 'Comprar';
  if (btnCancel) btnCancel.textContent = uiOptions.cancelLabel || 'Cancelar';
  if (btnCancel) btnCancel.classList.toggle('hidden', uiOptions.mode === 'creator');
  if (totalPriceEl) totalPriceEl.classList.toggle('hidden', uiOptions.showTotal === false);
  setCreatorMode(uiOptions.mode === 'creator' || uiOptions.mode === 'appearance');
  app.classList.toggle('store-mode', uiOptions.mode === 'store');
  titleEl.textContent = titleOverride || data.title || 'Orbis Creator';
  document.body.tabIndex = 0;
  document.body.focus();
  window.focus();
  postNui('ui_debug', { baseUrl: imageBaseUrl, proxy: imageProxyEnabled });
  renderSections(data);
  if (defaultSection) {
    const exists = data.sections.find(s => s.id === defaultSection);
    if (exists) {
      setActiveSection(defaultSection);
    } else if (data.sections.length > 0) {
      setActiveSection(data.sections[0].id);
    }
  } else if (data.sections.length > 0) {
    setActiveSection(data.sections[0].id);
  }
  app.classList.remove('hidden');
  document.body.classList.add('open');
  setView('categories');
}

function closeUi() {
  app.classList.add('hidden');
  clear(sectionsEl);
  clear(categoriesEl);
  clear(itemsEl);
  uiData = null;
  activeCategoryFocus = null;
  if (totalPriceEl) totalPriceEl.textContent = `Total: ${money(0)}`;
  if (parentModal) parentModal.classList.add('hidden');
  closeConfirm();
  closeAlert();
  setCreatorMode(false);
  app.classList.remove('store-mode');
  document.body.classList.remove('open');
}

window.addEventListener('message', (event) => {
  const { action, data, defaultSection, imageBaseUrl: baseUrl, allowedSections: sectionsAllowed, titleOverride, imageProxyEnabled: proxyEnabled, uiOptions: options } = event.data || {};
  if (action === 'open') {
    openUi(data, defaultSection, baseUrl, sectionsAllowed, titleOverride, proxyEnabled, options);
  }
  if (action === 'close') {
    closeUi();
  }
  if (action === 'cart_update' && totalPriceEl) {
    totalPriceEl.textContent = `Total: ${money(event.data.total || 0)}`;
  }
  if (action === 'texture_update') {
    const enabled = !!event.data.enabled;
    textureBlock.classList.toggle('hidden', !enabled);
    if (enabled) {
      const current = event.data.current || 0;
      const max = event.data.max || 1;
      textureValue.textContent = `${current + 1}/${max}`;
    }
  }
  if (action === 'colob_update') {
    const enabled = !!event.data.enabled;
    colorBlock.classList.toggle('hidden', !enabled);
    if (enabled) {
      const current = event.data.current || 0;
      const max = event.data.max || 1;
      colorValue.textContent = `${current + 1}/${max}`;
    }
  }
  if (action === 'creatob_init') {
    parentsData = event.data.parents || { mothers: [], fathers: [] };
    selectedMother = event.data.selected?.mother ?? 0;
    selectedFather = event.data.selected?.father ?? 0;
    shapeMix = typeof event.data.shapeMix === 'number' ? event.data.shapeMix : 0.5;
    skinMix = typeof event.data.skinMix === 'number' ? event.data.skinMix : shapeMix;
    faceFeatures = event.data.faceFeatures || {};
    faceLabels = event.data.faceLabels || [];
    identityData = event.data.identity || null;
    if (identityData && identityFirst) identityFirst.value = identityData.firstname || '';
    if (identityData && identityLast) identityLast.value = identityData.lastname || '';
    if (identityData && identityNation) identityNation.value = identityData.nationality || '';
    if (identityData && identityBirth) {
      const parts = parseBirthdate(identityData.birthdate || '');
      identityBirth.value = parts ? toIsoDate(parts) : '';
    }
    if (identityData && identityGender) identityGender.value = identityData.gender || 'male';
    updateParentPreviews();
    updateBlendDisplay();
    renderFaceList();
  }
});

btnSave.addEventListener('click', () => {
  if (creatorMode && uiOptions.mode !== 'appearance') {
    const data = collectIdentityData();
    const validation = validateIdentity(data);
    if (!validation.ok) {
      showAlert(validation.message);
      return;
    }
    showConfirm(data);
    return;
  }
  postNui('save');
});
btnCancel.addEventListener('click', () => {
  if (uiOptions.mode === 'appearance') { postNui('cancel'); return; }
  if (creatorMode && uiOptions.mode !== 'appearance') {
    return;
  }
  closeUi();
  postNui('cancel');
  postNui('close');
});
btnPrev.addEventListener('click', () => {
  if (viewMode === 'categories') {
    if (categoriesPage > 1) {
      categoriesPage -= 1;
      renderCategoriesPage(false);
    }
    return;
  }
  if (currentPage > 1) {
    currentPage -= 1;
    loadItems();
  }
});
btnNext.addEventListener('click', () => {
  if (viewMode === 'categories') {
    if (categoriesPage < categoriesTotalPages) {
      categoriesPage += 1;
      renderCategoriesPage(false);
    }
    return;
  }
  if (currentPage < totalPages) {
    currentPage += 1;
    loadItems();
  }
});

btnBack.addEventListener('click', () => {
  setView('categories');
});

if (creatorSteps) {
  creatorSteps.querySelectorAll('.step').forEach((btn) => {
    btn.addEventListener('click', () => setCreatorStep(btn.dataset.step));
  });
}

if (btnIdentityNext) {
  btnIdentityNext.classList.add('hidden');
}

if (identityGender) {
  identityGender.addEventListener('change', () => {
    const gender = identityGender.value || 'male';
    postNui('creatob_set_gender', { gender });
  });
}


if (btnSelectMother) btnSelectMother.addEventListener('click', () => openParentModal('mother'));
if (btnSelectFather) btnSelectFather.addEventListener('click', () => openParentModal('father'));
if (parentModalClose) parentModalClose.addEventListener('click', closeParentModal);
if (parentModal) parentModal.addEventListener('click', (e) => {
  if (e.target === parentModal) closeParentModal();
});
if (confirmNo) confirmNo.addEventListener('click', closeConfirm);
if (confirmYes) confirmYes.addEventListener('click', () => {
  const data = pendingConfirmData || collectIdentityData();
  const validation = validateIdentity(data);
  if (!validation.ok) {
    showAlert(validation.message);
    return;
  }
  if (confirmYes) confirmYes.disabled = true;
  postNui('save', { identity: data, confirmed: true });
  closeConfirm();
});
if (confirmModal) confirmModal.addEventListener('click', (e) => {
  if (e.target === confirmModal) closeConfirm();
});
if (alertOk) alertOk.addEventListener('click', closeAlert);
if (alertModal) alertModal.addEventListener('click', (e) => {
  if (e.target === alertModal) closeAlert();
});

if (blendRange) {
  blendRange.addEventListener('input', () => {
    shapeMix = Number(blendRange.value) / 100;
    skinMix = shapeMix;
    updateBlendDisplay();
    postNui('creatob_set_parents', { mother: selectedMother, father: selectedFather, shapeMix, skinMix });
  });
}

if (btnTexPrev) btnTexPrev.addEventListener('click', () => postNui('texture_change', { dir: -1 }));
if (btnTexNext) btnTexNext.addEventListener('click', () => postNui('texture_change', { dir: 1 }));
if (btnColorPrev) btnColorPrev.addEventListener('click', () => postNui('colob_change', { dir: -1 }));
if (btnColorNext) btnColorNext.addEventListener('click', () => postNui('colob_change', { dir: 1 }));

if (btnRotateLeft) btnRotateLeft.addEventListener('click', () => postNui('rotate', { dir: 1 }));
if (btnRotateRight) btnRotateRight.addEventListener('click', () => postNui('rotate', { dir: -1 }));
if (btnZoomIn) btnZoomIn.addEventListener('click', () => postNui('zoom', { dir: -1 }));
if (btnZoomOut) btnZoomOut.addEventListener('click', () => postNui('zoom', { dir: 1 }));

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    if (uiOptions.mode === 'appearance') { postNui('cancel'); return; }
    if (creatorMode && uiOptions.mode !== 'appearance') {
      return;
    }
    closeUi();
    postNui('cancel');
    postNui('close');
    return;
  }

  if (event.key === 'a' || event.key === 'A' || event.key === 'ArrowLeft') {
    postNui('rotate', { dir: 1 });
    return;
  }

  if (event.key === 'd' || event.key === 'D' || event.key === 'ArrowRight') {
    postNui('rotate', { dir: -1 });
  }
});

document.addEventListener('wheel', (event) => {
  if (event.target && event.target.closest && event.target.closest('.panel')) {
    return;
  }
  event.preventDefault();
  postNui('zoom', { dir: event.deltaY > 0 ? 1 : -1 });
}, { passive: false });

closeUi();
