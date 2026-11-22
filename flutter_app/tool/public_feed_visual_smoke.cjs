const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]) {
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++});
   for(const route of ['public-feed','resource-create','document-location','document-create']) {
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    const title=route==='public-feed'?(english?'Public feed':'公开广场'):route==='resource-create'?(english?'Create resource':'新建资源'):route==='document-location'?(english?'Choose document location':'选择文档位置'):(english?'New document':'新建文档');
    await page.getByText(title,{exact:true}).first().waitFor();await page.waitForTimeout(400);
    await page.screenshot({path:out+'/22-'+route+(english?'-english-small':'')+'-fixture-actual.png'});
    if(route==='document-location') {
     const folder=page.getByRole('button',{name:'第一章：建立阅读习惯',exact:true}).first();
     for(let step=0;step<16;step++) {
      if(await folder.count()) {const box=await folder.boundingBox();if(box&&box.y>=60&&box.y+box.height<page.viewportSize().height-140)break;}
      await page.mouse.move(150,250);await page.mouse.wheel(0,160);await page.waitForTimeout(120);
     }
     await folder.click();await page.waitForTimeout(200);
     await page.screenshot({path:out+'/22-document-location-nested'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    if(route==='public-feed') {
     // Flutter versions expose ChoiceChip as radio or button; its exact text is stable.
     await page.locator('[aria-label="'+(english?'Bookmarks':'书签')+'"]').first().click();
     await page.waitForTimeout(200);
     await page.screenshot({path:out+'/22-public-bookmarks'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS public feed/create selector '+(english?'English 320dp 200%':'Chinese')+' native fixtures; no HTTP writes');
  }
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
