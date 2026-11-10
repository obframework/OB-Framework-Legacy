const $ = id => document.getElementById(id);
let busy = false, areas = [];
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_perimetro';
async function post(action, data = {}) {
  const response = await fetch(`https://${resource}/${action}`, { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(data) });
  return response.json();
}
function render() {
  $('areas').replaceChildren(); $('count').textContent = areas.length;
  if (!areas.length) { const empty = document.createElement('p'); empty.className = 'empty'; empty.textContent = 'Nenhuma área interditada no momento.'; $('areas').append(empty); }
  for (const area of areas) {
    const row = document.createElement('div'); row.className = 'area';
    const info = document.createElement('div'), name = document.createElement('div'), meta = document.createElement('div');
    name.className = 'name'; name.textContent = area.name;
    meta.className = 'meta'; meta.textContent = `${area.radius} m · Liberação às ${new Date(area.expiresAt * 1000).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}`;
    info.append(name, meta);
    const button = document.createElement('button'); button.textContent = 'Liberar área'; button.disabled = busy;
    button.onclick = () => act('remove', {id:area.id}); row.append(info,button); $('areas').append(row);
  }
}
async function act(action, data) {
  if (busy) return;
  busy = true; $('status').textContent = ''; document.querySelector('.primary').disabled = true; render();
  try { const result = await post(action,data); $('status').textContent = result.ok ? (action === 'create' ? 'Área interditada.' : 'Área liberada.') : (result.error || 'Não foi possível concluir.'); }
  catch { $('status').textContent = 'Falha de comunicação. Feche o menu e tente novamente.'; }
  finally { busy = false; document.querySelector('.primary').disabled = false; render(); }
}
window.addEventListener('message', ({data}) => {
  if (!data || !['open','close','update'].includes(data.action)) return;
  if (data.action === 'close') { $('panel').hidden = true; return; }
  areas = Array.isArray(data.areas) ? data.areas : []; render();
  if (data.action === 'open') {
    const c = data.config; $('status').textContent = ''; $('panel').hidden = false;
    for (const [id,min,max,value] of [['radius',c.MinRadius,c.MaxRadius,c.DefaultRadius],['minutes',c.MinMinutes,c.MaxMinutes,c.DefaultMinutes]]) {
      Object.assign($(id),{min,max,value});
    }
    $('name').focus();
  }
});
$('form').addEventListener('submit', event => { event.preventDefault(); act('create',{name:$('name').value,radius:Number($('radius').value),minutes:Number($('minutes').value)}); });
const close = () => post('close').catch(() => { $('status').textContent = 'Não foi possível fechar o menu.'; });
$('close').onclick = close;
document.addEventListener('keydown', event => { if (event.key === 'Escape' && !$('panel').hidden) close(); });
