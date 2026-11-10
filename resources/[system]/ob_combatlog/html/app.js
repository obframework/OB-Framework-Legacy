const feed = document.getElementById('feed');
const safe = value => { const node = document.createElement('span'); node.textContent = value ?? ''; return node.innerHTML; };
window.addEventListener('message', event => {
  const message = event.data || {}; if (message.action !== 'show' || !message.data) return;
  const data = message.data;
  const notice = document.createElement('article'); notice.className = 'notice';
  const ids = `Sessao: ${safe(data.source ?? '?')} | ID: ${safe(data.userId ?? 'n/a')}`;
  notice.innerHTML = `<div class="icon">!</div><div><div class="title">${safe(data.name)} saiu da cidade <small>(${ids})</small></div><div class="reason">Motivo: ${safe(data.reason)}</div>${data.status ? `<div class="status">${safe(data.status)}</div>` : ''}</div>`;
  feed.prepend(notice); setTimeout(() => notice.remove(), 7600);
});
