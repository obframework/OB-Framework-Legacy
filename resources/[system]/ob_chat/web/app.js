const composer = document.getElementById('composer');
const input = document.getElementById('input');
const messages = document.getElementById('messages');
const suggestionsElement = document.getElementById('suggestions');
const errorElement = document.getElementById('error');
let suggestions = [];
let filtered = [];
let selected = 0;
let history = [];
let historyIndex = 0;
let open = false;

const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
}[character]));

const post = async (action, payload = {}) => {
    const response = await fetch(`https://${GetParentResourceName()}/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
    return response.json();
};

function colour(value) {
    if (!Array.isArray(value) || value.length < 3) return '#32c5ff';
    const parts = value.slice(0, 3).map(entry => Math.max(0, Math.min(255, Number(entry) || 0)));
    return `rgb(${parts.join(',')})`;
}

function renderSuggestions() {
    const term = input.value.replace(/^\//, '').split(/\s/, 1)[0].toLowerCase();
    filtered = suggestions.filter(item => !term || item.command.toLowerCase().startsWith(term)).slice(0, 8);
    selected = Math.max(0, Math.min(selected, filtered.length - 1));
    suggestionsElement.innerHTML = filtered.map((item, index) => `<div class="suggestion ${index === selected ? 'selected' : ''}" data-index="${index}">
        <span class="command">/${escapeHtml(item.command)}</span><span class="arguments">${escapeHtml(item.arguments || '')}</span>
        <span class="description">${escapeHtml(item.description || '')}</span>
    </div>`).join('');
    suggestionsElement.querySelectorAll('[data-index]').forEach(element => element.addEventListener('mousedown', event => {
        event.preventDefault();
        complete(Number(element.dataset.index));
    }));
}

function complete(index = selected) {
    const item = filtered[index];
    if (!item) return;
    input.value = `/${item.command} `;
    selected = index;
    renderSuggestions();
    input.focus();
}

function addMessage(data, lifetime, maximum) {
    const item = document.createElement('article');
    item.className = 'message';
    item.style.setProperty('--accent', colour(data.colour || data.color));
    const details = [data.department, data.rank].filter(Boolean).join(' · ');
    item.innerHTML = `<div class="message-head">
        ${data.channel ? `<span class="channel">${escapeHtml(data.channel)}</span>` : ''}
        ${data.author ? `<span class="author">${escapeHtml(data.author)}</span>` : ''}
        ${details ? `<span class="department">${escapeHtml(details)}</span>` : ''}
    </div><div class="message-body">${escapeHtml(data.message || '')}</div>`;
    messages.appendChild(item);
    while (messages.children.length > (Number(maximum) || 40)) messages.firstElementChild.remove();
    const delay = Math.max(3000, Number(lifetime) || 12000);
    const expire = () => {
        if (!item.isConnected) return;
        if (open) {
            setTimeout(expire, 1000);
            return;
        }
        item.classList.add('expiring');
        setTimeout(() => item.remove(), 400);
    };
    setTimeout(expire, delay);
}

async function submit() {
    const value = input.value.trim();
    if (!value.startsWith('/')) {
        errorElement.textContent = 'Somente comandos iniciados por / são permitidos.';
        return;
    }
    const result = await post('submit', { value });
    if (!result.ok) {
        errorElement.textContent = result.error || 'Comando inválido.';
        return;
    }
    if (value && history[history.length - 1] !== value) history.push(value);
    history = history.slice(-30);
    historyIndex = history.length;
}

input.addEventListener('input', () => {
    errorElement.textContent = '';
    if (!input.value.startsWith('/')) input.value = `/${input.value.replace(/^\/+/, '')}`;
    selected = 0;
    renderSuggestions();
});

input.addEventListener('keydown', event => {
    if (event.key === 'Escape') { event.preventDefault(); post('close'); return; }
    if (event.key === 'Enter') { event.preventDefault(); submit(); return; }
    if (event.key === 'Tab') { event.preventDefault(); complete(); return; }
    if (event.key === 'ArrowDown' && filtered.length) {
        event.preventDefault(); selected = (selected + 1) % filtered.length; renderSuggestions(); return;
    }
    if (event.key === 'ArrowUp' && filtered.length && input.value.split(/\s/).length === 1) {
        event.preventDefault(); selected = (selected - 1 + filtered.length) % filtered.length; renderSuggestions(); return;
    }
    if (event.key === 'ArrowUp' && history.length) {
        event.preventDefault(); historyIndex = Math.max(0, historyIndex - 1); input.value = history[historyIndex]; renderSuggestions();
    } else if (event.key === 'ArrowDown' && history.length) {
        event.preventDefault(); historyIndex = Math.min(history.length, historyIndex + 1); input.value = history[historyIndex] || '/'; renderSuggestions();
    }
});

window.addEventListener('message', ({ data }) => {
    if (data?.action === 'open') {
        open = true;
        suggestions = Array.isArray(data.suggestions) ? data.suggestions : [];
        input.value = '/';
        errorElement.textContent = '';
        selected = 0;
        composer.classList.remove('hidden');
        renderSuggestions();
        requestAnimationFrame(() => input.focus());
    } else if (data?.action === 'close') {
        open = false;
        composer.classList.add('hidden');
    } else if (data?.action === 'message' && data.message) {
        addMessage(data.message, data.lifetime, data.maximum);
    } else if (data?.action === 'clear') {
        messages.replaceChildren();
    }
});
