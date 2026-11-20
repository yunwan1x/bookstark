const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const origin = process.env.BOOKSTARK_TEST_ORIGIN;
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox']});
  const context = await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
  const page = await context.newPage();
  if (process.env.BOOKSTARK_TEST_LOCAL_HOME === '1') await page.route('**/static/js/home.js*',route=>route.fulfill({path:require('node:path').join(__dirname,'static/js/home.js'),contentType:'application/javascript'}));
  page.setDefaultTimeout(30000);
  page.setDefaultNavigationTimeout(30000);
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  async function api(path,body) {
    const c=(await context.cookies(origin)).find(c=>c.name==='csrf_token');
    const r=await context.request.post(origin+path,{headers:{'X-CSRF-Token':c?.value||''},data:body});
    const data=await r.json(); assert.equal(data.code,0,JSON.stringify(data)); return data.data;
  }
  try {
    const r=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(r.status(),200);
    if(process.env.BOOKSTARK_HOME_RETRY_ONLY==='1') {
      let calls=0;
      await page.route('**/api/home?*',route=>++calls===1?route.abort('failed'):route.continue());
      await page.goto(origin+'/',{waitUntil:'domcontentloaded'});await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');assert.equal(calls,2,'network failure retries exactly once');
      await page.unroute('**/api/home?*');calls=0;
      await page.route('**/api/home?*',route=>{calls++;return route.fulfill({status:500,contentType:'application/json',body:JSON.stringify({code:500,message:'server error'})});});
      await page.locator('[data-home-sort=created]').click();await page.locator('#homeRetry').waitFor({state:'visible'});assert.equal(calls,1,'HTTP errors do not auto retry');
      await page.unroute('**/api/home?*');calls=0;
      await page.route('**/api/home?*',route=>{calls++;return route.abort('failed');});
      await page.locator('#homeRetry').click();await page.locator('#homeRetry').waitFor({state:'visible'});assert.equal(calls,2,'persistent network error stops after two attempts');
      await page.unroute('**/api/home?*');await page.locator('#homeRetry').click();await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
      await context.clearCookies();await page.locator('[data-home-sort=updated]').click();await page.waitForURL('**/login');
      assert.deepEqual(errors,[]);console.log('PASS read-only retry limit, HTTP errors, manual retry and session expiry');return;
    }
    await page.goto(origin+'/');
    await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    assert.equal(await page.locator('.home-card').count(),9);
    assert.equal(await page.locator('#homeGrid .home-empty').count(),9);
    for(let i=0;i<12;i++) await api('/api/blogs',{blog_title:'首页测试笔记 '+i+' <img src=x onerror=alert(1)>',blog_type:'note',blog_content:'首页测试正文',visibility:0});
    const task=await api('/api/tasks',{content:'首页测试待办'});
    const article=await api('/api/blogs',{blog_title:'首页测试文章',blog_type:'article',blog_content:'文章内容',visibility:0});
    const book=await api('/api/books',{book_name:'首页测试书籍'});
    const topic=await api('/api/topics',{title:'首页测试专题'});
    const bookmark=await api('/api/bookmarks',{title:'首页测试书签',url:'https://example.com',favicon:'/static/favicon.ico'});
    await page.reload();
    await page.waitForSelector('[data-section=notes] .home-row');
    assert.equal(await page.locator('[data-section=notes] .home-row').count(),10);
    assert.equal(await page.locator('[data-section=notes] img').count(),0);
    assert.equal(await page.locator('[data-home-stat=notes]').innerText(),'12');
    assert.equal(await page.locator('[data-home-stat=pending_tasks]').innerText(),'1');
    await page.locator('[data-home-filter=tasks]').click();
    assert.equal(await page.locator('#homeGrid .home-card').count(),1);
    assert.equal(await page.locator('#homeGrid .home-card').getAttribute('data-section'),'tasks');
    await page.locator('[data-home-filter=all]').click();
    await page.locator('#homeSearch').fill('首页测试');
    await page.locator('#homeSearch').press('Enter');
    await page.waitForURL('**/search?q=*');
    assert.equal(new URL(page.url()).searchParams.get('q'),'首页测试');
    await page.goto(origin+'/home'); await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    for(const id of [1,2,3,4]) assert.equal((await context.request.get(origin+'/api/blogs/'+id)).status(),200);
    await page.reload();await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    assert.equal(await page.locator('#homeRecentList a:visible').count(),3);
    const columns=()=>page.locator('#homeGrid').evaluate(n=>getComputedStyle(n).gridTemplateColumns.split(' ').length);
    assert.equal(await columns(),2);
    await page.locator('#main-nav a[href="/home"]').waitFor({state:'visible'});
    console.log('PASS desktop data and columns');
    await page.screenshot({path:'/tmp/bookstark-home-desktop-test.png',fullPage:true});
    await page.setViewportSize({width:820,height:1180});assert.equal(await columns(),2);
    for(const width of [320,375,390,640]) {
      await page.setViewportSize({width,height:844});assert.equal(await columns(),1);
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'horizontal overflow '+width);
      assert.equal(await page.locator('[data-section=notes] li:visible').count(),3);
    }
    await page.setViewportSize({width:390,height:844});
    await page.locator('[data-section=notes] .home-expand').click();assert.equal(await page.locator('[data-section=notes] li:visible').count(),10);
    await page.locator('[data-section=notes] .home-expand').click();assert.equal(await page.locator('[data-section=notes] li:visible').count(),3);
    await page.locator('.home-bottom-nav [data-home-dialog=homeMore]').click();await page.locator('#homeMore a[href="/topics"]').waitFor({state:'visible'});
    await page.keyboard.press('Escape');
    await page.locator('[data-home-dialog=homeCustomize]').click();await page.locator('#homePreferences input').first().uncheck();
    await page.locator('#homeCustomize button.home-primary').click();await page.locator('#homeCustomize').waitFor({state:'hidden'});assert.equal(await page.locator('[data-section=notes]').count(),0);
    await page.reload();await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');assert.equal(await page.locator('[data-section=notes]').count(),0);
    await page.locator('[data-home-dialog=homeCustomize]').click();await page.locator('#homePreferences input').first().check();await page.locator('#homeLayoutSave').click();await page.locator('#homeCustomize').waitFor({state:'hidden'});
    await page.screenshot({path:'/tmp/bookstark-home-mobile-test.png',fullPage:true});
    await page.evaluate(()=>document.documentElement.setAttribute('data-theme','dark'));
    await page.screenshot({path:'/tmp/bookstark-home-dark-test.png',fullPage:true});
    await page.evaluate(()=>document.documentElement.setAttribute('data-theme','light'));
    await page.locator('.home-bottom-nav [data-home-dialog=homeCreate]').click();
    await page.locator('#homeCreate a[href="/notes?command=new-note"]').waitFor({state:'visible'});await page.keyboard.press('Escape');
    const noteID=new URL(await page.locator('[data-section=notes] .home-row').first().getAttribute('href'),origin).searchParams.get('id');
    console.log('Opening note',noteID);
    await page.locator('[data-section=notes] .home-row').first().click({noWaitAfter:true});await page.waitForSelector('.note-card[data-id="'+noteID+'"]');
    console.log('PASS responsive layout, dialogs, preferences and note deep link');
    await page.goto(origin+'/home');await page.waitForSelector('[data-section=tasks] .home-row');
    assert.ok((await page.locator('[data-section=tasks] .home-row').first().getAttribute('href')).includes('task_id='+task.task_id));
    await page.locator('[data-section=tasks] .home-row').first().click();await page.waitForSelector('[data-task-id="'+task.task_id+'"]');
    await page.goto(origin+'/home');await page.waitForSelector('[data-section=articles] .home-row');await page.locator('[data-section=articles] .home-row').first().click();await page.waitForSelector('.article-card');
    for (const section of ['books','topics','bookmarks']) {
      await page.goto(origin+'/home');await page.waitForSelector('[data-section='+section+'] .home-row');
      const href=await page.locator('[data-section='+section+'] .home-row').first().getAttribute('href');
      if(section==='bookmarks') assert.equal(href,'https://example.com');
      else assert.equal((await context.request.get(origin+href)).status(),200,'record destination '+section);
    }
    await page.goto(origin+'/home');await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    for(const lang of ['zh','en']) {
      await context.addCookies([{name:'lang',value:lang,url:origin}]);
      await page.goto(origin+'/home');await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
      assert.equal(await page.locator('html').getAttribute('lang'),lang);
      assert.equal(await page.locator('.home-welcome h1').innerText(),lang==='en'?'A clear space for your ideas.':'让思考，井然有序。');
      if(lang==='en') assert.ok(!/[\u4e00-\u9fff]/.test(await page.locator('.home-welcome').innerText()));
      for(const theme of ['light','nvidia','apple']) {
        await page.evaluate(theme=>window.BookStarkTheme.apply(theme),theme);
        await page.waitForTimeout(150);
        assert.equal(await page.locator('html').getAttribute('data-theme-style'),theme);
        const colors=await page.locator('.home-primary').first().evaluate(n=>{const s=getComputedStyle(n),r=getComputedStyle(document.documentElement);return [s.backgroundColor,s.color,r.getPropertyValue('--color-primary').trim(),r.getPropertyValue('--color-on-primary').trim()];});
        assert.notEqual(colors[0],colors[1]);
        function luminance(color) {
          const rgb=color.match(/[\d.]+/g).slice(0,3).map(Number).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4;});
          return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;
        }
        const light=luminance(colors[0]),dark=luminance(colors[1]);
        assert.ok((Math.max(light,dark)+.05)/(Math.min(light,dark)+.05)>=4.5,'primary button contrast '+theme);
        for(const width of [320,390,820,1440]) {
          await page.setViewportSize({width,height:1000});
          assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'overflow '+lang+' '+theme+' '+width);
          assert.ok(await page.locator('.home-search').evaluate(n=>n.getBoundingClientRect().right<=innerWidth));
        }
        await page.screenshot({path:'/tmp/bookstark-white-'+lang+'-'+theme+'.png',fullPage:true});
        await page.setViewportSize({width:390,height:844});
        await page.screenshot({path:'/tmp/bookstark-white-'+lang+'-'+theme+'-mobile.png',fullPage:true});
      }
      await page.locator('[data-home-view=week]').scrollIntoViewIfNeeded();
      await page.screenshot({path:'/tmp/bookstark-white-calendar-'+lang+'.png'});
      await page.locator('[data-home-view=week]').click();await page.waitForSelector('#homeGrid[aria-busy=false]');
      assert.equal(await page.locator('#homeCalendarDays').getAttribute('data-view'),'week');
      await page.locator('[data-home-view=month]').click();await page.waitForSelector('#homeGrid[aria-busy=false]');
      assert.equal(await page.locator('#homeCalendarDays button').count(),12);
      await page.locator('[data-home-view=day]').click();await page.waitForSelector('#homeGrid[aria-busy=false]');
      await page.locator('#homeCalendarDays [data-date]').first().click();await page.waitForSelector('#homeGrid[aria-busy=false]');
      assert.equal(await page.locator('[data-home-stat=notes]').innerText(),'12','date cutoff must not change totals');
      await page.locator('#homeClearDate').click();await page.waitForSelector('#homeGrid[aria-busy=false]');
    }
    await context.addCookies([{name:'lang',value:'zh',url:origin}]);
    await page.goto(origin+'/home');await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    console.log('PASS real statistics, global search, module filters, date views, two languages and three themes at 320/390/820/1440px');
    await page.route('**/api/home?*',route=>route.fulfill({status:500,contentType:'application/json',body:JSON.stringify({code:500,message:'测试加载错误'})}));
    await page.locator('[data-home-sort=created]').click();await page.locator('#homeRetry').waitFor({state:'visible'});assert.equal(await page.locator('.home-card').count(),0);
    assert.ok((await page.locator('#homeStatus').innerText()).includes('首页加载失败'));
    await page.unroute('**/api/home?*');await page.locator('#homeRetry').click();await page.waitForSelector('#homeGrid[aria-busy=false] .home-card');
    await context.clearCookies();await page.locator('[data-home-sort=updated]').click();await page.waitForURL('**/login');
    assert.deepEqual(errors,[]);
    console.log('PASS: home auth, empty state, sorting, 10/3 limits, responsive 320–1440, expand, preferences, XSS, record links, error/retry and session expiry');
  } catch(e) { console.error('Browser test failed at',page.url(),e); throw e; }
  finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
