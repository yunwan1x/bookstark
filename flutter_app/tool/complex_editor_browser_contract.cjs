const {chromium}=require('/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
const crypto=require('node:crypto');
const base=process.env.BOOKSTARK_COMPLEX_URL;
const markerOne='<!-- REAL_USER_EDIT_ONE -->',markerTwo='<!-- REAL_USER_EDIT_TWO -->';
function check(value,message){if(!value)throw new Error(message)}
function hash(bytes){return crypto.createHash('sha256').update(bytes).digest('hex')}
function b64(bytes){return Buffer.from(bytes).toString('base64')}
async function loadChunks(page,kind,source,readOnly=false){
 const bytes=Buffer.from(source,'utf8'),sha=hash(bytes);
 const load=await page.evaluate(({kind,length,sha,readOnly})=>window.BookStarkEditorHost.beginLoad(kind,length,sha,{readOnly,title:'User edit contract'}),{kind,length:bytes.length,sha,readOnly});
 for(let offset=0,index=0;offset<bytes.length;offset+=262144,index++){
  await page.evaluate(({id,index,base64})=>window.BookStarkEditorHost.appendLoad(id,index,base64),{id:load.id,index,base64:b64(bytes.subarray(offset,offset+262144))});
 }
 await page.evaluate(id=>window.BookStarkEditorHost.commitLoad(id),load.id);
 await page.waitForFunction(()=>window.BookStarkEditorHost.state().ready, null, {timeout:60000});
}
async function snapshot(page){
 const info=await page.evaluate(()=>window.BookStarkEditorHost.beginSnapshot());const chunks=[];
 for(let i=0;i<info.chunks;i++){
  const chunk=await page.evaluate(({id,i})=>window.BookStarkEditorHost.readSnapshot(id,i),{id:info.id,i});
  chunks.push(Buffer.from(chunk.base64,'base64'));
 }
 const bytes=Buffer.concat(chunks);check(bytes.length===info.bytes,'snapshot byte length mismatch');check(hash(bytes)===info.sha256,'snapshot SHA mismatch');
 return {info,bytes};
}
async function waitDirty(page){await page.waitForFunction(()=>window.BookStarkEditorHost.state().dirty,{timeout:15000})}
async function editHtml(browser){
 const source='<!doctype html><html><head><meta charset="utf-8"><title>Original</title></head><body><p>Original text</p></body></html>\n';
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});await loadChunks(page,'html',source);
  const editor=page.locator('.cm-content');await editor.waitFor({state:'visible',timeout:15000});
  await editor.click({position:{x:28,y:20}});
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,'HTML selection-only click marked content dirty');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'HTML selection-only click changed original source');
  const htmlGeneration=(await page.evaluate(()=>window.BookStarkEditorHost.state())).generation;
  const badHtmlLock=await page.evaluate(g=>{try{window.BookStarkEditorHost.setInputLocked(true,g+1);return false}catch(e){return e.message==='invalid_input_lock'}},htmlGeneration);
  check(badHtmlLock,'HTML wrong-generation input lock was not rejected');
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).inputLocked===false,'HTML wrong-generation lock changed lock state');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'HTML wrong-generation lock changed source');
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(true,g),htmlGeneration);
  await editor.click({force:true,position:{x:28,y:20}});
  await page.keyboard.press('Control+End');await page.keyboard.type('BLOCKED_HTML');
  await page.keyboard.press('Control+V');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'locked HTML keyboard/paste input changed source');
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,'locked HTML keyboard/paste input marked document dirty');
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(false,g),htmlGeneration);
  await page.evaluate(()=>{window.__contractRevisions=[];window.addEventListener('bookstark-editor-state',e=>{if(e.detail&&e.detail.dirty)window.__contractRevisions.push(e.detail.revision)})});
  const startRevision=(await page.evaluate(()=>window.BookStarkEditorHost.state())).revision;
  await editor.click({position:{x:28,y:20}});
  await page.keyboard.press('Control+End');await page.keyboard.type(markerOne);await waitDirty(page);
  await page.waitForFunction(()=>window.__contractRevisions.length>=1,null,{timeout:10000});
  const firstRevision=Math.max(...await page.evaluate(()=>window.__contractRevisions));
  check(firstRevision>startRevision,'first HTML edit did not emit a revision');
  let edited=await page.evaluate(()=>window.BookStarkEditorHost.getSource());
  check(edited.includes(markerOne),'HTML keyboard input did not reach CodeMirror source');
  const frozen=await snapshot(page);const frozenSource=frozen.bytes.toString('utf8');
  check(frozenSource.includes(markerOne),'HTML snapshot omitted first real edit');
  await page.keyboard.press('Control+End');await page.keyboard.type(markerTwo);await waitDirty(page);
  await page.waitForFunction(r=>window.__contractRevisions.some(value=>value>r),firstRevision,{timeout:10000});
  const secondRevision=Math.max(...await page.evaluate(()=>window.__contractRevisions));
  check(secondRevision>firstRevision,'continued dirty HTML input did not emit a newer revision');
  await page.evaluate(id=>window.BookStarkEditorHost.acknowledgeSnapshot(id),frozen.info.id);
  const state=await page.evaluate(()=>window.BookStarkEditorHost.state());check(state.dirty===true,'HTML snapshot acknowledgement cleared a newer edit');
  edited=await page.evaluate(()=>window.BookStarkEditorHost.getSource());
  check(edited.includes(markerOne)&&edited.includes(markerTwo),'HTML acknowledgement discarded an edit made after the snapshot');
  check(edited.includes('<title>Original</title>'),'HTML edit discarded untouched source');
  await page.evaluate(()=>window.BookStarkEditorHost.retire());
  console.log('PASS HTML selection no-op, stale-generation rejection, locked keyboard/paste blocked, successive dirty edits emit increasing revisions, and acknowledgement preserves newer edit');
 }finally{await page.close()}
}

