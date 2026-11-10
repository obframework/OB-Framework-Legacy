const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { chromium } = require('C:/Users/igo-r/AppData/Local/npm-cache/_npx/e41f203b7505f1fb/node_modules/playwright');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const config = read('config/patrol.lua');
const server = read('server/main.lua');
const client = read('client/main.lua');
const manifest = read('fxmanifest.lua');

assert(config.includes("leaveCommand = 'patrulhasair'"));
assert(config.includes('speedLimitKmh = 60.0'));
assert(config.includes('checkpoint = { min = 100, max = 250 }'));
assert(!config.includes('occurrenceSpeedLimitKmh'));
assert(!config.includes('events = {'));
assert(server.includes('CREATE TABLE IF NOT EXISTS ob_patrol_routes'));
assert(server.includes('CREATE TABLE IF NOT EXISTS ob_patrol_route_points'));
assert(server.includes('rewardPlayer(src, Patrol.payment.checkpoint'));
assert(server.includes('advanceOrLoop'));
assert(server.includes('adminDeleteRoute'));
assert(server.includes("ob_patrol:server:setLimiter"));
assert(!server.includes('scheduleNextEvent(session, true)'));
assert(client.includes("RegisterCommand(Patrol.command or 'patrulha'"));
assert(client.includes("Patrol.creator.panelCommand"));
assert(manifest.includes("'@ob_database/import.lua'"));
assert(manifest.includes("'ob_inventory'"));

(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.addInitScript(() => { window.GetParentResourceName = () => 'ob_patrol'; });
    await page.route('http://patrol.test/**', (route) => {
      const name = path.basename(new URL(route.request().url()).pathname) || 'index.html';
      const file = path.join(root, 'ui', name);
      route.fulfill({ body: fs.readFileSync(file), contentType: name.endsWith('.js') ? 'application/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html' });
    });
    await page.goto('http://patrol.test/index.html');
    await page.evaluate(() => window.postMessage({ action: 'open', payload: {
      speedLimit: 60,
      occurrenceSpeedLimit: 125,
      limiterEnabled: true,
      regions: { south: { routes: 3 }, north: { routes: 3 } },
      group: { isLeader: true, maxMembers: 4, members: [{ id: 1, name: 'Oficial Teste', leader: true }] },
      nearby: [{ id: 2, name: 'Parceiro Teste' }],
      work: { active: false }
    } }, '*'));
    assert.equal(await page.locator('#routeAdmin').isVisible(), false);
    assert.match(await page.locator('#southRoutes').textContent(), /^3 rotas/);
    assert.equal(await page.locator('#speedLimit').textContent(), '60 km/h');
    assert.equal(await page.locator('.steps > span').count(), 4);
    assert.equal(await page.locator('#groupCount').textContent(), '1/4 integrantes');
    assert.equal(await page.locator('.invite').count(), 1);
    await page.evaluate(() => window.postMessage({ action: 'update', payload: {
      adminOnly: true, isStaff: true,
      staffRoutes: [
        { id: 1, label: 'Centro e Mission Row', region: 'south', points: 8 },
        { id: 2, label: 'Sandy Shores', region: 'north', points: 6 }
      ]
    } }, '*'));
    assert.equal(await page.locator('.route-card').count(), 2);
    assert.equal(await page.locator('#routeAdmin').isVisible(), true);
    assert.equal(await page.locator('#patrolPanel').isVisible(), false);
    assert.deepEqual(errors, []);
    await page.screenshot({ path: path.join(__dirname, 'panel-preview.png'), fullPage: true });
    await page.evaluate(() => window.postMessage({ action: 'update', payload: {
      speedLimit: 60, limiterEnabled: true,
      regions: { south: { routes: 3 }, north: { routes: 3 } },
      group: { isLeader: true, maxMembers: 4, members: [{ id: 1, name: 'Oficial Teste', leader: true }] },
      nearby: [], isStaff: false,
      work: { active: true, routeLabel: 'Centro e Mission Row', checkpoint: 2, total: 8 }
    } }, '*'));
    assert.equal(await page.locator('#speedLimit').textContent(), '60 km/h');
    assert.equal(await page.locator('#stopPatrol').isVisible(), true);
    assert.equal(await page.locator('#activeProgress').textContent(), 'Checkpoint 2/8');
    console.log('ob_patrol OK: checkpoints, recompensas, ronda infinita, grupo e gerenciador de rotas validados.');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
