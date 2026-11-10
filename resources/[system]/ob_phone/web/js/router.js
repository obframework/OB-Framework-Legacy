// Seleciona, abre e atualiza aplicativos internos e externos.

function externalApp(item) {
  content.innerHTML =
    '<iframe id="externalApp" class="external-app" title="' +
    esc(item.name) +
    '" src="' +
    esc(item.entry) +
    '"></iframe>';
  q("#externalApp").addEventListener("load", () =>
    q("#externalApp").contentWindow?.postMessage(
      { type: "ob-phone:ready", appId: item.id, theme: prefs.theme || "dark" },
      "*",
    ),
  );
}
async function render(id) {
  if (id === "social") id = "obgram";
  if (app === "camera" && id !== "camera") stopCamera();
  const item = coreApps[id] ? { id, ...coreApps[id] } : catalog[id];
  if (!item || (!isInstalled(item) && id !== "store")) return;
  const version = ++pageVersion;
  app = id;
  home.classList.add("hidden");
  lock.classList.add("hidden");
  view.classList.remove("hidden");
  view.classList.toggle(
    "immersive",
    id === "obgram" || id === "camera" || id === "darkchat" || id === emergencyAppId,
  );
  q("#title").textContent = item.name;
  q("#refresh").classList.toggle(
    "hidden",
    item.external === true || id === "camera",
  );
  if (item.external) {
    if (id === emergencyAppId) {
      renderEmergencyApp();
      return;
    }
    // Apps externos rodam em outro iframe/origem. Enquanto estiverem abertos,
    // entregue o teclado inteiro a NUI; o iframe ainda refina o modo pelo foco.
    inputFocusMode = "typing";
    post("inputFocus", { mode: "typing" });
    externalApp(item);
    return;
  }
  if (id === "call") {
    content.innerHTML =
      '<div class="tabs"><button class="tab selected" data-do="keypad">Teclado</button><button class="tab" data-do="history">Recentes</button></div><input id="callNumber" inputmode="tel" maxlength="16" placeholder="Número"><div class="dial">' +
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
        .map(
          (number, index) =>
            '<button data-digit="' +
            number +
            '">' +
            number +
            "<small>" +
            ([
              "",
              "ABC",
              "DEF",
              "GHI",
              "JKL",
              "MNO",
              "PQRS",
              "TUV",
              "WXYZ",
              "",
              "+",
              "",
            ][index] || "·") +
            "</small></button>",
        )
        .join("") +
      '</div><div class="dial-actions"><button class="dial-call voice" data-do="dial" aria-label="Ligação de voz">' +
      uiIcon("phone") +
      "<small>Ligar</small></button></div>";
    if (call) {
      minimized = false;
      renderCall();
    }
  }
  if (id === "messages") {
    await loadMedia();
    if (version === pageVersion) {
      content.innerHTML = messagesV2();
      if (!thread) await loadMessageGroups();
      else scrollMessagesToEnd();
    }
  }
  if (id === "contacts") content.innerHTML = contactsV2();
  if (id === "obgram") {
    await loadMedia();
    if (version === pageVersion) content.innerHTML = obgram();
  }
  if (id === "darkchat") await darkchat(version);
  if (id === "camera") camera();
  if (id === "photos") await gallery(version);
  if (id === "calc") {
    expression = "";
    content.innerHTML =
      '<input id="calc" value="0" readonly><div class="keys">' +
      [
        "7",
        "8",
        "9",
        "/",
        "4",
        "5",
        "6",
        "*",
        "1",
        "2",
        "3",
        "-",
        "C",
        "0",
        ".",
        "+",
        "⌫",
        "=",
        "(",
        ")",
      ]
        .map((key) => '<button data-key="' + key + '">' + key + "</button>")
        .join("") +
      "</div>";
  }
  if (id === "notes")
    content.innerHTML =
      '<div class="notes-sheet"><p class="date"></p><textarea id="note" maxlength="8000" placeholder="Comece a escrever...">' +
      esc(prefs.note || "") +
      '</textarea></div><button class="action" data-do="saveNote">Salvar nota</button>';
  if (id === "settings") {
    await loadMedia();
    if (version === pageVersion) {
      content.innerHTML = settings();
      const ringtone = q("#ringtone");
      if (ringtone) ringtone.value = data.settings?.ringtone || "classic";
    }
  }
  if (id === "store") content.innerHTML = appStoreV2();
  if (id === "bank") await bank(version);
  if (id === "garage") await garage(version);
}
async function refresh() {
  const version = pageVersion,
    selected = app,
    result = await post("refresh");
  if (!result.ok)
    return toast(result.message || "Não foi possível atualizar.", "error");
  data = { ...data, ...result.data };
  battery();
  if (version !== pageVersion || !selected) return;
  if (selected === "messages" && messageGroup)
    return openMessageGroup(messageGroup);
  render(selected);
}
async function history() {
  const version = ++pageVersion;
  content.innerHTML = empty("Carregando chamadas...");
  const result = await post("callHistory");
  if (version !== pageVersion) return;
  content.innerHTML =
    '<div class="tabs"><button class="tab" data-do="keypad">Teclado</button><button class="tab selected">Recentes</button></div><div class="list call-history">' +
    (!result.ok
      ? empty("Histórico indisponível.")
      : (result.data || [])
          .map(
            (row) =>
              '<button class="list-row" data-number="' +
              esc(row.number) +
              '">' +
              avatar(contactName(row.number)) +
              '<span class="list-copy"><b>' +
              esc(contactName(row.number)) +
              "</b><small>" +
              (row.call_type === "video" ? "Vídeo" : "Voz") +
              " · " +
              (row.direction === "out" ? "Efetuada" : "Recebida") +
              " · " +
              (row.status === "answered"
                ? Number(row.duration) + "s"
                : "Não atendida") +
              " · " +
              esc(row.created_at) +
              '</small></span><i class="history-call-icon">' +
              uiIcon(row.call_type === "video" ? "video" : "phone") +
              "</i></button>",
          )
          .join("") || empty("Nenhuma ligação ainda.")) +
    "</div>";
}
