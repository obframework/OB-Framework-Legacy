const $ = (id) => document.getElementById(id);
const app = $('app');
const modal = $('crimesModal');
const state = { mode: 'police', profile: {}, permissions: {}, suspects: [], crimes: [], selected: [], historyUserId: null };

const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[char]));
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;
const date = (value) => value ? String(value).replace('T', ' ') : 'N/A';
const nui = async (event, data = {}) => {
  try {
    const response = await fetch(`https://${GetParentResourceName()}/${event}`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data) });
    return await response.json();
  } catch (_) { return { ok:false, message:'Não foi possível contactar o servidor.' }; }
};

function setTab(name) {
  document.querySelectorAll('.tab').forEach((node) => node.classList.toggle('active', node.id === `tab-${name}`));
  document.querySelectorAll('nav button').forEach((node) => node.classList.toggle('active', node.dataset.tab === name));
}

function resetMdt() {
  state.mode = 'police';
  state.profile = {};
  state.permissions = {};
  state.suspects = [];
  state.crimes = [];
  state.selected = [];
  state.historyUserId = null;
  document.querySelectorAll('input, textarea').forEach((field) => {
    if (field.type === 'checkbox') field.checked = false;
    else field.value = '';
    delete field.dataset.auto;
  });
  ['peopleResults','historyResults','plateResult','recordResponse','clearResponse','auditResults'].forEach((id) => {
    $(id).innerHTML = '';
  });
  ['mugshotPreview','inventoryPreview'].forEach((id) => {
    $(id).removeAttribute('src');
    $(id).classList.remove('has-src');
  });
  $('suspects').innerHTML = '';
  $('selectedCrimes').innerHTML = '';
  $('crimeCatalog').innerHTML = '';
  $('profile').innerHTML = '';
  modal.classList.add('hidden');
  document.querySelector('.content').scrollTop = 0;
  setTab('people');
}

function close() {
  app.classList.add('hidden');
  resetMdt();
  nui('close');
}

window.addEventListener('message', ({ data }) => {
  if (data.action === 'close') {
    app.classList.add('hidden');
    resetMdt();
    return;
  }
  if (data.action !== 'open') return;
  resetMdt();
  app.classList.remove('hidden');
  nui('trace', { stage:'nui_open_received' });
  try {
    const payload = data.payload || {};
    state.mode = payload.mode || 'police'; state.profile = payload.profile || {}; state.permissions = payload.permissions || {};
    state.suspects = []; state.crimes = Array.isArray(payload.crimeCatalog) ? payload.crimeCatalog : []; state.selected = [];
    $('modeLabel').textContent = state.mode === 'police' ? 'Polícia' : 'Advocacia';
    $('profile').innerHTML = `<strong>${esc(state.profile.name)}</strong><br>ID fixo: ${esc(state.profile.userId)}<br>${esc(state.profile.job)} · cargo ${esc(state.profile.grade)}${state.profile.onDuty ? ' · em serviço' : ''}`;
    document.querySelectorAll('[data-police]').forEach((node) => node.classList.toggle('hidden', state.mode !== 'police'));
    document.querySelectorAll('[data-clear]').forEach((node) => node.classList.toggle('hidden', !state.permissions.canClear));
    document.querySelectorAll('[data-audit]').forEach((node) => node.classList.toggle('hidden', !state.permissions.canSeeAudit));
    $('months').max = payload.maximumMonths || 240; $('fine').max = payload.maximumFine || 10000000;
    renderSuspects(); renderCrimes(); renderSelected(); recalc();
    $('peopleResults').innerHTML = ''; $('historyResults').innerHTML = '';
    setTab('people');
    nui('trace', { stage:'nui_rendered' });
  } catch (error) {
    console.error('[ob_mdt] Falha ao renderizar a interface:', error);
    nui('trace', { stage:'nui_render_error' });
  }
});

document.querySelectorAll('nav button').forEach((button) => button.addEventListener('click', () => {
  setTab(button.dataset.tab);
  if (button.dataset.tab === 'audit') loadAudit();
}));
$('closeBtn').onclick = close; $('closeCrimes').onclick = () => modal.classList.add('hidden'); $('openCrimes').onclick = () => { renderCrimes(); modal.classList.remove('hidden'); };

function personCard(person) {
  return `<article class="card"><div class="card-head"><div><h3>${esc(person.name)}</h3><p>ID fixo ${esc(person.userId)} · telefone ${esc(person.phone)}</p></div><span class="badge">personagem</span></div><small>Nascimento: ${esc(person.birthdate || 'N/A')} · Nacionalidade: ${esc(person.nationality || 'N/A')}</small><div class="card-actions"><button data-history="${Number(person.userId)}">Ver histórico</button>${state.mode === 'police' ? `<button data-suspect="${Number(person.userId)}">Adicionar à ocorrência</button>` : ''}</div></article>`;
}

