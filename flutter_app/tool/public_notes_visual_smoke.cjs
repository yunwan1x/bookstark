const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try{
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of (process.env.BOOKSTARK_NOTES_ENGLISH_ONLY?[true]:[false,true])){
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++});
   async function shot(name){await page.screenshot({path:out+'/25-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
   async function bring(locator,direction=1){for(let i=0;i<60;i++){if(await locator.count()){const b=await locator.first().boundingBox();if(b&&b.y>=55&&b.y+b.height<page.viewportSize().height-15)return;if(b){direction=b.y<55?-1:1;if(b.height<28){await locator.first().evaluate((node,direction)=>{for(let parent=node.parentElement;parent;parent=parent.parentElement){if(parent.getAttribute('role')==='group'&&getComputedStyle(parent).overflowY!=='visible'&&parent.scrollHeight>parent.clientHeight+2){parent.scrollBy(0,direction*110);return;}}},direction);await page.waitForTimeout(200);continue;}}}await page.mouse.move(24,page.viewportSize().height*.5);await page.mouse.wheel(0,direction*110);await page.waitForTimeout(90);}await shot('debug-unreachable');console.log('UNREACHABLE geometry',await locator.count(),await locator.first().boundingBox(),page.viewportSize());console.log('SCROLLERS',await page.locator('flt-semantics').evaluateAll(nodes=>nodes.filter(n=>n.scrollHeight>n.clientHeight+2).map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')?.slice(0,60),h:n.clientHeight,sh:n.scrollHeight,top:n.scrollTop,style:n.getAttribute('style')}))));throw new Error('Public notes control could not be reached');}
   async function click(locator,direction=1){await bring(locator,direction);await locator.click();await page.waitForTimeout(250);}
   const button=(zh,en)=>page.getByRole('button',{name:english?en:zh,exact:true});
   await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page=public-notes'+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
   const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
   await page.getByText(english?'Public notes':'公开笔记',{exact:true}).first().waitFor();await page.waitForTimeout(250);await shot('public-notes');
   assert.equal(await page.getByText('不得公开的标签',{exact:false}).count(),0);
   await click(page.locator('[aria-label="阅读"]').first());assert.equal(await button('解锁阅读','Unlock and read').count(),0);await shot('public-notes-current-page-filter');
   await click(page.locator('[aria-label="'+(english?'All on this page':'本页全部')+'"]').first(),-1);
   await click(button('下一页','Next'));await page.getByText(english?'No public notes on this page.':'这一页暂无公开笔记。',{exact:false}).first().waitFor();await shot('public-notes-empty-second-page');
   await click(button('上一页','Previous'));await click(button('打开完整笔记','Open full note').first());
   await page.getByText(english?'Shared reading':'分享阅读',{exact:true}).first().waitFor();await shot('public-notes-opens-native-reader');
   await page.getByRole('button',{name:/^(Back|返回)$/,exact:true}).click();await page.waitForTimeout(250);await click(button('解锁阅读','Unlock and read'));
   await page.getByText(english?'Shared reading':'分享阅读',{exact:true}).first().waitFor();await shot('public-notes-opens-protected-reader');
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS public notes '+(english?'English 320dp 200%':'Chinese')+'; page-only labels, locked masking, real page state, native readers; fixture only, no API');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
