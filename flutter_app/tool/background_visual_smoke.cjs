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
   async function shot(name){await page.screenshot({path:out+'/26-background-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
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
   for(const route of ['background','background-unknown']){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');
    // Flutter can retain accessibility activation after keyboard navigation.
    // Require either its activation control or this actual fixture heading;
    // an empty/crashed page must still fail before subsequent UI assertions.
    await Promise.race([
      placeholder.waitFor({state:'attached'}),
      text('背景设置','Background settings').waitFor({state:'attached'}),
    ]);
    if(await placeholder.count())await placeholder.dispatchEvent('click');
    await text('背景设置','Background settings').waitFor();await page.waitForTimeout(250);await shot(route+'-initial');
    let solid=page.getByRole('radio',{name:english?'Solid':'纯色',exact:true}).or(page.getByRole('button',{name:english?'Solid':'纯色',exact:true}));
    if(!await solid.count())solid=page.locator('[aria-label="'+(english?'Solid':'纯色')+'"]');
    solid=solid.first();
    await click(solid);
    const slider=page.getByRole('slider').first();
    await bring(slider);
    // Traverse actual Flutter keyboard focus; semantics inputs can be disabled
    // while the engine is in pointer gesture mode, so DOM .focus is insufficient.
    let adjusted=false;
    for(let tab=0;tab<18;tab++){
      await page.keyboard.press('Tab');await page.keyboard.press('ArrowLeft');await page.waitForTimeout(100);
      if(await slider.getAttribute('aria-valuetext')==='64%'){adjusted=true;break;}
    }
    assert.equal(adjusted,true,'Keyboard Tab focus and ArrowLeft must adjust actual fade to64%');
    await click(button('保存背景设置','Save background preferences'));
    if(route==='background-unknown'){
      await bring(text('保存结果未知，不会自动重发图片。','The save result is unknown. The image will not be resent automatically.'),1,true);await shot(route+'-unknown');
      await click(button('只读核对背景结果','Verify background without writing'));
    }
    await bring(text('实际背景设置已核对。','Actual background preferences verified.'),1,true);await shot(route+'-verified');
    if(route==='background'){
      await click(button('选择图片','Choose image'));
      await bring(text('已选择本地图片，尚未保存。','Local image selected. It is not saved yet.'),1,true);await shot(route+'-image-local');
      await click(button('保存背景设置','Save background preferences'));
      await bring(text('实际背景设置已核对。','Actual background preferences verified.'),1,true);await shot(route+'-image-saved');
      await click(button('恢复默认并移除图片','Restore defaults and remove image'));
      await click(button('保存背景设置','Save background preferences'));
      await bring(text('实际背景设置已核对。','Actual background preferences verified.'),1,true);await shot(route+'-reset');
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS background preferences '+(english?'English 320dp200%':'Chinese')+'; local preview, real Tab/ArrowLeft adjustment to64%, known/unknown readback, synthetic private image selection/save/reset; isolated fixture. Actual JPEG/ETag/SHA256 and root application/logout have separate Go and integration checks.');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