async function htmlUndoRestoresExactSource(browser){
 const fixtures=[
  {name:'BOM and CRLF',source:'\uFEFF<!doctype html>\r\n<html>\r\n<body>\r\n<p>Original CRLF</p>\r\n</body>\r\n</html>\r\n'},
  {name:'mixed CRLF/LF/CR',source:'<!doctype html>\r\n<html>\n<body>\r<p>Original mixed</p>\n</body>\r\n</html>\r'}
 ];
 for(const fixture of fixtures){
  const page=await browser.newPage({viewport:{width:1280,height:800}});
  try{
   await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});
   await loadChunks(page,'html',fixture.source);
   const editor=page.locator('.cm-content');await editor.waitFor({state:'visible',timeout:15000});
   check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===fixture.source,fixture.name+': initial raw source did not round-trip exactly');
   await editor.click({position:{x:24,y:18}});
   check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,fixture.name+': selection marked source dirty');
   await page.keyboard.press('Control+End');
   await page.keyboard.type('<!-- trusted edit -->');
   await waitDirty(page);
   check((await page.evaluate(()=>window.BookStarkEditorHost.getSource())).includes('trusted edit'),fixture.name+': trusted input was absent');
   await page.keyboard.press('Control+Z');
   await page.waitForFunction(()=>!window.BookStarkEditorHost.state().dirty,null,{timeout:10000});
   check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,fixture.name+': undo to original visible text remained dirty');
   check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===fixture.source,fixture.name+': undo did not restore exact original bytes/newlines');
   await page.keyboard.press('Control+Shift+Z');
   await waitDirty(page);
   check((await page.evaluate(()=>window.BookStarkEditorHost.getSource())).includes('trusted edit'),fixture.name+': redo did not restore edited text');
   check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===true,fixture.name+': redo failed to mark source dirty');
   await page.evaluate(()=>window.BookStarkEditorHost.retire());
   console.log('PASS HTML trusted edit/undo/redo newline fixture: '+fixture.name);
  }finally{await page.close()}
 }
}

