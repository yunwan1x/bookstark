const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const origin=process.env.BOOKSTARK_TEST_ORIGIN;
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:1400,height:1050}});
 const p=await context.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 async function api(path,method='GET',body){await context.request.get(origin+'/api/csrf-token');const token=(await context.cookies(origin)).find(c=>c.name==='csrf_token');return context.request.fetch(origin+path,{method,headers:{'X-CSRF-Token':token?.value||''},...(body===undefined?{}:{data:body})})}
 try{
  assert.equal((await context.request.get(origin+'/api/admin/tv/world')).status(),401);
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(login.status(),200);
  await p.goto(origin+'/admin/system?tab=tv&tvtab=world');await p.waitForFunction(()=>document.getElementById('wtv-count').textContent.includes('3 个频道'));
  assert.equal(await p.locator('#tv-world').isVisible(),true);assert.equal(await p.locator('#tv-domestic').isVisible(),false);
  assert.equal(await p.locator('#wtv-auto').isChecked(),true);
  await p.selectOption('#wtv-country','日本');assert.equal(await p.locator('#wtv-world-list button').count(),2);
  await p.locator('#wtv-world-search').fill('no-result');assert.equal(await p.locator('#wtv-try').isDisabled(),true);assert.equal(await p.locator('#wtv-open').isVisible(),false);
  await p.locator('#wtv-world-search').fill('<img');assert.equal(await p.locator('#wtv-world-list img').count(),0);assert.equal(await p.locator('#wtv-try').isDisabled(),true);assert.equal(await p.locator('#wtv-open').getAttribute('href'),'https://www.youtube.com/@test/live');
  await p.locator('#wtv-world-search').fill('');await p.selectOption('#wtv-country','');
  await p.locator('#wtv-auto').uncheck();await p.locator('#wtv-save').click();await p.waitForFunction(()=>document.getElementById('wtv-saved').textContent==='配置已保存');await p.reload();await p.waitForFunction(()=>!document.getElementById('wtv-auto').disabled);assert.equal(await p.locator('#wtv-auto').isChecked(),false);
  const stored=(await (await api('/api/admin/tv/world')).json()).data.state;assert.equal(stored.config.enabled,false);assert(stored.nextRun.startsWith('0001'));
  assert.equal((await api('/api/admin/tv/world','PUT',{source:'https://127.0.0.1/x',enabled:true,intervalHours:6})).status(),400);
  assert.equal((await api('/api/admin/settings','PUT',{world_tv_state:'{}'})).status(),400);
  assert.equal((await context.request.put(origin+'/api/admin/tv/world',{data:stored.config,headers:{'X-CSRF-Token':'wrong'}})).status(),403);
  await p.locator('#wtv-source').fill('https://example.invalid/list.m3u');assert.equal(await p.locator('#wtv-pull').isDisabled(),true);await p.locator('#wtv-save').click();await p.waitForFunction(()=>!document.getElementById('wtv-pull').disabled);await p.locator('#wtv-pull').click();await p.waitForFunction(()=>document.getElementById('wtv-error').textContent.includes('拉取失败'),{},{timeout:75000});assert.equal(await p.locator('#wtv-world-list button').count(),3);
  const publicCatalog=await context.request.get(origin+'/upload-files/worldtv/channels.json');assert.equal(publicCatalog.headers()['cache-control'],'no-store');assert.equal((await publicCatalog.json()).channels.length,3);
  // Real preview frame mounts and is torn down when changing tabs; no media fetches.
  await p.route('**/static/tv-preview/player.html',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><title>Isolated preview</title>'}));
  await p.locator('#wtv-try').click();assert.equal(await p.locator('#wtv-preview-world iframe').count(),1);await p.locator('#tv-domestic-tab').click();assert.equal(await p.locator('#wtv-preview-world iframe').count(),0);await p.waitForFunction(()=>document.getElementById('tv-name').textContent.includes('CCTV'));
  await p.locator('#tv-search').fill('CCTV-2');assert.equal(await p.locator('#tv-list button').count(),1);
  await p.locator('#tv-world-tab').click();
  for(const width of [1400,390]){await p.setViewportSize({width,height:1000});assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'horizontal overflow '+width)}
  await p.setViewportSize({width:1400,height:1050});
  if(process.env.BOOKSTARK_TEST_ARTIFACT_DIR){fs.mkdirSync(process.env.BOOKSTARK_TEST_ARTIFACT_DIR,{recursive:true});await p.screenshot({path:process.env.BOOKSTARK_TEST_ARTIFACT_DIR+'/world-tv-test.png',fullPage:true})}
  assert.deepEqual(errors,[]);console.log('PASS world TV: auth/CSRF, migration, filters/XSS, persistence, failure preservation, public cache, preview cleanup, domestic regression, mobile');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
