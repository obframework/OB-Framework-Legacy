const app = document.getElementById('app');
const confirmBox = document.getElementById('confirm');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ob_pausemenu';
const atlasSize = 4096;
const atlasCalibration = { zoom:16, xScale:0.02072, xOffset:117.3, yScale:0.0205, yOffset:172.8 };
let state = { profile: {}, location: {}, config: {} };
let atlas = { x:0, y:0, scale:1, fit:1, dragging:false, moved:false, startX:0, startY:0, originX:0, originY:0, waypoint:null };
let blipCatalog = {};

const blipCatalogReady = fetch('assets/blips/catalog.json').then((response) => response.json()).then((catalog) => { blipCatalog = catalog || {}; }).catch(() => {});

const $ = (id) => document.getElementById(id);
const text = (id, value, fallback = '--') => { const node = $(id); if (node) node.textContent = value === undefined || value === null || value === '' ? fallback : value; };
const money = (value) => new Intl.NumberFormat('pt-BR', { style:'currency', currency:'BRL', maximumFractionDigits:0 }).format(Number(value) || 0);

async function post(endpoint, data = {}) {
  try { const response = await fetch(`https://${resource}/${endpoint}`, { method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'}, body:JSON.stringify(data) }); return await response.json(); }
  catch (_) { return { ok:false }; }
}

function render() {
  const p = state.profile || {}, l = state.location || {}, job = p.job || {}, wallet = p.money || {};
  const first = p.firstname || (p.name || 'Cidadao').split(' ')[0];
  text('city-subtitle', state.config.citySubtitle, 'Sua historia acontece aqui');
  text('welcome-name', first, 'Cidadao');
  text('online', `${p.online ?? '--'}/${p.maxPlayers ?? '--'}`);
  text('user-id', p.userId || '--'); text('server-id', `Servidor ${p.serverId || '--'}`);
  text('cash', money(wallet.cash), '$0'); text('bank', money(wallet.bank), '$0');
  text('clock', `${String(l.hour ?? 0).padStart(2,'0')}:${String(l.minute ?? 0).padStart(2,'0')}`);
  text('map-street', l.street, 'Localizacao atual'); text('map-zone', l.zone, 'Los Santos');
  text('identity-name', p.name, 'Cidadao'); text('identity-job', job.label, 'Desempregado');
  text('identity-duty', job.onDuty ? 'Em servico' : 'Fora de servico'); text('detail-id', p.userId || '--');
  text('birthdate', p.birthdate, 'Nao informado'); text('nationality', p.nationality, 'Nao informada');
  text('health', `${Number(l.health) || 0}%`); text('armour', `${Number(l.armour) || 0}%`); text('detail-server', p.serverId || '--');
  const initials = (p.name || 'OB').split(/\s+/).slice(0,2).map((part) => part[0]).join('').toUpperCase(); text('avatar', initials, 'OB');
}

function showPage(name) {
  document.querySelectorAll('.nav').forEach((node) => node.classList.toggle('active', node.dataset.page === name));
  document.querySelectorAll('[data-page-content]').forEach((node) => node.classList.toggle('active', node.dataset.pageContent === name));
  if (name === 'map') { requestAnimationFrame(() => { fitAtlas(true); blipCatalogReady.finally(() => post('requestMap')); }); }
}

function worldToMap(coords) {
  return {
    x:(atlasCalibration.xScale*Number(coords.x)+atlasCalibration.xOffset)*atlasCalibration.zoom,
    y:(-atlasCalibration.yScale*Number(coords.y)+atlasCalibration.yOffset)*atlasCalibration.zoom
  };
}

function mapToWorld(x,y) {
  return {
    x:(x/atlasCalibration.zoom-atlasCalibration.xOffset)/atlasCalibration.xScale,
    y:(atlasCalibration.yOffset-y/atlasCalibration.zoom)/atlasCalibration.yScale
  };
}

function applyAtlas() { const stage=$('atlas-stage'); if(stage) stage.style.transform=`translate(${atlas.x}px,${atlas.y}px) scale(${atlas.scale})`; }

function centerAtlas(coords=state.location, zoom=true) {
  const viewport=$('atlas-viewport'); if(!viewport) return;
  const point=worldToMap(coords || {x:0,y:0});
  if(zoom) atlas.scale=Math.max(atlas.fit*2.7,Math.min(atlas.fit*5,atlas.scale));
  atlas.x=viewport.clientWidth/2-point.x*atlas.scale; atlas.y=viewport.clientHeight/2-point.y*atlas.scale; applyAtlas();
}

function fitAtlas(centerPlayer=false) {
  const viewport=$('atlas-viewport'); if(!viewport || !viewport.clientWidth) return;
  atlas.fit=Math.min(viewport.clientWidth/atlasSize,viewport.clientHeight/atlasSize);
  atlas.scale=atlas.fit; atlas.x=(viewport.clientWidth-atlasSize*atlas.scale)/2; atlas.y=(viewport.clientHeight-atlasSize*atlas.scale)/2; applyAtlas();
  if(centerPlayer) centerAtlas(state.location,true);
}

function zoomAtlas(multiplier, clientX, clientY) {
  const viewport=$('atlas-viewport'); if(!viewport) return;
  const rect=viewport.getBoundingClientRect(), px=(clientX??(rect.left+rect.width/2))-rect.left, py=(clientY??(rect.top+rect.height/2))-rect.top;
  const old=atlas.scale, next=Math.max(atlas.fit*.9,Math.min(atlas.fit*7,old*multiplier));
  const mapX=(px-atlas.x)/old, mapY=(py-atlas.y)/old; atlas.scale=next; atlas.x=px-mapX*next; atlas.y=py-mapY*next; applyAtlas();
}

const blipColors=['#f5f5f5','#e74c3c','#2ecc71','#3498db','#f1c40f','#9b59b6','#ecf0f1','#e67e22','#7f8c8d','#ff5bbd','#36d7ff','#9acd32','#ff8c42','#4dd0a8','#6f7cff','#ff4b4b'];
function blipIcon(sprite){ const entry=blipCatalog[String(sprite)]; return entry?.file?`assets/blips/${entry.file}`:null; }
function blipName(blip){
  if(blip.label && !/^Blip \d+$/.test(blip.label)) return blip.label;
  const raw=blipCatalog[String(blip.sprite)]?.name;
  if(!raw) return `Blip ${blip.sprite}`;
  return raw.replace(/^radar_/i,'').replaceAll('_',' ').replace(/\b\w/g,(letter)=>letter.toUpperCase());
}
function inspectBlip(blip,icon,count){
  text('atlas-blip-name',blipName(blip));
  text('atlas-blip-count',`${count} ponto${count===1?'':'s'} visível${count===1?'':'eis'} · ícone ${blip.sprite}`);
  const preview=$('atlas-blip-icon');
  if(icon){preview.src=icon;preview.classList.remove('hidden');}else{preview.removeAttribute('src');preview.classList.add('hidden');}
}
function renderAtlas(data){
  state.location=data.location||state.location; const player=worldToMap(state.location), playerNode=$('atlas-player');
  playerNode.style.left=`${player.x}px`; playerNode.style.top=`${player.y}px`; text('atlas-place',`${state.location.street||'Localizacao atual'}${state.location.zone?` · ${state.location.zone}`:''}`);
  const waypointNode=$('atlas-waypoint');
  if(data.waypoint && Number.isFinite(Number(data.waypoint.x)) && Number.isFinite(Number(data.waypoint.y))){
    atlas.waypoint=worldToMap(data.waypoint); waypointNode.style.left=`${atlas.waypoint.x}px`; waypointNode.style.top=`${atlas.waypoint.y}px`; waypointNode.classList.remove('hidden');
  }else{atlas.waypoint=null;waypointNode.classList.add('hidden');}
  const layer=$('atlas-blips'); layer.replaceChildren();
  const visible=(data.blips||[]).filter((blip)=>{const p=worldToMap(blip);blip._map=p;return p.x>=0&&p.x<=atlasSize&&p.y>=0&&p.y<=atlasSize;});
  text('atlas-blip-name','Passe o mouse em um blip');
  text('atlas-blip-count',`${visible.length} ponto${visible.length===1?'':'s'} carregado${visible.length===1?'':'s'} no mapa`);
  $('atlas-blip-icon')?.classList.add('hidden');
  visible.forEach((blip)=>{ const p=blip._map,sprite=Number(blip.sprite),icon=blipIcon(sprite); const node=document.createElement('i'); node.className=`atlas-blip${icon?' has-icon':' fallback'}`; node.style.left=`${p.x}px`; node.style.top=`${p.y}px`; node.style.setProperty('--blip',blipColors[Math.abs(Number(blip.color)||0)%blipColors.length]); if(icon){const image=document.createElement('img');image.src=icon;image.alt='';image.draggable=false;image.onerror=()=>{node.classList.remove('has-icon');node.classList.add('fallback');image.remove();node.dataset.glyph=String(sprite);};node.appendChild(image);}else{node.dataset.glyph=String(sprite);} const label=document.createElement('span'); label.textContent=blipName(blip); node.appendChild(label); node.addEventListener('mouseenter',()=>inspectBlip(blip,icon,visible.length)); layer.appendChild(node); });
  centerAtlas(state.location,true);
}

const viewport=$('atlas-viewport');
async function removeAtlasWaypoint(){
  const result=await post('clearWaypoint');
  if(!result?.ok)return false;
  atlas.waypoint=null;
  $('atlas-waypoint')?.classList.add('hidden');
  const toast=$('atlas-toast');toast.textContent='GPS removido';toast.classList.remove('hidden');setTimeout(()=>toast.classList.add('hidden'),1800);
  return true;
}
$('atlas-waypoint')?.addEventListener('dblclick',async(event)=>{event.preventDefault();event.stopPropagation();await removeAtlasWaypoint();});
viewport?.addEventListener('wheel',(event)=>{event.preventDefault();zoomAtlas(event.deltaY<0?1.17:.855,event.clientX,event.clientY)},{passive:false});
viewport?.addEventListener('pointerdown',(event)=>{atlas.dragging=true;atlas.moved=false;atlas.startX=event.clientX;atlas.startY=event.clientY;atlas.originX=atlas.x;atlas.originY=atlas.y;viewport.setPointerCapture(event.pointerId);viewport.classList.add('dragging');});
viewport?.addEventListener('pointermove',(event)=>{if(!atlas.dragging)return;const dx=event.clientX-atlas.startX,dy=event.clientY-atlas.startY;if(Math.abs(dx)+Math.abs(dy)>5)atlas.moved=true;atlas.x=atlas.originX+dx;atlas.y=atlas.originY+dy;applyAtlas();});
viewport?.addEventListener('pointerup',()=>{if(!atlas.dragging)return;atlas.dragging=false;viewport.classList.remove('dragging');});
viewport?.addEventListener('dblclick',async(event)=>{if(atlas.moved||event.target.closest('.atlas-blip')||event.target.closest('#atlas-waypoint'))return;event.preventDefault();if(atlas.waypoint){await removeAtlasWaypoint();return;}const rect=viewport.getBoundingClientRect(),mx=(event.clientX-rect.left-atlas.x)/atlas.scale,my=(event.clientY-rect.top-atlas.y)/atlas.scale;if(mx<0||mx>atlasSize||my<0||my>atlasSize)return;const pin=$('atlas-waypoint'),toast=$('atlas-toast');const world=mapToWorld(mx,my),result=await post('setWaypoint',world);if(result?.ok){atlas.waypoint={x:mx,y:my};pin.style.left=`${mx}px`;pin.style.top=`${my}px`;pin.classList.remove('hidden');toast.textContent='Rota marcada no GPS';toast.classList.remove('hidden');setTimeout(()=>toast.classList.add('hidden'),1800);}});

document.addEventListener('click', (event) => {
  const nav = event.target.closest('[data-page]'); if (nav) return showPage(nav.dataset.page);
  const link = event.target.closest('[data-page-link]'); if (link) return showPage(link.dataset.pageLink);
  const action = event.target.closest('[data-action]')?.dataset.action;
  if (action === 'close') post('close');
  if (action === 'refresh') post('refresh');
  if (action === 'native-map') post('openNativeMap');
  if (action === 'native-settings') post('openNativeSettings');
  if (action === 'hud-settings') post('openHudSettings');
  if (action === 'disconnect') confirmBox.classList.remove('hidden');
  const mapControl = event.target.closest('[data-map-control]')?.dataset.mapControl;
  if (mapControl === 'in') zoomAtlas(1.2);
  if (mapControl === 'out') zoomAtlas(.833);
  if (mapControl === 'center') centerAtlas(state.location,true);
  const decision = event.target.closest('[data-confirm]')?.dataset.confirm;
  if (decision === 'no') confirmBox.classList.add('hidden');
  if (decision === 'yes') post('disconnect');
});

document.addEventListener('keydown', (event) => { if (event.key === 'Escape') { if (!confirmBox.classList.contains('hidden')) confirmBox.classList.add('hidden'); else post('close'); } });

window.addEventListener('message', ({ data }) => {
  if (!data || typeof data !== 'object') return;
  if (data.action === 'open') { state = { profile:data.profile || {}, location:data.location || {}, config:data.config || {} }; render(); showPage('home'); confirmBox.classList.add('hidden'); app.classList.remove('hidden'); app.setAttribute('aria-hidden','false'); }
  if (data.action === 'update') { state.profile = data.profile || state.profile; state.location = data.location || state.location; state.config = data.config || state.config; render(); }
  if (data.action === 'close') { app.classList.add('hidden'); app.setAttribute('aria-hidden','true'); }
  if (data.action === 'location') { state.location = data.location || {}; render(); }
  if (data.action === 'mapData') renderAtlas(data);
});

window.addEventListener('resize',()=>{if(document.querySelector('[data-page-content="map"]')?.classList.contains('active'))fitAtlas(true);});
