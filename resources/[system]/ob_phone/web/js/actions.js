// Ações de interface. Elementos com data-do usam este registro.

const handlers = {
  keypad: () => render("call"),
  history,
  dial: () => action("call", { number: q("#callNumber").value }),
  newMessage: () => {
    content.innerHTML =
      '<section class="contact-recipient-picker"><header><button data-do="threads" aria-label="Voltar">' +
      uiIcon("back") +
      '</button><b>Nova mensagem</b></header><input id="recipientSearch" placeholder="Buscar contato"><div>' +
      (data.contacts || [])
        .map(
          (row) =>
            '<button data-thread="' +
            esc(row.contact_number) +
            '">' +
            avatar(row.contact_name, row.avatar_url) +
            "<span><b>" +
            esc(row.contact_name) +
            "</b><small>" +
            esc(row.contact_number) +
            "</small></span><i>›</i></button>",
        )
        .join("") +
      "</div></section>";
  },
  startThread: () => {},
  threads: () => {
    thread = null;
    messageGroup = null;
    render("messages");
  },
  send: () =>
    action("message", { to: thread, body: q("#body").value }, refresh),
  saveContact: () =>
    action(
      "contact",
      { name: q("#contactName").value, number: q("#contactNumber").value },
      refresh,
    ),
  username: () =>
    action(
      "username",
      {
        username: q("#username")?.value || data.profile?.username || "",
        name: q("#displayName")?.value || "",
      },
      refresh,
    ),
  openComposer: () => {
    obgramCompose = true;
    content.innerHTML = obgram();
  },
  closeComposer: () => {
    obgramCompose = false;
    content.innerHTML = obgram();
  },
  publish: () =>
    action(
      "post",
      { body: q("#postBody").value, mediaId: q("#postMedia")?.value },
      () => {
        obgramCompose = false;
        refresh();
      },
    ),
  createStory: () => {
    const mediaId = q("#postMedia")?.value;
    if (!mediaId)
      return toast("Selecione uma foto ou vídeo da galeria.", "error");
    action("obgramAction", { action: "story", mediaId }, () => {
      obgramCompose = false;
      refresh();
    });
  },
  setAvatar: openAvatarPicker,
  transfer: () =>
    action(
      "transfer",
      { id: q("#transferId").value, amount: q("#transferValue").value },
      () => render("bank"),
    ),
  capture,
  flipCamera: async () => {
    const captureApi = window.OBMediaCapture;
    if (captureApi?.recording?.())
      return toast("Finalize o vídeo antes de virar a câmera.", "error");
    resumeCameraGameInput();
    cameraFront = !cameraFront;
    await post("cameraFacing", { front: cameraFront });
    try {
      await captureApi?.start(q("#cameraView"), {
        landscape: cameraLandscape,
        front: cameraFront,
      });
    } catch (error) {
      cameraFront = !cameraFront;
      await post("cameraFacing", { front: cameraFront });
      toast(error?.message || "Não foi possível virar a câmera.", "error");
    }
  },
  saveNote: () => {
    prefs.note = q("#note").value;
    savePrefs();
  },
};
handlers.username = () =>
  action(
    "username",
    {
      username: q("#username")?.value || data.profile?.username || "",
      name: q("#displayName")?.value || "",
    },
    refresh,
  );
