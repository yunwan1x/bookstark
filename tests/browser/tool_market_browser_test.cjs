const {chromium}=require('playwright');const assert=require('node:assert/strict');const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});const origin=process.env.BOOKSTARK_TEST_ORIGIN,out=process.env.BOOKSTARK_SCREENSHOT_DIR||'/tmp/bookstark-market-aligned';fs.mkdirSync(out,{recursive:true});
 const context=await browser.newContext({viewport:{width:1440,height:1050},permissions:['clipboard-read','clipboard-write']});
 await context.addInitScript(()=>{if(window===top&&navigator.serviceWorker)navigator.serviceWorker.register=()=>new Promise(()=>{});});
 await context.addCookies([{name:'lang',value:'zh',url:origin}]);const page=await context.newPage(),errors=[];page.on('pageerror',err=>errors.push(err.message));
 const api=async(path,method='GET',data)=>{const csrf=(await(await context.request.get(origin+'/api/csrf-token')).json()).csrf_token;const response=await context.request.fetch(origin+path,{method,headers:{'X-CSRF-Token':csrf},data});assert.equal(response.ok(),true,await response.text());return response.json();};
 async function until(fn){const deadline=Date.now()+20000;while(!await fn()){if(Date.now()>deadline)throw Error('Timed out waiting for persisted tool state');await new Promise(resolve=>setTimeout(resolve,80));}}
 const act=(a,id)=>page.locator(`[data-market-action="${a}"][data-id="${id}"]:visible`).first();
 try{
  await page.goto(origin+'/market');await page.locator('.market-empty').waitFor();
  assert.equal(await page.locator('#marketSource').count(),0,'obsolete source form removed');
  assert.equal(await page.locator('#marketPublish,#marketSettings,#marketCatalogTab,#marketInstalledTab,.market-switch').count(),0,'guest and nested controls must be absent');
  assert.equal(await page.locator('#marketMain>.public-nav').count(),1);assert.equal(await page.locator('#marketMain>.public-nav a[aria-current]').textContent().then(x=>x.trim()),'工具');
  const signedIn=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(signedIn.status(),200);
  await page.goto(origin+'/admin/tool-market');await page.locator('#marketAdminForm input[name="name"]').waitFor();
  await page.locator('input[name="name"]').fill('我的工具市场');await page.locator('#marketAdminForm button[type="submit"]').click();await page.getByText('设置已保存',{exact:true}).waitFor();
  await page.getByRole('button',{name:'复制市场地址',exact:true}).click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),origin+'/market');
  await page.screenshot({path:out+'/01-server-market.png',fullPage:true});
  await page.goto(origin+'/market');await page.locator('#marketPublish').click();await page.locator('dialog a[href^="/market/publish/"]').first().waitFor();
  const candidates=await api('/api/tool-market/articles');const id=candidates.articles.find(x=>x.title==='Craft 白板').id;
  await page.screenshot({path:out+'/publish-02-article-picker.png'});
  await page.locator(`dialog a[href="/market/publish/${id}"]`).click();await page.waitForURL('**/market/publish/'+id);await page.locator('#toolPublishForm input[name="title"]').waitFor();
  await page.locator('input[name="title"]').fill('PDF 工具箱');await page.locator('select[name="category"]').selectOption('document');await page.locator('textarea[name="notes"]').fill('首次发布，原始资源在安装时下载。');
  await page.locator('select[name="access"]').selectOption('members');await page.locator('input[name="members"]').fill('admin');
  await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:out+'/02-publish-article.png',fullPage:true});
  await page.getByRole('button',{name:'检查资源',exact:true}).click();await page.getByRole('heading',{name:'资源检查结果',exact:true}).waitFor();
  await page.screenshot({path:out+'/publish-04-resource-check.png'});await page.getByRole('button',{name:'关闭',exact:true}).click();
  await page.locator('#toolPublishForm button[type="submit"]').click();await page.locator('#publishStatus').filter({hasText:'发布成功'}).waitFor();
  await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:out+'/publish-05-success.png',fullPage:true});
  const catalog=(await api('/api/tool-market')).tools;const tool=catalog.find(x=>x.id===id);assert.equal(tool.version,'1.0.0');assert.equal(tool.asset_count,4);assert.equal(tool.offline,true);
  assert.equal((await context.request.get(origin+'/api/tool-market/'+id)).status(),200);
  const guest=await browser.newContext();assert.equal((await guest.request.get(origin+'/api/tool-market/'+id)).status(),401);await guest.close();
  await page.goto(origin+'/market?selected='+id);await page.locator('.market-card').waitFor();await page.locator('#marketDetail .market-install').waitFor();await page.screenshot({path:out+'/03-market-and-detail.png',fullPage:true});
  await act('install',id).click();await page.locator('dialog[open]').waitFor();assert.match(await page.locator('dialog').textContent(),/需要使用的能力/);await page.getByRole('button',{name:/^确认安装/}).click();await until(async()=>(await api('/api/tool-installs')).tools.length===1);
  await page.goto(origin+'/market?open='+id);const frame=page.frameLocator('#marketFrameHost iframe');await frame.locator('#value').waitFor();await frame.locator('#value').fill('keep this');await frame.locator('#save').click();
  await until(async()=>(await api('/api/tool-installs/'+id+'?part=data')).values.value==='keep this');
  assert.equal(await frame.locator('body').evaluate(()=>{try{return parent.document.body.tagName;}catch(_){return 'isolated';}}),'isolated');
  await frame.locator('body').evaluate(async()=>{await BookStark.files.write('notes/saved.txt','saved file');});
  assert.equal(await frame.locator('body').evaluate(async()=>new TextDecoder().decode(await BookStark.files.read('notes/saved.txt'))),'saved file');
  assert.equal(await frame.locator('body').evaluate(()=>window.marketStaticLoaded),true);await page.waitForFunction(()=>true);assert.equal(await frame.locator('body').evaluate(()=>window.marketModule),42);
  // One list supports state/category/search/sort, pagination and list view.
  const mockTools=[{...tool,revision:'available-update'},...Array.from({length:20},(_,i)=>({...tool,id:1000+i,title:'筛选工具 '+String(i).padStart(2,'0'),category:i%2?'image':'document',size:1024+i,updated:1000+i}))];
  await page.route(origin+'/api/tool-market',route=>route.fulfill({json:{tools:mockTools,market:{name:'我的工具市场'}}}));
  await page.goto(origin+'/market');await until(async()=>await page.locator('.market-card').count()===12);assert.equal(await page.locator('#marketResultCount').textContent(),'21 个结果');
  await page.locator('#marketCategory').selectOption('image');assert.equal(await page.locator('.market-card').count(),10);
  await page.locator('#marketQuery').fill('工具 03');assert.equal(await page.locator('.market-card').count(),1);assert.equal(await page.locator('.market-card').getAttribute('data-tool-id'),'1003');
  await page.locator('#marketQuery').fill('');await page.locator('#marketCategory').selectOption('all');await page.locator('#marketState').selectOption('installed');assert.equal(await page.locator('.market-card').count(),1);
  await page.locator('#marketState').selectOption('updates');assert.equal(await page.locator('.market-card').count(),1);await page.locator('.market-install-state.has-update').waitFor();
  await page.locator('#marketState').selectOption('uninstalled');assert.equal(await page.locator('#marketResultCount').textContent(),'20 个结果');
  await page.locator('#marketSort').selectOption('size');assert.equal(await page.locator('.market-card').first().getAttribute('data-tool-id'),'1000');
  await page.locator('#marketPagination [data-page="2"]').first().click();assert.equal(await page.locator('.market-card').count(),8);
  await page.locator('#marketListView').click();assert.equal(await page.locator('#marketItems').evaluate(el=>el.classList.contains('is-list')),true);await page.reload();await until(async()=>await page.locator('.market-card').count()===8);assert.equal(await page.locator('#marketState').inputValue(),'uninstalled');
  await page.locator('#marketPageSize').selectOption('24');assert.equal(await page.locator('.market-card').count(),20);
  await page.screenshot({path:out+'/07-flat-list-view.png',fullPage:true});
  await page.locator('#marketGridView').click();await page.locator('#marketPageSize').selectOption('12');await page.locator('#marketState').selectOption('all');await page.locator('#marketSort').selectOption('updated');await page.screenshot({path:out+'/08-flat-tools-grid.png',fullPage:true});
  await page.unroute(origin+'/api/tool-market');
  const viewer=await browser.newContext();await viewer.addCookies([{name:'lang',value:'zh',url:origin}]);assert.equal((await viewer.request.post(origin+'/api/login',{data:{account:'tools-viewer',password:'viewer-password-2026'}})).status(),200);
  const viewerPage=await viewer.newPage();await viewerPage.goto(origin+'/market');await viewerPage.locator('.market-card').waitFor();assert.equal(await viewerPage.locator('#marketSettings').count(),0,'ordinary members must not see configuration');
  const viewerConfig=await(await viewer.request.get(origin+'/api/tool-market/client')).json();assert.equal(viewerConfig.can_configure,false);
  const viewerCSRF=(await(await viewer.request.get(origin+'/api/csrf-token')).json()).csrf_token;for(const [path,method]of [['/api/tool-market/client','PUT'],['/api/tool-market/client/test','POST']]){const denied=await viewer.request.fetch(origin+path,{method,headers:{'X-CSRF-Token':viewerCSRF},data:{url:origin+'/market'}});assert.equal(denied.status(),403);}
  await viewer.close();
  // Startup checks must visibly announce updates without downloading by default.
  await page.evaluate(()=>{for(let i=sessionStorage.length-1;i>=0;i--){const key=sessionStorage.key(i);if(key.startsWith('bookstark-tool-update-check:'))sessionStorage.removeItem(key);}});
  await page.route(origin+'/api/tool-market',route=>route.fulfill({json:{tools:catalog.map(x=>({...x,revision:'available-update'}))}}));
  await page.goto(origin+'/profile');await page.getByText('发现 1 个工具更新，可在「工具」中筛选「有更新」查看。',{exact:true}).waitFor();
  assert.equal((await api('/api/tool-installs')).tools[0].revision,tool.revision,'default startup checks must not install updates');
  await page.unroute(origin+'/api/tool-market');await page.goto(origin+'/market?open='+id);await frame.locator('#value').waitFor();
  // Removing source assets does not change a downloaded installation.
  for(const name of ['market-fixture.js','market-fixture.css','market-module.js','market-dep.js'])await api('/api/webdav/files?path='+encodeURIComponent('/'+name),'DELETE');
  await page.reload();await frame.locator('#value').waitFor();assert.equal(await frame.locator('body').evaluate(()=>window.marketStaticLoaded),true);
  // Restore original resources before reinstalling. New installations now read
  // those resources directly rather than retrieving a saved archive.
  for(const [name,content]of Object.entries({'market-fixture.js':'window.marketStaticLoaded=true;','market-fixture.css':'body { --market-local-style: ready; }','market-module.js':"import {value} from './market-dep.js'; window.marketModule=value;",'market-dep.js':'export const value=42;'})){
   await api('/api/webdav/files/content','PUT',{path:'/'+name,content,content_type:name.endsWith('.css')?'text/css':'text/javascript'});
   await api('/api/webdav/files/public','POST',{path:'/'+name});
  }
  await page.goto(origin+'/market?status=installed');await page.locator('.market-card').waitFor();
  await page.locator(`.market-card[data-tool-id="${id}"] summary`).click();await act('pin',id).click();await until(async()=>(await api('/api/tool-installs')).tools.find(x=>x.id===id).pinned===false);await page.locator(`[data-market-action="pin"][data-id="${id}"]`).filter({hasText:'固定到广场'}).waitFor({state:'attached'});
  await page.locator(`.market-card[data-tool-id="${id}"] summary`).click();await act('pin',id).click();await until(async()=>(await api('/api/tool-installs')).tools.find(x=>x.id===id).pinned===true);await page.locator(`[data-market-action="pin"][data-id="${id}"]`).filter({hasText:'取消固定'}).waitFor({state:'attached'});
  await page.locator(`.market-card[data-tool-id="${id}"] summary`).click();await act('uninstall',id).click();await page.locator('dialog input[name="keep"]').waitFor();assert.equal(await page.locator('dialog input[name="keep"]').isChecked(),true);await page.getByRole('button',{name:'确认卸载',exact:true}).click();await until(async()=>(await api('/api/tool-installs')).tools.length===0);
  await page.goto(origin+'/market?selected='+id);await act('install',id).click();await page.getByRole('button',{name:/^确认安装/}).click();await until(async()=>(await api('/api/tool-installs')).tools.length===1);
  await page.goto(origin+'/market?open='+id);await frame.locator('#value').waitFor();assert.equal(await frame.locator('#value').inputValue(),'keep this');assert.equal(await frame.locator('body').evaluate(async()=>new TextDecoder().decode(await BookStark.files.read('notes/saved.txt'))),'saved file');
  await page.goto(origin+'/market');await page.locator('#marketSettings').click();await page.locator('dialog input[name="url"]').waitFor();assert.equal(await page.locator('dialog input[name="url"]').inputValue(),origin+'/market');await page.getByRole('button',{name:'测试连接',exact:true}).click();await page.getByText('✓ 连接成功 · 我的工具市场',{exact:true}).waitFor();await page.screenshot({path:out+'/04-client-market-settings.png',fullPage:true});await page.getByRole('button',{name:'保存设置',exact:true}).click();
  for(const [width,lang,theme]of [[1440,'zh','light'],[390,'zh','hud-light'],[320,'en','glass'],[1440,'en','hud']]){
   await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.evaluate(theme=>localStorage.setItem('bookstark-theme',theme),theme);await page.setViewportSize({width,height:950});await page.reload();await page.locator('.market-card').first().waitFor();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,`${width}/${lang}/${theme}`);await page.screenshot({path:out+`/05-${width}-${lang}-${theme}.png`,fullPage:true});
  }
  await context.addCookies([{name:'lang',value:'zh',url:origin}]);await page.setViewportSize({width:1440,height:1000});await page.evaluate(()=>localStorage.setItem('bookstark-theme','light'));
  await page.goto(origin+'/blogs/market-browser-1/edit');await page.locator('#editorBackBtn').waitFor();assert.equal(await page.locator('#publish-tool-btn,#unpublish-tool-btn').count(),0,'editor must have no tool publishing controls');
  await page.goto(origin+'/notes?tab=articles');const article=page.locator('.article-card[data-id="'+id+'"]');await article.locator('.article-tool-publish').waitFor();
  assert.equal(await article.locator('.article-tool-publish').evaluate(el=>el.previousElementSibling.querySelector('i').classList.contains('fa-gear')),true,'tool publication must sit next to article settings');
  for(const card of await page.locator('.article-card').all())if(!await card.locator('.editor-type-chip').filter({hasText:'HTML'}).count())assert.equal(await card.locator('.article-tool-publish').count(),0,'non-HTML articles must not offer tool publication');
  await article.locator('.article-tool-publish').focus();await until(async()=>await article.locator('.article-actions').evaluate(el=>getComputedStyle(el).opacity)==='1');await article.hover();await page.screenshot({path:out+'/publish-01-article-list-entry.png',fullPage:true});
  await page.setViewportSize({width:390,height:844});await article.locator('.article-tool-publish').scrollIntoViewIfNeeded();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);await page.screenshot({path:out+'/publish-07-mobile-article-entry.png',fullPage:true});
  await context.addCookies([{name:'lang',value:'en',url:origin}]);await page.setViewportSize({width:320,height:844});await page.reload();await article.locator('.article-tool-publish').waitFor();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,'narrow English article list must fit the viewport');await page.screenshot({path:out+'/publish-08-mobile-english.png',fullPage:true});
  await context.addCookies([{name:'lang',value:'zh',url:origin}]);await page.setViewportSize({width:1440,height:1000});await page.reload();await article.locator('.article-tool-publish').click();await page.waitForURL('**/market/publish/'+id);await page.locator('#toolPublishForm input[name="version"]').waitFor();assert.equal(await page.locator('input[name="version"]').inputValue(),'1.0.1');assert.equal(await page.locator('#bs-confirm-ok').count(),0,'old one-step publication dialog removed');
  assert.equal(await page.locator('select[name="access"]').inputValue(),'members','updating must retain restricted access');assert.equal(await page.locator('input[name="members"]').inputValue(),'admin','updating must retain the allowed accounts');
  await page.screenshot({path:out+'/publish-06-release-history.png',fullPage:true});
  // Installing from a different market must request that market's account,
  // without replacing the already authenticated local workspace identity.
  const remote=process.env.BOOKSTARK_MARKET_REMOTE_URL;
  await page.goto(origin+'/market');await page.locator('#marketSettings').click();await page.locator('dialog input[name="url"]').fill(remote+'/market');await page.getByRole('button',{name:'测试连接',exact:true}).click();await page.getByText('✓ 连接成功 · 远端工具市场',{exact:true}).waitFor();assert.equal((await api('/api/tool-market/client')).url,origin+'/market','connection testing must not save settings');await page.getByRole('button',{name:'取消',exact:true}).click();
  await page.locator('#marketSettings').click();assert.equal(await page.locator('dialog input[name="url"]').inputValue(),origin+'/market');await page.locator('dialog input[name="url"]').fill(remote+'/market');await page.getByRole('button',{name:'保存设置',exact:true}).click();
  await page.locator('.market-card').filter({hasText:'远端工具'}).waitFor();
  const remoteTools=(await api('/api/tool-sources','POST',{server:remote+'/market'})).tools,remoteID=remoteTools[0].id;
  await act('details',remoteID).click();await act('install',remoteID).click();await page.getByRole('heading',{name:'登录工具市场',exact:true}).waitFor();
  await page.screenshot({path:out+'/06-independent-market-login.png',fullPage:true});
  await page.locator('dialog input[name="account"]').fill('remote-user');await page.locator('dialog input[name="password"]').fill('remote-password');await page.getByRole('button',{name:'登录并继续安装',exact:true}).click();
  await page.getByRole('button',{name:/^确认安装/}).click();await until(async()=>(await api('/api/tool-installs')).tools.some(x=>x.id===remoteID));await page.locator('dialog[open]').waitFor({state:'hidden'});
  assert.equal((await api('/api/profile')).data.account,'admin');
  const runtime=await api('/api/tool-installs/'+remoteID+'?part=runtime');assert.match(runtime.content,/Remote tool installed/);
  await page.goto(origin+'/market?open='+remoteID);await page.frameLocator('#marketFrameHost iframe').getByRole('heading',{name:'Remote tool installed'}).waitFor();await until(async()=>await page.frameLocator('#marketFrameHost iframe').locator('body').evaluate(()=>window.remoteReferenceDownloaded===true));
  await page.goto(origin+'/market');await page.locator('#marketSettings').click();await page.locator('dialog [data-account]').filter({hasText:'remote-user'}).waitFor();await page.getByRole('button',{name:'退出市场',exact:true}).click();await page.locator('dialog [data-account]').filter({hasText:'尚未登录'}).waitFor();
  await page.getByRole('button',{name:'登录市场',exact:true}).click();await page.locator('dialog input[name="account"]').fill('remote-user');await page.locator('dialog input[name="password"]').fill('remote-password');await page.locator('dialog').last().locator('button[type=submit]').click();await page.locator('dialog [data-account]').filter({hasText:'remote-user'}).waitFor();await page.getByRole('button',{name:'取消',exact:true}).click();assert.equal((await api('/api/profile')).data.account,'admin');
  // An installed tool keeps its original market even after changing the default.
  // Reauthentication must target that original market without changing the default.
  await api('/api/tool-market/client/login','DELETE',{server:remote+'/market'});
  await api('/api/tool-market/client','PUT',{url:origin+'/market',check_updates:true,auto_update:false});
  await page.goto(origin+'/market?status=installed');await act('details',remoteID).click();await act('update',remoteID).click();
  await page.getByRole('heading',{name:'登录工具市场',exact:true}).waitFor();
  assert.equal(await page.locator('dialog .market-info').textContent(),remote,'login must target the installed tool source');
  await page.locator('dialog input[name="account"]').fill('remote-user');await page.locator('dialog input[name="password"]').fill('remote-password');await page.getByRole('button',{name:'登录并继续安装',exact:true}).click();
  await page.getByText('已经是最新版本',{exact:true}).waitFor();
  assert.equal((await api('/api/tool-market/client')).url,origin+'/market','logging into an old tool source must not change the default market');
  const guardCSRF=(await(await context.request.get(origin+'/api/csrf-token')).json()).csrf_token;
  const blockedDelete=await context.request.delete(origin+'/api/blogs/'+id,{headers:{'X-CSRF-Token':guardCSRF}});assert.equal(blockedDelete.status(),409);assert.match((await blockedDelete.json()).message,/先.*下架|先.*撤回/);
  await page.goto(origin+'/market/publish/'+id);await page.getByRole('button',{name:'下架 / 撤回工具',exact:true}).click();await page.locator('#bs-confirm-ok').click();await page.getByText('已下架并撤回待审核版本，现在可以删除来源文章。',{exact:true}).waitFor();
  await api('/api/blogs/'+id,'DELETE');
  await page.goto(origin+'/market?open='+id);await frame.locator('#value').waitFor();assert.equal(await frame.locator('#value').inputValue(),'keep this');
  assert.deepEqual(errors,[]);console.log('PASS: flat Plaza Tools tab, role-gated settings, category/status/search/sort, pagination, list/grid, settings cancel and marketplace sign-in, source isolation, publication, installation and preserved data, bilingual responsive themes.');
 }catch(error){await page.screenshot({path:out+'/failure.png',fullPage:true});throw error;}finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1)});
