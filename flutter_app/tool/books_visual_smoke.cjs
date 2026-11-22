const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || '/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const origin = process.env.BOOKSTARK_VISUAL_URL || 'http://127.0.0.1:8099';
(async () => {
 const browser = await chromium.launch({headless:true,
  executablePath:process.env.CHROMIUM_PATH || '/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome', args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for (const [fixture,title,file] of [
   ['books','书籍','11-books-fixture-actual.png'],
   ['book-settings','书籍设置','11-book-settings-fixture-actual.png'],
   ['chapters','阅读的方法','12-chapters-fixture-actual.png'],
   ['document-reader','选择适合自己的书','13-document-reader-fixture-actual.png'],
   ['document-editor','编辑文档','12-document-editor-fixture-actual.png'],
  ]) {
   const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.goto(origin+'/?page='+fixture,{waitUntil:'networkidle',timeout:60000});
   const semantics=page.locator('flt-semantics-placeholder');
   if(await semantics.count())await semantics.dispatchEvent('click');
   await page.getByText(title,{exact:true}).first().waitFor();
   if(fixture==='books')await page.getByRole('button',{name:'新建书籍',exact:true}).waitFor();
   if(fixture==='chapters') {
    await page.getByRole('button',{name:'新建文档',exact:true}).waitFor();
    await page.getByRole('button',{name:'展开或收起',exact:true}).first().click();
   }
   if(fixture==='document-reader')await page.getByRole('button',{name:'下一篇',exact:true}).waitFor();
   await page.mouse.move(0,0);await page.waitForTimeout(350);
   assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0,'Fixture must not display a swallowed application error');
   assert.equal(await page.getByRole('button',{name:'重试',exact:true}).count(),0,'Fixture must load without a retry/error state');
   await page.screenshot({path:out+'/'+file});
   if(fixture==='document-editor') {
    const fields=page.getByRole('textbox');
    await fields.last().click();await page.waitForTimeout(100);
    assert.match(await fields.last().inputValue(),/三个选择标准/);
    await page.getByRole('button',{name:'预览',exact:true}).click();
    await page.mouse.move(0,0);await page.waitForTimeout(350);
    await page.screenshot({path:out+'/12-document-preview-fixture-actual.png'});
   }
   if(fixture==='document-reader') {
    await page.getByRole('button',{name:'下一篇',exact:true}).click();
    await page.getByText('每天二十分钟',{exact:true}).first().waitFor();
   }
   assert.equal(errors.length,0,errors.join('\n'));
   await page.close();console.log('PASS '+fixture+' native fixture and controls');
  }
 } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1});
