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

async function main() {
  const origin = process.env.BOOKSTARK_ORIGIN;
  const password = process.env.BOOKSTARK_PASSWORD;
  const zipPath = process.env.VAULT_ZIP;
  const outDir = process.env.ARTIFACT_DIR || '/tmp/vault-2fa-e2e';
  assert.ok(origin && password && zipPath, 'BOOKSTARK_ORIGIN, BOOKSTARK_PASSWORD, VAULT_ZIP required');
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  const page = await context.newPage();
  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(String(err)));

  try {
    // 1. Login as admin
    const loginRes = await context.request.post(origin + '/api/login', {
      data: { account: 'admin', password },
    });
    assert.equal(loginRes.status(), 200, 'admin login failed');

    const csrfRes = await context.request.get(origin + '/api/csrf-token');
    const { csrf_token: csrf } = await csrfRes.json();
    const headers = { 'X-CSRF-Token': csrf, Origin: origin };

    // 2. Point workspace market source to self & enable market
    await context.request.put(origin + '/api/tool-market/settings', {
      headers,
      data: {
        enabled: true,
        name: 'Test Market',
        public_url: origin,
        login_required: false,
        members_publish: true,
        review_required: false,
      },
    });
    await context.request.put(origin + '/api/tool-market/client', {
      headers,
      data: { url: origin + '/market', check_updates: true, auto_update: false },
    });

    // 3. Upload ZIP package
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
    assert.equal(uploadRes.status(), 200, 'upload failed: ' + (await uploadRes.text()));
    const upload = await uploadRes.json();
    assert.ok(upload.id > 0 && upload.package && upload.package.token, 'invalid upload response');

    // 4. Publish package
    const manifest = JSON.parse(
      fs.readFileSync(path.join(__dirname, '../web/tool.json'), 'utf8')
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
    assert.equal(pubRes.status(), 200, 'publish failed: ' + (await pubRes.text()));
    const pub = await pubRes.json();

    // 5. Install tool into admin workspace
    const installRes = await context.request.put(origin + '/api/tool-installs/' + upload.id, {
      headers,
      data: { server: origin + '/market', revision: pub.revision, hash: pub.metadata.hash },
    });
    assert.equal(installRes.status(), 200, 'install failed: ' + (await installRes.text()));

    // 6. Open standalone tool runtime page & wait for iframe ready
    await page.goto(origin + '/tools/run/' + upload.id, { waitUntil: 'networkidle' });
    await page.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frame = page.frameLocator('#marketFrameHost iframe');

    // Verify first-time master password setup screen
    await frame.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });
    await frame.locator('#confirmPasswordField').waitFor({ state: 'visible' });
    await page.screenshot({ path: path.join(outDir, '01-setup-master-password.png') });

    // Setup master password
    await frame.locator('#masterPassword').fill('MasterVault#2026');
    await frame.locator('#confirmMasterPassword').fill('MasterVault#2026');
    await frame.locator('#lockSubmitBtn').click();
    await frame.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });

    // Verify workspace encrypted sync mode is active (BookStark.secrets!)
    const syncText = await frame.locator('#syncStatusText').textContent();
    assert.ok(syncText.includes('工作区加密同步'), 'expected workspace sync mode, got: ' + syncText);

    // Create a new entry with strong generated password + TOTP
    await frame.locator('#newEntryBtn').click();
    await frame.locator('#fTitle').fill('GitHub · yunwan1x');
    await frame.locator('#fIssuer').fill('GitHub');
    await frame.locator('#fUsername').fill('yunwan1x');
    await frame.locator('#toggleGenBtn').click();
    await frame.locator('#runGenBtn').click();
    const generatedPwd = await frame.locator('#fPassword').inputValue();
    assert.ok(generatedPwd.length >= 16, 'generated password too short');
    await frame.locator('#fUrl').fill('https://github.com');
    await frame.locator('#fTotpSecret').fill('JBSWY3DPEHPK3PXP');
    await frame.locator('#fNotes').fill('Recovery codes stored safely');
    await frame.locator('#fFavorite').check();
    await frame.locator('#saveEntryBtn').click();

    // Verify detail view renders live 6-digit TOTP (use frameLocator since iframe is opaque-origin sandboxed)
    await frame.locator('#detailTotpCode').waitFor({ state: 'visible' });
    let liveCode = '';
    for (let i = 0; i < 30; i++) {
      liveCode = ((await frame.locator('#detailTotpCode').textContent()) || '').trim();
      if (/^\d{3}\s\d{3}$/.test(liveCode)) break;
      await page.waitForTimeout(200);
    }
    assert.match(liveCode, /^\d{3}\s\d{3}$/, 'expected live 6-digit TOTP code, got: ' + liveCode);

    // Import CSV + Google Migration via Import Modal
    await frame.locator('#openImportBtn').click();
    await frame.locator('#importModal').waitFor({ state: 'visible' });
    await frame.locator('[data-import-tab="csv"]').click();
    await frame.locator('#csvTextInput').fill(
      'name,url,username,password,totp,notes\n' +
        'Cloudflare DNS,https://dash.cloudflare.com,admin@vs2010wy.top,cf-pass-123,otpauth://totp/Cloudflare:admin@vs2010wy.top?secret=GEZDGNBVGY3TQOJQ&issuer=Cloudflare,DNS token'
    );
    await frame.locator('#parseCsvTextBtn').click();
    await frame.locator('#importPreviewBox').waitFor({ state: 'visible' });
    await frame.locator('#confirmImportBtn').click();
    await frame.locator('#importModal').waitFor({ state: 'hidden' });

    // Confirm 2 entries now exist
    const countAll = await frame.locator('[data-count="all"]').textContent();
    assert.equal(countAll.trim(), '2', 'expected 2 entries after import');

    // Select GitHub entry and capture Desktop unlocked screenshot
    await frame.locator('.entry-card', { hasText: 'GitHub · yunwan1x' }).click();
    await frame.locator('#detailTotpCode').waitFor({ state: 'visible' });
    await page.screenshot({ path: path.join(outDir, '02-desktop-unlocked-2fa.png') });

    // Open QR Export modal and verify SVG QR code rendered
    await frame.locator('#detailShowQrBtn').click();
    await frame.locator('#qrModal').waitFor({ state: 'visible' });
    const svgCount = await frame.locator('#qrSvgWrap svg').count();
    assert.equal(svgCount, 1, 'QR SVG must render');
    await page.screenshot({ path: path.join(outDir, '03-qr-export-modal.png') });
    await frame.locator('[data-close-modal="qrModal"]').first().click();

    // Save workspace encrypted snapshot via BookStark.files
    await frame.locator('#openSettingsBtn').click();
    await frame.locator('#settingsModal').waitFor({ state: 'visible' });
    await frame.locator('#saveWorkspaceSnapshotBtn').click();
    await frame.locator('.snapshot-row').first().waitFor({ state: 'visible', timeout: 10000 });
    await frame.locator('[data-close-modal="settingsModal"]').first().click();

    // Test manual Lock & verify plaintext DOM is cleared
    await frame.locator('#lockNowBtn').click();
    await frame.locator('#lockScreen').waitFor({ state: 'visible' });
    assert.equal(await frame.locator('.entry-card').count(), 0, 'entries DOM must be cleared on lock');

    // Test wrong password rejection
    await frame.locator('#masterPassword').fill('WrongMaster#999');
    await frame.locator('#lockSubmitBtn').click();
    await frame.locator('#lockError').waitFor({ state: 'visible', timeout: 10000 });
    await page.screenshot({ path: path.join(outDir, '04-lock-wrong-password.png') });

    // Reload page completely & unlock with real master password to prove persistence via BookStark.secrets
    await page.reload({ waitUntil: 'networkidle' });
    await page.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frame2 = page.frameLocator('#marketFrameHost iframe');
    await frame2.locator('#lockScreen').waitFor({ state: 'visible', timeout: 15000 });
    assert.equal(await frame2.locator('#confirmPasswordField').isVisible(), false, 'returning user must see unlock screen, not setup');
    await frame2.locator('#masterPassword').fill('MasterVault#2026');
    await frame2.locator('#lockSubmitBtn').click();
    await frame2.locator('#workspace').waitFor({ state: 'visible', timeout: 15000 });
    assert.equal((await frame2.locator('[data-count="all"]').textContent()).trim(), '2', 'both entries persisted across reload');

    // Mobile responsive check (390x844)
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(outDir, '05-mobile-detail.png') });

    assert.equal(pageErrors.length, 0, 'unexpected page errors: ' + pageErrors.join('; '));
    console.log('VAULT_2FA_E2E_PASSED', JSON.stringify({ toolId: upload.id, entries: 2 }));
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
