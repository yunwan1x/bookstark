const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  for(const [width,lang,theme] of [[1440,'zh','light'],[390,'zh','light'],[320,'en','dark'],[768,'en','scholar-paper']]){
   for(const kind of ['article','note','book','bookmark']){
   const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(theme=>localStorage.setItem('bookstark-theme',theme),theme);
   await page.route('http://public.test/**',route=>{
    const url=new URL(route.request().url());
    if(url.pathname.startsWith('/static/'))return route.fulfill({path:'.'+url.pathname});
    if(url.pathname==='/')return route.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync('/tmp/public-feed-'+lang+'-'+kind+'.html','utf8')});
    return route.fulfill({status:404,body:''});
   });
   await page.goto('http://public.test/');
   await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').first().waitFor();
   assert.equal(await page.locator('html').getAttribute('lang'),lang);
   assert.equal(await page.locator('.bookstark-science-bg').count(),0);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'horizontal overflow '+width);
   assert.equal(await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').count(),kind==='article'?2:1);
   assert.equal(await page.locator('.public-nav a').count(),4);
   assert.equal(await page.locator('.public-nav a i').count(),4);
   assert.equal(await page.locator('.public-nav a[aria-current]').getAttribute('href'),'/?type='+kind);
   if(kind==='article')assert.equal(await page.locator('.public-content-type').count(),2);
   if(kind==='note'){assert.equal(await page.locator('.public-note-card h2').count(),0);assert.equal(await page.locator('.public-read-link').count(),0);assert(await page.locator('.public-note-author').isVisible());}
   if(kind==='book')assert(await page.locator('.public-book-cover').isVisible());
   assert.notEqual(await page.locator('.public-categories').evaluate(n=>getComputedStyle(n).backgroundColor),'rgba(0, 0, 0, 0)');
   if(width<=640){
    assert.equal(await page.locator('.public-search').isVisible(),false);
    await page.locator('.public-search-toggle').click();assert(await page.locator('.public-search').isVisible());
    await page.locator('[name="keyword"]').press('Escape');assert.equal(await page.locator('.public-search').isVisible(),false);
    assert.equal(await page.locator('.public-categories nav').isVisible(),false);
    await page.locator('.public-categories summary').click();assert(await page.locator('.public-categories nav').isVisible());
    await page.locator('.public-categories summary').click();
   }
   assert.deepEqual(errors,[]);
   await page.screenshot({path:'/tmp/bookstark-public-'+kind+'-'+width+'.png',fullPage:true});
   console.log('PASS '+kind+' '+width+' '+lang+' '+theme+' layout, navigation and mobile controls');await page.close();
   }
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
