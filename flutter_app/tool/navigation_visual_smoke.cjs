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
   const errors=[];let apiCalls=0;page.on('pageerror',error=>errors.push(error.message));
   page.on('request',request=>{if(new URL(request.url()).pathname.startsWith('/api/'))apiCalls++});
   await page.goto(origin+'/?page=navigation'+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
   const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
   await page.getByText(english?'Navigation':'导航',{exact:true}).waitFor();
   await page.getByText(english?'Showing 5 · 5 loaded':'当前显示5条 · 已加载5条',{exact:true}).waitFor();
   await page.mouse.move(0,0);await page.waitForTimeout(350);
   await page.screenshot({path:out+'/16-navigation'+(english?'-english-small':'')+'-fixture-actual.png'});
   await page.getByLabel('开发',{exact:true}).click();
   await page.getByText(english?'Showing 4 · 5 loaded':'当前显示4条 · 已加载5条',{exact:true}).waitFor();
   await page.getByRole('button',{name:english?'Change view':'切换视图',exact:true}).click();
   await page.getByRole('menuitem',{name:english?'Compact':'紧凑',exact:true}).click();
   const manage=page.getByRole('button',{name:english?'Manage bookmarks':'管理书签',exact:true});await manage.click();
   await page.getByText(english?'Bookmarks':'书签',{exact:true}).waitFor();
   assert.equal(apiCalls,0);assert.equal(errors.length,0,errors.join('\n'));
   assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   await page.close();console.log('PASS navigation '+(english?'English 320dp 200%':'Chinese')+' fixture groups, compact view, management route; no HTTP');
  }
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});
