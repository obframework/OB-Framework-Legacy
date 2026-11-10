const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const parser=require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/46842520f68e72b9/node_modules/luaparse');
const {chromium}=require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright');

for(const file of ['config.lua','fxmanifest.lua','client/main.lua','server/main.lua']){
  parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
}
const server=fs.readFileSync(path.join(root,'server/main.lua'),'utf8');
const html=fs.readFileSync(path.join(root,'ui/index.html'),'utf8');
assert.match(server,/local function leaderboard\(source, ownRow\)/);
assert.match(server,/ORDER BY p\.repairs DESC/);
assert.match(server,/leaderboard = leaderboard\(source, row\)/);
assert(html.includes('data-tab="ranking"'));
assert(html.includes('id="leaderboard"'));

(async()=>{
  const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.addInitScript(()=>{window.GetParentResourceName=()=> 'ob_electricianjob';window.OBCurrency={format:value=>`$ ${value}`};});
    await page.route('https://ob_electricianjob/**',route=>route.fulfill({json:{ok:true}}));
    await page.route('https://cfx-nui-ob_lib/**',route=>route.fulfill({body:''}));
    await page.route('http://electrician-test/**',route=>{
      const name=path.basename(new URL(route.request().url()).pathname)||'index.html';
      const file=path.join(root,'ui',name);
      route.fulfill({body:fs.readFileSync(file),contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'text/html'});
    });
    await page.goto('http://electrician-test/index.html');
    const payload={progress:{level:3,xpInLevel:120,xpRequired:500,completed:11,totalEarned:8400,paymentBonus:5,maxLevel:10},work:{active:false},group:{isLeader:true,maxMembers:2,members:[{id:1,name:'Eletricista',leader:true}]},nearby:[],leaderboard:{xp:{list:[{rank:1,name:'Rey Ramon',xp:650,repairs:20}],myRank:1,myValue:650},repairs:{list:[{rank:1,name:'Rey Ramon',xp:650,repairs:20}],myRank:1,myValue:20}},tutorial:{}};
    await page.evaluate(payload=>window.postMessage({action:'open',payload},'*'),payload);
    await page.locator('[data-tab="ranking"]').click();
    assert.equal(await page.locator('#leaderboard .ranking-row').count(),1);
    assert.equal(await page.locator('#myRank').innerText(),'#1');
    await page.locator('#rankRepairs').click();
    assert.match(await page.locator('#myRankValue').innerText(),/20 reparos/);
    await page.screenshot({path:path.join(__dirname,'panel-preview.png')});
    assert.deepEqual(errors,[]);
    console.log('Eletricista OK: Lua, ranking geral e NUI padronizada.');
  }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
