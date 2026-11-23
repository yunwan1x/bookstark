const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({serviceWorkers:'block'}),page=await context.newPage(),errors=[],logins=[];
 const origin=process.env.BOOKSTARK_TEST_ORIGIN,password=process.env.BOOKSTARK_TEST_PASSWORD;
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(r.url()===origin+'/api/login'&&r.method()==='POST')logins.push(r.postDataJSON());});
 try{
  for(const lang of ['zh','en'])for(const width of [320,390,1440]){
   await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.setViewportSize({width,height:844});await page.goto(origin+'/login?next=%2Fshares');
   const field=page.locator('#password'),toggle=page.locator('#passwordToggle');
   assert.equal(await field.getAttribute('type'),'password');assert.equal(await field.getAttribute('autocomplete'),'current-password');
   assert.equal(await toggle.getAttribute('aria-label'),lang==='zh'?'显示密码':'Show password');
   await field.fill(password);await toggle.click();assert.equal(await field.getAttribute('type'),'text');assert.equal(await field.inputValue(),password);
   assert.equal(await toggle.getAttribute('aria-label'),lang==='zh'?'隐藏密码':'Hide password');assert.equal(await toggle.getAttribute('aria-pressed'),'true');
   await toggle.press('Space');assert.equal(await field.getAttribute('type'),'password');assert.equal(await field.inputValue(),password);
   assert.equal(await toggle.getAttribute('aria-pressed'),'false');assert.equal(logins.length,0,'visibility toggle must not submit login');
   const bounds=await toggle.boundingBox();assert(bounds.x>=0&&bounds.x+bounds.width<=width);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  }
  await page.locator('#account').fill('admin');await page.locator('#passwordToggle').click();await page.locator('#password').press('Enter');await page.waitForURL(url=>url.pathname==='/shares');
  assert.equal(logins.length,1);assert.deepEqual(logins[0],{account:'admin',password});assert.deepEqual(errors,[]);
  console.log('PASS login password visibility, keyboard toggle, preserved password/autocomplete, no accidental submit, Chinese/English 320–1440px and real login while visible');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
