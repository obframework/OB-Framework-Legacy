const toasts = document.querySelector('#toasts');
const panel = document.querySelector('#panel');
const list = document.querySelector('#list');
const closeButton = document.querySelector('#close');

function text(value) {
    return String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function post(name, payload = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    });
}

function addToast(call, seconds) {
    document.querySelector(`[data-toast-id="${Number(call.id)}"]`)?.remove();
    const element = document.createElement('article');
    element.className = `call p${Number(call.priority) || 1}`;
    element.dataset.toastId = Number(call.id);
    element.innerHTML = `<div class="top"><span class="code">${text(call.code)}</span><span class="priority">PRIORIDADE ${Number(call.priority) || 1}</span></div>
        <h2>${text(call.title)}</h2><p>${text(call.message)}</p>
        <div class="street"><span>LOCAL</span><strong>${text(call.street)}</strong></div>
        <div class="hint"><b>Y</b> Aceitar <span></span><b>N</b> Recusar</div>
        <i class="timer" style="animation-duration:${Math.max(3, Number(seconds) || 20)}s"></i>`;
    toasts.prepend(element);
    while (toasts.children.length > 4) toasts.lastElementChild.remove();
    setTimeout(() => dismissToast(call.id), Math.max(3, Number(seconds) || 20) * 1000);
}

function dismissToast(id) {
    const element = document.querySelector(`[data-toast-id="${Number(id)}"]`);
    if (!element) return;
    element.style.animation = 'leave .25s ease forwards';
    setTimeout(() => element.remove(), 260);
}

function renderPanel(calls) {
    list.innerHTML = '';
    if (!Array.isArray(calls) || calls.length === 0) {
        list.innerHTML = '<div class="empty">Nenhuma ocorrência ativa no momento.</div>';
        return;
    }
    calls.forEach(call => {
        const item = document.createElement('article');
        item.className = `panel-call p${Number(call.priority) || 1}`;
        item.innerHTML = `<div class="panel-code"><b>${text(call.code)}</b><span>PRIORIDADE ${Number(call.priority) || 1}</span></div>
            <div class="panel-content"><h2>${text(call.title)}</h2><p>${text(call.message)}</p><small>${text(call.street)}</small></div>
            <button class="route ${call.accepted ? 'selected' : ''}" type="button" data-route="${Number(call.id)}">${call.accepted ? 'Rota marcada' : (call.exclusive ? 'Aceitar chamado' : 'Marcar no GPS')}</button>`;
        list.appendChild(item);
    });
}

window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'alert' && data.call) addToast(data.call, data.cardDuration);
    if (data.action === 'accepted') {
        const element = document.querySelector(`[data-toast-id="${Number(data.id)}"]`);
        if (element) { element.classList.add('accepted'); element.querySelector('.hint').textContent = 'Rota marcada no GPS'; }
    }
    if (data.action === 'declined') dismissToast(data.id);
    if (data.action === 'remove') dismissToast(data.id);
    if (data.action === 'panel') {
        panel.classList.toggle('hidden', data.visible !== true);
        if (data.visible === true) renderPanel(data.calls);
    }
});

list.addEventListener('click', event => {
    const button = event.target.closest('[data-route]');
    if (!button) return;
    post('route', { id: Number(button.dataset.route) });
});
closeButton.addEventListener('click', () => post('close'));
document.addEventListener('keydown', event => { if (event.key === 'Escape') post('close'); });