handlers.closeStory = closeStoryViewer;
handlers.notifications = () => {
  obgramTab = "activity";
  obgramCompose = false;
  content.innerHTML = obgram();
};
handlers.openComposer = () => {
  obgramTab = "home";
  obgramCompose = true;
  content.innerHTML = obgram();
};
handlers.rotateCamera = async () => {
  const captureApi = window.OBMediaCapture;
  if (captureApi?.recording?.())
    return toast("Finalize o vídeo antes de girar a câmera.", "error");
  resumeCameraGameInput();
  cameraLandscape = !cameraLandscape;
  const shell = q(".camera-shell"),
    canvas = q("#cameraView");
  shell?.classList.toggle("landscape", cameraLandscape);
  await post("cameraOrientation", { horizontal: cameraLandscape });
  try {
    await captureApi?.start(canvas, {
      landscape: cameraLandscape,
      front: cameraFront,
    });
    const status = q("#cameraStatus");
    if (status)
      status.textContent = cameraLandscape
        ? "Câmera horizontal"
        : "Câmera vertical";
  } catch (error) {
    cameraLandscape = !cameraLandscape;
    shell?.classList.toggle("landscape", cameraLandscape);
    toast(error?.message || "Não foi possível girar a câmera.", "error");
  }
};
handlers.send = () =>
  action(
    "message",
    { to: thread, body: q("#body")?.value || "", messageType: "text" },
    refresh,
  );
handlers.messageAttach = () => {
  messageAttachOpen = !messageAttachOpen;
  content.innerHTML = messagesV2();
};
handlers.messageGallery = () => {
  messageAttachOpen = false;
  openMessageGallery();
};
handlers.closeMessageGallery = () => q(".message-gallery")?.remove();
handlers.messageLocation = async () => {
  const result = await action("sendLocation", { kind: "direct", to: thread });
  if (result?.ok) await refresh();
};
handlers.recordAudio = async () => {
  const api = window.OBMediaCapture;
  try {
    if (!api?.audioRecording?.()) {
      await api?.startAudio();
      content.innerHTML = messagesV2();
    } else {
      const blob = await api.stopAudio();
      const saved = await uploadMedia(blob, "audio");
      await action(
        "message",
        { to: thread, messageType: "audio", mediaId: saved.id },
        refresh,
      );
    }
  } catch (error) {
    toast(error?.message || "Não foi possível gravar o áudio.", "error");
  }
};
handlers.contactsHome = () => {
  contactView = null;
  contactShare = null;
  content.innerHTML = contactsV3();
};
handlers.contactAdd = () =>
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="share-sheet contact-add"><header><b>Novo contato</b><button data-share-close>×</button></header><input id="contactName" maxlength="40" placeholder="Nome"><input id="contactNumber" maxlength="16" inputmode="tel" placeholder="Número"><button class="action" data-do="saveContact">Salvar contato</button></section>',
  );
