const previewOrigin=process.env.BOOKSTARK_VISUAL_URL||'http://127.0.0.1:8099';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const [fixture,title,file] of [
   ['tasks','行动 · 待办','10-tasks-fixture-actual.png'],
   ['task-editor','编辑待办','10-task-editor-fixture-actual.png'],
   ['task-calendar','待办日历','10-task-calendar-fixture-actual.png'],
  ]) {
   const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto(previewOrigin+'/?page='+fixture,{waitUntil:'networkidle',timeout:60000});
   const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
   await page.getByText(title,{exact:true}).waitFor();
   if(fixture==='tasks') {
    await page.getByRole('checkbox').first().waitFor();
    await page.getByRole('button',{name:'新建待办',exact:true}).waitFor({timeout:5000});
   }
   if(fixture==='task-editor') {
    const input=page.locator('textarea:not([disabled])').first();await input.waitFor();

   }
   if(fixture==='task-calendar') await page.getByRole('button',{name:/2026.*11.*4.*修改2条/}).waitFor();
   await page.mouse.move(0,0);await page.waitForTimeout(350);
   await page.screenshot({path:out+'/'+file});
   if(fixture==='task-editor') {
    const input=page.getByRole('textbox').first();
    await input.click();await page.waitForTimeout(100);
    assert.match(await input.inputValue(),/选择一本正在阅读的书/);
    await page.getByRole('button',{name:'预览',exact:true}).click();await page.mouse.move(0,0);
    await page.getByRole('button',{name:'继续编辑',exact:true}).waitFor();await page.waitForTimeout(350);
    await page.screenshot({path:out+'/10-task-preview-fixture-actual.png'});
   }
   assert.equal(errors.length,0,errors.join('\n'));
   console.log('PASS '+fixture+' native fixture rendered with actual controls and no page errors');
   await page.close();
  }
 } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
