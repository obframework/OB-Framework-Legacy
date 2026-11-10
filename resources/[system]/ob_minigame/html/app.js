const app = document.querySelector('#app');
const title = document.querySelector('#title');
const key = document.querySelector('#key');
const counter = document.querySelector('#counter');
const needle = document.querySelector('#needle');
const target = document.querySelector('#target');
const precision = document.querySelector('#precision');
const precisionTarget = document.querySelector('#precision-target');
const precisionCursor = document.querySelector('#precision-cursor');
const precisionCounter = document.querySelector('#precision-counter');
const dataCrack = document.querySelector('#data-crack');
const dataBars = document.querySelector('#data-bars');
const dataTitle = document.querySelector('#data-title');
const dataTime = document.querySelector('#data-time');
const dataProgress = document.querySelector('#data-progress');
const dataErrors = document.querySelector('#data-errors');
const circuit = document.querySelector('#circuit');
const circuitRows = document.querySelector('#circuit-rows');
const circuitTitle = document.querySelector('#circuit-title');
const circuitTime = document.querySelector('#circuit-time');
const circuitTargetValue = document.querySelector('#circuit-target-value');
const circuitResultValue = document.querySelector('#circuit-result-value');
const circuitAttempts = document.querySelector('#circuit-attempts');
const wire = document.querySelector('#wire');
const wireTitle = document.querySelector('#wire-title');
const wireTime = document.querySelector('#wire-time');
const wireOrder = document.querySelector('#wire-order');
const wireBoard = document.querySelector('#wire-board');
const wireErrors = document.querySelector('#wire-errors');

