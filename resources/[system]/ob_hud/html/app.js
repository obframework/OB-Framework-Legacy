const main = document.getElementById('main');
const vehicle = document.getElementById('vehicle');
const logo = document.getElementById('logo');
const minimapFrame = document.getElementById('minimap-frame');
const clock = document.getElementById('clock');
const ammoBox = document.getElementById('ammo-box');
const ammo = document.getElementById('ammo');
const voiceBox = document.getElementById('voice-box');
const voiceLevels = [...voiceBox.querySelectorAll('.voice-level i')];
const speed = document.getElementById('speed');
const unit = document.getElementById('unit');
const mileage = document.getElementById('mileage');
const gear = document.getElementById('gear');
const fuel = document.getElementById('fuel');
const engine = document.getElementById('engine');
const bodyHealth = document.getElementById('body-health');
const fuelFill = document.getElementById('fuel-fill');
const engineFill = document.getElementById('engine-fill');
const bodyFill = document.getElementById('body-fill');
const seatbelt = document.getElementById('seatbelt');
const flightKind = document.getElementById('flight-kind');
const flightSpeed = document.getElementById('flight-speed');
const flightAltitude = document.getElementById('flight-altitude');
const flightHeading = document.getElementById('flight-heading');
const flightAgl = document.getElementById('flight-agl');
const flightVspeed = document.getElementById('flight-vspeed');
const flightRpm = document.getElementById('flight-rpm');
const flightFuel = document.getElementById('flight-fuel');
const flightFuelReadout = flightFuel.parentElement;
const flightEngine = document.getElementById('flight-engine');
const flightAttitude = document.getElementById('flight-attitude');
const airspeedNeedle = document.getElementById('airspeed-needle');
const altitudeNeedle = document.getElementById('altitude-needle');
const attitudeHorizon = document.getElementById('attitude-horizon');
const settingsOverlay = document.getElementById('settings-overlay');
const settingsClose = document.getElementById('settings-close');
const settingsReset = document.getElementById('settings-reset');
const settingsStatus = document.getElementById('settings-status');
const settingsTabs = [...document.querySelectorAll('.settings-tab')];
const settingsPages = [...document.querySelectorAll('.settings-page')];
const settingChoices = [...document.querySelectorAll('[data-setting][data-value]')];
let selectedSettings = { theme: 'current', visualFilter: 'default', performancePreset: 'default' };
const statusBoxes = [...document.querySelectorAll('.status-box')].reduce((all, box) => {
  all[box.dataset.key] = box;
  return all;
}, {});

const colors = {
  health: ['#ff5965', '#cf1f35'],
  armor: ['#6ff7ff', '#2c9be8'],
  hunger: ['#ffdd6f', '#ffad3d'],
  thirst: ['#87d3ff', '#4179ff'],
  stamina: ['#5ff3e5', '#1686e8'],
};

const pct = (value) => Math.max(0, Math.min(100, Math.floor(Number(value) || 0)));
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, Number(value) || 0));

