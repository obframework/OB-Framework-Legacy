// Estado compartilhado, utilitários, preferências e tela inicial do telefone.

const q = (s) => document.querySelector(s),
  phone = q("#phone"),
  home = q("#home"),
  view = q("#view"),
  lock = q("#lock"),
  content = q("#content");
const esc = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const money = (v) =>
  window.OBCurrency?.format(v) ?? "$ " + Number(v || 0).toLocaleString("pt-BR");
const coreApps = {
  call: { name: "Telefone", icon: "phone.webp", system: true },
  messages: { name: "Mensagens", icon: "messages.svg", system: true },
  contacts: { name: "Contatos", icon: "contacts.svg", system: true },
  bank: { name: "Banco", icon: "bank.webp", system: true },
  garage: { name: "Garagem", icon: "garage.webp", system: true },
  camera: { name: "Câmera", icon: "camera.svg", system: true },
  photos: { name: "Galeria", icon: "photos.svg", system: true },
  obgram: { name: "Obgram", icon: "social.webp", system: true },
  calc: { name: "Calculadora", icon: "calculator.webp", system: true },
  notes: { name: "Notas", icon: "notes.webp", system: true },
  store: { name: "OB Store", icon: "store.svg", system: true },
  settings: { name: "Ajustes", icon: "settings.webp", system: true },
};
const uiIcon = (name) =>
  ({
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg>',
    plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    compose:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13.5 6.5 17.5 10.5M4 20l4.3-1 10-10a2.8 2.8 0 0 0-4-4l-10 10L4 20Z"/></svg>',
    group:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8" r="3"/><path d="M3.5 19c.4-4 2.2-6 5.5-6s5.1 2 5.5 6M15 7.5a2.5 2.5 0 0 1 0 5M16 14c2.7.3 4 2 4.5 5"/></svg>',
    send: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 14-7-5 14-2.5-5.5L5 12Z"/><path d="m11.5 13.5 3-3"/></svg>',
    pin: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></svg>',
    phone:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.6 2.8 9.4 8l-2.2 2.2a16 16 0 0 0 6.6 6.6l2.2-2.2 5.2 2.8v2.5a2 2 0 0 1-2.2 2C9.8 20.8 3.2 14.2 2.1 5A2 2 0 0 1 4.1 2.8h2.5Z"/></svg>',
    video:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="6" width="13" height="12" rx="3"/><path d="m16 10 5-3v10l-5-3Z"/></svg>',
    message:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H9l-5 4v-4a2 2 0 0 1-1-2V7a2 2 0 0 1 2-2Z"/></svg>',
    settings:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19 13.5v-3l-2-.7a7 7 0 0 0-.8-1.8l.9-2-2.1-2.1-2 .9a7 7 0 0 0-1.8-.8l-.7-2h-3l-.7 2a7 7 0 0 0-1.8.8l-2-.9L.9 6l.9 2A7 7 0 0 0 1 9.8l-2 .7v3l2 .7a7 7 0 0 0 .8 1.8l-.9 2L3 20.1l2-.9a7 7 0 0 0 1.8.8l.7 2h3l.7-2a7 7 0 0 0 1.8-.8l2 .9 2.1-2.1-.9-2a7 7 0 0 0 .8-1.8l2-.7Z" transform="translate(2) scale(.83)"/></svg>',
  })[name] || "";
coreApps.darkchat = {
  name: "DarkChat",
  icon: "darkchat.svg",
  system: true,
  defaultInstalled: false,
  removable: true,
  description: "Rede privada por convite para grupos anônimos.",
  developer: "OB",
  version: "1.0.0",
};
const cases = {
    blue: "Azul",
    black: "Preto",
    cyan: "Ciano",
    white: "Branco",
    purple: "Roxo",
  },
  walls = { ocean: "Oceano", midnight: "Noturno", sky: "Sky" };
