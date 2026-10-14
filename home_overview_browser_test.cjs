// Real rendered templates and local assets, mocked API: never writes production data.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
 for(const lang of ['zh','en'])for(const [width,theme] of [[1440,'light'],[768,'light'],[390,'light'],[320,'dark']]){
  const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];let calls=0,fail=false;
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(t=>localStorage.setItem('bookstark-theme',t),theme);
  await page.route('http://home.test/**',route=>{
   const u=new URL(route.request().url());
   if(u.pathname.startsWith('/static/'))return route.fulfill({path:'.'+u.pathname});
   if(u.pathname==='/api/home'){calls++;return route.fulfill({json:fail?{code:500}:{code:0,stats:{notes:119,articles:86,pending_tasks:6,created_this_week:12},sections:['notes','articles','tasks'].map(key=>({key,total:1,items:[{title:'Example',url:'/notes',date:'2026-10-14'}]})),layout:null},status:fail?500:200});}
   if(u.pathname==='/home')return route.fulfill({contentType:'text/html',body:fs.readFileSync('/tmp/home-b1-'+lang+'.html','utf8')});
   return route.fulfill({status:404,body:''});
  });
  await page.goto('http://home.test/home');await page.locator('.home-card').first().waitFor();
  assert.deepEqual(await page.locator('[data-home-stat]').allTextContents(),['119','86','6','12']);
  assert.equal(await page.locator('.home-eyebrow').count(),0);
  assert(await page.locator('.home-heading-card [data-home-dialog="homeCreate"]').isVisible());
  const overflow=await page.evaluate(()=>({ok:document.documentElement.scrollWidth<=innerWidth,items:[...document.querySelectorAll('body *')].filter(n=>n.getBoundingClientRect().right>innerWidth+1).map(n=>({class:n.className,right:n.getBoundingClientRect().right})).slice(0,12)}));
  assert(overflow.ok,'overflow '+lang+' '+width+' '+JSON.stringify(overflow.items));
  assert.equal(await page.locator('.home-stats').evaluate(n=>getComputedStyle(n).gridTemplateColumns.split(' ').length),width<=768?2:4);
  const sort=page.locator('[data-home-sort="created"]');await sort.click();await page.waitForFunction(()=>document.querySelector('#homeStats').getAttribute('aria-busy')==='false');
  assert.equal(await sort.getAttribute('aria-pressed'),'true');assert((await sort.getAttribute('class')).includes('active'));
  assert.equal(await sort.evaluate(n=>getComputedStyle(n).borderBottomWidth),'0px');
  assert.notEqual(await sort.evaluate(n=>getComputedStyle(n).color),await sort.evaluate(n=>getComputedStyle(n).backgroundColor));
  const before=calls;await sort.click();assert.equal(calls,before,'selected sort must not reload');
  fail=true;await page.locator('[data-home-sort="updated"]').click();await page.locator('#homeRetry').waitFor({state:'visible'});
  assert.deepEqual(await page.locator('[data-home-stat]').allTextContents(),['—','—','—','—']);assert.equal(await page.locator('.home-card').count(),0);
  fail=false;await page.locator('#homeRetry').click();await page.locator('.home-card').first().waitFor();
  await page.locator('.home-heading-card [data-home-dialog="homeCustomize"]').click();assert(await page.locator('#homeCustomize').isVisible());await page.keyboard.press('Escape');
  await page.screenshot({path:'/tmp/home-b1-'+lang+'-'+width+'.png'});assert.deepEqual(errors,[]);console.log('PASS',lang,width,theme,'stats, sort, retry, layout dialog');await page.close();
 }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
