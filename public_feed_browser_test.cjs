const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  for(const [width,lang,theme] of [[1440,'zh','light'],[390,'zh','light'],[320,'en','dark'],[768,'en','scholar-paper']]){
   for(const kind of ['article','note','book','bookmark']){
   for(const signedIn of [false,true]) {
   const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(theme=>localStorage.setItem('bookstark-theme',theme),theme);
   await page.route('http://public.test/**',route=>{
    const url=new URL(route.request().url());
    if(url.pathname.startsWith('/static/'))return route.fulfill({path:'.'+url.pathname});
    if(url.pathname==='/shares')return route.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync('/tmp/public-feed-'+lang+'-'+kind+(signedIn?'-auth':'')+'.html','utf8')});
    if(url.pathname.startsWith('/api/shares/')&&url.pathname.endsWith('/comments'))return route.fulfill({contentType:'application/json',body:JSON.stringify({code:0,data:[],total:0})});
    return route.fulfill({status:404,body:''});
   });
   await page.goto('http://public.test/shares');
   await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').first().waitFor();
   assert.equal(await page.locator('html').getAttribute('lang'),lang);
   assert.equal(await page.locator('.bookstark-science-bg').count(),0);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'horizontal overflow '+width);
   assert.equal(await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').count(),kind==='article'?2:1);
   assert.equal(await page.locator('.public-nav a').count(),4);
   assert.equal(await page.locator('.public-nav a i').count(),4);
   const current=new URL(await page.locator('.public-nav a[aria-current]').getAttribute('href'),'http://public.test');
   assert.equal(current.pathname,'/shares');assert.equal(current.searchParams.get('type'),kind);
   assert.equal(await page.locator('.public-account').count(),signedIn?1:0);
   assert.equal(await page.locator('.public-login').count(),signedIn?0:1);
   if(signedIn){
    await page.locator('#user-menu-trigger').click();assert(await page.locator('#user-menu-dropdown').isVisible());
    await page.locator('#user-menu-trigger').press('Escape');assert.equal(await page.locator('#user-menu-dropdown').isVisible(),false);
    assert(await page.locator('[data-public-action="unpublish"]').count()=== (kind==='bookmark'?0:kind==='article'?2:1));
   } else assert.equal(await page.locator('[data-public-action]').count(),0);
   if(kind==='article')assert.equal(await page.locator('.public-content-type').count(),2);
   if(kind==='note'){assert.equal(await page.locator('.public-note-card h2').count(),0);assert.equal(await page.locator('.public-read-link').count(),0);assert(await page.locator('.public-note-author').isVisible());}
   if(kind==='book')assert(await page.locator('.public-book-cover').isVisible());
   if(kind!=='bookmark'){
    const badge=page.locator('.public-pinned').first();
    assert(await badge.count()>0,'missing pinned fixture');
    assert.equal(await badge.evaluate(n=>getComputedStyle(n).alignItems),'center');
    if(kind!=='note'){
     assert.equal(await badge.locator('..').getAttribute('class'),'public-entry-heading');
     const aligned=await badge.evaluate(n=>{const title=n.parentElement.querySelector('h2'),a=n.getBoundingClientRect(),b=title.getBoundingClientRect();return {delta:Math.abs(a.y+a.height/2-b.y-b.height/2),before:n.compareDocumentPosition(title)&Node.DOCUMENT_POSITION_FOLLOWING};});
     assert(aligned.before,'badge must precede title');
     if(width>=768)assert(aligned.delta<1,'badge/title vertical alignment');
    }
   }
   assert.notEqual(await page.locator('.public-categories').evaluate(n=>getComputedStyle(n).backgroundColor),'rgba(0, 0, 0, 0)');
   if(width<=640){
    assert.equal(await page.locator('.public-search').isVisible(),false);
    await page.locator('.public-search-toggle').click();assert(await page.locator('.public-search').isVisible());
    await page.locator('[name="keyword"]').press('Escape');assert.equal(await page.locator('.public-search').isVisible(),false);
    assert(await page.locator('.public-categories nav').isVisible());
    assert.equal(await page.locator('.public-info').isVisible(),false);
   }
   if(kind==='note'){
    assert.equal(await page.evaluate(()=>Boolean(window.__noteXss)),false);
    assert.equal(await page.locator('[data-note-content] script').count(),0);
    assert(await page.locator('[data-note-content] strong').count()>0);
    await page.locator('[data-note-content] img').click();assert(await page.locator('#shareNoteImageLightboxOverlay').isVisible());
    await page.locator('#shareNoteImageLightboxCloseBtn').press('Escape');assert.equal(await page.locator('#shareNoteImageLightboxOverlay').isVisible(),false);
    await page.locator('[data-note-action="expand"]').click();assert(await page.locator('#shareNoteViewerOverlay').isVisible());
    assert(await page.locator('#shareNoteViewerContent').textContent());
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'viewer overflow '+width);
    await page.locator('.note-viewer-close').press('Escape');assert.equal(await page.locator('#shareNoteViewerOverlay').isVisible(),false);
    await page.locator('[data-note-action="comments"]').click();assert(await page.locator('.share-comments').isVisible());
    await page.locator('[data-note-action="comments"]').click();assert.equal(await page.locator('.share-comments').isVisible(),false);
   }
   assert.deepEqual(errors,[]);
   await page.screenshot({path:'/tmp/bookstark-public-'+kind+'-'+width+'.png',fullPage:true});
   console.log('PASS '+kind+' '+width+' '+lang+' '+theme+' '+(signedIn?'authenticated':'guest')+' layout, navigation and controls');await page.close();
   }
   }
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
