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
  assert.deepEqual(errors,[]);console.log('PASS: en/zh setup, mismatch, custom password, real clipboard copy, fallback feedback, existing workspace, mobile layout');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
