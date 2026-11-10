const root = document.getElementById('selector');
const list = document.getElementById('characters');
const progress = document.getElementById('progress');
const progressLabel = document.getElementById('progress-label');
const progressFill = document.getElementById('progress-fill');

const post = (eventName, data = {}) => fetch(`https://${GetParentResourceName()}/${eventName}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(data),
});

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
})[character]);

function render(characters, maxSlots) {
  list.replaceChildren();
  const bySlot = new Map(characters.map((character) => [Number(character.slot), character]));

  for (let slot = 1; slot <= maxSlots; slot += 1) {
    const character = bySlot.get(slot);
    const button = document.createElement('button');
    button.className = `character ${character ? '' : 'empty'}`;
    button.type = 'button';

    if (character) {
      button.innerHTML = `<span class="slot">PERSONAGEM ${slot}</span><strong>${escapeHtml(character.firstname)} ${escapeHtml(character.lastname)}</strong><span>${escapeHtml(character.nationality || 'Sem nacionalidade')}</span>`;
      button.addEventListener('click', () => post('selectCharacter', { userId: character.userId }));
    } else {
      button.innerHTML = `<span class="plus">+</span><strong>Criar personagem</strong><span>Slot ${slot} disponivel</span>`;
      button.addEventListener('click', () => post('createCharacter', { slot }));
    }
    list.append(button);
  }
}

function setProgress(open, label, duration) {
  if (!open) {
    progress.classList.add('hidden');
    progressFill.style.transition = 'none';
    progressFill.style.width = '0%';
    return;
  }
  progressLabel.textContent = label || 'Processando...';
  progress.classList.remove('hidden');
  progressFill.style.transition = 'none';
  progressFill.style.width = '0%';
  requestAnimationFrame(() => requestAnimationFrame(() => {
    progressFill.style.transition = `width ${Math.max(1, Number(duration) || 1)}ms linear`;
    progressFill.style.width = '100%';
  }));
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    root.classList.remove('hidden');
    render(data.characters || [], Number(data.maxSlots) || 1);
    post('selectorReady');
  }
  if (data.action === 'close') root.classList.add('hidden');
  if (data.action === 'progress') setProgress(data.open === true, data.label, data.duration);
});