handlers.shareNumber = async () => {
  const selected = contactShare ||
    contactView || {
      name: data.shareName || data.ownerName || "Meu contato",
      number: data.number,
      own: true,
    };
  contactShare = selected;
  shareAllRecipients = false;
  nearbyShare = [];
  clearInterval(nearbyRefreshTimer);
  const result = await post("nearbyContacts");
  if (result.ok) nearbyShare = result.data || [];
  content.insertAdjacentHTML("beforeend", contactShareSheet(selected));
  nearbyRefreshTimer = setInterval(refreshNearbyShare, 1500);
};
handlers.shareAllContacts = () => {
  shareAllRecipients = true;
  const sheet = q(".contact-share");
  if (sheet) sheet.outerHTML = contactShareSheet(contactShare);
};
handlers.shareRecentContacts = () => {
  shareAllRecipients = false;
  const sheet = q(".contact-share");
  if (sheet) sheet.outerHTML = contactShareSheet(contactShare);
};
handlers.shareNearby = (target) => {
  const selected = contactShare || contactView;
  action(
    "shareNumber",
    {
      target: Number(target),
      contactName: selected?.name,
      contactNumber: selected?.number,
    },
    () => {
      clearInterval(nearbyRefreshTimer);
      q(".share-sheet")?.remove();
    },
  );
};
handlers.shareMessage = (to) => {
  const selected = contactShare || contactView;
  action(
    "message",
    {
      to,
      messageType: "contact",
      contactName: selected?.name || data.ownerName || "Meu contato",
      contactNumber: selected?.number || data.number,
    },
    () => {
      clearInterval(nearbyRefreshTimer);
      q(".share-sheet")?.remove();
    },
  );
};
handlers.openSettingsAvatar = () => openAvatarPicker("device");
handlers.openPhoneSecurity = () => {
  document.body.insertAdjacentHTML("beforeend", '<section class="share-sheet security-sheet"><header><b>Alterar senha</b><button data-security-close>×</button></header><input id="newDevicePin" type="password" inputmode="numeric" minlength="4" maxlength="6" placeholder="Nova senha"><input id="confirmDevicePin" type="password" inputmode="numeric" minlength="4" maxlength="6" placeholder="Confirmar senha"><button class="action" id="saveDevicePin">Salvar senha</button></section>');
  q("[data-security-close]").onclick = () => q(".security-sheet")?.remove();
  q("#saveDevicePin").onclick = async () => {
    const result = await post("deviceAuth", {action:"changePin",pin:q("#newDevicePin").value,confirmation:q("#confirmDevicePin").value});
    toast(result.message || (result.ok ? "Senha alterada." : "Não foi possível alterar."), result.ok);
    if (result.ok) q(".security-sheet")?.remove();
  };
};
handlers.saveFaceRecognition = async () => {
  const enabled = q("#faceRecognition")?.checked === true,
    result = await post("deviceAuth", {action:"face",enabled});
  toast(result.message || (result.ok ? "Configuração salva." : "Não foi possível salvar."), result.ok);
  if (result.ok) data.device.faceEnabled = enabled;
};
handlers.savePhoneSettings = () =>
  action(
    "phoneSettings",
    {
      action: "save",
      shareName: q("#shareName")?.value || "",
      airplane: q("#airplaneMode")?.checked === true,
      notifications: q("#phoneNotifications")?.checked === true,
      darkchatNotifications: q("#darkchatNotifications")?.checked === true,
      ringtone: q("#ringtone")?.value || "classic",
    },
    async () => {
      await refresh();
      ring();
    },
  );
handlers.darkLocation = async () => {
  const result = await action("sendLocation", {
    kind: "dark",
    groupId: darkGroup,
  });
  if (result?.ok) await openDarkGroup(darkGroup);
};
handlers.newGroup = () =>
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="share-sheet"><header><b>Novo grupo</b><button data-share-close>×</button></header><input id="messageGroupName" maxlength="40" placeholder="Nome do grupo"><button class="action" data-do="createMessageGroup">Criar grupo</button></section>',
  );
