// Layout regression using production styles, without a server or user data.
// NODE_PATH=<playwright installation>/node_modules node footer_scroll_browser_test.cjs
const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const read = path => fs.readFileSync(path, 'utf8');
const common = read('static/css/tailwind.min.css') + read('static/css/variables.css');
const topics = read('static/css/topics.css');
const labels = read('templates/labels.html').match(/<style>([\s\S]*?)<\/style>/)[1];
const long = '<div style="height:2200px">Long content</div>';
const rows = '<div style="height:40px;flex-shrink:0">Item</div>'.repeat(60);
const layouts = {
  topics: `<main class="topics-page"><div class="topic-workbench">
    <aside class="topic-rail"><div class="topic-toolbar">Topics</div><div class="topic-list">${rows}</div></aside>
    <section class="topic-detail"><div class="topic-detail-content">
    <div class="topic-detail-sticky-controls">Toolbar</div><div class="topic-detail-body">${long}</div>
    </div></section><aside class="topic-context-panel">${rows}</aside></div></main>`,
  labels: `<main class="flex-1 min-h-0"><div class="label-layout">
    <aside class="label-left"><div class="left-header">Tags</div><div class="tag-list">${rows}</div></aside>
    <div class="label-right">${long}</div></div></main>`
};
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    for (const width of [1440, 800, 390]) {
      for (const name of ['topics', 'labels']) {
        const page = await browser.newPage({ viewport: { width, height: 800 } });
        await page.setContent(`<style>${common}${name === 'topics' ? topics : labels}</style>
          <body class="${name}-body min-h-screen flex flex-col">
          <header style="height:40px;flex-shrink:0;position:sticky;top:0;z-index:20">Header</header>
          ${layouts[name]}<footer style="height:40px;flex-shrink:0">Footer</footer></body>`);
        const before = await page.locator('footer').evaluate(e => e.getBoundingClientRect().top);
        assert(before >= 800, `${name}/${width}: footer must start below viewport`);
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'no horizontal overflow');
        await page.evaluate(() => window.scrollTo(0, 400));
        if (name === 'topics') {
          const toolbar = await page.locator('.topic-detail-sticky-controls').boundingBox();
          const stickyTop = await page.locator('.topic-detail-sticky-controls').evaluate(e => parseFloat(getComputedStyle(e).top));
          assert(Math.abs(toolbar.y - stickyTop) < 2, `toolbar should stick: ${toolbar.y}`);
          if (width > 980) {
            assert(await page.locator('.topic-list').evaluate(e => e.scrollHeight > e.clientHeight), 'sidebar scroll retained');
          } else {
            await page.evaluate(() => document.body.classList.add('topic-mobile-topic-open'));
            assert.equal(await page.locator('.topic-rail').evaluate(e => getComputedStyle(e).position), 'fixed');
            await page.evaluate(() => document.body.classList.remove('topic-mobile-topic-open'));
          }
        }
        await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        const end = await page.locator('footer').boundingBox();
        assert(end.y >= 0 && end.y + end.height <= 801, `${name}/${width}: footer visible at bottom`);
        assert(end.y < before, 'footer moves with document');
        console.log(`PASS ${name} ${width}px: document scrolling and footer`);
        if (width === 1440) {
          await page.evaluate(() => {
            for (const selector of ['.topic-detail-body', '.topic-list', '.topic-context-panel', '.label-right', '.tag-list']) {
              const element = document.querySelector(selector);
              if (element) element.textContent = 'Short content';
            }
            window.scrollTo(0, 0);
          });
          const shortFooter = await page.locator('footer').boundingBox();
          assert(Math.abs(shortFooter.y + shortFooter.height - 800) < 2, 'short page footer stays at viewport bottom');
          console.log(`PASS ${name}: short page footer`);
        }
        await page.close();
      }
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
