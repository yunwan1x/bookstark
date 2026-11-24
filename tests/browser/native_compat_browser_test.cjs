const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox','--disable-dev-shm-usage']});
 try {
  const context=await browser.newContext();
  await context.addInitScript(()=>{
   window.nativeTest={clipboard:'',exports:[],transfers:{},rejectCopy:false,cancelSave:false};
   window.BookStarkNative={openExternal:url=>{window.nativeTest.external=url},request:payload=>{
    const {id,action,args}=JSON.parse(payload),state=window.nativeTest;let value=true,error=null;
    switch(action){
     case 'clipboard-write': if(state.rejectCopy)error='Copy denied';else state.clipboard=args.text;break;
     case 'save-begin':value='transfer_'+Object.keys(state.transfers).length;state.transfers[value]={...args,data:''};break;
     case 'save-chunk':state.transfers[args.token].data+=atob(args.data);break;
     case 'save-finish':state.exports.push(state.transfers[args.token]);value=!state.cancelSave;break;
     case 'save-cancel':delete state.transfers[args.token];break;
     default:error='Unexpected request';
    }
    setTimeout(()=>BookStarkHostReply(id,value,error),0);
   }};
  });
  const page=await context.newPage();await page.goto(process.env.BOOKSTARK_TEST_ORIGIN+'/shares');
  assert.equal(await page.evaluate(()=>BookStarkHost.available),true);
  await page.evaluate(()=>BookStarkCopyText('中文 clipboard'));assert.equal(await page.evaluate(()=>nativeTest.clipboard),'中文 clipboard');
  await page.evaluate(()=>nativeTest.rejectCopy=true);
  await assert.rejects(page.evaluate(()=>BookStarkCopyText('should fail')),/Copy denied/);
  await page.evaluate(()=>nativeTest.rejectCopy=false);
  const data='中文/🌱/'+('abcdefghij'.repeat(30000));
  const saved=await page.evaluate(async data=>BookStarkHost.saveBlob(new Blob([data],{type:'text/plain'}),'notes.txt'),data);assert.equal(saved,true);
  const exported=await page.evaluate(()=>nativeTest.exports[0]);assert.equal(exported.name,'notes.txt');assert.equal(Buffer.from(exported.data,'binary').toString(),data);
  await page.evaluate(()=>nativeTest.cancelSave=true);assert.equal(await page.evaluate(()=>BookStarkHost.saveBlob(new Blob(['cancel']),'cancel.txt')),false);
  await page.evaluate(()=>nativeTest.cancelSave=false);
  await page.evaluate(()=>{const f=document.createElement('iframe');f.id='nativePrintTest';document.body.append(f);f.contentDocument.write('<title>Canvas print</title><canvas width="10" height="10"></canvas><script>window.testUntrusted=true<\/script>');f.contentDocument.close();});
  await page.waitForFunction(()=>document.querySelector('#nativePrintTest').contentWindow.print.toString().includes('printDocument'));
  await page.evaluate(()=>document.querySelector('#nativePrintTest').contentWindow.print());
  await page.waitForFunction(()=>nativeTest.exports.some(item=>item.kind==='print'));
  const printed=await page.evaluate(()=>nativeTest.exports.find(item=>item.kind==='print').data);assert(printed.includes('data:image/png'));assert(!printed.includes('<script'));
  await page.evaluate(async()=>{window.qaCleanupRan=false;window.addEventListener('beforeunload',()=>window.qaCleanupRan=true);await BookStarkBeforeLeave()});assert.equal(await page.evaluate(()=>qaCleanupRan),false,'checking close does not run real unload cleanup');
  await page.evaluate(()=>window.dispatchEvent(new Event('beforeunload')));assert.equal(await page.evaluate(()=>qaCleanupRan),true,'approved departure still runs real cleanup callbacks');
  await page.evaluate(()=>{const popup=window.open('', '_blank');popup.document.write('<h1>Blank window print</h1>');popup.document.close();popup.print()});await page.waitForFunction(()=>nativeTest.exports.some(item=>item.kind==='print' && item.data.includes('Blank window print')));
  const allowed=await page.evaluate(async()=>{BookStarkNativeGuards.add(async()=>{await new Promise(r=>setTimeout(r,60));window.flushFinished=true;return true});return BookStarkBeforeLeave()});assert.equal(allowed,true);assert.equal(await page.evaluate(()=>flushFinished),true);
  await page.evaluate(()=>BookStarkNativeGuards.add(async()=>false));
  const denied=page.evaluate(()=>BookStarkBeforeLeave());await page.locator('#bs-confirm-cancel').click();assert.equal(await denied,false);
  await context.close();
  // A real user click on a LAN HTTP document exercises the clipboard fallback.
  const fallback=await browser.newContext();const p=await fallback.newPage();
  await p.route('http://192.168.42.1/**',r=>r.fulfill({contentType:'text/html',body:'<html lang="en"><body><button id="copy">Copy</button><output id="state"></output></body></html>'}));
  await p.goto('http://192.168.42.1/notes');
  const root=require('./repo-root.cjs');
  await p.addScriptTag({content:fs.readFileSync(path.join(root,'static/js/native-compat.js'),'utf8')});
  await p.evaluate(()=>document.querySelector('#copy').onclick=()=>BookStarkCopyText('LAN clipboard').then(()=>document.querySelector('#state').textContent='copied').catch(()=>document.querySelector('#state').textContent='failed'));
  assert.equal(await p.evaluate(()=>isSecureContext),false);await p.click('#copy');await p.waitForFunction(()=>document.querySelector('#state').textContent==='copied');
  await p.evaluate(()=>document.execCommand=()=>false);await p.click('#copy');await p.waitForFunction(()=>document.querySelector('#state').textContent==='failed');
  await fallback.close();
  // WebKitGTK supplies no frame identity. Host requests made before its
  // load-time proof arrives must be retried with that main-document proof.
  const proved=await browser.newContext();await proved.addInitScript(()=>{
   window.proofRequests=[];window.chrome=window.chrome||{};window.chrome.webview={postMessage:message=>{
    proofRequests.push(message);const prefix='bookstark:frame:test-main-window-proof:bookstark:request:';
    if(!message.startsWith(prefix))return;const request=JSON.parse(message.slice(prefix.length));
    setTimeout(()=>BookStarkHostReply(request.id,request.action==='capabilities'?{version:1}:true,null),0);
   }};
  });
  const proofPage=await proved.newPage();await proofPage.goto(process.env.BOOKSTARK_TEST_ORIGIN+'/shares');
  await proofPage.evaluate(()=>{Object.defineProperty(window,'__BookStarkFrameToken',{value:'test-main-window-proof'});dispatchEvent(new Event('bookstark:frame-ready'));});
  assert.equal(await proofPage.evaluate(()=>BookStarkHost.ready),true);await proofPage.evaluate(()=>BookStarkCopyText('proved clipboard'));
  const requests=await proofPage.evaluate(()=>proofRequests);assert.ok(requests.some(message=>message.startsWith('bookstark:frame:test-main-window-proof:')&&message.includes('clipboard-write')));
  await proved.close();
  const modernAndroid=await browser.newContext();await modernAndroid.addInitScript(()=>{window.modernAndroidRequests=[];window.BookStarkNative={postMessage:payload=>{const request=JSON.parse(payload);modernAndroidRequests.push(request.action);setTimeout(()=>BookStarkHostReply(request.id,true,null),0);}}});
  const androidPage=await modernAndroid.newPage();await androidPage.goto(process.env.BOOKSTARK_TEST_ORIGIN+'/shares');await androidPage.evaluate(()=>BookStarkCopyText('frame-aware Android host'));
  assert.deepEqual(await androidPage.evaluate(()=>modernAndroidRequests),['client','clipboard-write']);await modernAndroid.close();
  const legacy=await browser.newContext({permissions:['clipboard-read','clipboard-write']});
  await legacy.addInitScript(()=>{window.legacyNativeMessages=[];window.chrome=window.chrome||{};window.chrome.webview={postMessage:message=>legacyNativeMessages.push(message)}});
  const oldPage=await legacy.newPage();await oldPage.goto(process.env.BOOKSTARK_TEST_ORIGIN+'/shares');await oldPage.waitForTimeout(1700);
  assert.equal(await oldPage.evaluate(()=>BookStarkHost.available),false);
  await oldPage.evaluate(()=>BookStarkCopyText('Legacy client browser clipboard'));
  assert.equal(await oldPage.evaluate(()=>legacyNativeMessages.length),1,'legacy client only receives feature negotiation');
  await legacy.close();console.log('PASS: native clipboard acknowledgment/failure, chunked export bytes/cancel, iframe canvas print, async leave guard, real LAN HTTP copy fallback');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
