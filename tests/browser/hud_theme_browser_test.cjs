const REPO_ROOT = require('./repo-root.cjs');
// Offline regression test for HUD lifecycle, surface isolation and iframe opt-in.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs'), assert = require('assert/strict');
const bootstrap = fs.readFileSync('templates/base.html', 'utf8').match(/<script>(\(function\(\)\{var k='bookstark-theme'[\s\S]*?)<\/script>/)[1];
const light = process.env.HUD_VARIANT === 'hud-light';
const theme = light ? 'hud-light' : 'hud', scheme = light ? 'light' : 'dark';
const surfaceColor = light ? 'rgb(251, 253, 255)' : 'rgb(6, 27, 43)';
const html = `<!doctype html><html><head><script>${bootstrap};window.firstPaintScheme=document.documentElement.dataset.theme;</script>
<link rel="stylesheet" href="/static/css/variables.css"><link rel="stylesheet" href="/static/css/hud.css">
<style>.home-assistant-dialog{width:300px;height:200px}.home-card{width:300px;height:200px}.bm-row-swipe-actions{position:absolute}</style>
</head><body><select id="profile-theme"><option value="light">Default</option><option value="hud">HUD</option><option value="hud-light">Glacier HUD</option></select>
<div class="book-cover" style="--book-ink:#fff;color:var(--book-ink)">Book title</div><div class="home-card"><a class="home-row">Document underneath</a></div><dialog open class="home-assistant-dialog">Assistant<input aria-label="Message"></dialog>
<div id="bm-list"><div class="bm-row"><div class="bm-row-swipe-actions">Delete</div><div class="bm-row-content">Bookmark</div></div></div>
<iframe class="html-preview-iframe" src="/frame"></iframe><script src="/static/js/theme.js"></script><script src="/static/js/glass-tools.js"></script></body></html>`;
(async () => {
 const browser = await chromium.launch({args:['--no-sandbox']});
 try {
  const context = await browser.newContext({viewport:{width:390,height:844}});
  await context.route('**/*', route => {
   const path = new URL(route.request().url()).pathname;
   if (path.startsWith('/static/')) return route.fulfill({path:'.'+path});
   return route.fulfill({contentType:'text/html',body:path==='/frame'?'<!doctype html><html><head></head><body><div class="panel">Tool</div></body></html>':html});
  });
  for (const name of ['base','editor_common','notes_public','login','register','forgot_password','reset_password']) {
   const source = fs.readFileSync('templates/'+name+'.html','utf8');
   assert(source.includes('/static/css/hud.css'),name+' HUD stylesheet');
   const script = source.match(/<script>(\(function\(\)\{var k='bookstark-theme'[\s\S]*?)<\/script>/)[1];
   assert(script.includes(light ? "'hud-light':'light'" : "hud:'dark'"),name+' first-paint scheme');
  }
  const page = await context.newPage();
  await page.goto('http://hud.test/shares/share-1783071864572357387');
  await page.evaluate(t => BookStarkTheme.set(t), theme);
  assert.equal(await page.evaluate(() => document.documentElement.dataset.theme),scheme);
  assert.equal(await page.locator('#profile-theme').inputValue(),theme);
  await page.reload();
  assert.equal(await page.evaluate(() => BookStarkTheme.get()),theme);
  assert.equal(await page.evaluate(() => window.firstPaintScheme),scheme);
  assert.match(await page.locator('.home-card').evaluate(e=>getComputedStyle(e).borderImageSource),/hud-(?:light-)?frame/);
  assert.equal(await page.locator('.home-card .home-row').evaluate(e=>getComputedStyle(e,'::before').content),'\"\"');
  assert.match(await page.locator('.bm-row-content').evaluate(e=>getComputedStyle(e,'::after').borderImageSource),/hud-(?:light-)?frame/);
  if (light) assert.equal(await page.locator('.book-cover').evaluate(e=>getComputedStyle(e).color),'rgb(12, 25, 54)');
  const surface = await page.locator('dialog').evaluate(e=>({bg:getComputedStyle(e).backgroundColor,blur:getComputedStyle(e).backdropFilter}));
  assert.equal(surface.bg,surfaceColor); assert.equal(surface.blur,'none');
  assert.equal(await page.locator('.bm-row-swipe-actions').evaluate(e=>getComputedStyle(e).visibility),'hidden');
  await page.locator('.bm-row').evaluate(e=>e.classList.add('bm-row-swipe-open'));
  assert.equal(await page.locator('.bm-row-swipe-actions').evaluate(e=>getComputedStyle(e).visibility),'visible');
  assert.equal(await page.locator('.bm-row-content').evaluate(e=>getComputedStyle(e).backgroundColor),surfaceColor);
  await page.locator('input').focus();
  assert.equal(await page.locator('input').evaluate(e=>getComputedStyle(e).outlineStyle),'solid');
  await page.waitForFunction(()=>document.querySelector('iframe').contentDocument.documentElement.dataset.bookstarkHud==='meeting');
  assert.equal(await page.locator('iframe').evaluate(e=>e.contentDocument.documentElement.hasAttribute('data-bookstark-hud-light')),light);
  if (light) assert.equal(await page.locator('iframe').evaluate(e=>e.contentDocument.defaultView.getComputedStyle(e.contentDocument.body).backgroundColor),'rgb(243, 251, 255)');
  const second = await context.newPage(); await second.goto('http://hud.test/home');
  await page.evaluate(()=>BookStarkTheme.set('glass'));
  await second.waitForFunction(()=>BookStarkTheme.get()==='glass');
  assert.equal(await page.locator('iframe').evaluate(e=>e.contentDocument.querySelector('#bookstark-hud-tool').disabled),true);
  await page.evaluate(t=>BookStarkTheme.set(t), theme);
  await page.waitForFunction(()=>!document.querySelector('iframe').contentDocument.querySelector('#bookstark-hud-tool').disabled);
  await page.goto('http://hud.test/shares/untrusted-user-html');
  assert.equal(await page.locator('iframe').evaluate(e=>e.contentDocument.querySelector('#bookstark-hud-tool')),null);
  await page.evaluate(()=>BookStarkTheme.set('light'));
  assert.equal(await page.locator('.home-card').evaluate(e=>getComputedStyle(e).borderImageSource),'none');
  assert.equal(await page.evaluate(()=>BookStarkTheme.normalize('__proto__')),'light');
  console.log('PASS HUD persistence, cross-tab sync, opaque AI/bookmark surfaces, focus, reversible allowlisted iframe paint, theme isolation');
 } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1});
