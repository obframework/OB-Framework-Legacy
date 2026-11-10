const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright');
const scriptsRoot=path.resolve(__dirname,'..','..');
const jobs=[
  {name:'ob_garbagejob',host:'garbage.test',minimumIcons:5},
  {name:'ob_leiteirojob',host:'milk.test',minimumIcons:6},
  {name:'ob_lumberjackjob',host:'lumber.test',minimumIcons:6},
];

(async()=>{
  const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    for(const job of jobs){
      const ui=path.join(scriptsRoot,job.name,'ui');
      const html=fs.readFileSync(path.join(ui,'index.html'),'utf8');
      assert.equal((html.match(/class="nav-icon"/g)||[]).length,job.minimumIcons,`${job.name}: icones laterais incompletos`);
      const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
      page.on('pageerror',error=>errors.push(error.message));
      await page.addInitScript(name=>{window.GetParentResourceName=()=>name;window.OBCurrency={format:value=>`$ ${value}`};},job.name);
      await page.route('https://cfx-nui-ob_lib/**',route=>route.fulfill({body:''}));
      await page.route(`http://${job.host}/**`,route=>{
        const name=path.basename(new URL(route.request().url()).pathname)||'index.html';
        const file=path.join(ui,name);
        route.fulfill({body:fs.readFileSync(file),contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'text/html'});
      });
      await page.goto(`http://${job.host}/index.html`);
      await page.evaluate(()=>document.querySelector('#app').classList.remove('hidden'));
      await page.locator('[data-tab="ranking"]').click();
      assert(await page.locator('.nav-icon').count()>=job.minimumIcons);
      const outputDir=path.join(scriptsRoot,job.name,'tests');
      fs.mkdirSync(outputDir,{recursive:true});
      await page.screenshot({path:path.join(outputDir,'panel-preview.png')});
      assert.deepEqual(errors,[],`${job.name}: erro JavaScript`);
      await page.close();
      console.log(`${job.name} OK: icones, navegacao e renderizacao.`);
    }
  }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
