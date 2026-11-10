const q = (selector) => document.querySelector(selector);
const qa = (selector) => [...document.querySelectorAll(selector)];
const app = q('#app');
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;
const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({
  '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;'
}[char]));

let branch = false;
let account = {};
let pendingBankAction = null;

const finesStyle = document.createElement('link');
finesStyle.rel = 'stylesheet';
finesStyle.href = 'fines.css';
document.head.append(finesStyle);

q('nav').insertAdjacentHTML('beforeend',
  '<button class="nav" data-page="fines">! <span>Multas</span></button>');
q('.content').insertAdjacentHTML('beforeend', `
  <section class="page hidden" id="fines">
    <h2>Multas pendentes</h2>
    <div class="fine-summary">
      <div><small>TOTAL PENDENTE</small><strong id="fineTotal" data-ob-money="0">$0</strong></div>
      <span>O pagamento usa o saldo da sua conta e exige o seu próprio cartão bancário.</span>
    </div>
    <p id="fineMessage"></p>
    <div id="fineList" class="fine-list"></div>
  </section>
`);
document.body.insertAdjacentHTML('beforeend', `
  <div id="pinModal" class="pin-modal hidden">
    <div class="pin-dialog">
      <small>CONFIRMAÇÃO BANCÁRIA</small>
      <h2 id="pinTitle">Digite seu PIN</h2>
      <p id="pinSummary"></p>
      <input id="operationPin" type="password" inputmode="numeric" maxlength="4" autocomplete="off" placeholder="PIN de 4 números">
      <p id="pinError"></p>
      <div>
        <button id="cancelPin" type="button">Cancelar</button>
        <button id="confirmPin" class="confirm" type="button">Confirmar</button>
      </div>
    </div>
  </div>
`);
const legacyPin = q('#pin');
if (legacyPin) legacyPin.remove();

const post = (name, data = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(data)
}).then((response) => response.json());

function rows(target, items) {
  const outgoingKinds = ['withdraw', 'card', 'pin_reset', 'transfer_out', 'fine_payment'];
  target.innerHTML = items.length ? items.map((row) => {
    const outgoing = outgoingKinds.includes(row.kind);
    return `<div class="transaction">
      <span>${esc(row.description)}<small>${esc(row.created_at || '')}</small></span>
      <b class="${outgoing ? 'out' : 'in'}">${outgoing ? '-' : '+'}${money(row.amount)}</b>
    </div>`;
  }).join('') : '<div class="empty">Nenhuma movimentação.</div>';
}

function renderFines(data) {
  const fines = Array.isArray(data.fines) ? data.fines : [];
  const ownCard = data.card && data.card.owner === true;
  q('#fineTotal').textContent = money(data.pendingFineTotal);
  q('#fineList').innerHTML = fines.length ? fines.map((fine) => `
    <article class="fine-row">
      <div>
        <h3>Multa MDT #${Number(fine.id)}</h3>
        <p>${esc(fine.reason || 'Sem descrição.')}</p>
        <small>Registrada por ${esc(fine.officer_name || 'Polícia')} · ${esc(fine.created_at || '')}</small>
      </div>
      <div class="fine-payment">
        <b>${money(fine.fine)}</b>
        <button data-fine-id="${Number(fine.id)}" ${ownCard ? '' : 'disabled'}>Pagar multa</button>
      </div>
    </article>
  `).join('') : '<div class="empty">Você não possui multas pendentes.</div>';

  q('#fineList').querySelectorAll('[data-fine-id]').forEach((button) => {
    button.onclick = async () => {
      button.disabled = true;
      q('#fineMessage').textContent = 'Processando pagamento...';
      const response = await post('action', { action:'fine', value:Number(button.dataset.fineId) });
      q('#fineMessage').textContent = response.message || '';
      if (response.account) render(response.account);
      else button.disabled = false;
    };
  });
}

