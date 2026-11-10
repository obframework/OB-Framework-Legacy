const container = document.getElementById('notifications');
const icons = { success: '✓', error: '!', warning: '!', info: 'i', inform: 'i' };

function push(data) {
  const type = ['success', 'error', 'warning'].includes(data.notificationType) ? data.notificationType : 'info';
  const element = document.createElement('article');
  element.className = `notification ${type}`;
  element.innerHTML = `<span class="notification-icon">${icons[type]}</span><p></p>`;
  element.querySelector('p').textContent = String(data.message || '');
  container.appendChild(element);

  while (container.children.length > 5) container.removeChild(container.firstElementChild);
  window.setTimeout(() => {
    element.classList.add('out');
    window.setTimeout(() => element.remove(), 180);
  }, Math.max(1500, Math.min(15000, Number(data.duration) || 4500)));
}

window.addEventListener('message', ({ data }) => {
  if (data?.action === 'notify') push(data);
});
