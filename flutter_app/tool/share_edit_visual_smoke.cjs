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
   async function shot(name){await page.screenshot({path:out+'/24-'+name+suffix+'-fixture-actual.png'})}
   async function bring(locator,direction=1,dialog=false){
    for(let step=0;step<60;step++) {
     if(await locator.count()){const b=await locator.first().boundingBox();if(b&&b.y>=55&&b.y+b.height<page.viewportSize().height-15)return;if(b)direction=b.y<55?-1:1;}
     await page.mouse.move(dialog?24:4,page.viewportSize().height*.5);await page.mouse.wheel(0,direction*110);await page.waitForTimeout(90);
    }
    throw new Error('Control could not be reached by scrolling');
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
   const routes=(process.env.BOOKSTARK_EDIT_ROUTES||'share-edit-link,share-edit,share-edit-password,share-edit-conflict,share-edit-unknown').split(',');
   for(const route of routes){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    const entry=route==='share-edit-link'||route==='share-edit-password';
    await page.getByText(entry?(english?'Open editing link':'打开编辑链接'):(english?'Shared editing':'共享编辑'),{exact:true}).first().waitFor();
    await page.waitForTimeout(250);await shot(route+(route==='share-edit-password'?'-entry':''));
    if(entry){
     await type(page.getByRole('textbox',{disabled:false}).first(),'https://fixture.invalid/shares/editor?token='+'f'.repeat(64));
     await shot(route+'-filled');
     const verify=page.getByRole('button',{name:english?'Verify and open':'验证并打开',exact:true});await bring(verify);await verify.click();await page.waitForTimeout(350);await shot(route+'-verify-observation');
     if(route==='share-edit-password'){
      await page.getByText(english?'Verify share password':'验证分享密码',{exact:true}).first().waitFor();await shot('share-edit-password');
      await type(page.getByRole('textbox',{disabled:false}).first(),'fixture-only',true);
      const unlock=page.getByRole('button',{name:english?'Verify and edit':'验证并编辑',exact:true});await bring(unlock);await unlock.click();
     }
     await page.getByText(english?'Shared editing':'共享编辑',{exact:true}).first().waitFor();await shot(route+'-opens-editor');
    }else{
     const input=page.getByRole('textbox',{name:new RegExp('^'+(english?'Markdown content':'Markdown正文'))});
     await type(input,route==='share-edit-conflict'?'# Browser local proposal':route==='share-edit-unknown'?'# Browser pending save':'# Browser shared edit');
     await page.getByRole('button',{name:english?'Save':'保存',exact:true}).click();
     if(route==='share-edit-conflict'){
      await page.getByText(english?'Remote content has changed':'远端正文已更新',{exact:true}).first().waitFor();await shot('share-edit-conflict-dialog');
      const load=page.getByRole('button',{name:english?'Load remote':'载入远端',exact:true});await bring(load,1,true);await load.click();
      const preview=page.getByRole('button',{name:english?'Preview':'预览',exact:true});await bring(preview,-1);await preview.click();
      await page.waitForTimeout(250);assert.equal(await page.getByRole('textbox',{name:/^Markdown正文|^Markdown content/}).count(),0);await shot('share-edit-conflict-loaded');
     }else{
      const status=page.getByText(route==='share-edit-unknown'?(english?'Save result unknown. Verify the remote content first.':'保存结果未知，请先核对远端。'):(english?'Save confirmed':'保存已确认'),{exact:true}).first();
      await bring(status);await shot(route+'-save-state');
      if(route==='share-edit-unknown'){
       const reload=page.getByRole('button',{name:english?'Reload to verify':'重新读取核对',exact:true});await bring(reload);await reload.click();
       const matches=page.getByText(english?'Remote content matches':'远端正文已一致',{exact:true}).first();await bring(matches);await shot('share-edit-unknown-verified');
      }else{
       const preview=page.getByRole('button',{name:english?'Preview':'预览',exact:true});await bring(preview,-1);await preview.click();
       await shot('share-edit-preview-observation');
       // The shared selectable renderer paints rich text on canvas. Native
       // Flutter tests assert its rendered body; this checks the real mode
       // switch and retains the screenshot for direct prototype comparison.
       await page.waitForTimeout(250);assert.equal(await page.getByRole('textbox',{name:/^Markdown正文|^Markdown content/}).count(),0);await shot('share-edit-saved-preview');
      }
     }
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS shared editing ['+routes.join(',')+'] '+(english?'English 320dp 200%':'Chinese')+'; capability/password/native Markdown/conflict/receipt states; fixture only, no API requests');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
