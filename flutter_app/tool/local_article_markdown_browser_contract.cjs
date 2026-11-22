const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs');
const base=process.env.BOOKSTARK_COMPLEX_URL,out=process.env.BOOKSTARK_MARKDOWN_PROOF;
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
async function load(page,source,readOnly=false){
 const bytes=Buffer.from(source),info=await page.evaluate(({length,digest,readOnly})=>
  BookStarkEditorHost.beginLoad('markdown',length,digest,{readOnly,title:'本地文章'}),{length:bytes.length,digest:sha(bytes),readOnly});
 for(let i=0,n=0;i<bytes.length;i+=262144,n++)await page.evaluate(({id,index,base64})=>
  BookStarkEditorHost.appendLoad(id,index,base64),{id:info.id,index:n,base64:bytes.subarray(i,i+262144).toString('base64')});
 await page.evaluate(id=>BookStarkEditorHost.commitLoad(id),info.id);
 await page.waitForFunction(()=>BookStarkEditorHost.state().ready,null,{timeout:60000});
}
async function source(page){return page.evaluate(()=>BookStarkEditorHost.getSource());}
async function preview(page,readOnly=false){
 await page.getByRole('button',{name:'预览',exact:true}).click();
 const frame=page.frames().find(f=>f.parentFrame()===page.mainFrame());
 assert(frame,'Opaque Markdown preview frame required');
 await frame.waitForSelector('.cherry-markdown',{timeout:35000});
 await page.waitForFunction(()=>document.querySelector('.markdown-preview-notice')?.hidden,null,{timeout:35000});
 return frame;
}
(async()=>{
 assert(base&&out);
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:740}});
 const requests=[],errors=[],consoleErrors=[];
 await context.route('**/*',route=>{
  const url=route.request().url();
  if(!url.startsWith(base+'/')&&!url.startsWith('data:')&&!url.startsWith('blob:')){
   requests.push(url);return route.abort();
  }
  if(url.startsWith(base+'/api/')){requests.push(url);return route.abort();}
  return route.continue();
 });
 await context.addInitScript(()=>{
  if(window===window.top){
   window.__nativeMessages=[];
   window.BookStarkEditorMessages={postMessage:value=>window.__nativeMessages.push(JSON.parse(value))};
  }
 });
 const page=await context.newPage();
 page.on('pageerror',error=>errors.push(error.message));
 page.on('console',message=>{if(message.type()==='error')consoleErrors.push(message.text());});
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});
  const original='\ufeff\ufeff# 阅读计划\r\n\r\n- 每天阅读 20 分钟\r\n- 记录 **三个要点**\r\n';
  await load(page,original);
  assert.equal(await source(page),original);
  const editor=page.locator('.markdown-source .cm-content');
  await editor.click();assert.equal((await page.evaluate(()=>BookStarkEditorHost.state())).dirty,false);
  await page.keyboard.press('Control+End');await page.keyboard.type('REAL_MARKDOWN_EDIT');
  await page.waitForFunction(()=>BookStarkEditorHost.state().dirty);
  const edited=await source(page);
  assert(edited.includes('REAL_MARKDOWN_EDIT')&&edited.startsWith('\ufeff\ufeff'));
  assert(!edited.replace(/\r\n/g,'').includes('\n'),'Uniform original CRLF must survive real edits');
  const frame=await preview(page);
  await frame.waitForSelector('h1');
  assert((await frame.locator('h1').innerText()).includes('阅读计划'));
  assert.equal(await source(page),edited);
  assert.equal(await frame.evaluate(()=>typeof window.BookStarkEditorMessages),'undefined');
  assert(await frame.evaluate(()=>{try{void parent.document.body;return false}catch(_){return true;}}));
  await page.getByRole('button',{name:'返回编辑',exact:true}).click();
  await editor.waitFor({state:'visible'});
  assert.equal(await source(page),edited);
  const snapshot=await page.evaluate(()=>BookStarkEditorHost.beginSnapshot());
  const chunks=[];
  for(let i=0;i<snapshot.chunks;i++){
   const value=await page.evaluate(({id,index})=>BookStarkEditorHost.readSnapshot(id,index),{id:snapshot.id,index:i});
   chunks.push(Buffer.from(value.base64,'base64'));
  }
  const captured=Buffer.concat(chunks);
  assert.equal(sha(captured),snapshot.sha256);assert.equal(captured.toString(),edited);
  await page.evaluate(id=>BookStarkEditorHost.endSnapshot(id),snapshot.id);

  const headingBOM='\ufeff\ufeff# heading\r\nnext\r\n';
  await load(page,headingBOM);
  await editor.click();await page.keyboard.press('Control+Home');
  await page.getByRole('button',{name:'一级标题',exact:true}).click();
  assert.equal(await source(page),'\ufeff\ufeffheading\r\nnext\r\n');
  await page.getByRole('button',{name:'一级标题',exact:true}).click();
  assert.equal(await source(page),headingBOM);
  assert.equal(await page.getByRole('button',{name:'插入链接',exact:true}).locator('svg').count(),1);
  assert.equal(await page.getByRole('button',{name:'撤销',exact:true}).locator('svg').count(),1);
  assert.equal(await page.getByRole('button',{name:'重做',exact:true}).locator('svg').count(),1);

  await load(page,'word');
  await editor.click();await page.keyboard.press('Control+A');
  await page.getByRole('button',{name:'粗体',exact:true}).click();
  assert.equal(await source(page),'**word**');
  await page.getByRole('button',{name:'撤销',exact:true}).click();
  assert.equal(await source(page),'word');
  await page.getByRole('button',{name:'重做',exact:true}).click();
  assert.equal(await source(page),'**word**');

  const hostile='# 安全预览\n\n<script>parent.__markdownAttack=true;<\/script>\n'+
    '<img src="https://bookstark-canary.invalid/steal" onerror="parent.__markdownAttack=true">\n'+
    '[外部链接](https://bookstark-canary.invalid/link)\n';
  await load(page,hostile);
  const hostileFrame=await preview(page);
  assert.equal(await page.evaluate(()=>window.__markdownAttack),undefined);
  assert.equal(await hostileFrame.evaluate(()=>typeof window.BookStarkEditorMessages),'undefined');
  const blocked=await hostileFrame.evaluate(async origin=>{
   let network=false,parentRead=false;
   try{await fetch(origin+'/api/forbidden')}catch(_){network=true}
   try{void parent.document.body}catch(_){parentRead=true}
   parent.postMessage({type:'bookstark-markdown-preview-ready',nonce:'0'.repeat(32),epoch:1},origin);
   return {network,parentRead};
  },base);
  assert(blocked.network&&blocked.parentRead);
  assert.equal(await source(page),hostile);
  assert.equal(await page.evaluate(()=>window.__markdownAttack),undefined);
  assert.equal(requests.length,0,'CSP must reject hostile requests before networking');
  assert.equal(await page.evaluate(()=>window.__nativeMessages.some(m=>m.type==='save'||m.type==='command')),false);

  const readonly='# 只读文章\n\n**保留内容**\n';
  await load(page,readonly,true);
  assert.equal(await source(page),readonly);
  await page.getByRole('button',{name:'查看源码',exact:true}).click();
  await editor.waitFor({state:'visible'});
  await editor.click();await page.keyboard.press('Control+End');await page.keyboard.type('BLOCKED_READONLY');
  assert.equal(await source(page),readonly);
  assert.equal((await page.evaluate(()=>BookStarkEditorHost.state())).dirty,false);
  await page.evaluate(()=>BookStarkEditorHost.retire());
  assert.equal(await page.locator('.markdown-preview-frame').count(),0);
  const report={passed:true,proofScope:'host Chromium genuine Go CM6 and opaque Go Markdown preview; Android pending',
   originalBOMAndCRLFPreserved:true,realKeyboardInputAndExactSnapshot:true,formatUndoRedo:true,
   previewRetainsUnsavedSource:true,opaquePreviewHasNoParentBridge:true,
   hostileMarkupCannotReadParentOrNetwork:true,untrustedMessagesDoNotInvokeNativeCommands:true,
   readOnlyPreventsInput:true,retirementRemovesFrame:true,externalRequests:requests.length,
   pageErrors:errors,actualAndroid:false,all45Complete:false};
  assert.equal(errors.length,0);
  fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});
  console.log('PASS local article Markdown source/opaque preview browser contract');
 }catch(error){
  const frames=[];
  for(const frame of page.frames()){
   try{frames.push(await frame.evaluate(()=>({url:location.href,
    cherry:typeof window.Cherry,common:typeof window.BookStarkEditor,
    bridge:typeof window.BookStarkEditorMessages,root:!!document.getElementById('markdown-preview-root'),
    text:document.body?.innerText.slice(0,600)})))}catch(_){}
  }
  fs.writeFileSync(out.replace(/\.json$/,'-diagnostics.json'),
    JSON.stringify({errors,consoleErrors,frames},null,2)+'\n',{flag:'wx',mode:0o600});
  throw error;
 }finally{await context.close();await browser.close();}
})().catch(error=>{console.error(error.stack);process.exit(1)});
