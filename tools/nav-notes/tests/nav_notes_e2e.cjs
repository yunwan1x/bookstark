#!/usr/bin/env node
'use strict';

const assert = require('assert');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/root/.npm/_npx/f15a2c6009a805b8/node_modules/playwright');

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
      if (clean === '/favicon.ico') {
        res.writeHead(200, { 'Content-Type': 'image/svg+xml' });
        res.end('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#2563eb"/><circle cx="16" cy="16" r="8" fill="#fff"/></svg>');
        return;
      }
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
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || '/root/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome',
    args: ['--no-sandbox'],
  });
  const errors = [];
  try {
    const context = await browser.newContext({ viewport: { width: 1360, height: 900 }, deviceScaleFactor: 2 });
    const page = await context.newPage();
    page.on('pageerror', (err) => errors.push('pageerror: ' + err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error' && !/Failed to load resource:/.test(msg.text())) {
        errors.push('console: ' + msg.text());
      }
    });

    await page.goto(url, { waitUntil: 'networkidle' });
    // Force light theme first via unified settings dropdown
    if ((await page.locator('html').getAttribute('data-theme')) === 'dark') {
      await page.click('#settingsMenuBtn');
      await page.click('#themeLightBtn');
      await page.keyboard.press('Escape');
    }

    // 1. Initial sample data & default single-tab view (导航 only, 随记 hidden!)
    assert.strictEqual((await page.locator('h1').textContent()).trim(), '极简导航 & 随记', 'brand renamed to 极简导航 & 随记');
    assert.strictEqual(await page.locator('.brand-sub').count(), 0, 'no subtitle in header');
    assert.strictEqual(await page.locator('#urlBoardSection').isVisible(), true, 'URL board visible by default');
    assert.strictEqual(await page.locator('#notesSection').isVisible(), false, 'Notes hidden on default Nav tab');
    assert.strictEqual(await page.locator('#viewSeg').isVisible(), true, 'View segmented tab switcher visible');
    assert.strictEqual(await page.locator('.url-tile').count(), 5, '5 default URLs');
    assert.strictEqual(await page.locator('.url-tile .u-ico i.fa-solid').count(), 5, 'every URL has deterministic FA fallback icon');

    // Cross-module search badge test: searching ComfyUI on Nav tab lights up badge on 随记 tab!
    await page.fill('#globalSearch', 'ComfyUI');
    assert.strictEqual(await page.locator('.url-tile').count(), 1);
    assert.strictEqual(await page.locator('#notesSearchBadge').isVisible(), true, 'notes search badge visible');
    assert.strictEqual((await page.locator('#notesSearchBadge').textContent()).trim(), '1');
    await page.click('[data-view-tab="notes"]');
    assert.strictEqual(await page.locator('#urlBoardSection').isVisible(), false, 'URL board hidden on Notes tab');
    assert.strictEqual(await page.locator('#notesSection').isVisible(), true, 'Notes visible on Notes tab');
    assert.strictEqual(await page.locator('.memo-card').count(), 1);
    assert.strictEqual(await page.locator('#navSearchBadge').isVisible(), true, 'nav search badge visible');
    await page.fill('#globalSearch', '');
    await page.click('[data-view-tab="nav"]');

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

    // 5. Add new multi-env URL "本地测试站" pointing to our local server (real favicon!) + custom FA icon test
    await page.click('#addLinkBtn');
    await page.fill('#linkTitleInput', 'NAS 管理');
    await page.fill('#linkGroupInput', '自托管');
    await page.fill('#linkDefaultUrlInput', url);
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
    const nasTile = page.locator('.url-tile', { hasText: 'NAS 管理' });
    const nasLink = nasTile.locator('a.url-tile-link');
    assert.strictEqual(await nasLink.getAttribute('href'), 'http://192.168.10.10:5000/');
    await page.click(`.env-pill[data-env-id="${tsVal}"]`);
    assert.strictEqual(await nasLink.getAttribute('href'), 'http://100.64.0.10:5000/');
    await page.click('.env-pill[data-env-id="public"]');
    assert.strictEqual(await nasLink.getAttribute('href'), url + '/');
    // Real favicon loaded on local test server!
    await nasTile.locator('.u-ico.has-favicon img.u-favicon').waitFor({ state: 'visible', timeout: 5000 });

    // Edit NAS 管理 to test manual FA icon picker (choose fa-rocket in custom icon mode)
    await nasTile.locator('[data-edit-link]').click();
    await page.click('[data-icon-mode="icon"]');
    await page.click('[data-pick-icon="rocket"]');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-icon-picker.png') });
    await page.click('#linkForm button[type="submit"]');
    assert.strictEqual(await nasTile.locator('.u-ico i.fa-rocket').count(), 1, 'custom FA rocket icon applied');
    assert.strictEqual(await nasTile.locator('.u-ico.has-favicon').count(), 0, 'custom icon mode disables favicon overlay');

    // Switch NAS 管理 back to auto favicon for clean light screenshot
    await nasTile.locator('[data-edit-link]').click();
    await page.click('[data-icon-mode="auto"]');
    await page.click('#linkForm button[type="submit"]');
    await nasTile.locator('.u-ico.has-favicon img.u-favicon').waitFor({ state: 'visible', timeout: 5000 });

    // 6. Switch to Notes tab and add tag + content scratchpad note with auto-detected path
    await page.click('[data-view-tab="notes"]');
    assert.strictEqual(await page.locator('.memo-card').count(), 4, '4 default memos');
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

    // 9. Switch to All view & verify global search filters both
    await page.click('[data-view-tab="all"]');
    assert.strictEqual(await page.locator('#urlBoardSection').isVisible(), true);
    assert.strictEqual(await page.locator('#notesSection').isVisible(), true);
    await page.fill('#globalSearch', 'ComfyUI');
    assert.strictEqual(await page.locator('.url-tile').count(), 1);
    assert.strictEqual(await page.locator('.memo-card').count(), 1);
    await page.fill('#globalSearch', '');

    // 9b. Unified Settings dropdown: module checkboxes hide #viewSeg when only 1 module enabled
    await page.click('#settingsMenuBtn');
    await page.locator('#settingsMenu').waitFor({ state: 'visible' });
    await page.uncheck('#modNotesCheck');
    assert.strictEqual(await page.locator('#viewSeg').isVisible(), false, 'Tab switcher auto-hides with single module');
    assert.strictEqual(await page.locator('#notesSection').isVisible(), false);
    assert.strictEqual(await page.locator('#urlBoardSection').isVisible(), true);
    // Attempting to uncheck the last remaining module keeps it checked
    await page.click('#modNavCheck');
    assert.strictEqual(await page.locator('#modNavCheck').isChecked(), true, 'at least 1 module stays enabled');
    // Re-enable notes module -> tab switcher returns
    await page.check('#modNotesCheck');
    assert.strictEqual(await page.locator('#viewSeg').isVisible(), true, 'Tab switcher restored');
    await page.click('[data-default-view="nav"]');

    // Capture live light screenshot (Nav tab with settings dropdown visible)
    await page.click('[data-view-tab="nav"]');
    await page.click('#settingsMenuBtn');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-light.png'), fullPage: true });

    // 10. Dark theme via unified settings dropdown + reload persistence check
    await page.click('#themeDarkBtn');
    await page.keyboard.press('Escape');
    assert.strictEqual(await page.locator('html').getAttribute('data-theme'), 'dark');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-dark.png'), fullPage: true });

    await page.reload({ waitUntil: 'networkidle' });
    assert.strictEqual(await page.locator('#urlBoardSection').isVisible(), true, 'defaultView=nav respected on reload');
    assert.strictEqual(await page.locator('#notesSection').isVisible(), false, 'notes hidden on reload');
    assert.strictEqual(await page.locator('.url-tile').count(), 6, 'links persisted');
    await page.click('[data-view-tab="notes"]');
    assert.strictEqual(await page.locator('.memo-card').count(), 5, 'notes persisted');

    // 11. Mobile 390px single-row Brand+Gear topbar & zero overflow check
    await page.click('[data-view-tab="nav"]');
    await page.setViewportSize({ width: 390, height: 844 });
    const mob = await page.evaluate(() => {
      const brand = document.querySelector('.brand').getBoundingClientRect();
      const gear = document.querySelector('#settingsMenuBtn').getBoundingClientRect();
      return {
        overflow: document.documentElement.scrollWidth > window.innerWidth + 1,
        sameRow: Math.abs(brand.top - gear.top) < 10,
      };
    });
    assert.strictEqual(mob.overflow, false, 'no horizontal overflow at 390px');
    assert.strictEqual(mob.sameRow, true, 'Brand and Settings button share single top row on mobile');
    await page.screenshot({ path: path.join(SHOT_DIR, 'live-e2e-mobile.png'), fullPage: true });

    assert.deepStrictEqual(errors, [], 'no console or page errors: ' + errors.join('; '));
    console.log('PASS: NavNotes v1.2.0 E2E (3-way tab, cross-search badge, unified settings dropdown, module toggles, default view, dark mode, 390px compact topbar)');
  } finally {
    await browser.close();
    server.close();
  }
})();
