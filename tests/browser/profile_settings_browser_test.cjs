const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const origin=process.env.BOOKSTARK_TEST_ORIGIN;
 const browser=await chromium.launch({args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}}),page=await context.newPage();
 const errors=[],writes=[];page.on('pageerror',error=>errors.push(error.message));
 page.on('request',request=>{if(request.url().startsWith(origin+'/api/profile')&&request.method()==='PUT')writes.push(request.url());});
 const background=async()=>{const response=await context.request.get(origin+'/api/profile/background');assert.equal(response.status(),200);return(await response.json()).data;};
 const save=async()=>{await page.locator('#profile-save').click();await page.locator('.bs-dialog-overlay.active').waitFor();await page.locator('.bs-dialog-overlay.active .bs-btn-primary').click();};
 try{
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(login.status(),200);
  await context.addCookies([{name:'lang',value:'zh',url:origin}]);await page.goto(origin+'/profile');
  await page.waitForFunction(()=>Boolean(window.BookStarkProfileBackground));
  assert.equal(await page.locator('#background-save').count(),0);
  assert.equal(await page.locator('#profile-save').evaluate(button=>button.previousElementSibling.id),'background-reset');
  await page.locator('#email').fill('unified@example.com');await page.locator('#default-home').selectOption('notes');await page.locator('#background-mode').selectOption('solid');
  await save();assert.equal((await background()).mode,'solid');
  await page.reload();assert.equal(await page.locator('#email').inputValue(),'unified@example.com');assert.equal(await page.locator('#default-home').inputValue(),'notes');assert.equal(await page.locator('#background-mode').inputValue(),'solid');
  const beforeReset=writes.length;await page.locator('#background-reset').click();assert.equal(writes.length,beforeReset,'reset only previews until Save');
  assert.equal((await background()).mode,'solid');assert.equal(await page.locator('#background-mode').inputValue(),'dynamic');assert.equal(await page.locator('#email').inputValue(),'unified@example.com');
  await save();assert.equal((await background()).mode,'dynamic');
  await page.locator('#background-mode').selectOption('image');const beforeInvalid=writes.length;
  await page.locator('#profile-save').click();await page.locator('#profile-error').waitFor({state:'visible'});assert.equal(writes.length,beforeInvalid,'validate missing image before saving personal information');
  const png=await page.evaluate(()=>{const canvas=document.createElement('canvas');canvas.width=16;canvas.height=16;canvas.getContext('2d').fillRect(0,0,16,16);return canvas.toDataURL().split(',')[1];});
  await page.setInputFiles('#background-file',{name:'background.png',mimeType:'image/png',buffer:Buffer.from(png,'base64')});
  await page.locator('#background-fade').fill('40');await page.locator('#email').fill('retry@example.com');
  let failNext=true,releaseRequest,requestArrived;
  const arrived=new Promise(resolve=>requestArrived=resolve),release=new Promise(resolve=>releaseRequest=resolve);
  await page.route('**/api/profile/background',async route=>{
   if(route.request().method()==='PUT'&&failNext){failNext=false;requestArrived();await release;await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({code:1,message:'Temporary background error'})});}
   else await route.continue();
  });
  await page.locator('#profile-save').click();await arrived;
  for(const selector of ['#profile-save','#background-reset','#email','#background-mode','#background-file'])assert.equal(await page.locator(selector).isDisabled(),true,'lock entire save operation: '+selector);
  releaseRequest();await page.locator('#profile-error').waitFor({state:'visible'});await page.waitForFunction(()=>!document.querySelector('#profile-save').disabled);
  assert((await page.locator('#profile-error').innerText()).includes('个人信息已保存，但背景保存失败'));
  assert.equal(await page.locator('.bs-dialog-overlay.active').count(),0,'background failure must not announce complete success');
  assert.equal(await page.locator('#background-file').evaluate(input=>input.files.length),1,'keep upload for retry');assert.equal(await page.locator('#background-fade').inputValue(),'40');
  await save();let stored=await background();assert.equal(stored.mode,'image');assert.equal(stored.fade,40);assert(stored.image_hash);assert.equal((await context.request.get(origin+'/api/profile/background/image')).status(),200);
  await page.reload();assert.equal(await page.locator('#email').inputValue(),'retry@example.com');assert.equal(await page.locator('#background-mode').inputValue(),'image');
  // The moved reset still removes saved images only after the shared Save action.
  await page.locator('#background-reset').click();assert.equal((await background()).image_hash,stored.image_hash);await save();stored=await background();assert.equal(stored.image_hash,'');assert.equal(stored.mode,'dynamic');
  for(const lang of ['zh','en'])for(const width of [320,390,1440]){
   await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.setViewportSize({width,height:1000});await page.goto(origin+'/profile');
   const saveButton=page.locator('#profile-save'),reset=page.locator('#background-reset');
   assert.equal(await saveButton.textContent(),lang==='zh'?'保存':'Save');assert.equal(await reset.textContent(),lang==='zh'?'恢复默认':'Restore default');
   await reset.scrollIntoViewIfNeeded();const left=await reset.boundingBox(),right=await saveButton.boundingBox();assert(Math.abs(left.y-right.y)<2);assert(left.x+left.width<=right.x);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   await page.locator('#profile-settings').screenshot({path:'/tmp/bookstark-profile-unified-'+lang+'-'+width+'.png'});
  }
  assert.deepEqual(errors,[]);console.log('PASS unified profile/background save, reset preview, image upload/removal, validation, in-flight locking, partial failure/retry and Chinese/English responsive actions');
 }catch(error){await page.screenshot({path:'/tmp/bookstark-profile-unified-error.png'}).catch(()=>{});throw error;}
 finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1)});