handlers.createMessageGroup = async () => {
  const result = await action("messageGroups", {
    action: "create",
    name: q("#messageGroupName")?.value,
  });
  if (result?.ok) await openMessageGroup(result.data.groupId);
};
handlers.closeMessageGroup = () => {
  messageGroup = null;
  render("messages");
};
handlers.sendGroupMessage = async () => {
  const result = await action("messageGroups", {
    action: "send",
    groupId: messageGroup,
    body: q("#groupBody")?.value || "",
  });
  if (result?.ok) await openMessageGroup(messageGroup);
};
handlers.groupLocation = async () => {
  const result = await action("sendLocation", {
    kind: "group",
    groupId: messageGroup,
  });
  if (result?.ok) await openMessageGroup(messageGroup);
};
handlers.groupInfo = () => q("[data-group-panel]")?.classList.toggle("hidden");
handlers.groupInvite = async () => {
  const result = await action("messageGroups", {
    action: "invite",
    groupId: messageGroup,
    number: q("#groupInviteContact")?.value,
  });
  if (result?.ok) await openMessageGroup(messageGroup);
};
handlers.groupPermission = async () => {
  const result = await action("messageGroups", {
    action: "permission",
    groupId: messageGroup,
    value: q("#groupInvitePermission")?.value,
  });
  if (result?.ok) await openMessageGroup(messageGroup);
};
handlers.deleteMessageGroup = async () => {
  if (!confirm("Excluir este grupo para todos?")) return;
  const result = await action("messageGroups", {
    action: "delete",
    groupId: messageGroup,
  });
  if (result?.ok) {
    messageGroup = null;
    render("messages");
  }
};
function calculate() {
  if (!/^[0-9+*/(). -]{1,80}$/.test(expression)) return "Erro";
  try {
    const value = Function('"use strict";return (' + expression + ")")();
    return Number.isFinite(value)
      ? String(Math.round(value * 1e8) / 1e8)
      : "Erro";
  } catch {
    return "Erro";
  }
}
function closePostSheet() {
  q(".post-actions-sheet")?.remove();
}
function showPostActions(postId) {
  closePostSheet();
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="post-actions-sheet"><div class="sheet-grip"></div><button data-own-action="edit" data-post-id="' +
      Number(postId) +
      '">Editar publicação</button><button class="delete" data-own-action="delete" data-post-id="' +
      Number(postId) +
      '">Excluir publicação</button><button data-own-action="close">Cancelar</button></section>',
  );
}
content.addEventListener(
  "click",
  async (event) => {
    const button = event.target.closest("button");
    if (!button) return;
    if (button.hasAttribute("data-audio-toggle")) {
      event.stopImmediatePropagation();
      const player = button.closest(".voice-note"),
        audio = player?.querySelector("audio"),
        progress = player?.querySelector("[data-audio-progress]"),
        time = player?.querySelector("[data-audio-time]");
      if (!audio) return;
      document.querySelectorAll(".voice-note audio").forEach((other) => {
        if (other !== audio) other.pause();
      });
      const format = (value) => {
        value = Math.max(0, Math.floor(Number(value) || 0));
        return (
          Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
        );
      };
      audio.onloadedmetadata = () => {
        progress.max = String(audio.duration || 1);
        time.textContent = format(audio.duration);
      };
      audio.ontimeupdate = () => {
        progress.value = String(audio.currentTime);
        time.textContent = format(audio.currentTime);
      };
      audio.onplay = () => (button.textContent = "❚❚");
      audio.onpause = () => (button.textContent = "▶");
      audio.onended = () => {
        button.textContent = "▶";
        progress.value = "0";
      };
      if (audio.paused)
        await audio
          .play()
          .catch(() => toast("Não foi possível reproduzir o áudio.", "error"));
      else audio.pause();
      return;
    }
    if (button.dataset.shareTo) {
      event.stopImmediatePropagation();
      handlers.shareMessage(button.dataset.shareTo);
      return;
    }
    if (button.dataset.shareNearby) {
      event.stopImmediatePropagation();
      handlers.shareNearby(button.dataset.shareNearby);
      return;
    }
    if (button.dataset.location) {
      event.stopImmediatePropagation();
      await action("setWaypoint", { location: button.dataset.location });
      return;
    }
    if (button.dataset.messageGroup) {
      event.stopImmediatePropagation();
      await openMessageGroup(button.dataset.messageGroup);
      return;
    }
    if (button.dataset.groupManage) {
      event.stopImmediatePropagation();
      const result = await action("messageGroups", {
        action: "manage",
        groupId: messageGroup,
        userId: Number(button.dataset.groupManage),
        operation: button.dataset.operation,
      });
      if (result?.ok) await openMessageGroup(messageGroup);
      return;
    }
    if (button.dataset.groupTransfer) {
      event.stopImmediatePropagation();
      if (confirm("Transferir este grupo para o participante?")) {
        const result = await action("messageGroups", {
          action: "transfer",
          groupId: messageGroup,
          userId: Number(button.dataset.groupTransfer),
        });
        if (result?.ok) await openMessageGroup(messageGroup);
      }
      return;
    }
    if (button.dataset.do === "publish" || button.dataset.do === "createStory")
      obgramMediaId = null;
    if (button.dataset.galleryAlbum) {
      galleryAlbum = button.dataset.galleryAlbum;
      renderGalleryContent();
      return;
    }
    if (button.dataset.galleryMedia) {
      event.stopImmediatePropagation();
      openMediaViewer(button.dataset.galleryMedia);
      return;
    }
    if (button.dataset.mediaView) {
      event.stopImmediatePropagation();
      const viewer = q(".media-viewer");
      if (button.dataset.mediaView === "close") {
        viewer?.remove();
        return;
      }
      if (button.dataset.mediaView === "delete") {
        button.dataset.mediaView = "confirm";
        button.textContent = "Confirmar exclusão";
        return;
      }
      if (button.dataset.mediaView === "confirm") {
        const id = Number(viewer?.dataset.viewingMedia);
        const result = await action("mediaDelete", { id });
        if (result?.ok) {
          await loadMedia();
          renderGalleryContent();
        }
        return;
      }
    }
    if (button.dataset.postPicker === "open") {
      event.stopImmediatePropagation();
      openPostMediaPicker();
      return;
    }
    if (button.dataset.postPicker === "close") {
      event.stopImmediatePropagation();
      q(".post-media-picker")?.remove();
      return;
    }
    if (button.dataset.postAlbum) {
      event.stopImmediatePropagation();
      postMediaAlbum = button.dataset.postAlbum;
      renderPostMediaPicker();
      return;
    }
    if (button.dataset.postMedia) {
      event.stopImmediatePropagation();
      obgramMediaId = Number(button.dataset.postMedia);
      q(".post-media-picker")?.remove();
      const select = q(".ig-compose #postMedia");
      if (select) {
        select.value = String(obgramMediaId);
        select.dataset.enhanced = "";
        q(".choose-post-media")?.remove();
        q(".selected-post-media")?.remove();
        enhanceObgramComposer();
      }
      return;
    }
    if (button.dataset.pickerAlbum) {
      event.stopImmediatePropagation();
      avatarAlbum = button.dataset.pickerAlbum;
      renderAvatarPicker();
      return;
    }
    if (button.dataset.avatarMedia) {
      event.stopImmediatePropagation();
      openAvatarEditor(button.dataset.avatarMedia);
      return;
    }
    if (button.dataset.avatarFilter) {
      event.stopImmediatePropagation();
      avatarEdit.filter = button.dataset.avatarFilter;
      q(".avatar-filters .selected")?.classList.remove("selected");
      button.classList.add("selected");
      updateAvatarEditor();
      return;
    }
    if (button.dataset.storyUser) {
      event.preventDefault();
      event.stopImmediatePropagation();
      openStoryUser(button.dataset.storyUser);
      return;
    }
    if (button.dataset.storyStep) {
      event.preventDefault();
      event.stopImmediatePropagation();
      stepStory(Number(button.dataset.storyStep));
      return;
    }
    if (button.hasAttribute("data-share-close")) {
      event.stopImmediatePropagation();
      clearInterval(nearbyRefreshTimer);
      shareAllRecipients = false;
      q(".share-sheet")?.remove();
      return;
    }
    if (button.dataset.saveContact) {
      event.stopImmediatePropagation();
      await action(
        "contact",
        {
          number: button.dataset.saveContact,
          name: button.dataset.contactName,
        },
        refresh,
      );
      return;
    }
    if (button.dataset.messageMedia) {
      event.stopImmediatePropagation();
      q(".message-gallery")?.remove();
      await action(
        "message",
        {
          to: thread,
          messageType: button.dataset.messageType,
          mediaId: Number(button.dataset.messageMedia),
        },
        refresh,
      );
      return;
    }
    if (button.hasAttribute("data-contact-own")) {
      event.stopImmediatePropagation();
      contactView = {
        name: data.shareName || data.ownerName || "Meu contato",
        number: data.number,
        avatar_url: data.deviceAvatar,
        own: true,
      };
      contactShare = contactView;
      content.innerHTML = contactsV3();
      return;
    }
    if (button.dataset.contactOpen) {
      event.stopImmediatePropagation();
      const selected = (data.contacts || []).find(
        (row) => row.contact_number === button.dataset.contactOpen,
      );
      if (selected) {
        contactView = {
          name: selected.contact_name,
          number: selected.contact_number,
          avatar_url: selected.avatar_url,
          own: false,
        };
        contactShare = contactView;
        content.innerHTML = contactsV3();
      }
      return;
    }
    if (button.dataset.shareContact) {
      event.stopImmediatePropagation();
      contactShare = {
        name: button.dataset.shareName,
        number: button.dataset.shareContact,
        own: contactView?.own === true,
      };
      handlers.shareNumber();
      return;
    }
    if (button.dataset.darkGroup) {
      event.stopImmediatePropagation();
      await openDarkGroup(button.dataset.darkGroup);
      return;
    }
    if (button.dataset.darkAction) {
      event.stopImmediatePropagation();
      const actionName = button.dataset.darkAction;
      if (actionName === "home") {
        darkGroup = null;
        content.innerHTML = darkHome();
        return;
      }
      if (actionName === "compose") {
        content.insertAdjacentHTML(
          "beforeend",
          '<section class="share-sheet dark-create"><header><b>Novo grupo privado</b><button data-share-close>×</button></header><input id="darkName" maxlength="40" placeholder="Nome do grupo"><button data-dark-action="create">Criar grupo</button></section>',
        );
        return;
      }
      if (actionName === "create") {
        const result = await action("darkchat", {
          action: "create",
          name: q("#darkName")?.value,
        });
        if (result?.ok) await render("darkchat");
        return;
      }
      if (actionName === "join") {
        const result = await action("darkchat", {
          action: "join",
          code: q("#darkCode")?.value,
        });
        if (result?.ok) await render("darkchat");
        return;
      }
      if (actionName === "send") {
        const result = await action("darkchat", {
          action: "send",
          groupId: darkGroup,
          body: q("#darkBody")?.value || "",
        });
        if (result?.ok) await openDarkGroup(darkGroup);
        return;
      }
    }
    const avatarAction = button.dataset.avatarAction;
    if (!avatarAction) return;
    event.stopImmediatePropagation();
    if (avatarAction === "close") {
      q(".avatar-picker")?.remove();
      avatarEdit = null;
    }
    if (avatarAction === "back") {
      avatarEdit = null;
      renderAvatarPicker();
    }
    if (avatarAction === "save") await saveAvatarEdit();
  },
  true,
);
content.addEventListener("input", (event) => {
  const key = event.target.dataset.avatarRange;
  if (!key || !avatarEdit) return;
  avatarEdit[key] = Number(event.target.value);
  updateAvatarEditor();
});
content.addEventListener("input", (event) => {
  if (event.target.id !== "darkSearch") return;
  const term = event.target.value.toLowerCase();
  content
    .querySelectorAll("[data-dark-group]")
    .forEach((group) =>
      group.classList.toggle(
        "hidden",
        !group.textContent.toLowerCase().includes(term),
      ),
    );
});
content.addEventListener("input", (event) => {
  if (event.target.id !== "recipientSearch") return;
  const term = event.target.value.toLowerCase();
  content
    .querySelectorAll(".contact-recipient-picker [data-thread]")
    .forEach((row) =>
      row.classList.toggle(
        "hidden",
        !row.textContent.toLowerCase().includes(term),
      ),
    );
});
content.addEventListener("input", (event) => {
  if (event.target.id !== "body") return;
  const button = q("#messageAction"),
    hasText = event.target.value.trim().length > 0;
  if (!button || window.OBMediaCapture?.audioRecording?.()) return;
  button.dataset.do = hasText ? "send" : "recordAudio";
  button.setAttribute(
    "aria-label",
    hasText ? "Enviar mensagem" : "Gravar áudio",
  );
  button.innerHTML = hasText
    ? uiIcon("send")
    : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>';
});
content.addEventListener("input", (event) => {
  if (!event.target.hasAttribute("data-audio-progress")) return;
  const audio = event.target.closest(".voice-note")?.querySelector("audio");
  if (audio) audio.currentTime = Number(event.target.value) || 0;
});
content.addEventListener("input", (event) => {
  if (event.target.id !== "contactSearch") return;
  const term = event.target.value.toLocaleLowerCase("pt-BR");
  content
    .querySelectorAll("[data-contact-open]")
    .forEach((row) =>
      row.classList.toggle(
        "hidden",
        !row.textContent.toLocaleLowerCase("pt-BR").includes(term),
      ),
    );
});
content.addEventListener("input", (event) => {
  if (event.target.id !== "shareContactSearch") return;
  const term = event.target.value.toLocaleLowerCase("pt-BR");
  content
    .querySelectorAll(".contact-share-all [data-share-to]")
    .forEach((row) =>
      row.classList.toggle(
        "hidden",
        !row.textContent.toLocaleLowerCase("pt-BR").includes(term),
      ),
    );
});
content.addEventListener(
  "click",
  async (event) => {
    const button = event.target.closest("button");
    if (!button) return;
    const postMenu = button.dataset.postMenu,
      ownAction = button.dataset.ownAction;
    if (!postMenu && !ownAction) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (postMenu) {
      showPostActions(postMenu);
      return;
    }
    if (ownAction === "close") {
      closePostSheet();
      return;
    }
    const postId = Number(button.dataset.postId),
      post = (data.posts || []).find((row) => Number(row.id) === postId);
    if (!post) return closePostSheet();
    if (ownAction === "edit") {
      closePostSheet();
      content.insertAdjacentHTML(
        "beforeend",
        '<section class="post-actions-sheet edit-post-sheet"><div class="sheet-grip"></div><h3>Editar publicação</h3><textarea id="editPostBody" maxlength="350">' +
          esc(post.body || "") +
          '</textarea><button class="primary" data-own-action="save" data-post-id="' +
          postId +
          '">Salvar alterações</button><button data-own-action="close">Cancelar</button></section>',
      );
      return;
    }
    if (ownAction === "delete") {
      closePostSheet();
      content.insertAdjacentHTML(
        "beforeend",
        '<section class="post-actions-sheet"><div class="sheet-grip"></div><h3>Excluir publicação?</h3><p>Essa ação não pode ser desfeita.</p><button class="delete" data-own-action="confirmDelete" data-post-id="' +
          postId +
          '">Excluir</button><button data-own-action="close">Cancelar</button></section>',
      );
      return;
    }
    if (ownAction === "save") {
      const body = q("#editPostBody")?.value || "";
      await action(
        "obgramAction",
        { action: "editPost", postId, body },
        refresh,
      );
      return;
    }
    if (ownAction === "confirmDelete") {
      await action("obgramAction", { action: "deletePost", postId }, refresh);
    }
  },
  true,
);
content.addEventListener("click", async (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  if (button.dataset.do) {
    handlers[button.dataset.do]?.();
    return;
  }
  if (button.dataset.obgramTab) {
    obgramTab = button.dataset.obgramTab;
    obgramCompose = false;
    content.innerHTML = obgram();
    return;
  }
  if (button.dataset.cameraMode) {
    if (window.OBMediaCapture?.recording?.())
      return toast("Finalize o vídeo antes de trocar o modo.", "error");
    cameraMode = button.dataset.cameraMode;
    content
      .querySelectorAll("[data-camera-mode]")
      .forEach((item) => item.classList.toggle("selected", item === button));
    return;
  }
  if (button.dataset.fine) {
    action("payFine", { id: button.dataset.fine }, () => render("bank"));
    return;
  }
  if (button.dataset.like) {
    action(
      "obgramAction",
      { action: "like", postId: button.dataset.like },
      refresh,
    );
    return;
  }
  if (button.dataset.follow) {
    action(
      "obgramAction",
      { action: "follow", userId: button.dataset.follow },
      refresh,
    );
    return;
  }
  if (button.dataset.comment) {
    const result = await post("obgramAction", {
        action: "comments",
        postId: button.dataset.comment,
      }),
      comments = result.ok ? result.data || [] : [];
    content.insertAdjacentHTML(
      "beforeend",
      '<section class="comments-sheet"><header><b>Comentários</b><button data-do="closeComments">×</button></header><div class="comments-list">' +
        (comments
          .map(
            (row) =>
              "<article>" +
              avatar(row.username, row.avatar_url) +
              "<p><b>@" +
              esc(row.username) +
              "</b> " +
              esc(row.body) +
              "<small>" +
              esc(row.created_at) +
              "</small></p></article>",
          )
          .join("") || empty("Nenhum comentário ainda.")) +
        '</div><div class="comments-send"><input id="commentInput" maxlength="180" placeholder="Adicione um comentário..."><button data-send-comment="' +
        Number(button.dataset.comment) +
        '">➤</button></div></section>',
    );
    handlers.closeComments = () => q(".comments-sheet")?.remove();
    return;
  }
  if (button.dataset.sendComment) {
    const input = q("#commentInput");
    action(
      "obgramAction",
      {
        action: "comment",
        postId: button.dataset.sendComment,
        body: input?.value,
      },
      refresh,
    );
    return;
  }
  if (button.dataset.thread) {
    thread = button.dataset.thread;
    render("messages");
    return;
  }
  if (button.dataset.callNumber) {
    action("call", { number: button.dataset.callNumber });
    return;
  }
  if (button.dataset.videoNumber) {
    action("call", { number: button.dataset.videoNumber, mode: "video" });
    return;
  }
  if (button.dataset.number) {
    render("call");
    q("#callNumber").value = button.dataset.number;
    return;
  }
  if (button.dataset.plate) {
    action("track", { id: Number(button.dataset.id), plate: button.dataset.plate, model: button.dataset.model });
    return;
  }
  if (button.dataset.digit) {
    q("#callNumber").value = (
      q("#callNumber").value + button.dataset.digit
    ).slice(0, 16);
    return;
  }
  if (button.dataset.case) {
    prefs.case = button.dataset.case;
    savePrefs();
    applyPrefs();
    render("settings");
    return;
  }
  if (button.dataset.wall) {
    prefs.wallpaper = button.dataset.wall;
    savePrefs();
    applyPrefs();
    render("settings");
    return;
  }
  if (button.dataset.install) {
    const id = button.dataset.install,
      installed = button.dataset.value === "true";
    await action("setAppInstalled", { appId: id, installed }, () => {
      data.installedApps = { ...(data.installedApps || {}), [id]: installed };
      render("store");
    });
    return;
  }
  if (button.dataset.key) {
    const key = button.dataset.key;
    if (key === "C") expression = "";
    else if (key === "⌫") expression = expression.slice(0, -1);
    else if (key === "=") expression = calculate();
    else
      expression = (expression === "Erro" ? "" : expression)
        .concat(key)
        .slice(0, 80);
    q("#calc").value = expression || "0";
  }
});
content.addEventListener("change", (event) => {
  if (event.target.id === "lightTheme")
    prefs.theme = event.target.checked ? "light" : "dark";
  else if (event.target.id === "silent") {
    prefs.silent = event.target.checked;
    ring();
  } else return;
  savePrefs();
  applyPrefs();
});
q("#back").onclick = goHome;
q("#homeBar").onclick = unlock;
q("#unlock").onclick = unlock;
q("#refresh").onclick = refresh;
lock.addEventListener("pointerdown", (event) => (startY = event.clientY));
lock.addEventListener("pointerup", (event) => {
  if (startY - event.clientY > 35) unlock();
});
