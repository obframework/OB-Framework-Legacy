// Configurações do aparelho e catálogo da OB Store.

function settings() {
  const s = data.settings || {};
  return (
    '<div class="settings-page"><div class="settings-profile">' +
    avatar(data.ownerName || "Você", data.deviceAvatar) +
    "<div><b>" +
    esc(data.ownerName || "Meu aparelho") +
    "</b><small>" +
    esc(data.number) +
    " · " +
    Math.floor(Number(data.battery) || 0) +
    '%</small></div></div><section class="settings-block profile-photo-setting"><div><span><b>Foto do celular</b><small>Usada somente em Contatos e Mensagens</small></span>' +
    avatar(data.ownerName || "Você", data.deviceAvatar) +
    '</div><button data-do="openSettingsAvatar">Escolher na Galeria</button></section><section class="settings-block share-name-setting"><label for="shareName"><span><b>Nome ao compartilhar</b><small>Será o nome salvo no celular de quem receber</small></span></label><input id="shareName" maxlength="40" value="' +
    esc(data.shareName || data.ownerName || "") +
    '" placeholder="Seu nome no cartão"></section><section class="settings-block"><label class="switch-row"><span><b>Modo avião</b><small>Chamadas ficam fora de área</small></span><input type="checkbox" id="airplaneMode" ' +
    (Number(s.airplane_mode) === 1 ? "checked" : "") +
    '><i></i></label><label class="switch-row"><span><b>Notificações</b><small>Mensagens, Obgram e chamadas</small></span><input type="checkbox" id="phoneNotifications" ' +
    (Number(s.notifications) !== 0 ? "checked" : "") +
    '><i></i></label><label class="switch-row"><span><b>Notificações do DarkChat</b><small>Novas mensagens dos grupos privados</small></span><input type="checkbox" id="darkchatNotifications" ' +
    (Number(s.darkchat_notifications) !== 0 ? "checked" : "") +
    '><i></i></label><label><span><b>Toque do celular</b></span><select id="ringtone"><option value="classic">Clássico</option><option value="digital">Digital</option><option value="soft">Suave</option></select></label><button class="action" data-do="savePhoneSettings">Salvar configurações</button></section><section class="settings-block"><div><span><b>Segurança</b><small>Senha do aparelho e reconhecimento facial</small></span></div><button data-do="openPhoneSecurity">Alterar senha</button><label class="switch-row"><span><b>Reconhecimento facial</b><small>O dono desbloqueia automaticamente</small></span><input type="checkbox" id="faceRecognition" ' +
    (data.device?.faceEnabled ? "checked" : "") +
    '><i></i></label><button data-do="saveFaceRecognition">Salvar reconhecimento</button></section><div class="section-heading"><b>Aparência</b></div><div class="case-options">' +
    Object.entries(cases)
      .map(
        ([key, label]) =>
          '<button class="case-option ' +
          (prefs.case === key ? "selected" : "") +
          '" data-case="' +
          key +
          '"><img src="assets/case-' +
          key +
          '.webp" alt="">' +
          label +
          "</button>",
      )
      .join("") +
    '</div><div class="wall-options">' +
    Object.entries(walls)
      .map(
        ([key, label]) =>
          '<button class="wall-option ' +
          (prefs.wallpaper === key ? "selected" : "") +
          '" data-wall="' +
          key +
          '">' +
          label +
          "</button>",
      )
      .join("") +
    '</div><label class="switch-row"><span><b>Tema claro</b></span><input type="checkbox" id="lightTheme" ' +
    (prefs.theme === "light" ? "checked" : "") +
    "><i></i></label></div>"
  );
}
function appStore() {
  const apps = Object.values(catalog).sort((a, b) =>
    a.name.localeCompare(b.name),
  );
  return (
    '<div class="store-hero"><span>OB Store</span><h2>Aplicativos da cidade</h2><p>Instale serviços criados por outros recursos sem alterar o celular.</p></div><div class="section-heading"><b>Disponíveis</b><span>' +
    apps.length +
    '</span></div><div class="store-list">' +
    (apps
      .map((item) => {
        const installed = isInstalled(item);
        return (
          '<article class="store-app"><img src="' +
          esc(iconUrl(item)) +
          '" alt=""><div><b>' +
          esc(item.name) +
          "</b><small>" +
          esc(item.description || "Aplicativo da cidade") +
          "</small><em>" +
          esc(item.developer || "OB") +
          " · " +
          esc(item.version || "1.0") +
          '</em></div><button data-install="' +
          esc(item.id) +
          '" data-value="' +
          !installed +
          '" ' +
          (!item.removable && installed ? "disabled" : "") +
          ">" +
          (installed ? "Remover" : "Obter") +
          "</button></article>"
        );
      })
      .join("") || empty("Nenhum aplicativo extra foi publicado ainda.", "▦")) +
    "</div>"
  );
}
function storeApps() {
  const placements = data.publicConfig?.apps || {},
    builtIn = Object.entries(coreApps)
      .filter(([id]) => appMode(id) === "store")
      .map(([id, item]) => ({ id, ...item })),
    external = Object.values(catalog).filter((item) =>
      Object.prototype.hasOwnProperty.call(placements, item.id)
        ? appMode(item.id) === "store"
        : true,
    );
  return [...builtIn, ...external].sort((a, b) => a.name.localeCompare(b.name));
}
function appStoreV2() {
  const apps = storeApps();
  return (
    '<div class="store-hero"><span>OB Store</span><h2>Aplicativos da cidade</h2><p>Instale os serviços liberados na configuração do servidor.</p></div><div class="section-heading"><b>Disponíveis</b><span>' +
    apps.length +
    '</span></div><div class="store-list">' +
    (apps
      .map((item) => {
        const installed = isInstalled(item);
        return (
          '<article class="store-app"><img src="' +
          esc(iconUrl(item)) +
          '" alt=""><div><b>' +
          esc(item.name) +
          "</b><small>" +
          esc(item.description || "Aplicativo da cidade") +
          "</small><em>" +
          esc(item.developer || "OB") +
          " · " +
          esc(item.version || "1.0") +
          '</em></div><button data-install="' +
          esc(item.id) +
          '" data-value="' +
          !installed +
          '" ' +
          (!item.removable && installed ? "disabled" : "") +
          ">" +
          (installed ? "Remover" : "Obter") +
          "</button></article>"
        );
      })
      .join("") || empty("Nenhum aplicativo está disponível.", "▦")) +
    "</div>"
  );
}
