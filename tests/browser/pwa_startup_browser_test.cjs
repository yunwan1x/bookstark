const REPO_ROOT = require('./repo-root.cjs');
// Real Chromium service-worker regression tests; no production data is written.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  let mode = 'online';
  const requests = [];
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (mode === 'offline') { req.socket.destroy(); return; }
    requests.push(url.pathname);
    if (url.pathname === '/' || url.pathname === '/home') {
      if (mode === 'stream') {
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.write('<!doctype html><h1>Streaming dashboard</h1>' + ' '.repeat(2048));
        const timer = setTimeout(() => res.end(), 10000);
        res.on('close', () => clearTimeout(timer));
        return;
      }
      if (mode === 'slow') { const timer = setTimeout(() => res.end('too late'), 15000); res.on('close', () => clearTimeout(timer)); return; }
      if (mode === 'error') { res.writeHead(503); res.end('server error'); return; }
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end('<!doctype html><meta charset="utf-8"><h1>Personal dashboard</h1><script src="/static/js/sw-register.js"></script>');
      return;
    }
    if (url.pathname === '/shares') {
      res.setHeader('Vary', 'X-BookStark-Feed');
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      if (req.headers['x-bookstark-feed'] === 'content') {
        res.end('<div class="partial">fragment only</div>');
        return;
      }
      res.end('<!doctype html><meta charset="utf-8"><h1>Plaza full page</h1><script src="/static/js/sw-register.js"></script>');
      return;
    }
    if (url.pathname === '/notes' || url.pathname === '/books') {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end(`<!doctype html><meta charset="utf-8"><h1>Page ${url.pathname}${url.search}</h1><script src="/static/js/sw-register.js"></script>`);
      return;
    }
    if (url.pathname === '/api/home') { res.setHeader('Content-Type', 'application/json'); res.end('{"ok":true,"source":"home"}'); return; }
    const rel = url.pathname === '/sw.js' ? 'static/sw.js' : url.pathname.slice(1);
    if (!rel.startsWith('static/') || rel.includes('..')) { res.writeHead(404); res.end(); return; }
    const file = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', rel.endsWith('.js') ? 'application/javascript' : rel.endsWith('.css') ? 'text/css' : rel.endsWith('.html') ? 'text/html; charset=utf-8' : 'image/png');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({headless: true, args: ['--no-sandbox']});
  const context = await browser.newContext({viewport: {width: 390, height: 844}, isMobile: true, serviceWorkers: 'allow'});
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  try {
    await page.goto(origin);
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    assert.ok(!requests.some(p => /excalidraw|univer|pptist|webfonts/.test(p)), 'no optional editor/font downloads during install');

    // Warm online visits populate DYNAMIC_CACHE for /, /home, /shares (full page only), /notes?tab=tasks, /books, /api/home
    await page.reload();
    assert.equal(await page.locator('h1').textContent(), 'Personal dashboard');
    await page.evaluate(() => fetch('/api/home'));
    await page.goto(origin + '/shares');
    assert.equal(await page.locator('h1').textContent(), 'Plaza full page');
    // Partial AJAX fragment must not overwrite cached full page
    const frag = await page.evaluate(() => fetch('/shares', {headers: {'X-BookStark-Feed': 'content'}}).then(r => r.text()));
    assert.ok(frag.includes('fragment only'));
    await page.goto(origin + '/notes?tab=tasks');
    assert.equal(await page.locator('h1').textContent(), 'Page /notes?tab=tasks');
    await page.goto(origin + '/books');
    assert.equal(await page.locator('h1').textContent(), 'Page /books');

    // Exact static asset versioning online + offline fallback
    await page.evaluate(async () => {
      const key = (await caches.keys()).find(k => k.startsWith('bookstark-static-'));
      await (await caches.open(key)).put('/static/js/home.js?v=old', new Response('stale script'));
      await (await caches.open('bookstark-static-legacy-test')).put('/static/js/home.js?v=new', new Response('wrong release'));
    });
    const fresh = await page.evaluate(() => fetch('/static/js/home.js?v=new').then(r => r.text()));
    assert.ok(fresh.includes('function renderCalendar()'), 'new version bypasses stale/current and foreign caches');
    await page.evaluate(async () => {
      const key = (await caches.keys()).find(k => k.startsWith('bookstark-static-') && !k.endsWith('legacy-test'));
      await (await caches.open(key)).put('/static/js/home.js?v=exact', new Response('exact version'));
    });
    assert.equal(await page.evaluate(() => fetch('/static/js/home.js?v=exact').then(r => r.text())), 'exact version');

    // Streaming HTML first paint must not wait for the full body
    mode = 'stream';
    let streamStart = Date.now();
    await page.goto(origin + '/home', {waitUntil:'commit'});
    await page.getByRole('heading', {name:'Streaming dashboard'}).waitFor();
    assert.ok(Date.now() - streamStart < 4000, 'first paint must not wait for the full HTML body');
    mode = 'online';

    // Offline tests: /, /home, /shares, /notes (ignoring query), /api/home, and post-release static asset fallback all work!
    mode = 'offline';
    await context.setOffline(true);
    await page.goto(origin + '/');
    assert.equal(await page.locator('h1').textContent(), 'Personal dashboard', 'offline start_url / shows cached dashboard');
    const cachedHomeApi = await page.evaluate(() => fetch('/api/home').then(r => r.json()));
    assert.equal(cachedHomeApi.source, 'home', 'offline /api/home falls back to cache');
    await page.goto(origin + '/shares');
    assert.equal(await page.locator('h1').textContent(), 'Plaza full page', 'offline /shares shows full page, not fragment');
    await page.goto(origin + '/notes');
    assert.equal(await page.locator('h1').textContent(), 'Page /notes?tab=tasks', 'offline /notes falls back to cached /notes?tab=tasks');
    const offlineStaticFallback = await page.evaluate(() => fetch('/static/js/home.js?v=missing-after-deploy').then(r => r.text()));
    assert.ok(offlineStaticFallback.length > 0, 'offline missing static ?v= falls back to STATIC_CACHE pathname');

    // Uncached page offline shows offline.html WITH clickable cached page links!
    await page.goto(origin + '/uncached-route');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    await page.locator('#cachedList a[href="/books"]').waitFor({state: 'visible'});

    // Stalled / 503 network falls back to cached / within deadline
    await context.setOffline(false);
    mode = 'slow';
    let start = Date.now();
    await page.goto(origin + '/');
    assert.equal(await page.locator('h1').textContent(), 'Personal dashboard', 'stalled / falls back to cached dashboard');
    assert.ok(Date.now() - start < 7500, 'stalled navigation must be bounded');
    mode = 'error';
    await page.reload();
    assert.equal(await page.locator('h1').textContent(), 'Personal dashboard', '503 falls back to cached dashboard');

    // Clearing page cache (logout/login) wipes cached HTML so offline shows offline.html (no cross-account leak!)
    mode = 'online';
    await context.setOffline(false);
    await page.goto(origin + '/books');
    await page.evaluate(() => window.BookStarkPWA.clearPageCache());
    mode = 'offline';
    await context.setOffline(true);
    await page.goto(origin + '/');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    assert.equal(await page.getByRole('button', {name: '重试'}).count(), 1);

    // Even if all caches are wiped, inline fallback remains usable
    await page.evaluate(async () => { for (const key of await caches.keys()) await caches.delete(key); });
    await page.goto(origin + '/home');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    assert.equal(await page.getByRole('button', {name: '重试'}).count(), 1);

    console.log('PASS actual SW: offline /, /home, /shares, /notes query-fallback, /api/home, offline hub links, logout clear, static fallback.');
  } finally {
    await browser.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
