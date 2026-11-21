// Real pointer/touch events: taps must reach buttons, drags activate one tab.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('assert/strict');
(async () => {
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 700 }, hasTouch: true });
    const page = await context.newPage();
    await page.setContent(`<style>nav{display:flex;width:330px;touch-action:pan-y}button{width:110px;height:50px}</style>
      <nav data-swipe-nav><button data-swipe-idx="0" class="active">First</button><button data-swipe-idx="1">Second</button><button data-swipe-idx="2">Third</button></nav>
      <script>window.activations=[];document.querySelectorAll('button').forEach((button,index)=>button.onclick=()=>{document.querySelectorAll('button').forEach(b=>b.classList.remove('active'));button.classList.add('active');activations.push(index)});</script>`);
    await page.addScriptTag({ path: 'static/js/mobile-ui.js' });
    const active = () => page.locator('button.active').getAttribute('data-swipe-idx');
    await page.locator('button').nth(1).click();
    assert.equal(await active(), '1', 'mouse click reaches tab instead of captured parent');
    await page.locator('button').nth(0).tap();
    assert.equal(await active(), '0', 'touch tap reaches tab');
    await page.evaluate(() => { activations.length = 0; });
    await page.mouse.move(260, 30); await page.mouse.down();
    await page.mouse.move(140, 30, { steps: 8 }); await page.mouse.up();
    assert.deepEqual(await page.evaluate(() => activations), [1], 'drag activates exactly one adjacent tab');
    await page.waitForTimeout(360);
    const cdp = await context.newCDPSession(page);
    await page.evaluate(() => { activations.length = 0; });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 260, y: 30 }] });
    for (const x of [230, 190, 140]) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: 30 }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    assert.deepEqual(await page.evaluate(() => activations), [2], 'touch swipe is not double-triggered by pointer events');
    await page.waitForTimeout(360);
    await page.locator('button').nth(0).focus(); await page.keyboard.press('Enter');
    assert.equal(await active(), '0', 'keyboard activation remains available');
    console.log('PASS mouse click, touch tap, pointer drag, touch swipe and keyboard tabs');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