async function searchPeople(term, target) {
  target.innerHTML = '<div class="empty">Consultando...</div>';
  const response = await nui('queryPerson', { mode:state.mode, term });
  if (!response.ok) return target.innerHTML = `<div class="notice">${esc(response.message)}</div>`;
  target.innerHTML = response.data.length ? response.data.map(personCard).join('') : '<div class="empty">Nenhum personagem encontrado.</div>';
  target.querySelectorAll('[data-history]').forEach((button) => button.onclick = () => loadHistory(Number(button.dataset.history)));
  target.querySelectorAll('[data-suspect]').forEach((button) => button.onclick = () => addSuspectFromResults(response.data.find((person) => Number(person.userId) === Number(button.dataset.suspect))));
  return response.data;
}

$('searchPerson').onclick = () => searchPeople($('personTerm').value, $('peopleResults'));
$('personTerm').onkeydown = (event) => { if (event.key === 'Enter') $('searchPerson').click(); };

async function loadHistory(userId) {
  state.historyUserId = Number(userId) || null;
  const box = $('historyResults'); box.innerHTML = '<div class="empty">Carregando histórico...</div>';
  const response = await nui('getHistory', { mode:state.mode, userId });
  if (!response.ok) return box.innerHTML = `<div class="notice">${esc(response.message)}</div>`;
  box.innerHTML = `<div class="section-title"><div><span>HISTÓRICO</span><h2>ID fixo ${esc(userId)}</h2></div></div>` + (response.data.length ? response.data.map((record) => {
    const crimeNames = (record.crimes || []).map((crime) => crime.label).join(', ') || 'Nenhum crime catalogado';
    const fineStatus = record.fine_status === 'paid' ? 'paga' : 'pendente';
    const clearButton = !record.cleared && state.permissions.canClear
      ? `<div class="card-actions"><button data-clear-record="${Number(record.id)}">Limpar esta ficha</button></div>` : '';
    return `<article class="card"><div class="card-head"><div><h3>Registro #${esc(record.id)}</h3><p>${esc(record.reason)}</p></div><span class="badge ${record.cleared ? 'cleared' : ''}">${record.cleared ? 'ficha limpa' : 'ativo'}</span></div><small>${esc(crimeNames)}<br>Pena: ${esc(record.months)} mês(es) · multa: ${money(record.fine)} (${fineStatus}) · fiança: ${money(record.bail_amount)}<br>Oficial: ${esc(record.officer_name)} · ${esc(date(record.created_at))}${record.cleared ? `<br>Limpo por ${esc(record.cleared_by_name)}: ${esc(record.cleared_reason)}` : ''}</small>${clearButton}</article>`;
  }).join('') : '<div class="empty">Nenhum registro encontrado.</div>');
  box.querySelectorAll('[data-clear-record]').forEach((button) => button.onclick = () => {
    $('clearRecordId').value = button.dataset.clearRecord;
    $('clearReason').value = '';
    $('clearResponse').innerHTML = '';
    setTab('clear');
    setTimeout(() => $('clearReason').focus(), 0);
  });
}

function addSuspectFromResults(person) {
  if (!person || state.suspects.some((item) => Number(item.userId) === Number(person.userId))) return;
  state.suspects.push(person); renderSuspects(); setTab('record');
}

$('addSuspect').onclick = async () => {
  const temporary = document.createElement('div');
  const people = await searchPeople($('suspectTerm').value, temporary);
  if (people && people[0]) addSuspectFromResults(people[0]);
};

function renderSuspects() {
  $('suspects').innerHTML = state.suspects.length ? state.suspects.map((person, index) => `<span class="chip">${esc(person.name)} · ID ${esc(person.userId)} <button data-remove-suspect="${index}">×</button></span>`).join('') : '<span class="chip">Nenhum suspeito adicionado</span>';
  $('suspects').querySelectorAll('[data-remove-suspect]').forEach((button) => button.onclick = () => { state.suspects.splice(Number(button.dataset.removeSuspect), 1); renderSuspects(); });
}

function renderCrimes() {
  $('crimeCatalog').innerHTML = state.crimes.map((crime) => `<label class="crime-item"><input type="checkbox" data-crime="${esc(crime.code)}" ${state.selected.includes(crime.code) ? 'checked' : ''}><span>${esc(crime.label)}</span><small>${esc(crime.months)} mês(es) · ${money(crime.fine)}</small></label>`).join('');
  $('crimeCatalog').querySelectorAll('[data-crime]').forEach((input) => input.onchange = () => {
    state.selected = input.checked ? [...new Set([...state.selected, input.dataset.crime])] : state.selected.filter((code) => code !== input.dataset.crime);
    renderSelected(); recalc();
  });
}

