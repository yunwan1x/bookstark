const {chromium}=require('playwright');const assert=require('node:assert/strict');const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox','--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream']});
 const origin=process.env.BOOKSTARK_TEST_ORIGIN,out=process.env.BOOKSTARK_SCREENSHOT_DIR||'/tmp/bookstark-permissions';fs.mkdirSync(out,{recursive:true});
 const context=await browser.newContext({viewport:{width:1440,height:1050},serviceWorkers:'block'});await context.addCookies([{name:'lang',value:'zh',url:origin}]);
 const page=await context.newPage(),errors=[];page.on('pageerror',err=>errors.push(err.message));page.on('console',msg=>{if(msg.type()==='error')console.log('browser console:',msg.text());});
 async function api(path,method='GET',data){const csrf=(await(await context.request.get(origin+'/api/csrf-token')).json()).csrf_token;const r=await context.request.fetch(origin+path,{method,headers:{'X-CSRF-Token':csrf},data});assert.ok(r.ok(),await r.text());return r.json();}
 try {
  assert.equal((await context.request.post(origin+'/api/login',{data:{account:'admin',password:process.env.BOOKSTARK_TEST_PASSWORD}})).status(),200);
  await page.goto(origin+'/tools/run/9001');const frame=page.frameLocator('#marketFrameHost iframe');await frame.locator('#ready').waitFor();await page.locator('#toolRuntimeState').waitFor({state:'hidden'});
  const frameOrigin=await frame.locator('body').evaluate(()=>location.origin);assert.notEqual(frameOrigin,origin);assert.match(frameOrigin,/^http:\/\/tool-[a-f0-9]{32}\.localhost:/);
  await context.grantPermissions(['camera','microphone','clipboard-read','clipboard-write','geolocation']);
  assert.equal(await frame.locator('body').evaluate(()=>{try{void parent.document.body;return 'unsafe'}catch(_){return 'isolated'}}),'isolated');
  assert.equal(await frame.locator('body').evaluate(()=>document.cookie),'','no main login cookie in tool origin');
  const policy=await frame.locator('body').evaluate(()=>({secure:isSecureContext,camera:document.featurePolicy.allowsFeature('camera'),microphone:document.featurePolicy.allowsFeature('microphone'),screen:document.featurePolicy.allowsFeature('display-capture'),clipboard:document.featurePolicy.allowsFeature('clipboard-write'),usb:document.featurePolicy.allowsFeature('usb')}));
  assert.deepEqual(policy,{secure:true,camera:true,microphone:true,screen:true,clipboard:true,usb:false});
  await frame.locator('#camera').click();await frame.locator('#result').filter({hasText:'audio,video'}).waitFor();await frame.locator('#copy').click();await page.waitForTimeout(100);await frame.locator('#result').filter({hasText:'copied'}).waitFor();
  assert.equal(await frame.locator('body').evaluate(()=>navigator.clipboard.readText()),'BookStark clipboard fixture');
  const files=await frame.locator('body').evaluate(async()=>{
   const f=BookStark.files;await f.mkdir('notes/deep',{recursive:true});await f.write('notes/deep/你好.txt','saved file');
   const stat=await f.stat('notes/deep/你好.txt');const list=await f.list('notes/deep');await f.copy('notes','backup');await f.rename('backup/deep/你好.txt','backup/deep/new.txt');await f.move('backup/deep/new.txt','notes/moved.txt');
   let nonempty;try{await f.remove('notes')}catch(err){nonempty=err.code}await f.remove('backup',{recursive:true});
   let traversal;try{await f.list('../')}catch(err){traversal=err.code}
   return {methods:Object.keys(f),stat,list,content:new TextDecoder().decode(await f.read('notes/moved.txt')),exists:await f.exists('backup'),nonempty,traversal};
  });
  assert.deepEqual(files.methods.sort(),['read','write','list','stat','exists','mkdir','remove','rename','move','copy'].sort());assert.equal(files.stat.path,'notes/deep/你好.txt');assert.equal(files.stat.size,10);assert.equal(files.list[0].path,files.stat.path);assert.equal(files.content,'saved file');assert.equal(files.exists,false);assert.equal(files.nonempty,'directory_not_empty');assert.equal(files.traversal,'invalid_path');
  const socketResult=await frame.locator('body').evaluate(async(_element,port)=>{
   const socket=await BookStark.sockets.connect({host:'127.0.0.1',port});
   const reader=socket.readable.getReader(),writer=socket.writable.getWriter(),input=new Uint8Array(600000);for(let i=0;i<input.length;i++)input[i]=i%251;
   await writer.write(input);const output=new Uint8Array(input.length);let offset=0;while(offset<output.length){const {value,done}=await reader.read();if(done)throw Error('early EOF');output.set(value,offset);offset+=value.length;}
   const equal=output.every((byte,index)=>byte===input[index]);socket.close();await socket.closed;return {equal,bytes:offset,closed:socket.readyState};
  },Number(process.env.BOOKSTARK_SOCKET_TEST_PORT));assert.deepEqual(socketResult,{equal:true,bytes:600000,closed:3});
  await frame.locator('body').evaluate(()=>localStorage.setItem('permission-persistence','saved'));await page.waitForTimeout(400);await page.reload();await frame.locator('#ready').waitFor();assert.equal(await frame.locator('body').evaluate(()=>localStorage.getItem('permission-persistence')),'saved');
  await page.locator('#toolRuntimeMore [data-bs-action-dropdown-toggle]').click();await page.locator('#toolRuntimeInfo').click();await page.locator('dialog[open] .tool-permission-list').waitFor();await page.screenshot({path:out+'/03-runtime-capabilities.png',fullPage:true});await page.locator('dialog[open] button').last().click();
  await page.goto(origin+'/tools/run/9002');await frame.locator('#ready').waitFor();const denied=await frame.locator('body').evaluate(async()=>{let file,camera,socket;try{await BookStark.sockets.connect('127.0.0.1',22)}catch(err){socket=err.code}try{await BookStark.files.list()}catch(err){file=err.code}try{const stream=await navigator.mediaDevices.getUserMedia({video:true});stream.getTracks().forEach(t=>t.stop());camera='unsafe'}catch(err){camera=err.name}return {file,camera,socket,cameraPolicy:document.featurePolicy.allowsFeature('camera'),clipboardPolicy:document.featurePolicy.allowsFeature('clipboard-write')}});
  assert.deepEqual(denied,{file:'permission_denied',camera:'NotAllowedError',socket:'permission_denied',cameraPolicy:false,clipboardPolicy:false});
  // The host's frame-src prevents navigating a same-origin-enabled tool back
  // into the application origin, even to an existing iframe-compatible page.
  await frame.locator('body').evaluate((_element,target)=>{location.href=target},origin+'/login').catch(()=>{});await page.waitForTimeout(200);assert.notEqual(page.frames().find(f=>f!==page.mainFrame())?.url(),origin+'/login');
  const blog=(await api('/api/blogs','POST',{blog_title:'设备与文件工具',blog_type:'article',editor_type:'html',blog_desc:'设备与文件处理工具',blog_content:'<!doctype html><h1>设备与文件工具</h1>'})).data.blog_id;
  await page.goto(origin+'/market/publish/'+blog);await page.locator('#toolPublishForm:not([aria-busy])').waitFor();assert.equal(await page.locator('[data-tool-permission]').count(),42);assert.equal(await page.locator('[data-tool-permission=camera]').isChecked(),false);
  for(const key of ['camera','microphone','display_capture','clipboard_read','clipboard_write','fullscreen','downloads'])await page.locator('[data-tool-permission='+key+']').check();
  await page.locator('.tool-permission-groups').scrollIntoViewIfNeeded();await page.screenshot({path:out+'/01-publication-permissions-desktop.png',fullPage:false});
  await page.locator('.tool-permission-group summary').click();await page.locator('[data-tool-permission=usb]').scrollIntoViewIfNeeded();await page.screenshot({path:out+'/02-advanced-permissions.png'});
  await page.setViewportSize({width:390,height:900});await page.locator('[data-tool-permission=camera]').scrollIntoViewIfNeeded();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);await page.screenshot({path:out+'/04-publication-permissions-mobile.png'});
  await page.setViewportSize({width:1440,height:1050});await context.addCookies([{name:'lang',value:'en',url:origin}]);await page.reload();await page.locator('#toolPublishForm:not([aria-busy])').waitFor();assert.equal(await page.locator('label[for=publishPermission_camera]').innerText(),'Camera\nRequest a camera; the browser controls device selection and consent.');await page.locator('.tool-permission-groups').scrollIntoViewIfNeeded();await page.screenshot({path:out+'/05-publication-permissions-english.png'});
  await context.addCookies([{name:'lang',value:'zh',url:origin}]);await page.reload();await page.locator('#toolPublishForm:not([aria-busy])').waitFor();await page.locator('#toolPublishForm [type=submit]').click();await page.locator('#publishStatus.market-success').waitFor();const published=await api('/api/blogs/'+blog+'/tool');assert.equal(published.metadata.permissions.camera,true);assert.equal(published.metadata.permissions.schema,1);
  await api('/api/tool-market/client','PUT',{url:origin+'/market',check_updates:false,auto_update:false});
  await page.goto(origin+'/market?q='+encodeURIComponent('设备与文件工具'));await page.locator('[data-market-action=install][data-id="'+blog+'"]').first().click();await page.locator('dialog[open] .tool-permission-list').waitFor();assert.equal(await page.locator('dialog[open]').getByText('摄像头',{exact:true}).count(),1);await page.screenshot({path:out+'/06-install-permission-review.png'});await page.locator('dialog[open] .market-actions button').last().click();await page.locator('dialog[open]').waitFor({state:'hidden'});
  const installed=await api('/api/tool-installs/'+blog);assert.equal(installed.permissions.camera,true);
  await page.goto(origin+'/admin/tool-market');await page.locator('[name=runtime_origin]').waitFor();await page.locator('[name=runtime_origin]').scrollIntoViewIfNeeded();await page.screenshot({path:out+'/07-remote-runtime-setting.png'});
  assert.deepEqual(errors,[]);fs.writeFileSync(out+'/validation.json',JSON.stringify({policy,files,socketResult,denied,screenshots:7,consoleErrors:errors},null,2));console.log('Tool capability declaration, isolation, browser devices, clipboard, complete file API and responsive UI passed');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
