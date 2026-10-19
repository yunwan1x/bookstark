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
      res.end('<!doctype html><meta charset="utf-8"><h1>Private account dashboard</h1><script src="/static/js/sw-register.js"></script>');
      return;
    }
    if (url.pathname === '/api/home') { res.setHeader('Content-Type', 'application/json'); res.end('{"private":true}'); return; }
    const rel = url.pathname === '/sw.js' ? 'static/sw.js' : url.pathname.slice(1);
    if (!rel.startsWith('static/') || rel.includes('..')) { res.writeHead(404); res.end(); return; }
    const file = path.join(__dirname, rel);
    if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', rel.endsWith('.js') ? 'application/javascript' : rel.endsWith('.html') ? 'text/html; charset=utf-8' : 'image/png');
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
    await page.reload();
    assert.equal(await page.locator('h1').textContent(), 'Private account dashboard');
    // Old assets may remain in both the current and another release's cache.
    // A new version must hit the network; exact-version assets remain offline-safe.
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
    await page.evaluate(() => fetch('/api/home'));
    const cached = await page.evaluate(async () => {
      const all = [];
      for (const key of await caches.keys()) for (const req of await (await caches.open(key)).keys()) all.push(new URL(req.url).pathname);
      return all;
    });
    assert.ok(!cached.includes('/') && !cached.includes('/home') && !cached.includes('/api/home'), 'no private dashboard HTML/API in Cache Storage');
    mode = 'stream';
    let streamStart = Date.now();
    await page.goto(origin + '/home', {waitUntil:'commit'});
    await page.getByRole('heading', {name:'Streaming dashboard'}).waitFor();
    assert.ok(Date.now() - streamStart < 4000, 'first paint must not wait for the full HTML body');
    console.log('Streaming HTML first content:', Date.now() - streamStart, 'ms');
    mode = 'online';
    await context.setOffline(true);
    let start = Date.now();
    await page.goto(origin + '/home');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    console.log('Offline startup fallback:', Date.now() - start, 'ms');
    assert.ok(!(await page.textContent('body')).includes('Private account'));
    await context.setOffline(false);
    await page.getByRole('button', {name: '重试'}).click();
    await page.getByRole('heading', {name: 'Private account dashboard'}).waitFor();
    mode = 'slow';
    start = Date.now();
    await page.goto(origin + '/');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    const elapsed = Date.now() - start;
    assert.ok(elapsed < 7500, 'stalled navigation must be bounded');
    console.log('Stalled network fallback:', elapsed, 'ms');
    mode = 'error';
    await page.reload();
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    mode = 'online';
    await page.getByRole('button', {name: '重试'}).click();
    await page.getByRole('heading', {name: 'Private account dashboard'}).waitFor();
    // Even if installation could not cache offline.html, a usable inline fallback remains.
    await page.evaluate(async () => { for (const key of await caches.keys()) await caches.delete(key); });
    await context.setOffline(true);
    await page.goto(origin + '/home');
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    assert.equal(await page.getByRole('button', {name: '重试'}).count(), 1);
    console.log('PASS actual SW: install, warm launch, privacy, offline, deadline, 503, retry, missing fallback cache.');
  } finally {
    await browser.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