function renderSelected() {
  $('selectedCrimes').innerHTML = state.selected.length ? state.selected.map((code) => {
    const crime = state.crimes.find((entry) => entry.code === code); return crime ? `<span class="chip">${esc(crime.label)} <button data-remove-crime="${esc(code)}">×</button></span>` : '';
  }).join('') : '<span class="chip">Nenhum crime selecionado</span>';
  $('selectedCrimes').querySelectorAll('[data-remove-crime]').forEach((button) => button.onclick = () => { state.selected = state.selected.filter((code) => code !== button.dataset.removeCrime); renderSelected(); renderCrimes(); recalc(); });
}

function recalc() {
  const selected = state.crimes.filter((crime) => state.selected.includes(crime.code));
  const months = selected.reduce((sum, crime) => sum + Number(crime.months || 0), 0); const fine = selected.reduce((sum, crime) => sum + Number(crime.fine || 0), 0);
  const monthsInput = $('months'), fineInput = $('fine');
  if (!monthsInput.dataset.auto || monthsInput.value === monthsInput.dataset.auto) monthsInput.value = months;
  if (!fineInput.dataset.auto || fineInput.value === fineInput.dataset.auto) fineInput.value = fine;
  monthsInput.dataset.auto = String(months); fineInput.dataset.auto = String(fine);
}

function preview(input, image) { $(input).oninput = () => { $(image).src = $(input).value; $(image).classList.toggle('has-src', /^https?:\/\//i.test($(input).value)); }; }
preview('mugshotUrl','mugshotPreview'); preview('inventoryPhotoUrl','inventoryPreview');

$('createRecord').onclick = async () => {
  const responseBox = $('recordResponse'); responseBox.innerHTML = '<div class="notice">Registrando...</div>';
  const response = await nui('createRecord', {
    suspects:state.suspects, crimeCodes:state.selected, months:Number($('months').value || 0), fine:Number($('fine').value || 0), reason:$('reason').value,
    bailAmount:Number($('bailAmount').value || 0), lawyerRequired:$('lawyerRequired').checked, mugshotUrl:$('mugshotUrl').value,
    inventoryPhotoUrl:$('inventoryPhotoUrl').value, seizedItems:$('seizedItems').value
  });
  responseBox.innerHTML = `<div class="notice">${esc(response.message || (response.ok ? 'Registro criado.' : 'Falha no registro.'))}</div>`;
  if (response.ok) { state.suspects = []; renderSuspects(); }
};

$('searchPlate').onclick = async () => {
  const box = $('plateResult'); const response = await nui('queryPlate', { mode:'police', plate:$('plateTerm').value });
  box.innerHTML = response.ok ? `<article class="card"><div class="card-head"><div><h3>${esc(response.data.plate)} · ${esc(response.data.model)}</h3><p>Proprietário: ${esc(response.data.ownerName)}</p></div><span class="badge">ID ${esc(response.data.ownerUserId)}</span></div></article>` : `<div class="notice">${esc(response.message)}</div>`;
};

$('clearRecord').onclick = async () => {
  const response = await nui('clearRecord', { mode:state.mode, recordId:Number($('clearRecordId').value), reason:$('clearReason').value });
  $('clearResponse').innerHTML = `<div class="notice">${esc(response.message)}</div>`;
  if (response.ok && state.historyUserId) loadHistory(state.historyUserId);
};

async function loadAudit() {
  const box = $('auditResults');
  box.innerHTML = '<div class="empty">Carregando histórico...</div>';
  const response = await nui('getClearAudit', { mode:state.mode });
  if (!response.ok) return box.innerHTML = `<div class="notice">${esc(response.message)}</div>`;
  box.innerHTML = response.data.length ? response.data.map((row) => `<article class="card"><div class="card-head"><div><h3>Registro #${esc(row.record_id)}</h3><p>${esc(row.suspect_name || 'Personagem')} · ID ${esc(row.suspect_user_id || 'N/A')}</p></div><span class="badge">${row.cleaner_mode === 'lawyer' ? 'advocacia' : 'polícia'}</span></div><p>Motivo: ${esc(row.note)}</p><small>Limpo por ${esc(row.cleaner_name)} · ID ${esc(row.cleaner_user_id)} · ${esc(date(row.created_at))}</small></article>`).join('') : '<div class="empty">Nenhuma ficha foi limpa até agora.</div>';
}
$('loadAudit').onclick = loadAudit;

window.addEventListener('keydown', (event) => { if (event.key !== 'Escape') return; if (!modal.classList.contains('hidden')) modal.classList.add('hidden'); else close(); });

const announceReady = async () => {
  const response = await nui('ready');
  if (!response?.ok) window.setTimeout(announceReady, 500);
};
announceReady();