let data = {},
  catalog = {},
  app = "",
  thread = null,
  call = null,
  minimized = false,
  prefs = {},
  pageVersion = 0,
  toastTimer,
  startY = 0,
  callSince = 0,
  expression = "",
  ringTimer,
  audioContext,
  opened = false,
  autoRefreshing = false,
  cameraMode = "photo",
  cameraFront = false,
  cameraLandscape = false,
  cameraVideoTimer,
  cameraRecordingTimer,
  cameraRecordingStarted = 0,
  cameraCaptureBusy = false,
  obgramTab = "home",
  obgramCompose = false,
  storyViewerState = null,
  storyViewerTimer,
  galleryAlbum = "all",
  avatarAlbum = "all",
  avatarEdit = null,
  avatarTarget = "obgram",
  obgramMediaId = null,
  postMediaAlbum = "all";
let darkGroup = null,
  darkState = null,
  messageAttachOpen = false,
  messageGroup = null,
  messageGroupState = null,
  inputFocusMode = "phone",
  videoCallFreeLook = false;
let contactView = null,
  contactShare = null,
  shareAllRecipients = false,
  nearbyShare = [],
  nearbyRefreshTimer;
const pending = new Set();
function storageKey() {
  return "ob_phone:v2:" + (data.number || "default");
}
function saved() {
  try {
    return JSON.parse(localStorage.getItem(storageKey())) || {};
  } catch {
    return {};
  }
}
function savePrefs() {
  try {
    localStorage.setItem(storageKey(), JSON.stringify(prefs));
  } catch {
    toast("Não foi possível salvar no aparelho.", "error");
  }
}
function applyPrefs() {
  q("#caseFrame").src =
    "assets/case-" + (cases[prefs.case] ? prefs.case : "blue") + ".webp";
  q(".screen").dataset.wallpaper = walls[prefs.wallpaper]
    ? prefs.wallpaper
    : "ocean";
  phone.classList.toggle("light", prefs.theme === "light");
}
async function post(name, body = {}) {
  const abort = new AbortController(),
    timeout = setTimeout(() => abort.abort(), 30000);
  try {
    const response = await fetch(
      "https://" + GetParentResourceName() + "/" + name,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: abort.signal,
      },
    );
    return await response.json();
  } catch {
    return {
      ok: false,
      message: "O celular não recebeu resposta. Tente novamente.",
    };
  } finally {
    clearTimeout(timeout);
  }
}
function toast(text, kind = "info") {
  if (!text) return;
  q("#toast").textContent = text;
  q("#toast").className = kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (q("#toast").className = "hidden"), 3500);
}
let notificationTimer, closedNotificationTimer, shareRequestTimer;
function notifyBanner(text, kind = "phone") {
  if (!text) return;
  const titles = {
      messages: "Mensagens",
      darkchat: "DarkChat",
      obgram: "Obgram",
      call: "Telefone",
      phone: "Celular",
    },
    markup =
      "<i></i><span><b>" +
      esc(titles[kind] || "Celular") +
      "</b><small>" +
      esc(text) +
      "</small></span>";
  if (opened) {
    const banner = q("#notificationBanner");
    banner.innerHTML = markup;
    banner.className = kind;
    clearTimeout(notificationTimer);
    notificationTimer = setTimeout(() => (banner.className = "hidden"), 4500);
  } else {
    const card = q("#closedNotification");
    card.innerHTML =
      '<div class="compact-status"><b>OB</b><span>' +
      new Date().toLocaleTimeString("pt-BR", {
        hour: "2-digit",
        minute: "2-digit",
      }) +
      '</span></div><div class="compact-alert ' +
      esc(kind) +
      '">' +
      markup +
      "</div>";
    card.className = "closed-phone-card " + kind;
    clearTimeout(closedNotificationTimer);
    closedNotificationTimer = setTimeout(
      () => (card.className = "closed-phone-card hidden"),
      5500,
    );
  }
}
function showShareRequest(request) {
  if (!opened || !request?.token) return;
  q(".share-request")?.remove();
  clearTimeout(shareRequestTimer);
  q(".screen").insertAdjacentHTML(
    "beforeend",
    '<section class="share-request" data-share-token="' +
      Number(request.token) +
      '"><div class="share-request-icon">' +
      avatar(request.name || "Contato") +
      "</div><small>" +
      esc(request.senderName || "Uma pessoa próxima") +
      " quer compartilhar</small><h3>" +
      esc(request.name || "Novo contato") +
      "</h3><p>" +
      esc(request.number || "") +
      '</p><div><button class="reject" data-share-response="reject">Recusar</button><button class="accept" data-share-response="accept">Aceitar</button></div></section>',
  );
  shareRequestTimer = setTimeout(
    () => q(".share-request")?.remove(),
    Math.max(5, Number(request.expiresIn) || 20) * 1000,
  );
}
async function respondShareRequest(accepted) {
  const sheet = q(".share-request"),
    token = Number(sheet?.dataset.shareToken);
  if (!token) return;
  clearTimeout(shareRequestTimer);
  sheet.remove();
  const result = await post("shareNumberResponse", { token, accepted }),
    message =
      result.message ||
      (accepted ? "Contato adicionado." : "Solicitação recusada.");
  if (result.ok) notifyBanner(message, "phone");
  else toast(message, "error");
  if (result.ok && accepted) {
    const refreshed = await post("refresh");
    if (refreshed.ok) {
      data = { ...data, ...refreshed.data };
      if (opened && app === "contacts") content.innerHTML = contactsV3();
    }
  }
}
async function action(name, body, after) {
  if (pending.has(name)) return;
  pending.add(name);
  try {
    const result = await post(name, body);
    if (!result.ok && typeof result.message === "string")
      toast(result.message, "error");
    if (result.ok && after) await after(result);
    return result;
  } finally {
    pending.delete(name);
  }
}
function battery() {
  const value = Math.max(0, Math.min(100, Number(data.battery) || 0)),
    fill = q("#batteryFill");
  q("#battery").textContent = value + "%";
  fill.style.width = value + "%";
  fill.classList.toggle("low", value < 20);
}
function clock() {
  const now = new Date(),
    time = now.toLocaleTimeString("pt-BR", {
      hour: "2-digit",
      minute: "2-digit",
    });
  ["#clock", "#time", "#lockTime"].forEach((id) => (q(id).textContent = time));
  document
    .querySelectorAll(".date")
    .forEach(
      (el) =>
        (el.textContent = now.toLocaleDateString("pt-BR", {
          weekday: "long",
          day: "numeric",
          month: "long",
        })),
    );
  if (call?.phase === "active") {
    const seconds = Math.max(0, Math.floor((Date.now() - callSince) / 1000)),
      duration =
        String(Math.floor(seconds / 60)).padStart(2, "0") +
        ":" +
        String(seconds % 60).padStart(2, "0");
    ["#callDuration", "#compactCallDuration"].forEach((id) => {
      const node = q(id);
      if (node) node.textContent = duration;
    });
  }
}
function addCatalog(list = []) {
  for (const item of list)
    if (item?.id && item?.name && item?.icon && item?.entry)
      catalog[item.id] = item;
  if (opened && !app) renderHomeApps();
}
function appMode(id) {
  return String(data.publicConfig?.apps?.[id] || "default").toLowerCase();
}
function isInstalled(item) {
  const state = data.installedApps || {},
    placements = data.publicConfig?.apps || {},
    configured = Object.prototype.hasOwnProperty.call(placements, item.id),
    mode = appMode(item.id);
  if (mode === "disabled") return false;
  if (configured && mode === "default") return true;
  if (Object.prototype.hasOwnProperty.call(state, item.id))
    return state[item.id] === true;
  return mode === "store"
    ? item.defaultInstalled === true
    : item.system
      ? true
      : item.defaultInstalled === true;
}
function iconUrl(item) {
  return item.external ? item.icon : "assets/" + item.icon;
}
function appButton(item) {
  return (
    '<button class="app" data-app="' +
    esc(item.id) +
    '" aria-label="' +
    esc(item.name) +
    '"><span class="app-icon"><img src="' +
    esc(iconUrl(item)) +
    '" alt=""></span><small>' +
    esc(item.name) +
    "</small></button>"
  );
}
function renderHomeApps() {
  const external = Object.values(catalog)
      .filter(isInstalled)
      .sort((a, b) => a.name.localeCompare(b.name)),
    ids = [
      "contacts",
      "bank",
      "garage",
      "camera",
      "photos",
      "obgram",
      "calc",
      "notes",
      "store",
      "settings",
    ];
  q("#apps").innerHTML =
    ids.map((id) => appButton({ id, ...coreApps[id] })).join("") +
    external.map(appButton).join("");
  q("#dock").innerHTML = ["call", "messages", "contacts"]
    .map((id) => appButton({ id, ...coreApps[id] }))
    .join("");
  document
    .querySelectorAll("[data-app]")
    .forEach((button) => (button.onclick = () => render(button.dataset.app)));
}
function renderHomeAppsV2() {
  const external = Object.values(catalog)
      .filter(isInstalled)
      .sort((a, b) => a.name.localeCompare(b.name)),
    ids = [
      "contacts",
      "bank",
      "garage",
      "camera",
      "photos",
      "obgram",
      "darkchat",
      "calc",
      "notes",
      "store",
      "settings",
    ].filter((id) => isInstalled({ id, ...coreApps[id] }));
  q("#apps").innerHTML =
    ids.map((id) => appButton({ id, ...coreApps[id] })).join("") +
    external.map(appButton).join("");
  q("#dock").innerHTML = ["call", "messages", "contacts"]
    .filter((id) => isInstalled({ id, ...coreApps[id] }))
    .map((id) => appButton({ id, ...coreApps[id] }))
    .join("");
  document
    .querySelectorAll("[data-app]")
    .forEach((button) => (button.onclick = () => render(button.dataset.app)));
}
renderHomeApps = renderHomeAppsV2;
function stopCamera() {
  clearTimeout(cameraVideoTimer);
  clearInterval(cameraRecordingTimer);
  cameraRecordingStarted = 0;
  cameraCaptureBusy = false;
  if (window.OBMediaCapture?.recording())
    window.OBMediaCapture.stopVideo().catch(() => {});
  window.OBMediaCapture?.stopView();
  cameraLandscape = false;
  post("cameraOrientation", { horizontal: false });
  post("cameraActive", { active: false });
}
function clearAppAppearance() {
  q(".screen").classList.remove(
    "obgram-active",
    "darkchat-active",
    "messages-active",
    "app-active",
  );
}
function goHome() {
  clearInterval(nearbyRefreshTimer);
  closeStoryViewer();
  if (app === "camera") stopCamera();
  window.OBMediaCapture?.cancelAudio?.();
  if (opened && inputFocusMode !== "game") {
    inputFocusMode = "phone";
    post("inputFocus", { mode: "phone" });
  }
  pageVersion++;
  app = "";
  thread = null;
  messageGroup = null;
  messageAttachOpen = false;
  clearAppAppearance();
  view.classList.add("hidden");
  lock.classList.add("hidden");
  home.classList.remove("hidden");
  renderHomeApps();
  if (call) minimized = true;
  renderCall();
}
function unlock() {
  goHome();
  if (call) {
    minimized = false;
    renderCall();
  }
}
function contactName(number) {
  return (
    data.contacts?.find((row) => row.contact_number === number)?.contact_name ||
    number ||
    "Número desconhecido"
  );
}
function contactInfo(number) {
  return (
    data.contacts?.find((row) => row.contact_number === number) || {
      contact_name: number || "Número desconhecido",
      contact_number: number,
      avatar_url: null,
    }
  );
}
function initials(value) {
  return String(value || "?")
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();
}
function conversations() {
  const rows = new Map();
  for (const contact of data.contacts || [])
    rows.set(contact.contact_number, {
      number: contact.contact_number,
      name: contact.contact_name,
      avatar_url: contact.avatar_url,
      last: "",
    });
  for (const message of data.messages || [])
    if (message.other_phone) {
      const row = rows.get(message.other_phone) || {
        number: message.other_phone,
        name: message.other_phone,
      };
      row.last = message.body;
      rows.delete(message.other_phone);
      rows.set(message.other_phone, row);
    }
  return [...rows.values()].reverse();
}
