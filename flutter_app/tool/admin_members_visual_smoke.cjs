const assert=require('node:assert/strict'),fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const out=process.env.BOOKSTARK_MEMBERS_VISUAL_OUT;assert.ok(out&&process.env.BOOKSTARK_BROWSER_PROFILE);
 fs.mkdirSync(out,{recursive:true});
 const browser=await chromium.launchPersistentContext(process.env.BOOKSTARK_BROWSER_PROFILE,{headless:true,executablePath:process.env.CHROMIUM_PATH,deviceScaleFactor:2,args:['--no-sandbox']});
 const report=[];
 try{
 for(const s of [{name:'zh-390',width:390,scale:1,en:false},{name:'en-320',width:320,scale:1,en:true},{name:'zh-320-200',width:320,scale:2,en:false},{name:'en-320-200',width:320,scale:2,en:true}]){
 const page=await browser.newPage();await page.setViewportSize({width:s.width,height:900});
 const errors=[];let api=0;const t=(zh,en)=>s.en?en:zh;
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/RenderFlex overflowed|EXCEPTION CAUGHT|Bad state:/.test(m.text()))errors.push(m.text());});
 page.on('request',r=>{if(new URL(r.url()).pathname.includes('/api/'))api++;});
 const wheel=async n=>{await page.mouse.move(22,500);await page.mouse.wheel(0,n);await page.waitForTimeout(100);};
 async function tap(zh,en){
 const text=t(zh,en),target=page.getByRole('button',{name:new RegExp((text.startsWith('demo-')?'(?:^|\\s)':'^')+text.replace(/[.*+?^{}()|[\]\\]/g,'\\$&')+'(?:\\s|$)')}).last();
 await wheel(-10000);
 for(let i=0;i<80;i++){const b=await target.boundingBox({timeout:500}).catch(()=>null);if(b&&b.y>=55&&b.y+b.height<page.viewportSize().height-8){await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.waitForTimeout(350);return;}await wheel(160);}
 throw Error('Unreachable control: '+text);
 }
 async function back(){await page.mouse.move(0,0);await page.getByRole('button',{name:t('返回','Back'),exact:true}).last().click();await page.waitForTimeout(350);}
 async function capture(screen,bottom=false){await wheel(bottom?10000:-10000);await page.mouse.move(0,0);await page.waitForTimeout(200);const file=out+'/'+s.name+'-'+screen+'.png';assert.ok(!fs.existsSync(file));await page.screenshot({path:file});report.push({layout:s.name,screen});}
 try{
 await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?lang='+(s.en?'en':'zh')+'&scale='+s.scale,{waitUntil:'networkidle',timeout:60000});
 const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
 await page.getByRole('button',{name:/(?:^|\s)demo-admin(?:\s|$)/}).last().waitFor({timeout:15000});
 await capture('list');await capture('list-bottom',true);
 await tap('下一页','Next');await page.getByRole('button',{name:/(?:^|\s)demo-member-21(?:\s|$)/}).last().waitFor();await capture('list-page2');
 await tap('上一页','Previous');await tap('demo-member-2','demo-member-2');await capture('detail-pending');
 await tap('审批处理','Review approval');await capture('approval-options');
 await tap('审批通过','Approve');await capture('approval-confirmation');
 await page.getByRole('button',{name:t('取消','Cancel'),exact:true}).last().click();await page.waitForTimeout(200);
 await tap('修改角色','Change role');await capture('role');await back();await back();
 await tap('demo-admin','demo-admin');await tap('修改角色','Change role');await capture('own-role-disabled');
 assert.equal(await page.getByRole('button',{name:t('下一步','Next'),exact:true}).last().isDisabled(),true);
 await back();await back();await tap('demo-member-3','demo-member-3');await tap('重置密码','Reset password');
 await capture('password');await capture('password-bottom',true);
 assert.equal(api,0);assert.deepEqual(errors,[]);console.log('PASS members visual '+s.name);
 }catch(e){await page.screenshot({path:out+'/failure-'+s.name+'.png'});fs.writeFileSync(out+'/failure-'+s.name+'.json',JSON.stringify({errors,semantics:await page.locator('flt-semantics').allTextContents()},null,2));throw e;}finally{await page.close();}
 }
 fs.writeFileSync(out+'/visual-proof.json',JSON.stringify({count:report.length,report,networkApiRequests:0},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
