// Local Chromium only. Verify startup failures cannot leave permanent skeletons.
const {chromium} = require('playwright');
const fs = require('node:fs');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH, args:['--no-sandbox']});
  try {
    for (const lang of ['zh','en']) for (const mode of ['stale','missing','stalled','healthy']) {
      const page = await browser.newPage({viewport:{width:390,height:844}});
      await page.clock.install();
      await page.route('**/*', async route => {
        const u = new URL(route.request().url());
        if (u.pathname === '/home') return route.fulfill({contentType:'text/html',body:fs.readFileSync('/tmp/home-b1-'+lang+'.html','utf8')});
        if (u.pathname === '/static/js/home.js') {
          if (mode === 'missing') return route.abort();
          if (mode === 'stale') return route.fulfill({contentType:'text/javascript',body:cp.execFileSync('git',['show','aaed2fb:static/js/home.js'],{encoding:'utf8'})});
          if (mode === 'stalled') return route.fulfill({contentType:'text/javascript',body:'/* initialization never completed */'});
        }
        if (u.pathname === '/api/home') return route.fulfill({json:{code:0,sections:[],layout:[],activity:{},recent:[]}});
        if (u.pathname.startsWith('/static/') && fs.existsSync('.'+u.pathname)) return route.fulfill({path:'.'+u.pathname});
        return route.fulfill({status:404,body:''});
      });
      await page.goto('http://home.test/home');
      if (mode === 'stalled') await page.clock.fastForward(131000);
      await page.waitForFunction(() => document.getElementById('homeGrid').getAttribute('aria-busy') === 'false');
      assert.equal(await page.locator('.home-loading-card').count(),0);
      assert.equal(await page.locator('#homeRecent .skeleton').count(),0);
      assert.equal(await page.locator('#homeRetry').isVisible(),mode !== 'healthy');
      console.log(lang, mode, 'PASS');
      await page.close();
    }
  } finally { await browser.close(); }
})().catch(err => {console.error(err);process.exitCode=1;});
