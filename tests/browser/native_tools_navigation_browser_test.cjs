const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const origin = process.env.BOOKSTARK_TEST_ORIGIN;

(async () => {
  const browser = await chromium.launch({args: ['--no-sandbox', '--disable-dev-shm-usage']});
  try {
    // Exercise native bridge detection without depending on a platform WebView.
    for (const platform of ['windows', 'mac', 'android']) {
      const context = await browser.newContext();
      await context.addInitScript(platform => {
        window.__nativeMessages = [];
        const send = message => {
          if (message.startsWith('bookstark:request:')) {
            const request = JSON.parse(message.slice('bookstark:request:'.length));
            if (request.action === 'capabilities') setTimeout(() => window.BookStarkHostReply(request.id, {version: 1}, null), 0);
            return;
          }
          window.__nativeMessages.push(message);
        };
        if (platform === 'windows') {
          window.chrome = window.chrome || {};
          window.chrome.webview = {postMessage: send};
        } else if (platform === 'mac') {
          window.webkit = {messageHandlers: {external: {postMessage: send}}};
        } else window.BookStarkNative = {openExternal: url => send('bookstark:open-external:' + url)};
      }, platform);
      const page = await context.newPage();
      let popups = 0;
      page.on('pageerror', error => console.log('NATIVE PAGE ERROR', platform, error.message));
      page.on('popup', popup => { popups++; popup.close(); });
      await page.goto(origin + '/shares');
      await page.locator('.public-tools-card a[href="/tools?type=markdown"] i').click();
      try { await page.waitForURL(/\/tools\?/, {waitUntil: 'domcontentloaded', timeout: 10000}); } catch (error) { console.log('NATIVE DEBUG',platform,await page.evaluate(()=>({url:location.href,host:window.BookStarkHost?.available,messages:window.__nativeMessages}))); throw error; }
      await page.locator('#toolsTitle').waitFor({state: 'visible'});
      await page.locator('#toolsTitle').fill('Native ' + platform);
      await page.waitForFunction(() => document.querySelector('#toolsStatus').dataset.state === 'saved');
      const draftURL = page.url();
      await page.locator('.local-tools-brand').click();
      await page.waitForURL(origin + '/shares');
      await page.locator('#publicLocalDrafts a strong').first().click();
      await page.waitForURL(draftURL, {timeout: 5000});
      await page.locator('#toolsTitle').waitFor({state: 'visible'});
      assert.equal(await page.locator('#toolsTitle').inputValue(), 'Native ' + platform);
      await page.locator('.local-tools-brand').click();
      await page.locator('.local-recent-heading a').click();
      await page.waitForURL(origin + '/tools', {timeout: 5000});
      // The same grid is also rendered on the tools welcome screen.
      await page.locator('#toolsWelcome a[href="/tools?type=markdown"]').click();
      await page.locator('#toolsTitle').waitFor({state: 'visible'});
      // Real bookmarks: favicon filtering cancels navigation; title uses
      // stopPropagation; the context-menu action calls window.open directly.
      const login = await context.request.post(origin + '/api/login', {data: {account: 'admin', password: process.env.BOOKSTARK_TEST_PASSWORD}});
      assert.equal(login.status(), 200);
      await page.goto(origin + '/bookmarks');
      const title = page.locator('.bm-row-title').filter({hasText: 'Native external bookmark'});
      await title.waitFor();
      await title.locator('.bm-site-icon').click();
      assert.deepEqual(await page.evaluate(() => window.__nativeMessages), []);
      await title.focus();
      await page.keyboard.press('Enter');
      const expected = 'bookstark:open-external:https://example.com/native-link?q=bookstark';
      assert.deepEqual(await page.evaluate(() => window.__nativeMessages), [expected]);
      const bookmarkID = await title.evaluate(link => Number(link.closest('.bm-row').dataset.id));
      assert.ok(bookmarkID > 0);
      await page.evaluate(id => BM.openBookmark(null, id), bookmarkID);
      assert.deepEqual(await page.evaluate(() => window.__nativeMessages), [expected, expected]);
      assert.equal(page.url().split('?')[0], origin + '/bookmarks', 'external link keeps the client open');
      await page.evaluate(() => { const popup = window.open(undefined, '_blank'); popup.opener = null; popup.location = 'https://example.com/deferred'; });
      assert.equal(await page.evaluate(() => window.__nativeMessages.at(-1)), 'bookstark:open-external:https://example.com/deferred');
      // Another real dynamically-rendered link path, and a generic site link.
      await page.goto(origin + '/nav');
      await page.locator('.nav-card-link').filter({hasText: 'Native external bookmark'}).first().click();
      assert.deepEqual(await page.evaluate(() => window.__nativeMessages), [expected]);
      await page.locator('.nav-card-link').filter({hasText: 'Native external bookmark'}).first().click({button: 'middle'});
      assert.deepEqual(await page.evaluate(() => window.__nativeMessages), [expected, expected]);
      await page.evaluate(() => {
        const link = document.createElement('a'); link.href = '/notes'; link.target = '_blank'; link.textContent = 'Open notes'; link.id = 'nativeInternalTest'; document.body.append(link);
      });
      await page.locator('#nativeInternalTest').click();
      await page.waitForURL(origin + '/notes', {timeout: 5000});
      await page.evaluate(() => {
        const link = document.createElement('a'); link.href = '/shares'; link.textContent = 'Modified click'; link.id = 'nativeModifiedTest'; document.body.append(link);
      });
      await page.locator('#nativeModifiedTest').click({modifiers: ['Control']});
      await page.waitForURL(origin + '/shares', {timeout: 5000});
      assert.equal(popups, 0, platform + ' stays inside the client');
      await context.close();
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(origin + '/shares');
    const popupPromise = page.waitForEvent('popup');
    await page.locator('.public-tools-card a[href="/tools?type=markdown"]').click();
    const popup = await popupPromise;
    await popup.waitForURL(/\/tools\?/);
    assert.equal(page.url(), origin + '/shares', 'browser keeps the plaza open');
    await context.close();
    console.log('PASS: native tools/drafts; real bookmark title, favicon and JS action; navigation cards; internal link; browser new tab');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
