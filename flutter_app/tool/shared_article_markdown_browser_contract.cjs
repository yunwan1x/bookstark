
const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs'),http=require('node:http');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const hits=[],errors=[];
 const server=http.createServer((req,res)=>{
  hits.push(req.url);res.writeHead(200,{'Content-Type':'image/svg+xml','Access-Control-Allow-Origin':'*'});
  res.end('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="48"><rect width="96" height="48" fill="purple"/></svg>');
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const root='http://127.0.0.1:'+server.address().port+'/bookstark/';
 const browser=await chromium.launch({executablePath:'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const page=await browser.newPage({viewport:{width:390,height:740}});
 page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{if(window===window.top){window.__events=[];window.BookStarkEditorMessages={postMessage:v=>window.__events.push(JSON.parse(v))};}});
 const source='\ufeff# Shared editing\r\n\r\n![image](upload-files/shared.svg)\r\n\r\n$$x^2+y^2=z^2$$\r\n';
 try{
  await page.goto(process.env.BOOKSTARK_COMPLEX_URL+'/host.html',{waitUntil:'networkidle'});
  const bytes=Buffer.from(source);
  const info=await page.evaluate(p=>BookStarkEditorHost.beginLoad('markdown',p.length,p.sha,{readOnly:false,sharedMarkdownEditing:true,publicResourceRoot:p.root}),{length:bytes.length,sha:sha(bytes),root});
  await page.evaluate(p=>BookStarkEditorHost.appendLoad(p.id,0,p.body),{id:info.id,body:bytes.toString('base64')});
  await page.evaluate(id=>BookStarkEditorHost.commitLoad(id),info.id);
  await page.waitForFunction(()=>BookStarkEditorHost.state().ready);
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  await page.evaluate(()=>window.__originalView=CMHtml.EditorView.findFromDOM(document.querySelector('.cm-editor')));
  const editable=page.locator('.markdown-source .cm-content');
  await editable.click();await page.keyboard.press('Control+End');await page.keyboard.type('LIVE_MARKER');
  await page.waitForFunction(()=>BookStarkEditorHost.getSource().includes('LIVE_MARKER'));
  const changed=await page.evaluate(()=>BookStarkEditorHost.getSource());
  assert(changed.startsWith('\ufeff# Shared editing\r\n'));
  assert(changed.includes('\r\n\r\n![image]'));
  await page.getByRole('button',{name:'预览',exact:true}).click();
  let frame=page.frames().find(f=>f.parentFrame()===page.mainFrame());
  assert(frame);await frame.waitForSelector('h1');
  await frame.waitForSelector('mjx-container svg',{timeout:30000});
  await frame.waitForFunction(()=>Array.from(document.images).some(i=>i.complete&&i.naturalWidth===96));
  assert(hits.includes('/bookstark/upload-files/shared.svg'));
  assert.equal(await frame.evaluate(()=>typeof window.BookStarkEditorMessages),'undefined');
  assert(await frame.evaluate(()=>{try{void parent.document.body;return false}catch(_){return true}}));
  await page.getByRole('button',{name:'编辑',exact:true}).click();
  assert(await page.evaluate(()=>window.__originalView===CMHtml.EditorView.findFromDOM(document.querySelector('.cm-editor'))));
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),changed);
  await page.getByRole('button',{name:'撤销',exact:true}).click();
  await page.waitForFunction(()=>!BookStarkEditorHost.getSource().includes('LIVE_MARKER'));
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  const generation=await page.evaluate(()=>BookStarkEditorHost.state().generation);
  await page.evaluate(g=>BookStarkEditorHost.setInputLocked(true,g),generation);
  await page.keyboard.type('BLOCKED_MARKER');
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  // Capture an actual CM selection under the native input lock.
  // Native Dart never receives DOM offsets; the frozen snapshot owns them.
  await page.evaluate(()=>window.__originalView.dispatch({selection:{anchor:2,head:8}}));
  const captured=await page.evaluate(()=>BookStarkEditorHost.beginSnapshot());
  assert.equal(captured.sha256,sha(Buffer.from(source)));
  await page.evaluate(p=>BookStarkEditorHost.insertMarkdownSnapshot(p.id,p.text),
    {id:captured.id,text:'ATTACHMENT'});
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source.slice(0,2)+'ATTACHMENT'+source.slice(8));
  await assert.rejects(page.evaluate(p=>BookStarkEditorHost.insertMarkdownSnapshot(p.id,p.text),
    {id:captured.id,text:'REPLAY'}));
  const stale=await page.evaluate(()=>BookStarkEditorHost.beginSnapshot());
  // Test changed source rejection even if a buggy caller tries to reuse it.
  await page.evaluate(()=>window.__originalView.dispatch({changes:{from:0,insert:'changed'}}));
  await assert.rejects(page.evaluate(p=>BookStarkEditorHost.insertMarkdownSnapshot(p.id,p.text),
    {id:stale.id,text:'WRONG_SOURCE'}));
  await page.evaluate(id=>BookStarkEditorHost.endSnapshot(id),stale.id);
  await page.evaluate(g=>BookStarkEditorHost.setInputLocked(false,g),generation);
  await editable.click();await page.keyboard.press('Control+End');await page.keyboard.type('SECOND_MARKER');
  await page.waitForFunction(()=>BookStarkEditorHost.getSource().includes('SECOND_MARKER'));
  await page.evaluate(()=>BookStarkEditorHost.retire());
  await assert.rejects(page.evaluate(()=>BookStarkEditorHost.beginSnapshot()));
  assert.deepEqual(errors,[]);
  fs.writeFileSync(process.env.BOOKSTARK_MARKDOWN_PROOF,JSON.stringify({passed:true,actualGoEngine:true,nativeAndroid:false,exactInitialBomCrlf:true,realKeyboardEditing:true,sameCmAcrossPreview:true,undoRestoresExactSource:true,anonymousPrefixImage:true,mathSvg:true,opaquePreview:true,inputLock:true,snapshotSha:true,selectionBoundInsertion:true,replayInsertionRejected:true,changedSourceInsertionRejected:true,retireRejectsCapture:true,errors},null,2));
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
