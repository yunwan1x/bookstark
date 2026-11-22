const previewOrigin=process.env.BOOKSTARK_VISUAL_URL||'http://127.0.0.1:8099';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  await page.goto(previewOrigin+'/?page=articles',{waitUntil:'networkidle',timeout:60000});
  const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
  await page.getByText('知识库 · 文章',{exact:true}).waitFor();
  const first=page.getByRole('group',{name:/^如何建立自己的知识体系/});
  await first.waitFor();
  await page.mouse.move(0,0);await page.waitForTimeout(350);
  await page.screenshot({path:out+'/09-articles-fixture-actual.png'});
  await first.click();
  await page.getByText('编辑文章',{exact:true}).waitFor();
  await page.getByRole('button',{name:'预览',exact:true}).click();
  await page.mouse.move(0,0);await page.waitForTimeout(350);
  await page.screenshot({path:out+'/09-article-preview-fixture-actual.png'});
  assert.equal(errors.length,0,errors.join('\n'));
  console.log('PASS article fixture list, typed article editor and shared native preview; no page errors');
 } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
