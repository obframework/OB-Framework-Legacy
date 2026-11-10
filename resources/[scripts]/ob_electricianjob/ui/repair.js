(() => {
  const root = document.querySelector('#repair'), board = document.querySelector('#repairBoard');
  const feedback = document.querySelector('#repairFeedback');
  let game = null, timer = null, holdFrame = null;
  const shuffle = items => {
    const result = [...items];
    for (let i = result.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [result[i], result[j]] = [result[j], result[i]]; }
    return result;
  };
  function close() {
    clearInterval(timer); cancelAnimationFrame(holdFrame); timer = holdFrame = null;
    game = null; root.classList.add('hidden'); board.replaceChildren();
  }
  function finish(success) {
    if (!game) return;
    const id = game.id;
    close();
    fetch(`https://${GetParentResourceName()}/repairResult`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id,success})}).catch(() => {});
  }
  function mistake(message) {
    if (!game) return;
    game.errors++;
    feedback.textContent = message;
    document.querySelector('#repairErrors').textContent = `Falhas: ${game.errors}/3`;
    if (game.errors >= 3) finish(false);
  }
  function screws() {
    board.innerHTML = '<div class="screw-grid">'+[1,2,3,4].map(i=>`<button class="screw" aria-label="Soltar parafuso ${i}"><span>＋</span></button>`).join('')+'</div>';
    let completed = 0;
    board.querySelectorAll('.screw').forEach(button => {
      let started = 0;
      const stop = () => { cancelAnimationFrame(holdFrame); holdFrame = null; };
      button.onpointerdown = event => {
        if (event.button !== 0 || button.disabled || !game) return;
        stop(); button.setPointerCapture(event.pointerId); started = performance.now();
        const tick = now => {
          if (!game) return;
          const fraction = Math.min(1, (now - started) / 900);
          button.firstElementChild.style.transform = `rotate(${-fraction * 540}deg)`;
          if (fraction >= 1) {
            button.disabled = true; button.classList.add('done'); completed++;
            feedback.textContent = `Parafusos removidos: ${completed}/4`;
            if (completed === 4) finish(true);
          } else holdFrame = requestAnimationFrame(tick);
        };
        holdFrame = requestAnimationFrame(tick);
      };
      button.onpointerup = button.onpointercancel = button.onlostpointercapture = stop;
    });
  }
  function wires() {
    const colors = ['#f07878','#65acff','#f4ce59','#68d6a1','#d3a2ff'];
    const ids = [0,1,2,3,4]; let selected = null, dragging = false; const connected = new Set();
    const terminal = (id, side) => `<button class="terminal" data-wire="${id}" data-side="${side}" style="--wire:${colors[id]}">${side === 'left' ? 'CABO' : 'BORNE'} ${id+1}</button>`;
    board.innerHTML = `<svg class="wire-svg"></svg><div class="wire-columns"><div class="wire-column">${shuffle(ids).map(i=>terminal(i,'left')).join('')}</div><div class="wire-column">${shuffle(ids).map(i=>terminal(i,'right')).join('')}</div></div>`;
    function pick(button) {
      if (!game || !button || button.disabled) return;
      const id = Number(button.dataset.wire);
      if (button.dataset.side === 'left') {
        board.querySelectorAll('.selected').forEach(b=>b.classList.remove('selected'));
        selected = id; button.classList.add('selected'); return;
      }
      if (selected === null) { feedback.textContent = 'Escolha primeiro um cabo da esquerda.'; return; }
      if (id !== selected) { mistake('Borne incorreto. Confira o número e a cor do cabo.'); return; }
      const left = board.querySelector(`[data-side="left"][data-wire="${id}"]`);
      const box = board.getBoundingClientRect(), a = left.getBoundingClientRect(), b = button.getBoundingClientRect();
      const line = document.createElementNS('http://www.w3.org/2000/svg','path');
      const x1 = a.right-box.left, y1 = a.top+a.height/2-box.top, x2 = b.left-box.left, y2 = b.top+b.height/2-box.top;
      line.setAttribute('d',`M ${x1} ${y1} C ${x1+90} ${y1},${x2-90} ${y2},${x2} ${y2}`);
      line.setAttribute('stroke',colors[id]); line.setAttribute('stroke-width','5'); line.setAttribute('fill','none');
      board.querySelector('svg').append(line);
      [left,button].forEach(e=>{e.disabled=true;e.classList.add('connected');e.classList.remove('selected');});
      selected=null; connected.add(id); feedback.textContent=`Cabos conectados: ${connected.size}/5`;
      if (connected.size===5) finish(true);
    }
    board.querySelectorAll('.terminal').forEach(button => {
      button.onclick = () => pick(button);
      button.onpointerdown = event => { dragging = button.dataset.side==='left' && event.button===0; if(dragging) pick(button); };
    });
    board.onpointerup = event => {
      const target = document.elementFromPoint(event.clientX,event.clientY)?.closest('[data-side="right"]');
      if (dragging && selected !== null && target && !target.disabled) { event.preventDefault(); pick(target); }
      dragging = false;
    };
  }
  function voltage() {
    const targets = [0,1,2].map(()=>80+Math.floor(Math.random()*13)*10);
    board.innerHTML = targets.map((target,i)=>`<div class="voltage-row"><label for="phase${i}">Fase ${i+1} · alvo ${target} V <output id="reading${i}">0 V</output></label><input id="phase${i}" type="range" min="0" max="240" step="5" value="0" aria-label="Tensão fase ${i+1}"></div>`).join('')+'<button class="repair-test">Testar circuito</button>';
    board.querySelectorAll('input').forEach((input,i)=>input.oninput=()=>{document.querySelector(`#reading${i}`).textContent=`${input.value} V`;});
    board.querySelector('.repair-test').onclick=()=>{
      if (targets.every((target,i)=>Math.abs(Number(document.querySelector(`#phase${i}`).value)-target)<=5)) finish(true);
      else mistake('Tensão fora da faixa. Ajuste cada fase até o alvo (tolerância de 5 V).');
    };
  }
  const titles = ['Abrir e isolar o painel','Reconectar os cabos','Regular e testar a tensão'];
  const hints = ['Mantenha o botão pressionado em cada parafuso para soltar a tampa e isolar o circuito.','Arraste ou clique em um cabo e depois no borne de mesmo número e cor. Três falhas encerram a tentativa.','Ajuste as três fases conforme os alvos fixos e teste o circuito. Tolerância de 5 V por fase.'];
  addEventListener('message', event => {
    if(event.data?.action==='repairClose') return close();
    if(event.data?.action!=='repairOpen') return;
    close();
    const p=event.data.payload;
    if(!p || ![1,2,3].includes(p.stage)) return;
    game={id:p.id,errors:0,deadline:performance.now()+60000};
    board.onpointerup=null; feedback.textContent='';
    document.querySelector('#repairTitle').textContent=`0${p.stage} / ${titles[p.stage-1]}`;
    document.querySelector('#repairHint').textContent=hints[p.stage-1];
    document.querySelector('#repairErrors').textContent='Falhas: 0/3';
    root.classList.remove('hidden');
    [screws,wires,voltage][p.stage-1]();
    const tick=()=>{if(!game)return;const seconds=Math.max(0,Math.ceil((game.deadline-performance.now())/1000));document.querySelector('#repairTime').textContent=`${seconds}s restantes`;if(seconds===0)finish(false);};
    tick(); timer=setInterval(tick,200);
  });
  document.querySelector('#repairCancel').onclick=()=>finish(false);
  addEventListener('keydown',event=>{if(event.key==='Escape' && game){event.preventDefault();finish(false);}});
})();
