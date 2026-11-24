const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
(async()=>{
 const origin=process.env.BOOKSTARK_TEST_ORIGIN||'http://127.0.0.1:18280',out=process.env.BOOKSTARK_SCREENSHOT_DIR;
 assert.ok(out,'Set BOOKSTARK_SCREENSHOT_DIR containing browser-tool-1.0.0.zip fixtures');
 const browser=await chromium.launch({args:['--no-sandbox']}),context=await browser.newContext({viewport:{width:1440,height:1050}}),page=await context.newPage();
 await context.addCookies([{name:'lang',value:'zh',url:origin}]);await context.addInitScript(()=>{if(window===top&&navigator.serviceWorker)navigator.serviceWorker.register=()=>new Promise(()=>{})});
 const errors=[];page.on('pageerror',error=>{errors.push(error.message);console.log('PAGEERROR',error.stack)});page.on('requestfailed',r=>console.log('REQUEST_FAILED',r.url(),r.failure()?.errorText));page.on('console',msg=>{if(msg.type()==='error')console.log('console',msg.text())});
 async function api(url,method='GET',data){const csrf=(await(await context.request.get(origin+'/api/csrf-token')).json()).csrf_token;const r=await context.request.fetch(origin+url,{method,data,headers:{'X-CSRF-Token':csrf}});assert.ok(r.ok(),url+' '+await r.text());return r.json()}
 const shot=name=>page.screenshot({path:path.join(out,name+'.png'),fullPage:true});
 try{
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD||'admin'}});assert.equal(login.status(),200,await login.text());
  await page.route('**/static/js/tool-package-upload.js*',async route=>{await new Promise(resolve=>setTimeout(resolve,1000));await route.continue()});await page.goto(origin+'/market/publish?source=package');await page.locator('#publishPackagePanel').waitFor();assert.equal(new URL(page.url()).searchParams.get('source'),'package','article fetch cannot clear package source before upload script loads');await page.unroute('**/static/js/tool-package-upload.js*');await shot('01-upload-empty');
  await page.locator('#publishPackageFile').setInputFiles(path.join(out,'invalid-path.zip'));await page.locator('#publishPackageStatus.market-error').waitFor();assert.match(await page.locator('#publishPackageStatus').textContent(),/路径/);assert.ok(await page.locator('#publishPackageNext').isDisabled());await shot('02-upload-error');
  await page.locator('#publishPackageFile').setInputFiles(path.join(out,'browser-tool-1.0.0.zip'));await page.locator('#publishPackageCheck').waitFor();assert.equal(await page.locator('#publishPackageFiles li').count(),10);assert.match(await page.locator('#publishPackageSummary').textContent(),/解压后/);await shot('03-package-checked');
  await page.locator('#publishPackageNext').click();await page.waitForURL('**/market/packages/**');await page.locator('#toolPublishFields').waitFor({state:'visible'});assert.equal(await page.locator('#publishTitle').inputValue(),'WASM Worker 验证工具');assert.equal(await page.locator('#publishVersion').inputValue(),'1.0.0');assert.equal(await page.locator('#publishNetwork').count(),0);assert.equal(await page.locator('[data-tool-permission]').count(),3);await shot('04-publish-settings');
  const id=Number(await page.locator('#toolPublishPage').getAttribute('data-tool-id'));
  await page.locator('#toolPublishDraft').click();assert.match(await page.locator('#publishStatus').textContent(),/草稿/);
  await page.locator('#toolPublishPreview').click();await page.locator('dialog[open]').waitFor();assert.match(await page.locator('dialog').textContent(),/10/);await page.keyboard.press('Escape');
  await page.locator('#toolPublishForm [type=submit]').click();await page.locator('#publishStatus.market-success').waitFor();
  const tool=await api('/api/tool-market/'+id);assert.equal(tool.distribution,'files');assert.equal(tool.files.length,10);
  await api('/api/tool-installs/'+id,'PUT',{revision:tool.revision,hash:tool.hash});
  await page.goto(origin+'/tools/run/'+id);const frame=page.frameLocator('#marketFrameHost iframe');await frame.locator('body[data-ready=yes]').waitFor({timeout:20000});const result=JSON.parse(await frame.locator('#result').textContent());assert.deepEqual(result,{answer:42,label:'module-worker',blocked:true,data:true,version:'1.0.0'});await shot('05-installed-wasm-worker');
  const sandboxOrigin=await frame.locator('body').evaluate(()=>location.origin);assert.notEqual(sandboxOrigin,origin);const sw=await frame.locator('body').evaluate(async()=>{try{await navigator.serviceWorker.register('/sw.js');return 'registered'}catch(error){return 'blocked'}});assert.equal(sw,'blocked','tool service worker cannot persist across versions');
  assert.equal(await frame.locator('body').evaluate(async()=>{localStorage.setItem('persist','kept');await BookStark.files.write('saved.txt','kept');return await BookStark.files.exists('saved.txt')}),true);
  await page.goto(origin+'/market/publish?source=package&tool='+id);await page.locator('#publishPackageFile').setInputFiles(path.join(out,'browser-tool-1.0.1.zip'));await page.locator('#publishPackageCheck').waitFor();await page.locator('#publishPackageNext').click();await page.waitForURL('**/market/packages/**');await page.locator('#publishVersion').fill('1.0.1');await page.locator('#toolPublishForm [type=submit]').click();await page.locator('#publishStatus.market-success').waitFor();
  const latest=await api('/api/tool-market/'+id),old=await api('/api/tool-installs/'+id);await api('/api/tool-installs/'+id,'PUT',{revision:latest.revision,hash:latest.hash,expected:old.revision,instance:old.instance});
  await page.goto(origin+'/tools/run/'+id);await frame.locator('body[data-ready=yes]').waitFor({timeout:20000});assert.equal(JSON.parse(await frame.locator('#result').textContent()).version,'1.0.1');assert.equal(await frame.locator('body').evaluate(()=>localStorage.getItem('persist')),'kept');assert.equal(await frame.locator('body').evaluate(async()=>new TextDecoder().decode(await BookStark.files.read('saved.txt'))),'kept');
  const current=await api('/api/tool-installs/'+id);assert.equal(current.instance,old.instance);
  if(sandboxOrigin!=='null'){const sameOrigin=await context.request.get(sandboxOrigin+'/api/profile');assert.equal(sameOrigin.status(),404,'sandbox never serves app API');}
  const article=await api('/api/blogs','POST',{blog_title:'Article return identity',blog_desc:'Source and tool IDs differ',blog_type:'article',editor_type:'html',blog_content:'<h1>Source article</h1>'});
  await page.goto(origin+'/market/publish/'+article.data.blog_id);await page.locator('#toolPublishForm:not([aria-busy])').waitFor();assert.notEqual(Number(await page.locator('#toolPublishPage').getAttribute('data-tool-id')),article.data.blog_id,'ZIP identities exercise the article/tool ID collision');await page.locator('#toolPublishBack').click();await page.locator('#publishSourceNext:not([disabled])').waitFor();assert.equal(new URL(page.url()).searchParams.get('selected'),String(article.data.blog_id),'return restores source article, not independent tool ID');
  for(const [width,lang,name]of [[390,'zh','06-mobile-upload'],[320,'en','07-mobile-english']]){
   await page.setViewportSize({width,height:844});await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.goto(origin+'/market/publish?source=package');await page.locator('#publishPackagePanel').waitFor();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false);await shot(name);
  }
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(out,'browser-result-'+new URL(origin).hostname+'.json'),JSON.stringify({origin,id,sandboxOrigin,result,upgrade:true,mobile:true,errors},null,2));console.log('PACKAGE BROWSER PASSED',id,sandboxOrigin);
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
