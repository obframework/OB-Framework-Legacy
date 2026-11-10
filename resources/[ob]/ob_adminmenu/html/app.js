const app = document.querySelector('#app');
const moduleList = document.querySelector('#modules');
const homePage = document.querySelector('#home-page');
const garagePage = document.querySelector('#garage-page');
const blackoutPage = document.querySelector('#blackout-page');
const offlinePage = document.querySelector('#offline-page');
const title = document.querySelector('#page-title');
const description = document.querySelector('#page-description');
const garageFeedback = document.querySelector('#garage-feedback');
const garageOwner = document.querySelector('#garage-owner');
const garageVehicles = document.querySelector('#garage-vehicles');
const garageGive = document.querySelector('#garage-give');
const userIdInput = document.querySelector('#garage-user-id');
const vehicleCount = document.querySelector('#vehicle-count');
const laserHud = document.querySelector('#laser-hud');
const laserType = document.querySelector('#laser-type');
const laserData = document.querySelector('#laser-data');
const blackoutFeedback = document.querySelector('#blackout-feedback');
let selectedUserId = null;
let canRemoveVehicle = false;

const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, character => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
})[character]);

const post = (name, data = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
}).then(response => response.json());

function showFeedback(message, type = 'error') {
  garageFeedback.textContent = message || '';
  garageFeedback.className = message ? `feedback ${type}` : 'feedback hidden';
}
function showHome() {
  homePage.classList.remove('hidden'); garagePage.classList.add('hidden'); blackoutPage.classList.add('hidden'); offlinePage.classList.add('hidden');
  title.textContent = 'Administração'; description.textContent = 'Ferramentas e editores autorizados';
}
function showGarage() {
  homePage.classList.add('hidden'); garagePage.classList.remove('hidden'); blackoutPage.classList.add('hidden'); offlinePage.classList.add('hidden');
  title.textContent = 'Garagens'; description.textContent = 'Consulta e entrega por ID fixo do personagem';
  setTimeout(() => userIdInput.focus(), 0);
}
function blackoutMessage(message, type = 'error') {
  blackoutFeedback.textContent = message || '';
  blackoutFeedback.className = message ? `feedback ${type}` : 'feedback hidden';
}
function renderBlackout(data) {
  const activeLabel = document.querySelector('#blackout-active');
  activeLabel.textContent = data.active ? 'Energia desligada' : 'Energia ligada';
  activeLabel.className = data.active ? 'power-off' : 'power-on';
  document.querySelector('#blackout-mode').textContent = data.mode === 'admin' ? 'Manual do administrador'
    : data.mode === 'manual' || data.mode === 'item' ? 'Procedimento no painel elétrico' : 'Automático';
  document.querySelector('#blackout-clock').textContent = `${String(data.hour ?? 0).padStart(2, '0')}:${String(data.minute ?? 0).padStart(2, '0')}`;
  const chance = Math.max(0, Math.min(100, Number(data.automaticChancePercent ?? 10)));
  document.querySelector('#blackout-scheduled').textContent = !data.automaticEnabled
    ? 'Desativado'
    : data.scheduled
      ? `${data.automaticSelected ? 'Sorteado nesta noite' : 'Sem apagão nesta noite'} · ${chance}%`
      : `Fora do período · ${chance}% por noite`;
}
async function refreshBlackout() {
  blackoutMessage('');
  const response = await post('blackoutStatus');
  if (!response.ok) return blackoutMessage(response.error || 'Não foi possível consultar a energia.');
  renderBlackout(response.data);
}
async function showBlackout() {
  homePage.classList.add('hidden'); garagePage.classList.add('hidden'); blackoutPage.classList.remove('hidden'); offlinePage.classList.add('hidden');
  title.textContent = 'Energia da cidade'; description.textContent = 'Controle manual e agenda automática do apagão';
  await refreshBlackout();
}
function resetGarage() {
  selectedUserId = null; canRemoveVehicle = false; userIdInput.value = ''; garageOwner.textContent = ''; garageOwner.classList.add('hidden');
  garageGive.classList.add('hidden'); garageGive.reset(); document.querySelector('#give-garage').value = 'central';
  garageVehicles.className = 'vehicle-list empty'; garageVehicles.textContent = 'Nenhuma consulta realizada.';
  vehicleCount.textContent = 'Consulte um personagem'; showFeedback('');
}
function renderModules(entries) {
  moduleList.innerHTML = '';
  for (const module of entries) {
    const button = document.createElement('button');
    button.className = 'module'; button.type = 'button'; button.disabled = module.enabled === false;
    button.innerHTML = `<b>${escapeHtml(module.label)}</b><span>${escapeHtml(module.description || '')}</span>`;
    button.onclick = () => post('action', { id: module.id }); moduleList.append(button);
  }
}
function vehicleCard(vehicle) {
  const article = document.createElement('article'); article.className = 'vehicle-card';
  const status = vehicle.stored ? 'Na garagem' : 'Fora da garagem';
  article.innerHTML = `<div class="vehicle-main"><small>#${escapeHtml(vehicle.id)}</small><h3>${escapeHtml(vehicle.label || vehicle.model)}</h3><p>${escapeHtml(vehicle.model)}</p></div>
    <div><small>PLACA</small><strong>${escapeHtml(vehicle.plate)}</strong></div><div><small>GARAGEM</small><strong>${escapeHtml(vehicle.garage)}</strong></div>
    <div><small>STATUS</small><strong class="status ${vehicle.stored ? 'stored' : 'outside'}">${status}</strong></div>
    <div><small>ESTADO</small><strong>${Math.round(vehicle.fuel)}% combustível · ${Math.round(vehicle.engine)} motor</strong></div>`;
  if (canRemoveVehicle) {
    const remove = document.createElement('button');
    remove.type = 'button'; remove.className = 'vehicle-remove'; remove.textContent = 'Remover';
    remove.disabled = vehicle.stored !== true;
    remove.title = vehicle.stored ? 'Remover permanentemente da garagem' : 'Guarde o veiculo antes de remover';
    let removalArmed = false;
    remove.onclick = async () => {
      if (!removalArmed) {
        removalArmed = true; remove.textContent = 'Confirmar'; remove.classList.add('confirming');
        setTimeout(() => { removalArmed = false; remove.textContent = 'Remover'; remove.classList.remove('confirming'); }, 5000);
        return;
      }
      remove.disabled = true;
      showFeedback('Removendo veiculo...', 'success');
      const response = await post('garageRemoveVehicle', { userId: selectedUserId, vehicleId: vehicle.id });
      if (!response.ok) {
        remove.disabled = false; removalArmed = false; remove.textContent = 'Remover'; remove.classList.remove('confirming');
        return showFeedback(response.error || 'Nao foi possivel remover o veiculo.');
      }
      await queryGarage();
      showFeedback(response.message || 'Veiculo removido.', 'success');
    };
    article.append(remove);
  }
  return article;
}
function renderGarage(data) {
  selectedUserId = data.character.userId;
  canRemoveVehicle = data.canRemove === true;
  garageOwner.textContent = `${data.character.name} · ID fixo ${data.character.userId}`; garageOwner.classList.remove('hidden');
  garageGive.classList.toggle('hidden', data.canGive !== true); garageVehicles.innerHTML = '';
  garageVehicles.classList.toggle('empty', !data.vehicles.length); vehicleCount.textContent = `${data.vehicles.length} veículo(s)`;
  if (!data.vehicles.length) garageVehicles.textContent = 'Esse personagem ainda não possui veículos.';
  else data.vehicles.forEach(vehicle => garageVehicles.append(vehicleCard(vehicle)));
}
async function queryGarage() {
  showFeedback('');
  const response = await post('garageVehicles', { userId: userIdInput.value.trim() });
  if (!response.ok) return showFeedback(response.error || 'Não foi possível consultar a garagem.');
  renderGarage(response.data);
}
document.querySelector('#garage-search').onsubmit = async event => { event.preventDefault(); await queryGarage(); };
garageGive.onsubmit = async event => {
  event.preventDefault();
  if (!selectedUserId) return showFeedback('Consulte primeiro o personagem que receberá o veículo.');
  showFeedback('');
  const response = await post('garageGiveVehicle', {
    userId: selectedUserId, model: document.querySelector('#give-model').value.trim(),
    label: document.querySelector('#give-label').value.trim(), plate: document.querySelector('#give-plate').value.trim(),
    garage: document.querySelector('#give-garage').value.trim(),
  });
  if (!response.ok) return showFeedback(response.error || 'Não foi possível entregar o veículo.');
  showFeedback(response.message || 'Veículo entregue.', 'success');
  document.querySelector('#give-model').value = ''; document.querySelector('#give-label').value = ''; document.querySelector('#give-plate').value = '';
  await queryGarage();
};
document.querySelector('#garage-back').onclick = showHome;
document.querySelector('#blackout-back').onclick = showHome;
document.querySelector('#blackout-refresh').onclick = refreshBlackout;
document.querySelectorAll('[data-blackout]').forEach(button => {
  button.onclick = async () => {
    blackoutMessage('');
    const response = await post('blackoutSet', { action: button.dataset.blackout });
    if (!response.ok) return blackoutMessage(response.error || 'Não foi possível alterar a energia.');
    renderBlackout(response.data);
    blackoutMessage('Estado da energia atualizado.', 'success');
  };
});
document.querySelector('#close').onclick = () => post('close');
document.addEventListener('keydown', event => { if (event.key === 'Escape' && !app.classList.contains('hidden')) post('close'); });

