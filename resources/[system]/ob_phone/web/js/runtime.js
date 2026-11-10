// Eventos globais, chamadas, notificações e mensagens recebidas do Lua.

document.addEventListener(
  "click",
  (event) => {
    const response = event.target.closest?.("[data-share-response]");
    if (response) {
      event.preventDefault();
      respondShareRequest(response.dataset.shareResponse === "accept");
    }
  },
  true,
);
document.addEventListener(
  "pointerdown",
  (event) => {
    if (!opened || event.button !== 0) return;
    if (phone.contains(event.target)) {
      inputFocusMode = "phone";
      post("inputFocus", { mode: "phone" });
    } else {
      inputFocusMode = "game";
      if (document.activeElement instanceof HTMLElement)
        document.activeElement.blur();
      post("inputFocus", { mode: "game" });
    }
  },
  true,
);
document.addEventListener("focusin", (event) => {
  if (opened && event.target.matches?.("input,textarea,select")) {
    inputFocusMode = "typing";
    post("inputFocus", { mode: "typing" });
  }
});
document.addEventListener("focusout", () =>
  setTimeout(() => {
    if (
      opened &&
      inputFocusMode !== "game" &&
      !document.activeElement?.matches?.("input,textarea,select")
    ) {
      inputFocusMode = "phone";
      post("inputFocus", { mode: "phone" });
    }
  }, 0),
);
function ring() {
  clearInterval(ringTimer);
  ringTimer = null;
  if (!call || call.phase !== "ringing" || !call.incoming) return;
  const style = data.settings?.ringtone || "classic",
    tones =
      style === "digital"
        ? [980, 1240, 980]
        : style === "soft"
          ? [440, 520, 440]
          : [660, 880, 660];
  const beep = () => {
    try {
      audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
      if (audioContext.state === "suspended")
        audioContext.resume().catch(() => {});
      const time = audioContext.currentTime;
      tones.forEach((frequency, index) => {
        const offset = index * 0.25,
          oscillator = audioContext.createOscillator(),
          gain = audioContext.createGain();
        oscillator.frequency.value = frequency;
        gain.gain.setValueAtTime(0, time + offset);
        gain.gain.linearRampToValueAtTime(
          style === "soft" ? 0.025 : 0.045,
          time + offset + 0.02,
        );
        gain.gain.linearRampToValueAtTime(0, time + offset + 0.18);
        oscillator.connect(gain);
        gain.connect(audioContext.destination);
        oscillator.start(time + offset);
        oscillator.stop(time + offset + 0.2);
      });
    } catch {}
  };
  beep();
  ringTimer = setInterval(beep, 3500);
}
function refreshSnapshot(id, source) {
  if (id === "contacts")
    return JSON.stringify([source.ownerName, source.contacts || []]);
  if (id === "messages")
    return JSON.stringify([source.contacts || [], source.messages || []]);
  if (id === "obgram")
    return JSON.stringify([
      source.profile || {},
      source.posts || [],
      source.stories || [],
    ]);
  return "";
}
async function autoRefresh() {
  const selected = app,
    version = pageVersion,
    refreshable = ["contacts", "messages", "obgram"];
  if (
    autoRefreshing ||
    !opened ||
    !refreshable.includes(selected) ||
    document.activeElement?.matches("input,textarea,select") ||
    q(
      ".share-sheet,.media-viewer,.avatar-picker,.post-media-picker,.comments-sheet,.story-viewer,.ig-compose",
    )
  )
    return;
  autoRefreshing = true;
  try {
    const before = refreshSnapshot(selected, data),
      result = await post("refresh");
    if (!result.ok || version !== pageVersion || selected !== app) return;
    const next = { ...data, ...result.data },
      after = refreshSnapshot(selected, next);
    data = next;
    battery();
    if (before !== after) {
      if (selected === "messages" && messageGroup)
        await openMessageGroup(messageGroup);
      else await render(selected);
    }
  } finally {
    autoRefreshing = false;
  }
}
const towerIcon = '<div class="device-guard-tower"><svg viewBox="0 0 80 100"><path d="M40 8 18 92M40 8l22 84M25 66h30M30 45h20M34 27h12M12 29c-8 9-8 21 0 30M68 29c8 9 8 21 0 30M20 36c-4 5-4 12 0 17M60 36c4 5 4 12 0 17"/></svg></div>';
let deviceGuardSignature = "";
function updateSignalBars(strength) {
  document.querySelectorAll(".signal i").forEach((bar, index) => bar.classList.toggle("off", index >= Number(strength || 0)));
}
function updateDeviceGuard(device = {}) {
  data.device = {...(data.device || {}), ...device};
  updateSignalBars(device.signal);
  const guard = q("#deviceGuard");
  if (device.valid === false || Number(device.signal) <= 0) {
    const signature = "signal:" + String(device.valid !== false);
    if (deviceGuardSignature === signature) return;
    deviceGuardSignature = signature;
    document.querySelectorAll(".share-request,.share-sheet,.story-viewer,.media-viewer,.message-gallery,.avatar-picker").forEach((node) => node.remove());
    guard.innerHTML = '<div class="device-guard-card">' + towerIcon + '<h2>Sem Sinal</h2><p>' + (device.valid === false ? 'Este aparelho foi desativado porque o dono ativou um celular novo.' : 'Você está fora da área de cobertura.') + '</p></div>';
    guard.classList.remove("hidden"); return;
  }
  if (device.authorized) {
    deviceGuardSignature = "authorized";
    guard.classList.add("hidden");
    return;
  }
  const setup = device.setupRequired === true, locked = Number(device.lockedSeconds || 0);
  const signature = "pin:" + String(setup) + ":" + String(locked);
  if (deviceGuardSignature === signature) return;
  deviceGuardSignature = signature;
  guard.innerHTML = '<div class="device-guard-card"><h2>' + (setup ? 'Crie sua senha' : 'Celular bloqueado') + '</h2><p>' + (locked > 0 ? 'Tente novamente em ' + locked + ' segundos.' : setup ? 'Use uma senha de 4 a 6 dígitos.' : 'Digite a senha deste aparelho.') + '</p><div class="device-pin"><input id="devicePin" type="password" inputmode="numeric" maxlength="6" placeholder="Senha">' + (setup ? '<input id="devicePinConfirm" type="password" inputmode="numeric" maxlength="6" placeholder="Confirmar">' : '') + '<button id="deviceUnlock" ' + (locked > 0 ? 'disabled' : '') + '>' + (setup ? 'Criar senha' : 'Desbloquear') + '</button></div></div>';
  guard.classList.remove("hidden");
  q("#deviceUnlock").onclick = async () => {
    const result = await post("deviceAuth", {action:setup ? "setup" : "unlock",pin:q("#devicePin").value,confirmation:q("#devicePinConfirm")?.value});
    if (!result.ok) toast(result.message || "Senha incorreta.", false);
  };
}
function showSimPrompt(slot) {
  q(".sim-sheet")?.remove();
  document.body.insertAdjacentHTML("beforeend", '<section class="share-sheet sim-sheet"><header><b>Trocar número</b><button data-sim-close>×</button></header><p>Digite o número desejado.</p><input id="simNumber" inputmode="numeric" maxlength="16" placeholder="Novo número"><button class="action" id="confirmSim">Confirmar</button></section>');
  q("[data-sim-close]").onclick = () => q(".sim-sheet")?.remove();
  q("#confirmSim").onclick = async () => {
    const result = await post("deviceAuth", {action:"changeNumber",number:q("#simNumber").value,slot});
    toast(result.message || (result.ok ? "Número alterado." : "Número indisponível."), result.ok);
    if (result.ok) { q(".sim-sheet")?.remove(); refresh(); }
  };
}
const callIcons = {
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/></svg>',
  speaker:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M11 4 5 9H2v6h3l6 5V4ZM16 8a6 6 0 0 1 0 8M19 4a11 11 0 0 1 0 16"/></svg>',
  phone: uiIcon("phone"),
  video: uiIcon("video"),
  flip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 7h11a5 5 0 0 1 0 10H8M7 4 4 7l3 3M17 14l3 3-3 3"/></svg>',
};
function renderCall() {
  const screen = q("#callScreen"),
    pill = q("#callPill");
  pill.classList.toggle("hidden", !call || opened);
  if (!call) {
    screen.classList.add("hidden");
    delete screen.dataset.videoCall;
    window.OBVideoCall?.stop();
    return;
  }
  const name = contactName(call.number),
    active = call.phase === "active",
    video = call.video === true,
    label = video ? "chamada de vídeo" : "ligação",
    details = active
      ? '<small class="compact-call-details"><span>' +
        esc(name) +
        '</span><strong id="compactCallDuration">00:00</strong></small>'
      : "<small>" + esc(name) + " · pressione K para abrir</small>";
  pill.innerHTML =
    '<div class="compact-status"><b>OB</b><span>' +
    new Date().toLocaleTimeString("pt-BR", {
      hour: "2-digit",
      minute: "2-digit",
    }) +
    '</span></div><div class="compact-call"><span class="compact-call-icon">' +
    (video ? callIcons.video : callIcons.phone) +
    "</span><span><b>" +
    esc(
      active
        ? "Em " + label
        : call.incoming
          ? "Recebendo " + label
          : "Chamando por " + (video ? "vídeo" : "voz"),
    ) +
    "</b>" +
    details +
    "</span></div>";
  screen.classList.toggle("hidden", !opened || minimized);
  if (
    active &&
    video &&
    screen.dataset.videoCall === String(call.id) &&
    q("#localVideo")
  ) {
    q('[data-call="mute"]')?.classList.toggle("active", call.muted);
    q('[data-call="speaker"]')?.classList.toggle("active", call.speaker);
    q('[data-call="camera"]')?.classList.toggle(
      "active",
      call.camera === false,
    );
    q(".video-remote-off")?.classList.toggle(
      "hidden",
      call.remoteCamera !== false,
    );
    window.OBVideoCall?.setCamera(call.camera !== false);
    clock();
    return;
  }
  if (!(active && video)) window.OBVideoCall?.stop();
  screen.dataset.videoCall = active && video ? String(call.id) : "";
  if (active && video) {
    screen.innerHTML =
      '<div class="video-call-stage"><video id="remoteVideo" autoplay playsinline></video><div class="video-remote-off ' +
      (call.remoteCamera === false ? "" : "hidden") +
      '">' +
      avatar(name) +
      '<b>Câmera desligada</b></div><canvas id="localVideo"></canvas><div class="video-call-copy"><b>' +
      esc(name) +
      '</b><small id="videoCallStatus">Conectando vídeo…</small><small id="callDuration">00:00</small></div></div><div class="call-tools video-tools"><button class="call-control ' +
      (call.muted ? "active" : "") +
      '" data-call="mute"><span>' +
      callIcons.mic +
      '</span>Microfone</button><button class="call-control ' +
      (call.speaker ? "active" : "") +
      '" data-call="speaker"><span>' +
      callIcons.speaker +
      '</span>Viva-voz</button><button class="call-control ' +
      (call.camera === false ? "active" : "") +
      '" data-call="camera"><span>' +
      callIcons.video +
      '</span>Câmera</button><button class="call-control" data-call="flip"><span>' +
      callIcons.flip +
      '</span>Virar</button></div><div class="call-bottom video-bottom"><button class="call-control end" data-call="hangup"><span>' +
      callIcons.phone +
      "</span>Desligar</button></div>";
    requestAnimationFrame(() =>
      window.OBVideoCall?.start({
        callId: call.id,
        initiator: call.initiator === true,
        iceServers: data.publicConfig?.videoIceServers || [],
      }),
    );
    clock();
    return;
  }
  screen.innerHTML =
    '<p class="eyebrow">' +
    (active ? "CONECTADO" : video ? "CHAMADA DE VÍDEO" : "CHAMADA") +
    '</p><div class="call-avatar">' +
    esc(initials(name)) +
    '</div><h2 class="call-name">' +
    esc(name) +
    '</h2><p class="call-caption">' +
    esc(call.number) +
    '</p><p class="call-caption" id="callDuration">' +
    (active
      ? "00:00"
      : call.incoming
        ? video
          ? "Chamada de vídeo recebida…"
          : "Chamada recebida…"
        : video
          ? "Chamando por vídeo…"
          : "Chamando…") +
    "</p>" +
    (active
      ? '<div class="call-tools"><button class="call-control ' +
        (call.muted ? "active" : "") +
        '" data-call="mute"><span>' +
        callIcons.mic +
        "</span>" +
        (call.muted ? "Sem microfone" : "Silenciar") +
        '</button><button class="call-control ' +
        (call.speaker ? "active" : "") +
        '" data-call="speaker"><span>' +
        callIcons.speaker +
        "</span>Viva-voz</button></div>"
      : "") +
    '<div class="call-bottom">' +
    (!active && call.incoming
      ? '<button class="call-control answer" data-call="answer"><span>' +
        (video ? callIcons.video : callIcons.phone) +
        "</span>Atender</button>"
      : "") +
    '<button class="call-control end" data-call="hangup"><span>' +
    callIcons.phone +
    "</span>" +
    (active ? "Desligar" : "Recusar") +
    '</button></div><button class="call-minimize" data-call="minimize">Usar outros aplicativos</button>';
  clock();
}
function handleCallControl(event) {
  const button = event.target.closest("[data-call]");
  if (!button) return;
  const name = button.dataset.call;
  if (name === "minimize") {
    minimized = true;
    goHome();
    return;
  }
  if (call?.phase === "active" && call.video)
    setTimeout(() => {
      if (opened && call?.phase === "active" && call.video) {
        inputFocusMode = "game";
        post("inputFocus", { mode: "game" });
      }
    }, 60);
  if (name === "flip") {
    window.OBVideoCall?.flip();
    return;
  }
  action("callAction", {
    action: name,
    value:
      name === "speaker"
        ? !call?.speaker
        : name === "mute"
          ? !call?.muted
          : name === "camera"
            ? !call?.camera
            : undefined,
  });
}
q("#callScreen").addEventListener("click", handleCallControl);
q("#callPill").addEventListener("click", handleCallControl);
window.addEventListener("keydown", (event) => {
  if (!opened) return;
  const editing = /INPUT|TEXTAREA|SELECT/.test(event.target.tagName);
  if (event.key === "Escape" || (event.key.toLowerCase() === "k" && !editing)) {
    event.preventDefault();
    post("close");
    return;
  }
  if (
    app === "call" &&
    event.key === "Enter" &&
    q("#callNumber") &&
    (!call || minimized)
  ) {
    event.preventDefault();
    handlers.dial();
  }
});
window.addEventListener(
  "contextmenu",
  (event) => {
    if (opened && app === "camera") event.preventDefault();
  },
  true,
);
window.addEventListener("message", (event) => {
  if (event.data?.action === "close") {
    window.OBMediaCapture?.cancelAudio?.();
    clearAppAppearance();
  }
});
window.addEventListener("message", (event) => {
  const message = event.data || {};
  if (
    message.type === "ob-phone:input-focus" &&
    app &&
    catalog[app]?.external === true
  ) {
    inputFocusMode = message.mode === "typing" ? "typing" : "phone";
    post("inputFocus", { mode: inputFocusMode });
  }
  if (
    message.type === "ob-phone:event" &&
    app &&
    catalog[app]
  )
    post("externalAppEvent", {
      appId: app,
      event: message.event,
      payload: message.payload,
    });
  if (message.action === "open") {
    data = message.data || {};
    catalog = {};
    addCatalog(data.appCatalog || []);
    window.OBVideoIceServers = data.publicConfig?.videoIceServers || [];
    prefs = {
      case: data.defaults?.case || "blue",
      wallpaper: data.defaults?.wallpaper || "ocean",
      theme: "dark",
      ...saved(),
    };
    opened = true;
    inputFocusMode = "phone";
    phone.classList.remove("hidden");
    home.classList.add("hidden");
    view.classList.add("hidden");
    lock.classList.remove("hidden");
    app = "";
    pageVersion++;
    q("#number").textContent = data.number || "";
    battery();
    applyPrefs();
    call = data.call || null;
    minimized = false;
    if (call?.phase === "active")
      callSince = Date.now() - (call.elapsed || 0) * 1000;
    renderCall();
    clock();
    ring();
    updateDeviceGuard(data.device || {valid:true,authorized:true,signal:4});
    if (call?.phase === "active") {
      videoCallFreeLook = true;
      inputFocusMode = "game";
      post("inputFocus", { mode: "game" });
    }
  }
  if (message.action === "deviceState") updateDeviceGuard(message.device || {});
  if (message.action === "authorized") {
    data = {...data, ...(message.data || {})};
    q("#number").textContent = data.number || "";
    battery();
    updateDeviceGuard(data.device || {valid:true,authorized:true,signal:4});
    renderHomeApps();
  }
  if (message.action === "simPrompt") showSimPrompt(message.slot);
  if (message.action === "appCatalog") addCatalog(message.apps || []);
  if (message.action === "externalAppMessage" && catalog[message.appId]) {
    if (message.appId === emergencyAppId) updateEmergencyView(message.payload);
    else
      q("#externalApp")?.contentWindow?.postMessage(
        {
          type: "ob-phone:message",
          appId: message.appId,
          payload: message.payload,
        },
        "*",
      );
  }
  if (message.action === "close") {
    if (app === "camera") {
      clearTimeout(cameraVideoTimer);
      if (window.OBMediaCapture?.recording())
        window.OBMediaCapture.stopVideo().catch(() => {});
      window.OBMediaCapture?.stopView();
    }
    window.OBVideoCall?.stop();
    opened = false;
    deviceGuardSignature = "";
    q("#deviceGuard").innerHTML = "";
    inputFocusMode = "phone";
    clearTimeout(shareRequestTimer);
    clearInterval(nearbyRefreshTimer);
    clearTimeout(storyViewerTimer);
    q(".share-request")?.remove();
    phone.classList.add("hidden");
    pageVersion++;
    renderCall();
  }
  if (message.action === "inputFocus") inputFocusMode = message.mode || "phone";
  if (message.action === "battery") {
    data.battery = message.battery;
    battery();
  }
  if (message.action === "notification") {
    notifyBanner(message.text, message.kind);
    if (opened && app === "messages" && !q("#body")?.value) refresh();
    if (opened && app === "darkchat" && !q("#darkBody")?.value && darkGroup)
      openDarkGroup(darkGroup);
    if (
      opened &&
      app === "obgram" &&
      message.kind === "obgram" &&
      !q(".story-viewer,.ig-compose,.comments-sheet")
    )
      refresh();
  }
  if (message.action === "shareRequest") showShareRequest(message.request);
  if (message.action === "videoSignal")
    window.OBVideoCall?.signal(message.callId, message.payload);
  if (message.action === "callState") {
    const next = message.call;
    if (next && next.phase !== "ended" && !opened)
      q("#closedNotification").className = "closed-phone-card hidden";
    if (next?.ownNumber && data.number !== next.ownNumber) {
      data = { number: next.ownNumber };
      prefs = { case: "blue", wallpaper: "ocean", theme: "dark", ...saved() };
    }
    const enteringActiveVideo =
      next?.phase === "active" && call?.phase !== "active";
    if (!next || next.phase === "ended") {
      call = null;
      if (videoCallFreeLook) {
        videoCallFreeLook = false;
        if (opened) {
          inputFocusMode = "phone";
          post("inputFocus", { mode: "phone" });
        }
      }
      if (opened && next?.reason) notifyBanner(next.reason, "call");
    } else {
      const newCall = !call || next.id !== call.id;
      call = next;
      if (newCall) minimized = false;
      if (call.phase === "active")
        callSince = Date.now() - (call.elapsed || 0) * 1000;
      if (enteringActiveVideo && opened) {
        videoCallFreeLook = true;
        inputFocusMode = "game";
        post("inputFocus", { mode: "game" });
      }
    }
    renderCall();
    ring();
  }
});
