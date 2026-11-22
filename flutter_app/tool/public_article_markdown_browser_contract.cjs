
const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs'),http=require('node:http');
const base=process.env.BOOKSTARK_COMPLEX_URL,out=process.env.BOOKSTARK_MARKDOWN_PROOF;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const hits=[];
 const server=http.createServer((req,res)=>{
  hits.push(req.url);res.writeHead(200,{'Content-Type':'image/svg+xml','Access-Control-Allow-Origin':'*'});
  res.end('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="48"><rect width="96" height="48" fill="purple"/></svg>');
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const root='http://127.0.0.1:'+server.address().port+'/bookstark/';
 const browser=await chromium.launch({executablePath:'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const page=await browser.newPage({viewport:{width:390,height:740}});
 await page.addInitScript(()=>{
  window.MathJax={startup:{ready:()=>setTimeout(()=>MathJax.startup.defaultReady(),700)}};
 });
 await page.addInitScript(()=>{
  if(window===window.top){window.__publicEvents=[];window.BookStarkEditorMessages={postMessage:v=>window.__publicEvents.push(JSON.parse(v))};}
 });
 await page.addInitScript(()=>window.addEventListener('unhandledrejection',e=>console.error('REJECTION_DETAIL',String(e.reason),e.reason?.target?.outerHTML)));
 page.on('console',m=>{if(m.type()==='error')console.error('BROWSER_CONSOLE',m.text());});
 page.on('requestfailed',r=>console.error('REQUEST_FAILED',r.url(),r.failure()?.errorText));
 const errors=[];page.on('pageerror',e=>errors.push({message:e.message,stack:e.stack}));
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle'});
  const original='\ufeff\ufeff# 公开文章\r\n\r\n![插图](upload-files/public.svg)\r\n\r\n- 保留 **正文**\r\n\r\n[Open fixture](https://bookstark-article-canary.invalid/link)\r\n\r\n![不可访问](https://bookstark-article-canary.invalid/blocked.png)\r\n\r\n$$x^2+y^2=z^2$$\r\n';
  const bytes=Buffer.from(original),params={length:bytes.length,digest:sha(bytes),root};
  const info=await page.evaluate(p=>BookStarkEditorHost.beginLoad('markdown',p.length,p.digest,{readOnly:true,publicResourceRoot:p.root}),params);
  await page.evaluate(p=>BookStarkEditorHost.appendLoad(p.id,0,p.body),{id:info.id,body:bytes.toString('base64')});
  await page.evaluate(id=>BookStarkEditorHost.commitLoad(id),info.id);
  await page.waitForFunction(()=>BookStarkEditorHost.state().ready);
  const frame=page.frames().find(f=>f.parentFrame()===page.mainFrame());
  assert(frame);await frame.waitForSelector('h1');
  await frame.waitForFunction(()=>Array.from(document.images).some(i=>i.complete&&i.naturalWidth===96));
  assert(hits.includes('/bookstark/upload-files/public.svg'));
  await frame.waitForSelector('mjx-container svg',{timeout:30000});
  await frame.evaluate(()=>{
    const image=document.createElement('img');
    image.src='https://bookstark-article-canary.invalid/blocked.png';
    document.body.append(image);
  });
  await page.waitForFunction(()=>window.__publicEvents.some(e=>e.type==='publicImageFailure'));
  assert.deepEqual(await page.evaluate(()=>window.__publicEvents.filter(e=>e.type==='publicImageFailure')),[{type:'publicImageFailure'}]);
  const previewLocation=await frame.evaluate(()=>location.href);
  const link=frame.getByRole('link',{name:'Open fixture',exact:true});
  await link.evaluate(element=>element.click());
  await page.waitForTimeout(100);
  assert.deepEqual(await page.evaluate(()=>window.__publicEvents.filter(e=>e.type==='publicExternalLink')),[]);
  await link.click();
  await page.waitForFunction(()=>window.__publicEvents.some(e=>e.type==='publicExternalLink'));
  assert.deepEqual(await page.evaluate(()=>window.__publicEvents.filter(e=>e.type==='publicExternalLink')),
   [{type:'publicExternalLink',url:'https://bookstark-article-canary.invalid/link'}]);
  assert(await page.evaluate(()=>navigator.userActivation.isActive));
  assert.equal(await frame.evaluate(()=>location.href),previewLocation);
  assert.equal(await frame.locator('h1').innerText(),'公开文章');
  await link.focus();await page.keyboard.press('Enter');
  await page.waitForFunction(()=>window.__publicEvents.filter(e=>e.type==='publicExternalLink').length===2);
  assert.equal(await frame.evaluate(()=>location.href),previewLocation);
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),original);
  assert(await frame.evaluate(()=>{try{void parent.document.body;return false}catch(_){return true}}));
  assert.equal(await frame.evaluate(()=>typeof window.BookStarkEditorMessages),'undefined');
  await page.getByRole('button',{name:'源码',exact:true}).click();
  const source=page.locator('.markdown-source .cm-content');
  await source.waitFor({state:'visible'});await source.click();await page.keyboard.type('FORBIDDEN_EDIT');
  assert.equal(await page.evaluate(()=>BookStarkEditorHost.getSource()),original);
  await page.getByRole('button',{name:'正文',exact:true}).click();
  assert.equal(await page.getByRole('button',{name:'正文',exact:true}).getAttribute('aria-pressed'),'true');
  assert.deepEqual(errors,[]);
  const rejected=await page.evaluate(root=>{
   let count=0;
   for(const opt of [{readOnly:false,publicResourceRoot:root},{readOnly:true,publicResourceRoot:'file:///bad'}]){
    try{BookStarkEditorHost.beginLoad('markdown',0,'0'.repeat(64),opt)}catch(_){count++}
   }
   try{BookStarkEditorHost.beginLoad('markdown',4*1024*1024+1,'0'.repeat(64),{readOnly:true,publicResourceRoot:root})}catch(_){count++}
   return count;
  },root);
  assert.equal(rejected,3);assert.deepEqual(errors,[]);
  fs.writeFileSync(out,JSON.stringify({passed:true,genuineGoMarkdown:true,opaquePreview:true,prefixedImage:true,delayedMathStartupRendered:true,bundledMathJaxRendered:true,blockedImageFailureReportedWithoutURL:true,mixedBrokenImageAndFormula:true,trustedLinkIntentWithoutFrameNavigation:true,syntheticClickIgnored:true,trustedKeyboardLinkIntent:true,readonlyExactSource:true,invalidPublicModesRejected:3,nativePolicyProven:false},null,2));
  console.log('PASS public Markdown genuine browser contract');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
