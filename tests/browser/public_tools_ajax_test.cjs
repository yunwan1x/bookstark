// Exercises real plaza HTML fragments, lifecycle and history against a local server.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs');
(async()=>{
 const origin=process.env.BOOKSTARK_TEST_ORIGIN||'http://127.0.0.1:18281',out=process.env.BOOKSTARK_SCREENSHOT_DIR||'/tmp/public-tools-ajax';fs.mkdirSync(out,{recursive:true});
 const browser=await chromium.launch({args:['--no-sandbox']}),context=await browser.newContext({viewport:{width:1440,height:1000},serviceWorkers:'block'}),page=await context.newPage(),errors=[];
 const fixtures=Array.from({length:26},(_,i)=>({id:1000+i,title:'AJAX Tool '+i,description:'Plaza tool',version:'1.0.0',category:i%2?'image':'development',author:'QA',size:2000+i,permissions:{read_files:true,save_files:true,socket_tcp:true},updated:i}));
 page.on('pageerror',e=>errors.push(e.message));
 await context.route('**/api/tool-market',r=>r.fulfill({json:{tools:fixtures}}));
 const tools=()=>page.locator('.public-nav a[href="/shares?type=tool"]');
 async function navigate(link){await link.click();await page.waitForFunction(()=>!document.querySelector('.public-content').hasAttribute('aria-busy'));}
 async function ready(){await page.locator('#marketItems[aria-busy=false]').waitFor();}
 async function sameShell(){assert.equal(await page.evaluate(()=>window.__plazaDocument===document&&window.__plazaSidebar===document.querySelector('.public-info')&&window.__plazaAudio===document.querySelector('.public-info audio')),true,'AJAX must preserve shell and audio nodes');}
 try{
 await page.goto(origin+'/shares?type=bookmark');await page.evaluate(()=>{window.__plazaDocument=document;window.__plazaSidebar=document.querySelector('.public-info');window.__plazaAudio=document.querySelector('.public-info audio');window.__plazaAudio.volume=.25});
 await navigate(tools());await ready();assert.equal(new URL(page.url()).searchParams.get('type'),'tool');await sameShell();assert.equal(await page.locator('#marketSettings,#marketPublish').count(),0);assert.equal(await page.locator('.market-card').count(),12);
 await page.locator('#marketCategories [data-category=image]').click();await page.locator('#marketQuery').fill('Tool 1');await page.locator('#marketSort').selectOption('name');const filteredURL=page.url(),count=await page.locator('.market-card').count();assert.ok(count>0&&count<12);assert.equal(new URL(filteredURL).searchParams.get('type'),'tool');
 await navigate(page.locator('.public-nav a[href*="type=news"]'));await sameShell();await page.goBack();await page.locator('#marketQuery').waitFor();await ready();assert.equal(page.url(),filteredURL);assert.equal(await page.locator('#marketQuery').inputValue(),'Tool 1');assert.equal(await page.locator('#marketSort').inputValue(),'name');assert.equal(await page.locator('.market-card').count(),count);
 await page.goForward();await page.locator('.public-news-feed').waitFor();await sameShell();
 // Old catalog requests must be harmless after tab replacement.
 let release,seen;const gate=new Promise(r=>release=r),started=new Promise(r=>seen=r);await page.route('**/api/tool-market',async r=>{seen();await gate;await r.fulfill({json:{tools:fixtures}})});
 await navigate(tools());await started;await navigate(page.locator('.public-nav a[href*="type=bookmark"]'));release();await page.unrouteAll({behavior:'wait'});await page.waitForTimeout(100);await sameShell();assert.equal(await page.locator('#marketMain').count(),0);assert.equal(new URL(page.url()).searchParams.get('type'),'bookmark');
 // Failed fragment requests keep the prior content and URL.
 await page.route('**/shares?type=tool',r=>r.fulfill({status:503,body:'temporary error'}));const previous=page.url();await tools().click();await page.locator('.public-load-status:not([hidden])').waitFor();assert.equal(page.url(),previous);await sameShell();await page.unroute('**/shares?type=tool');
 // A response belonging to another account must never replace this workspace.
 await page.route('**/shares?type=tool',async r=>{const response=await r.fetch();const html=await response.text();await r.fulfill({response,body:html.replace('"account":""','"account":"another-user"')})});await tools().click();await page.locator('.public-load-status:not([hidden])').waitFor();assert.equal(page.url(),previous);assert.equal(await page.locator('#marketMain').count(),0);await page.unroute('**/shares?type=tool');
 // Direct entry and the old URL both use the same shell.
 await page.goto(origin+'/market?category=image&layout=list');await ready();assert.equal(new URL(page.url()).pathname,'/shares');assert.equal(await page.locator('#marketCategories [aria-current]').getAttribute('data-category'),'image');assert.equal(await page.locator('#marketItems').evaluate(el=>el.classList.contains('is-list')),true);
 for(const [width,lang]of [[1440,'zh'],[390,'zh'],[320,'en'],[768,'en'],[1024,'zh']]){await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.setViewportSize({width,height:900});await page.evaluate(theme=>localStorage.setItem('bookstark-theme',theme),width===1024?'hud-light':'light');await page.reload();await ready();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);assert.equal(await page.evaluate(()=>{const f=document.querySelector('.site-footer').getBoundingClientRect();return Math.abs(f.bottom+scrollY-Math.max(innerHeight,document.documentElement.scrollHeight))<2}),true,'footer follows document bottom');await page.screenshot({path:out+'/tools-'+width+'-'+lang+'.png',fullPage:true});}
 // Sign in and simulate a remote source requiring market authentication.
 await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD||'admin'}});
 await context.route('**/api/tool-market/client',r=>r.fulfill({json:{url:origin+'/market',configured:true,workspace_account:'admin',can_configure:true}}));await context.route('**/api/tool-installs',r=>r.fulfill({json:{tools:[]}}));
 await page.setViewportSize({width:1440,height:1000});await page.goto(origin+'/shares?type=news');await navigate(tools());await ready();assert.equal(await page.locator('#marketSettings,#marketPublish').count(),2);
 for(let n=0;n<3;n++){await navigate(page.locator('.public-nav a[href*="type=bookmark"]'));await navigate(tools());await ready();}
 let metadataRequests=0;await page.route('**/api/tool-market/1025?metadata=1',r=>{metadataRequests++;return r.fulfill({status:401,json:{error:'market_login_required'}})});
 await page.locator('[data-market-action=install][data-id="1025"]').click();await page.locator('dialog[open]').waitFor();assert.equal(metadataRequests,1,'remounts must not duplicate install handlers');
 await page.goBack();await page.locator('.public-content:not(#marketMain)').waitFor();assert.equal(await page.locator('dialog[open]').count(),0,'unmount closes market login');
 // BFCache-like remount on the same DOM must abort all earlier handlers.
 await navigate(tools());await ready();await page.evaluate(()=>{window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true}));window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}))});await ready();await page.locator('[data-market-action=install][data-id="1025"]').click();await page.locator('dialog[open]').waitFor();assert.equal(metadataRequests,2);await page.keyboard.press('Escape');
 assert.deepEqual(errors,[]);fs.writeFileSync(out+'/result.json',JSON.stringify({sharedShell:true,audioRetained:true,historyRestoresFilters:true,staleCatalogGuard:true,fragmentFailure:true,accountGuard:true,compatRedirect:true,responsive320:true,guestAndAdminPermissions:true,noDuplicateListeners:true,loginDialogCleanup:true,bfcacheRemount:true,errors},null,2));console.log('PUBLIC TOOLS AJAX REGRESSION PASSED');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
