const root = document.getElementById('multichar');
const slotsRoot = document.getElementById('slots');
const nameEl = document.getElementById('name');
const slotEl = document.getElementById('slot');
const genderEl = document.getElementById('gender');
const birthdateEl = document.getElementById('birthdate');
const nationalityEl = document.getElementById('nationality');
const playLabel = document.getElementById('play-label');
const playButton = document.getElementById('play');

let selectedSlot = 1;
let characters = [];
let unlockedSlots = 1;

const post = (name, data = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(data),
});

const characterAt = (slot) => characters.find((character) => Number(character.slot) === Number(slot));

function showDetails(details = {}) {
  nameEl.textContent = details.name || 'Novo personagem';
  slotEl.textContent = `0${details.slot || 1}`.slice(-2);
  genderEl.textContent = details.gender || '--';
  birthdateEl.textContent = details.birthdate || '--';
  nationalityEl.textContent = details.nationality || 'Disponivel';
  playLabel.textContent = details.empty ? 'CRIAR PERSONAGEM' : 'JOGAR COM PERSONAGEM';
}

function render(maxSlots) {
  slotsRoot.replaceChildren();
  for (let slot = 1; slot <= maxSlots; slot += 1) {
    const character = characterAt(slot);
    const unlocked = Boolean(character) || slot <= unlockedSlots;
    const button = document.createElement('button');
    button.className = `slot ${slot === selectedSlot ? 'active' : ''} ${character ? '' : 'empty'} ${unlocked ? '' : 'locked'}`;
    button.type = 'button';
    button.disabled = !unlocked;
    button.innerHTML = !unlocked
      ? `<span class="lock">🔒</span><small>SLOT ${String(slot).padStart(2, '0')}</small><strong>Bloqueado</strong>`
      : character
      ? `<small>SLOT ${String(slot).padStart(2, '0')}</small><strong>${character.firstname} ${character.lastname}</strong><span>${Number(character.gender) === 1 ? '♀' : '♂'}</span>`
      : `<span class="plus">+</span><small>SLOT ${String(slot).padStart(2, '0')}</small><strong>Novo personagem</strong>`;
    button.addEventListener('click', () => {
      selectedSlot = slot;
      render(maxSlots);
      post('preview', { slot });
    });
    slotsRoot.append(button);
  }
}

playButton.addEventListener('click', () => post('play', { slot: selectedSlot }));

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'close') root.classList.add('hidden');
  if (data.action === 'open') {
    characters = data.characters || [];
    selectedSlot = Number(data.selectedSlot) || 1;
    unlockedSlots = Number(data.unlockedSlots) || 1;
    render(Number(data.maxSlots) || 1);
    showDetails(data.details);
    root.classList.remove('hidden');
  }
  if (data.action === 'select') {
    selectedSlot = Number(data.selectedSlot) || 1;
    const maxSlots = slotsRoot.children.length || 1;
    render(maxSlots);
    showDetails(data.details);
  }
});
