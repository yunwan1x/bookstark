// Read-only integration test: fixture cards exist only in the browser DOM.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

(async () => {
  const origin = process.env.BOOKSTARK_TEST_ORIGIN || 'https://books.vs2010wy.top';
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ serviceWorkers: 'block' });
    const login = await context.request.post(origin + '/api/login', {
      data: { account: 'admin', password: process.env.BOOKSTARK_TEST_PASSWORD }
    });
    assert.equal(login.status(), 200);
    const page = await context.newPage();
    page.setDefaultTimeout(60000);
    if (process.env.BOOKSTARK_TEST_LOCAL_ASSETS === '1') {
      for (const asset of ['js/utils.js', 'js/notes.js', 'css/notes.css']) {
        await page.route('**/static/' + asset + '*', route => route.fulfill({
          path: path.join(__dirname, 'static', asset),
          contentType: asset.endsWith('.css') ? 'text/css' : 'application/javascript'
        }));
      }
    }
    await page.goto(origin + '/notes', { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => window.notesApp && window.marked);
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
        writeText: async text => { window.testCopiedText = text; }
      }});
      const fixture = document.createElement('div');
      fixture.id = 'code-copy-test';
      fixture.style.cssText = 'position:fixed;inset:0;z-index:999999;background:white;padding:16px;overflow:auto';
      const content = '```json\n{"message":"<hello>&world"}\n```\n\n```' + 'long-language-'.repeat(30) + '\nsecond block\n```';
      fixture.append(NotesApp.renderNoteCard({ blog_id: 0, content_preview: content, visibility: 0 }, false));
      document.body.append(fixture);
      const clean = document.createElement('div');
      clean.innerHTML = sanitizeRenderedHTML('<button class="code-copy-btn dangerous-action" onclick="alert(1)" style="position:fixed" type="submit">copy</button><button class="delete-action">bad</button><script>alert(1)</script><img src="javascript:alert(1)" onerror="alert(1)">');
      const btn = clean.querySelector('button');
      if (btn.className !== 'code-copy-btn' || btn.type !== 'button' || btn.hasAttribute('onclick') || btn.hasAttribute('style') || clean.querySelector('script,[onerror],img[src]') || clean.querySelectorAll('button')[1].hasAttribute('class')) throw new Error('sanitizer regression');
    });
    for (const width of [1280, 375]) {
      await page.setViewportSize({ width, height: 900 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.setAttribute('data-theme', theme), theme);
        const bounds = await page.locator('#code-copy-test .code-block-header').evaluateAll(headers => headers.map(header => {
          const button = header.querySelector('.code-copy-btn');
          if (!button) throw new Error('sanitizer removed copy button class');
          const h = header.getBoundingClientRect(), b = button.getBoundingClientRect();
          const label = header.querySelector('.code-block-lang').getBoundingClientRect();
          return { gap: h.right - b.right, top: b.top - h.top, bottom: h.bottom - b.bottom, overlaps: label.right > b.left + 1 };
        }));
        assert.equal(bounds.length, 2);
        for (const box of bounds) {
          assert.ok(box.gap >= 10 && box.gap <= 14, JSON.stringify(box));
          assert.ok(box.top >= 0 && box.bottom >= 0 && !box.overlaps, JSON.stringify(box));
        }
        await page.locator('#code-copy-test .code-copy-btn').first().click();
        assert.equal(await page.evaluate(() => window.testCopiedText), '{"message":"<hello>&world"}');
        console.log(`PASS ${width}px ${theme}: right aligned, no overlap, copies exact code`);
      }
    }
    console.log('PASS sanitizer security checks; no server data created');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
