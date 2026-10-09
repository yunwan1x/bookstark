// Production smoke check: reads only, except an explicitly requested default-home preference update.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const origin=process.env.BOOKSTARK_TEST_ORIGIN || 'https://books.vs2010wy.top';
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
  const page=await context.newPage();page.setDefaultTimeout(120000);page.setDefaultNavigationTimeout(120000);
  if(process.env.BOOKSTARK_TEST_LOCAL_HOME==='1')await page.route('**/static/js/home.js*',route=>route.fulfill({path:require('node:path').join(__dirname,'static/js/home.js'),contentType:'application/javascript'}));
  page.on('pageerror',e=>console.error('PAGE ERROR',e.message));
  try {
    const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(login.status(),200);
    if(process.env.BOOKSTARK_SET_HOME==='1') {
      await context.request.get(origin+'/api/csrf-token');
      const profile=(await (await context.request.get(origin+'/api/profile')).json()).data;
      const cookie=(await context.cookies(origin)).find(c=>c.name==='csrf_token');
      const result=await context.request.put(origin+'/api/profile',{headers:{'X-CSRF-Token':cookie.value},data:{email:profile.email,default_home:'home'}});
      assert.equal(result.status(),200);assert.equal((await result.json()).code,0);
    }
    const response=await context.request.get(origin+'/api/home');assert.equal(response.status(),200);
    assert.ok(response.headers()['cache-control'].includes('no-store'));
    const data=await response.json();assert.equal(data.code,0);
    for(const section of data.sections)assert.ok(section.items.length<=10);
    console.log('Production homepage OK. Counts:',data.sections.map(s=>s.key+':'+s.total).join(', '));
    await page.goto(origin+'/',{waitUntil:'domcontentloaded'});console.log('Opened',page.url(),await page.title());await page.waitForSelector('.home-card');
    await page.locator('#main-nav a[href="/home"]').waitFor({state:'visible'});
    await page.screenshot({path:'/tmp/bookstark-home-desktop.png',fullPage:true});
    await page.setViewportSize({width:390,height:844});
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:'/tmp/bookstark-home-mobile.png'});
    await page.locator('.home-bottom-nav [data-home-dialog=homeMore]').click();await page.locator('#homeMore').waitFor({state:'visible'});
    await page.screenshot({path:'/tmp/bookstark-home-mobile-menu.png'});
    await page.keyboard.press('Escape');
    await page.evaluate(()=>document.documentElement.setAttribute('data-theme','dark'));
    await page.screenshot({path:'/tmp/bookstark-home-mobile-dark.png'});
    console.log('PASS production desktop/mobile/menu/dark screenshots; no test records created.');
  } catch(e) {console.error('Failed page',page.url(),await page.locator('body').innerText().catch(()=>''));await page.screenshot({path:'/tmp/bookstark-home-smoke-failure.png'}).catch(()=>{});throw e;}
  finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