function renderFlight(flight, car) {
  const knots = Math.max(0, Math.floor(Number(flight.groundSpeed) || 0));
  const altitude = Math.max(0, Math.floor(Number(flight.altitude) || 0));
  const agl = Math.max(0, Math.floor(Number(flight.agl) || 0));
  const verticalSpeed = Math.floor(Number(flight.verticalSpeed) || 0);
  const heading = ((Math.floor(Number(flight.heading) || 0) % 360) + 360) % 360;
  const pitch = clamp(flight.pitch, -45, 45);
  const roll = clamp(flight.roll, -180, 180);

  flightKind.textContent = flight.kind === 'HELI' ? 'HELI' : 'PLANE';
  flightSpeed.textContent = String(knots).padStart(3, '0');
  flightAltitude.textContent = String(altitude).padStart(5, '0');
  flightHeading.textContent = `${String(heading).padStart(3, '0')}\u00B0`;
  flightAgl.textContent = `${agl} FT`;
  flightVspeed.textContent = `${verticalSpeed > 0 ? '+' : ''}${verticalSpeed} FPM`;
  flightRpm.textContent = `${pct(flight.rpm)}%`;
  const fuelPercent = pct(car.fuel);
  flightFuel.textContent = `${fuelPercent}%`;
  flightFuelReadout.style.setProperty('--flight-fuel', fuelPercent);
  flightFuelReadout.classList.toggle('warning', fuelPercent <= 30 && fuelPercent > 15);
  flightFuelReadout.classList.toggle('critical', fuelPercent <= 15);
  flightEngine.textContent = `${pct(car.engine)}%`;
  flightAttitude.textContent = `P ${Math.round(pitch)} / R ${Math.round(roll)}`;

  airspeedNeedle.style.transform = `translateX(-50%) rotate(${clamp(knots / 600, 0, 1) * 270 - 135}deg)`;
  altitudeNeedle.style.transform = `translateX(-50%) rotate(${(altitude % 1000) / 1000 * 360}deg)`;
  attitudeHorizon.style.setProperty('--pitch', `${pitch * 0.075}vh`);
  attitudeHorizon.style.setProperty('--roll', `${-roll}deg`);
}

function setTheme(theme) {
  const safeTheme = ['current', 'clean', 'racing'].includes(theme) ? theme : 'current';
  main.classList.remove('theme-current', 'theme-clean', 'theme-racing');
  main.classList.add(`theme-${safeTheme}`);
  selectedSettings.theme = safeTheme;
}

function renderSettings(settings = {}) {
  selectedSettings = { ...selectedSettings, ...settings };
  setTheme(selectedSettings.theme);
  settingChoices.forEach((choice) => {
    choice.classList.toggle('active', selectedSettings[choice.dataset.setting] === choice.dataset.value);
  });
}

