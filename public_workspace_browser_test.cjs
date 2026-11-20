const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const origin=process.env.BOOKSTARK_TEST_ORIGIN;
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 async function navigate(locator) { const [response]=await Promise.all([page.waitForNavigation(),locator.click()]);assert.equal(response.status(),200); }
 try {
  await page.goto(origin+'/shares');
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
  await Promise.all([page.waitForNavigation(),page.locator('#publicSort').selectOption({label:'最近更新'})]);
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
  assert.equal(await page.locator('.public-info>section').count(),3);
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
  await navigate(page.locator('.public-nav a').first());assert.equal(new URL(page.url()).searchParams.get('keyword'),null);
  // Real timezone calculation, including DST and date differences.
  for(const instant of ['2026-11-20T12:30:00Z','2026-07-20T23:30:00Z']){
   await page.clock.install({time:new Date(instant)});
   await page.reload();
   const times=await page.locator('[data-clock-zone] time').allTextContents();
   assert.deepEqual(times,instant.includes('11-20')?['20:30','12:30','07:30']:['07:30','00:30','19:30']);
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
  assert.equal(await page.locator('#publicRadioSource').getAttribute('href'),'https://www.radio-browser.info/');
  await page.locator('#publicRadioPlay').click();await page.reload();
  assert.ok((await page.locator('#publicRadioStation').inputValue()).includes('test-radio.example'));
  assert.equal(await page.locator('#publicRadioPlay').getAttribute('aria-pressed'),'false','restore must not autoplay');
  await page.locator('#publicRadioDiscovery summary').click();
  directoryMode='empty';await page.locator('#publicRadioQuery').fill('none');await page.locator('#publicRadioSearch button').click();
  await page.waitForFunction(()=>document.getElementById('publicRadioSearchStatus').textContent.includes('没有匹配'));
  directoryMode='error';await page.locator('#publicRadioSearch button').click();await page.waitForFunction(()=>document.getElementById('publicRadioSearchStatus').textContent.includes('暂时不可用'));
  directoryMode='stale';await page.locator('#publicRadioQuery').fill('old');await page.locator('#publicRadioSearch button').click();await page.locator('#publicRadioQuery').fill('new');await page.locator('#publicRadioSearch button').click();
  await page.waitForFunction(()=>document.querySelectorAll('.public-radio-result').length===1);await page.waitForTimeout(250);
  assert.ok(!(await page.locator('#publicRadioResults').innerText()).includes('OLD RESULT'));
  directoryMode='paged';await page.locator('#publicRadioSearch button').click();await page.locator('#publicRadioMore').waitFor({state:'visible'});await page.locator('#publicRadioMore').click();await page.locator('#publicRadioMore').waitFor({state:'hidden'});assert.equal(requested.searchParams.get('offset'),'40');
  for(const width of [320,390,1440]){await page.setViewportSize({width,height:1050});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
  await page.goto(origin+'/shares?type=article&keyword=Workspace%20article%2003');
  await page.locator('.public-manage summary').click();
  await page.locator('[data-public-action=pin]').click();await page.locator('.public-pinned').waitFor();
  const menu=page.locator('.public-manage');await menu.locator('summary').click();
  await page.locator('[data-public-action=unpublish]').click();
  await page.locator('#bs-confirm-ok').click();
  await page.locator('.public-empty').waitFor();
  await context.clearCookies();await page.reload();assert.equal(await page.locator('.public-entry').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS real server: tabs, pagination, search, category/sort retention, empty state, login return, account menu, note viewer, bookmark domain, pin/unpublish, radio search/genres/paging/failover/persistence/safe rendering, 320–1440px.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
