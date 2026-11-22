const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try{
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]){
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++});
   await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page=search'+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
   const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
   await page.getByText(english?'Global search':'全局搜索',{exact:true}).waitFor();await page.waitForTimeout(350);
   await page.screenshot({path:out+'/19-search'+(english?'-english-small':'')+'-fixture-actual.png'});
   const filter=page.getByLabel(english?'Bookmarks 2':'书签 2',{exact:true});
   for(let i=0;i<15&&!await filter.isVisible();i++){await page.mouse.move(150,400);await page.mouse.wheel(0,200);await page.waitForTimeout(100);}
   await filter.click();await page.mouse.move(150,400);await page.mouse.wheel(0,550);await page.waitForTimeout(300);
   await page.screenshot({path:out+'/19-search-bookmarks'+(english?'-english-small':'')+'-fixture-actual.png'});
   await page.mouse.wheel(0,-10000);await page.waitForTimeout(300);await page.getByRole('button',{name:english?'Clear':'清空',exact:true}).click();
   await page.getByText(english?/Enter a query to find/:/输入关键词，查找/).waitFor();
   assert.equal(api,0);assert.deepEqual(errors,[]);assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   await page.close();console.log('PASS global search '+(english?'English 320dp 200%':'Chinese')+' loaded groups, bookmark filter and clear; fixture only, no HTTP');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