function render(data) {
  if (!data) return;
  account = data;
  q('#balance').textContent = money(data.balance);
  q('#cash').textContent = money(data.cash);

  const card = data.card;
  const ownCard = card && card.owner;
  const week = data.week || {};
  q('.chart-area').innerHTML = `<div class="week-summary">
    <small>RESUMO REAL — ÚLTIMOS 7 DIAS</small>
    <b class="in">Entrou ${money(week.incoming)}</b>
    <b class="out">Saiu ${money(week.outgoing)}</b>
    <span>Soma salários, transferências e operações bancárias desta semana.</span>
  </div>`;

  q('#cardStatus').textContent = card ? 'Cartão ativo' : 'Sem cartão';
  q('#cardInfo').textContent = card ? (ownCard ? 'Seu cartão pessoal' : 'Cartão de terceiro') : 'Emita em uma agência';
  q('#cardNumber').textContent = card ? card.number.replace(/(\d{4})/g, '$1 ').trim() : '•••• •••• •••• ••••';
  q('#cardText').textContent = card
    ? (ownCard ? 'Seu cartão pessoal está pronto para operações.' : 'Este cartão pertence a outra pessoa e não movimenta a sua conta.')
    : 'Você não possui um cartão válido.';

  rows(q('#recent'), (data.transactions || []).slice(0, 4));
  rows(q('#transactionList'), data.transactions || []);
  q('#atmHint').textContent = ownCard
    ? 'Depósito e saque exigem o seu cartão e confirmação pelo PIN.'
    : 'Você precisa do seu próprio cartão para movimentar a conta.';
  qa('#overview [data-action]').forEach((button) => { button.disabled = !ownCard; });
  q('#issue').style.display = branch ? '' : 'none';
  q('#resetPin').style.display = branch && card ? '' : 'none';
  q('#resetPin').textContent = `Alterar PIN — ${money(1500)}`;
  renderFines(data);
}

function page(id) {
  qa('.page').forEach((node) => node.classList.toggle('hidden', node.id !== id));
  qa('.nav').forEach((node) => node.classList.toggle('active', node.dataset.page === id));
  const titles = {
    overview: 'Olá, cliente.',
    transactions: 'Movimentações',
    card: 'Meu cartão',
    fines: 'Multas pendentes'
  };
  q('#pageTitle').textContent = titles[id] || 'OB Bank';
}

function closePinModal() {
  pendingBankAction = null;
  q('#operationPin').value = '';
  q('#pinError').textContent = '';
  q('#pinModal').classList.add('hidden');
}

function openPinModal(action) {
  const value = Math.floor(Number(q('#amount').value) || 0);
  if (value < 1) {
    q('#message').textContent = 'Informe um valor válido.';
    return;
  }
  pendingBankAction = { action, value };
  q('#pinTitle').textContent = action === 'deposit' ? 'Confirmar depósito' : 'Confirmar saque';
  q('#pinSummary').textContent = `${action === 'deposit' ? 'Depositar' : 'Sacar'} ${money(value)}`;
  q('#operationPin').value = '';
  q('#pinError').textContent = '';
  q('#pinModal').classList.remove('hidden');
  setTimeout(() => q('#operationPin').focus(), 0);
}

async function confirmPinOperation() {
  if (!pendingBankAction) return;
  const pin = q('#operationPin').value;
  if (!/^\d{4}$/.test(pin)) {
    q('#pinError').textContent = 'Digite os 4 números do PIN.';
    q('#operationPin').focus();
    return;
  }
  const button = q('#confirmPin');
  button.disabled = true;
  q('#pinError').textContent = 'Validando...';
  let response;
  try {
    response = await post('action', { ...pendingBankAction, pin });
  } catch (_) {
    button.disabled = false;
    q('#pinError').textContent = 'O banco não respondeu. Tente novamente.';
    return;
  }
  button.disabled = false;
  if (!response.ok) {
    q('#pinError').textContent = response.message || 'Não foi possível concluir a operação.';
    q('#operationPin').value = '';
    q('#operationPin').focus();
    if (response.account) render(response.account);
    return;
  }
  q('#message').textContent = response.message || 'Operação concluída.';
  q('#amount').value = '';
  closePinModal();
  if (response.account) render(response.account);
}

function resetBank() {
  branch = false;
  account = {};
  closePinModal();
  ['amount','newPin'].forEach((id) => { const field = q(`#${id}`); if (field) field.value = ''; });
  ['message','fineMessage'].forEach((id) => { const field = q(`#${id}`); if (field) field.textContent = ''; });
  const content = q('.content');
  if (content) content.scrollTop = 0;
  page('overview');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    resetBank();
    branch = data.data.branch === true;
    app.classList.remove('hidden');
    page('overview');
    render(data.data.account);
  }
  if (data.action === 'close') {
    app.classList.add('hidden');
    resetBank();
  }
});

qa('.nav').forEach((button) => { button.onclick = () => page(button.dataset.page); });
qa('[data-action]').forEach((button) => {
  button.onclick = async () => {
    const action = button.dataset.action;
    if (action === 'deposit' || action === 'withdraw') return openPinModal(action);
    const response = await post('action', { action, value:q('#amount').value, pin:q('#newPin').value });
    q('#message').textContent = response.message || '';
    if (response.account) render(response.account);
    if (response.ok) q('#newPin').value = '';
  };
});

q('#cancelPin').onclick = closePinModal;
q('#confirmPin').onclick = confirmPinOperation;
q('#operationPin').onkeydown = (event) => { if (event.key === 'Enter') confirmPinOperation(); };
q('#close').onclick = () => post('close');
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (!q('#pinModal').classList.contains('hidden')) closePinModal();
  else post('close');
});
