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
   async function shot(name){await page.screenshot({path:out+'/26-security-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
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
   for(const route of ['account-security','account-security-unknown','account-security-storage']){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    await text('账户安全','Account security').waitFor();await page.waitForTimeout(250);await shot(route+'-initial');
    const field=(zh,en)=>page.getByRole('textbox',{name:english?en:zh,exact:true});
    await type(field('当前登录密码','Current login password'),'current-pass',true);
    await type(field('新登录密码','New login password'),' browser 新密码 ',true);
    await type(field('确认新登录密码','Confirm new login password'),' browser 新密码 ',true);
    // Close the active native input before scrolling to the submission button.
    await page.keyboard.press('Tab');await page.waitForTimeout(200);
    await click(button('修改登录密码','Change login password'));
    const empty=()=>page.evaluate(()=>[...document.querySelectorAll('input,textarea')].every(node=>node.value===''));
    assert.equal(await empty(),true,'All attached native password input nodes must be cleared');
    if(route==='account-security-unknown'){
      await bring(text('修改结果未知。不会自动重发，请先验证新凭据。','The change result is unknown. It will not be resent. Verify the new credentials first.'),1,true);
      await shot(route+'-unknown');
      await click(button('验证本次新凭据','Verify these new credentials'));
    }else if(route==='account-security-storage'){
      await bring(text('新凭据已验证，但当前会话尚未保存。','The new credentials are verified, but this session is not saved.'),1,true);
      await shot(route+'-storage-pending');
      await click(button('仅重试保存会话','Retry session saving only'));
    }
    const verified=route==='account-security-unknown'?text('新凭据已验证，会话已保存；上次修改回执仍未知。','The new credentials are verified and saved; the earlier change receipt remains unknown.'):text('登录密码修改已核对，当前会话已保存。','The password change was verified and this session is saved.');
    await bring(verified,1,true);await shot(route+'-verified');
    assert.equal(await empty(),true);
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS account security '+(english?'English 320dp200%':'Chinese')+'; actual password typing, clear all attached native inputs, explicit unknown verification and storage-only retry; isolated fixture, no API. Actual Go and root session have separate contract/integration checks.');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
