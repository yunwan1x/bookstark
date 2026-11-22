const assert=require('node:assert/strict'),fs=require('node:fs');
const {chromium,request}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const out=process.env.BOOKSTARK_ASSETS_VISUAL_OUT;assert.ok(out&&process.env.BOOKSTARK_BROWSER_PROFILE);
 fs.mkdirSync(out,{recursive:true});
 const fontProxy=await request.newContext({proxy:{server:'http://192.168.200.3:7890'}});
 const browser=await chromium.launchPersistentContext(process.env.BOOKSTARK_BROWSER_PROFILE,{
  headless:true,executablePath:process.env.CHROMIUM_PATH,deviceScaleFactor:2,args:['--no-sandbox']});
 const report=[];
 async function session(s,kind,params,action){
  if(process.env.BOOKSTARK_ASSETS_CASES&&!process.env.BOOKSTARK_ASSETS_CASES.split(',').includes(kind))return;
  const page=await browser.newPage();await page.setViewportSize({width:s.width,height:s.height});
  await page.route('https://fonts.gstatic.com/**',async route=>{
   const response=await fontProxy.get(route.request().url(),{timeout:45000});
   assert.equal(response.status(),200,'Owned font proxy failed');
   await route.fulfill({response});
  });
  const errors=[],fontResponses=[];let api=0;const t=(zh,en)=>s.en?en:zh;
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',r=>{if(r.url().includes('fonts.gstatic.com'))fontResponses.push({status:r.status(),url:r.url()});});
  page.on('console',m=>{if(/RenderFlex overflowed|EXCEPTION CAUGHT|Bad state:/.test(m.text()))errors.push(m.text());});
  page.on('request',r=>{if(new URL(r.url()).pathname.includes('/api/'))api++;});
  const wheel=async n=>{await page.mouse.move(24,page.viewportSize().height*.6);await page.mouse.wheel(0,n);await page.waitForTimeout(120);};
  async function locate(target,reset=true,toolbar=false,footer=false){
   if(reset)await wheel(-10000);
   for(let i=0;i<80;i++){
    const b=await target.boundingBox({timeout:350}).catch(()=>null);
    let bottom=page.viewportSize().height-12;
    if(!toolbar&&!footer&&s.scale<1.5&&await page.getByRole('heading',{name:t('资产管理','Asset management'),exact:true}).count()){
     const fixed=page.getByRole('button',{name:new RegExp('^('+t('新增主机','Add host')+'|'+t('新增凭据','Add credential')+')$')});
     const f=await fixed.last().boundingBox({timeout:350}).catch(()=>null);
     if(f)bottom=Math.min(bottom,f.y-16);
    }
    if(b&&b.width>0&&b.height>0&&b.y+b.height/2>=(toolbar?0:48)&&b.y+b.height/2<bottom){
     await page.waitForTimeout(300);
     const settled=await target.boundingBox({timeout:350}).catch(()=>null);
     if(settled&&Math.abs(settled.y-b.y)<1&&Math.abs(settled.height-b.height)<1)return settled;
    }
    await wheel(140);
   }
   throw Error('Cannot reach fixture control '+JSON.stringify({count:await target.count(),html:await target.evaluate(e=>e.outerHTML).catch(()=>null)}));
  }
  async function target(zh,en,index=0){
   const name=t(zh,en),button=page.getByRole('button',{name,exact:true});
   return (await button.count()?button:page.getByText(name,{exact:true}).or(page.getByLabel(name,{exact:true}))).nth(index);
  }
  async function tap(zh,en,index=0){
   const control=await target(zh,en,index),b=await locate(control,true,zh==="资产设置",zh==="新增主机"||zh==="新增凭据");
   await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(300);
  }
  async function viewHost(name){
   const control=page.getByRole('button',{name:new RegExp('^'+t('查看主机','View host')+' '+name+' ID [0-9]+$')});
   const b=await locate(control);await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(300);
   await page.getByRole('heading',{name:t('SSH 主机详情','SSH host details'),exact:true}).waitFor({timeout:5000});
  }
  async function back(){
   await page.getByRole('button',{name:t('返回','Back'),exact:true}).last().click();
   await page.waitForTimeout(300);
  }
  async function capture(screen,bottom=false){
   await wheel(bottom?10000:-10000);await page.waitForTimeout(220);await page.waitForLoadState('networkidle',{timeout:45000});await page.waitForTimeout(350);await page.mouse.move(0,0);
   const name=s.name+'-'+kind+'-'+screen,file=out+'/'+name+'.png';
   assert.ok(!fs.existsSync(file));await page.screenshot({path:file});
   report.push({layout:s.name,kind,screen,fontResponses:fontResponses.map(x=>({...x}))});
  }
  async function field(index,text){
   const settingsLabels=[t('空闲超时（秒）','Idle timeout (seconds)'),t('回滚行数','Scrollback lines'),t('新密钥','New key'),t('确认新密钥','Confirm new key')];
   const control=kind==='settings'||kind==='settings-legacy'||kind==='unknown-settings'
    ?page.getByRole('textbox',{name:settingsLabels[index],exact:true}):page.getByRole('textbox').nth(index);
   const b=await locate(control);
   await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(150);
   const active=await page.evaluate(()=>({tag:document.activeElement?.tagName,role:document.activeElement?.getAttribute('role'),class:document.activeElement?.className,parent:document.activeElement?.parentElement?.tagName}));
   assert.ok(['INPUT','TEXTAREA'].includes(active.tag),'Real pointer did not focus a text input');
   await page.keyboard.press('ControlOrMeta+A');await page.keyboard.insertText(text);await page.waitForTimeout(200);
   const applied=await page.evaluate(expected=>document.activeElement?.value===expected,text);
   fs.appendFileSync(out+'/input-probes.jsonl',JSON.stringify({layout:s.name,kind,index,active,realKeyboardInput:true,applied})+'\n');
   assert.ok(applied,'Actual focused input did not accept synthetic keyboard input');
   // Remove editing focus before the next scroll. Otherwise browser semantics
   // keeps bringing an offscreen password field into view during pointer targeting.
   await page.mouse.click(s.width/2,28);await page.waitForTimeout(250);

  }
  async function choose(currentZh,currentEn,nextZh,nextEn){
   const suffix=t(currentZh,currentEn).replace(/[.*+?^{}()|[\]\\]/g,'\\$&');
   const prefix=currentZh==='保持原凭据'?t('更新方式','Update mode'):t('认证方式','Authentication');
   const current=page.getByRole('button',{name:new RegExp('^'+prefix+'\\s+'+suffix+'$')}).last();
   const b=await locate(current);
   fs.appendFileSync(out+'/dropdown-probes.jsonl',JSON.stringify({layout:s.name,kind,label:t(currentZh,currentEn),box:b,html:await current.evaluate(e=>e.outerHTML)})+'\n');
   await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(200);
   const next=page.getByText(t(nextZh,nextEn),{exact:true}).or(page.getByLabel(t(nextZh,nextEn),{exact:true})).last();
   await next.waitFor({timeout:5000});await next.click();await page.waitForTimeout(250);
  }
  try{
   const query=new URLSearchParams({lang:s.en?'en':'zh',scale:String(s.scale),...params});
   await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?'+query,{waitUntil:'networkidle',timeout:60000});
   const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
   const initial=params.role==='1'?t('管理员会话已失效，请返回重新登录。','The administrator session is no longer valid. Return and sign in again.')
    :params.fault==='read'?t('读取失败，请重试。当前数量未知。','Read failed. Try again. The current count is unknown.')
    :params.fault==='empty'?t('没有符合条件的记录。','No matching records.'):'开发机 A';
   await page.getByText(initial,{exact:false}).or(page.getByLabel(initial,{exact:false})).last().waitFor({timeout:15000});
   await page.waitForLoadState('networkidle',{timeout:45000});
   await page.waitForTimeout(1200);
   await action({page,t,wheel,locate,tap,back,capture,field,choose,target,viewHost});
   assert.equal(api,0,'Synthetic fixture emitted real API traffic');assert.deepEqual(errors,[]);
  }catch(error){
   const prefix=out+'/failure-'+s.name+'-'+kind;
   await page.screenshot({path:prefix+'.png'});
   fs.writeFileSync(prefix+'.json',JSON.stringify({errors,aria:await page.locator('body').ariaSnapshot(),semantics:await page.locator('flt-semantics').allTextContents()},null,2));throw error;
  }finally{await page.close();}
 }
 try{
  let layouts=[
   {name:'zh-390',width:390,height:844,scale:1,en:false},
   {name:'en-320',width:320,height:900,scale:1,en:true},
   {name:'zh-320-200',width:320,height:900,scale:2,en:false},
   {name:'en-320-200',width:320,height:900,scale:2,en:true},
  ];
  if(process.env.BOOKSTARK_ASSETS_LAYOUTS)layouts=layouts.filter(s=>process.env.BOOKSTARK_ASSETS_LAYOUTS.split(',').includes(s.name));
  for(const s of layouts){
   await session(s,'hosts',{},async h=>{
    await h.capture('list');await h.capture('list-bottom',true);
    await h.tap('新增主机','Add host');await h.capture('new-host');await h.capture('new-host-bottom',true);
    await h.field(0,'preview-host');await h.field(1,'new.example.invalid');
    const selector=h.page.getByRole('button',{name:new RegExp('^'+h.t('使用已有凭据','Use existing credential'))});
    const selectorBox=await h.locate(selector);await h.page.mouse.click(selectorBox.x+selectorBox.width/2,selectorBox.y+selectorBox.height/2);
    await h.page.waitForTimeout(250);
    const choice=h.t('演示私钥 #2 · 私钥','演示私钥 #2 · Private key');
    const option=h.page.getByRole('menuitem',{name:choice,exact:true}).or(h.page.getByLabel(choice,{exact:true})).last();
    await option.waitFor();await option.click();await h.page.waitForTimeout(250);
    await h.capture('new-host-credential-selected',true);
    await h.tap('保存主机','Save host');await h.capture('new-host-saved');
    await h.viewHost('开发机 A');await h.capture('detail');await h.capture('detail-bottom',true);
    await h.tap('检测连接','Test connection');await h.capture('test-receipt');await h.capture('test-receipt-bottom',true);
    await h.tap('刷新保存状态','Refresh stored status');await h.tap('编辑主机','Edit host');
    await h.capture('editor');await h.capture('editor-bottom',true);
    await h.tap('高级设置 · 工作目录与 Docker Socket','Advanced · Working directory and Docker Socket');
    await h.capture('editor-advanced',true);await h.back();
    await h.tap('删除主机','Delete host');await h.capture('delete');await h.capture('delete-bottom',true);
    await h.tap('取消','Cancel');await h.back();
   });
   await session(s,'credentials',{},async h=>{
    await h.tap('凭据','Credentials');await h.capture('list');await h.capture('list-bottom',true);
    await h.tap('编辑凭据','Edit credential',0);await h.capture('editor-keep');await h.capture('editor-keep-bottom',true);
    await h.choose('保持原凭据','Keep current credential','替换凭据','Replace credential');
    await h.field(2,'synthetic preview replacement');await h.capture('editor-replace',true);
    await h.tap('保存凭据','Save credential');await h.capture('saved');
    await h.tap('凭据操作','Credential actions',0);await h.tap('查看凭据','View credential');
    await h.capture('view-hidden');await h.capture('view-hidden-bottom',true);
    await h.tap('显示秘密','Show secret');await h.capture('view-synthetic-secret',true);
    await h.tap('隐藏秘密','Hide secret');await h.back();
    await h.tap('凭据操作','Credential actions',0);await h.tap('删除凭据','Delete credential');
    await h.capture('delete');await h.capture('delete-bottom',true);await h.tap('取消','Cancel');
    await h.tap('新增凭据','Add credential');await h.capture('new');await h.capture('new-bottom',true);
    await h.field(0,'演示新私钥');await h.field(1,'preview-user');
    await h.choose('密码','Password','SSH 私钥','SSH private key');
    await h.tap('编辑私钥','Edit private key');await h.capture('key-input');await h.capture('key-input-bottom',true);
    await h.field(0,'synthetic preview first line\nsynthetic second line\n');
    await h.tap('使用此私钥','Use this private key');await h.capture('key-summary',true);
    await h.tap('保存凭据','Save credential');await h.capture('created');
   });
   await session(s,'settings',{},async h=>{
    await h.tap('资产设置','Asset settings');await h.capture('policy');await h.capture('policy-bottom',true);
    await h.field(0,'2400');await h.field(1,'7000');await h.tap('保存设置','Save settings');await h.capture('policy-saved');
    await h.tap('资产设置','Asset settings');await h.tap('更换密钥','Replace key');
    await h.field(2,'synthetic new preview key');await h.field(3,'synthetic new preview key');
    await h.capture('replace');await h.capture('replace-bottom',true);
    await h.tap('保存设置','Save settings');
    await h.page.getByRole('heading',{name:h.t('确认更换密钥','Confirm key replacement'),exact:true}).waitFor({timeout:5000});
    await h.capture('replace-confirmation');await h.capture('replace-confirmation-bottom',true);
    await h.tap('返回核对','Return to review');await h.capture('returned-to-review',true);
    await h.tap('保存设置','Save settings');
    await h.page.getByRole('heading',{name:h.t('确认更换密钥','Confirm key replacement'),exact:true}).waitFor({timeout:5000});
    await h.capture('second-confirmation',true);await h.tap('确认保存','Confirm save');
    await h.capture('replace-saved');
    await h.tap('资产设置','Asset settings');await h.tap('关闭加密','Disable encryption');await h.tap('保存设置','Save settings');
    await h.capture('disable-confirmation');await h.tap('取消','Cancel');await h.back();
   });
   await session(s,'migration',{legacy:'1'},async h=>{
    await h.viewHost('旧式开发主机');await h.capture('legacy-detail');await h.capture('legacy-detail-bottom',true);
    await h.tap('迁移为独立凭据','Migrate to independent credential');await h.capture('confirmation');await h.capture('confirmation-bottom',true);
    await h.tap('确认迁移','Confirm migration');await h.capture('created');await h.capture('created-bottom',true);
    await h.tap('核对并绑定本主机','Review and bind this host');
    await h.page.getByRole('heading',{name:h.t('资产管理','Asset management'),exact:true}).waitFor({timeout:5000});
    await h.capture('bound');
   });
  }
  const s=layouts[0];
  if(s){
   for(const fault of ['read','empty'])await session(s,fault,{fault},async h=>{
    await h.capture('initial');if(fault==='read'){await h.tap('刷新资料','Refresh data');await h.capture('retried');}
   });
   await session(s,'permission',{role:'1'},async h=>{await h.capture('denied');});
   await session(s,'unknown-create',{fault:'unknown-create'},async h=>{
    await h.tap('凭据','Credentials');await h.tap('新增凭据','Add credential');
    await h.field(0,'演示未知创建');await h.field(1,'preview-user');await h.field(2,'synthetic preview password');
    await h.tap('保存凭据','Save credential');await h.capture('unknown');await h.tap('刷新资料','Refresh data');
    await h.capture('current');await h.tap('结束本次核对','Finish this review');await h.capture('review-ended');
   });
   for(const fault of ['unknown-bind','legacy-changed'])await session(s,fault,{fault,legacy:'1'},async h=>{
    await h.viewHost('旧式开发主机');await h.tap('迁移为独立凭据','Migrate to independent credential');
    await h.tap('确认迁移','Confirm migration');await h.tap('核对并绑定本主机','Review and bind this host');
    await h.capture('partial');await h.capture('partial-bottom',true);
    await h.tap('读取当前资料','Read current data');await h.capture('current',true);
    await h.tap('结束迁移核对','Finish migration review');await h.capture('review-ended');
   });
   await session(s,'settings-legacy',{legacy:'1'},async h=>{
    await h.tap('资产设置','Asset settings');await h.tap('更换密钥','Replace key');
    await h.field(2,'synthetic new preview key');await h.field(3,'synthetic new preview key');
    await h.tap('保存设置','Save settings');await h.tap('确认保存','Confirm save');
    await h.capture('rotation-blocked');await h.capture('rotation-blocked-bottom',true);
   });
   await session(s,'known-read',{fault:'known-read'},async h=>{
    await h.tap('凭据','Credentials');await h.tap('编辑凭据','Edit credential',0);
    await h.field(0,'演示已确认凭据');await h.tap('保存凭据','Save credential');
    await h.capture('ack-read-failed');await h.tap('刷新资料','Refresh data');await h.capture('current');
   });
   await session(s,'unknown-settings',{fault:'unknown'},async h=>{
    await h.tap('资产设置','Asset settings');await h.field(0,'2401');await h.tap('保存设置','Save settings');
    await h.capture('unknown',true);await h.back();await h.tap('资产设置','Asset settings');
    await h.capture('current');await h.capture('current-bottom',true);
    await h.tap('结束本次核对','Finish this review');await h.capture('review-ended');
   });
  }
  fs.writeFileSync(out+'/report.json',JSON.stringify({passed:true,views:report.length,scenarios:report,externalApiRequests:0,syntheticWindowGuard:true,nativeSecurityProven:false,semanticsViewportRefresh:false},null,2));
  process.stdout.write('PASS '+report.length+' asset browser views; synthetic UI only\n');
 }finally{await browser.close();await fontProxy.dispose();}
})().catch(error=>{console.error(error);process.exit(1);});