let active = null;
let frame = null;
let precisionActive = null;
let precisionFrame = null;
let dataActive = null;
let dataFrame = null;
let circuitActive = null;
let circuitFrame = null;
let wireActive = null;
let wireFrame = null;

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_minigame';
const post = payload => fetch(`https://${resource}/complete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
const postPrecision = payload => fetch(`https://${resource}/precisionComplete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
const postDataCrack = payload => fetch(`https://${resource}/dataCrackComplete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
const postCircuit = payload => fetch(`https://${resource}/circuitComplete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
const postWire = payload => fetch(`https://${resource}/wireComplete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
const angleDistance = (a, b) => Math.abs((((a - b) + 180) % 360) - 180);
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
const clockText = seconds => `00:${String(Math.max(0, Math.ceil(seconds))).padStart(2, '0')}`;
const padValue = value => String(Math.max(0, Math.floor(value))).padStart(3, '0').slice(-3);

function stop(success, reason) {
  if (!active) return;
  cancelAnimationFrame(frame);
  active = null;
  app.classList.add('hidden');
  post({ success, reason });
}

function newStep() {
  active.progress = 0;
  active.target = 50 + Math.random() * 260;
  target.style.transform = `rotate(${active.target}deg)`;
  counter.textContent = `${active.completed + 1}/${active.steps}`;
}

function animate(time) {
  if (!active) return;
  if (!active.last) active.last = time;
  const elapsed = Math.min(100, time - active.last);
  active.last = time;
  active.progress = (active.progress + (elapsed / 1000) * active.speed * 180) % 360;
  needle.style.transform = `rotate(${active.progress}deg)`;
  frame = requestAnimationFrame(animate);
}

function stopPrecision(success) {
  if (!precisionActive) return;
  cancelAnimationFrame(precisionFrame);
  precisionActive = null;
  precision.classList.add('hidden');
  postPrecision({ success });
}

function newPrecisionStep() {
  precisionActive.position = 0;
  precisionActive.target = 12 + Math.random() * 68;
  precisionTarget.style.left = `${precisionActive.target}%`;
  precisionCounter.textContent = `${precisionActive.completed + 1} / ${precisionActive.steps}`;
}

function animatePrecision(time) {
  if (!precisionActive) return;
  if (!precisionActive.last) precisionActive.last = time;
  const elapsed = Math.min(80, time - precisionActive.last);
  precisionActive.last = time;
  precisionActive.position = (precisionActive.position + (elapsed / 1000) * 46) % 100;
  precisionCursor.style.left = `${precisionActive.position}%`;
  precisionFrame = requestAnimationFrame(animatePrecision);
}

function stopDataCrack(success, reason) {
  if (!dataActive) return;
  cancelAnimationFrame(dataFrame);
  dataActive = null;
  dataCrack.classList.add('hidden');
  postDataCrack({ success, reason });
}

function selectNextDataBar(direction = 1) {
  if (!dataActive) return;
  for (let offset = 1; offset <= dataActive.bars.length; offset += 1) {
    const index = (dataActive.selected + (offset * direction) + dataActive.bars.length) % dataActive.bars.length;
    if (!dataActive.bars[index].locked) {
      dataActive.selected = index;
      break;
    }
  }
  dataActive.bars.forEach((bar, index) => bar.element.classList.toggle('selected', index === dataActive.selected));
}

function renderDataStatus() {
  if (!dataActive) return;
  const completed = dataActive.bars.filter(bar => bar.locked).length;
  dataProgress.textContent = `${completed} / ${dataActive.bars.length} SINCRONIZADAS`;
  dataErrors.textContent = `FALHAS ${dataActive.mistakes} / ${dataActive.maxMistakes}`;
  dataErrors.classList.toggle('danger', dataActive.mistakes > 0);
}

function animateDataCrack(time) {
  if (!dataActive) return;
  if (!dataActive.last) dataActive.last = time;
  const delta = Math.min(0.05, (time - dataActive.last) / 1000);
  dataActive.last = time;
  const remaining = (dataActive.deadline - performance.now()) / 1000;
  dataTime.textContent = clockText(remaining);
  if (remaining <= 0) return stopDataCrack(false, 'tempo esgotado');

  dataActive.bars.forEach(bar => {
    if (!bar.locked) {
      bar.position += bar.direction * bar.speed * delta;
      if (bar.position >= 0.9) { bar.position = 0.9; bar.direction = -1; }
      if (bar.position <= 0.1) { bar.position = 0.1; bar.direction = 1; }
    }
    bar.stick.style.top = `${bar.position * 100}%`;
  });
  dataFrame = requestAnimationFrame(animateDataCrack);
}

function startDataCrack(options = {}) {
  const count = clamp(Math.floor(Number(options.bars) || 6), 3, 10);
  dataTitle.textContent = options.title || 'INVASAO DA REDE';
  dataBars.innerHTML = '';
  dataActive = {
    selected: 0,
    mistakes: 0,
    maxMistakes: clamp(Math.floor(Number(options.maxMistakes) || 3), 0, 10),
    tolerance: clamp(Number(options.tolerance) || 0.075, 0.035, 0.16),
    deadline: performance.now() + (clamp(Number(options.timeSeconds) || 40, 10, 180) * 1000),
    last: 0,
    bars: [],
  };
  for (let index = 0; index < count; index += 1) {
    const element = document.createElement('div');
    element.className = `data-column${index === 0 ? ' selected' : ''}`;
    element.innerHTML = '<i class="data-bar-stick"></i><small></small>';
    const bar = {
      element,
      stick: element.querySelector('i'),
      position: 0.12 + Math.random() * 0.76,
      direction: Math.random() > 0.5 ? 1 : -1,
      speed: (0.24 + Math.random() * 0.22) * clamp(Number(options.speed) || 1, 0.35, 2.5),
      locked: false,
    };
    element.querySelector('small').textContent = String(index + 1).padStart(2, '0');
    element.onclick = () => {
      if (!dataActive || bar.locked) return;
      dataActive.selected = index;
      dataActive.bars.forEach((entry, entryIndex) => entry.element.classList.toggle('selected', entryIndex === index));
    };
    dataActive.bars.push(bar);
    dataBars.append(element);
  }
  renderDataStatus();
  dataCrack.classList.remove('hidden');
  cancelAnimationFrame(dataFrame);
  dataFrame = requestAnimationFrame(animateDataCrack);
}

function circuitResult() {
  return circuitActive ? circuitActive.rows.reduce((total, row) => total + (row.base * row.multiplier), 0) : 0;
}

function renderCircuit() {
  if (!circuitActive) return;
  circuitRows.innerHTML = circuitActive.rows.map((row, index) => `
    <button class="circuit-row${index === circuitActive.selected ? ' selected' : ''}" data-circuit-row="${index}">
      <strong>${row.base}</strong><span>×</span><b>${row.multiplier}</b><i></i><em>${padValue(row.base * row.multiplier)}</em>
    </button>`).join('');
  circuitRows.querySelectorAll('[data-circuit-row]').forEach(button => {
    button.onclick = () => { if (circuitActive) { circuitActive.selected = Number(button.dataset.circuitRow); renderCircuit(); } };
  });
  const result = circuitResult();
  if (circuitActive.adjustCurrent) {
    circuitTargetValue.textContent = padValue(result);
    circuitResultValue.textContent = padValue(circuitActive.target);
  } else {
    circuitResultValue.textContent = padValue(result);
  }
  circuitResultValue.classList.toggle('matched', result === circuitActive.target);
  circuitAttempts.textContent = `TENTATIVAS ${circuitActive.attempts}`;
  circuitAttempts.classList.toggle('danger', circuitActive.attempts <= 2);
}

function stopCircuit(success, reason) {
  if (!circuitActive) return;
  cancelAnimationFrame(circuitFrame);
  circuitActive = null;
  circuit.classList.add('hidden');
  postCircuit({ success, reason });
}

function animateCircuit() {
  if (!circuitActive) return;
  const remaining = (circuitActive.deadline - performance.now()) / 1000;
  circuitTime.textContent = clockText(remaining);
  if (remaining <= 0) return stopCircuit(false, 'tempo esgotado');
  circuitFrame = requestAnimationFrame(animateCircuit);
}

function startCircuit(options = {}) {
  const rowCount = clamp(Math.floor(Number(options.rows) || 3), 3, 5);
  const maxMultiplier = clamp(Math.floor(Number(options.maxMultiplier) || 5), 3, 9);
  const rows = Array.from({ length: rowCount }, () => ({
    base: 2 + Math.floor(Math.random() * 8),
    multiplier: 1,
    secret: 1 + Math.floor(Math.random() * maxMultiplier),
  }));
  const adjustCurrent = options.adjustCurrent === true;
  if (adjustCurrent) rows.forEach(row => { row.multiplier = row.base; row.base = 1 + Math.floor(Math.random() * maxMultiplier); });
  const targetValue = rows.reduce((total, row) => total + (adjustCurrent ? row.multiplier * row.secret : row.base * row.secret), 0);
  if (!adjustCurrent) rows.forEach(row => { row.multiplier = 1 + Math.floor(Math.random() * maxMultiplier); });
  if (rows.reduce((total, row) => total + (row.base * row.multiplier), 0) === targetValue) {
    const field = adjustCurrent ? 'base' : 'multiplier';
    rows[0][field] = (rows[0][field] % maxMultiplier) + 1;
  }
  circuitActive = {
    rows,
    adjustCurrent,
    target: targetValue,
    selected: 0,
    maxMultiplier,
    attempts: clamp(Math.floor(Number(options.maxAttempts) || 4), 1, 10),
    deadline: performance.now() + (clamp(Number(options.timeSeconds) || 45, 10, 180) * 1000),
  };
  circuitTitle.textContent = options.title || 'RECALIBRAR REDE';
  circuit.querySelector('.circuit-target small').textContent = adjustCurrent ? 'TENSAO ATUAL (AJUSTAVEL)' : 'TENSAO ALVO';
  circuit.querySelector('.circuit-result small').textContent = adjustCurrent ? 'RESULTADO NECESSARIO (FIXO)' : 'RESULTADO ATUAL';
  circuit.querySelector('.terminal-footer span').textContent = adjustCurrent ? '↑ ↓ circuito · ← → valor atual' : '↑ ↓ circuito · ← → multiplicador';
  circuitTargetValue.textContent = padValue(targetValue);
  renderCircuit();
  circuit.classList.remove('hidden');
  cancelAnimationFrame(circuitFrame);
  circuitFrame = requestAnimationFrame(animateCircuit);
}

const wireColors = ['#ef5350', '#42a5f5', '#ffca28', '#66bb6a', '#ab47bc', '#ff8a65', '#26c6da', '#ec407a'];

function stopWire(success, reason) {
  if (!wireActive) return;
  cancelAnimationFrame(wireFrame);
  wireActive = null;
  wire.classList.add('hidden');
  postWire({ success, reason });
}

function renderWire() {
  if (!wireActive) return;
  wireOrder.innerHTML = wireActive.sequence.map((number, index) => `<span class="${index < wireActive.position ? 'done' : index === wireActive.position ? 'current' : ''}" style="--wire:${wireColors[number - 1]}">${number}</span>`).join('');
  wireErrors.textContent = `FALHAS ${wireActive.mistakes} / ${wireActive.maxMistakes}`;
  wireErrors.classList.toggle('danger', wireActive.mistakes > 0);
}

function chooseWire(number) {
  if (!wireActive) return;
  if (number !== wireActive.sequence[wireActive.position]) {
    wireActive.mistakes += 1;
    wireBoard.querySelector(`[data-wire="${number}"]`)?.classList.add('error');
    setTimeout(() => wireBoard.querySelector(`[data-wire="${number}"]`)?.classList.remove('error'), 280);
    renderWire();
    if (wireActive.mistakes > wireActive.maxMistakes) stopWire(false, 'limite de falhas');
    return;
  }
  wireBoard.querySelector(`[data-wire="${number}"]`)?.classList.add('connected');
  wireActive.position += 1;
  renderWire();
  if (wireActive.position >= wireActive.sequence.length) stopWire(true, 'cabos conectados');
}

function animateWire() {
  if (!wireActive) return;
  const remaining = (wireActive.deadline - performance.now()) / 1000;
  wireTime.textContent = clockText(remaining);
  if (remaining <= 0) return stopWire(false, 'tempo esgotado');
  wireFrame = requestAnimationFrame(animateWire);
}

function startWire(options = {}) {
  const count = clamp(Math.floor(Number(options.wires) || 5), 3, 8);
  const sequence = Array.from({ length: count }, (_, index) => index + 1);
  for (let index = sequence.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(Math.random() * (index + 1));
    [sequence[index], sequence[swap]] = [sequence[swap], sequence[index]];
  }
  wireActive = { sequence, position: 0, mistakes: 0, maxMistakes: clamp(Math.floor(Number(options.maxMistakes) || 2), 0, 5), deadline: performance.now() + clamp(Number(options.timeSeconds) || 30, 8, 120) * 1000 };
  wireTitle.textContent = options.title || 'LIGAR CABOS';
  wireBoard.innerHTML = sequence.slice().sort(() => Math.random() - .5).map(number => `<button data-wire="${number}" style="--wire:${wireColors[number - 1]}"><i></i><b>${number}</b></button>`).join('');
  wireBoard.querySelectorAll('[data-wire]').forEach(button => button.onclick = () => chooseWire(Number(button.dataset.wire)));
  renderWire();
  wire.classList.remove('hidden');
  cancelAnimationFrame(wireFrame);
  wireFrame = requestAnimationFrame(animateWire);
}

window.addEventListener('message', event => {
  const message = event.data || {};
  if (message.action === 'close') {
    if (active) cancelAnimationFrame(frame);
    active = null;
    app.classList.add('hidden');
    return;
  }
  if (message.action === 'closePrecision') {
    cancelAnimationFrame(precisionFrame);
    precisionActive = null;
    precision.classList.add('hidden');
    return;
  }
  if (message.action === 'closeDataCrack') {
    cancelAnimationFrame(dataFrame);
    dataActive = null;
    dataCrack.classList.add('hidden');
    return;
  }
  if (message.action === 'closeCircuit') {
    cancelAnimationFrame(circuitFrame);
    circuitActive = null;
    circuit.classList.add('hidden');
    return;
  }
  if (message.action === 'closeWire') {
    cancelAnimationFrame(wireFrame);
    wireActive = null;
    wire.classList.add('hidden');
    return;
  }
  if (message.action === 'startDataCrack') {
    startDataCrack(message.options || {});
    return;
  }
  if (message.action === 'startCircuit') {
    startCircuit(message.options || {});
    return;
  }
  if (message.action === 'startWire') {
    startWire(message.options || {});
    return;
  }
  if (message.action === 'startPrecision') {
    precisionActive = { steps: Math.max(1, Number(message.steps) || 3), completed: 0, position: 0, target: 0, last: 0 };
    newPrecisionStep();
    precision.classList.remove('hidden');
    cancelAnimationFrame(precisionFrame);
    precisionFrame = requestAnimationFrame(animatePrecision);
    return;
  }
  if (message.action !== 'startKeypress') return;
  const options = message.options || {};
  title.textContent = options.title || 'AÇÃO';
  key.textContent = options.key || 'E';
  active = {
    steps: Math.max(1, Number(options.steps) || 3),
    speed: Math.max(.1, Number(options.speed) || 1),
    tolerance: Math.max(.03, Math.min(.35, Number(options.tolerance) || .14)) * 180,
    completed: 0,
    progress: 0,
    target: 0,
    last: 0
  };
  newStep();
  app.classList.remove('hidden');
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(animate);
});

document.addEventListener('keydown', event => {
  if (wireActive) {
    const pressed = event.key.toLowerCase();
    if (pressed === 'escape') { event.preventDefault(); stopWire(false, 'cancelado'); return; }
    const number = Number(pressed);
    if (number >= 1 && number <= wireActive.sequence.length) { event.preventDefault(); chooseWire(number); }
    return;
  }
  if (dataActive) {
    const pressed = event.key.toLowerCase();
    if (pressed === 'escape') { event.preventDefault(); stopDataCrack(false, 'cancelado'); return; }
    if (pressed === 'arrowleft' || pressed === 'a') { event.preventDefault(); selectNextDataBar(-1); return; }
    if (pressed === 'arrowright' || pressed === 'd') { event.preventDefault(); selectNextDataBar(1); return; }
    if (pressed !== 'e' && pressed !== ' ') return;
    event.preventDefault();
    const bar = dataActive.bars[dataActive.selected];
    if (!bar || bar.locked) return;
    if (Math.abs(bar.position - 0.5) > dataActive.tolerance) {
      dataActive.mistakes += 1;
      bar.element.classList.add('error');
      setTimeout(() => bar.element?.classList.remove('error'), 280);
      renderDataStatus();
      if (dataActive.mistakes > dataActive.maxMistakes) stopDataCrack(false, 'limite de falhas');
      return;
    }
    bar.locked = true;
    bar.position = 0.5;
    bar.element.classList.add('locked');
    renderDataStatus();
    if (dataActive.bars.every(entry => entry.locked)) return stopDataCrack(true, 'sincronizado');
    selectNextDataBar(1);
    return;
  }
  if (circuitActive) {
    const pressed = event.key.toLowerCase();
    if (pressed === 'escape') { event.preventDefault(); stopCircuit(false, 'cancelado'); return; }
    if (pressed === 'arrowup' || pressed === 'w') {
      event.preventDefault(); circuitActive.selected = (circuitActive.selected - 1 + circuitActive.rows.length) % circuitActive.rows.length; renderCircuit(); return;
    }
    if (pressed === 'arrowdown' || pressed === 's') {
      event.preventDefault(); circuitActive.selected = (circuitActive.selected + 1) % circuitActive.rows.length; renderCircuit(); return;
    }
    if (pressed === 'arrowleft' || pressed === 'a' || pressed === 'arrowright' || pressed === 'd') {
      event.preventDefault();
      const row = circuitActive.rows[circuitActive.selected];
      const direction = pressed === 'arrowleft' || pressed === 'a' ? -1 : 1;
      const field = circuitActive.adjustCurrent ? 'base' : 'multiplier';
      row[field] = ((row[field] - 1 + direction + circuitActive.maxMultiplier) % circuitActive.maxMultiplier) + 1;
      renderCircuit(); return;
    }
    if (pressed !== 'e' && pressed !== 'enter') return;
    event.preventDefault();
    if (circuitResult() === circuitActive.target) return stopCircuit(true, 'circuito estabilizado');
    circuitActive.attempts -= 1;
    circuitResultValue.classList.add('wrong');
    setTimeout(() => circuitResultValue?.classList.remove('wrong'), 300);
    if (circuitActive.attempts <= 0) return stopCircuit(false, 'limite de tentativas');
    renderCircuit();
    return;
  }
  if (precisionActive) {
    const pressed = event.key.toLowerCase();
    if (pressed === 'escape') { event.preventDefault(); stopPrecision(false); return; }
    if (pressed !== 'e') return;
    event.preventDefault();
    if (Math.abs(precisionActive.position - (precisionActive.target + 9)) > 11) return stopPrecision(false);
    precisionActive.completed += 1;
    if (precisionActive.completed >= precisionActive.steps) stopPrecision(true);
    else newPrecisionStep();
    return;
  }
  if (!active) return;
  const pressed = event.key.toLowerCase();
  if (pressed === 'escape') {
    event.preventDefault();
    stop(false, 'cancelado');
    return;
  }
  if (pressed !== 'e') return;
  event.preventDefault();
  if (angleDistance(active.progress, active.target) > active.tolerance) {
    stop(false, 'errou o momento');
    return;
  }
  active.completed += 1;
  if (active.completed >= active.steps) stop(true, 'concluido');
  else newStep();
});
