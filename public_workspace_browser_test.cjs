const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const origin=process.env.BOOKSTARK_TEST_ORIGIN;
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 async function update(action) { const [response]=await Promise.all([page.waitForResponse(r=>r.request().headers()['x-bookstark-feed']==='content'),action()]);assert.equal(response.status(),200);await page.waitForFunction(()=>!document.querySelector('.public-content').hasAttribute('aria-busy')); }
 async function navigate(locator) { if(await locator.evaluate(n=>Boolean(n.closest('.public-content'))))return update(()=>locator.click());const [response]=await Promise.all([page.waitForNavigation(),locator.click()]);assert.equal(response.status(),200); }
 try {
  await page.goto(origin+'/?type=article');
  await navigate(page.locator('.public-nav a').nth(3));
  await update(()=>page.goBack());assert.equal(new URL(page.url()).pathname,'/');
  assert.equal(await page.locator('.public-entry').count(),15);
  await page.evaluate(()=>document.fonts.ready);
  const icons=await page.locator('.public-article-icon i').evaluateAll(nodes=>nodes.map(n=>({name:n.className,glyph:getComputedStyle(n,'::before').content,font:getComputedStyle(n).fontFamily})));
  assert.equal(icons.length,15);
  assert.equal(new Set(icons.map(i=>i.name)).size,15,'same-page article icons must be unique');
  for(const icon of icons){assert.ok(icon.glyph&&icon.glyph!=='none'&&icon.glyph!=='normal');assert.ok(icon.font.includes('Font Awesome 6 Free'));}
  await navigate(page.locator('.public-pagination a').last());assert.equal(await page.locator('.public-entry').count(),2);
  await navigate(page.locator('.public-categories a').nth(1));assert.equal(new URL(page.url()).searchParams.get('page'),'1');
  assert.equal(new URL(page.url()).searchParams.get('label'),'工具');
  await page.locator('#publicSearch [name=keyword]').fill('Workspace article 03');
  await navigate(page.locator('.public-search-submit'));
  assert.equal(await page.locator('.public-entry').count(),1);
  assert.ok((await page.locator('.public-entry').innerText()).includes('article 03'));
  await update(()=>page.locator('#publicSort').selectOption({label:'最近更新'}));
  assert.equal(new URL(page.url()).searchParams.get('keyword'),'Workspace article 03');
  assert.equal(new URL(page.url()).searchParams.get('label'),'工具');
  await page.locator('#publicSearch [name=keyword]').fill('no-matching-record');await navigate(page.locator('.public-search-submit'));await page.locator('.public-empty').waitFor();
  await page.goto(origin+'/shares?type=note&sort=updated');
  const loginHref=await page.locator('.public-login').getAttribute('href');
  assert.equal(new URL(loginHref,origin).searchParams.get('next'),'/shares?type=note&sort=updated');
  await navigate(page.locator('.public-login'));assert.ok(await page.evaluate(()=>Boolean(sessionStorage.getItem('bookstark:public-login-return'))));
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(login.status(),200);
  await page.goto(origin+'/shares?type=note&sort=updated');
  assert.equal(await page.evaluate(()=>sessionStorage.getItem('bookstark:public-login-return')),null);
  await page.locator('#user-menu-trigger').click();await page.locator('#user-menu-dropdown').waitFor({state:'visible'});await page.keyboard.press('Escape');
  for (const type of ['article','note','book','bookmark']) {
   await page.goto(origin+'/shares?type='+type);
   assert.equal(await page.locator('.public-nav a[aria-current]').count(),1);
   const kind=new URL(await page.locator('.public-nav a[aria-current]').getAttribute('href'),origin).searchParams.get('type');assert.equal(kind,type);
   assert.equal(await page.locator('.header-plaza-link.active').count(),1);
   for(const width of [320,390,768,1440]){
    await page.setViewportSize({width,height:1000});
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'overflow '+type+' '+width);
   }
   if(type==='note') {
    await page.locator('[data-note-content] strong').waitFor();
    await page.locator('[data-note-action=expand]').click();await page.locator('#shareNoteViewerOverlay').waitFor({state:'visible'});await page.keyboard.press('Escape');
   }
   if(type==='bookmark')assert.equal(await page.locator('.public-bookmark-domain').innerText(),'example.com');
   await page.screenshot({path:'/tmp/bookstark-square-real-'+type+'.png'});
  }

  await page.goto(origin+'/shares?type=book');
  assert.equal(await page.locator('.public-book-card').count(),4);
  assert.equal(await page.locator('.public-info>section').count(),4);
  assert.equal(await page.locator('.public-tools-card .local-tool-grid a').count(),6);
  assert.ok(await page.evaluate(()=>document.querySelector('#publicSearch').getBoundingClientRect().top>=document.querySelector('.public-nav').getBoundingClientRect().bottom));
  const covers=await page.locator('.public-book-cover').evaluateAll(ns=>ns.map(n=>n.className));
  await page.reload();assert.deepEqual(await page.locator('.public-book-cover').evaluateAll(ns=>ns.map(n=>n.className)),covers);
  for (const theme of ['light','nvidia','apple']) {
   await page.evaluate(theme=>window.BookStarkTheme.apply(theme),theme);
   for (const width of [1440,390,320]) {
    await page.setViewportSize({width,height:1080});
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'book widget overflow '+theme+width);
    const boxes=await page.locator('.public-book-card').evaluateAll(ns=>ns.map(n=>({x:n.offsetLeft,y:n.offsetTop,w:n.offsetWidth})));
    if(width===1440)assert.equal(boxes[0].y,boxes[1].y);
    else assert.ok(boxes[1].y>boxes[0].y);
    await page.screenshot({path:'/tmp/bookstark-widgets-'+theme+'-'+width+'.png',fullPage:true});
   }
  }
  await page.setViewportSize({width:1440,height:1080});
  await page.goto(origin+'/shares?type=book&keyword=Workspace');
  assert.equal(await page.locator('.public-book-card').count(),1);
  const one=await page.locator('.public-book-card').boundingBox(), grid=await page.locator('.public-items-book').boundingBox();
  assert.ok(one.width<grid.width*.6,'single book must not stretch');
  await navigate(page.locator('.public-nav a').nth(1));assert.equal(new URL(page.url()).searchParams.get('keyword'),null);
  // Real timezone calculation, including DST and date differences.
  for(const instant of ['2026-11-20T12:30:00Z','2026-07-20T23:30:00Z']){
   await page.clock.install({time:new Date(instant)});
   await page.reload();
   const times=await page.locator('[data-clock-zone] time').allTextContents();
   assert.deepEqual(times,instant.includes('11-20')?['20:30','12:30','07:30']:['07:30','00:30','19:30']);
   const winter=instant.includes('11-20');
   assert.deepEqual(await page.locator('[data-clock-zone]').evaluateAll(rows=>rows.map(r=>r.classList.contains('is-night'))),winter?[true,false,false]:[false,true,true]);
   assert.deepEqual(await page.locator('.public-clock-hour').evaluateAll(hands=>hands.map(h=>h.getAttribute('transform'))),winter?['rotate(255 50 50)','rotate(15 50 50)','rotate(225 50 50)']:['rotate(225 50 50)','rotate(15 50 50)','rotate(225 50 50)']);
   assert.deepEqual(await page.locator('[data-clock-date]').allTextContents(),winter?['11月20日','11月20日','11月20日']:['7月21日','7月21日','7月20日']);
   await page.clock.runFor(2000);
   assert.deepEqual(await page.locator('.public-clock-second').evaluateAll(hands=>hands.map(h=>h.getAttribute('transform'))),Array(3).fill('rotate(12 50 50)'));
   assert.deepEqual(await page.locator('.public-clock-minute').evaluateAll(hands=>hands.map(h=>h.getAttribute('transform'))),Array(3).fill('rotate(180.2 50 50)'));

  }
  // Exercise native media with a generated WAV, without depending on an external stream.
  await page.clock.resume();
  const wav=Buffer.alloc(44+16000*2);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(8000,24);wav.writeUInt32LE(16000,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(wav.length-44,40);
  let requests=0, fail=false;
  await page.route('https://stream.srg-ssr.ch/**',route=>{requests++;return fail?route.abort():route.fulfill({contentType:'audio/wav',body:wav});});
  await page.reload();assert.equal(requests,0,'radio must not preload/autoplay');
  await page.locator('#publicRadioPlay').click();
  await page.waitForFunction(()=>!document.getElementById('publicRadioAudio').paused);
  await page.locator('#publicRadioStation').selectOption('rsj');
  await page.waitForFunction(()=>document.getElementById('publicRadioAudio').src.includes('rsj'));
  await page.locator('#publicRadioVolume').fill('0.25');
  assert.equal(await page.locator('#publicRadioAudio').evaluate(a=>a.volume),.25);
  await page.locator('#publicRadioPlay').click();assert.equal(await page.locator('#publicRadioPlay').getAttribute('aria-pressed'),'false');
  await page.reload();assert.equal(await page.locator('#publicRadioStation').inputValue(),'rsj');assert.equal(await page.locator('#publicRadioVolume').inputValue(),'0.25');
  fail=true;await page.locator('#publicRadioPlay').click();await page.waitForFunction(()=>document.getElementById('publicRadioStatus').textContent.includes('失败'));
  assert.equal(await page.locator('#publicRadioPlay').getAttribute('aria-pressed'),'false');

  // Directory results are untrusted; keep controls independent from the page search.
  let directoryCalls=0, directoryMode='results', requested;
  const directoryStation={name:'<img src=x onerror=alert(1)> Test Jazz',url_resolved:'https://test-radio.example/jazz.mp3',countrycode:'US',tags:'jazz,smooth',codec:'MP3',hls:0,homepage:'javascript:alert(1)'};
  await page.route('https://*.api.radio-browser.info/**',async route=>{
   if(new URL(route.request().url()).pathname.includes('/countrycodes'))return route.fulfill({json:[{name:'CN'},{name:'US'},{name:'CH'},{name:'DE'},{name:'<script>'}]});
   directoryCalls++;requested=new URL(route.request().url());
   if(directoryMode==='failover'&&requested.hostname.startsWith('de1'))return route.fulfill({status:503,body:''});
   if(directoryMode==='error')return route.fulfill({status:503,body:''});
   if(directoryMode==='stale'&&requested.searchParams.get('name')==='old'){await new Promise(r=>setTimeout(r,200));return route.fulfill({json:[{...directoryStation,name:'OLD RESULT'}]}).catch(()=>{});}
   if(directoryMode==='empty')return route.fulfill({json:[]});
   if(directoryMode==='paged')return route.fulfill({json:requested.searchParams.get('offset')==='0'?Array.from({length:40},(_,i)=>({...directoryStation,name:'Station '+i,url_resolved:'https://test-radio.example/'+i+'.mp3'})):[]});
   return route.fulfill({json:[directoryStation,directoryStation,{...directoryStation,url_resolved:'http://insecure.example/a'}, {name:'bad',url_resolved:'javascript:alert(1)'}]});
  });
  await page.route('https://test-radio.example/**',route=>route.fulfill({contentType:'audio/wav',body:wav}));
  await page.reload();assert.equal(directoryCalls,0,'directory must be lazy');
  await page.locator('#publicRadioDiscovery summary').click();assert.equal(directoryCalls,0);
  directoryMode='failover';await page.locator('#publicRadioGenre').selectOption('jazz');
  await page.waitForFunction(()=>document.querySelectorAll('.public-radio-result').length===1);
  assert.equal(requested.searchParams.get('tag'),'jazz');assert.ok(directoryCalls>=2,'mirror failover');
  assert.equal(await page.locator('.public-radio-result img').count(),0,'station title must be text');
  await page.locator('.public-radio-result').click();await page.waitForFunction(()=>!document.getElementById('publicRadioAudio').paused);
  assert.equal(await page.locator('.public-radio a[href^="http"]').count(),0,'source links removed');
  await page.locator('#publicRadioPlay').click();await page.reload();
  assert.ok((await page.locator('#publicRadioStation').inputValue()).includes('test-radio.example'));
  assert.equal(await page.locator('#publicRadioPlay').getAttribute('aria-pressed'),'false','restore must not autoplay');
  await page.locator('#publicRadioDiscovery summary').click();

  directoryMode='results';
  const country=page.locator('#publicRadioCountry');
  await country.locator('[role=combobox]').click();await country.locator('input[type=search]').fill('瑞士');
  await country.locator('[data-bs-selection-value="CH"]').waitFor();
  await page.waitForFunction(()=>document.querySelectorAll('#publicRadioCountry [role=option]').length===1);
  const callsBefore=directoryCalls;await country.locator('input[type=search]').press('Enter');
  await page.waitForFunction(()=>document.querySelector('#publicRadioResults').getAttribute('aria-busy')==='false');
  assert.equal(requested.searchParams.get('countrycode'),'CH');assert.equal(directoryCalls,callsBefore+1,'country selection should search once');
  await country.locator('[role=combobox]').click();await country.locator('input[type=search]').fill('United States');await country.locator('[data-bs-selection-value="US"]').waitFor();
  await country.locator('input[type=search]').fill('CN');await country.locator('[data-bs-selection-value="CN"]').waitFor();
  await country.locator('input[type=search]').fill('no-country-found');await country.locator('.bs-selection-status').waitFor();assert.equal(await country.locator('[role=option]').count(),0);
  await country.locator('input[type=search]').press('Escape');assert.equal(await country.locator('[role=combobox]').getAttribute('aria-expanded'),'false');
  directoryMode='empty';await page.locator('#publicRadioQuery').fill('none');await page.locator('#publicRadioSearch button[type=submit]').click();
  await page.waitForFunction(()=>document.getElementById('publicRadioSearchStatus').textContent.includes('没有匹配'));
  directoryMode='error';await page.locator('#publicRadioSearch button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('publicRadioSearchStatus').textContent.includes('暂时不可用'));
  directoryMode='stale';await page.locator('#publicRadioQuery').fill('old');await page.locator('#publicRadioSearch button[type=submit]').click();await page.locator('#publicRadioQuery').fill('new');await page.locator('#publicRadioSearch button[type=submit]').click();
  await page.waitForFunction(()=>document.querySelectorAll('.public-radio-result').length===1);await page.waitForTimeout(250);
  assert.ok(!(await page.locator('#publicRadioResults').innerText()).includes('OLD RESULT'));
  directoryMode='paged';await page.locator('#publicRadioSearch button[type=submit]').click();await page.locator('#publicRadioMore').waitFor({state:'visible'});await page.locator('#publicRadioMore').click();await page.locator('#publicRadioMore').waitFor({state:'hidden'});assert.equal(requested.searchParams.get('offset'),'40');assert.equal(requested.searchParams.get('countrycode'),'CH');
  await country.locator('[role=combobox]').click();await country.locator('input[type=search]').fill('');await country.locator('[data-bs-selection-value=""]').waitFor();await country.locator('[data-bs-selection-value=""]').click();await page.waitForFunction(()=>document.querySelector('#publicRadioResults').getAttribute('aria-busy')==='false');assert.equal(requested.searchParams.get('countrycode'),'');
  for(const width of [320,390,1440]){await page.setViewportSize({width,height:1050});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}

  // One live audio element must survive every left-column transition.
  await page.goto(origin+'/shares?type=article');fail=false;
  // Normal transitions use the actual page top; history keeps reading positions.
  for(const width of [1440,390]){
    await page.setViewportSize({width,height:700});
    await page.evaluate(()=>scrollTo(0,120));await page.waitForTimeout(200);
    const articleY=await page.evaluate(()=>scrollY);assert.ok(articleY>0);
    await update(()=>page.locator('.public-nav a').nth(3).evaluate(a=>a.click()));
    assert.equal(await page.evaluate(()=>scrollY),0,'tab returns to actual top');
    await page.evaluate(()=>scrollTo(0,80));await page.waitForTimeout(200);
    const bookY=await page.evaluate(()=>scrollY);assert.ok(bookY>0);
    await update(()=>page.goBack());assert.equal(await page.evaluate(()=>scrollY),articleY);
    await update(()=>page.goForward());assert.equal(await page.evaluate(()=>scrollY),bookY);
    await update(()=>page.locator('.public-nav a').nth(1).evaluate(a=>a.click()));
    assert.equal(await page.evaluate(()=>scrollY),0);
  }
  await page.setViewportSize({width:1440,height:1050});
  const longWav=Buffer.alloc(44+8000*2*120);wav.copy(longWav,0,0,44);longWav.writeUInt32LE(longWav.length-8,4);longWav.writeUInt32LE(longWav.length-44,40);
  await page.route('https://stream.srg-ssr.ch/**',route=>route.fulfill({contentType:'audio/wav',body:longWav}));
  await page.locator('#publicRadioStation').selectOption('rsj');await page.locator('#publicRadioPlay').click();await page.waitForFunction(()=>!document.getElementById('publicRadioAudio').paused);
  await page.evaluate(()=>{window.keptAudio=document.getElementById('publicRadioAudio');window.keptSidebar=document.querySelector('.public-info');window.pauseEvents=0;window.keptAudio.addEventListener('pause',()=>window.pauseEvents++);window.audioStart=window.keptAudio.currentTime;});
  let documentRequests=0;const recordNavigation=r=>{if(r.isNavigationRequest()&&r.frame()===page.mainFrame())documentRequests++;};page.on('request',recordNavigation);
  await navigate(page.locator('.public-pagination a').last());assert.equal(await page.locator('.public-entry').count(),2);
  await navigate(page.locator('.public-categories a').nth(1));
  await page.locator('#publicSearch [name=keyword]').fill('Workspace article 03');await navigate(page.locator('.public-search-submit'));assert.equal(await page.locator('.public-entry').count(),1);
  await update(()=>page.locator('#publicSort').selectOption({label:'最近更新'}));
  await navigate(page.locator('.public-nav a').nth(2));await page.locator('[data-note-content] strong').waitFor();
  await page.locator('[data-note-action=expand]').click();await page.locator('#shareNoteViewerOverlay').waitFor({state:'visible'});await page.keyboard.press('Escape');
  await page.locator('[data-note-action=comments]').click();await page.locator('.share-comments').waitFor({state:'visible'});await page.locator('[data-note-action=comments]').click();
  await navigate(page.locator('.public-nav a').nth(3));assert.equal(await page.locator('.public-book-card').count(),4);
  await navigate(page.locator('.public-nav a').nth(4));assert.equal(await page.locator('.public-bookmark-domain').innerText(),'example.com');
  await update(()=>page.goBack());assert.equal(await page.locator('.public-book-card').count(),4);
  await update(()=>page.goForward());assert.equal(await page.locator('.bm-row').count(),1);
  const navTop=await page.locator('.public-nav').evaluate(el=>el.getBoundingClientRect().top+scrollY);
  // Fetch errors keep the current view and URL; they must not fall back to reload.
  await page.route(origin+'/shares?**',route=>route.request().headers()['x-bookstark-feed']==='content'?route.fulfill({status:503,body:'unavailable'}):route.continue());
  const retainedURL=page.url();await page.locator('.public-nav a').nth(1).click();await page.waitForFunction(()=>document.querySelector('.public-load-status').textContent.includes('加载失败'));assert.equal(page.url(),retainedURL);assert.equal(await page.locator('.bm-row').count(),1);
  await page.unroute(origin+'/shares?**');
  // Delayed obsolete requests cannot overwrite a more recent tab selection.
  await page.route(origin+'/shares?**',async route=>{if(route.request().headers()['x-bookstark-feed']==='content'&&new URL(route.request().url()).searchParams.get('type')==='article'){await new Promise(r=>setTimeout(r,800));}await route.continue().catch(()=>{});});
  await page.locator('.public-nav a').nth(1).click();
  await page.locator('.public-feed-skeleton').waitFor({state:'visible'});
  assert.equal(await page.locator('.public-load-status').isVisible(),false);
  assert.equal(await page.locator('.public-nav').evaluate(el=>el.getBoundingClientRect().top+scrollY),navTop);
  assert.ok(await page.locator('.public-items').evaluate(el=>el.inert&&getComputedStyle(el).visibility==='hidden'));
  await navigate(page.locator('.public-nav a').nth(3));await page.waitForTimeout(850);
  assert.equal(await page.locator('.public-feed-skeleton').count(),0);
  assert.ok(await page.locator('.public-items').evaluate(el=>!el.inert&&getComputedStyle(el).visibility==='visible'));assert.equal(new URL(page.url()).searchParams.get('type'),'book');assert.equal(await page.locator('.public-book-card').count(),4);
  await page.unroute(origin+'/shares?**');
  assert.equal(documentRequests,0,'left navigation must never reload the document');
  assert.ok(await page.evaluate(()=>window.keptAudio===document.getElementById('publicRadioAudio')&&window.keptSidebar===document.querySelector('.public-info')&&!window.keptAudio.paused&&window.keptAudio.currentTime>window.audioStart&&window.pauseEvents===0),'audio continuity');
  await page.locator('#publicRadioPlay').click();page.off('request',recordNavigation);
  await page.goto(origin+'/shares?type=article&keyword=Workspace%20article%2003');
  await page.locator('.public-manage summary').click();
  await page.locator('[data-public-action=pin]').click();await page.locator('.public-pinned').waitFor();
  const menu=page.locator('.public-manage');await menu.locator('summary').click();
  await page.locator('[data-public-action=unpublish]').click();
  await page.locator('#bs-confirm-ok').click();
  await page.locator('.public-empty').waitFor();
  await context.clearCookies();await page.reload();assert.equal(await page.locator('.public-entry').count(),0);

  const pwa=await browser.newContext({serviceWorkers:'allow'}),pwaPage=await pwa.newPage();
  await pwaPage.goto(origin+'/shares?type=article');await pwaPage.evaluate(async()=>{await navigator.serviceWorker.register('/sw.js');await navigator.serviceWorker.ready;});await pwaPage.reload();
  await pwaPage.waitForFunction(()=>Boolean(navigator.serviceWorker.controller));
  await pwaPage.locator('.public-nav a').nth(3).click();await pwaPage.locator('.public-book-card').first().waitFor();
  assert.equal(await pwaPage.locator('#publicRadioAudio').count(),1);
  assert.deepEqual(await pwaPage.evaluate(async()=>{const paths=[];for(const name of await caches.keys()){const cache=await caches.open(name);for(const request of await cache.keys()){if(new URL(request.url).pathname==='/shares')paths.push(request.url);}}return paths;}),[],'service worker must not cache public pages or fragments');
  await pwa.setOffline(true);await pwaPage.locator('.public-nav a').nth(1).click();await pwaPage.waitForFunction(()=>document.querySelector('.public-load-status').textContent.includes('加载失败'));
  assert.equal(await pwaPage.locator('.public-book-card').count(),4);await pwa.close();
  assert.deepEqual(errors,[]);
  console.log('PASS real server: tabs, pagination, search, category/sort retention, empty state, login return, account menu, note viewer, bookmark domain, pin/unpublish, radio search/countries, AJAX tabs/search/sort/pages/history/errors/races with uninterrupted native audio, 320–1440px.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