async function readonlyCapture(browser){
 const source='<!doctype html><html><body><p>Read-only original</p></body></html>\n';
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});await loadChunks(page,'html',source,true);
  await page.evaluate(()=>{window.__readonlyRevisionEvents=[];window.addEventListener('bookstark-editor-state',e=>{window.__readonlyRevisionEvents.push(e.detail.revision)})});
  const before=await page.evaluate(()=>window.BookStarkEditorHost.state());
  for(let i=0;i<3;i++){
   const frozen=await snapshot(page);
   check(frozen.bytes.toString('utf8')===source,'read-only capture changed exact source');
   await page.evaluate(id=>window.BookStarkEditorHost.endSnapshot(id),frozen.info.id);
   const state=await page.evaluate(()=>window.BookStarkEditorHost.state());
   check(state.revision===before.revision,'read-only capture incremented editor revision');
  }
  await page.waitForTimeout(250);
  const after=await page.evaluate(()=>({state:window.BookStarkEditorHost.state(),events:window.__readonlyRevisionEvents}));
  check(after.state.revision===before.revision,'repeated read-only capture caused revision churn');
  check(after.events.length===0,'read-only capture emitted state events');
  await page.evaluate(()=>window.BookStarkEditorHost.retire());
  console.log('PASS repeated read-only captures preserve exact source without revision/event churn');
 }finally{await page.close()}
}
async function editSpreadsheet(browser){
 const id='real-univer-edit-workbook';
 const source=JSON.stringify({id,name:'Edit contract',appVersion:'0.25.1',locale:'zhCN',futureRoot:{futureFlag:'preserve-root'},styles:{},sheetOrder:['sheet-edit'],sheets:{'sheet-edit':{id:'sheet-edit',name:'Sheet1',rowCount:1000,columnCount:26,defaultColumnWidth:100,defaultRowHeight:36,freeze:{startRow:-1,startColumn:-1,ySplit:0,xSplit:0},rowData:{},columnData:{},mergeData:[],cellData:{0:{0:{v:'Item',t:1}},1:{0:{v:'Design',t:1},1:{v:1200,t:2,futureCell:{futureFlag:'preserve-B2'}}},2:{0:{v:'Build',t:1},1:{v:3600,t:2}},3:{0:{v:'Total',t:1},1:{v:-999,t:2,f:'=SUM(B2:B3)',futureFormula:{futureFlag:'preserve-formula'}}}}}}});
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 try{
  await page.goto(base+'/host.html',{waitUntil:'networkidle',timeout:60000});await loadChunks(page,'spreadsheet',source);
  await page.waitForFunction(()=>{const c=document.querySelector('#univer-sheet');return c&&c.style.visibility!=='hidden'&&c.querySelectorAll('canvas').length>0},null,{timeout:30000});
  const before=await page.evaluate(()=>window.BookStarkEditorHost.getSource());check(before===source,'spreadsheet source changed during initial load');
  const metrics=await page.evaluate(()=>Array.from(document.querySelectorAll('#univer-sheet canvas')).map((c,i)=>{const r=c.getBoundingClientRect();return {i,x:r.x,y:r.y,width:r.width,height:r.height,cls:c.className}}).filter(r=>r.width>20&&r.height>20));
  console.log('Univer canvas metrics '+JSON.stringify(metrics));
  const grid=metrics.find(c=>c.width>200&&c.height>200);check(grid,'editable Univer grid canvas unavailable');
  const cellX=grid.x+75,cellY=grid.y+48;
  const b2X=cellX+100,b2Y=cellY+36;
  await page.mouse.click(b2X,b2Y);
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,'selection-only click with stale formula cache marked spreadsheet dirty');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'selection-only click or stale formula cache changed original spreadsheet source');
  const sheetGeneration=(await page.evaluate(()=>window.BookStarkEditorHost.state())).generation;
  const badSheetLock=await page.evaluate(g=>{try{window.BookStarkEditorHost.setInputLocked(true,g+1);return false}catch(e){return e.message==='invalid_input_lock'}},sheetGeneration);
  check(badSheetLock,'spreadsheet wrong-generation input lock was not rejected');
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).inputLocked===false,'spreadsheet wrong-generation lock changed lock state');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'spreadsheet wrong-generation lock changed source');
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(true,g),sheetGeneration);
  await page.mouse.dblclick(b2X,b2Y);await page.keyboard.press('Control+A');await page.keyboard.type('7777');await page.keyboard.press('Enter');
  check(await page.evaluate(()=>window.BookStarkEditorHost.getSource())===source,'locked spreadsheet keyboard input changed source');
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===false,'locked spreadsheet keyboard input marked document dirty');
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(false,g),sheetGeneration);
  await page.mouse.dblclick(b2X,b2Y);await page.keyboard.press('Control+A');await page.keyboard.type('1500');await page.keyboard.press('Enter');
  // Lock and snapshot immediately. The host must wait for Univer's calculation
  // result barrier before capturing the dirty workbook's cached formula value.
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(true,g),sheetGeneration);
  const frozen=await snapshot(page);
  let edited=JSON.parse(await page.evaluate(()=>window.BookStarkEditorHost.getSource()));
  const cells=edited.sheets['sheet-edit'].cellData;
  if(cells['3']['1'].v!==5100)console.log('Univer immediate snapshot formula observation '+JSON.stringify({B2:cells['1']&&cells['1']['1']&&cells['1']['1'].v,B3:cells['2']&&cells['2']['1']&&cells['2']['1'].v,B4:cells['3']&&cells['3']['1']&&cells['3']['1'].v,formula:cells['3']&&cells['3']['1']&&cells['3']['1'].f}));
  check(cells['3']['1'].v===5100,'Univer immediate locked snapshot formula cache did not recalculate B4 to 5100');
  check(edited.id===id,'spreadsheet edit changed workbook id');check(edited.futureRoot?.futureFlag==='preserve-root','spreadsheet edit dropped unknown root field');
  check(cells['1']['1'].v===1500,'spreadsheet keyboard edit did not update B2');
  check(cells['1']['1'].futureCell?.futureFlag==='preserve-B2','spreadsheet edit dropped unknown B2 field');
  check(cells['3']['1'].f==='=SUM(B2:B3)','spreadsheet edit dropped B4 formula');
  check(cells['3']['1'].futureFormula?.futureFlag==='preserve-formula','spreadsheet edit dropped unknown formula-cell field');
  const frozenDoc=JSON.parse(frozen.bytes.toString('utf8'));
  check(frozenDoc.sheets['sheet-edit'].cellData['3']['1'].v===5100,'immediate locked spreadsheet snapshot omitted recalculated formula cache');
  await page.evaluate(g=>window.BookStarkEditorHost.setInputLocked(false,g),sheetGeneration);
  await page.mouse.dblclick(b2X,b2Y);await page.keyboard.press('Control+A');await page.keyboard.type('1600');await page.keyboard.press('Enter');await waitDirty(page);
  await page.waitForFunction(()=>JSON.parse(window.BookStarkEditorHost.getSource()).sheets['sheet-edit'].cellData['3']['1'].v===5200,null,{timeout:20000});
  await page.evaluate(sid=>window.BookStarkEditorHost.acknowledgeSnapshot(sid),frozen.info.id);
  check((await page.evaluate(()=>window.BookStarkEditorHost.state())).dirty===true,'spreadsheet snapshot acknowledgement cleared a newer edit');
  edited=JSON.parse(await page.evaluate(()=>window.BookStarkEditorHost.getSource()));
  check(edited.sheets['sheet-edit'].cellData['1']['1'].v===1600,'spreadsheet acknowledgement discarded newer B2 edit');
  check(edited.sheets['sheet-edit'].cellData['3']['1'].v===5200,'spreadsheet acknowledgement discarded newer formula cache');
  check(edited.id===id&&edited.futureRoot?.futureFlag==='preserve-root','spreadsheet acknowledgement lost root identity/unknown field');
  check(edited.sheets['sheet-edit'].cellData['1']['1'].futureCell?.futureFlag==='preserve-B2','spreadsheet acknowledgement lost unknown B2 field');
  check(edited.sheets['sheet-edit'].cellData['3']['1'].f==='=SUM(B2:B3)'&&edited.sheets['sheet-edit'].cellData['3']['1'].futureFormula?.futureFlag==='preserve-formula','spreadsheet acknowledgement lost B4 formula metadata');
  await page.evaluate(()=>window.BookStarkEditorHost.retire());
  console.log('PASS Univer selection no-op, stale-generation rejection, locked keyboard edit blocked, unlocked real B2 edit, immediate locked snapshot recalculates B4, and acknowledgement retains newer edit');
 }finally{await page.close()}
}
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try{await editHtml(browser);await htmlUndoRestoresExactSource(browser);await readonlyCapture(browser);await editSpreadsheet(browser)}finally{await browser.close()}
})().catch(error=>{console.error('FAIL real edit browser contract: '+String(error&&error.message||error).split('\n')[0]);process.exit(1)});
