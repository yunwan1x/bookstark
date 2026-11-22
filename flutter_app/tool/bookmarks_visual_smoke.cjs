const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const origin=process.env.BOOKSTARK_VISUAL_URL||'http://127.0.0.1:8099';
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]) {
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];page.on('pageerror',error=>errors.push(error.message));
   for(const route of ['bookmarks','bookmark-editor']) {
    await page.goto(origin+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
    await page.getByText(route==='bookmarks'?(english?'Bookmarks':'书签'):(english?'Edit bookmark':'编辑书签'),{exact:true}).waitFor();
    await page.mouse.move(0,0);await page.waitForTimeout(400);
    await page.screenshot({path:out+'/15-'+route+(english?'-english-small':'')+'-fixture-actual.png'});
    if(route==='bookmarks') {
     await page.getByRole('button',{name:english?'Select bookmarks':'批量选择',exact:true}).click();
     await page.getByText(english?/0\/200 selected/:/已选择0\/200条/).waitFor();
    } else {
     const title=page.getByRole('textbox',{name:english?'Title':'标题',exact:true});
     await title.waitFor({state:'attached'}); assert.equal(await title.count(),1); // Flutter mirrors the value only when the field is focused.
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   }
   assert.equal(errors.length,0,errors.join('\n'));await page.close();
   console.log('PASS bookmarks '+(english?'English 320dp 200%':'Chinese')+' fixture list/editor and explicit selection');
  }
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});
