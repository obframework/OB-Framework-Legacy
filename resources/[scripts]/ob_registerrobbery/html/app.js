const app=document.querySelector('#app'), form=document.querySelector('#form'), list=document.querySelector('#list'), status=document.querySelector('#status');
let rows=[], selected=null, waiting=false;
const fields=['id','label','x','y','z','w','minimum','maximum','police','seconds','cooldown'];
async function post(name,data={}) {
  const response=await fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  return response.json();
}
function render(){
  list.replaceChildren();
  const query=document.querySelector('#search').value.toLowerCase();
  for(const row of rows.filter(row=>`${row.id} ${row.label}`.toLowerCase().includes(query))){
    const button=document.createElement('button'); button.type='button'; button.textContent=row.label;
    const sub=document.createElement('small'); sub.textContent=row.id; button.append(sub);
    button.classList.toggle('selected',row.id===selected); button.onclick=()=>select(row); list.append(button);
  }
}
function select(row){
  selected=row?.id??null;
  const value=row?{...row,...row.coords}:{id:'',label:'',x:0,y:0,z:0,w:0,minimum:500,maximum:1500,police:1,seconds:12,cooldown:900};
  for(const key of fields)form.elements.namedItem(key).value=value[key];
  form.elements.namedItem('id').readOnly=!!selected;
  form.elements.namedItem('spawnProp').checked=!!row?.spawnProp;
  document.querySelector('#teleport').disabled=!selected;
  document.querySelector('#delete').disabled=!selected;
  status.textContent=''; render();
}
async function perform(action){
  if(waiting)return; waiting=true;
  try{await action();}catch(e){status.textContent='Falha de comunicacao com o servidor.';}finally{waiting=false;}
}
form.onsubmit=event=>{event.preventDefault();perform(async()=>{
  const data=Object.fromEntries(new FormData(form));
  data.coords={}; for(const key of ['x','y','z','w'])data.coords[key]=Number(data[key]);
  for(const key of ['minimum','maximum','police','seconds','cooldown'])data[key]=Number(data[key]);
  data.spawnProp=form.elements.namedItem('spawnProp').checked;
  const response=await post('editorSave',data);
  if(response.ok){rows=response.data.rows; select(rows.find(row=>row.id===data.id));}
  status.textContent=response.message||'Salvo.';
});};
document.querySelector('#new').onclick=()=>select(null);
document.querySelector('#search').oninput=render;
document.querySelector('#capture').onclick=()=>perform(async()=>{
  const result=await post('capture');
  if(result.ok)for(const [key,value]of Object.entries(result.coords))form.elements.namedItem(key).value=Number(value).toFixed(4);
});
document.querySelector('#teleport').onclick=()=>perform(async()=>{
  const response=await post('editorTeleport',{id:selected}); status.textContent=response.message||'';
});
document.querySelector('#delete').onclick=()=>perform(async()=>{
  const button=document.querySelector('#delete');
  if(button.dataset.confirm!==selected){button.dataset.confirm=selected;status.textContent='Clique em Excluir novamente para confirmar.';return;}
  delete button.dataset.confirm;
  const response=await post('editorDelete',{id:selected});
  if(response.ok){rows=response.data.rows;select(null);}
  status.textContent=response.message||'';
});
document.querySelector('#close').onclick=()=>post('close');
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!app.hidden)post('close');});
window.addEventListener('message',({data})=>{
  if(data.action==='close'){app.hidden=true;return;}
  if(data.action==='open'){rows=data.rows||[];app.hidden=false;select(rows[0]||null);}
});
