const app = document.querySelector("#app"),
  tabs = [...document.querySelectorAll(".tab")],
  nav = [...document.querySelectorAll(".nav")];
let data = null,
  preview = 1;
const post = (action, payload = {}) =>
  fetch(`https://${GetParentResourceName()}/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).catch(() => {});
const money = (value) => window.OBCurrency?.format(value) ?? `$${Number(value || 0).toLocaleString('en-US')}`;
const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const person = (member) => {
  const name = String(member.name || `ID ${member.id}`);
  return `<article class="person"><span class="avatar">${escapeHtml(name.slice(0,1).toUpperCase())}</span><span class="name">${escapeHtml(name)}${member.leader ? '<small class="leader">Lider</small>' : ''}</span></article>`;
};
function setTutorial(tutorial) {
  const value = String(tutorial?.youtubeUrl || "").trim();
  const match = value.match(/(?:youtu\.be\/|(?:youtube(?:-nocookie)?\.com)\/(?:watch\?v=|embed\/|shorts\/))([^?&#/]+)/i);
  const embed = match ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(match[1])}?rel=0` : "";
  document.querySelector("#tutorialTitle").textContent = tutorial?.title || "Tutorial";
  document.querySelector("#tutorialEmpty").style.display = embed ? "none" : "block";
  const frame = document.querySelector("#tutorialVideo");
  frame.style.display = embed ? "block" : "none";
  frame.src = embed;
}
function setTab(id) {
  tabs.forEach((n) => n.classList.toggle("active", n.id === id));
  nav.forEach((n) => n.classList.toggle("active", n.dataset.tab === id));
  document.querySelector("#title").textContent = {
    overview: "Visão geral",
    progress: "Progresso",
    contract: "Contrato",
    group: "Grupo",
    ranking: "Ranking",
  }[id];
}
function renderPreview(p) {
  preview = Math.max(1, Math.min(10, preview));
  const bonus = (preview - 1) * Number(p.paymentBonusStep || 2.5);
  document.querySelector("#previewTitle").textContent = `Nível: ${preview}`;
  document.querySelector("#previewXp").textContent =
    `${(preview - 1) * Number(p.xpRequired || 500)} XP`;
  document.querySelector("#previewBonus").textContent = `+${bonus}%`;
  document.querySelector("#previewText").textContent =
    preview === 1
      ? "Pagamento padrão por caixa entregue."
      : `+${bonus}% no pagamento de cada caixa entregue.`;
  document.querySelector("#prev").disabled = preview === 1;
  document.querySelector("#next").disabled = preview === 10;
}
function update(payload) {
  if (!payload) return;
  data = payload;
  const p = payload.progress || {},
    w = payload.work || {},
    c = payload.contract || {},
    g = payload.group || { members: [], maxMembers: 2, isLeader: true },
    percent = Math.min(
      100,
      (100 * Number(p.xpInLevel || 0)) / Math.max(1, Number(p.xpRequired || 1)),
    ),
    contractPercent = Math.min(
      100,
      (100 * Number(c.delivered || 0)) / Math.max(1, Number(c.target || 1)),
    );
  document.querySelector("#level").textContent = p.level || 1;
  document.querySelector("#xpText").textContent =
    `${p.xpInLevel || 0} / ${p.xpRequired || 0} XP`;
  document.querySelector("#xpBar").style.width = `${percent}%`;
  document.querySelector("#boxes").textContent = p.boxesDelivered || 0;
  document.querySelector("#earned").textContent = money(p.totalEarned);
  document.querySelector("#bonus").textContent = `+${p.paymentBonus || 0}%`;
  document.querySelector("#progressLevel").textContent =
    `Nível: ${p.level || 1}`;
  document.querySelector("#progressBar").style.width = `${percent}%`;
  document.querySelector("#progressDetails").textContent =
    `${Math.floor(percent)}%`;
  document.querySelector("#status").textContent = w.active
    ? "Em turno"
    : "Fora de turno";
  document.querySelector("#statusInfo").textContent = w.active
    ? `${w.boxes || 0} caixas no caminhão${w.destination ? " | Entrega marcada" : ""}`
    : "Fale com o responsável para iniciar";
  document.querySelector("#turnHint").textContent = w.active
    ? "Retire o caminhão para transportar as caixas. Pegue baldes vazios quando precisar ordenhar novamente."
    : "Inicie o turno para liberar o caminhão e os baldes.";
  document.querySelector("#start").textContent = w.active
    ? "Finalizar trabalho"
    : "Iniciar trabalho";
  document.querySelector("#start").classList.toggle("danger", !!w.active);
  document.querySelector("#start").disabled = g.isLeader === false;
  if (g.isLeader === false) document.querySelector("#start").textContent = "Aguardando o lider";
  document.querySelector("#truck").classList.toggle("hidden", !w.active);
  document.querySelector("#buckets").classList.toggle("hidden", !w.active);
  document
    .querySelector("#payment")
    .classList.toggle("hidden", Number(w.pending || 0) <= 0);
  document.querySelector("#payment").textContent =
    `Receber ${money(w.pending)}`;
  document.querySelector("#pending").textContent = money(w.pending);
  document.querySelector("#contractTitle").textContent = c.unlocked
    ? `${c.delivered || 0} / ${c.target || 0} caixas`
    : "Bloqueado";
  document.querySelector("#contractBar").style.width = c.unlocked
    ? `${contractPercent}%`
    : "0%";
  document.querySelector("#contractInfo").textContent = c.unlocked
    ? c.complete
      ? `Contrato concluído: +${Math.floor(Number(c.bonus || 0) * 100)}% ao receber.`
      : `Complete a meta para ganhar +${Math.floor(Number(c.bonus || 0) * 100)}% no pagamento final.`
    : "Desbloqueia no nível 3.";
  const members = g.members || [];
  document.querySelector('#groupCount').textContent = `${members.length}/${g.maxMembers || 2}`;
  document.querySelector('#groupDescription').textContent = g.isLeader ? 'Convide uma pessoa que esteja proxima.' : 'O lider inicia e finaliza o trabalho da dupla.';
  document.querySelector('#members').innerHTML = members.map(person).join('') || '<div class="empty">Nenhum integrante.</div>';
  document.querySelector('#leaveGroup').classList.toggle('hidden', members.length <= 1 || !!w.active);
  const nearby = (payload.nearby || []).filter((entry) => !members.some((member) => Number(member.id) === Number(entry.id)));
  document.querySelector('#nearby').innerHTML = nearby.length
    ? nearby.map((entry) => `<article class="person"><span class="avatar">${escapeHtml(String(entry.name).slice(0,1).toUpperCase())}</span><span class="name">${escapeHtml(entry.name)}</span>${g.isLeader && !w.active && members.length < (g.maxMembers || 2) ? `<button class="invite" data-id="${Number(entry.id)}">Convidar</button>` : ''}</article>`).join('')
    : '<div class="empty">Ninguem proximo para convidar.</div>';
  document.querySelectorAll('.invite').forEach((button) => button.addEventListener('click', () => post('invite', { id:Number(button.dataset.id) })));
  const board = payload.leaderboard || {},
    list = board.list || [];
  document.querySelector("#leaderboard").innerHTML = list.length
    ? list
        .map(
          (e) =>
            `<div class="ranking-row"><span>#${e.rank}</span><span>${e.name || "Desconhecido"}</span><b>${e.xp || 0} XP</b></div>`,
        )
        .join("")
    : '<div class="empty">Ainda não há dados no ranking.</div>';
  document.querySelector("#rank").textContent = board.myRank
    ? `#${board.myRank}`
    : "#-";
  document.querySelector("#rankValue").textContent = `${board.myValue || 0} XP`;
  renderPreview(p);
}
nav.forEach((n) => (n.onclick = () => setTab(n.dataset.tab)));
nav.forEach((n) => n.addEventListener("click", () => {
  if (n.dataset.tab === "tutorial") document.querySelector("#title").textContent = "Tutorial";
}));
document.querySelector("#close").onclick = () => post("close");
document.querySelector("#start").onclick = () =>
  post(data?.work?.active ? "stop" : "start");
document.querySelector("#truck").onclick = () => post("truck");
document.querySelector("#buckets").onclick = () => post("buckets");
document.querySelector("#payment").onclick = () => post("payment");
document.querySelector('#leaveGroup').onclick = () => post('leaveGroup');
document.querySelector("#prev").onclick = () => {
  preview--;
  renderPreview(data?.progress || {});
};
document.querySelector("#next").onclick = () => {
  preview++;
  renderPreview(data?.progress || {});
};
addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !app.classList.contains("hidden")) post("close");
});
addEventListener("message", (e) => {
  const { action, payload } = e.data || {};
  if (action === "open") {
    app.classList.remove("hidden");
    preview = payload?.progress?.level || 1;
    setTutorial(payload?.tutorial);
    update(payload);
    setTab("overview");
  }
  if (action === "update") update(payload);
  if (action === "close") app.classList.add("hidden");
});
