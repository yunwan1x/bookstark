const assert=require('node:assert/strict'),fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const out=process.env.BOOKSTARK_COMMUNITY_VISUAL_OUT;assert.ok(out&&process.env.BOOKSTARK_BROWSER_PROFILE);
 fs.mkdirSync(out,{recursive:true});
 const browser=await chromium.launchPersistentContext(process.env.BOOKSTARK_BROWSER_PROFILE,{
  headless:true,executablePath:process.env.CHROMIUM_PATH,deviceScaleFactor:2,args:['--no-sandbox']});
 const report=[];
 async function session(s,kind,fault,action){
  const page=await browser.newPage();await page.setViewportSize({width:s.width,height:s.height});
  const errors=[];let api=0;const t=(zh,en)=>s.en?en:zh;
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(/RenderFlex overflowed|EXCEPTION CAUGHT|Bad state:/.test(m.text()))errors.push(m.text());});
  page.on('request',r=>{if(new URL(r.url()).pathname.includes('/api/'))api++;});
  const wheel=async n=>{await page.mouse.move(24,page.viewportSize().height*.6);await page.mouse.wheel(0,n);await page.waitForTimeout(140);};
  async function locate(target,reset=true){
   if(reset)await wheel(-10000);
   for(let i=0;i<100;i++){
    const b=await target.boundingBox({timeout:400}).catch(()=>null);
    if(b&&b.width>0&&b.height>0&&b.y+b.height/2>=45&&b.y+b.height/2<page.viewportSize().height-8)return b;
    await wheel(140);
   }
   throw Error('Cannot reach fixture control '+JSON.stringify({count:await target.count(),box:await target.boundingBox({timeout:400}).catch(()=>null),html:await target.evaluate(e=>e.outerHTML).catch(()=>null)}));
  }
  async function tap(zh,en,index=0){
   const name=t(zh,en).replace(/[.*+?^{}()|[\]\\]/g,'\\$&');
   const all=page.getByRole('button',{name:new RegExp('^'+name+'(?:\\s|$)')});
   const target=index<0?all.last():all.nth(index);
   const b=await locate(target);await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(350);
  }
  async function back(){
   await page.mouse.move(0,0);await page.getByRole('button',{name:t('返回','Back'),exact:true}).last().click();
   await page.waitForTimeout(350);
  }
  async function capture(screen,bottom=false){
   await wheel(bottom?10000:-10000);await page.waitForTimeout(250);await page.mouse.move(0,0);
   const name=s.name+'-'+kind+(fault?'-'+fault:'')+'-'+screen;
   const file=out+'/'+name+'.png';assert.ok(!fs.existsSync(file));await page.screenshot({path:file});
   report.push({layout:s.name,kind,fault:fault||null,screen});
  }
  async function field(index,text){
   const target=page.getByRole('textbox').nth(index);await locate(target);
   await target.fill(text);await page.waitForTimeout(200);
  }
  async function chooseFilter(currentZh,currentEn,nextZh,nextEn){
   const fieldLabel=currentZh==='全部状态'?t('评论状态','Comment status'):t('评论类型','Comment target type');
   const selected=fieldLabel+'\n'+t(currentZh,currentEn);
   const current=page.getByText(selected,{exact:true}).or(page.getByLabel(selected,{exact:true})).last();
   const b=await locate(current);await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(250);
   const next=page.getByText(t(nextZh,nextEn),{exact:true}).or(page.getByLabel(t(nextZh,nextEn),{exact:true})).last();
   await next.waitFor({timeout:4000});await next.click();await page.waitForTimeout(350);
  }
  try{
   const url=process.env.BOOKSTARK_VISUAL_URL+'/?kind='+kind+'&lang='+(s.en?'en':'zh')+'&scale='+s.scale+(fault?'&fault='+fault:'');
   await page.goto(url,{waitUntil:'networkidle',timeout:60000});
   const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
   await page.getByText(kind==='links'?'文档中心':'reader-lin',{exact:false}).or(page.getByLabel(kind==='links'?'文档中心':'reader-lin',{exact:false})).last().waitFor({timeout:15000});
   await action({page,t,wheel,locate,tap,back,capture,field,chooseFilter});
   assert.equal(api,0,'Synthetic fixture emitted real API network traffic');assert.deepEqual(errors,[]);
  }catch(error){
   const prefix=out+'/failure-'+s.name+'-'+kind+'-'+(fault||'normal');
   await page.screenshot({path:prefix+'.png'});
   fs.writeFileSync(prefix+'.json',JSON.stringify({errors,aria:await page.locator('body').ariaSnapshot(),semantics:await page.locator('flt-semantics').allTextContents()},null,2));
   throw error;
  }finally{await page.close();}
 }
 try{
  for(const s of [
   {name:'zh-390',width:390,height:844,scale:1,en:false},
   {name:'en-320',width:320,height:900,scale:1,en:true},
   {name:'zh-320-200',width:320,height:900,scale:2,en:false},
   {name:'en-320-200',width:320,height:900,scale:2,en:true},
  ]){
   await session(s,'links',null,async h=>{
    await h.capture('list');await h.capture('list-bottom',true);
    await h.tap('编辑','Edit',0);await h.capture('editor');await h.capture('editor-bottom',true);
    // This final editor action is visible after a real bottom scroll. Flutter Web
    // large-text semantics can retain its pre-scroll y, so verify a real pointer
    // at the visible last action and require the resulting owned dialog.
    await h.wheel(10000);await h.page.mouse.click(s.width/2,s.height-40);await h.page.waitForTimeout(350);
    await h.page.getByRole('button',{name:h.t('移除草稿','Remove draft'),exact:true}).waitFor();
    await h.capture('remove-confirmation');
    await h.page.getByRole('button',{name:h.t('取消','Cancel'),exact:true}).last().click();await h.page.waitForTimeout(200);
    await h.field(0,'文档中心改');
    await h.tap('应用到草稿','Apply to draft');
    await h.tap('保存全部','Save all');await h.capture('save-confirmation');
    await h.tap('返回核对','Return to review');await h.tap('保存全部','Save all');await h.tap('确认保存全部','Confirm save all');
    await h.capture('known-saved');
    await h.tap('编辑 联系示例','Edit 联系示例');await h.capture('qr-editor');await h.capture('qr-editor-bottom',true);await h.back();
   });
   await session(s,'comments',null,async h=>{
    await h.capture('list');await h.capture('list-bottom',true);
    await h.tap('下一页','Next');await h.capture('page2');await h.tap('上一页','Previous');
    const box=await h.locate(h.page.getByRole('checkbox',{name:/ID 24(?:\s|$)/}));await h.page.mouse.click(box.x+box.width/2,box.y+box.height/2);await h.page.waitForTimeout(250);
    await h.tap('永久删除','Delete permanently');await h.capture('delete-confirmation');await h.capture('delete-confirmation-bottom',true);
    await h.tap('取消','Cancel');await h.tap('永久删除','Delete permanently');await h.tap('确认永久删除','Confirm permanent deletion');
    await h.capture('known-deleted');
    await h.field(0,'reader-zhou');await h.tap('搜索评论','Search comments');await h.capture('searched');
    await h.chooseFilter('全部状态','All statuses','已删除','Deleted');await h.capture('status-filter');
    await h.chooseFilter('全部类型','All types','文档','Document');await h.capture('empty-filter');
   });
   console.log('PASS community visual '+s.name);
  }
  const s={name:'zh-390-fault',width:390,height:844,scale:1,en:false};
  for(const kind of ['links','comments']){
   for(const fault of ['unknown','known-read']){
    await session(s,kind,fault,async h=>{
     if(kind==='links'){
      await h.tap('编辑','Edit',0);await h.field(0,'故障示例草稿');await h.tap('应用到草稿','Apply to draft');
      await h.tap('保存全部','Save all');await h.tap('确认保存全部','Confirm save all');
     }else{
      const b=await h.locate(h.page.getByRole('checkbox',{name:/ID 24(?:\s|$)/}));await h.page.mouse.click(b.x+b.width/2,b.y+b.height/2);await h.page.waitForTimeout(250);
      await h.tap('永久删除','Delete permanently');await h.tap('确认永久删除','Confirm permanent deletion');
     }
     await h.capture('result');
     await h.tap(kind==='links'?'只读取当前配置':'只读取当前列表',kind==='links'?'Read current configuration only':'Read current list only');
     await h.capture('read-current');
     if(fault==='unknown'){
      if(kind==='links'){
       await h.tap('采用当前配置并结束核对','Adopt current configuration and finish review');await h.capture('adoption-confirmation');
       await h.page.getByRole('button',{name:'采用当前配置',exact:true}).last().click();await h.page.waitForTimeout(250);
      }else{await h.tap('已核对，结束本次核对','Finish this review');}
      await h.capture('review-ended');
     }
    });
   }
  }
  fs.writeFileSync(out+'/visual-proof.json',JSON.stringify({count:report.length,report,externalApiRequests:0},null,2));
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
