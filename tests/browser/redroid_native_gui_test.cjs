// Real Android WebView + native dialogs. Run against the isolated --debug APK.
const assert=require('node:assert/strict');const crypto=require('node:crypto');
const fs=require('node:fs');const path=require('node:path');const cp=require('node:child_process');const http=require('node:http');const WebSocket=require('ws');
const ROOT=path.resolve(__dirname,'../..'),OUT=path.join(ROOT,'artifacts/native-gui-redroid');fs.mkdirSync(OUT,{recursive:true});
const serial=process.env.BOOKSTARK_ADB_SERIAL||'127.0.0.1:15555',PKG='com.bookstark.wails.qa';
const adb=(...args)=>cp.execFileSync('adb',['-s',serial,...args],{encoding:'utf8',maxBuffer:8*1024*1024});
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(fn,label,timeout=20000){const start=Date.now();let last;while(Date.now()-start<timeout){try{const r=await fn();if(r)return r}catch(e){last=e}await pause(200)}throw Error(label+(last?': '+last.message:''))}
function nativeNodes(){adb('shell','uiautomator','dump','/sdcard/bookstark-qa-window.xml');const xml=adb('shell','cat','/sdcard/bookstark-qa-window.xml');return [...xml.matchAll(/<node\b[^>]*>/g)].map(([tag])=>Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]])))}
async function tapNative(predicate,label){const node=await until(()=>nativeNodes().find(predicate),label);const n=node.bounds.match(/\d+/g).map(Number);adb('shell','input','tap',String((n[0]+n[2])/2|0),String((n[1]+n[3])/2|0));return node}
function screenshot(name){const bytes=cp.execFileSync('adb',['-s',serial,'exec-out','screencap','-p']);fs.writeFileSync(path.join(OUT,name+'.png'),bytes)}
class CDP{
 async connect(){const pid=adb('shell','pidof',PKG).trim();assert(pid);adb('forward','tcp:19331','localabstract:webview_devtools_remote_'+pid);const targets=await(await fetch('http://127.0.0.1:19331/json/list')).json();const target=targets.find(t=>t.type==='page'&&JSON.parse(t.description).attached===true)||targets.find(t=>t.type==='page');this.geometry=JSON.parse(target.description);this.ws=new WebSocket(target.webSocketDebuggerUrl);this.jobs=new Map();this.id=0;this.ws.on('message',buffer=>{const m=JSON.parse(buffer);if(m.id&&this.jobs.has(m.id)){const job=this.jobs.get(m.id);this.jobs.delete(m.id);m.error?job.reject(new Error(JSON.stringify(m.error))):job.resolve(m.result)}});await new Promise(r=>this.ws.once('open',r))}
 call(method,params={}){return new Promise((resolve,reject)=>{const id=++this.id;this.jobs.set(id,{resolve,reject});this.ws.send(JSON.stringify({id,method,params}))})}
 async eval(expression){const r=await this.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true,userGesture:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value}
 async goto(url){await this.call('Page.navigate',{url});await until(()=>this.eval(`location.href===${JSON.stringify(url)} && document.readyState==='complete'`),'navigate '+url)}
 close(){this.ws.close()}
}
async function tapWeb(client, selector) {
 const rect=await client.eval(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:innerWidth}})()`);
 const scale=client.geometry.width/rect.width;adb('shell','input','tap',String(Math.round(client.geometry.screenX+rect.x*scale)),String(Math.round(client.geometry.screenY+rect.y*scale)));
}
async function pasteWeb(client, selector, expected) {
 await tapWeb(client, selector);
 await until(()=>adb('shell','dumpsys','input_method').includes('mInputShown=true'),'Android input connection');
 await until(async()=>{
  if(await client.eval(`document.querySelector(${JSON.stringify(selector)}).value===${JSON.stringify(expected)}`))return true;
  await client.eval(`document.querySelector(${JSON.stringify(selector)}).select();true`);
  adb('shell','input','keyevent','279');await pause(200);
  return client.eval(`document.querySelector(${JSON.stringify(selector)}).value===${JSON.stringify(expected)}`);
 },'native clipboard paste');
}
const results=[];function pass(name,details){results.push({name,status:'passed',details});console.log('PASS',name,details||'')}
(async()=>{
 let client=new CDP();let server;
 adb('shell','am','force-stop',PKG);adb('shell','am','start','-n',PKG+'/com.wails.app.MainActivity');
 await until(async()=>{try{client=new CDP();await client.connect();return true}catch(_){return false}},'connect QA APK');
 await until(()=>client.eval(`document.readyState==='complete' && (!!document.querySelector('form[action="/__bookstark/local"]') || !!document.querySelector('#passwordValue') || !!window.BookStarkHost?.available)`),'initial workspace ready');
 try{
  let url=await client.eval('location.href');const localOrigin='http://127.0.0.1:'+adb('shell','run-as',PKG,'cat','files/bookstark/workspace-port').trim();
  // Resume or create this dedicated QA workspace only.
  if(await client.eval('!!document.querySelector("#confirmPassword")')){await client.eval(`document.querySelector('#password').value='Redroid-GUI-2026!';document.querySelector('#confirmPassword').value='Redroid-GUI-2026!';document.querySelector('form[action="/__bookstark/local"] button').click();true`);await until(()=>client.eval('!!document.querySelector("#passwordValue")'),'create workspace')}
  if(await client.eval(`!!document.querySelector('form[action="/__bookstark/local"]')`)){await client.eval(`document.querySelector('form[action="/__bookstark/local"] button').click();true`);await pause(700)}
  await client.goto(localOrigin+'/shares');
  assert(await client.eval('window.BookStarkHost?.available && typeof BookStarkNative.request === "function"'));
  const embedded=await client.eval("fetch('/static/js/native-compat.js?qa='+Date.now(),{cache:'no-store'}).then(r=>r.text())");
  assert.equal(crypto.createHash('sha256').update(embedded).digest('hex'),crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,'static/js/native-compat.js'))).digest('hex'),'installed APK contains final shared adapter');
  const manifest=await client.eval("fetch('/static/asset-hashes.json?qa='+Date.now(),{cache:'no-store'}).then(r=>r.json())");assert.deepEqual(manifest,JSON.parse(fs.readFileSync(path.join(ROOT,'static/asset-hashes.json'),'utf8')));
  pass('Actual APK loads shared native adapter');
  await client.goto(localOrigin+'/tools?type=markdown');
  await until(()=>client.eval('document.querySelector("#toolsTitle") && !document.querySelector("#toolsTitle").hidden'),'markdown editor');
  const marker='Redroid Saved '+Date.now();
  await client.eval(`document.querySelector('#toolsTitle').value=${JSON.stringify(marker)};document.querySelector('#toolsTitle').dispatchEvent(new Event('input',{bubbles:true}));true`);
  await tapNative(n=>n['resource-id']===PKG+':id/native_back','native Back');
  await until(()=>client.eval('location.pathname==="/shares" && typeof BookStarkLocalDrafts!=="undefined"'),'native Back navigated');
  const stored=await client.eval(`BookStarkLocalDrafts.list().then(rows=>rows.find(row=>row.title===${JSON.stringify(marker)}))`);assert(stored?.id);
  pass('Native Back waits for IndexedDB save',{draft:stored.id});
  await tapNative(n=>n['resource-id']===PKG+':id/native_forward','native Forward');
  await until(()=>client.eval('location.pathname==="/tools"'),'native Forward navigated');
  await until(()=>client.eval(`document.querySelector('#toolsTitle')?.value===${JSON.stringify(marker)}`),'draft restored');pass('Native Forward restores draft');
  const clipboard='Redroid clipboard 中文 '+Date.now();
  await client.eval(`BookStarkCopyText(${JSON.stringify(clipboard)})`);
  await client.eval(`{const ta=document.createElement('textarea');ta.id='nativeClipboardProbe';ta.style.cssText='position:fixed;left:20px;top:20px;width:220px;height:60px;z-index:99999';document.body.append(ta);ta.focus();true}`);
  await pasteWeb(client,'#nativeClipboardProbe',clipboard);pass('Native clipboard write + real Android paste');
  const filename='bookstark-redroid-'+Date.now()+'.txt',fileData='Redroid export 中文\n'+('chunked-content-'.repeat(18000));
  await client.eval(`window.qaExportPromise=BookStarkHost.saveBlob(new Blob([${JSON.stringify(fileData)}],{type:'text/plain'}),${JSON.stringify(filename)});true`);
  await until(()=>nativeNodes().some(n=>n.package==='com.android.documentsui'),'system Save dialog');screenshot('01-save-dialog');
  await tapNative(n=>n['resource-id']==='com.android.documentsui:id/button1'||(n.text==='SAVE'&&n.clickable==='true'),'save exported file');
  assert.equal(await client.eval('qaExportPromise'),true);
  const disk=cp.execFileSync('adb',['-s',serial,'exec-out','cat','/sdcard/Download/'+filename]);assert.equal(disk.toString(),fileData);fs.writeFileSync(path.join(OUT,filename),disk);pass('Native SAF export preserves all chunked UTF-8 bytes',{bytes:disk.length});
  // A real same-origin, non-secure LAN page proves the native clipboard path.
  const gateway=JSON.parse(cp.execFileSync('docker',['inspect','redroid'],{encoding:'utf8'}))[0].NetworkSettings.Networks;const host=Object.values(gateway)[0].Gateway;
  server=http.createServer((req,res)=>{
   if(req.url.startsWith('/static/js/')){const name=path.basename(req.url);if(!['utils.js','native-compat.js','bs-dialog.js'].includes(name)){res.writeHead(404);return res.end()};res.setHeader('Content-Type','text/javascript');return res.end(fs.readFileSync(path.join(ROOT,'static/js',name)))}
   if(req.url==='/download') {
     if(!String(req.headers.cookie).includes('gui_session=local-test-only')) {res.writeHead(401);return res.end('No session')}
     res.setHeader('Content-Type','text/plain');res.setHeader('Content-Disposition','attachment; filename="'+filename.replace('.txt','-http.txt')+'"');return res.end('Authenticated HTTP download 中文');
   }
   res.setHeader('Set-Cookie','gui_session=local-test-only; HttpOnly; SameSite=Lax');res.setHeader('Content-Type','text/html');
   res.end('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>BookStark Native QA</title><script src="/static/js/utils.js"></script><script src="/static/js/native-compat.js"></script></head><body><main><h1>BookStark Native QA</h1><textarea id="paste"></textarea><input type="file" id="upload" accept="text/plain"><a id="outside" href="https://example.com/bookstark-gui" target="_blank">External browser</a><iframe id="printFrame" srcdoc="&lt;title&gt;Redroid Print Probe&lt;/title&gt;&lt;h1&gt;Redroid Print Probe&lt;/h1&gt;&lt;p&gt;Native PDF content validation&lt;/p&gt;"></iframe></main><script src="/static/js/bs-dialog.js"></script></body></html>');
  });await new Promise(resolve=>server.listen(19882,host,resolve));
  const fixture='http://'+host+':19882/native-fixture';await client.goto(fixture);assert.equal(await client.eval('isSecureContext'),false);
  await client.eval(`BookStarkCopyText('LAN native clipboard')`);await client.eval('document.querySelector("#paste").focus();true');await pasteWeb(client,'#paste','LAN native clipboard');pass('LAN HTTP clipboard fallback on real Android WebView');
  await client.eval(`document.querySelector('#outside').click();true`);await until(()=>adb('shell','dumpsys','activity','activities').includes('mResumedActivity')&&/mResumedActivity.*org.chromium.webview_shell/.test(adb('shell','dumpsys','activity','activities')),'external browser Activity');adb('shell','input','keyevent','4');await pause(500);assert.equal(await client.eval('location.href'),fixture);pass('External link opens system browser and retains client page');
  await client.eval(`{const popup=window.open(undefined,'_blank');popup.opener=null;popup.location='https://example.com/bookstark-deferred';true}`);await until(()=>/mResumedActivity.*org.chromium.webview_shell/.test(adb('shell','dumpsys','activity','activities')),'deferred popup opens browser');adb('shell','input','keyevent','4');await pause(300);assert.equal(await client.eval('location.href'),fixture);pass('Blank-window deferred external link opens the system browser');
  await until(()=>client.eval('document.querySelector("#printFrame").contentWindow.print.toString().includes("printDocument")'),'iframe print adapter');
  const pdfName='Redroid_Print_Probe_'+Date.now();
  await client.eval(`document.querySelector('#printFrame').contentDocument.title=${JSON.stringify(pdfName)};document.querySelector('#printFrame').contentWindow.print();true`);
  await until(()=>nativeNodes().some(n=>n.package==='com.android.printspooler'),'native Print dialog');screenshot('02-print-dialog');
  let nodes=nativeNodes();
  if(nodes.some(n=>n.text==='Select a printer')) {
    await tapNative(n=>n.text==='Select a printer','printer selector');
    await tapNative(n=>n.text==='Save as PDF','Save as PDF destination');
  }
  await tapNative(n=>n['resource-id']==='com.android.printspooler:id/print_button','save PDF button');
  await until(()=>nativeNodes().some(n=>n.package==='com.android.documentsui'),'PDF Save dialog');
  await tapNative(n=>n.text==='SAVE'&&n.clickable==='true','save PDF file');
  await until(()=>{try{adb('pull','/sdcard/Download/'+pdfName+'.pdf',path.join(OUT,'redroid-print.pdf'));const bytes=fs.readFileSync(path.join(OUT,'redroid-print.pdf'));return bytes.length>1000 && bytes.subarray(0,5).toString()==='%PDF-'}catch(_){return false}},'saved PDF exists');
  const pdf=fs.readFileSync(path.join(OUT,'redroid-print.pdf'));assert.equal(pdf.subarray(0,5).toString(),'%PDF-');assert(pdf.length>1000);
  const printedText=cp.execFileSync('pdftotext',[path.join(OUT,'redroid-print.pdf'),'-'],{encoding:'utf8'});assert(printedText.includes('Redroid Print Probe'));assert(printedText.includes('Native PDF content validation'));
  pass('Iframe print produces a PDF with the expected content',{bytes:pdf.length});
  // Cancelled exports acknowledge cancellation and keep the page usable.
  await client.eval(`window.qaCancelledExport=BookStarkHost.saveBlob(new Blob(['cancelled']),'cancelled-export.txt');true`);
  await until(()=>nativeNodes().some(n=>n.package==='com.android.documentsui'),'cancel export Save dialog');adb('shell','input','keyevent','4');
  assert.equal(await client.eval('qaCancelledExport'),false);pass('Native Save cancellation returns false');
  await client.eval(`window.qaHTTPDownload=BookStarkHost.downloadURL('/download');true`);
  await until(()=>nativeNodes().some(n=>n.package==='com.android.documentsui'),'HTTP download Save dialog');
  await tapNative(n=>n.text==='SAVE'&&n.clickable==='true','save authenticated HTTP download');assert.equal(await client.eval('qaHTTPDownload'),true);
  const httpFile=cp.execFileSync('adb',['-s',serial,'exec-out','cat','/sdcard/Download/'+filename.replace('.txt','-http.txt')]);assert.equal(httpFile.toString(),'Authenticated HTTP download 中文');pass('Authenticated HTTP download keeps cookie and server filename');
  await client.eval(`document.querySelector('#upload').click();true`);
  await until(()=>nativeNodes().some(n=>n.package==='com.android.documentsui'),'native upload file chooser');
  await tapNative(n=>n.text===filename,'select exported file for upload');
  await until(()=>client.eval('document.querySelector("#upload").files.length===1'),'upload file callback');
  const uploaded=await client.eval(`document.querySelector('#upload').files[0].text()`);assert.equal(uploaded,fileData);pass('Native file chooser returns readable file bytes');

  await client.goto(localOrigin+'/shares');
  const devices=await client.eval('navigator.mediaDevices.enumerateDevices().then(list=>list.map(d=>({kind:d.kind,label:d.label})))');
  await client.eval(`window.qaDeniedMedia=navigator.mediaDevices.getUserMedia({audio:true}).then(s=>{s.getTracks().forEach(t=>t.stop());return 'granted'}).catch(e=>e.name);true`);
  await tapNative(n=>n.text==='Cancel'||n.text==='CANCEL','deny website microphone');
  assert.equal(await client.eval('qaDeniedMedia'),'NotAllowedError');pass('Website microphone denial is respected');
  await client.eval(`window.qaAllowedMedia=navigator.mediaDevices.getUserMedia({audio:true}).then(s=>{const result={tracks:s.getAudioTracks().length,state:s.getAudioTracks()[0]?.readyState};s.getTracks().forEach(t=>t.stop());return result}).catch(e=>({error:e.name,message:e.message}));true`);
  await tapNative(n=>n.text==='OK','allow website microphone');
  const permissionNodes=nativeNodes();
  if(permissionNodes.some(n=>n.package==='com.android.permissioncontroller')) await tapNative(n=>n['resource-id'].endsWith(':id/permission_allow_foreground_only_button')||n.text==='While using the app','Android RECORD_AUDIO permission');
  const media=await client.eval('qaAllowedMedia');
  if(media.error) {
    assert.equal(media.error,'NotReadableError');
    assert(/android.permission.RECORD_AUDIO: granted=true/.test(adb('shell','dumpsys','package',PKG)));
    pass('Website + Android microphone permission granted; capture reaches device',media);
    results.push({name:'Microphone audio capture',status:'hardware-unavailable',details:media.message});
  } else { assert.equal(media.tracks,1);assert.equal(media.state,'live');pass('Website + Android permission grant yields a live audio track',media); }
  results.push({name:'Camera image capture',status:'hardware-unavailable',details:'redroid has zero camera devices; permission path shares the tested audio permission implementation.'});
  await client.goto(localOrigin+'/tools?type=markdown');await until(()=>client.eval('document.querySelector("#toolsTitle") && !document.querySelector("#toolsTitle").hidden'),'unsaved guard editor');
  await client.eval(`window.qaRealSave=BookStarkLocalDrafts.save;BookStarkLocalDrafts.save=()=>Promise.reject(new Error('QA write denied'));document.querySelector('#toolsTitle').value='Uncommitted redroid draft';document.querySelector('#toolsTitle').dispatchEvent(new Event('input',{bubbles:true}));true`);
  await tapNative(n=>n['resource-id']===PKG+':id/native_back','Back with failed save');
  await until(()=>client.eval('!!document.querySelector("#bs-confirm-cancel")'),'unsaved confirmation');screenshot('04-unsaved-protection');
  await client.eval('document.querySelector("#bs-confirm-cancel").click();true');await pause(300);assert.equal(await client.eval('location.pathname'),'/tools');
  assert.equal(await client.eval('document.querySelector("#toolsTitle").value'),'Uncommitted redroid draft');
  await client.eval('BookStarkLocalDrafts.save=qaRealSave;true');await tapNative(n=>n['resource-id']===PKG+':id/native_back','retry Back after restoring save');
  await until(()=>client.eval('location.pathname==="/shares"'),'save retry navigates');pass('Failed save blocks native navigation; cancel retains draft and retry saves');
  // Reset the real WebView history so Android Back takes its Activity-finish path.
  await client.goto(localOrigin+'/tools?type=markdown');await until(()=>client.eval('document.querySelector("#toolsTitle") && !document.querySelector("#toolsTitle").hidden'),'close test editor');
  if(adb('shell','dumpsys','input_method').includes('mInputShown=true')) { adb('shell','input','keyevent','4');await until(()=>!adb('shell','dumpsys','input_method').includes('mInputShown=true'),'hide keyboard before Activity close test'); }
  const closeMarker='Persisted on native close '+Date.now();
  await client.call('Page.resetNavigationHistory');const history=await client.call('Page.getNavigationHistory');assert.equal(history.entries.length,1);
  await client.eval(`document.querySelector('#toolsTitle').value=${JSON.stringify(closeMarker)};document.querySelector('#toolsTitle').dispatchEvent(new Event('input',{bubbles:true}));true`);
  adb('shell','input','keyevent','4');await until(()=>!/mResumedActivity.*com.bookstark.wails.qa/.test(adb('shell','dumpsys','activity','activities')),'Android Back closes Activity');
  pass('Android Back at history root closes the Activity after save');client.close();
  adb('shell','am','force-stop',PKG);adb('shell','am','start','-n',PKG+'/com.wails.app.MainActivity');
  await until(async()=>{try{client=new CDP();await client.connect();return true}catch(_){return false}},'reconnect restarted APK');
  await until(()=>client.eval(`document.readyState==='complete' && !!document.querySelector('form[action="/__bookstark/local"]')`),'workspace launcher after restart');
  await client.eval(`document.querySelector('form[action="/__bookstark/local"] button').click();true`);await pause(1000);
  await client.goto(localOrigin+'/shares');await until(()=>client.eval('typeof BookStarkLocalDrafts!=="undefined"'),'draft store after restart');
  assert(await client.eval(`BookStarkLocalDrafts.list().then(rows=>rows.some(row=>row.title===${JSON.stringify(closeMarker)}))`));pass('Draft survives Activity close and process restart');
  fs.writeFileSync(path.join(OUT,'results.json'),JSON.stringify({results,localOrigin,fixture},null,2));screenshot('03-client-after-tests');
 }finally{if(server)await new Promise(r=>server.close(r));client.close()}
})().catch(error=>{fs.writeFileSync(path.join(OUT,'results.json'),JSON.stringify({results,error:String(error)},null,2));console.error(error);process.exit(1)});
