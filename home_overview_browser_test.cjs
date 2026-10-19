// Rendered templates + local assets and mocked APIs; never writes production data.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage']});
 try{
 for(const lang of ['zh','en'])for(const [width,theme] of [[1440,'light'],[1280,'dark'],[768,'light'],[390,'light'],[320,'dark']]){
  if(process.env.HOME_TEST_LANG&&process.env.HOME_TEST_LANG!==lang)continue;
  if(process.env.HOME_TEST_WIDTH&&Number(process.env.HOME_TEST_WIDTH)!==width)continue;
  const page=await browser.newPage({viewport:{width,height:1000},hasTouch:width<=640,isMobile:width<=640}),errors=[];
  let calls=0,fail=false,lastQuery,release,cleared=false,clearCalls=0;
  const pending=new Promise(resolve=>release=resolve);
  page.on('pageerror',e=>errors.push(e.message));
  await page.clock.setFixedTime(new Date('2026-10-16T12:00:00'));
  await page.addInitScript(t=>{localStorage.setItem('bookstark-theme',t);document.cookie='csrf_token=local-test; path=/';},theme);
  await page.route('**/*',route=>new URL(route.request().url()).hostname==='home.test'?route.fallback():route.abort());
  await page.route('http://home.test/**',async route=>{
   const u=new URL(route.request().url());
   if(u.pathname.startsWith('/static/'))return route.fulfill({path:'.'+u.pathname});
   if(u.pathname==='/api/home/recent'){assert.equal(route.request().method(),'DELETE');cleared=true;clearCalls++;return route.fulfill({json:{code:0}});}
   if(u.pathname==='/api/home'){
    calls++;lastQuery=u.searchParams;await pending;
    const activity=u.searchParams.get('view')==='month'?{'2026-10-14':3,'2026-10-07':9,'2026-10-01':2,'2026-09-30':5,'2026-09-01':2,'2026-01-01':4}:u.searchParams.get('view')==='week'?{'2026-10-14':3,'2026-10-07':9,'2026-10-01':2,'2026-09-30':5,'2026-09-01':2}:u.searchParams.get('month')==='2026-10'?{'2026-10-14':3,'2026-10-07':9}:{'2026-09-01':2};
    return route.fulfill({status:fail?500:200,json:fail?{code:500}:{code:0,activity,
     recent:cleared?[]:[{type:'note',id:7,title:'<img src=x onerror=alert(1)>',url:'/notes?tab=notes&id=7',visited_at:1792134000000},{type:'document',id:8,title:'A recently visited chapter with a long title',context:'Book name',url:'/books/example/edit?doc=8',visited_at:1792130000000}],
     sections:['notes','articles','tasks'].map(key=>({key,total:1,items:[{title:'Example',url:'/notes',date:'2026-10-01'}]})),layout:null}});
   }
   if(u.pathname==='/home')return route.fulfill({contentType:'text/html',body:fs.readFileSync('/tmp/home-b1-'+lang+'.html','utf8')});
   return route.fulfill({status:404,body:''});
  });
  await page.goto('http://home.test/home');await page.locator('.home-loading-card').first().waitFor();
  assert.equal(await page.locator('#homeGrid').getAttribute('aria-busy'),'true');
  assert.equal(await page.locator('#homeRecent').getAttribute('aria-busy'),'true');
  const loadingNote=page.locator('.home-loading-card[data-section="notes"]');
  assert.equal(await loadingNote.locator('h2').textContent(),lang==='zh'?'笔记':'Notes');
  assert(await loadingNote.locator('.home-card-icon').isVisible());
  assert.equal(await loadingNote.locator('.home-card-all').getAttribute('href'),'/notes');
  assert.equal(await loadingNote.getAttribute('aria-hidden'),null,'fixed section header remains accessible');
  assert.equal(await loadingNote.locator('.home-card-head .skeleton').count(),0);
  assert(await loadingNote.locator('[aria-hidden="true"] .skeleton').count()>0,'only content uses placeholders');
  release();await page.locator('.home-card:not(.home-loading-card)').first().waitFor();
  const ready=()=>page.waitForFunction(()=>document.querySelector('#homeGrid').getAttribute('aria-busy')==='false');
  assert.equal(await page.locator('.home-loading-card').count(),0);
  assert.equal(lastQuery.get('start'),null);assert.equal(lastQuery.get('end'),'');assert.equal(lastQuery.get('limit'),'10');
  assert.equal(await page.locator('.calendar-day.selected').count(),0);
  assert.equal(await page.locator('[data-home-range],#homeRangeForm,#homeHeatmap').count(),0);
  assert.equal(await page.locator('#homeSelectedDate').textContent(),lang==='zh'?'全部时间 · 最近内容':'All time · Recent content');
  assert(await page.locator('#homeCalendar').isVisible(),'monthly calendar visible on phones too');
  const calendarFooter=await page.locator('.home-calendar-footer').evaluate(footer=>{
    const legend=footer.querySelector('.home-calendar-legend').getBoundingClientRect();
    const tabs=footer.querySelector('.home-calendar-view').getBoundingClientRect();
    return {legendTop:legend.top,legendRight:legend.right,tabsTop:tabs.top,tabsLeft:tabs.left,height:tabs.height,width:tabs.width,hidden:!!footer.querySelector('.home-calendar-view').closest('[aria-hidden="true"]')};
  });
  assert(calendarFooter.height<=32&&calendarFooter.width<180,'calendar view uses compact buttons');
  assert.equal(calendarFooter.hidden,false,'view buttons remain accessible beside decorative legend');
  if(lang==='zh')assert(calendarFooter.tabsLeft>=calendarFooter.legendRight&&Math.abs(calendarFooter.tabsTop-calendarFooter.legendTop)<16,'view buttons follow legend on one row');
  assert.equal(await page.locator('.home-recent-row').count(),2);
  const recentRects=await page.locator('.home-recent-row').evaluateAll(rows=>rows.map(row=>{
    const rect=row.getBoundingClientRect();return {top:rect.top,bottom:rect.bottom,height:rect.height};
  }));
  assert(recentRects.every(row=>row.height>=44&&row.height<=56),'recent visits use compact, touch-friendly rows');
  assert(recentRects[1].top-recentRects[0].bottom<=2,'recent rows must not stretch to fill the calendar height');
  assert.equal(await page.locator('.home-recent-row img').count(),0,'titles are text, not HTML');
  assert.equal(await page.locator('.home-recent-row').first().getAttribute('href'),'/notes?tab=notes&id=7');
  assert.equal(await page.locator('.home-recent-row').nth(1).getAttribute('href'),'/books/example/edit?doc=8');
  assert.equal(await page.locator('#homeCalendarDays [data-date="2026-10-14"]').getAttribute('data-level'),'2');
  assert.equal(await page.locator('#homeCalendarDays [data-date="2026-10-07"]').getAttribute('data-level'),'4');
  assert((await page.locator('#homeCalendarDays [data-date="2026-10-14"]').getAttribute('aria-label')).includes('3'));
  if(width>=768){const rects=await page.evaluate(()=>['homeCalendar','homeRecent'].map(id=>document.getElementById(id).getBoundingClientRect().bottom));assert(Math.abs(rects[0]-rects[1])<2,'calendar/recent alignment');}
  const noOverflow=async()=>assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'overflow '+lang+' '+width);
  await noOverflow();
  if(width<=640){
   const sharedHeader=()=>page.locator('body>header').evaluate(header=>{
    const selectors=['.logo-text','#main-nav','.header-home-link','.header-nav-group','.header-plaza-link','#searchTrigger','#user-menu-trigger'];
    return selectors.map(selector=>{
     const node=header.querySelector(selector),style=getComputedStyle(node),rect=node.getBoundingClientRect();
     return {selector,display:style.display,width:rect.width,height:rect.height,left:rect.left};
    });
   });
   const homeHeader=await sharedHeader();
   await page.locator('body').evaluate(body=>body.classList.remove('home-body'));
   assert.deepEqual(await sharedHeader(),homeHeader,'home header matches shared console header');
   await page.locator('body').evaluate(body=>body.classList.add('home-body'));
   assert.equal(await page.locator('header .logo-text').isVisible(),false);
   assert(await page.locator('.home-bottom-nav').isVisible(),'keep home bottom shortcuts');
   for(const id of ['knowledge','collections','assets']){
    const trigger=page.locator('[data-header-menu-id="header-'+id+'-menu"]'),menu=page.locator('#header-'+id+'-menu');
    await trigger.click();assert(await menu.isVisible());assert.equal(await trigger.getAttribute('aria-expanded'),'true');
    const rect=await menu.boundingBox();assert(rect.x>=0&&rect.x+rect.width<=width,'dropdown stays within viewport');
    await page.keyboard.press('Escape');
    // Escape on the trigger closes its shared dropdown.
    await trigger.focus();await page.keyboard.press('Escape');assert.equal(await menu.isVisible(),false);
   }
   await page.locator('#searchTrigger').click();assert(await page.locator('#headerSearchInput').isVisible());
   await page.locator('#headerCloseSearch').click();assert(await page.locator('#main-nav').isVisible());
  }
  await page.locator('#homeCalendarDays [data-date="2026-10-14"]').click();await ready();
  assert.equal(lastQuery.get('start'),null);assert.equal(lastQuery.get('end'),'2026-10-14','upper bound, not one-day range');
  assert((await page.locator('#homeSelectedDate').textContent()).includes('2026/10/14'));
  assert.equal(await page.locator('.home-recent-row').count(),2,'visits independent of cutoff');
  await page.locator('#homeCalendarDays [data-date="2026-10-14"]').focus();await page.keyboard.press('ArrowRight');await ready();
  assert.equal(lastQuery.get('end'),'2026-10-15');assert.equal(await page.locator(':focus').getAttribute('data-date'),'2026-10-15');
  await page.locator('#homePrevMonth').click();await ready();assert.equal(lastQuery.get('month'),'2026-09');assert.equal(lastQuery.get('end'),'2026-10-15');
  assert.equal(await page.locator('#homeCalendarDays [data-date="2026-09-01"]').getAttribute('data-level'),'2');
  await page.locator('#homeClearDate').click();await ready();assert.equal(lastQuery.get('end'),'');assert.equal(await page.locator('.calendar-day.selected').count(),0);
  await page.locator('[data-home-view="week"]').click();await ready();assert.equal(lastQuery.get('view'),'week');assert.equal(lastQuery.get('end'),'');
  assert.equal(await page.locator('#homeWeekdays').isVisible(),false);
  const crossWeek=page.locator('[data-period-start="2026-09-28"]');assert.equal(await crossWeek.getAttribute('data-date'),'2026-10-04');assert((await crossWeek.getAttribute('aria-label')).includes('7'));
  await noOverflow();await page.screenshot({path:'/tmp/home-week-'+lang+'-'+width+'.png'});
  await crossWeek.click();await ready();assert.equal(lastQuery.get('end'),'2026-10-04');assert.equal(lastQuery.get('month'),'2026-09');
  await page.locator('[data-home-view="month"]').click();await ready();assert.equal(lastQuery.get('view'),'month');assert.equal(lastQuery.get('end'),'2026-10-04');
  assert.equal(await page.locator('#homeCalendarDays button').count(),12);
  const october=page.locator('[data-period-start="2026-10-01"]');assert.equal(await october.getAttribute('data-date'),'2026-10-31');assert((await october.getAttribute('aria-label')).includes('14'));
  await noOverflow();await page.screenshot({path:'/tmp/home-month-'+lang+'-'+width+'.png'});
  await october.click();await ready();assert.equal(lastQuery.get('end'),'2026-10-31');
  await page.locator('#homePrevMonth').click();await ready();assert.equal(lastQuery.get('month'),'2025-09');assert.equal(lastQuery.get('end'),'2026-10-31');
  await page.locator('[data-home-current]').click();await ready();assert.equal(lastQuery.get('month'),'2026-10');assert.equal(lastQuery.get('end'),'2026-10-31','current returns display only');
  await page.locator('[data-period-start="2026-02-01"]').focus();await page.keyboard.press('ArrowRight');assert.equal(await page.locator(':focus').getAttribute('data-period-start'),'2026-03-01');assert.equal(lastQuery.get('end'),'2026-10-31','period arrow keys only move focus');
  await page.locator('[data-period-start="2026-02-01"]').click();await ready();assert.equal(lastQuery.get('end'),'2026-02-28');
  await page.locator('[data-home-view="day"]').click();await ready();assert.equal(lastQuery.get('end'),'2026-02-28');assert(await page.locator('#homeWeekdays').isVisible());
  await page.locator('#homeClearDate').click();await ready();assert.equal(lastQuery.get('end'),'');
  await page.locator('#homeLimit').selectOption('20');await ready();assert.equal(lastQuery.get('limit'),'20');
  await page.locator('[data-home-sort="created"]').click();await ready();assert.equal(lastQuery.get('order'),'created');
  assert.equal(await page.locator('[data-home-sort="created"]').evaluate(n=>getComputedStyle(n).borderBottomWidth),'2px');
  assert.equal(await page.locator('.home-recent-row').count(),2);
  const before=calls;await page.locator('[data-home-sort="created"]').click();assert.equal(calls,before);
  await page.locator('#homeRecentClear').click();await page.locator('#bs-confirm-cancel').click();assert.equal(clearCalls,0);
  await page.locator('#homeRecentClear').click();await page.locator('#bs-confirm-ok').click();await page.locator('#homeRecentClear').waitFor({state:'hidden'});await ready();
  assert.equal(clearCalls,1);assert.equal(await page.locator('.home-recent-row').count(),0);
  fail=true;await page.locator('[data-home-sort="updated"]').click();await page.locator('#homeRetry').waitFor({state:'visible'});assert.equal(await page.locator('.home-card').count(),0);
  fail=false;await page.locator('#homeRetry').click();await page.locator('.home-card:not(.home-loading-card)').first().waitFor();
  await page.locator('.home-heading-card [data-home-dialog="homeCustomize"]').click();assert(await page.locator('#homeCustomize').isVisible());await page.keyboard.press('Escape');
  await noOverflow();assert.deepEqual(errors,[]);
  await page.screenshot({path:'/tmp/home-calendar-'+lang+'-'+width+'.png',fullPage:true});
  console.log('PASS',lang,width,theme,'merged calendar, cutoff, account visits, clear, keyboard, retry, layout');await page.close();
 }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