function renderLaser(data = {}) {
  laserType.textContent = data.type || 'Mundo';
  const fields = [['Nome',data.name],['Hash',data.hash],['Net ID',data.netId],['ID da sessão',data.sessionId],['Placa',data.plate],
    ['Coordenadas',data.coords],['Rotação',data.rotation],['Heading',data.heading],['Combustível',data.fuel],['Motor',data.engine],['Lataria',data.body]];
  laserData.innerHTML = fields.filter(([,value]) => value !== undefined && value !== null && value !== '')
    .map(([label,value]) => `<div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>`).join('');
}
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); }
  catch (_) { const input=document.createElement('textarea'); input.value=text; document.body.append(input); input.select(); document.execCommand('copy'); input.remove(); }
  post('laserCopied');
}
window.addEventListener('message', event => {
  const message = event.data || {};
  if (message.action === 'open') { resetGarage(); app.classList.remove('hidden'); showHome(); renderModules(message.modules || []); }
  else if (message.action === 'close') { app.classList.add('hidden'); showHome(); resetGarage(); }
  else if (message.action === 'garageOpen') showGarage();
  else if (message.action === 'blackoutOpen') showBlackout();
  else if (message.action === 'laser') { laserHud.classList.toggle('hidden', message.show !== true); if (message.show) renderLaser(message.data); }
  else if (message.action === 'laserCopy' && message.text) copyText(message.text);
});
