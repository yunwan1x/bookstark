// Real browser regression for focus leaving a shared menu, including sandboxed iframes.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const root=require('./repo-root.cjs');

(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});
 try{
  for(const width of [1440,390]){
   const page=await browser.newPage({viewport:{width,height:950}}),errors=[];
   page.on('pageerror',error=>errors.push(error.message));
   await page.route('https://dropdown.test/**',route=>{
    const file=new URL(route.request().url()).pathname;
    if(file.startsWith('/static/'))return route.fulfill({path:path.join(root,file)});
    return route.fulfill({contentType:'text/html',body:`<!doctype html><html><head><link rel="stylesheet" href="/static/css/variables.css"><link rel="stylesheet" href="/static/css/components.css"></head><body>
     <div id="menu" class="bs-action-dropdown"><button class="bs-action-dd-btn" data-bs-action-dropdown-toggle aria-expanded="false">More</button><div class="bs-action-dd-menu" role="menu">
     <button class="bs-action-menu-item" disabled>Disabled</button><button class="bs-action-menu-item" style="display:none">Hidden</button><button id="first" class="bs-action-menu-item">Information</button><button id="last" class="bs-action-menu-item">Export</button></div></div>
     <button id="outside">Outside</button><div id="blank" style="height:80px">Page background</div>
     <iframe title="Tool" sandbox="allow-scripts" srcdoc="<input id='toolInput' aria-label='Tool input'>"></iframe>
     <script src="/static/js/utils.js"></script></body></html>`});
   });
   await page.goto('https://dropdown.test/');
   const trigger=page.locator('#menu>.bs-action-dd-btn'),menu=page.locator('#menu>.bs-action-dd-menu');
   const focus=id=>page.waitForFunction(id=>document.activeElement?.id===id,id);
   const closed=async()=>{await menu.waitFor({state:'hidden'});assert.equal(await trigger.getAttribute('aria-expanded'),'false');};
   await trigger.click();await focus('first');
   await page.keyboard.press('Tab');await focus('last');assert.equal(await menu.isVisible(),true,'focus within menu keeps it open');
   await page.keyboard.press('Tab');await focus('outside');await closed();
   await trigger.click();await focus('first');await page.locator('#blank').click();await closed();
   await trigger.click();await focus('first');await page.locator('#outside').focus();await closed();
   await trigger.click();await focus('first');await page.frameLocator('iframe').locator('#toolInput').click();await closed();
   assert.equal(await page.frameLocator('iframe').locator('#toolInput').evaluate(el=>el===document.activeElement),true,'iframe receives focus without sandbox changes');
   await trigger.focus();await page.keyboard.press('ArrowUp');await focus('last');await page.keyboard.press('ArrowDown');await focus('first');await page.keyboard.press('Escape');await closed();assert.equal(await trigger.evaluate(el=>el===document.activeElement),true);
   await trigger.click();await focus('first');await trigger.click();await closed();
   await page.evaluate(()=>{BSActionDropdown.open(document.getElementById('menu'));BSActionDropdown.closeAll();document.getElementById('outside').focus();});
   await page.waitForTimeout(30);await focus('outside');await closed();
   assert.deepEqual(errors,[]);await page.close();console.log('PASS shared dropdown focus, outside click, Tab, iframe and Escape',width);
  }
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
