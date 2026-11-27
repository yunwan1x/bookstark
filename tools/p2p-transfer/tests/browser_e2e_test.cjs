'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
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

async function waitForTextMatch(locator, regex, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let last = '';
  while (Date.now() < deadline) {
    try {
      last = ((await locator.textContent()) || '').trim();
      if (regex.test(last)) return last;
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error('Timed out waiting for ' + regex + '; last text: ' + JSON.stringify(last));
}

async function main() {
  const origin = process.env.BOOKSTARK_ORIGIN;
  const password = process.env.BOOKSTARK_PASSWORD;
  const zipPath = process.env.P2P_ZIP;
  const outDir = process.env.ARTIFACT_DIR || '/tmp/p2p-transfer-e2e';
  assert.ok(origin && password && zipPath, 'BOOKSTARK_ORIGIN, BOOKSTARK_PASSWORD, P2P_ZIP required');
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctxA = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    locale: 'zh-CN',
    acceptDownloads: true,
  });

  const pageA = await ctxA.newPage();
  const pageB = await ctxA.newPage();
  const pageErrors = [];
  pageA.on('pageerror', (err) => pageErrors.push('A: ' + String(err)));
  pageB.on('pageerror', (err) => pageErrors.push('B: ' + String(err)));
  pageA.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') {
      console.log('[console A ' + msg.type() + ']', msg.text());
    }
  });
  pageB.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') {
      console.log('[console B ' + msg.type() + ']', msg.text());
    }
  });

  try {
    // 1. Login as admin in ctxA
    const loginRes = await ctxA.request.post(origin + '/api/login', {
      data: { account: 'admin', password },
    });
    assert.equal(loginRes.status(), 200, 'admin login failed');

    const csrfRes = await ctxA.request.get(origin + '/api/csrf-token');
    const { csrf_token: csrf } = await csrfRes.json();
    const headers = { 'X-CSRF-Token': csrf, Origin: origin };

    // 2. Configure local market
    await ctxA.request.put(origin + '/api/tool-market/settings', {
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
    await ctxA.request.put(origin + '/api/tool-market/client', {
      headers,
      data: { url: origin + '/market', check_updates: true, auto_update: false },
    });

    // 3. Upload ZIP package
    const uploadRes = await ctxA.request.post(origin + '/api/tool-packages', {
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

    // 4. Publish package
    const manifest = JSON.parse(
      fs.readFileSync(path.join(__dirname, '../web/tool.json'), 'utf8')
    );
    const pubRes = await ctxA.request.post(origin + '/api/tool-publications/' + upload.id, {
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

    // 5. Install tool
    const installRes = await ctxA.request.put(origin + '/api/tool-installs/' + upload.id, {
      headers,
      data: { server: origin + '/market', revision: pub.revision, hash: pub.metadata.hash },
    });
    assert.equal(installRes.status(), 200, 'install failed: ' + (await installRes.text()));

    // 6. Open Peer A (Host) — logged-in user
    const toolUrl = origin + '/tools/run/' + upload.id;
    await pageA.goto(toolUrl, { waitUntil: 'networkidle' });
    await pageA.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frameA = pageA.frameLocator('#marketFrameHost iframe');

    // Wait for signaling ready and 6-digit room code
    const formattedCode = await waitForTextMatch(frameA.locator('#roomCodeValue'), /^\d{3}\s\d{3}$/, 15000);
    await waitForTextMatch(frameA.locator('#signalingPillText'), /信令已就绪/, 10000);
    assert.equal(await frameA.locator('#miniQrWrap svg').count(), 1, 'mini QR SVG should render');

    // Open QR Modal & screenshot
    await frameA.locator('#openQrModalBtn').click();
    await frameA.locator('#qrModal').waitFor({ state: 'visible' });
    assert.equal(await frameA.locator('#qrModalSvgWrap svg').count(), 1, 'modal QR SVG should render');
    await pageA.screenshot({ path: path.join(outDir, '01-host-qr-modal.png') });
    await frameA.locator('[data-close-modal="qrModal"]').first().click();
    await frameA.locator('#qrModal').waitFor({ state: 'hidden' });

    // Rename Host device via Settings modal
    await frameA.locator('#openSettingsBtn').click();
    await frameA.locator('#settingsModal').waitFor({ state: 'visible' });
    await frameA.locator('#settingDeviceName').fill('MacBook Pro · Host');
    await frameA.locator('#saveSettingsBtn').click();
    await frameA.locator('#settingsModal').waitFor({ state: 'hidden' });

    // 7. Open Peer B (Guest — unauthenticated context proves access:"public" works!)
    await pageB.goto(toolUrl, { waitUntil: 'networkidle' });
    await pageB.locator('#marketFrameHost iframe').waitFor({ state: 'visible', timeout: 15000 });
    const frameB = pageB.frameLocator('#marketFrameHost iframe');
    await waitForTextMatch(frameB.locator('#roomCodeValue'), /^\d{3}\s\d{3}$/, 15000);

    // Rename Guest device
    await frameB.locator('#openSettingsBtn').click();
    await frameB.locator('#settingDeviceName').fill('iPhone 16 Pro · Guest');
    await frameB.locator('#saveSettingsBtn').click();

    // Switch Guest to Join Room & verify invalid/missing room error first
    await frameB.locator('#tabJoinBtn').click();
    await frameB.locator('#joinCodeInput').fill('999 999');
    await frameB.locator('#joinSubmitBtn').click();
    await frameB.locator('#joinError').waitFor({ state: 'visible', timeout: 10000 });

    // Now join Host's real room code
    await frameB.locator('#joinCodeInput').fill(formattedCode);
    await frameB.locator('#joinSubmitBtn').click();

    // 8. Verify real WebRTC P2P DataChannel establishes on BOTH peers
    await waitForTextMatch(frameA.locator('#signalingPillText'), /已直连 1 台设备/, 20000);
    await waitForTextMatch(frameB.locator('#signalingPillText'), /已直连 1 台设备/, 20000);
    await waitForTextMatch(frameA.locator('#peersList'), /iPhone 16 Pro · Guest/, 10000);
    await waitForTextMatch(frameB.locator('#peersList'), /MacBook Pro · Host/, 10000);

    // Wait briefly for ICE getStats() to populate candidate type (host / LAN direct) & RTT
    await pageA.waitForTimeout(600);
    await pageA.screenshot({ path: path.join(outDir, '02-desktop-paired.png') });

    // 9. Send a real 384 KB binary file from Peer A -> Peer B over WebRTC DataChannel
    const sampleBuf = crypto.randomBytes(384 * 1024 + 137);
    const expectedSha = crypto.createHash('sha256').update(sampleBuf).digest('hex');
    const sampleFilePath = path.join(outDir, 'release-preview-384k.bin');
    fs.writeFileSync(sampleFilePath, sampleBuf);

    await frameA.locator('#fileInput').setInputFiles(sampleFilePath);

    // Wait for BOTH sender and receiver to finish + pass SHA-256 verification
    await frameA.locator('.transfer-item[data-status="done"]').first().waitFor({ state: 'visible', timeout: 25000 });
    await frameB.locator('.transfer-item[data-status="done"]').first().waitFor({ state: 'visible', timeout: 25000 });
    await waitForTextMatch(frameA.locator('.transfer-item').first(), /SHA-256 校验通过/, 5000);
    await waitForTextMatch(frameB.locator('.transfer-item').first(), /SHA-256 校验通过/, 5000);

    // Click Save File on Peer B and verify downloaded bytes match byte-for-byte
    const [download] = await Promise.all([
      pageB.waitForEvent('download', { timeout: 10000 }),
      frameB.locator('[data-download-tr]').first().click(),
    ]);
    assert.equal(download.suggestedFilename(), 'release-preview-384k.bin');
    const savedPath = await download.path();
    assert.ok(savedPath, 'download path missing');
    const receivedBuf = fs.readFileSync(savedPath);
    assert.equal(Buffer.compare(receivedBuf, sampleBuf), 0, 'downloaded file bytes must match original byte-for-byte');
    const actualSha = crypto.createHash('sha256').update(receivedBuf).digest('hex');
    assert.equal(actualSha, expectedSha, 'SHA-256 mismatch');

    // Clean up temp binary fixture so artifact folder stays tidy
    fs.unlinkSync(sampleFilePath);

    // 10. Real-time Shared Clipboard from Peer B -> Peer A
    const clipMsg = 'https://cloud.vs2010wy.top/market 部署完成 · 极速快传 P2P 验证通过';
    await frameB.locator('#clipboardInput').fill(clipMsg);
    await frameB.locator('#sendClipboardBtn').click();

    await waitForTextMatch(frameA.locator('#clipboardList'), /极速快传 P2P 验证通过/, 10000);
    const linkCount = await frameA.locator('#clipboardList a[href="https://cloud.vs2010wy.top/market"]').count();
    assert.equal(linkCount, 1, 'URL in shared clipboard should be safely linkified');

    await pageA.screenshot({ path: path.join(outDir, '03-desktop-transfer-and-clipboard.png') });

    // 11. Mobile responsive verification on Peer B (390x844)
    await pageB.setViewportSize({ width: 390, height: 844 });
    await pageB.waitForTimeout(300);
    await pageB.screenshot({ path: path.join(outDir, '04-mobile-receiver.png') });

    assert.equal(pageErrors.length, 0, 'unexpected page errors: ' + pageErrors.join('; '));
    console.log(
      'P2P_TRANSFER_E2E_PASSED',
      JSON.stringify({
        toolId: upload.id,
        roomCode: formattedCode,
        fileBytes: sampleBuf.length,
        sha256: actualSha.slice(0, 16) + '...',
      })
    );
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
