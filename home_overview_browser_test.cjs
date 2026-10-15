// Real rendered templates and local assets, mocked API: never writes production data.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage']});
 try {
 for(const lang of ['zh','en'])for(const [width,theme] of [[1440,'light'],[1280,'dark'],[768,'light'],[390,'light'],[320,'dark']]){
  if(process.env.HOME_TEST_LANG&&process.env.HOME_TEST_LANG!==lang)continue;
  if(process.env.HOME_TEST_WIDTH&&Number(process.env.HOME_TEST_WIDTH)!==width)continue;
  const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];let calls=0,fail=false,release,lastQuery;
  const pending=new Promise(resolve=>release=resolve);
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(t=>localStorage.setItem('bookstark-theme',t),theme);
  await page.route('**/*',route=>new URL(route.request().url()).hostname==='home.test'?route.fallback():route.abort());
  await page.route('http://home.test/**',async route=>{
   const u=new URL(route.request().url());
   if(u.pathname.startsWith('/static/'))return route.fulfill({path:'.'+u.pathname});
   if(u.pathname==='/api/home'){calls++;lastQuery=u.searchParams;await pending;return route.fulfill({json:fail?{code:500}:{code:0,activity:{'2026-10-14':3,'2026-10-07':9},activity_start:'2026-07-27',activity_end:'2026-10-15',sections:['notes','articles','tasks'].map(key=>({key,total:1,dates:[u.searchParams.get('end')],items:[{title:'Example',url:'/notes',date:u.searchParams.get('end')}]})),layout:null},status:fail?500:200});}
   if(u.pathname==='/home')return route.fulfill({contentType:'text/html',body:fs.readFileSync('/tmp/home-b1-'+lang+'.html','utf8')});
   return route.fulfill({status:404,body:''});
  });
  await page.goto('http://home.test/home');await page.locator('.home-loading-card').first().waitFor();
  assert.equal(await page.locator('#homeGrid').getAttribute('aria-busy'),'true');
  assert.equal(await page.locator('#headerCreateTrigger').count(),0);
  assert.equal(await page.locator('#main-nav > a[href="/shares"]').textContent(),lang==='zh'?'广场':'Community');
  release();await page.locator('.home-card:not(.home-loading-card)').first().waitFor();
  assert.equal(await page.locator('.home-loading-card').count(),0);
  assert.equal(await page.locator('[data-home-stat]').count(),0);
  assert.equal(lastQuery.get('start'),lastQuery.get('end'));assert.equal(lastQuery.get('limit'),'10');
  assert.equal(lastQuery.get('start'),'');
  assert.equal(await page.locator('.calendar-day.selected').count(),0);
  assert.equal(await page.locator('[data-home-range="1"]').count(),0);
  assert.equal(await page.locator('#homeRangeForm').isVisible(),false);
  assert.equal(await page.locator('#homeSelectedDate').textContent(),lang==='zh'?'最近内容':'Recent content');
  assert.equal(await page.locator('.home-eyebrow').count(),0);
  assert(await page.locator('.home-heading-card [data-home-dialog="homeCreate"]').isVisible());
  const overflow=await page.evaluate(()=>({ok:document.documentElement.scrollWidth<=innerWidth,items:[...document.querySelectorAll('body *')].filter(n=>n.getBoundingClientRect().right>innerWidth+1).map(n=>({class:n.className,right:n.getBoundingClientRect().right})).slice(0,12)}));
  assert(overflow.ok,'overflow '+lang+' '+width+' '+JSON.stringify(overflow.items));
  assert.equal(await page.locator('#homeCalendar').isVisible(),width>640);
  if(width<=640){await page.locator('#homeCalendarToggle').click();assert(await page.locator('#homeCalendar').isVisible());await page.locator('#homeCalendarToggle').press('Escape');await page.locator('#homeCalendarToggle').click();assert.equal(await page.locator('#homeCalendar').isVisible(),false);}
  const ready=()=>page.waitForFunction(()=>document.querySelector('#homeGrid').getAttribute('aria-busy')==='false');
  assert.equal(await page.locator('#homeActivity').isVisible(),width>=1280);
  assert.equal(await page.locator('.home-date-controls #homeRangeForm').count(),0,'no inline date inputs');
  if(width>=1280){
   const heights=await page.evaluate(()=>({height:document.querySelector('.home-date-layout').getBoundingClientRect().height,bottoms:['homeCalendar','homeActivity'].map(id=>document.getElementById(id).getBoundingClientRect().bottom)}));
   assert(heights.height<330,'header should stay compact: '+JSON.stringify(heights));
   assert(Math.abs(heights.bottoms[0]-heights.bottoms[1])<2,'calendar and heatmap bottoms aligned');
  }
  assert.equal(await page.locator('#homeHeatmap button').count(),84);
  if(width>=1280){
   const hot=page.locator('[data-heat-date="2026-10-14"]');
   assert.equal(await hot.getAttribute('data-level'),'2');assert((await hot.getAttribute('aria-label')).includes('3'));
   assert.equal(await page.locator('[data-heat-date="2026-10-16"]').isDisabled(),true);
   await hot.click();await ready();assert.equal(lastQuery.get('start'),'2026-10-14');assert.equal(lastQuery.get('end'),'2026-10-14');
   assert.equal(await hot.getAttribute('aria-pressed'),'true');assert(await page.locator('#homeCalendarDays [data-date="2026-10-14"]').evaluate(n=>n.classList.contains('selected')));
   await page.locator('[data-heat-date="2026-10-07"]').focus();await page.keyboard.press('ArrowRight');assert.equal(await page.locator(':focus').getAttribute('data-heat-date'),'2026-10-14');
   await page.locator('[data-home-range="all"]').click();await ready();assert.equal(await hot.getAttribute('aria-pressed'),'false');
  }
  await page.locator('[data-home-range="7"]').click();await ready();assert.equal((new Date(lastQuery.get('end'))-new Date(lastQuery.get('start')))/86400000,6);
  await page.locator('#homeLimit').selectOption('20');await ready();assert.equal(lastQuery.get('limit'),'20');
  const beforeDialog=calls,previousStart=lastQuery.get('start');
  await page.locator('[data-home-range="custom"]').click();assert(await page.locator('#homeDateDialog').isVisible());await page.locator('#homeStart').fill('2026-10-01');await page.keyboard.press('Escape');assert.equal(await page.locator('#homeDateDialog').isVisible(),false);assert.equal(calls,beforeDialog,'cancelling must not fetch');assert.equal(lastQuery.get('start'),previousStart,'cancelling must not change filter');
  await page.locator('[data-home-range="custom"]').click();await page.locator('#homeStart').fill('2026-10-01');await page.locator('#homeEnd').fill('2026-10-15');await page.locator('#homeRangeApply').click();await ready();assert.equal(lastQuery.get('start'),'2026-10-01');assert.equal(lastQuery.get('end'),'2026-10-15');assert.equal(await page.locator('#homeDateDialog').isVisible(),false);assert((await page.locator('#homeSelectedDate').textContent()).includes('2026/10/01'));
  if(width<=640)await page.locator('#homeCalendarToggle').click();
  await page.locator('#homeCalendarDays [data-date="2026-10-12"]').click();await ready();assert.equal(lastQuery.get('start'),'2026-10-12');assert.equal(lastQuery.get('end'),'2026-10-12');
  const currentRange=lastQuery.get('start');await page.locator('#homePrevMonth').click();await ready();assert.equal(lastQuery.get('month'),'2026-09');assert.equal(lastQuery.get('start'),currentRange,'browsing month must not change selected range');
  await page.locator('[data-home-range="all"]').click();await ready();assert.equal(lastQuery.get('start'),'');assert.equal(lastQuery.get('end'),'');assert.equal(await page.locator('.calendar-day.selected').count(),0);assert.equal(await page.locator('#homeRangeForm').isVisible(),false);
  await page.locator('[data-home-today]').filter({visible:true}).first().click();await ready();
  if(width<=640)await page.locator('#homeCalendarToggle').click();
  const sort=page.locator('[data-home-sort="created"]');await sort.click();await ready();assert.equal(lastQuery.get('order'),'created');
  assert.equal(await sort.getAttribute('aria-pressed'),'true');assert((await sort.getAttribute('class')).includes('active'));
  assert.equal(await sort.evaluate(n=>getComputedStyle(n).borderBottomWidth),'2px');
  assert.notEqual(await sort.evaluate(n=>getComputedStyle(n).color),await sort.evaluate(n=>getComputedStyle(n).backgroundColor));
  const before=calls;await sort.click();assert.equal(calls,before,'selected sort must not reload');
  fail=true;await page.locator('[data-home-sort="updated"]').click();await page.locator('#homeRetry').waitFor({state:'visible'});
  assert.equal(await page.locator('.home-card').count(),0);
  fail=false;await page.locator('#homeRetry').click();await page.locator('.home-card:not(.home-loading-card)').first().waitFor();
  await page.locator('.home-heading-card [data-home-dialog="homeCustomize"]').click();assert(await page.locator('#homeCustomize').isVisible());await page.keyboard.press('Escape');
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'overflow after date filtering');
  await page.screenshot({path:'/tmp/home-calendar-'+lang+'-'+width+'.png'});assert.deepEqual(errors,[]);console.log('PASS',lang,width,theme,'calendar, date range, limit, sort, retry, layout dialog');await page.close();
 }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
