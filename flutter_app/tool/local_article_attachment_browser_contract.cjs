const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../assets/complex_editors');
const output=process.argv[2];assert(output&&!fs.existsSync(output));
const mimes={html:'text/html',js:'application/javascript',css:'text/css',json:'application/json',svg:'image/svg+xml',woff2:'font/woff2',woff:'font/woff',ttf:'font/ttf'};
(async()=>{
 const requests=[];
 const server=http.createServer((req,res)=>{
  const pathname=new URL(req.url,'http://127.0.0.1').pathname;
  if(pathname==='/__bookstark_local_image/'+'a'.repeat(32)+'/image.png'){
   res.writeHead(200,{'Content-Type':'image/png','Access-Control-Allow-Origin':'*','Cache-Control':'no-store'});
   res.end(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64'));return;
  }
  const name=path.resolve(root,'.'+decodeURIComponent(pathname));
  if(!name.startsWith(root+'/')){res.writeHead(403);res.end();return;}
  fs.readFile(name,(error,data)=>{if(error){res.writeHead(404);res.end();return;}
   res.writeHead(200,{'Content-Type':mimes[path.extname(name).slice(1)]||'application/octet-stream','Access-Control-Allow-Origin':'*','Cache-Control':'no-store'});res.end(data);});
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({executablePath:'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const page=await browser.newPage({viewport:{width:390,height:740}});
 await page.addInitScript(()=>{if(window===window.top){window.__events=[];window.BookStarkEditorMessages={postMessage:v=>window.__events.push(JSON.parse(v))};}});
 page.on('request',r=>requests.push(r.url()));
 const legacyURL=process.argv[3]==='--legacy-custom-url';
 assert(process.argv[3]===undefined||legacyURL);
 if(legacyURL)await page.addInitScript(()=>{
  const OriginalURL=window.URL;
  window.URL=class extends OriginalURL{
   constructor(input,base){
    if(typeof input==='string'&&input.startsWith('bookstark-attachment:'))
     throw new TypeError('Legacy custom-scheme URL parsing is unavailable');
    super(input,base);
   }
  };
 });
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 try {
  await page.goto(base+'/host.html',{waitUntil:'networkidle'});
  const uri='bookstark-attachment:///'+'a'.repeat(32)+'/image.png';
  const codeFence=String.fromCharCode(96).repeat(3);
  const source='\ufeff# 本地图片\r\n\r\n![叶片](<'+uri+'>)\r\n\r\n'+codeFence+'\r\n'+uri+'\r\n'+codeFence+'\r\n\r\n😀尾';
  const bytes=Buffer.from(source);
  const receipt=await page.evaluate(p=>BookStarkEditorHost.beginLoad('markdown',p.length,p.digest,{readOnly:false,localMarkdownImages:true}),{length:bytes.length,digest:crypto.createHash('sha256').update(bytes).digest('hex')});
  await page.evaluate(p=>BookStarkEditorHost.appendLoad(p.id,0,p.data),{id:receipt.id,data:bytes.toString('base64')});
  await page.evaluate(id=>BookStarkEditorHost.commitLoad(id),receipt.id);
  const start=source.indexOf('😀');
  await page.evaluate(()=>{
   const view=CMHtml.EditorView.findFromDOM(document.querySelector('.cm-editor'));
   view.dispatch({selection:{anchor:view.state.doc.length-3,head:view.state.doc.length-1}});
  });
  await page.evaluate(()=>BookStarkEditorHost.setInputLocked(true,BookStarkEditorHost.state().generation));
  const snapshot=await page.evaluate(()=>BookStarkEditorHost.beginSnapshot());
  assert.deepEqual(snapshot.markdownSelection,{anchor:start,head:start+2});
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  await page.evaluate(id=>BookStarkEditorHost.endSnapshot(id),snapshot.id);
  await page.evaluate(()=>BookStarkEditorHost.setInputLocked(false,BookStarkEditorHost.state().generation));
  assert.equal(await page.getByRole('button',{name:'编辑',exact:true}).getAttribute('aria-pressed'),'true');
  await page.getByRole('button',{name:'预览',exact:true}).click();
  assert.equal(await page.getByRole('button',{name:'预览',exact:true}).getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator('.markdown-toolbar').isVisible(),false);
  await page.getByRole('button',{name:'编辑',exact:true}).click();
  assert.equal(await page.getByRole('button',{name:'编辑',exact:true}).getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator('.markdown-toolbar').isVisible(),true);
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  await page.getByRole('button',{name:'预览',exact:true}).click();
  const frame=page.frames().find(f=>f.parentFrame()===page.mainFrame());assert(frame);
  await frame.waitForSelector('h1');
  const images=await frame.locator('img').evaluateAll(nodes=>nodes.map(n=>({raw:n.getAttribute('src'),resolved:n.src})));
  assert(images.some(i=>i.raw===base+'/__bookstark_local_image/'+'a'.repeat(32)+'/image.png'),'Go image callback must map only the presented URL to its owned endpoint');
  await frame.waitForFunction(()=>Array.from(document.images).some(i=>i.complete&&i.naturalWidth===1));

  assert((await frame.locator('pre').allTextContents()).some(text=>text.includes(uri)));
  await frame.evaluate(()=>{
   const image=document.createElement('img');image.src='https://bookstark-local-attachment-canary.invalid/blocked.png';document.body.append(image);
  });
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='localImageFailure'));
  assert.equal(await frame.evaluate(()=>typeof window.BookStarkEditorMessages),'undefined');
  assert(await frame.evaluate(()=>{try{void parent.document.body;return false}catch(_){return true}}));
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),source);
  assert.deepEqual(errors,[]);
  fs.writeFileSync(output,JSON.stringify({passed:true,separateEditPreviewTabs:true,formatToolbarHiddenInPreview:true,customSchemeURLParserRequired:false,legacyCustomURLProbe:legacyURL,actualGoEngine:true,opaquePreview:true,opaqueAttachmentURIUnchangedInSource:true,presentationOnlyOwnedImageMapping:true,actualRasterImageRendered:true,sourceExactBomCrlf:true,astralSelectionMappedToExactRawSource:true,codeBlockReferenceUnchanged:true,blockedRemoteImageReported:true,desktopDoesNotProveAndroidResourceInterception:true,externalHttpRequests:requests.filter(u=>/^https?:/.test(u)&&!u.startsWith(base+'/')).length,errors},null,2),{flag:'wx',mode:0o600});
  console.log('PASS local article attachment Go rendering, exact source/selection, unchanged code block and blocked networking.');
 } finally {await browser.close();await new Promise(r=>server.close(r));}
})().catch(error=>{console.error(error.stack);process.exitCode=1;});

