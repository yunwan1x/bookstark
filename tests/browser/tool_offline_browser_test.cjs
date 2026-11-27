'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function loadPlaywright() {
  for (const candidate of [
    'playwright',
    '/root/.agents/skills/gstack/node_modules/playwright',
  ]) {
    try {
      return require(candidate);
    } catch (_) {}
  }
  throw new Error('Playwright not found');
}

const { chromium } = loadPlaywright();

async function waitForMatch(locator, regex, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let last = '';
  while (Date.now() < deadline) {
    try {
      last = ((await locator.textContent()) || '').trim();
      if (regex.test(last)) return last;
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error('Timed out waiting for ' + regex + '; last=' + JSON.stringify(last));
}

async function main() {
  const origin = process.env.BOOKSTARK_ORIGIN;
  const password = process.env.BOOKSTARK_PASSWORD;
  const zipPath = process.env.VAULT_ZIP;
  const outDir = process.env.ARTIFACT_DIR || '/tmp/pwa-offline-tools-e2e';
  assert.ok(origin && password && zipPath, 'BOOKSTARK_ORIGIN, BOOKSTARK_PASSWORD, VAULT_ZIP required');
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    locale: 'zh-CN',
    serviceWorkers: 'allow',
  });
  const page = await context.newPage();
  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(String(err)));
  page.on('console', (msg) => {
    if (msg.type() === 'error') console.log('[console error]', msg.text());
  });

  try {
    // 1. Login & install vault-2fa tool
    const loginRes = await context.request.post(origin + '/api/login', {
      data: { account: 'admin', password },
    });
    assert.equal(loginRes.status(), 200, 'admin login failed');

    const csrfRes = await context.request.get(origin + '/api/csrf-token');
    const { csrf_token: csrf } = await csrfRes.json();
    const headers = { 'X-CSRF-Token': csrf, Origin: origin };

    await context.request.put(origin + '/api/tool-market/settings', {
      headers,
      data: {
        enabled: true,
        name: 'Offline Test Market',
        public_url: origin,
        login_required: false,
        members_publish: true,
        review_required: false,
      },
    });
    await context.request.put(origin + '/api/tool-market/client', {
      headers,
      data: { url: origin + '/market', check_updates: false, auto_update: false },
    });

    const uploadRes = await context.request.post(origin + '/api/tool-packages', {
      headers,
      multipart: {
        file: {
          name: path.basename(zipPath),
          mimeType: 'application/zip',
          buffer: fs.readFileSync(zipPath),
        },
      },
    });
    assert.equal(uploadRes.status(), 200, 'upload failed');
    const upload = await uploadRes.json();

    const manifest = JSON.parse(
      fs.readFileSync(path.join(__dirname, '../../tools/vault-2fa/web/tool.json'), 'utf8')
    );
    const pubRes = await context.request.post(origin + '/api/tool-publications/' + upload.id, {
      headers,
      data: {
        title: manifest.title,
        description: manifest.description,
        version: manifest.version,
        category: manifest.category,
        icon: manifest.icon,
        icon_style: manifest.icon_style,
        icon_color: manifest.icon_color,
        access: manifest.access,
        package: upload.package.token,
        entry: upload.package.entry,
        permissions: manifest.permissions,
        notes: manifest.notes,
      },
    });
    assert.equal(pubRes.status(), 200, 'publish failed');
    const pub = await pubRes.json();

    const installRes = await context.request.put(origin + '/api/tool-installs/' + upload.id, {
      headers,
      data: { server: origin + '/market', revision: pub.revision, hash: pub.metadata.hash },
    });
    assert.equal(installRes.status(), 200, 'install failed');
    const toolId = upload.id;

    // 2. Register SW via /home, warm /market?status=installed and /tools/run/:id online
    await page.goto(origin + '/home', { waitUntil: 'networkidle' });
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);

    await page.goto(origin + '/market?status=installed', { waitUntil: 'networkidle' });
    await page.locator(`.market-card[data-tool-id="${toolId}"]`).waitFor({ state: 'visible', timeout: 15000 });

    await page.goto(origin + '/tools/run/' + toolId, { waitUntil: 'networkidle' });
    await page.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frameOnline = page.frameLocator('#marketFrameHost iframe');
    await frameOnline.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });

    // Setup master password & save 1st entry online
    await frameOnline.locator('#masterPassword').fill('OfflineMaster#2026');
    await frameOnline.locator('#confirmMasterPassword').fill('OfflineMaster#2026');
    await frameOnline.locator('#lockSubmitBtn').click();
    await frameOnline.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });

    await frameOnline.locator('#newEntryBtn').click();
    await frameOnline.locator('#fTitle').fill('GitHub · OnlineInit');
    await frameOnline.locator('#fUsername').fill('yunwan1x');
    await frameOnline.locator('#fPassword').fill('StrongOnline#2026');
    await frameOnline.locator('#toggleTotpSectionBtn').click();
    await frameOnline.locator('#fTotpSecret').fill('JBSWY3DPEHPK3PXP');
    await frameOnline.locator('#saveEntryBtn').click();
    await frameOnline.locator('#detailTotpCode').waitFor({ state: 'visible', timeout: 10000 });

    // Allow background asset warming (warmToolAssets) to populate bookstark-tools-v1
    await page.waitForTimeout(1200);
    const cachedAssetsCount = await page.evaluate(async () => {
      const c = await caches.open('bookstark-tools-v1');
      return (await c.keys()).length;
    });
    assert.ok(cachedAssetsCount >= 5, 'expected tool assets warmed in bookstark-tools-v1, got: ' + cachedAssetsCount);

    // 3. GO 100% OFFLINE!
    await context.setOffline(true);

    // 3a. Open /market?status=installed completely offline
    await page.goto(origin + '/market?status=installed', { waitUntil: 'domcontentloaded' });
    await page.locator(`.market-card[data-tool-id="${toolId}"]`).waitFor({ state: 'visible', timeout: 15000 });
    await page.screenshot({ path: path.join(outDir, '01-offline-market-installed.png') });

    // 3b. Launch /tools/run/:id completely offline!
    await page.goto(origin + '/tools/run/' + toolId, { waitUntil: 'domcontentloaded' });
    await page.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    await waitForMatch(page.locator('#toolRuntimeCapabilities'), /离线模式/, 10000);

    const frameOffline = page.frameLocator('#marketFrameHost iframe');
    await frameOffline.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });
    await frameOffline.locator('#masterPassword').fill('OfflineMaster#2026');
    await frameOffline.locator('#lockSubmitBtn').click();
    await frameOffline.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });

    // Verify cached entry + live 6-digit TOTP works 100% offline!
    assert.equal(((await frameOffline.locator('[data-count="all"]').textContent()) || '').trim(), '1');
    const offlineTotp = await waitForMatch(frameOffline.locator('#detailTotpCode'), /^\d{3}\s\d{3}$/, 10000);

    // 3c. Create a 2nd entry WHILE OFFLINE & verify pending sync banner!
    await frameOffline.locator('#newEntryBtn').click();
    await frameOffline.locator('[data-pick-cat="server"]').click();
    await frameOffline.locator('#fTitle').fill('Offline Created Server');
    await frameOffline.locator('#fHost').fill('10.0.0.8');
    await frameOffline.locator('#fPort').fill('2222');
    await frameOffline.locator('#fUsername').fill('root');
    await frameOffline.locator('#fPassword').fill('OfflineSrv#2026!');
    await frameOffline.locator('#saveEntryBtn').click();
    await frameOffline.locator('#detailCopySshBtn').waitFor({ state: 'visible', timeout: 10000 });
    await waitForMatch(page.locator('#toolRuntimeCapabilities'), /待联网同步/, 10000);
    await page.screenshot({ path: path.join(outDir, '02-offline-vault-running.png') });

    // 3d. Reload /tools/run/:id WHILE STILL OFFLINE — both entries must persist!
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frameOffline2 = page.frameLocator('#marketFrameHost iframe');
    await frameOffline2.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });
    await frameOffline2.locator('#masterPassword').fill('OfflineMaster#2026');
    await frameOffline2.locator('#lockSubmitBtn').click();
    await frameOffline2.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });
    assert.equal(((await frameOffline2.locator('[data-count="all"]').textContent()) || '').trim(), '2', 'offline-created entry must persist across offline reload');

    // 4. COME BACK ONLINE — offline queue auto-syncs to server!
    await context.setOffline(false);
    await page.evaluate(() => window.dispatchEvent(new Event('online')));
    // Wait until pendingCount drops to 0
    for (let i = 0; i < 40; i++) {
      const pending = await page.evaluate(() => window.BookStarkMarketStore.pendingCount());
      if (pending === 0) break;
      await page.waitForTimeout(200);
    }
    assert.equal(await page.evaluate(() => window.BookStarkMarketStore.pendingCount()), 0, 'offline queue must drain on reconnect');

    // Verify in a brand-new clean context (zero cache!) that server received the offline-created entry!
    const cleanCtx = await browser.newContext({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
    const cleanPage = await cleanCtx.newPage();
    await cleanCtx.request.post(origin + '/api/login', { data: { account: 'admin', password } });
    await cleanPage.goto(origin + '/tools/run/' + toolId, { waitUntil: 'networkidle' });
    const cleanFrame = cleanPage.frameLocator('#marketFrameHost iframe');
    await cleanFrame.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });
    await cleanFrame.locator('#masterPassword').fill('OfflineMaster#2026');
    await cleanFrame.locator('#lockSubmitBtn').click();
    await cleanFrame.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });
    assert.equal(((await cleanFrame.locator('[data-count="all"]').textContent()) || '').trim(), '2', 'clean online session must see offline-synced entry!');
    await cleanFrame.locator('.entry-card', { hasText: 'Offline Created Server' }).waitFor({ state: 'visible' });
    await cleanCtx.close();

    // 5. Logout cleanup check: clearing page/API cache wipes tool caches so offline shows offline.html
    await page.evaluate(async () => {
      if (navigator.serviceWorker && navigator.serviceWorker.controller) {
        navigator.serviceWorker.controller.postMessage({ type: 'CLEAR_API_CACHE' });
      }
      if (window.BookStarkPWA && window.BookStarkPWA.clearPageCache) {
        await window.BookStarkPWA.clearPageCache();
      }
      if (window.BookStarkMarketStore && window.BookStarkMarketStore.clearOfflineData) {
        await window.BookStarkMarketStore.clearOfflineData();
      }
    });
    await page.waitForTimeout(300);
    await context.setOffline(true);
    await page.goto(origin + '/tools/run/' + toolId, { waitUntil: 'domcontentloaded' });
    await page.getByRole('heading', { name: '暂时无法连接 BookStark' }).waitFor({ state: 'visible', timeout: 10000 });

    assert.equal(pageErrors.length, 0, 'unexpected page errors: ' + pageErrors.join('; '));
    console.log(
      'PWA_OFFLINE_TOOLS_E2E_PASSED',
      JSON.stringify({ toolId, cachedAssetsCount, offlineTotp, syncedEntries: 2 })
    );
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
