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
   async function shot(name){await page.screenshot({path:out+'/28-trash-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
   async function bring(locator,direction=1,partial=false,dialog=false){
    for(let step=0;step<60;step++){
     let clipped=false;
     if(await locator.count()){
      const b=await locator.first().boundingBox();
      if(b&&((b.y>=55&&b.y+b.height<page.viewportSize().height-15)||(partial&&Math.min(b.y+b.height,page.viewportSize().height-15)-Math.max(b.y,55)>=28)))return;
      if(b){direction=b.y<55?-1:1;clipped=b.height<28;}
      if(clipped){await locator.first().evaluate((node,direction)=>{for(let parent=node.parentElement;parent;parent=parent.parentElement){if(parent.getAttribute('role')==='group'&&getComputedStyle(parent).overflowY!=='visible'&&parent.scrollHeight>parent.clientHeight+2){parent.scrollBy(0,direction*110);return;}}},direction);await page.waitForTimeout(200);continue;}
     }
     await page.mouse.move(dialog?page.viewportSize().width/2:24,page.viewportSize().height*.5);await page.mouse.wheel(0,direction*110);await page.waitForTimeout(90);
    }
    await shot('profile-debug-unreachable');throw new Error('Profile control could not be reached');
   }
   async function type(field,text,secret=false){
    let point;
    for(let step=0;step<60;step++) {
     if(await field.count()) {
      const box=await field.first().boundingBox();
      if(box&&box.x>=0&&box.x+box.width<=page.viewportSize().width+2) {
       const top=Math.max(70,box.y+8),bottom=Math.min(page.viewportSize().height-55,box.y+box.height-8);
       if(bottom-top>=28){point={x:box.x+Math.min(24,box.width/2),y:(top+bottom)/2};break;}
      }
     }
     if(await field.count()){await field.first().evaluate(node=>{for(let parent=node.parentElement;parent;parent=parent.parentElement){if(parent.getAttribute('role')==='group'&&getComputedStyle(parent).overflowY!=='visible'&&parent.scrollHeight>parent.clientHeight+2){parent.scrollBy(0,110);return;}}});await page.waitForTimeout(200);}else{await page.mouse.move(24,250);await page.mouse.wheel(0,110);await page.waitForTimeout(90);}
    }
    assert.ok(point,'Editable field must have a reachable interior');
    await page.mouse.click(point.x,point.y);await page.waitForTimeout(250);
    await page.keyboard.press('Control+A');await page.waitForTimeout(100);await page.keyboard.insertText(text);
    await page.waitForFunction(({text,secret})=>{let node=document.activeElement;while(node&&node.shadowRoot&&node.shadowRoot.activeElement)node=node.shadowRoot.activeElement;return node&&typeof node.value==='string'&&(secret?node.value.length===text.length:node.value===text);},{text,secret},{timeout:5000});
    await page.waitForTimeout(150);
   }


   const button=(zh,en)=>page.getByRole('button',{name:english?en:zh,exact:true});
   const text=(zh,en)=>page.getByText(english?en:zh,{exact:false}).or(page.getByLabel(english?en:zh,{exact:false})).last();
   async function click(locator,dialog=false){await bring(locator,1,false,dialog);await locator.click();await page.waitForTimeout(250);}
   for(const route of ['trash-partial','trash-unknown']) {
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');await page.waitForTimeout(400);
    await shot(route+'-initial');
    await click(button('选择当前页','Select current page'));
    await click(button('永久删除所选','Delete selected permanently'));
    await text('永久删除这3项？','Permanently delete these 3 items?').waitFor();await shot(route+'-confirmation');
    await click(button('取消','Cancel'),true);
    await click(button('还原所选','Restore selected'));
    await click(button('确认还原','Confirm restoration'),true);
    if(route==='trash-unknown') {
      await bring(text('结果未知，不会自动重发。','Result unknown. It will not be resent.'),1,true);await shot(route+'-unknown');
      await click(button('只读核对未确认结果','Verify unconfirmed results without writing'));
      await bring(text('记录已移出；上次操作回执仍未知。','The record is absent; the earlier receipt remains unknown.'),1,true);
    } else {
      await bring(text('操作未完成，保留选择','Operation incomplete. Selection retained'),1,true);
      await bring(text('已选1项','1 selected'),1,true);
    }
    await shot(route+'-result');
   }
   assert.equal(api,0,'Fixtures must never contact an API');assert.deepEqual(errors,[]);await page.close();
  }
  console.log('PASS trash browser exact confirmation/cancel, partial selection and unknown readonly verification in Chinese and English narrow200 percent');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
