// Feed, perfis, publicações e stories do Obgram.

contactsV2 = contactsV3;
function mediaOptions() {
  return (
    '<option value="">Sem mídia</option>' +
    (data.media || [])
      .filter(
        (item) => item.media_type === "photo" || item.media_type === "video",
      )
      .map(
        (item) =>
          '<option value="' +
          Number(item.id) +
          '">' +
          (item.media_type === "video" ? "Vídeo" : "Foto") +
          " · " +
          esc(item.created_at) +
          "</option>",
      )
      .join("")
  );
}
function obgramPost(post) {
  const own = Number(post.user_id) === Number(data.profile?.user_id || 0),
    name = post.display_name || post.username;
  return (
    '<article class="ig-post" data-post-id="' +
    Number(post.id) +
    '"><header>' +
    avatar(name, post.avatar_url) +
    "<div><b>" +
    esc(name) +
    "</b><small>@" +
    esc(post.username) +
    " · Los Santos · " +
    esc(post.created_at) +
    "</small></div>" +
    (own
      ? '<button class="post-menu" data-post-menu="' +
        Number(post.id) +
        '" aria-label="Opções da publicação">•••</button>'
      : '<button class="follow" data-follow="' +
        Number(post.user_id) +
        '">' +
        (Number(post.followed) === 1 ? "Seguindo" : "Seguir") +
        "</button>") +
    "</header>" +
    (post.media_url
      ? post.media_type === "video"
        ? '<video class="ig-media" src="' +
          esc(post.media_url) +
          '" controls playsinline></video>'
        : '<img class="ig-media" src="' +
          esc(post.media_url) +
          '" alt="Publicação">'
      : '<div class="ig-text-post">' +
        esc(post.body || "Publicação sem mídia") +
        "</div>") +
    '<div class="ig-actions"><button data-like="' +
    Number(post.id) +
    '" aria-label="Curtir">' +
    (Number(post.liked) === 1 ? "♥" : "♡") +
    '</button><button class="comment-button" data-comment="' +
    Number(post.id) +
    '" aria-label="Comentar"><i></i></button></div><b class="like-count">' +
    Number(post.likes || 0) +
    " curtidas</b>" +
    (post.media_url && post.body
      ? "<p><b>@" + esc(post.username) + "</b> " + esc(post.body) + "</p>"
      : "") +
    '<button class="view-comments" data-comment="' +
    Number(post.id) +
    '">Ver os ' +
    Number(post.comments || 0) +
    " comentários</button></article>"
  );
}
function obgramNav() {
  return (
    '<nav class="ig-nav"><button data-obgram-tab="home" class="' +
    (obgramTab === "home" ? "active" : "") +
    '">⌂<small>Início</small></button><button data-obgram-tab="explore" class="' +
    (obgramTab === "explore" ? "active" : "") +
    '">◎<small>Explorar</small></button><button data-obgram-tab="activity" class="' +
    (obgramTab === "activity" ? "active" : "") +
    '">♡<small>Atividade</small></button><button data-obgram-tab="profile" class="' +
    (obgramTab === "profile" ? "active" : "") +
    '">♙<small>Perfil</small></button></nav>'
  );
}
function storyGroups(source = data.stories || []) {
  const own = Number(data.profile?.user_id || 0),
    groups = new Map();
  for (const story of source) {
    const userId = Number(story.user_id);
    if (!userId) continue;
    if (!groups.has(userId))
      groups.set(userId, {
        userId,
        own: userId === own,
        username: story.username,
        name: story.display_name || story.username,
        avatar_url: story.avatar_url,
        items: [],
      });
    groups.get(userId).items.push(story);
  }
  return [...groups.values()]
    .map((group) => {
      group.items.sort((a, b) => Number(a.id) - Number(b.id));
      group.unseen =
        !group.own && group.items.some((item) => Number(item.viewed) !== 1);
      group.latest = Math.max(...group.items.map((item) => Number(item.id)));
      return group;
    })
    .sort(
      (a, b) =>
        Number(b.own) - Number(a.own) ||
        Number(b.unseen) - Number(a.unseen) ||
        b.latest - a.latest,
    );
}
function storyBubbles(source) {
  return storyGroups(source)
    .filter((group) => !group.own)
    .map(
      (group) =>
        '<button class="story ' +
        (group.unseen ? "" : "viewed") +
        '" data-story-user="' +
        group.userId +
        '"><i>' +
        avatar(group.name, group.avatar_url) +
        "</i><small>" +
        esc(group.username) +
        "</small></button>",
    )
    .join("");
}
function closeStoryViewer() {
  clearTimeout(storyViewerTimer);
  storyViewerTimer = null;
  storyViewerState = null;
  const viewer = q(".story-viewer");
  viewer?.remove();
  if (viewer && opened && app === "obgram" && obgramTab === "home")
    content.innerHTML = obgram();
}
function renderStoryViewer() {
  clearTimeout(storyViewerTimer);
  const state = storyViewerState,
    group = state?.groups?.[state.groupIndex],
    story = group?.items?.[state.itemIndex];
  if (!story) return closeStoryViewer();
  q(".story-viewer")?.remove();
  const media =
      story.media_type === "video"
        ? '<video src="' +
          esc(story.media_url) +
          '" autoplay playsinline></video>'
        : '<img src="' + esc(story.media_url) + '" alt="Story">',
    progress = group.items
      .map(
        (_, index) =>
          '<i class="' +
          (index < state.itemIndex
            ? "done"
            : index === state.itemIndex
              ? "current"
              : "") +
          '"></i>',
      )
      .join("");
  content.insertAdjacentHTML(
    "beforeend",
    '<section class="story-viewer" data-story-id="' +
      Number(story.id) +
      '" data-story-user="' +
      group.userId +
      '"><div class="story-progress">' +
      progress +
      "</div><header>" +
      avatar(group.name, group.avatar_url) +
      "<b>" +
      esc(group.username) +
      '</b><button data-do="closeStory">×</button></header>' +
      media +
      '<button class="story-zone previous" data-story-step="-1" aria-label="Story anterior"></button><button class="story-zone next" data-story-step="1" aria-label="Próximo story"></button></section>',
  );
  if (Number(story.viewed) !== 1) {
    story.viewed = 1;
    post("obgramAction", { action: "viewStory", storyId: Number(story.id) });
  }
  const video = q(".story-viewer video");
  if (video) video.onended = () => stepStory(1);
  else storyViewerTimer = setTimeout(() => stepStory(1), 5000);
}
function openStoryUser(userId) {
  const groups = storyGroups(),
    groupIndex = groups.findIndex((group) => group.userId === Number(userId));
  if (groupIndex < 0) return;
  const items = groups[groupIndex].items,
    itemIndex = Math.max(
      0,
      items.findIndex((item) => Number(item.viewed) !== 1),
    );
  storyViewerState = { groups, groupIndex, itemIndex };
  renderStoryViewer();
}
function stepStory(direction) {
  const state = storyViewerState;
  if (!state) return;
  let group = state.groups[state.groupIndex],
    next = state.itemIndex + (direction < 0 ? -1 : 1);
  if (next >= 0 && next < group.items.length) {
    state.itemIndex = next;
    return renderStoryViewer();
  }
  const groupIndex = state.groupIndex + (direction < 0 ? -1 : 1);
  if (groupIndex < 0 || groupIndex >= state.groups.length)
    return closeStoryViewer();
  state.groupIndex = groupIndex;
  group = state.groups[groupIndex];
  state.itemIndex =
    direction < 0
      ? group.items.length - 1
      : Math.max(
          0,
          group.items.findIndex((item) => Number(item.viewed) !== 1),
        );
  renderStoryViewer();
}
function obgram() {
  const username = data.profile?.username;
  if (!username)
    return '<div class="obgram-page obgram-signup-page"><main class="obgram-signup"><div class="obgram-signup-logo">OB</div><h1>Crie sua conta</h1><p>Escolha como você será conhecido no Obgram para acessar publicações, stories e perfis.</p><label>Nome<input id="displayName" maxlength="32" autocomplete="off" placeholder="Seu nome"></label><label>Nome de usuário<div class="obgram-handle-input"><span>@</span><input id="username" maxlength="24" autocomplete="off" placeholder="seu.usuario"></div></label><small>O nome de usuário é permanente e não poderá ser alterado.</small><button class="action" data-do="username">Criar conta</button></main></div>';
  const displayName = data.profile?.display_name || username,
    stories = data.stories || [],
    posts = data.posts || [],
    ownId = Number(data.profile?.user_id || 0),
    hasOwnStory = stories.some((story) => Number(story.user_id) === ownId);
  let body = "";
  if (obgramTab === "profile") {
    body =
      '<section class="ig-profile">' +
      avatar(displayName || "OB", data.profile?.avatar_url) +
      "<h2>" +
      esc(displayName) +
      '</h2><div class="locked-handle">@' +
      esc(username) +
      " · seu @ é permanente</div><p>" +
      Number(data.profile?.followers || 0) +
      " seguidores · " +
      Number(data.profile?.following || 0) +
      ' seguindo</p><input id="displayName" maxlength="32" placeholder="Seu nome" value="' +
      esc(displayName) +
      '"><button class="action" data-do="username">Salvar nome</button>' +
      (data.media?.length
        ? '<select id="postMedia">' +
          mediaOptions() +
          '</select><button class="text-action" data-do="setAvatar">Alterar foto do perfil</button>'
        : "") +
      "</section>";
  } else if (obgramTab === "explore") {
    body =
      '<div class="ig-explore">' +
      (posts
        .filter((post) => post.media_url)
        .map((post) =>
          post.media_type === "video"
            ? '<video src="' +
              esc(post.media_url) +
              '" muted playsinline></video>'
            : '<img src="' + esc(post.media_url) + '" alt="Publicação">',
        )
        .join("") || empty("Ainda não há fotos para explorar.")) +
      "</div>";
  } else if (obgramTab === "activity") {
    body =
      '<div class="ig-activity"><h2>Notificações</h2><div><b>' +
      Number(data.profile?.followers || 0) +
      "</b><span>Pessoas seguem seu perfil.</span></div><div><b>" +
      posts.reduce((sum, post) => sum + Number(post.likes || 0), 0) +
      "</b><span>Curtidas nas publicações recentes.</span></div></div>";
  } else {
    body =
      '<div class="stories"><button class="story own-story ' +
      (hasOwnStory ? "viewed" : "") +
      '" ' +
      (hasOwnStory
        ? 'data-story-user="' + ownId + '"'
        : 'data-do="openComposer"') +
      ">" +
      avatar(displayName || "Você", data.profile?.avatar_url) +
      "<i>＋</i><small>Seu story</small></button>" +
      storyBubbles(stories) +
      "</div>" +
      (obgramCompose
        ? '<section class="ig-compose"><header><b>Nova publicação</b><button data-do="closeComposer">×</button></header><textarea id="postBody" maxlength="350" placeholder="Escreva uma legenda..."></textarea><select id="postMedia">' +
          mediaOptions() +
          '</select><div><button class="action" data-do="publish">Publicar</button><button class="story-publish" data-do="createStory">Adicionar ao story</button></div></section>'
        : "") +
      '<div class="ig-feed">' +
      (posts.map(obgramPost).join("") ||
        empty("Siga pessoas ou faça a primeira publicação.")) +
      "</div>";
  }
  return (
    '<div class="obgram-page"><header class="obgram-head"><button data-do="openComposer" aria-label="Nova publicação">＋</button><b>Obgram</b><button data-do="notifications" aria-label="Notificações">♡</button></header><main class="ig-body">' +
    body +
    "</main>" +
    obgramNav() +
    "</div>"
  );
}
