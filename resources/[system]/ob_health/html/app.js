const root = document.getElementById('death');
const timer = document.getElementById('timer');
const giveUp = document.getElementById('give-up');
const cause = document.getElementById('death-cause');
const detail = document.getElementById('death-detail');
const medical = document.getElementById('medical');
const medicalName = document.getElementById('medical-name');
const medicalStatus = document.getElementById('medical-status');
const medicalHealth = document.getElementById('medical-health');
const patientState = document.querySelector('.patient-state');
const carryLabel = document.getElementById('carry-label');
const treatmentDescription = document.getElementById('treatment-description');
const reviveDescription = document.getElementById('revive-description');
const bodyScan = document.getElementById('body-scan');
const scanName = document.getElementById('scan-name');
const scanStatus = document.getElementById('scan-status');
const scanHealth = document.getElementById('scan-health');
const injuryCount = document.getElementById('injury-count');
const injuryList = document.getElementById('injury-list');
const resource = GetParentResourceName();

function formatTime(milliseconds) {
  const seconds = Math.max(0, Math.ceil((Number(milliseconds) || 0) / 1000));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}

function update(remaining) {
    const value = Math.max(0, Number(remaining) || 0);
    timer.textContent = formatTime(value);
    giveUp.disabled = value > 0;
}

function requestRespawn() {
  if (giveUp.disabled) return;
  fetch(`https://${GetParentResourceName()}/giveUp`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: '{}',
  });
}

function postMedical(endpoint, data = {}) {
  return fetch(`https://${resource}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
}

function closeMedical() {
  medical.classList.add('hidden');
  postMedical('medicalClose');
}

function openMedical(patient = {}) {
  const downed = patient.downed === true;
  const carried = Number(patient.carriedBy) > 0;
  medicalName.textContent = patient.name || 'Paciente';
  medicalStatus.textContent = downed ? 'Paciente incapacitado' : 'Paciente consciente';
  medicalHealth.textContent = downed ? 'CRITICO' : `${Number(patient.healthPercent) || 0}% SAUDE`;
  patientState.classList.toggle('downed', downed);
  carryLabel.textContent = carried ? 'Colocar no chao' : 'Carregar';
  treatmentDescription.textContent = `Recuperar a saude · ${patient.prices?.treatment || '$0'}`;
  reviveDescription.textContent = `Desfibrilador e protocolo CPR · ${patient.prices?.revive || '$0'}`;
  document.querySelector('[data-medical-action="treat"]').disabled = downed;
  document.querySelector('[data-medical-action="revive"]').disabled = !downed;
  document.querySelector('[data-medical-action="carry"]').disabled = !downed && !carried;
  medical.classList.remove('hidden');
}

function closeBodyScan() {
  bodyScan.classList.add('hidden');
  postMedical('bodyScanClose');
}

function escapeHtml(value) {
  const element = document.createElement('span');
  element.textContent = String(value ?? '');
  return element.innerHTML;
}

function openBodyScan(patient = {}) {
  medical.classList.add('hidden');
  const injuries = patient.injuries || {};
  const rows = Object.entries(injuries).filter(([, injury]) => injury && Number(injury.severity) > 0);
  scanName.textContent = patient.name || 'Paciente';
  scanStatus.textContent = patient.downed === true ? 'INCAPACITADO' : 'CONSCIENTE';
  scanHealth.textContent = `${Number(patient.healthPercent) || 0}%`;
  injuryCount.textContent = String(rows.length);
  document.querySelectorAll('.body-map [data-region]').forEach(element => {
    const injury = injuries[element.dataset.region];
    element.classList.toggle('injured', Boolean(injury));
    element.classList.toggle('severe', Number(injury?.severity) >= 60);
  });
  injuryList.innerHTML = rows.length ? rows.map(([region, injury]) => {
    const severity = Math.max(1, Math.min(100, Number(injury.severity) || 1));
    const material = patient.requiredMaterials?.[region];
    const missing = material && Number(material.available) < Number(material.amount);
    const labels = { tweezers: 'Pinça cirúrgica', suturekit: 'Kit de sutura', icepack: 'Bolsa de gelo', burncream: 'Creme para queimaduras', bandage: 'Bandagem' };
    const materialText = material
      ? `Material: ${Number(material.amount) || 1}× ${labels[material.item] || material.item} (${material.item}) · Você tem: ${Number(material.available) || 0}`
      : 'O material será conferido ao iniciar o tratamento.';
    return `<article class="injury-card">
      <div><h4>${escapeHtml(injury.label || region)}</h4>
      <p>${escapeHtml(injury.causeLabel || 'Ferimento')} · gravidade <em>${severity}%</em></p>
      <p>${escapeHtml(materialText)}</p>
      <div class="severity-bar"><i style="width:${severity}%"></i></div></div>
      <button type="button" data-treat-region="${escapeHtml(region)}" ${missing ? 'disabled' : ''}>${missing ? 'FALTA MATERIAL' : 'TRATAR'}</button>
    </article>`;
  }).join('') : '<div class="injury-empty"><div><strong>SEM LESOES</strong><p>Nenhum trauma localizado foi detectado.</p></div></div>';
  injuryList.querySelectorAll('[data-treat-region]').forEach(button => {
    button.addEventListener('click', () => {
      bodyScan.classList.add('hidden');
      postMedical('injuryTreat', { region: button.dataset.treatRegion });
    });
  });
  bodyScan.classList.remove('hidden');
}

giveUp.addEventListener('click', requestRespawn);
document.getElementById('npc-rescue').addEventListener('click', () => postMedical('npcRescue'));
document.getElementById('medical-close').addEventListener('click', closeMedical);
document.getElementById('scan-close').addEventListener('click', closeBodyScan);
document.querySelectorAll('[data-medical-action]').forEach(button => {
  button.addEventListener('click', () => {
    if (button.disabled) return;
    medical.classList.add('hidden');
    postMedical('medicalAction', { action: button.dataset.medicalAction });
  });
});

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !bodyScan.classList.contains('hidden')) {
    event.preventDefault();
    closeBodyScan();
    return;
  }
  if (event.key === 'Escape' && !medical.classList.contains('hidden')) {
    event.preventDefault();
    closeMedical();
    return;
  }
  if (event.key.toLowerCase() === 'e') requestRespawn();
});

window.addEventListener('message', ({ data = {} }) => {
  if (data.action === 'open') {
    const death = data.death || {};
    cause.textContent = death.cause || 'Ferimentos graves';
    detail.textContent = death.detail || 'Aguarde atendimento ou uma adrenalina no HP ilegal.';
    update(data.remaining);
    root.classList.remove('hidden');
  }
  if (data.action === 'close') root.classList.add('hidden');
  if (data.action === 'tick') update(data.remaining);
  if (data.action === 'medicalOpen') openMedical(data.patient || {});
  if (data.action === 'medicalClose') medical.classList.add('hidden');
  if (data.action === 'bodyScanOpen') openBodyScan(data.patient || {});
  if (data.action === 'bodyScanClose') bodyScan.classList.add('hidden');
});
