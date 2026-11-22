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
   const suffix=english?'-english-small':'';
   async function shot(name){await page.screenshot({path:out+'/23-'+name+suffix+'-fixture-actual.png'})}
   async function bring(locator,direction=1,dialog=false,partial=false){
    for(let step=0;step<60;step++) {
     if(await locator.count()){const b=await locator.first().boundingBox();if(b&&((b.y>=55&&b.y+b.height<page.viewportSize().height-15)||(partial&&Math.min(b.y+b.height,page.viewportSize().height-15)-Math.max(b.y,55)>=28)))return;if(b)direction=b.y<55?-1:1;}
     await page.mouse.move(dialog?page.viewportSize().width/2:4,page.viewportSize().height*.5);await page.mouse.wheel(0,direction*110);await page.waitForTimeout(90);
    }
    await shot('debug-unreachable');throw new Error('Control could not be reached by scrolling');
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
     await page.mouse.move(4,250);await page.mouse.wheel(0,110);await page.waitForTimeout(90);
    }
    assert.ok(point,'Editable field must have a reachable interior');
    await page.mouse.click(point.x,point.y);await page.waitForTimeout(250);
    await page.keyboard.press('Control+A');await page.waitForTimeout(100);await page.keyboard.insertText(text);
    await page.waitForFunction(({text,secret})=>{let node=document.activeElement;while(node&&node.shadowRoot&&node.shadowRoot.activeElement)node=node.shadowRoot.activeElement;return node&&typeof node.value==='string'&&(secret?node.value.length===text.length:node.value===text);},{text,secret},{timeout:5000});
    await page.waitForTimeout(150);
   }

   const button=(zh,en)=>page.getByRole('button',{name:english?en:zh,exact:true});
   async function click(zh,en,dialog=false){const item=button(zh,en);await bring(item,1,dialog);await item.click();await page.waitForTimeout(250);}
   for(const route of (process.env.BOOKSTARK_SHARING_ROUTES||'share-settings,share-settings-unknown,content-password,content-password-unknown').split(',')){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    await page.getByText(route.startsWith('share-settings')?(english?'Sharing settings':'分享设置'):(english?'Body password':'内容密码'),{exact:true}).first().waitFor();
    await page.waitForTimeout(250);await shot(route+'-initial');
    if(route.startsWith('share-settings')){
     assert.equal(await button('复制编辑链接','Copy editing link').count(),0);
     await click('公开并获取链接','Publish and obtain links');await shot(route+'-publication-confirmation');
     await click('确认公开并获取','Publish and obtain',true);
     const copy=button('复制编辑链接','Copy editing link');await bring(copy);await shot(route+'-actual-publication-receipt');
     await click('重置编辑链接','Reset editing link');await click('确认','Confirm',true);
     if(route.endsWith('unknown')){
      await click('核对发布状态','Check publication status');
      const statusText=english?'Latest read: published; editing token remains unconfirmed.':'最新读取：已发布，编辑令牌仍待核对。';const unknown=page.getByText(statusText,{exact:false}).or(page.getByLabel(statusText,{exact:false})).last();await bring(unknown,-1,false,true);await shot(route+'-checked-without-resend');
      assert.equal(await copy.count(),0);
     }else{
      await bring(copy);await shot(route+'-reset-receipt');
      await click('停止分享','Stop sharing');await shot(route+'-withdrawal-confirmation');
      const stop=button('停止分享','Stop sharing').last();await bring(stop,1,true);await stop.click();await page.waitForTimeout(250);
      await shot(route+'-after-withdraw-click');
      const unpublished=page.getByText(english?'Unpublished':'未发布',{exact:false}).last();await unpublished.waitFor({state:'attached'});await page.mouse.move(4,250);await page.mouse.wheel(0,-4000);await page.waitForTimeout(250);await shot(route+'-withdrawn');
     }
    }else{
     await type(page.getByRole('textbox',{name:english?'Current password':'当前密码',exact:true}),'fixture-only',true);
     await type(page.getByRole('textbox',{name:english?'New password':'新密码',exact:true}),' browser password ',true);
     await type(page.getByRole('textbox',{name:english?'Confirm new password':'确认新密码',exact:true}),' browser password ',true);
     await click('修改密码','Change password');
     if(route.endsWith('unknown')){await click('只读核对更改结果','Verify the result without writing');}
     const verified=page.getByText(route.endsWith('unknown')?(english?'Current password state verified; the earlier write receipt remains unknown.':'当前密码状态已核对；上次写回执仍未知。'):(english?'Password change verified.':'密码更改已核对。'),{exact:true});await bring(verified,-1);await shot(route+'-verified');
     const fields=page.getByRole('textbox');for(let i=0;i<await fields.count();i++){assert.equal(await fields.nth(i).inputValue(),'');}
     const retained=await page.locator('input,textarea').evaluateAll(nodes=>nodes.some(node=>node.value.includes('fixture-only')||node.value.includes('browser password')));assert.equal(retained,false,'Passwords must be cleared from all attached Web inputs');
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS owner sharing/password '+(english?'English 320dp 200%':'Chinese')+'; explicit publication/reset/withdraw, unknown receipts, actual candidate verification; fixture only, no API');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
