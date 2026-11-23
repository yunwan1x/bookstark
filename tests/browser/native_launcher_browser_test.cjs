const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});
 try {
  const context=await browser.newContext({locale:'en-US',permissions:['clipboard-read','clipboard-write'],viewport:{width:390,height:844}});
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(process.env.NATIVE_START_URL);
  assert.equal(await page.locator('html').getAttribute('lang'),'en');
  await page.getByRole('button',{name:'Create local workspace',exact:true}).waitFor();
  assert.equal(await page.locator('#password').getAttribute('autocomplete'),'new-password');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  const password='Chosen-Admin-2026!';
  await page.locator('#password').fill(password);await page.locator('#confirmPassword').fill('Not-The-Same!');
  await page.getByRole('button',{name:'Create local workspace',exact:true}).click();
  await page.getByRole('alert').filter({hasText:'The passwords do not match.'}).waitFor();
  assert.equal(await page.locator('#password').inputValue(),'');
  await page.locator('#password').fill(password);await page.locator('#confirmPassword').fill(password);
  await page.getByRole('button',{name:'Create local workspace',exact:true}).click();
  await page.locator('#copyPassword').waitFor();assert.equal(await page.locator('#passwordValue').textContent(),password);
  await page.locator('#copyPassword').click();await page.getByRole('status').filter({hasText:'Password copied'}).waitFor();
  assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),password);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  if(process.env.NATIVE_SCREENSHOT)await page.screenshot({path:process.env.NATIVE_SCREENSHOT});
  await page.evaluate(()=>{Object.defineProperty(navigator,'clipboard',{configurable:true,value:undefined});document.execCommand=()=>false;});
  await page.locator('#copyPassword').click();await page.getByRole('status').filter({hasText:'copy it manually'}).waitFor();
  await context.addCookies([{name:'lang',value:'zh',url:new URL(process.env.NATIVE_START_URL).origin}]);
  await page.goto(process.env.NATIVE_START_URL);await page.getByRole('button',{name:'打开本地工作区',exact:true}).waitFor();
  assert.equal(await page.locator('#password').count(),0);
  await page.getByRole('button',{name:'打开本地工作区',exact:true}).click();
  await page.getByRole('button',{name:'复制密码',exact:true}).waitFor();
  const origin=new URL(process.env.NATIVE_START_URL).origin;
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password}});
  assert.equal(login.status(),200);
  await page.goto(origin+'/profile?tab=api');
  const address=page.locator('#bookmark-extension-url');
  await address.waitFor({state:'visible'});assert.equal(await address.inputValue(),origin);
  assert.equal(await address.getAttribute('readonly'),'');
  await page.getByRole('button',{name:'复制',exact:true}).click();
  assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),origin);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.evaluate(()=>{window.BookStarkCopyText=async()=>{throw new Error('denied')};});
  await page.getByRole('button',{name:'复制',exact:true}).click();
  await page.getByText('复制失败，请选中地址手动复制。',{exact:true}).waitFor();
  await context.addCookies([{name:'lang',value:'en',url:origin}]);
  await page.setViewportSize({width:1280,height:850});await page.reload();
  assert.equal(await address.inputValue(),origin);
  await page.getByText('Browser extension server address (Base URL)',{exact:true}).waitFor();
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
  assert.deepEqual(errors,[]);console.log('PASS: en/zh setup, mismatch, custom password, real clipboard copy, fallback feedback, existing workspace, mobile layout, plugin Base URL, copy and failure feedback');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
