const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const origin=process.env.BOOKSTARK_VISUAL_URL||'http://127.0.0.1:8099';
async function reveal(page,locator) {
 for(let i=0;i<30;i++) {
  if(await locator.count()) {
   const box=await locator.boundingBox();
   if(box&&box.y>=60&&box.y+box.height<page.viewportSize().height)return;
   if(box&&box.y<60) {await page.mouse.move(150,350);await page.mouse.wheel(0,-150);await page.waitForTimeout(100);continue;}
  }
  await page.mouse.move(150,350);await page.mouse.wheel(0,200);await page.waitForTimeout(100);
 }
 throw new Error('Speech control could not be reached by scrolling');
}
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]) {
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let apiCalls=0;
   page.on('pageerror',error=>errors.push(error.message));page.on('request',request=>{if(new URL(request.url()).pathname.startsWith('/api/'))apiCalls++});
   await page.goto(origin+'/?page=speech'+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
   const semantics=page.locator('flt-semantics-placeholder');await semantics.waitFor({state:'attached',timeout:15000});await semantics.dispatchEvent('click');
   await page.getByText(english?'Listen':'听书',{exact:true}).waitFor();
   // Flutter merges the reading status/count into the selectable paragraph's
   // accessible textarea label; its rendered text is not a DOM text node.
   await page.getByRole('textbox',{name:english?/1 \/ 4 passages/:/第1段 \/ 共4段/}).waitFor();
   await page.mouse.move(0,0);await page.waitForTimeout(350);
   await page.screenshot({path:out+'/14-speech'+(english?'-english-small':'')+'-fixture-actual.png'});
   const pause=page.getByRole('button',{name:english?'Pause':'暂停',exact:true});await reveal(page,pause);await pause.click();await page.mouse.move(0,0);
   await page.getByRole('button',{name:english?'Play':'播放',exact:true}).waitFor();
   const next=page.getByRole('button',{name:english?'Next passage':'下一段',exact:true});await reveal(page,next);await next.click();await page.mouse.move(0,0);
   await page.getByRole('button',{name:english?'Pause':'暂停',exact:true}).waitFor();
   const stop=page.getByRole('button',{name:english?'Stop reading':'停止朗读',exact:true});await reveal(page,stop);await stop.click();
   await page.getByRole('button',{name:english?'Play':'播放',exact:true}).waitFor();
   assert.equal(await stop.isEnabled(),false);assert.equal(apiCalls,0);assert.equal(errors.length,0,errors.join('\n'));
   assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   await page.close();console.log('PASS speech '+(english?'English small':'Chinese')+' widget states, pause/next/stop; fixture only, no platform decoder');
  }
 } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1});
