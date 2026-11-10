(() => {
  'use strict';

  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_lib';
  const messageHandlers = new Map();
  const escapeHandlers = new Set();
  let opened = false;

  const post = async (action, payload = {}, timeout = 15000) => {
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = controller ? window.setTimeout(() => controller.abort(), Math.max(250, Number(timeout) || 15000)) : null;
    try {
      const response = await fetch(`https://${resource}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload ?? {}),
        signal: controller?.signal,
      });
      if (!response.ok) throw new Error(`NUI ${action} respondeu ${response.status}`);
      const text = await response.text();
      return text ? JSON.parse(text) : { ok: true };
    } finally {
      if (timer) window.clearTimeout(timer);
    }
  };

  const on = (action, handler) => {
    if (typeof action !== 'string' || typeof handler !== 'function') return () => {};
    const handlers = messageHandlers.get(action) || new Set();
    handlers.add(handler);
    messageHandlers.set(action, handlers);
    return () => handlers.delete(handler);
  };

  const onEscape = handler => {
    if (typeof handler !== 'function') return () => {};
    escapeHandlers.add(handler);
    return () => escapeHandlers.delete(handler);
  };

  const setVisible = (element, visible) => {
    const target = typeof element === 'string' ? document.querySelector(element) : element;
    if (!target) return false;
    target.classList.toggle('ob-hidden', !visible);
    target.hidden = !visible;
    opened = visible;
    return true;
  };

  const reset = (root = document) => {
    root.querySelectorAll?.('.ob-modal-layer').forEach(node => node.remove());
    document.activeElement?.blur?.();
    opened = false;
  };

  const confirm = options => new Promise(resolve => {
    const settings = options && typeof options === 'object' ? options : {};
    const layer = document.createElement('section');
    layer.className = 'ob-modal-layer';
    layer.innerHTML = `
      <div class="ob-modal" role="dialog" aria-modal="true" aria-labelledby="ob-dialog-title">
        <header><h2 id="ob-dialog-title"></h2></header>
        <p></p>
        <footer>
          <button class="ob-button secondary" data-action="cancel" type="button"></button>
          <button class="ob-button" data-action="confirm" type="button"></button>
        </footer>
      </div>`;
    layer.querySelector('h2').textContent = settings.title || 'Confirmar';
    layer.querySelector('p').textContent = settings.message || '';
    const cancel = layer.querySelector('[data-action="cancel"]');
    const accept = layer.querySelector('[data-action="confirm"]');
    cancel.textContent = settings.cancelText || 'Cancelar';
    accept.textContent = settings.confirmText || 'Confirmar';
    const escape = event => { if (event.key === 'Escape') finish(false); };
    const finish = value => {
      document.removeEventListener('keydown', escape);
      layer.remove();
      resolve(value);
    };
    cancel.onclick = () => finish(false);
    accept.onclick = () => finish(true);
    layer.onclick = event => { if (event.target === layer) finish(false); };
    document.addEventListener('keydown', escape);
    document.body.append(layer);
    requestAnimationFrame(() => accept.focus());
  });

  window.addEventListener('message', event => {
    const message = event.data && typeof event.data === 'object' ? event.data : {};
    if (message.action === 'open') opened = true;
    if (message.action === 'close' || message.reset === true) {
      opened = false;
      reset();
    }
    messageHandlers.get(message.action)?.forEach(handler => {
      try { handler(message); } catch (error) { console.error('[ob_lib:nui]', error); }
    });
  });

  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || !opened) return;
    for (const handler of escapeHandlers) {
      event.preventDefault();
      handler(event);
    }
  });

  window.OBNui = Object.freeze({
    post, on, onEscape, setVisible, reset, confirm,
    isOpen: () => opened,
    setOpen: value => { opened = value === true; },
    resource,
  });
})();
