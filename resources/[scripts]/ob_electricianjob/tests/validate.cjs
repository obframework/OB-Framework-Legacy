// Validacao local: nao conecta ao FXServer nem ao banco.
const fs = require('fs'), path = require('path'), assert = require('assert');
const root = path.resolve(__dirname, '..');
const parser = require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/46842520f68e72b9/node_modules/luaparse');
const {chromium} = require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright');
for (const file of ['config.lua','fxmanifest.lua','client/main.lua','server/main.lua']) {
  parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
  console.log('Sintaxe Lua OK:',file);
}
const clientLua=fs.readFileSync(path.join(root,'client/main.lua'),'utf8');
const manifestLua=fs.readFileSync(path.join(root,'fxmanifest.lua'),'utf8');
assert.match(clientLua,/MarkerTypeUpsideDownCone\s*=\s*0/);
assert.match(clientLua,/\[E\] Pegar %s/);
assert.match(clientLua,/truckSidePoints\(vehicle\)/);
assert.match(clientLua,/exports\.ob_target:RegisterEntity\('orbis_electrician_npc'/);
assert(manifestLua.includes("'ob_target'"), 'O manifesto precisa exigir ob_target para o NPC');
assert(!clientLua.includes('pickupToolbox') && !clientLua.includes('placeToolbox') && !clientLua.includes('collectToolbox'));
assert(!clientLua.includes('prop_tool_box_04'), 'A caixa fisica ainda existe no cliente');
console.log('Interacoes OK: NPC com target, cone tipo 0 + E nas duas laterais e sem caixa fisica.');
(async()=>{
  const browser = await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:1366,height:768}}), errors=[], results=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.addInitScript(()=>{window.GetParentResourceName=()=> 'ob_electricianjob';});
    await page.route('https://ob_electricianjob/**',route=>{results.push(JSON.parse(route.request().postData()||'{}'));return route.fulfill({json:{ok:true}});});
    await page.route('https://cfx-nui-ob_lib/**',route=>route.fulfill({body:''}));
    await page.route('http://electrician-test/**',route=>{
      const name=path.basename(new URL(route.request().url()).pathname);
      const file=path.join(root,'ui',name);
      return route.fulfill({body:fs.readFileSync(file),contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'text/html'});
    });
    await page.goto('http://electrician-test/index.html');
    const open=stage=>page.evaluate(stage=>window.postMessage({action:'repairOpen',payload:{id:stage,stage}},'*'),stage);
    const assertResult=async(success)=>{await page.waitForFunction(()=>document.querySelector('#repair').classList.contains('hidden'));await page.waitForTimeout(80);assert.equal(results.at(-1)?.success,success);};
    await open(1);
    for(let i=0;i<4;i++){
      const b=await page.locator('.screw').nth(i).boundingBox();
      await page.mouse.move(b.x+b.width/2,b.y+b.height/2);await page.mouse.down();await page.waitForTimeout(1000);await page.mouse.up();
    }
    await assertResult(true);
    await open(2);
    // Arrastar tambem deve conectar uma vez, sem contar um clique extra.
    const left=await page.locator('[data-side="left"][data-wire="0"]').boundingBox();
    const right=await page.locator('[data-side="right"][data-wire="0"]').boundingBox();
    await page.mouse.move(left.x+20,left.y+20);await page.mouse.down();
    await page.mouse.move(right.x+20,right.y+20,{steps:8});await page.mouse.up();
    assert(await page.locator('[data-side="right"][data-wire="0"]').isDisabled());
    await page.keyboard.press('Escape');await assertResult(false);
    await open(2);
    await page.locator('[data-side="left"][data-wire="0"]').click();
    await page.locator('[data-side="right"][data-wire="1"]').click();
    assert.match(await page.locator('#repairErrors').innerText(),/1\/3/);
    for(let i=0;i<5;i++){
      await page.locator(`[data-side="left"][data-wire="${i}"]`).click();
      await page.locator(`[data-side="right"][data-wire="${i}"]`).click();
    }
    await assertResult(true);
    await open(2);
    await page.locator('[data-side="left"][data-wire="0"]').click();
    for(let i=0;i<3;i++) await page.locator('[data-side="right"][data-wire="1"]').click();
    await assertResult(false);
    await open(3);
    await page.locator('.repair-test').click();
    assert.match(await page.locator('#repairErrors').innerText(),/1\/3/);
    await page.evaluate(()=>document.querySelectorAll('.voltage-row').forEach(row=>{const target=Number(row.querySelector('label').textContent.match(/alvo (\d+)/)[1]);const input=row.querySelector('input');input.value=target;input.dispatchEvent(new Event('input'));}));
    await page.screenshot({path:path.join(__dirname,'repair-preview.png')});
    await page.locator('.repair-test').click();await assertResult(true);
    await open(1);await page.keyboard.press('Escape');await assertResult(false);
    await page.clock.install();await open(2);await page.clock.fastForward(61000);await assertResult(false);
    await page.setViewportSize({width:1280,height:720});await open(3);
    const panel=await page.locator('.repair-panel').boundingBox();assert(panel.y>=0 && panel.y+panel.height<=720);
    await page.keyboard.press('Escape');await assertResult(false);
    await page.evaluate(()=>window.postMessage({action:'jobHud',payload:{title:'Poste de Mirror Park',stage:2,total:3,step:'Reconectar os cabos',instruction:'Pegue o alicate em uma das laterais do caminhão.',completed:2,batch:5}},'*'));
    await page.locator('#jobHud').waitFor({state:'visible'});
    assert.match(await page.locator('#hudStep').innerText(),/2\/3/);
    assert.deepEqual(errors,[]);
    console.log('NUI OK: parafusos, cabos certos/errados/arrastar, tensao certa/errada, ESC, timeout, 720p e HUD.');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
