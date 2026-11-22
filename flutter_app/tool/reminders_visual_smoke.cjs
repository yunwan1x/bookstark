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
   async function shot(name){await page.screenshot({path:out+'/26-reminders-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
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
   for(const route of ['reminders','reminders-unknown','reminders-unavailable']){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    await text('邮件提醒','Email reminders').waitFor();await page.waitForTimeout(250);await shot(route+'-initial');
    if(route==='reminders-unavailable') {
      await click(page.getByRole('switch',{name:english?'Enable task reminders':'启用待办提醒',exact:true}));
    }
    await click(button('增加提前天数','Increase advance days'));
    await click(button('保存提醒设置','Save reminder preferences'));
    if(route==='reminders-unknown'){
      await bring(text('保存结果未知，不会自动重发。','The save result is unknown. It will not be resent.'),1,true);await shot(route+'-unknown');
      await click(button('只读核对保存结果','Verify without writing'));
    }
    await bring(text('实际提醒设置已核对。','Actual reminder preferences verified.'),1,true);await shot(route+'-verified');
    await click(button('发送测试邮件','Send test email'));
    await text('发送一封测试邮件？','Send one test email?').waitFor();await shot(route+'-mail-confirmation');
    await click(button('取消','Cancel'),true);
    await click(button('发送测试邮件','Send test email'));
    await click(button('确认发送一封','Send one email'),true);
    await bring(text('服务器已确认发送请求，请自行检查邮箱。','The server acknowledged sending. Check your mailbox.'),1,true);await shot(route+'-mail-acknowledged');
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS email reminders '+(english?'English 320dp200%':'Chinese')+'; saved actual fixture fields, explicit unknown readback, unavailable scheduler disable, test mail cancel/confirmation and acknowledged state; isolated non-sending fixture. Actual Go/private SMTP and root email edit have separate checks.');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
