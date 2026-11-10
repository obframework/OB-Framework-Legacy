const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { chromium } = require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

assert(read('config/lumberjack.lua').includes('maxMembers = 2'), 'limite da dupla ausente');
assert(read('server/main.lua').includes("exports.ob_vehiclekeys:GiveSpareKey"), 'chave do parceiro ausente');
assert(read('server/main.lua').includes("client:jobSync"), 'sincronizacao da dupla ausente');
assert(read('client/main.lua').includes("GetModelDimensions"), 'alinhamento com o prop real ausente');

(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.addInitScript(() => {
      window.GetParentResourceName = () => 'ob_lumberjackjob';
      window.OBCurrency = { format: (value) => `$ ${value}` };
    });
    await page.route('https://cfx-nui-ob_lib/**', (route) => route.fulfill({ body: '' }));
    await page.route('http://lumber.test/**', (route) => {
      const name = path.basename(new URL(route.request().url()).pathname) || 'index.html';
      const file = path.join(root, 'ui', name);
      route.fulfill({ body: fs.readFileSync(file), contentType: name.endsWith('.js') ? 'application/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html' });
    });
    await page.goto('http://lumber.test/index.html');
    await page.evaluate(() => window.postMessage({ action: 'open', payload: {
      progress: { level: 2, xpInLevel: 120, xpRequired: 600, completed: 3, totalEarned: 4200, paymentBonus: 25, paymentBonusStep: 25 },
      work: { active: false, loaded: 0, maxWood: 30 },
      group: { isLeader: true, maxMembers: 2, members: [{ id: 1, name: 'Lider Teste', leader: true }] },
      nearby: [{ id: 2, name: 'Parceiro Teste' }],
      leaderboard: { list: [], myRank: 1, myValue: 720 },
      tutorial: {}
    } }, '*'));
    await page.locator('[data-tab="group"]').click();
    assert.equal(await page.locator('#groupCount').textContent(), '1/2');
    assert.equal(await page.locator('.invite').count(), 1);
    assert((await page.locator('#groupMembers').textContent()).includes('Lider Teste'));
    assert.deepEqual(errors, [], `erros JavaScript: ${errors.join(', ')}`);
    await page.screenshot({ path: path.join(__dirname, 'group-preview.png') });
    console.log('ob_lumberjackjob OK: dupla, convite, icones e painel renderizados.');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
