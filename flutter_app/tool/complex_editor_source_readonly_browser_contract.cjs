// Real browser contract for immutable HTML CodeMirror source.
const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const crypto=require('node:crypto');
const base=process.env.BOOKSTARK_COMPLEX_URL;
const source='\uFEFF\uFEFF<!doctype html>\r\n<html>\r\n<head><title>readonly-fixture</title></head>\r\n<body><p>Copy this exact visible text: READONLY_COPY_TOKEN \u53ea\u8bfb \ud83e\udded</p>\r\n<script>window.__readonlyScriptRan=(window.__readonlyScriptRan||0)+1;</script>\r\n</body>\r\n</html>\r\n';
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
function check(v,m){if(!v)throw Error(m)}
async function loadReadonly(page){
 const bytes=Buffer.from(source,'utf8'),sha=digest(bytes);
 const load=await page.evaluate(({n,sha})=>window.BookStarkEditorHost.beginLoad('html',n,sha,{readOnly:false,sourceReadOnly:true,title:'Readonly source contract'}),{n:bytes.length,sha});
 for(let off=0,i=0;off<bytes.length;off+=262144,i++){
  const part=bytes.subarray(off,off+262144);
  await page.evaluate(({id,i,b64})=>window.BookStarkEditorHost.appendLoad(id,i,b64),{id:load.id,i,b64:part.toString('base64')});
 }
 const receipt=await page.evaluate(id=>window.BookStarkEditorHost.commitLoad(id),load.id);
 await page.waitForFunction(()=>window.BookStarkEditorHost.state().ready,null,{timeout:30000});
 const state=await page.evaluate(()=>window.BookStarkEditorHost.state());
 check(receipt.sourceReadOnly===true&&receipt.inputLocked===true,'readonly load receipt did not confirm locked source mode');
 check(state.sourceReadOnly===true&&state.inputLocked===true&&state.readOnly===false,'host state is not locked CodeMirror source mode');
 check(await page.evaluate(()=>document.querySelectorAll('#html-editor-container iframe').length)===0,'readonly source mode rendered an HTML iframe');
 check(await page.evaluate(()=>window.__readonlyScriptRan===undefined),'fixture script executed in readonly source mode');
 check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'BOM/CRLF source did not round-trip exactly before interaction');
 return {bytes,sha};
}
async function run(){
 check(base,'BOOKSTARK_COMPLEX_URL is required');
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:1280,height:800}});
 await context.grantPermissions(['clipboard-read','clipboard-write']);
 const page=await context.newPage();
 await page.addInitScript(()=>{
  window.__readonlyDragEntries=0;
  window.addEventListener('dragenter',event=>{if(event.isTrusted)window.__readonlyDragEntries++},true);
 });
 let statusEvents=0,saveEvents=0;
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});
  const original=await loadReadonly(page);
  await page.evaluate(()=>{window.__readonlyStateEvents=0;window.__readonlySaveEvents=0;window.addEventListener('bookstark-editor-state',()=>window.__readonlyStateEvents++);window.addEventListener('bookstark-editor-save',()=>window.__readonlySaveEvents++)});
  const editor=page.locator('#html-editor-container .cm-content');
  await editor.waitFor({state:'visible',timeout:15000});
  check(await editor.getAttribute('tabindex')==='0','CodeMirror readonly content is not keyboard-focusable');
  check(await editor.getAttribute('aria-readonly')==='true','CodeMirror readonly accessibility state is absent');
  await editor.click({position:{x:30,y:20}});
  check(await editor.evaluate(el=>document.activeElement===el),'mouse click did not focus readonly CodeMirror');
  await page.keyboard.press('Control+A');
  const selection=await page.evaluate(()=>{
   const view=window.CMHtml.EditorView.findFromDOM(document.querySelector('#html-editor-container .cm-editor'));
   const range=view.state.selection.main;
   return {doc:view.state.doc.toString(),from:range.from,to:range.to,text:view.state.sliceDoc(range.from,range.to),dom:window.getSelection()?.toString()||''};
  });
  check(selection.from===0&&selection.to===selection.doc.length,'trusted Ctrl+A did not select the complete CodeMirror document');
  check(selection.doc===source.replace(/\r\n|\r/g,'\n'),'actual CodeMirror document differs from normalized source');
  check(selection.dom.includes('READONLY_COPY_TOKEN')&&selection.dom.includes('只读'),'trusted keyboard selection did not select visible source text');
  // BOM widgets display placeholder glyphs; clipboard must carry source text.
  const selected=selection.text;
  await page.keyboard.press('Control+C');
  const copied=await page.evaluate(()=>navigator.clipboard.readText());
  check(copied===selected,'clipboard text differs from the actual selected source text');
  check(Buffer.byteLength(copied,'utf8')>0,'clipboard selection was empty');
  const selectedSha=digest(Buffer.from(selected,'utf8'));
  const copiedSha=digest(Buffer.from(copied,'utf8'));
  check(copiedSha===selectedSha,'clipboard bytes do not match selected source text');
  await page.evaluate(async()=>navigator.clipboard.writeText('PASTE_BLOCKED'));
  await page.keyboard.press('End');
  await page.keyboard.type('KEYBOARD_BLOCKED');
  await page.keyboard.press('Control+V');
  await page.keyboard.press('Control+Z');
  await page.keyboard.press('Control+Y');
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Control+X');
  await page.keyboard.press('Control+S');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'keyboard, paste, cut, undo/redo or Ctrl+S changed readonly source');
  check(digest(Buffer.from(await page.evaluate(()=>window.BookStarkEditorHost.getSource()),'utf8'))===original.sha,'blocked editing changed exact source SHA');
  const state=await page.evaluate(()=>window.BookStarkEditorHost.state());
  check(state.dirty===false&&state.revision===0,'blocked readonly input changed dirty/revision state');
  check(await page.evaluate(()=>window.CMHtml.EditorView.findFromDOM(document.querySelector('#html-editor-container .cm-editor')).state.doc.toString())===selection.doc,'blocked editing changed actual CodeMirror document');
  check(await page.evaluate(()=>window.__readonlySaveEvents)===0,'Ctrl+S emitted a save request in readonly source mode');
  const cannotUnlock=await page.evaluate(()=>{try{window.BookStarkEditorHost.setInputLocked(false,window.BookStarkEditorHost.state().generation);return false}catch(e){return e.message==='source_read_only'}});
  check(cannotUnlock,'readonly source lock was removable');
  // Start in a separate frame, outside the host's dragstart gate, so a real
  // external drag gesture reaches the readonly editor.
  await page.evaluate(()=>{
   const f=document.createElement('iframe');f.id='readonly-drag-frame';
   f.style.cssText='position:fixed;left:10px;top:700px;width:140px;height:70px;z-index:99999';
   f.srcdoc='<html><body><div id="payload" draggable="true" style="padding:12px">DROP_BLOCKED</div></body></html>';
   document.body.append(f);
  });
  const frame=await (await page.$('#readonly-drag-frame')).contentFrame();
  await frame.locator('#payload').waitFor({state:'visible'});
  await frame.evaluate(()=>document.querySelector('#payload').addEventListener('dragstart',event=>event.dataTransfer.setData('text/plain','DROP_BLOCKED')));
  const from=await frame.locator('#payload').boundingBox(),to=await editor.boundingBox();
  await page.mouse.move(from.x+20,from.y+20);
  await page.mouse.down();
  await page.mouse.move(from.x+45,from.y+20,{steps:5});
  await page.mouse.move(to.x+180,to.y+40,{steps:25});
  await page.mouse.up();
  check(await page.evaluate(()=>window.__readonlyDragEntries)>0,'external trusted drag did not reach host');
  check(await page.evaluate(()=>window.CMHtml.EditorView.findFromDOM(document.querySelector('#html-editor-container .cm-editor')).state.doc.toString())===selection.doc,'external drag changed actual readonly document');
  await page.locator('#readonly-drag-frame').evaluate(el=>el.remove());
  const snapshot=await page.evaluate(()=>window.BookStarkEditorHost.beginSnapshot());
  try{
   const chunks=[];
   for(let i=0;i<snapshot.chunks;i++){
    const part=await page.evaluate(({id,i})=>window.BookStarkEditorHost.readSnapshot(id,i),{id:snapshot.id,i});
    check(part.index===i&&part.id===snapshot.id,'snapshot chunk identity differs');
    chunks.push(Buffer.from(part.base64,'base64'));
   }
   const bytes=Buffer.concat(chunks);
   check(bytes.equals(original.bytes)&&digest(bytes)===snapshot.sha256,'readonly snapshot changed consecutive BOM/CRLF bytes');
  }finally{await page.evaluate(id=>window.BookStarkEditorHost.endSnapshot(id),snapshot.id)}
  await page.evaluate(()=>window.BookStarkEditorHost.retire());
  await page.waitForTimeout(250);
  const retired=await page.evaluate(()=>({state:window.BookStarkEditorHost.state(),events:window.__readonlyStateEvents,saves:window.__readonlySaveEvents,view:!!document.querySelector('#html-editor-container .cm-content')}));
  check(retired.state.ready===false&&!retired.view,'retire left the old CodeMirror view mounted');
  check(retired.events===0&&retired.saves===0,'retired view emitted stale state/save events');
  console.log('PASS readonly CodeMirror actual document focus/select/clipboard; blocked type/paste/cut/undo/redo/save and trusted external drag; exact double-BOM+CRLF chunked snapshot; no script/iframe; clean retire');
 }finally{await context.close();await browser.close()}
}
run().catch(e=>{console.error('FAIL readonly source browser candidate: '+String(e&&e.message||e).split('\n')[0]);process.exit(1)});
