const services = [...document.querySelectorAll('[data-service]')];
const message = document.querySelector('#message');
const send = document.querySelector('#send');
const status = document.querySelector('#status');
let selected = '';
let busy = false;

const setPhoneInputMode = mode => window.parent.postMessage({
    type: 'ob-phone:input-focus', mode,
}, '*');

document.addEventListener('focusin', event => {
    if (event.target.matches('input, textarea, select')) setPhoneInputMode('typing');
});

document.addEventListener('focusout', () => setTimeout(() => {
    if (!document.activeElement?.matches('input, textarea, select')) setPhoneInputMode('phone');
}, 0));

document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'a' &&
        event.target.matches('input, textarea')) {
        event.stopPropagation();
    }
});

services.forEach(button => button.addEventListener('click', () => {
    if (busy) return;
    selected = button.dataset.service;
    services.forEach(entry => entry.classList.toggle('selected', entry === button));
    send.disabled = false;
    status.textContent = '';
}));

send.addEventListener('click', () => {
    if (!selected || busy) return;
    busy = true;
    send.disabled = true;
    window.parent.postMessage({
        type: 'ob-phone:event', event: 'request',
        payload: { service: selected, message: message.value.trim() },
    }, '*');
});

window.addEventListener('message', event => {
    const data = event.data;
    if (data?.type === 'ob-phone:ready') document.documentElement.dataset.theme = data.theme;
    if (data?.type !== 'ob-phone:message') return;
    const payload = data.payload || {};
    if (payload.state === 'sending') status.textContent = 'Enviando sua localização...';
    if (payload.state === 'sent') {
        busy = false;
        status.textContent = payload.message || 'Chamado enviado. Aguarde no local.';
        status.className = 'success';
        message.value = '';
    }
    if (payload.state === 'error') {
        busy = false;
        status.textContent = payload.message || 'Não foi possível enviar o chamado.';
        status.className = 'error';
    }
    send.disabled = !selected || busy;
});
