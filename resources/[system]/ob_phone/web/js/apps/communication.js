// Contatos, mensagens diretas, grupos, compartilhamento e DarkChat.

const empty = (text, icon = "") =>
    '<div class="empty-state">' +
    (icon ? "<span>" + icon + "</span>" : "") +
    "<p>" +
    text +
    "</p></div>",
  avatar = (name, url) =>
    url
      ? '<span class="avatar"><img src="' + esc(url) + '" alt=""></span>'
      : '<span class="avatar">' + esc(initials(name)) + "</span>";
function messages() {
  if (!thread)
    return (
      '<div class="app-intro"><span>Conversas</span><button class="mini-action" data-do="newMessage">＋ Nova</button></div><div class="list">' +
      (conversations()
        .map(
          (row) =>
            '<button class="list-row" data-thread="' +
            esc(row.number) +
            '">' +
            avatar(row.name) +
            '<span class="list-copy"><b>' +
            esc(row.name) +
            "</b><small>" +
            esc(row.last || row.number) +
            "</small></span><i>›</i></button>",
        )
        .join("") || empty("Nenhuma conversa por aqui.", "✦")) +
      "</div>"
    );
  const list = (data.messages || []).filter(
    (message) => message.other_phone === thread,
  );
  return (
    '<div class="thread-head"><button class="circle-button" data-do="threads">‹</button>' +
    avatar(contactName(thread)) +
    "<span><b>" +
    esc(contactName(thread)) +
    "</b><small>" +
    esc(thread) +
    '</small></span></div><div class="threadMessages">' +
    (list
      .map(
        (message) =>
          '<div class="bubble ' +
          (message.direction === "out" ? "outgoing" : "incoming") +
          '"><span>' +
          esc(message.body) +
          "</span><small>" +
          esc(message.created_at) +
          "</small></div>",
      )
      .join("") || empty("Envie a primeira mensagem.")) +
    '</div><div class="composer"><textarea id="body" maxlength="500" placeholder="Mensagem"></textarea><button class="send-button" data-do="send">↑</button></div>'
  );
}
function contacts() {
  return (
    '<section class="form-card"><div class="form-title"><span class="form-icon">＋</span><div><b>Novo contato</b><small>Salve um número no aparelho</small></div></div><input id="contactName" maxlength="40" placeholder="Nome"><input id="contactNumber" maxlength="16" inputmode="tel" placeholder="Número"><button class="action" data-do="saveContact">Salvar contato</button><button class="text-action" data-do="shareNumber">Compartilhar meu número</button></section><div class="section-heading"><b>Contatos</b><span>' +
    (data.contacts || []).length +
    '</span></div><div class="list">' +
    ((data.contacts || [])
      .map(
        (contact) =>
          '<div class="contact-card">' +
          avatar(contact.contact_name) +
          '<div class="list-copy"><b>' +
          esc(contact.contact_name) +
          "</b><small>" +
          esc(contact.contact_number) +
          '</small></div><button class="round-action icon-call-action" data-call-number="' +
          esc(contact.contact_number) +
          '" aria-label="Ligar">' +
          uiIcon("phone") +
          '</button><button class="round-action icon-call-action" data-thread="' +
          esc(contact.contact_number) +
          '" aria-label="Mensagem">' +
          uiIcon("message") +
          "</button></div>",
      )
      .join("") || empty("Você ainda não salvou contatos.")) +
    "</div>"
  );
}
function messageContent(message) {
  const type = message.message_type || "text";
  if (type === "contact")
    return (
      '<article class="shared-contact">' +
      avatar(message.contact_name) +
      "<div><b>" +
      esc(message.contact_name) +
      "</b><small>" +
      esc(message.contact_number) +
      '</small></div><button data-save-contact="' +
      esc(message.contact_number) +
      '" data-contact-name="' +
      esc(message.contact_name) +
      '">Salvar</button><button data-number="' +
      esc(message.contact_number) +
      '">Ligar</button><button data-thread="' +
      esc(message.contact_number) +
      '">Mensagem</button></article>'
    );
  if (type === "video")
    return (
      '<video class="message-media" src="' +
      esc(message.media_url) +
      '" controls playsinline></video>'
    );
  if (type === "photo")
    return (
      '<img class="message-media" src="' +
      esc(message.media_url) +
      '" alt="Foto">'
    );
  if (type === "audio")
    return (
      '<div class="voice-note"><button data-audio-toggle aria-label="Reproduzir áudio">▶</button><input data-audio-progress type="range" min="0" max="1" step="0.01" value="0"><span data-audio-time>0:00</span><audio preload="metadata" src="' +
      esc(message.media_url) +
      '"></audio></div>'
    );
  if (type === "location")
    return (
      '<button class="location-card" data-location="' +
      esc(message.media_url) +
      '">⌖<span><b>Localização</b><small>Toque para marcar no mapa</small></span></button>'
    );
  return "<span>" + esc(message.body) + "</span>";
}
function messageAttachmentPanel() {
  if (!messageAttachOpen) return "";
  return '<section class="message-attachments action-menu"><button data-do="messageGallery"><i>▣</i><span><b>Galeria</b><small>Enviar foto ou vídeo</small></span></button><button data-do="messageLocation"><i>⌖</i><span><b>Localização</b><small>Compartilhar posição atual</small></span></button></section>';
}
function messageActionButton() {
  const recording = window.OBMediaCapture?.audioRecording?.();
  return (
    '<button id="messageAction" class="send-button ' +
    (recording ? "recording" : "") +
    '" data-do="recordAudio" aria-label="' +
    (recording ? "Parar e enviar áudio" : "Gravar áudio") +
    '">' +
    (recording
      ? "■"
      : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>') +
    "</button>"
  );
}
function messagesV2() {
  if (!thread)
    return (
      '<div class="app-intro messages-intro"><span>Conversas</span><span class="message-header-actions"><button class="mini-action icon-action" data-do="newGroup" aria-label="Novo grupo" title="Novo grupo">' +
      uiIcon("group") +
      '</button><button class="mini-action icon-action" data-do="newMessage" aria-label="Nova mensagem" title="Nova mensagem">' +
      uiIcon("compose") +
      '</button></span></div><div class="message-groups" id="messageGroups"></div><div class="list conversation-list">' +
      (conversations()
        .map(
          (row) =>
            '<button class="list-row" data-thread="' +
            esc(row.number) +
            '">' +
            avatar(row.name, row.avatar_url) +
            '<span class="list-copy"><b>' +
            esc(row.name) +
            "</b><small>" +
            esc(row.last || row.number) +
            "</small></span><i>›</i></button>",
        )
        .join("") || empty("Nenhuma conversa por aqui.", "✦")) +
      "</div>"
    );
  const info = contactInfo(thread),
    list = (data.messages || []).filter(
      (message) => message.other_phone === thread,
    );
  return (
    '<div class="message-thread"><div class="thread-head"><button class="circle-button" data-do="threads" aria-label="Voltar">' +
    uiIcon("back") +
    "</button>" +
    avatar(info.contact_name, info.avatar_url) +
    "<span><b>" +
    esc(info.contact_name) +
    "</b><small>" +
    esc(thread) +
    '</small></span><div class="thread-call-actions"><button data-call-number="' +
    esc(thread) +
    '" aria-label="Ligação de voz" title="Ligação de voz">' +
    uiIcon("phone") +
    '</button><button data-video-number="' +
    esc(thread) +
    '" aria-label="Chamada de vídeo" title="Chamada de vídeo">' +
    uiIcon("video") +
    '</button></div></div><div class="threadMessages">' +
    (list
      .map(
        (message) =>
          '<div class="bubble ' +
          (message.direction === "out" ? "outgoing" : "incoming") +
          '">' +
          messageContent(message) +
          "<small>" +
          esc(message.created_at) +
          "</small></div>",
      )
      .join("") || empty("Envie a primeira mensagem.")) +
    "</div>" +
    messageAttachmentPanel() +
    '<div class="composer"><button class="attach-button" data-do="messageAttach" aria-label="Anexar">' +
    uiIcon("plus") +
    '</button><textarea id="body" maxlength="500" rows="1" placeholder="Mensagem"></textarea>' +
    messageActionButton() +
    "</div></div>"
  );
}
function contactsV2() {
  return (
    '<section class="my-contact-card">' +
    avatar(data.ownerName || "Você") +
    "<div><small>MEU CARTÃO</small><b>" +
    esc(data.ownerName || "Meu contato") +
    "</b><span>" +
    esc(data.number) +
    '</span></div><button data-do="shareNumber">Compartilhar</button></section><section class="form-card"><div class="form-title"><span class="form-icon">＋</span><div><b>Novo contato</b><small>Salve um número no aparelho</small></div></div><input id="contactName" maxlength="40" placeholder="Nome"><input id="contactNumber" maxlength="16" inputmode="tel" placeholder="Número"><button class="action" data-do="saveContact">Salvar contato</button></section><div class="section-heading"><b>Contatos</b><span>' +
    (data.contacts || []).length +
    '</span></div><div class="list">' +
    ((data.contacts || [])
      .map(
        (contact) =>
          '<div class="contact-card">' +
          avatar(contact.contact_name) +
          '<div class="list-copy"><b>' +
          esc(contact.contact_name) +
          "</b><small>" +
          esc(contact.contact_number) +
          '</small></div><button class="round-action icon-call-action" data-call-number="' +
          esc(contact.contact_number) +
          '" aria-label="Ligar">' +
          uiIcon("phone") +
          '</button><button class="round-action icon-call-action" data-thread="' +
          esc(contact.contact_number) +
          '" aria-label="Mensagem">' +
          uiIcon("message") +
          "</button></div>",
      )
      .join("") || empty("Você ainda não salvou contatos.")) +
    "</div>"
  );
}
function contactDetailsCard(contact, own = false) {
  return (
    '<div class="contact-detail"><button class="contact-back" data-do="contactsHome" aria-label="Voltar">' +
    uiIcon("back") +
    "</button>" +
    avatar(contact.name, contact.avatar_url) +
    "<h2>" +
    esc(contact.name) +
    '</h2><div class="contact-actions"><button data-thread="' +
    esc(contact.number) +
    '" aria-label="Mensagem">' +
    uiIcon("message") +
    '<small>Mensagem</small></button><button data-call-number="' +
    esc(contact.number) +
    '" aria-label="Ligação de voz">' +
    uiIcon("phone") +
    '<small>Ligar</small></button><button data-video-number="' +
    esc(contact.number) +
    '" aria-label="Chamada de vídeo">' +
    uiIcon("video") +
    "<small>Vídeo</small></button></div><section><small>" +
    (own ? "MEU NÚMERO" : "TELEFONE") +
    "</small><b>" +
    esc(contact.number) +
    '</b></section><button class="share-profile" data-share-contact="' +
    esc(contact.number) +
    '" data-share-name="' +
    esc(contact.name) +
    '">Compartilhar perfil</button></div>'
  );
}
function contactsV3() {
  if (contactView)
    return contactDetailsCard(contactView, contactView.own === true);
  const contacts = [...(data.contacts || [])].sort((a, b) =>
    String(a.contact_name).localeCompare(String(b.contact_name), "pt-BR", {
      sensitivity: "base",
    }),
  );
  let letter = "";
  const rows = contacts
    .map((contact) => {
      const next = (
          String(contact.contact_name || "#").trim()[0] || "#"
        ).toUpperCase(),
        heading =
          next !== letter
            ? '<b class="contact-letter">' + esc(next) + "</b>"
            : "";
      letter = next;
      return (
        heading +
        '<button class="contact-list-row" data-contact-open="' +
        esc(contact.contact_number) +
        '">' +
        avatar(contact.contact_name, contact.avatar_url) +
        "<span><b>" +
        esc(contact.contact_name) +
        "</b><small>" +
        esc(contact.contact_number) +
        "</small></span><i>›</i></button>"
      );
    })
    .join("");
  return (
    '<div class="contacts-head"><h2>Contatos</h2><button data-do="contactAdd" aria-label="Novo contato">' +
    uiIcon("plus") +
    '</button></div><input class="contact-search" id="contactSearch" placeholder="Buscar"><button class="contact-list-row my-row" data-contact-own>' +
    avatar(data.shareName || data.ownerName || "Você", data.deviceAvatar) +
    "<span><b>Meu cartão</b><small>" +
    esc(data.shareName || data.ownerName || "") +
    " · " +
    esc(data.number) +
    '</small></span><i>›</i></button><div class="alphabetical-contacts">' +
    (rows || empty("Você ainda não salvou contatos.")) +
    "</div>"
  );
}
function darkHome() {
  const groups = darkState?.groups || [];
  return (
    '<div class="dark-page"><header><span>♙</span><div><h2>DarkChat</h2><small>Rede privada somente por convite</small></div><button data-dark-action="compose">＋</button></header><input id="darkSearch" placeholder="Buscar grupo"><section class="dark-code"><small>Entrar com convite</small><div><input id="darkCode" maxlength="20" placeholder="dark/XXXX-XXXX"><button data-dark-action="join">Entrar</button></div></section><div class="dark-groups">' +
    (groups
      .map(
        (group) =>
          '<button data-dark-group="' +
          Number(group.id) +
          '"><i>◆</i><span><b>' +
          esc(group.name) +
          "</b><small>" +
          esc(group.last_message || group.invite_code) +
          "</small></span><em>" +
          esc(group.last_time || "") +
          " ›</em></button>",
      )
      .join("") || empty("Crie um grupo ou use um código de convite.", "◇")) +
    "</div></div>"
  );
}
function darkThread(payload) {
  const group = payload.group || {},
    messages = payload.messages || [];
  return (
    '<div class="dark-page dark-thread"><header><button data-dark-action="home">‹</button><div><h2>' +
    esc(group.name || "DarkChat") +
    "</h2><small>" +
    esc(group.invite_code || "Conversa privada") +
    '</small></div><span>♙</span></header><div class="dark-messages">' +
    (messages
      .map(
        (row) =>
          '<article class="' +
          (Number(row.user_id) === Number(data.profile?.user_id)
            ? "mine"
            : "") +
          '"><b>' +
          esc(row.name) +
          "</b>" +
          (row.media_type === "location"
            ? '<button class="location-card" data-location="' +
              esc(row.media_url) +
              '">⌖<span><b>Localização</b><small>Marcar no mapa</small></span></button>'
            : "") +
          (row.body && row.media_type !== "location"
            ? "<p>" + esc(row.body) + "</p>"
            : "") +
          "<small>" +
          esc(row.created_at) +
          "</small></article>",
      )
      .join("") || empty("Nenhuma mensagem neste grupo.")) +
    '</div><div class="dark-composer"><button data-do="darkLocation" title="Enviar localização">⌖</button><textarea id="darkBody" maxlength="500" placeholder="Mensagem anônima"></textarea><button data-dark-action="send">↑</button></div></div>'
  );
}

function messageGroupThread(payload) {
  const group = payload.group || {},
    messages = payload.messages || [],
    members = payload.members || [],
    canManage = payload.role === "owner" || payload.role === "moderator",
    roleLabel = {
      owner: "Dono",
      moderator: "Moderador",
      member: "Participante",
    };
  return (
    '<div class="message-thread group-thread"><div class="thread-head"><button class="circle-button" data-do="closeMessageGroup" aria-label="Voltar">' +
    uiIcon("back") +
    '</button><span class="group-avatar">' +
    esc(initials(group.name || "G")) +
    "</span><span><b>" +
    esc(group.name || "Grupo") +
    "</b><small>" +
    members.length +
    ' participantes</small></span><button class="group-settings-button" data-do="groupInfo" aria-label="Ajustes do grupo">' +
    uiIcon("settings") +
    '</button></div><div class="threadMessages">' +
    (messages
      .map(
        (row) =>
          '<div class="bubble ' +
          (Number(row.user_id) === Number(data.userId)
            ? "outgoing"
            : "incoming") +
          '"><b>' +
          esc(row.name) +
          "</b>" +
          messageContent(row) +
          "<small>" +
          esc(row.created_at) +
          "</small></div>",
      )
      .join("") || empty("Envie a primeira mensagem.")) +
    '</div><div class="composer group-composer"><button class="attach-button" data-do="groupLocation" aria-label="Enviar localização">' +
    uiIcon("pin") +
    '</button><textarea id="groupBody" maxlength="500" rows="1" placeholder="Mensagem"></textarea><button class="send-button" data-do="sendGroupMessage" aria-label="Enviar">' +
    uiIcon("send") +
    '</button></div><section class="group-info hidden" data-group-panel><header><button class="circle-button" data-do="groupInfo" aria-label="Voltar">' +
    uiIcon("back") +
    '</button><b>Dados do grupo</b><span></span></header><div class="group-info-hero"><span class="group-avatar large">' +
    esc(initials(group.name || "G")) +
    "</span><h2>" +
    esc(group.name || "Grupo") +
    "</h2><small>" +
    members.length +
    ' participantes</small></div><section class="group-settings-card"><b>Participantes</b><div class="group-members">' +
    members
      .map(
        (member) =>
          "<article>" +
          avatar(member.name, member.avatar_url) +
          '<span class="group-member-copy"><b>' +
          esc(member.name) +
          "</b><small>" +
          esc(roleLabel[member.role] || "Participante") +
          '</small></span><div class="group-member-actions">' +
          (payload.role === "owner" && member.role === "member"
            ? '<button data-group-manage="' +
              Number(member.user_id) +
              '" data-operation="moderator">Tornar moderador</button>'
            : "") +
          (payload.role === "owner" && member.role !== "owner"
            ? '<button data-group-transfer="' +
              Number(member.user_id) +
              '">Transferir grupo</button>'
            : "") +
          (canManage && member.role !== "owner"
            ? '<button class="danger-text" data-group-manage="' +
              Number(member.user_id) +
              '" data-operation="remove">Remover</button>'
            : "") +
          "</div></article>",
      )
      .join("") +
    '</div></section><section class="group-settings-card"><b>Adicionar participante</b><select id="groupInviteContact"><option value="">Escolha um contato</option>' +
    (data.contacts || [])
      .map(
        (row) =>
          '<option value="' +
          esc(row.contact_number) +
          '">' +
          esc(row.contact_name) +
          "</option>",
      )
      .join("") +
    '</select><button class="group-primary" data-do="groupInvite">Adicionar ao grupo</button></section>' +
    (payload.role === "owner"
      ? '<section class="group-settings-card"><b>Quem pode convidar</b><select id="groupInvitePermission"><option value="owner">Somente o dono</option><option value="moderators">Dono e moderadores</option><option value="members">Todos os participantes</option></select><button class="group-primary" data-do="groupPermission">Salvar permissão</button></section><button class="group-delete" data-do="deleteMessageGroup">Excluir grupo</button>'
      : "") +
    "</section></div>"
  );
}
async function darkchat(version) {
  content.innerHTML = empty("Conectando à rede privada...");
  await loadMedia();
  const result = await post("darkchat", { action: "state" });
  if (version !== pageVersion) return;
  if (!result.ok) {
    content.innerHTML =
      '<div class="dark-denied"><span>⌁</span><h2>Acesso negado</h2><p>' +
      esc(
        result.message || "Você não tem permissão para abrir este aplicativo.",
      ) +
      "</p></div>";
    return;
  }
  darkState = result.data || { groups: [] };
  darkGroup = null;
  content.innerHTML = darkHome();
}
function scrollMessagesToEnd() {
  const scroll = () => {
    for (const list of content.querySelectorAll(
      ".threadMessages,.dark-messages",
    ))
      list.scrollTop = list.scrollHeight;
  };
  requestAnimationFrame(() => {
    scroll();
    requestAnimationFrame(scroll);
  });
  setTimeout(scroll, 120);
}
async function openDarkGroup(groupId) {
  const result = await post("darkchat", { action: "messages", groupId });
  if (!result.ok) return toast(result.message, "error");
  darkGroup = Number(groupId);
  content.innerHTML = darkThread(result.data || {});
  scrollMessagesToEnd();
}
async function loadMessageGroups() {
  const result = await post("messageGroups", { action: "state" });
  messageGroupState = result.ok ? result.data : { groups: [] };
  const host = q("#messageGroups");
  if (host) {
    const groups = messageGroupState?.groups || [];
    host.innerHTML = groups.length
      ? "<b>Grupos</b>" +
        groups
          .map(
            (row) =>
              '<button data-message-group="' +
              Number(row.id) +
              '"><span class="group-list-icon">' +
              uiIcon("group") +
              "</span><div><b>" +
              esc(row.name) +
              "</b><small>" +
              esc(row.last_message || "Grupo de mensagens") +
              "</small></div><i>›</i></button>",
          )
          .join("")
      : "";
  }
  return result;
}
async function openMessageGroup(groupId) {
  const result = await post("messageGroups", { action: "open", groupId });
  if (!result.ok) return toast(result.message, "error");
  messageGroup = Number(groupId);
  content.innerHTML = messageGroupThread(result.data || {});
  const permission = q("#groupInvitePermission");
  if (permission)
    permission.value = result.data?.group?.invite_permission || "moderators";
  scrollMessagesToEnd();
}
function openMessageGallery() {
  const items = (data.media || []).filter(
    (row) => row.media_type === "photo" || row.media_type === "video",
  );
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="message-gallery"><header><button data-do="closeMessageGallery" aria-label="Voltar">' +
      uiIcon("back") +
      '</button><b>Galeria</b></header><div class="gallery-grid">' +
      (items
        .map(
          (item) =>
            '<button class="gallery-item" data-message-media="' +
            Number(item.id) +
            '" data-message-type="' +
            esc(item.media_type) +
            '">' +
            (item.media_type === "video"
              ? '<video src="' +
                esc(item.media_url) +
                '" muted></video><i class="video-mark">▶</i>'
              : '<img src="' + esc(item.media_url) + '" alt="Foto">') +
            "</button>",
        )
        .join("") || empty("Nenhuma foto ou vídeo.")) +
      "</div></section>",
  );
}
function shareRecipientRows() {
  const rows = conversations(),
    recent = rows.filter((row) => row.last),
    others = rows.filter((row) => !row.last);
  return [...recent, ...others];
}
function sharePeople(rows, attribute) {
  return rows
    .map(
      (row) =>
        '<button class="share-person" ' +
        attribute +
        '="' +
        esc(row.serverId ?? row.number) +
        '" title="' +
        esc(row.name) +
        '">' +
        avatar(row.name, row.avatar_url) +
        "<b>" +
        esc(row.name) +
        "</b></button>",
    )
    .join("");
}
function contactShareSheet(selected) {
  const all = shareRecipientRows();
  if (shareAllRecipients)
    return (
      '<section class="share-sheet contact-share contact-share-all"><header><button data-do="shareRecentContacts" aria-label="Voltar">' +
      uiIcon("back") +
      '</button><b>Todos os contatos</b><button data-share-close aria-label="Fechar">×</button></header><input id="shareContactSearch" placeholder="Buscar contato"><div class="share-recipient-grid show-all">' +
      sharePeople(all, "data-share-to") +
      "</div>" +
      (all.length
        ? ""
        : '<small class="share-empty">Nenhum contato salvo.</small>') +
      "</section>"
    );
  return (
    '<section class="share-sheet contact-share"><header><b>Compartilhar ' +
    esc(selected.name) +
    '</b><button data-share-close aria-label="Fechar">×</button></header><b>Pessoas próximas com o celular aberto</b><div class="share-recipient-grid nearby-recipients">' +
    (sharePeople(nearbyShare, "data-share-nearby") ||
      '<small class="share-empty">Ninguém próximo com o celular aberto.</small>') +
    '</div><b>Conversas recentes</b><div class="share-recipient-grid">' +
    sharePeople(all.slice(0, 4), "data-share-to") +
    '<button class="share-person share-more" data-do="shareAllContacts" title="Mostrar todos os contatos"><span>' +
    uiIcon("plus") +
    "</span><b>Todos</b></button></div>" +
    (all.length
      ? ""
      : '<small class="share-empty">Nenhum contato salvo.</small>') +
    "</section>"
  );
}
async function refreshNearbyShare() {
  if (!opened || app !== "contacts" || !q(".share-sheet") || shareAllRecipients)
    return;
  const result = await post("nearbyContacts");
  if (!result.ok) return;
  nearbyShare = result.data || [];
  const list = q(".nearby-recipients");
  if (list)
    list.innerHTML =
      sharePeople(nearbyShare, "data-share-nearby") ||
      '<small class="share-empty">Ninguém próximo com o celular aberto.</small>';
}
