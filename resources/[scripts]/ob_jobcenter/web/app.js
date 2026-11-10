const app = document.getElementById('app');
const jobs = document.getElementById('jobs');
const statusCard = document.getElementById('status');
const confirmPanel = document.getElementById('confirm');
const confirmCopy = document.getElementById('confirm-copy');
const rules = document.getElementById('rules');
const agree = document.getElementById('agree');
const accept = document.getElementById('accept-confirm');
let state = null;
let pending = null;

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
}[char]));

const post = async (action, payload = {}) => {
    const response = await fetch(`https://${GetParentResourceName()}/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
    return response.json();
};

function duration(seconds) {
    seconds = Math.max(0, Number(seconds) || 0);
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.ceil((seconds % 3600) / 60);
    if (hours) return `${hours}h ${minutes}min`;
    return `${Math.max(1, minutes)}min`;
}

function renderStatus() {
    const current = state.current;
    statusCard.classList.toggle('blocked', Boolean(state.blacklist));
    if (current) {
        const leaveText = current.canLeaveHere
            ? current.remainingSeconds > 0 ? `Saída liberada em ${duration(current.remainingSeconds)}` : 'Saída voluntária disponível'
            : 'Este vínculo não pode ser encerrado nesta central';
        statusCard.innerHTML = `<div><strong>${escapeHtml(current.label)} · ${escapeHtml(current.rankLabel)}</strong><small>${escapeHtml(leaveText)}</small></div>
            ${current.canLeaveHere ? `<button class="button danger" data-leave ${current.remainingSeconds > 0 ? 'disabled' : ''}>Sair do trabalho</button>` : ''}`;
    } else if (state.blacklist) {
        statusCard.innerHTML = `<div><strong>Período de espera ativo</strong><small>${escapeHtml(state.blacklist.reason)} · termina em ${duration(state.blacklist.remainingSeconds)}</small></div>`;
    } else {
        statusCard.innerHTML = '<div><strong>Você está disponível para contratação</strong><small>Escolha abaixo uma organização legal.</small></div>';
    }
    statusCard.querySelector('[data-leave]')?.addEventListener('click', () => showConfirm('leave'));
}

function renderJobs() {
    jobs.innerHTML = (state.jobs || []).map(job => {
        const disabled = Boolean(state.current || state.blacklist || !job.available);
        const feedback = !job.available ? job.unavailableReason : state.current ? 'Saia do trabalho atual para trocar.' : state.blacklist ? 'Aguarde o fim do bloqueio.' : '';
        return `<article class="job ${job.available ? '' : 'unavailable'}">
            <span class="tag">${escapeHtml(job.tag || 'SERVIÇO PÚBLICO')}</span>
            <h2>${escapeHtml(job.label)}</h2>
            <p>${escapeHtml(job.description)}</p>
            <p class="rank">Cargo inicial: <strong>${escapeHtml(job.rankLabel)}</strong></p>
            <div class="feedback">${escapeHtml(feedback)}</div>
            <button class="button primary" data-job="${escapeHtml(job.key)}" ${disabled ? 'disabled' : ''}>Candidatar-se</button>
        </article>`;
    }).join('');
    jobs.querySelectorAll('[data-job]').forEach(button => button.addEventListener('click', () => showConfirm('join', button.dataset.job)));
}

function render() {
    renderStatus();
    renderJobs();
}

function showConfirm(action, jobKey) {
    pending = { action, jobKey };
    const job = (state.jobs || []).find(item => item.key === jobKey);
    confirmCopy.textContent = action === 'join'
        ? `Você está prestes a ingressar em ${job?.label || 'uma organização legal'}.`
        : `Você está prestes a sair de ${state.current?.label || 'seu trabalho'} e receberá 1 hora de espera.`;
    rules.innerHTML = (state.rules || []).map(rule => `<li>${escapeHtml(rule)}</li>`).join('');
    agree.checked = false;
    accept.disabled = true;
    confirmPanel.classList.remove('hidden');
}

function hideConfirm() {
    pending = null;
    confirmPanel.classList.add('hidden');
}

async function execute() {
    if (!pending || !agree.checked || accept.disabled) return;
    accept.disabled = true;
    const result = await post(pending.action, { jobKey: pending.jobKey });
    if (!result.ok) {
        accept.disabled = false;
        confirmCopy.textContent = result.error || 'Não foi possível concluir a operação.';
        return;
    }
    if (result.data) state = result.data;
    hideConfirm();
    render();
}

window.addEventListener('message', ({ data }) => {
    if (data?.action === 'open') {
        state = data.data;
        document.getElementById('title').textContent = data.title || 'Central de Empregos';
        app.classList.remove('hidden');
        app.setAttribute('aria-hidden', 'false');
        render();
    } else if (data?.action === 'close') {
        hideConfirm();
        app.classList.add('hidden');
        app.setAttribute('aria-hidden', 'true');
    }
});

agree.addEventListener('change', () => { accept.disabled = !agree.checked; });
accept.addEventListener('click', execute);
document.getElementById('cancel-confirm').addEventListener('click', hideConfirm);
document.getElementById('close').addEventListener('click', () => post('close'));
document.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    if (!confirmPanel.classList.contains('hidden')) hideConfirm();
    else post('close');
});
