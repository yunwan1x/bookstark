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
   const routes=(process.env.BOOKSTARK_SHARE_ROUTES||'share-reader,share-unlock,share-book,share-chapter,share-comments').split(',');
   for(const route of routes) {
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    const titles={'share-reader':english?'Shared reading':'分享阅读','share-unlock':english?'Unlock share':'解锁分享','share-book':english?'Shared contents':'共享目录','share-chapter':english?'Shared chapter':'共享章节','share-comments':english?'Share comments':'分享评论'};
    await page.getByText(titles[route],{exact:true}).first().waitFor();
    await page.waitForTimeout(300);await page.screenshot({path:out+'/24-'+route+(english?'-english-small':'')+'-fixture-actual.png'});
    if(route==='share-unlock') {
     const field=page.getByRole('textbox').first();
     for(let step=0;step<20;step++) {
      if(await field.count()) {const box=await field.boundingBox();if(box&&box.y>55&&box.y+box.height<page.viewportSize().height-70)break;}
      await page.mouse.move(4,250);await page.mouse.wheel(0,160);await page.waitForTimeout(80);
     }
     await field.click();await page.waitForTimeout(250);await page.keyboard.type('bad-secret',{delay:25});await page.keyboard.press('Tab');
     const button=page.getByRole('button',{name:english?'Unlock and read':'解锁阅读',exact:true});
     for(let step=0;step<15;step++) {
      if(await button.count()) {const box=await button.boundingBox();if(box&&box.y>55&&box.y+box.height<page.viewportSize().height-10)break;}
      await page.mouse.move(4,250);await page.mouse.wheel(0,120);await page.waitForTimeout(80);
     }
     await button.click();await page.waitForTimeout(250);
     const message=page.getByText(english?'Unable to unlock. Check the password and connection, then retry.':'无法解锁，请核对密码和网络后重试。',{exact:true}).first();
     for(let step=0;step<20;step++) {
      if(await message.count()) {const box=await message.boundingBox();if(box&&box.y>=55&&box.y<page.viewportSize().height)break;}
      await page.mouse.move(4,250);await page.mouse.wheel(0,-100);await page.waitForTimeout(80);
     }
     await message.waitFor();
     await page.screenshot({path:out+'/24-share-unlock-error'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    if(route==='share-book') {
     const chapter=page.getByRole('button',{name:'第一章：开始阅读',exact:true});
     for(let step=0;step<20;step++) {
      if(await chapter.count()){const box=await chapter.boundingBox();if(box&&box.y>=55&&box.y+box.height<page.viewportSize().height-50)break;}
      await page.mouse.move(4,250);await page.mouse.wheel(0,120);await page.waitForTimeout(80);
     }
     await chapter.click();await page.getByText(english?'Shared chapter':'共享章节',{exact:true}).first().waitFor();
     await page.screenshot({path:out+'/24-share-book-parent-opens'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    if(route==='share-chapter') {
     await page.getByRole('button',{name:english?'Next':'下一章',exact:true}).click();
     await page.getByText('4 / 5',{exact:true}).first().waitFor();
     await page.screenshot({path:out+'/24-share-chapter-next'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    if(route==='share-comments') {
     await page.getByRole('button',{name:english?'Write comment':'写评论',exact:true}).click();
     await page.getByText(english?'Write comment':'写评论',{exact:true}).first().waitFor();
     async function fieldVisible(field) {
      for(let step=0;step<30;step++) {
       if(await field.count()) {const box=await field.boundingBox();if(box&&box.y>=55&&box.y+box.height<page.viewportSize().height-100)return;}
       await page.mouse.move(4,250);await page.mouse.wheel(0,100);await page.waitForTimeout(80);
      }
      throw new Error('Comment field did not become visible');
     }
     const name=page.getByRole('textbox',{name:new RegExp('^'+(english?'Public name':'公开昵称'))});
     await fieldVisible(name);await name.click();await page.waitForTimeout(250);await page.keyboard.type('Browser Visitor',{delay:25});
     const content=page.getByRole('textbox',{name:new RegExp('^'+(english?'Comment':'评论内容'))});
     await fieldVisible(content);await content.click();await page.waitForTimeout(250);await page.keyboard.type('Browser actual comment',{delay:25});await page.keyboard.press('Tab');await page.waitForTimeout(150);
     await page.screenshot({path:out+'/24-share-comment-compose'+(english?'-english-small':'')+'-fixture-actual.png'});
     await page.getByRole('button',{name:english?'Publish comment':'发布评论',exact:true}).click();
     await page.waitForTimeout(350);
     await page.screenshot({path:out+'/24-share-comments-submit-observation'+(english?'-english-small':'')+'-fixture-actual.png'});
     await page.getByText(english?'Share comments':'分享评论',{exact:true}).first().waitFor();
     const published=page.locator('[aria-label*="Browser actual comment"]');
     for(let step=0;step<30;step++) {
      if(await published.count()) break;
      // Keep wheel events outside native read-only text overlays.
      await page.mouse.move(4,250);await page.mouse.wheel(0,100);await page.waitForTimeout(150);
     }
     await page.screenshot({path:out+'/24-comments-publication-semantics'+(english?'-english-small':'')+'.png'});
     await published.first().waitFor({state:'attached'});
     assert.ok(await published.count()>0,'Published comment must be present in the readable semantics');
     await page.screenshot({path:out+'/24-share-comments-published'+(english?'-english-small':'')+'-fixture-actual.png'});
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS public routes ['+routes.join(',')+'] '+(english?'English 320dp 200%':'Chinese')+'; native fixtures and keyboard submission; no API requests');
  }
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
