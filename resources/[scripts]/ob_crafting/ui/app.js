const app = document.querySelector('#app');
const recipes = document.querySelector('#recipes');
let payload = null;

const post = (name, data = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
}).then(response => response.json());

function render(data) {
    payload = data;
    const progression = data.progression !== false;
    app.classList.toggle('private-mode', !progression);
    document.querySelector('#mode').textContent = progression ? 'BANCADA PUBLICA' : 'ACESSO PRIVADO';
    document.querySelector('#station').textContent = data.station.label;
    document.querySelector('#category').textContent = data.station.category;
    document.querySelector('.level').classList.toggle('hidden', !progression);
    document.querySelector('#level').textContent = data.profile.level;
    document.querySelector('#xp').textContent = `${data.profile.xpInLevel} / ${data.profile.xpRequired} XP`;
    document.querySelector('#xpbar').style.width = `${Math.min(100, data.profile.xpInLevel / data.profile.xpRequired * 100)}%`;
    document.querySelector('#crafts').textContent = data.profile.crafts;
    document.querySelector('#successes').textContent = data.profile.successes;
    document.querySelector('#batch').textContent = `1–${data.maxBatch}`;
    recipes.innerHTML = '';

    data.recipes.forEach(recipe => {
        const locked = progression && (!recipe.unlocked || data.profile.level < recipe.level);
        const card = document.createElement('article');
        card.className = `recipe${locked ? ' locked' : ''}`;
        const ingredients = recipe.ingredients.map(ingredient =>
            `<span class="ingredient ${ingredient.owned < ingredient.amount ? 'missing' : ''}">${ingredient.label} ${ingredient.owned}/${ingredient.amount}</span>`
        ).join('');
        const badge = progression ? `Nivel ${recipe.level} · ${recipe.chance}%` : `${recipe.chance}% de sucesso`;
        card.innerHTML = `<header><h3>${recipe.label}</h3><span class="badge">${badge}</span></header>` +
            `<div class="ingredients">${ingredients}</div>` +
            `${progression && recipe.blueprint && !recipe.unlocked ? '<p>🔒 Projeto necessario</p>' : ''}` +
            `<div class="foot"><input type="number" min="1" max="${data.maxBatch}" value="1">` +
            `<button ${(!recipe.canCraft || locked) ? 'disabled' : ''}>Fabricar</button></div>`;
        card.querySelector('button').onclick = async () => {
            const amount = Number(card.querySelector('input').value) || 1;
            const result = await post('craft', { recipe: recipe.id, amount });
            if (!result.ok) {
                card.querySelector('button').textContent = result.message || 'Indisponivel';
                setTimeout(() => render(payload), 1800);
            }
        };
        recipes.appendChild(card);
    });
}

window.addEventListener('message', event => {
    if (event.data.action === 'open') {
        app.classList.remove('hidden');
        render(event.data.payload);
    }
    if (event.data.action === 'close') app.classList.add('hidden');
});
document.querySelector('#close').onclick = () => post('close');
document.addEventListener('keyup', event => { if (event.key === 'Escape') post('close'); });

