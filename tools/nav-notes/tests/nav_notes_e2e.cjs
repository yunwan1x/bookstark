#!/usr/bin/env node
'use strict';

const assert = require('assert');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const PKG_DIR = path.resolve(__dirname, '../../../../artifacts/nav-notes/package');
const SHOT_DIR = path.resolve(__dirname, '../../../../artifacts/nav-notes');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

function startStaticServer(root) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const clean = decodeURIComponent((req.url || '/').split('?')[0]);
      const rel = clean === '/' ? 'index.html' : clean.replace(/^\/+/, '');
      const full = path.join(root, rel);
      if (!full.startsWith(root) || !fs.existsSync(full) || fs.statSync(full).isDirectory()) {
        res.writeHead(404);
        res.end('Not found');
        return;
      }
      const ext = path.extname(full);
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      fs.createReadStream(full).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, url: 'http://127.0.0.1:' + server.address().port });
    });
  });
}

(async () => {
  const { server, url } = await startStaticServer(PKG_DIR);
  const browser = await chromium.launch();
  const errors = [];
  try {
    const context = await browser.newContext({ viewport: { width: 1360, height: 900 }, deviceScaleFactor: 2 });
    const page = await context.newPage();
    page.on('pageerror', (err) => errors.push('pageerror: ' + err.message));
    page.on('console', (msg) => { if (msg.type() === 'error') errors.push('console: ' + msg.text()); });

    await page.goto(url, { waitUntil: 'networkidle' });
    // Force light theme first for predictable baseline screenshot
    if ((await page.locator('html').getAttribute('data-theme')) === 'dark') {
      await page.click('#themeToggleBtn');
    }

    // 1. Initial sample data rendered
    assert.strictEqual(await page.locator('.url-tile').count(), 5, '5 default URLs');
    assert.strictEqual(await page.locator('.memo-card').count(), 4, '4 default memos');

    // 2. Switch environment: 公网 -> 内网
    const bsLink = page.locator('.url-tile', { hasText: 'BookStark 云市场' }).locator('a.url-tile-link');
    assert.strictEqual(await bsLink.getAttribute('href'), 'https://cloud.vs2010wy.top/');
    await page.click('.env-pill[data-env-id="lan"]');
    assert.strictEqual(await bsLink.getAttribute('href'), 'http://192.168.10.10:8089/');
    // Fallback URL (GitHub has no LAN url) still works with default URL
    const ghLink = page.locator('.url-tile', { hasText: 'GitHub' }).locator('a.url-tile-link');
    assert.strictEqual(await ghLink.getAttribute('href'), 'https://github.com/');

    // 3. Single-card quick multi-env popover on ComfyUI
    await page.locator('.url-tile', { hasText: 'ComfyUI 出图台' }).locator('[data-open-env-pop]').click();
    await page.locator('#envPopover').waitFor({ state: 'visible' });
    assert.strictEqual(await page.locator('#envPopover .env-pop-item').count(), 3, 'ComfyUI has 3 env endpoints');
    await page.keyboard.press('Escape');
    await page.locator('#envPopover').waitFor({ state: 'hidden' });

    // 4. Add custom environment "Tailscale"
    await page.click('#openEnvManageBtn');
    await page.fill('#newEnvNameInput', 'Tailscale');
    await page.selectOption('#newEnvColorInput', 'purple');
    await page.click('#addEnvForm button[type="submit"]');
    assert.ok((await page.locator('#envBar').textContent()).includes('Tailscale'));
    await page.locator('#envDialog [data-close-dialog]').first().click();

    // 5. Add new multi-env URL "NAS 管理"
    await page.click('#addLinkBtn');
    await page.fill('#linkTitleInput', 'NAS 管理');
    await page.fill('#linkGroupInput', '自托管');
    await page.fill('#linkDefaultUrlInput', 'https://nas.example.com');
    await page.click('#addEnvUrlRowBtn');
    const firstRow = page.locator('#envUrlRows .env-url-row').nth(0);
    await firstRow.locator('select').selectOption('lan');
    await firstRow.locator('input').fill('http://192.168.10.10:5000');
    await page.click('#addEnvUrlRowBtn');
    const secondRow = page.locator('#envUrlRows .env-url-row').nth(1);
    const tsVal = await secondRow.locator('select option', { hasText: 'Tailscale' }).getAttribute('value');
    await secondRow.locator('select').selectOption(tsVal);
    await secondRow.locator('input').fill('http://100.64.0.10:5000');
    await page.click('#linkForm button[type="submit"]');

    assert.strictEqual(await page.locator('.url-tile').count(), 6, '6 URLs after add');
    const nasLink = page.locator('.url-tile', { hasText: 'NAS 管理' }).locator('a.url-tile-link');
    assert.strictEqual(await nasLink.getAttribute('href'), 'http://192.168.10.10:5000/');
    await page.click(`.env-pill[data-env-id="${tsVal}"]`);
    assert.strictEqual(await nasLink.getAttribute('href'), 'http://100.64.0.10:5000/');
    await page.click('.env-pill[data-env-id="public"]');
    assert.strictEqual(await nasLink.getAttribute('href'), 'https://nas.example.com/');

    // 6. Add tag + content scratchpad note with auto-detected path
    await page.fill('#noteInput', '#模型 #新卡 DeepSeek-R1 量化权重\n/data/models/deepseek-r1-32b.gguf');
    await page.click('#submitNoteBtn');
    assert.strictEqual(await page.locator('.memo-card').count(), 5, '5 memos after add');
    const newCard = page.locator('.memo-card', { hasText: 'DeepSeek-R1' });
    assert.strictEqual(await newCard.locator('.code-chip-row code').textContent(), '/data/models/deepseek-r1-32b.gguf');

    // 7. Filter by tag #新卡 and then reset
    await page.locator('#tagRail [data-filter-tag="新卡"]').click();
    assert.strictEqual(await page.locator('.memo-card').count(), 1, 'filtered to 1 memo');
    await page.click('#resetFilterBtn');
    assert.strictEqual(await page.locator('.memo-card').count(), 5, 'reset back to 5 memos');

    // 8. Inline edit note
    await newCard.locator('[data-edit-note]').click();
    await page.fill('#inlineEditArea', '#模型 #新卡 DeepSeek-R1 32B 已校验\n/data/models/deepseek-r1-32b.gguf');
    await newCard.locator('[data-save-edit]').click();
    assert.ok((await newCard.textContent()).includes('已校验'));

    // 9. Global search filters both URLs and memos
    await page.fill('#globalSearch', 'ComfyUI');
    assert.strictEqual(await page.locator('.url-tile').count(), 1);
    assert.strictEqual(await page.locator('.memo-card').count(), 1);
    await page.fill('#globalSearch', '');

    // Capture live light screenshot
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-light.png'), fullPage: true });

    // 10. Dark theme + reload persistence check
    await page.click('#themeToggleBtn');
    assert.strictEqual(await page.locator('html').getAttribute('data-theme'), 'dark');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-dark.png'), fullPage: true });

    await page.reload({ waitUntil: 'networkidle' });
    assert.strictEqual(await page.locator('.url-tile').count(), 6, 'links persisted');
    assert.strictEqual(await page.locator('.memo-card').count(), 5, 'notes persisted');

    // 11. Mobile 390px overflow check
    await page.setViewportSize({ width: 390, height: 844 });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert.strictEqual(overflow, false, 'no horizontal overflow at 390px');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-mobile.png'), fullPage: true });

    assert.deepStrictEqual(errors, [], 'no console or page errors: ' + errors.join('; '));
    console.log('PASS: NavNotes E2E (multi-env switch, custom env, fallback, popover, tag notes, auto path copy, inline edit, search, dark mode, persistence, 390px mobile)');
  } finally {
    await browser.close();
    server.close();
  }
})();
