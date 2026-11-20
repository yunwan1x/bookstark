const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const origin=process.env.BOOKSTARK_TEST_ORIGIN;
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({serviceWorkers:'block',viewport:{width:1440,height:1000}});
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 try {
  await page.goto(origin+'/shares');
  assert.equal(await page.locator('.public-entry').count(),15);
  await page.locator('.public-pagination a').last().click();assert.equal(await page.locator('.public-entry').count(),2);
  await page.locator('.public-categories a').nth(1).click();assert.equal(new URL(page.url()).searchParams.get('page'),'1');
  assert.equal(new URL(page.url()).searchParams.get('label'),'工具');
  await page.locator('#publicSearch [name=keyword]').fill('Workspace article 03');
  await page.locator('.public-search-submit').click();
  assert.equal(await page.locator('.public-entry').count(),1);
  assert.ok((await page.locator('.public-entry').innerText()).includes('article 03'));
  await page.locator('.public-feed-tabs a').nth(1).click();
  assert.equal(new URL(page.url()).searchParams.get('keyword'),'Workspace article 03');
  assert.equal(new URL(page.url()).searchParams.get('label'),'工具');
  await page.locator('#publicSearch [name=keyword]').fill('no-matching-record');await page.locator('.public-search-submit').click();await page.locator('.public-empty').waitFor();
  await page.goto(origin+'/shares?type=note&sort=updated');
  const loginHref=await page.locator('.public-login').getAttribute('href');
  assert.equal(new URL(loginHref,origin).searchParams.get('next'),'/shares?type=note&sort=updated');
  await page.locator('.public-login').click();assert.ok(await page.evaluate(()=>Boolean(sessionStorage.getItem('bookstark:public-login-return'))));
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
  await page.goto(origin+'/shares?type=article&keyword=Workspace%20article%2003');
  await page.locator('.public-manage summary').click();
  await page.locator('[data-public-action=pin]').click();await page.locator('.public-pinned').waitFor();
  const menu=page.locator('.public-manage');await menu.locator('summary').click();
  await page.locator('[data-public-action=unpublish]').click();
  await page.locator('#bs-confirm-ok').click();
  await page.locator('.public-empty').waitFor();
  await context.clearCookies();await page.reload();assert.equal(await page.locator('.public-entry').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS real server: tabs, pagination, search, category/sort retention, empty state, login return, account menu, note viewer, bookmark domain, pin/unpublish, 320–1440px.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
