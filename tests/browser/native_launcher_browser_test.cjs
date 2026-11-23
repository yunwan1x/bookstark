const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});
 try {
  const context=await browser.newContext({locale:'en-US',permissions:['clipboard-read','clipboard-write'],viewport:{width:390,height:844}});
  // Exercise the native client API against the real isolated launcher and vault.
  // This only substitutes the WebView message transport, not saved data or auth.
  await context.addInitScript(()=>{
   const copy=navigator.clipboard?.writeText.bind(navigator.clipboard);
   window.BookStarkNative={request(payload){
    const {id,action,args}=JSON.parse(payload);
    (async()=>{
     try{
      let result;
      if(action==='client'){
       const response=await fetch('/__bookstark/client',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(args)});
       if(!response.ok)throw new Error('client request '+response.status+' '+await response.text());result=await response.json();
      }else if(action==='clipboard-write'){await copy(args.text);result=true;}
      else throw new Error('Unsupported action '+action);
      window.BookStarkHostReply(id,result,null);
     }catch(error){window.BookStarkHostReply(id,null,error.message);}
    })();
   }};
  });
  await context.addCookies([{name:'lang',value:'en',url:new URL(process.env.NATIVE_START_URL).origin}]);
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  const origin=new URL(process.env.NATIVE_START_URL).origin;
  await page.goto(process.env.NATIVE_START_URL);
  assert.equal(await page.locator('html').getAttribute('lang'),'en');
  assert.equal(await page.locator('#password').count(),0);
  assert.equal(await page.locator('#remember-workspace').isChecked(),true);
  await page.getByRole('button',{name:'Local workspace',exact:false}).click();
  await page.locator('#copyPassword').waitFor();
  assert.equal(await page.locator('#passwordValue').textContent(),'wy19870714');
  await page.locator('#copyPassword').click();await page.getByRole('status').filter({hasText:'Password copied'}).waitFor();
  assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'wy19870714');
  await page.getByRole('link',{name:'Open sign-in page',exact:true}).click();
  await page.waitForFunction(()=>document.getElementById('password')?.value==='wy19870714');
  assert.equal(await page.locator('#account').inputValue(),'admin');
  assert.equal(await page.locator('#client-remember-password').isChecked(),true);
  await page.locator('button[onclick="doLogin()"]').click();
  await page.waitForURL(url=>url.pathname!='/login');
  await page.goto(origin+'/profile?tab=workspace');
  await page.locator('#panel-workspace').waitFor({state:'visible'});
  assert.equal(await page.locator('input[name="client-startup"][value="continue"]').isChecked(),true);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.locator('input[value="ask"]').check();await page.locator('#client-save-workspace').click();
  await page.waitForFunction(()=>document.getElementById('client-workspace-status').textContent);
  assert.equal(await page.locator('#client-workspace-status').textContent(),'Saved. Applies at next startup.');
  await page.goto(process.env.NATIVE_START_URL);
  await page.locator('#remember-workspace').waitFor();assert.equal(await page.locator('#remember-workspace').isChecked(),false);
  await page.locator('#remember-workspace').check();
  await page.getByRole('button',{name:'Local workspace',exact:false}).click();
  await page.waitForURL(url=>!url.pathname.startsWith('/__bookstark/'));
  await page.goto(process.env.NATIVE_START_URL);
  await page.waitForURL(url=>!url.pathname.startsWith('/__bookstark/'));
  // Discard the login cookie to confirm stored credentials refill the login form.
  await context.clearCookies({name:'token'});await page.goto(origin+'/login');
  await page.waitForFunction(()=>document.getElementById('password')?.value==='wy19870714');
  assert.equal(await page.locator('#account').inputValue(),'admin');
  await page.locator('button[onclick="doLogin()"]').click();await page.waitForURL(url=>url.pathname!='/login');
  await context.addCookies([{name:'lang',value:'zh',url:origin}]);
  await page.goto(origin+'/profile?tab=workspace');await page.locator('#panel-workspace').waitFor({state:'visible'});
  await page.getByText('启动方式',{exact:true}).waitFor();
  await page.locator('#client-forget-credentials').click();
  await page.getByText('已清除记住的账号密码，当前登录不受影响。',{exact:true}).waitFor();
  await context.clearCookies({name:'token'});await page.goto(origin+'/login');
  await page.waitForFunction(()=>!document.getElementById('remember-client-credentials').hidden);
  assert.equal(await page.locator('#password').inputValue(),'');assert.equal(await page.locator('#account').inputValue(),'');
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:'wy19870714'}});assert.equal(login.status(),200);
  await page.goto(origin+'/profile?tab=api');
  const address=page.locator('#bookmark-extension-url');
  await address.waitFor({state:'visible'});assert.equal(await address.inputValue(),origin);
  await page.getByRole('button',{name:'复制',exact:true}).click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),origin);
  await page.evaluate(()=>{window.BookStarkCopyText=async()=>{throw new Error('denied')};});
  await page.getByRole('button',{name:'复制',exact:true}).click();await page.getByText('复制失败，请选中地址手动复制。',{exact:true}).waitFor();
  await page.setViewportSize({width:1280,height:900});
  await page.evaluate(()=>BookStarkTheme.set('hud-light'));
  assert.equal(await page.evaluate(()=>getComputedStyle(document.querySelector('body>header'),'::after').content),'none');
  if(process.env.NATIVE_SCREENSHOT){await page.goto(origin+'/profile?tab=workspace');await page.locator('#panel-workspace').waitFor({state:'visible'});await page.screenshot({path:process.env.NATIVE_SCREENSHOT});}
  // Optional upstream extension smoke test, using a real extension origin and
  // its configuration UI in a separate profile without any workspace cookies.
  if(process.env.BOOKSTARK_TEST_EXTENSION) {
   const token=await page.evaluate(async()=>{
    const r=await csrfFetch('/api/api-tokens',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'upstream extension smoke'})});
    if(!r.ok)throw new Error('create API token failed');
    return (await r.json()).data.token;
   });
   const extensionPath=process.env.BOOKSTARK_TEST_EXTENSION;
   const extContext=await chromium.launchPersistentContext('',{channel:'chromium',headless:true,args:['--no-sandbox','--disable-extensions-except='+extensionPath,'--load-extension='+extensionPath]});
   try {
    const worker=extContext.serviceWorkers()[0]||await extContext.waitForEvent('serviceworker');
    const extensionOrigin='chrome-extension://'+new URL(worker.url()).host;
    const options=await extContext.newPage();
    await options.goto(extensionOrigin+'/options/index.html');
    await options.locator('#input-base-url').fill(origin);await options.locator('#input-token').fill(token);
    await options.getByRole('button',{name:'Save',exact:true}).click();
    await options.getByText('Connection successful',{exact:true}).waitFor();
    const result=await options.evaluate(async({origin,token})=>{
     const headers={Authorization:'Token '+token,'Content-Type':'application/json'};
     const created=await fetch(origin+'/api/bookmarks/',{method:'POST',headers,body:JSON.stringify({url:'https://example.org/real-native-plugin',title:'Real extension save',unread:true})});
     if(created.status!==201)throw new Error('save status '+created.status);
     const bookmark=await created.json();
     const found=await fetch(origin+'/api/bookmarks/?q=Real%20extension%20save',{headers});
     const list=await found.json();
     const deleted=await fetch(origin+'/api/bookmarks/'+bookmark.id+'/',{method:'DELETE',headers});
     return {count:list.count,deleted:deleted.status};
    },{origin,token});
    assert.equal(result.count,1);assert.equal(result.deleted,204);
    assert.equal((await extContext.cookies(origin)).some(c=>c.name==='bookstark_native'),false);
    console.log('PASS: real Linkding extension connection, save, search, delete without native cookies');
   }finally{await extContext.close()}
  }
  assert.deepEqual(errors,[]);
  console.log('PASS: default password, first launch, saved startup setting, auto resume, credential autofill and forget, en/zh settings, mobile layout, plugin URL copy, HUD header label removed');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
