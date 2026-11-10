const $=id=>document.getElementById(id);
let busy=false,quiz=null,index=0,answers={},timer=null,deadline=0,epoch=0;
const money=n=>`$ ${Number(n).toLocaleString('pt-BR')}`;
const node=(tag,text,cls)=>{const e=document.createElement(tag);e.textContent=text;if(cls)e.className=cls;return e;};
async function post(action,data={}){const r=await fetch(`https://${GetParentResourceName()}/${action}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});return r.json();}
async function request(action,data,done){
 if(busy)return;busy=true;const token=epoch;$('error').textContent='';
 try{const r=await post(action,data);if(token!==epoch)return;if(!r.ok)$('error').textContent=r.error||'Operação indisponível.';else done(r.data);}
 catch{if(token===epoch)$('error').textContent='Falha de comunicação. Tente novamente.';}
 finally{busy=false;}
}
function button(text,click){const b=node('button',text);b.onclick=click;return b;}
function screen(){clearInterval(timer);$('content').replaceChildren();$('content').className='';$('error').textContent='';$('footer').textContent='ESC para sair';}
function school(data){
 screen();quiz=null;$('footer').textContent='ESC para sair · Fechar uma prova iniciada cancela a tentativa.';$('title').textContent='Centro de licenças';$('info').textContent=data.notice||`Teórica: ${money(data.theory.fee)} · ${data.theory.questionAmount} questões · Até ${data.theory.maxErrors} erros · Primeira prática gratuita.`;$('content').className='grid';
 const documents=data.documents||null,driver=documents&&documents.driver;
 if(driver){const driverCard=node('article','','card document-card'),combined=Number(driver.renewalFee||0)+Number(driver.replacementFee||0);let driverText='Conclua uma categoria para emitir sua CNH.',driverButton='CNH indisponível';
 if(driver.eligible){if(driver.hasItem&&!driver.expired){driverText=`Documento válido por ${driver.daysLeft} dia(s).`;driverButton='CNH emitida';}else if(driver.expired&&driver.hasItem){driverText='Documento vencido. Renove para voltar a usar as categorias.';driverButton=`Renovar · ${money(driver.renewalFee)}`;}else if(driver.expired&&driver.issued){driverText='Documento vencido e sem a via física.';driverButton=`Renovar + 2ª via · ${money(combined)}`;}else if(driver.issued){driverText=`Documento válido por ${driver.daysLeft} dia(s), mas a via física foi perdida.`;driverButton=`Segunda via · ${money(driver.replacementFee)}`;}else{driverText='Primeira emissão gratuita após a aprovação.';driverButton='Emitir CNH';}}
 driverCard.append(node('div','DOCUMENTO','tag'),node('h2','Carteira de motorista'),node('p',driverText));const driverAction=button(driverButton,()=>request('document',{kind:'driver'},school));driverAction.disabled=!driver.eligible||(driver.hasItem&&!driver.expired);driverCard.append(driverAction);$('content').append(driverCard);}
 for(const c of data.categories){const card=node('article','','card');card.append(node('div',`CATEGORIA ${c.class}`,'tag'),node('h2',c.label),node('p',c.owned?(c.expired?'Categoria registrada; renove a CNH para voltar a utiliza-la.':'Habilitação válida e registrada.'):c.theory?`Teórica aprovada. Prática: ${money(c.fee)}.`:'Conclua a prova teórica e o percurso prático.'));
 const b=button(c.owned?'Habilitação emitida':c.theory?'Iniciar prática':'Fazer teórica',()=>request(c.theory?'practical':'theory',{category:c.name},r=>{if(!c.theory)startQuiz(r);}));b.disabled=c.owned;card.append(b);$('content').append(card);}
}
function startQuiz(data){screen();quiz=data;index=0;answers={};deadline=Date.now()+data.seconds*1000;$('title').textContent=`Prova teórica · ${data.label}`;question();tick();timer=setInterval(tick,1000);}
function tick(){const s=Math.max(0,Math.ceil((deadline-Date.now())/1000));$('info').textContent=`Tempo restante: ${Math.floor(s/60)}:${String(s%60).padStart(2,'0')} · Questão ${index+1}/${quiz.questions.length}`;if(!s){clearInterval(timer);submit();}}
function question(){const q=quiz.questions[index];$('content').replaceChildren(node('h2',q.question));q.answers.forEach((text,i)=>{const b=button(text,()=>{if(busy)return;answers[q.id]=i+1;question();});b.className='answer'+(answers[q.id]===i+1?' selected':'');$('content').append(b);});
 const nav=node('div','','actions'),previous=button('Anterior',()=>{if(index>0){index--;question();tick();}});previous.disabled=index===0;
 nav.append(previous,button(index===quiz.questions.length-1?'Finalizar prova':'Próxima',()=>{if(busy)return;if(index<quiz.questions.length-1){index++;question();tick();}else submit();}));$('content').append(nav);
}
function submit(){request('answers',{answers},r=>{screen();quiz=null;$('title').textContent=r.passed?'Teórica aprovada':'Prova encerrada';$('info').textContent=r.message;$('content').append(node('p',`Erros: ${r.errors}`),button('Voltar ao centro',()=>request('status',{},school)));});}
function documentCard(data){screen();quiz=null;$('title').textContent='Consulta de documentos';$('info').textContent='Consulta policial · Registro oficial do personagem';
 const licenseStatus=data.licenseExpiresAt?(data.licenseExpired?'VENCIDA em ':'Válida até ')+new Date(data.licenseExpiresAt*1000).toLocaleDateString('pt-BR'):'Não emitida';
 $('content').append(node('div',`${data.name}\nRegistro: ${data.userId}\nNascimento: ${data.birthdate||'Não informado'}\nNacionalidade: ${data.nationality||'Não informada'}\nTrabalho: ${data.job||'Desempregado'}\nCNH: ${licenseStatus}`,'doc'));
 for(const c of data.categories){const p=node('p',`${c.label} (${c.class}): ${c.valid?'HABILITADO':'NÃO HABILITADO'}${c.valid&&c.issuedAt?' · Emitida em '+new Date(c.issuedAt*1000).toLocaleDateString('pt-BR'):''}`,c.valid?'valid':'invalid');$('content').append(p);}
}
function driverDocument(data){screen();quiz=null;$('title').textContent='Carteira de motorista';$('info').textContent='Documento pessoal · Clique na carteira para fechar';
 const validUntil=data.licenseExpiresAt?new Date(data.licenseExpiresAt*1000).toLocaleDateString('pt-BR'):'Não informada';
 const enabled=(data.categories||[]).filter(c=>c.valid);
 const card=node('article','','license-card'+(data.licenseExpired?' expired':''));card.tabIndex=0;
 const top=node('div','','license-top');top.append(node('div','OB · DEPARTAMENTO DE TRÂNSITO','license-agency'),node('div',data.licenseExpired?'VENCIDA':'CNH DIGITAL',data.licenseExpired?'license-state expired':'license-state'));
 const body=node('div','','license-body'),photo=node('div',(data.name||'?').split(/\s+/).map(part=>part[0]).join('').slice(0,2).toUpperCase(),'license-photo'),fields=node('div','','license-fields');
 fields.append(node('small','NOME COMPLETO'),node('strong',data.name||'Não informado'),node('small','REGISTRO'),node('strong',String(data.userId||'—')),
  node('small','NASCIMENTO · NACIONALIDADE'),node('strong',`${data.birthdate||'Não informado'} · ${data.nationality||'Não informada'}`));body.append(photo,fields);
 const categories=node('div','','license-categories');categories.append(node('span','CATEGORIAS'));
 if(enabled.length)enabled.forEach(c=>categories.append(node('b',c.class||'?')));else categories.append(node('strong','Nenhuma habilitação válida'));
 const bottom=node('div','','license-bottom');bottom.append(node('span',`VALIDADE ${validUntil}`),node('span',data.job||'Desempregado'));
 card.append(top,body,categories,bottom);card.onclick=close;card.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();close();}};$('content').append(card);
}
window.addEventListener('message',({data})=>{
 if(data.action==='close'){epoch++;$('app').hidden=true;clearInterval(timer);quiz=null;return;}
 if(data.action==='hud'){$('hud').hidden=!data.visible;if(data.visible)$('hud').textContent=`PROVA PRÁTICA\nPonto ${data.index}/${data.total} · Erros ${data.errors}/${data.maxErrors}\n${data.limit?'Limite: '+data.limit+' km/h':'Siga o percurso sinalizado'}\nTempo: ${data.seconds}s`;return;}
 if(data.action==='open'){epoch++;$('app').hidden=false;data.mode==='inspect'?documentCard(data.data):data.mode==='driver'?driverDocument(data.data):school(data.data);}
});
const close=()=>post('close').catch(()=>{$('error').textContent='Falha ao fechar.';});
$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('app').hidden)close();});
