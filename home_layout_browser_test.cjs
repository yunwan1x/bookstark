// Uses the real template/styles/script with mocked API responses; no production data.
const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const keys = ['notes','articles','tasks','books','bookmarks','topics','nav','shares','assets'];
const sections = keys.map(key => ({key,total:1,items:[{title:key,url:'/notes',date:'2026-10-09'}]}));
let saved = null, fail = false, saves = 0;
(async () => {
  const browser = await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:1000}});
    const errors = []; page.on('pageerror',error => errors.push(error.message));
    await page.route('http://layout.test/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/api/home/layout') {
        saves++;
        if (fail) return route.fulfill({status:500,json:{code:500}});
        saved = route.request().postDataJSON().layout;
        return route.fulfill({json:{code:0,layout:saved}});
      }
      if (url.pathname === '/api/home') return route.fulfill({json:{code:0,sections,layout:saved}});
      if (url.pathname.startsWith('/static/')) return route.fulfill({path:'.'+url.pathname});
      const translations = Object.fromEntries([...fs.readFileSync('i18n/zh.go','utf8').matchAll(/"(home\.layout\.[^"]+)":\s*"([^"]*)"/g)].map(match=>[match[1],match[2]]));
      let html = fs.readFileSync('templates/home.html','utf8').replace(/\{\{call \.T "([^"]+)"\}\}/g,(_,key)=>translations[key]||key).replace(/\{\{[^}]*\}\}/g,'');
      html = html.replace('<head>','<head><script>window.csrfFetch=window.fetch; document.documentElement.lang="zh";</script><link rel="stylesheet" href="/static/css/variables.css">');
      return route.fulfill({contentType:'text/html',body:html});
    });
    await page.goto('http://layout.test/home');
    await page.waitForSelector('.home-card');
    const open = async () => {await page.locator('[data-home-dialog="homeCustomize"]').click();};
    await open();
    await page.locator('#home-layout-width-notes').selectOption('3');
    await page.locator('#home-layout-width-articles').selectOption('2');
    assert.equal(await page.locator('.home-card[data-section="notes"]').getAttribute('data-width'),'1');
    await page.keyboard.press('Escape');
    assert.equal(saves,0);
    await open();
    assert.equal(await page.locator('#home-layout-width-notes').inputValue(),'1');
    await page.locator('#home-layout-width-notes').selectOption('3');
    await page.locator('#home-layout-width-articles').selectOption('2');
    await page.locator('#homeLayoutSave').click();
    await page.waitForFunction(() => !document.querySelector('#homeCustomize').open);
    const bounds = async key => page.locator('.home-card[data-section="'+key+'"]').boundingBox();
    const notes = await bounds('notes'), articles = await bounds('articles'), tasks = await bounds('tasks');
    assert(articles.y > notes.y && Math.abs(articles.y-tasks.y)<2);
    assert(articles.width > tasks.width*1.8 && notes.width > articles.width);
    await page.reload(); await page.waitForSelector('.home-card[data-width="3"]');
    assert.equal(await page.locator('.home-card[data-section="notes"]').getAttribute('data-width'),'3');
    console.log('PASS draft cancellation, full row / two-column placement, save and reload');
    await open();
    await page.locator('#home-layout-drag-tasks').dragTo(page.locator('.home-layout-card[data-key="notes"]'));
    assert.equal(await page.locator('.home-layout-card').first().getAttribute('data-key'),'tasks');
    await page.locator('.home-layout-card[data-key="tasks"] button[aria-label="下移 待办"]').click();
    assert.equal(await page.locator('.home-layout-card').first().getAttribute('data-key'),'notes');
    await page.locator('#home-layout-visible-books').uncheck();
    fail = true;
    await page.locator('#homeLayoutSave').click();
    await page.waitForFunction(() => document.querySelector('#homeLayoutStatus').textContent.includes('保存失败'));
    assert.equal(await page.locator('#home-layout-visible-books').isChecked(),false);
    assert.equal(await page.locator('.home-card[data-section="books"]').count(),1);
    fail = false;
    await page.locator('#homeLayoutSave').click();
    await page.waitForFunction(() => !document.querySelector('#homeCustomize').open);
    assert.equal(await page.locator('.home-card[data-section="books"]').count(),0);
    console.log('PASS drag reorder, keyboard-accessible arrows, hide, failed-save draft and retry');
    for (const width of [850,390]) {
      await page.setViewportSize({width,height:844});
      const a = await bounds('articles'), t = await bounds('tasks'), n = await bounds('notes');
      assert(t.y > n.y && a.y > t.y, 'tablet/mobile row flow follows saved notes/tasks/articles order');
      if (width===390) assert(Math.abs(a.width-t.width)<2, 'phone always one column');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await open();
      assert(await page.locator('#homeLayoutSave').isVisible());
      const dialog = await page.locator('#homeCustomize').boundingBox();
      assert(dialog.x>=0 && dialog.x+dialog.width<=width+1);
      await page.screenshot({path:'/tmp/bookstark-layout-'+width+'.png'});
      await page.keyboard.press('Escape');
    }
    await open(); await page.locator('#homeLayoutReset').click(); await page.locator('#homeLayoutSave').click();
    await page.waitForFunction(() => !document.querySelector('#homeCustomize').open);
    assert(saved.every(item => item.width===1 && !item.hidden));
    assert.deepEqual(saved.map(item=>item.key),keys);
    assert.deepEqual(errors,[]);
    console.log('PASS tablet/phone layout, no overflow, restore defaults and no JS errors');
  } finally {await browser.close();}
})().catch(error => {console.error(error);process.exitCode=1;});
