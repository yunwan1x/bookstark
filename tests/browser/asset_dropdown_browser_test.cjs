const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');

(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});
 const origin=process.env.BOOKSTARK_TEST_ORIGIN,out=process.env.BOOKSTARK_SCREENSHOT_DIR||'/tmp/bookstark-asset-dropdown';fs.mkdirSync(out,{recursive:true});
 const context=await browser.newContext({viewport:{width:1440,height:1050}});
 await context.addInitScript(()=>{if(window===top&&navigator.serviceWorker)navigator.serviceWorker.register=()=>new Promise(()=>{});});
 await context.addCookies([{name:'lang',value:'zh',url:origin}]);
 const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
 async function topmost(selector){
  const evidence=await page.locator(selector).first().evaluate(element=>{
   const box=element.getBoundingClientRect(),x=box.left+box.width/2,y=box.top+box.height/2,hit=document.elementFromPoint(x,y);
   return {visible:!!hit&&element.contains(hit),hit:hit?.id||hit?.className,portalZ:getComputedStyle(document.getElementById('assetDropdownPortal')).zIndex,modalZ:getComputedStyle(document.getElementById('sshModal')).zIndex,rect:{x:box.x,y:box.y,width:box.width,height:box.height},viewport:{width:innerWidth,height:innerHeight}};
  });
  assert.equal(evidence.visible,true,'Dropdown option must receive pointer input above the modal: '+JSON.stringify(evidence));
 }
 try{
  assert.equal((await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}})).status(),200);
  const csrf=(await(await context.request.get(origin+'/api/csrf-token')).json()).csrf_token;
  const credentials=[];
  for(const name of ['fixture-a','fixture-b']){
   const response=await context.request.post(origin+'/api/admin/assets/credentials',{headers:{'X-CSRF-Token':csrf},data:{name,username:'test-user',auth_type:'password',credential:'isolated-browser-fixture'}});
   assert.equal(response.status(),200);credentials.push((await response.json()).data);
  }
  for(const [width,lang,theme]of [[1440,'zh','light'],[1440,'en','glass'],[390,'zh','glass'],[320,'en','hud'],[390,'zh','hud-light']]){
   await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.goto(origin+'/admin/assets');await page.evaluate(theme=>localStorage.setItem('bookstark-theme',theme),theme);await page.setViewportSize({width,height:900});await page.reload();
   await page.locator(width<=640?'#assetMobileFab':'#addSshBtn').click();await page.locator('#sshCredentialSearch').click();await page.locator('#sshCredentialDropdown:not(.asset-hidden) .asset-combobox-option').first().waitFor();
   await topmost('#sshCredentialDropdown .asset-combobox-option');
   await page.screenshot({path:out+`/ssh-${width}-${lang}-${theme}.png`,animations:'disabled'});
   await page.locator('#sshCredentialSearch').fill('fixture-a');await page.locator('#sshCredentialDropdown .asset-combobox-option').click();assert.equal(await page.locator('#sshCredential').inputValue(),String(credentials[0].id));
   if(width>640){
   await page.locator('#sshCredentialSearch').click();await page.locator('#sshCredentialSearch').press('ArrowDown');await page.keyboard.press('Enter');assert.equal(await page.locator('#sshCredentialSearch').getAttribute('aria-expanded'),'false');
   await page.locator('#sshCredentialSearch').click();await page.locator('#sshName').click();assert.equal(await page.locator('#sshCredentialSearch').getAttribute('aria-expanded'),'false');
   await page.locator('#sshCredentialSearch').click();await page.locator('#sshCredentialDropdown .asset-combobox-create').click();await page.locator('#credentialModal.open').waitFor();assert.equal(await page.locator('#sshModal.open').count(),1);
   await page.locator('#credentialModal [data-close-modal]').first().click();await page.waitForFunction(()=>document.activeElement?.id==='sshCredentialSearch');assert.equal(await page.locator('#sshCredential').inputValue(),String(credentials[0].id));
   }
   await page.locator('#sshShell').click();await page.locator('#sshShellOptions:not(.asset-hidden) .asset-autocomplete-option').first().waitFor();await topmost('#sshShellOptions .asset-autocomplete-option');await page.locator('#sshShellOptions .asset-autocomplete-option').first().click();
   await page.locator('#sshModal [data-close-modal]').first().click();await page.locator('#sshModal.open').waitFor({state:'hidden'});assert.equal(await page.locator('#sshCredentialDropdown').evaluate(el=>el.parentElement.id),'sshCredentialPicker');
   await page.locator('[data-tab=webdav]').click();await page.locator(width<=640?'#assetMobileFab':'#addWebdavBtn').click();await page.locator('#webdavCredentialSearch').click();await page.locator('#webdavCredentialDropdown:not(.asset-hidden) .asset-combobox-option').first().waitFor();await topmost('#webdavCredentialDropdown .asset-combobox-option');await page.locator('#webdavCredentialDropdown .asset-combobox-option').first().click();await page.locator('#webdavModal [data-close-modal]').first().click();
  }
  assert.deepEqual(errors,[]);console.log('PASS: SSH credential and shell dropdowns and WebDAV credential dropdowns stay above modal, with mouse/keyboard selection, nested credential cancellation and responsive themes.');
 }catch(error){await page.screenshot({path:out+'/failure.png',fullPage:true,animations:'disabled'});throw error;}finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1)});
