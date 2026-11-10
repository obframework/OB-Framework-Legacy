const app = document.querySelector('#app');
const amount = document.querySelector('#amount');
const liters = document.querySelector('#liters');
const total = document.querySelector('#total');
const level = document.querySelector('#level');
const capacity = document.querySelector('#capacity');
const price = document.querySelector('#price');
const vehicle = document.querySelector('#vehicle');
const title = document.querySelector('#title');
const hint = document.querySelector('.hint');
const fuelContent = document.querySelector('#fuel-content');
const statusContent = document.querySelector('#status-content');
let state = null;
const post = (action, data = {}) => fetch(`https://${GetParentResourceName()}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;

function update() {
  const value = Number(amount.value) || 0;
  const selected = selectedFuelType();
  const unitPrice = Number(state?.prices?.[selected] ?? state?.price) || 0;
  liters.textContent = `${value.toFixed(1)} L`;
  total.textContent = money(Math.ceil(value * unitPrice));
}
function selectedFuelType() {
  return state?.selectedType || state?.type || 'gasoline';
}
function renderFuelButtons() {
  const selected = selectedFuelType();
  document.querySelectorAll('.fuel-types button').forEach((button) => {
    const active = button.dataset.type === selected;
    button.classList.toggle('active', active);
    button.classList.toggle('disabled', false);
    button.disabled = false;
  });
  const correct = selected === state.type;
  price.textContent = `${money(Number(state.prices?.[selected] ?? state.price) || 0)}/L`;
  hint.textContent = correct
    ? `Combustivel recomendado: ${selected === 'diesel' ? 'diesel' : 'gasolina'}.`
    : `Combustivel incorreto: ${selected === 'diesel' ? 'diesel' : 'gasolina'} pode contaminar o motor e causar falhas.`;
}
function renderFuel() {
  title.textContent = 'Abastecimento';
  fuelContent.classList.remove('hidden');
  statusContent.classList.add('hidden');
  vehicle.textContent = state.vehicle;
  level.textContent = `${state.level.toFixed(1)}%`;
  capacity.textContent = `${state.capacity} L`;
  price.textContent = `${money(state.price)}/L`;
  amount.max = state.maximum;
  amount.value = state.maximum;
  renderFuelButtons();
  update();
}
function renderStatus(data) {
  title.textContent = 'Diagnostico';
  fuelContent.classList.add('hidden');
  statusContent.classList.remove('hidden');
  vehicle.textContent = data.vehicle;
  document.querySelector('#status-fuel').textContent = `${data.fuel}%`;
  document.querySelector('#status-mileage').textContent = `${data.mileage} km`;
  document.querySelector('#maintenance').innerHTML = [['Oleo', data.oil], ['Freios', data.brakes], ['Velas', data.spark]].map(([name, item]) => `<div class="maintenance"><span>${name}</span><b class="${item.percent <= 15 ? 'bad' : item.percent <= 45 ? 'warn' : ''}">${item.label} · ${item.remaining} km</b><i><em style="width:${item.percent}%"></em></i></div>`).join('');
}
window.addEventListener('message', (event) => {
  if (event.data?.action === 'open') { state = event.data.data; app.classList.remove('hidden'); renderFuel(); }
  if (event.data?.action === 'status') { app.classList.remove('hidden'); renderStatus(event.data.data); }
  if (event.data?.action === 'close') { app.classList.add('hidden'); state = null; }
});
amount.oninput = update;
document.querySelectorAll('.fuel-types button').forEach((button) => {
  button.onclick = () => {
    if (!state) return;
    state.selectedType = button.dataset.type;
    renderFuelButtons();
    update();
  };
});
document.querySelector('#close').onclick = () => post('close');
document.querySelector('#confirm').onclick = () => post('confirm', { liters: Number(amount.value), fuelType: selectedFuelType() });
