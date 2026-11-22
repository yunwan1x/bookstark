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
   async function shot(name){await page.screenshot({path:out+'/26-'+name+(english?'-english-small':'')+'-fixture-actual.png'})}
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
   for(const route of (process.env.BOOKSTARK_PROFILE_ROUTES||'profile,profile-edit,profile-edit-conflict,profile-edit-unknown').split(',')){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
    await text(route==='profile'?'我的':'编辑资料',route==='profile'?'My account':'Edit profile').waitFor();await page.waitForTimeout(250);await shot(route+'-initial');
    if(route==='profile'){await click(button('编辑资料','Edit profile'));await text('编辑资料','Edit profile').waitFor();}
    await type(page.getByRole('textbox',{disabled:false}).first(),'browser.profile@example.test');
    await click(button('书籍','Books'));
    await button('保存','Save').click();await page.waitForTimeout(250);
    if(route==='profile-edit-conflict'){
     const observed=text('服务器当前资料','Observed server profile');await bring(observed,1,true);await shot(route+'-observed');
     await click(button('保留本次并再次核对','Keep mine and recheck'));await shot(route+'-overwrite-confirmation');
     await click(button('再次核对并保存','Recheck and save'),true);
    }else if(route==='profile-edit-unknown'){
     const unknown=text('提交结果未知，请先读取核对。','The update result is unknown. Read to verify first.');await bring(unknown,1,true);await shot(route+'-pending');
     await click(button('只读核对提交结果','Verify the submission without writing'));
    }
    const verified=route==='profile-edit-unknown'?text('服务器资料已一致','Server profile matches'):text('资料保存已核对','Profile save verified');await bring(verified,1,true);await shot(route+'-verified');
    if(route==='profile'){
     await button('返回','Back').click();await page.waitForTimeout(250);const language=page.getByRole('button',{name:english?/^App language/:/^应用语言/});await click(language);
     await page.getByText(english?'中文':'English',{exact:true}).last().click();await page.waitForTimeout(300);
     await page.getByRole('button',{name:english?'编辑资料':'Edit profile',exact:true}).waitFor();await shot('profile-language-switched');
    }
    assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:/).count(),0);
   }
   assert.equal(api,0);assert.deepEqual(errors,[]);await page.close();console.log('PASS profile/editor '+(english?'English 320dp200%':'Chinese')+'; actual form state, eight-module picker, conflict and unknown receipt verification, language; isolated fixture. Root navigation/session has separate widget integration.');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
