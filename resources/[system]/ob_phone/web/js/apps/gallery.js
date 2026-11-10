// Galeria, seletores de mídia e editor de foto de perfil.

async function loadMedia() {
  const result = await post("mediaList");
  if (result.ok) {
    const unique = new Map();
    for (const item of result.data || []) {
      const key = String(item.media_url || item.id);
      if (!unique.has(key)) unique.set(key, item);
    }
    data.media = [...unique.values()];
  }
  return result;
}
function mediaForAlbum(album, photosOnly = false) {
  return (data.media || []).filter(
    (item) =>
      (!photosOnly || item.media_type === "photo") &&
      (album === "all" ||
        (album === "videos" && item.media_type === "video") ||
        (album === "audios" && item.media_type === "audio") ||
        (album === "obgram" && Number(item.used_in_obgram) === 1) ||
        (album === "camera" &&
          item.media_type === "photo" &&
          Number(item.used_in_obgram) !== 1)),
  );
}
function albumTabs(selected, picker = false) {
  return (
    '<div class="gallery-albums">' +
    [
      ["all", "Todos"],
      ["camera", "Câmera"],
      ["obgram", "Obgram"],
      ["videos", "Vídeos"],
      ["audios", "Áudios"],
    ]
      .map(
        ([id, label]) =>
          '<button class="' +
          (selected === id ? "selected" : "") +
          '" data-' +
          (picker ? "picker" : "gallery") +
          '-album="' +
          id +
          '">' +
          label +
          "</button>",
      )
      .join("") +
    "</div>"
  );
}
function galleryGrid(items, picker = false) {
  return (
    '<div class="gallery-grid">' +
    (items
      .map(
        (item) =>
          '<button class="gallery-item" ' +
          (picker ? "data-avatar-media" : "data-gallery-media") +
          '="' +
          Number(item.id) +
          '">' +
          (item.media_type === "video"
            ? '<video src="' +
              esc(item.media_url) +
              '" muted playsinline></video><i class="video-mark">▶</i>'
            : item.media_type === "audio"
              ? '<span class="audio-tile">♫<small>Áudio</small></span>'
              : '<img src="' + esc(item.media_url) + '" alt="Foto">') +
          "</button>",
      )
      .join("") || empty("Nenhuma mídia nesta pasta.", "▧")) +
    "</div>"
  );
}
function renderGalleryContent() {
  content.innerHTML =
    '<div class="gallery-head"><b>Galeria</b><button class="open-camera" data-app="camera"><i></i><span>Abrir câmera</span></button></div>' +
    albumTabs(galleryAlbum) +
    galleryGrid(mediaForAlbum(galleryAlbum));
  content
    .querySelector('[data-app="camera"]')
    ?.addEventListener("click", () => render("camera"));
}
function openMediaViewer(id) {
  const item = (data.media || []).find((row) => Number(row.id) === Number(id));
  if (!item) return;
  const label =
      item.media_type === "video"
        ? "Vídeo"
        : item.media_type === "audio"
          ? "Áudio"
          : "Foto",
    viewer =
      item.media_type === "video"
        ? '<video src="' +
          esc(item.media_url) +
          '" controls autoplay playsinline></video>'
        : item.media_type === "audio"
          ? '<audio src="' +
            esc(item.media_url) +
            '" controls autoplay></audio>'
          : '<img src="' + esc(item.media_url) + '" alt="Foto">';
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="media-viewer" data-viewing-media="' +
      Number(item.id) +
      '"><header><button data-media-view="close">×</button><b>' +
      label +
      '</b><button class="delete-media" data-media-view="delete">Excluir</button></header>' +
      viewer +
      "</section>",
  );
}
async function gallery(version) {
  content.innerHTML = empty("Abrindo sua galeria...");
  const result = await loadMedia();
  if (version !== pageVersion) return;
  if (!result.ok) {
    content.innerHTML = empty(esc(result.message || "Galeria indisponível."));
    return;
  }
  renderGalleryContent();
}
function renderAvatarPicker() {
  const photos = mediaForAlbum(avatarAlbum, true),
    picker = q(".avatar-picker");
  if (!picker) return;
  picker.innerHTML =
    '<header><button data-avatar-action="close">‹</button><b>Escolher foto</b><span></span></header>' +
    albumTabs(avatarAlbum, true) +
    galleryGrid(photos, true);
}
function openAvatarPicker(target = "obgram") {
  avatarTarget = target;
  q(".avatar-picker")?.remove();
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="avatar-picker"></section>',
  );
  renderAvatarPicker();
}
function avatarFilter(name) {
  return (
    {
      normal: "none",
      vivo: "saturate(1.45) contrast(1.08)",
      pb: "grayscale(1)",
      quente: "sepia(.35) saturate(1.3)",
      frio: "saturate(.9) hue-rotate(175deg)",
    }[name] || "none"
  );
}
function updateAvatarEditor() {
  const img = q("#avatarCropImage");
  if (!img || !avatarEdit) return;
  const limit = ((avatarEdit.zoom - 1) * 50) / avatarEdit.zoom,
    tx = ((50 - avatarEdit.x) / 50) * limit,
    ty = ((50 - avatarEdit.y) / 50) * limit;
  img.style.objectPosition = "center";
  img.style.transform =
    "translate(" + tx + "%," + ty + "%) scale(" + avatarEdit.zoom + ")";
  img.style.filter = avatarFilter(avatarEdit.filter);
}
function openAvatarEditor(id) {
  const item = (data.media || []).find((row) => Number(row.id) === Number(id));
  if (!item || item.media_type !== "photo") return;
  avatarEdit = { item, x: 50, y: 50, zoom: 1.25, filter: "normal" };
  const picker = q(".avatar-picker");
  picker.innerHTML =
    '<header><button data-avatar-action="back">‹</button><b>Editar foto</b><button data-avatar-action="save">Salvar</button></header><div class="avatar-crop"><img id="avatarCropImage" crossorigin="anonymous" src="' +
    esc(item.media_url) +
    '" alt=""></div><label>Horizontal<input data-avatar-range="x" type="range" min="0" max="100" value="50"></label><label>Vertical<input data-avatar-range="y" type="range" min="0" max="100" value="50"></label><label>Zoom<input data-avatar-range="zoom" type="range" min="1" max="3" step=".05" value="1.25"></label><div class="avatar-filters">' +
    [
      ["normal", "Normal"],
      ["vivo", "Vivo"],
      ["pb", "P&B"],
      ["quente", "Quente"],
      ["frio", "Frio"],
    ]
      .map(
        ([id, label]) =>
          '<button class="' +
          (id === "normal" ? "selected" : "") +
          '" data-avatar-filter="' +
          id +
          '">' +
          label +
          "</button>",
      )
      .join("") +
    "</div>";
  updateAvatarEditor();
}
async function saveAvatarEdit() {
  if (!avatarEdit) return;
  const source = new Image();
  source.crossOrigin = "anonymous";
  source.src = avatarEdit.item.media_url;
  try {
    await source.decode();
  } catch {
    return toast("Não foi possível editar essa imagem.", "error");
  }
  const size =
      Math.min(source.naturalWidth, source.naturalHeight) / avatarEdit.zoom,
    sx = (source.naturalWidth - size) * (avatarEdit.x / 100),
    sy = (source.naturalHeight - size) * (avatarEdit.y / 100),
    canvas = document.createElement("canvas");
  canvas.width = canvas.height = 512;
  const ctx = canvas.getContext("2d");
  ctx.filter = avatarFilter(avatarEdit.filter);
  ctx.drawImage(source, sx, sy, size, size, 0, 0, 512, 512);
  const blob = await new Promise((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", 0.92),
  );
  if (!blob) return toast("Não foi possível gerar a foto.", "error");
  try {
    const saved = await uploadMedia(blob, "photo", avatarEdit.item.id),
      endpoint = avatarTarget === "device" ? "phoneSettings" : "obgramAction",
      payload = {
        action: "avatar",
        mediaId: saved.id,
        variantId: saved.variant_id,
      };
    await action(endpoint, payload, async () => {
      q(".avatar-picker")?.remove();
      avatarEdit = null;
      await refresh();
    });
  } catch (error) {
    toast(error.message || "Falha ao salvar avatar.", "error");
  }
}
function renderPostMediaPicker() {
  const picker = q(".post-media-picker");
  if (!picker) return;
  const items = mediaForAlbum(postMediaAlbum);
  picker.innerHTML =
    '<header><button data-post-picker="close">‹</button><b>Galeria</b><span></span></header>' +
    albumTabs(postMediaAlbum).replaceAll(
      "data-gallery-album",
      "data-post-album",
    ) +
    '<div class="gallery-grid">' +
    (items
      .map(
        (item) =>
          '<button class="gallery-item" data-post-media="' +
          Number(item.id) +
          '">' +
          (item.media_type === "video"
            ? '<video src="' +
              esc(item.media_url) +
              '" muted playsinline></video>'
            : '<img src="' + esc(item.media_url) + '" alt="Foto">') +
          "</button>",
      )
      .join("") || empty("Nenhuma mídia nesta pasta.", "▧")) +
    "</div>";
}
function openPostMediaPicker() {
  q(".post-media-picker")?.remove();
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="avatar-picker post-media-picker"></section>',
  );
  renderPostMediaPicker();
}
function enhanceObgramComposer() {
  const select = q(".ig-compose #postMedia");
  if (!select || select.dataset.enhanced) return;
  select.dataset.enhanced = "true";
  select.classList.add("hidden");
  if (obgramMediaId) select.value = String(obgramMediaId);
  const item = (data.media || []).find(
    (row) => Number(row.id) === Number(select.value),
  );
  select.insertAdjacentHTML(
    "afterend",
    '<button class="choose-post-media" data-post-picker="open">' +
      (item ? "Trocar mídia" : "Escolher na Galeria") +
      "</button>" +
      (item
        ? '<div class="selected-post-media">' +
          (item.media_type === "video"
            ? '<video src="' + esc(item.media_url) + '" muted></video>'
            : '<img src="' + esc(item.media_url) + '" alt="">') +
          "<span>" +
          esc(
            item.media_type === "video"
              ? "Vídeo selecionado"
              : "Foto selecionada",
          ) +
          "</span></div>"
        : ""),
  );
}
new MutationObserver(() => {
  enhanceObgramComposer();
  const screen = q(".screen");
  screen.classList.toggle("app-active", opened && !!app);
  screen.classList.toggle("obgram-active", opened && app === "obgram");
  screen.classList.toggle("darkchat-active", opened && app === "darkchat");
  screen.classList.toggle("messages-active", opened && app === "messages");
  content.classList.toggle(
    "thread-mode",
    opened && app === "messages" && !!q(".message-thread"),
  );
}).observe(content, { childList: true, subtree: true });
