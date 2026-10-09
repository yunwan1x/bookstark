const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const origin=process.env.BOOKSTARK_TEST_ORIGIN;
const prefix='csrf-all-'+Date.now();
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({serviceWorkers:'block'});
 const page=await context.newPage();page.setDefaultTimeout(60000);page.setDefaultNavigationTimeout(120000);
 const resources=[], comments=[];let worker;
 const expire=()=>context.clearCookies({name:'csrf_token'});
 async function api(path,method='GET',body){
  await context.request.get(origin+'/api/csrf-token');
  const cookie=(await context.cookies(origin)).find(c=>c.name==='csrf_token');
  const r=await context.request.fetch(origin+path,{method,headers:{'X-CSRF-Token':cookie?.value||''},...(body===undefined?{}:{data:body})});
  const j=await r.json();assert.equal(j.code,0,`${method} ${path}: ${r.status()} ${j.message}`);return j;
 }
 async function mutate(path,method,body){
  await expire();
  const result=await page.evaluate(async({path,method,body})=>{
   const r=await csrfFetch(path,{method,offlinePolicy:'reject',headers:new Headers({'Content-Type':'application/json'}),body:body===undefined?undefined:JSON.stringify(body)});
   return {status:r.status,json:await r.json()};
  },{path,method,body});
  assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.json.code,0);return result.json;
 }
 async function notes(){const j=await api('/api/blogs?keyword='+encodeURIComponent(prefix)+'&page_size=200');return (j.data||[]).filter(row=>row.blog_title.startsWith(prefix));}
 try{
  const login=await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}});assert.equal(login.status(),200);
  await page.goto(origin+'/notes',{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.notesApp&&window.BSOfflineQueue);
  let j=await mutate('/api/blogs','POST',{blog_title:prefix+'-edit',blog_type:'note',blog_content:'original',visibility:0});
  resources.push({type:'blogs',id:j.data.blog_id});const blog=j.data;
  await mutate('/api/blogs/'+blog.blog_id,'PUT',{blog_content:'changed'});
  assert.equal((await api('/api/blogs/'+blog.blog_id)).data.blog_content,'changed');
  await mutate('/api/blogs/'+blog.blog_id+'/pin','PATCH');
  console.log('PASS note PUT/PATCH after expiry');
  j=await mutate('/api/tasks','POST',{content:prefix+'-task'});const taskID=j.data.task_id;resources.push({type:'tasks',id:taskID});
  await mutate('/api/tasks/'+taskID,'PUT',{content:prefix+'-task-edited'});
  await mutate('/api/tasks/'+taskID+'/done','PATCH',{done:true});
  await mutate('/api/tasks/'+taskID,'DELETE');resources.pop();console.log('PASS task POST/PUT/PATCH/DELETE after expiry');
  j=await mutate('/api/bookmarks','POST',{title:prefix+'-bookmark',url:'https://example.invalid/'+prefix});const bookmarkID=j.data.bookmark_id||j.data.id;resources.push({type:'bookmarks',id:bookmarkID});
  await mutate('/api/bookmarks/'+bookmarkID,'PUT',{title:prefix+'-bookmark-edited'});
  await mutate('/api/bookmarks/'+bookmarkID,'DELETE');resources.pop();console.log('PASS bookmark create/edit/delete after expiry');
  await expire();
  const upload=await page.evaluate(async prefix=>{
   const c=document.createElement('canvas');c.width=16;c.height=16;const pixels=new ImageData(16,16);crypto.getRandomValues(pixels.data);for(let i=3;i<pixels.data.length;i+=4)pixels.data[i]=255;c.getContext('2d').putImageData(pixels,0,0);
   const blob=await new Promise(r=>c.toBlob(r));const form=new FormData();form.append('file',blob,prefix+'.png');form.append('category','drawing');
   const r=await fetchWithCurrentCSRF('/api/uploads',{method:'POST',body:form});return {status:r.status,json:await r.json()};
  },prefix);
  assert.equal(upload.status,200);assert.equal(upload.json.code,0);assert.equal(upload.json.data.file_name,prefix+'.png');resources.push({type:'uploads',id:upload.json.data.id});
  await mutate('/api/uploads/'+upload.json.data.id,'DELETE');resources.pop();console.log('PASS multipart upload/delete after expiry');
  let aiCalls=0;
  await page.route('**/api/ai/complete',async route=>{
   aiCalls++;const cookie=(await context.cookies(origin)).find(c=>c.name==='csrf_token');
   assert.equal(route.request().headers()['x-csrf-token'],cookie.value);
   await route.fulfill({status:200,contentType:'text/event-stream',body:'data: {"choices":[{"delta":{"content":"test-stream"}}]}\n\ndata: [DONE]\n\n'});
  });
  await expire();assert.equal(await page.evaluate(()=>new Promise((resolve,reject)=>AIHelper.complete({messages:[],onDone:resolve,onError:reject}))),'test-stream');
  assert.equal(aiCalls,1);await page.unroute('**/api/ai/complete');console.log('PASS AI streaming with mocked provider, one request after expiry');
  const share=await mutate('/api/shares','POST',{share_type:'blog',target_id:blog.blog_id});const identify=share.data.share_identify;
  await page.goto(origin+'/shares/'+identify,{waitUntil:'domcontentloaded'});
  await page.locator('[data-share-comments-trigger]:visible').first().click();
  await page.locator('#share-comment-content').fill(prefix+'-comment');await expire();
  const posted=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.endsWith('/comments'));
  await page.locator('#share-comments-form .share-comments-submit').click();const cr=await posted;assert.equal(cr.status(),200);const cj=await cr.json();comments.push(cj.data.comment_id);
  await page.locator('.share-comment-delete[data-comment-id="'+cj.data.comment_id+'"]').waitFor();await expire();
  page.once('dialog',d=>d.accept());const removed=page.waitForResponse(r=>r.request().method()==='DELETE'&&new URL(r.url()).pathname.startsWith('/api/share-comments/'));
  await page.locator('.share-comment-delete[data-comment-id="'+cj.data.comment_id+'"]').click();assert.equal((await removed).status(),200);console.log('PASS real comment UI create/delete after expiry');
  for(const type of ['markdown','html']){
   const protectedBlog=await api('/api/blogs','POST',{blog_title:prefix+'-'+type,blog_type:'article',editor_type:type,blog_content:type==='html'?'<p>protected</p>':'protected',new_password:'test-article-password'});
   resources.push({type:'blogs',id:protectedBlog.data.blog_id});
   await page.goto(origin+'/blogs/'+protectedBlog.data.blog_identify+'/edit?mode=edit',{waitUntil:'domcontentloaded'});
   await page.locator('#blog-pwd-input').fill('test-article-password');await expire();
   const unlocked=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.includes('/verify-password'));
   await page.locator('#blog-pwd-ok').click();assert.equal((await unlocked).status(),200);console.log('PASS protected '+type+' editor unlock after expiry');
   if(type==='markdown'){
    await page.waitForFunction(()=>window._cherryEditor);
    await expire();const saved=page.waitForResponse(r=>r.request().method()==='PUT'&&new URL(r.url()).pathname==='/api/blogs/'+protectedBlog.data.blog_id);
    await page.evaluate(()=>{window._cherryEditor.setValue('edited after expiry');manualSave();});
    assert.equal((await saved).status(),200);console.log('PASS real editor save after expiry');
    await page.waitForFunction(()=>document.querySelector('#save-status').textContent.includes('已保存'));
    const saveURL=origin+'/api/blogs/'+protectedBlog.data.blog_id;
    for(const [status,payload,reason] of [
     [401,{code:401,message:'登录已过期',error:'登录已过期'},'登录已过期'],
     [403,{error:'没有修改权限'},'没有修改权限'],
     [200,{code:1,message:'密码不正确'},'密码不正确'],
     [413,null,'HTTP 413'],
    ]) {
     await page.route(saveURL,route=>route.request().method()==='PUT'?route.fulfill({status,contentType:payload?'application/json':'text/html',body:payload?JSON.stringify(payload):'<html>too large</html>'}):route.continue());
     const content='retained failed save '+status;
     await page.evaluate(async content=>{window._cherryEditor.setValue(content);await manualSave();},content);
     const label=await page.locator('#save-status').textContent();
     assert.ok(label.includes('未保存')&&label.includes(reason),`HTTP ${status}, expected ${reason}: ${label}`);
     assert.equal(await page.evaluate(()=>window._cherryEditor.getMarkdown()),content);
     await page.unroute(saveURL);
    }
    await page.evaluate(()=>manualSave());
    await page.waitForFunction(()=>document.querySelector('#save-status').textContent==='● 已保存');
    assert.equal(await page.locator('#save-status').getAttribute('title'),'');
    console.log('PASS editor preserves failed content, displays server errors, and clears errors after recovery');
   }
  }
  await page.goto(origin+'/notes',{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>window.BSOfflineQueue);
  async function queue(label){await page.evaluate(({prefix,label})=>BSOfflineQueue.addToQueue('/api/blogs','POST',{'Content-Type':'application/json','X-CSRF-Token':'stale-queued-token'},JSON.stringify({blog_title:prefix+'-'+label,blog_type:'note',blog_content:label})),{prefix,label});}
  await queue('page-replay');await expire();
  await page.evaluate(()=>Promise.all([BSOfflineQueue.replayQueue(),BSOfflineQueue.replayQueue()]));
  assert.equal((await notes()).filter(x=>x.blog_title===prefix+'-page-replay').length,1);console.log('PASS page offline replay with stale token, concurrent replay creates once');
  // Run the production worker's replay code in an actual worker with the same
  // origin, IndexedDB, cookies and Web Locks, without downloading its full precache.
  const ready=page.waitForEvent('worker');await page.evaluate(()=>{window.testReplayWorker=new Worker('/sw.js');});worker=await ready;
  assert.equal(await worker.evaluate(()=>typeof replayOfflineQueue),'function');
  await queue('worker-replay');await expire();await worker.evaluate(()=>replayOfflineQueue());
  assert.equal((await notes()).filter(x=>x.blog_title===prefix+'-worker-replay').length,1);console.log('PASS background worker replay after expiry');
  await queue('shared-lock');await expire();await Promise.all([page.evaluate(()=>BSOfflineQueue.replayQueue()),worker.evaluate(()=>replayOfflineQueue())]);
  assert.equal((await notes()).filter(x=>x.blog_title===prefix+'-shared-lock').length,1);console.log('PASS page/worker shared lock prevents duplicate creation');
  await queue('csrf-retained');
  await page.route('**/api/blogs',route=>route.fulfill({status:403,contentType:'application/json',body:'{"code":403,"csrf_error":true}'}));
  await page.evaluate(()=>BSOfflineQueue.replayQueue());assert.equal(await page.evaluate(()=>BSOfflineQueue.getQueueCount()),1);await page.unroute('**/api/blogs');
  await worker.evaluate(()=>{self.originalTestFetch=self.fetch;self.fetch=(url,opts)=>String(url)==='/api/blogs'?Promise.resolve(new Response('{"csrf_error":true}',{status:403})):self.originalTestFetch(url,opts);});
  await worker.evaluate(()=>replayOfflineQueue());assert.equal(await page.evaluate(()=>BSOfflineQueue.getQueueCount()),1);
  await worker.evaluate(()=>{self.fetch=self.originalTestFetch;});await worker.evaluate(()=>replayOfflineQueue());
  assert.equal((await notes()).filter(x=>x.blog_title===prefix+'-csrf-retained').length,1);console.log('PASS repeated CSRF rejection preserves queue until recovery');
  await queue('login-retained');const auth=(await context.cookies(origin)).filter(c=>c.name==='token');assert.equal(auth.length,1);await context.clearCookies({name:'token'});
  await page.evaluate(()=>BSOfflineQueue.replayQueue());assert.equal(await page.evaluate(()=>BSOfflineQueue.getQueueCount()),1);
  await worker.evaluate(()=>replayOfflineQueue());assert.equal(await page.evaluate(()=>BSOfflineQueue.getQueueCount()),1);
  await context.addCookies(auth);await worker.evaluate(()=>replayOfflineQueue());assert.equal(await page.evaluate(()=>BSOfflineQueue.getQueueCount()),0);console.log('PASS login expiry keeps queued data; relogin resumes');
  const count=await page.evaluate(()=>BSOfflineQueue.getQueueCount());assert.equal(count,0);
 }finally{
  if(worker)await page.evaluate(()=>window.testReplayWorker.terminate()).catch(()=>{});
  if(comments.length)await api('/api/admin/share-comments/delete','POST',{comment_ids:comments});
  for(const row of await notes()){if(!resources.some(x=>x.type==='blogs'&&x.id===row.blog_id))resources.push({type:'blogs',id:row.blog_id});}
  for(const resource of resources.reverse()){await api('/api/'+resource.type+'/'+resource.id,'DELETE');}
  const trash=await api('/api/trash?page=1&page_size=200');
  for(const row of trash.data||[]){if(row.resource_name.startsWith(prefix))await api('/api/trash/'+row.trash_id,'DELETE');}
  assert.equal((await notes()).length,0);assert.equal((await api('/api/trash?page=1&page_size=200')).data.some(x=>x.resource_name.startsWith(prefix)),false);
  console.log('CLEANUP_OK',prefix);await browser.close();
 }
})().catch(e=>{console.error(e.stack);process.exit(1)});
