const app=document.querySelector('#app'),accounts=document.querySelector('#accounts'),ledger=document.querySelector('#ledger');
const accountKey=document.querySelector('#accountKey'),statusText=document.querySelector('#statusText'),feedback=document.querySelector('#feedback');
let state={accounts:[],ledger:[],currency:'USD',mode:'disabled'};
const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'ob_economy';
const post=async(name,data={})=>{const response=await fetch(`https://${resource}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});return response.json()};
const money=value=>new Intl.NumberFormat('en-US',{style:'currency',currency:state.currency||'USD'}).format(Number(value)||0);
const escapeHtml=value=>String(value??'').replace(/[&<>'"]/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
function render(data){state={...state,...(data||{})};statusText.textContent=`Modo: ${state.mode} · ${state.mode==='active'?'controlando pagamentos':state.mode==='monitor'?'somente observando':'integração desativada'}`;
accounts.innerHTML=(state.accounts||[]).map(a=>`<article class="account"><span>${escapeHtml(a.label)} · ${escapeHtml(a.kind)}</span><strong>${money(a.balance)}</strong><span>${escapeHtml(a.account_key)}</span></article>`).join('');
accountKey.innerHTML=(state.accounts||[]).map(a=>`<option value="${escapeHtml(a.account_key)}">${escapeHtml(a.label)}</option>`).join('');
ledger.innerHTML=(state.ledger||[]).map(row=>`<tr><td>${escapeHtml(row.created_at)}</td><td>${escapeHtml(row.account_key)}</td><td class="${row.direction==='credit'?'credit':'debit'}">${row.direction==='credit'?'+':'−'} ${money(row.amount)}<br><small>${escapeHtml(row.status)}</small></td><td>${escapeHtml(row.category)}</td><td>${escapeHtml(row.source_resource)}${row.target_user_id?` · ID ${escapeHtml(row.target_user_id)}`:''}</td><td class="description">${escapeHtml(row.description)}</td><td>${money(row.balance_after)}</td></tr>`).join('')||'<tr><td colspan="7">Nenhum lançamento encontrado.</td></tr>'}
window.addEventListener('message',event=>{if(event.data?.action==='open'){render(event.data.data);app.classList.remove('hidden')}if(event.data?.action==='close')app.classList.add('hidden')});
document.querySelector('#close').onclick=()=>post('close');document.addEventListener('keydown',event=>{if(event.key==='Escape')post('close')});
document.querySelector('#refresh').onclick=async()=>{const result=await post('refresh',{term:document.querySelector('#term').value,category:document.querySelector('#category').value});if(result.ok)render(result.data);else show(result.error,false)};
document.querySelector('#adjustForm').onsubmit=async event=>{event.preventDefault();const result=await post('adjust',{accountKey:accountKey.value,direction:document.querySelector('#direction').value,amount:document.querySelector('#amount').value,reason:document.querySelector('#reason').value});show(result.message||result.error,result.ok);if(result.ok&&result.data)render(result.data)};
function show(message,ok){feedback.textContent=message||'';feedback.className=ok?'success':'error'}