async function nuiRequest(endpoint, payload = {}) {
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_hud';
  const response = await fetch(`https://${resource}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload),
  });
  return response.json();
}

function showSettingsStatus(message, error = false) {
  settingsStatus.textContent = message;
  settingsStatus.classList.toggle('error', error);
}

function closeSettings() {
  settingsOverlay.classList.add('hidden');
  nuiRequest('closeSettings').catch(() => {});
}

for (let index = 0; index < 12; index += 1) {
  const bar = document.createElement('i');
  bar.className = 'rpm-bar';
  document.getElementById('rpm-bars').append(bar);
}
const rpmBars = [...document.querySelectorAll('.rpm-bar')];

function setStatus(key, value) {
  const box = statusBoxes[key];
  if (!box) return;
  const safeValue = pct(value);
  box.querySelector('span').textContent = String(safeValue);
  box.style.setProperty('--pct', safeValue);
  box.style.setProperty('--grad-a', colors[key][0]);
  box.style.setProperty('--grad-b', colors[key][1]);
}

function toggleStatus(key, visible) {
  statusBoxes[key]?.classList.toggle('hidden', !visible);
}

function setRpm(value) {
  const active = Math.round((pct(value) / 100) * rpmBars.length);
  rpmBars.forEach((bar, index) => {
    bar.classList.toggle('on', index < active);
    bar.classList.toggle('danger', index >= rpmBars.length - 3 && index < active);
  });
}

window.addEventListener('message', ({ data = {} }) => {
  if (data.action === 'init') {
    unit.textContent = String(data.unit || 'kmh').toUpperCase().replace('KMH', 'KM/H');
    logo.src = `assets/${data.logoFile || 'logo.png'}`;
    setTheme(data.theme || 'current');
    setRpm(0);
    return;
  }

  if (data.action === 'theme') {
    setTheme(data.theme || 'current');
    renderSettings(selectedSettings);
    return;
  }

  if (data.action === 'settings') {
    settingsOverlay.classList.toggle('hidden', data.visible !== true);
    if (data.settings) renderSettings(data.settings);
    if (data.visible === true) showSettingsStatus('Configuracoes salvas neste computador.');
    return;
  }

  if (data.action === 'seatbelt') {
    seatbelt.classList.toggle('on', data.belted === true);
    seatbelt.classList.toggle('off', data.belted !== true);
    return;
  }

  if (data.action === 'player') {
    main.classList.toggle('hidden', !data.visible);
    if (!data.visible) {
      vehicle.classList.add('hidden');
      return;
    }

    const player = data.data || {};
    const bounds = player.minimapBounds;
    if (bounds && ['left', 'top', 'width', 'height'].every(key => Number.isFinite(bounds[key]))) {
      // A mascara define o recorte; a moldura acompanha os limites enviados.
      const frameLeft = bounds.left;
      const frameTop = bounds.top;
      const frameWidth = bounds.width;
      const frameHeight = bounds.height;
      Object.assign(minimapFrame.style, {
        left: `${frameLeft * 100}%`, top: `${frameTop * 100}%`,
        width: `${frameWidth * 100}%`, height: `${frameHeight * 100}%`,
        right: 'auto', bottom: 'auto',
      });
      main.style.setProperty('--radar-bottom', `${(bounds.top + bounds.height) * 100}vh`);
      main.style.setProperty('--radar-left', `${bounds.left * 100}vw`);
      main.style.setProperty('--radar-right', `${(1 - bounds.left - bounds.width) * 100}vw`);
    }
    const radarVisible = player.radarVisible === true || player.inVehicle === true;
    main.classList.toggle('radar-hidden', !radarVisible);
    minimapFrame.classList.toggle('hidden', !radarVisible);
    const voice = player.voice || {};
    voiceBox.classList.toggle('hidden', !player.voice);
    voiceBox.classList.toggle('talking', voice.talking === true);
    voiceBox.classList.toggle('radio-talking', voice.radioTalking === true);
    voiceBox.classList.toggle('offline', voice.ready !== true);
    const voiceMode = voice.ready === true ? Math.max(0, Math.min(3, Math.floor(Number(voice.mode) || 0))) : 0;
    voiceLevels.forEach((bar, index) => bar.classList.toggle('on', index < voiceMode));
    const voiceDistance = Math.max(0, Number(voice.distance) || 0);
    const voiceStatus = voice.ready !== true ? 'Voz desconectada' : voice.radioTalking ? 'Transmitindo no radio' : voice.talking ? 'Falando' : 'Microfone';
    voiceBox.title = `${voiceStatus}: ${voice.label || 'Voz'} (${voiceDistance} m) - HOME alterna / SHIFT+HOME diminui`;
    voiceBox.setAttribute('aria-label', voiceBox.title);
    setStatus('health', player.health);
    setStatus('armor', player.armor);
    setStatus('hunger', player.hunger);
    setStatus('thirst', player.thirst);
    setStatus('stamina', player.stamina);
    toggleStatus('armor', pct(player.armor) > 0);
    toggleStatus('stamina', player.showStamina === true);

    clock.textContent = /^\d{2}:\d{2}$/.test(String(player.gameTime)) ? player.gameTime : '00:00';
    ammoBox.classList.toggle('hidden', !player.showAmmo);
    if (player.showAmmo) {
      const clip = Math.max(0, Math.floor(Number(player.ammoClip) || 0));
      const reserve = Math.max(0, Math.floor(Number(player.ammoReserve) || 0));
      ammo.textContent = `${clip}/${reserve}`;
    }
    return;
  }

  if (data.action === 'vehicle') {
    vehicle.classList.toggle('hidden', !data.visible);
    if (!data.visible) return;

    const car = data.data || {};
    const isAircraft = car.flight?.active === true;
    vehicle.classList.toggle('aircraft', isAircraft);
    if (isAircraft) renderFlight(car.flight, car);
    const speedValue = Math.max(0, Math.floor(Number(car.speed) || 0));
    const fuelValue = pct(car.fuel);
    const engineValue = pct(car.engine);
    const bodyValue = pct(car.body);
    speed.textContent = String(speedValue).padStart(3, '0');
    gear.textContent = String(car.gear ?? 'R');
    // O painel e um odometro de sete digitos: ele volta para 0000000 apos
    // 9.999.999 km. O valor real nao e alterado aqui; permanece no ob_fuel e
    // pode ser consultado pelo leitor de odometro.
    const mileageValue = Math.max(0, Math.floor(Number(car.mileage) || 0));
    mileage.textContent = `${String(mileageValue % 10000000).padStart(7, '0')} km`;
    fuel.textContent = `${fuelValue}%`;
    engine.textContent = `${engineValue}%`;
    bodyHealth.textContent = `${bodyValue}%`;
    fuelFill.style.height = `${fuelValue}%`;
    engineFill.style.height = `${engineValue}%`;
    bodyFill.style.height = `${bodyValue}%`;
    seatbelt.classList.toggle('on', car.seatbelt === true);
    seatbelt.classList.toggle('off', car.seatbelt !== true);
    setRpm(car.rpm);
  }
});

settingsTabs.forEach((tab) => {
  tab.addEventListener('click', () => {
    settingsTabs.forEach((item) => item.classList.toggle('active', item === tab));
    settingsPages.forEach((page) => page.classList.toggle('active', page.dataset.page === tab.dataset.tab));
  });
});

settingChoices.forEach((choice) => {
  choice.addEventListener('click', async () => {
    const setting = choice.dataset.setting;
    const value = choice.dataset.value;
    const previous = { ...selectedSettings };
    renderSettings({ [setting]: value });
    showSettingsStatus('Aplicando configuracao...');
    try {
      const result = await nuiRequest('updateSettings', { [setting]: value });
      if (!result?.ok) throw new Error('rejected');
      renderSettings(result.settings || { [setting]: value });
      showSettingsStatus('Configuracao aplicada e salva.');
    } catch (_) {
      renderSettings(previous);
      showSettingsStatus('Nao foi possivel aplicar a configuracao.', true);
    }
  });
});

settingsClose.addEventListener('click', closeSettings);
settingsReset.addEventListener('click', async () => {
  showSettingsStatus('Restaurando configuracoes...');
  try {
    const result = await nuiRequest('resetSettings');
    if (!result?.ok) throw new Error('rejected');
    renderSettings(result.settings);
    showSettingsStatus('Configuracoes padrao restauradas.');
  } catch (_) {
    showSettingsStatus('Nao foi possivel restaurar as configuracoes.', true);
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !settingsOverlay.classList.contains('hidden')) closeSettings();
});

// Permite revisar o layout diretamente no navegador sem afetar a NUI do jogo.
const previewMode = new URLSearchParams(window.location.search).get('preview');
if (previewMode === 'settings' || previewMode === 'settings-graphics') {
  settingsOverlay.classList.remove('hidden');
  renderSettings(selectedSettings);
  if (previewMode === 'settings-graphics') settingsTabs.find((tab) => tab.dataset.tab === 'graphics')?.click();
} else if (['current', 'clean', 'racing'].includes(String(previewMode).replace('-hidden', ''))) {
  const previewTheme = String(previewMode).replace('-hidden', '');
  setTheme(previewTheme);
  window.dispatchEvent(new MessageEvent('message', { data: {
    action: 'player', visible: true, data: {
      health: 86, armor: 42, hunger: 71, thirst: 64, stamina: 58, showStamina: true,
      radarVisible: !String(previewMode).endsWith('-hidden'),
      showAmmo: true, ammoClip: 30, ammoReserve: 120, gameTime: '21:48',
      voice: { ready: true, talking: true, mode: 2, label: 'Normal', distance: 8 },
    },
  } }));
  window.dispatchEvent(new MessageEvent('message', { data: {
    action: 'vehicle', visible: true, data: {
      speed: 128, rpm: 74, gear: 4, fuel: 68, engine: 82, body: 57, mileage: 2481, seatbelt: true,
    },
  } }));
}
