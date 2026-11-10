const video = document.getElementById('background-video');
const music = document.getElementById('background-music');
const audioLabel = document.getElementById('audio-label');
const progressFill = document.getElementById('progress-fill');
const progressLabel = document.getElementById('progress-label');
const progressTrack = document.getElementById('progress-track');
const statusText = document.getElementById('status-text');

const statusByEvent = {
    startDataFileEntries: 'Carregando arquivos da cidade',
    performMapLoadFunction: 'Preparando Los Santos',
    startInitFunction: 'Iniciando sistemas',
    startInitFunctionOrder: 'Organizando recursos',
    initFunctionInvoking: 'Ativando recursos',
    endInitFunction: 'Finalizando conexao',
};

function setProgress(value) {
    const safeValue = Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
    const percentage = Math.round(safeValue * 100);

    progressFill.style.width = `${percentage}%`;
    progressLabel.textContent = `${percentage}%`;
    progressTrack.setAttribute('aria-valuenow', String(percentage));

    if (percentage >= 100) {
        statusText.textContent = 'Entrando na cidade';
    }
}

window.addEventListener('message', ({ data }) => {
    if (!data || typeof data.eventName !== 'string') return;

    if (data.eventName === 'loadProgress') {
        setProgress(Number(data.loadFraction));
        return;
    }

    const nextStatus = statusByEvent[data.eventName];
    if (nextStatus) statusText.textContent = nextStatus;
});

video.addEventListener('error', () => {
    video.hidden = true;
});

video.play().catch(() => {
    // O poster permanece visivel caso o Chromium ainda nao permita iniciar.
});

music.volume = 0.32;

function updateAudioLabel() {
    audioLabel.textContent = music.muted ? 'Ativar musica' : 'Silenciar musica';
}

function tryPlayMusic() {
    music.play().catch(() => {
        audioLabel.textContent = 'Pressione M para tocar';
    });
}

document.addEventListener('keydown', (event) => {
    if (event.repeat || event.code !== 'KeyM') return;

    if (music.paused) {
        music.muted = false;
        tryPlayMusic();
    } else {
        music.muted = !music.muted;
    }
    updateAudioLabel();
});

updateAudioLabel();
tryPlayMusic();
