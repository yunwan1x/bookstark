// Read-only production smoke test with an actual controlling service worker.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const origin = process.env.BOOKSTARK_TEST_ORIGIN || 'https://books.vs2010wy.top';
(async () => {
  const browser = await chromium.launch({headless: true, args: ['--no-sandbox'], ...(process.env.BOOKSTARK_BROWSER_PROXY ? {proxy:{server:process.env.BOOKSTARK_BROWSER_PROXY}} : {})});
  const context = await browser.newContext({serviceWorkers: 'allow', viewport: {width: 390, height: 844}, isMobile: true});
  const page = await context.newPage();
  page.setDefaultTimeout(120000);
  page.setDefaultNavigationTimeout(120000);
  const errors = [];
  const requested = [];
  page.on('request', req => requested.push(new URL(req.url()).pathname));
  page.on('console', msg => { if (msg.type() === 'warning' || msg.type() === 'error') console.log('BROWSER', msg.text()); });
  page.on('pageerror', err => { errors.push(err.message); console.log('PAGE ERROR', err.message); });
  page.on('requestfailed', req => console.log('REQUEST FAILED', new URL(req.url()).pathname, req.failure().errorText));
  page.on('response', res => { if (['/', '/home', '/api/home'].includes(new URL(res.url()).pathname)) console.log('HTTP', new URL(res.url()).pathname, res.status()); });
  try {
    const login = await context.request.post(origin + '/api/login', {data: {account: 'admin', password: process.env.BOOKSTARK_TEST_PASSWORD}});
    assert.equal(login.status(), 200);
    assert.equal((await login.json()).code, 0);
    let start = Date.now();
    await page.goto(origin + '/', {waitUntil: 'commit'});
    await page.locator('.home-card').first().waitFor();
    console.log('Fresh mobile context, homepage cards:', Date.now() - start, 'ms');
    console.log('Cold browser paint:', await page.evaluate(() => performance.getEntriesByName('first-contentful-paint').map(e => Math.round(e.startTime))), 'ms');
    console.log('Slowest cold resources:', await page.evaluate(() => performance.getEntriesByType('resource').sort((a,b) => b.duration-a.duration).slice(0,8).map(e => ({path:new URL(e.name).pathname, start:Math.round(e.startTime), ms:Math.round(e.duration), wait:Math.round(e.responseStart-e.requestStart), download:Math.round(e.responseEnd-e.responseStart), bytes:e.transferSize}))));
    await page.locator('.home-bottom-nav [data-home-dialog="homeMore"]').click();
    await page.locator('#homeMore').waitFor({state:'visible'});
    await page.locator('#homeMore [data-home-close]').click();
    await page.waitForFunction(() => !!window.BookStarkPWA);
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    assert.ok(!requested.some(p => p.includes('/mathjax/')), 'homepage decoration must not download MathJax');
    await page.waitForLoadState('networkidle', {timeout: 120000});
    start = Date.now();
    await page.reload({waitUntil: 'commit'});
    await page.locator('.home-card').first().waitFor();
    console.log('Warm mobile launch, homepage cards:', Date.now() - start, 'ms');
    console.log('Warm browser paint:', await page.evaluate(() => performance.getEntriesByName('first-contentful-paint').map(e => Math.round(e.startTime))), 'ms');
    await page.waitForLoadState('networkidle', {timeout: 120000});
    start = Date.now();
    await page.goto(origin + '/home', {waitUntil:'commit'});
    await page.locator('.home-card').first().waitFor();
    console.log('Cached app reopen, homepage cards:', Date.now() - start, 'ms');
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({path: '/tmp/bookstark-pwa-mobile.png'});
    const paths = await page.evaluate(async () => {
      const paths = [];
      for (const name of await caches.keys()) for (const req of await (await caches.open(name)).keys()) paths.push(new URL(req.url).pathname);
      return paths;
    });
    assert.ok(!paths.includes('/') && !paths.includes('/home') && !paths.includes('/api/home'));
    await context.setOffline(true);
    start = Date.now();
    await page.goto(origin + '/home', {waitUntil: 'domcontentloaded'});
    await page.getByRole('heading', {name: '暂时无法连接 BookStark'}).waitFor();
    console.log('Production offline fallback:', Date.now() - start, 'ms');
    await context.setOffline(false);
    await page.getByRole('button', {name: '重试'}).click();
    await page.locator('.home-card').first().waitFor();
    await page.setViewportSize({width: 1440, height: 1000});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    assert.deepEqual(errors, []);
    console.log('PASS production: mobile cold/warm, controlling SW, private cache exclusion, offline/retry, desktop layout, no JS errors; no records created.');
  } catch (err) {
    console.log('Failure diagnostics:', await page.evaluate(async () => ({path:location.pathname,title:document.title,status:document.getElementById('homeStatus')?.textContent,ready:document.readyState,workers:(await navigator.serviceWorker.getRegistrations()).map(r=>({installing:r.installing?.state,waiting:r.waiting?.state,active:r.active?.state})),resources:performance.getEntriesByType('resource').sort((a,b)=>b.duration-a.duration).slice(0,10).map(e=>({path:new URL(e.name).pathname,ms:Math.round(e.duration)}))})).catch(()=>({})));
    throw err;
  } finally { await browser.close(); }
})().catch(err => { console.error(err); process.exitCode = 1; });
