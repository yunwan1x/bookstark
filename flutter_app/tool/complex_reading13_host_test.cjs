// Offline mock-only draft. No browser/ADB/VM/network. NOT executed in freeze.
const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const {webcrypto}=require('node:crypto');
const code=fs.readFileSync(process.argv[2],'utf8');
function host(kind='richdoc'){
 const state={ready:true,readOnly:true,inputLocked:false,generation:1,kind};
 const viewport={scrollTop:52,scrollLeft:3};
 let selection='Actual selected plain <text>';
 const editor={getSelectionText:()=>selection,command:(name)=>{assert.equal(name,'getRange');return{startIndex:2,endIndex:29,zone:'main'};}};
 const events=new Map();
 const ctx={TextEncoder,TextDecoder,crypto:webcrypto,console,
  setTimeout,clearTimeout,addEventListener:(n,f)=>events.set(n,f),
  removeEventListener:(n)=>events.delete(n)};
 ctx.window=ctx;
 vm.runInNewContext(code,ctx);
 const reader=ctx.BookStarkReading13.create({
  root:{querySelector:()=>viewport},state:()=>state,instance:()=>editor,original:()=>'<p>Exact</p>',
 });
 return {reader,state,viewport,editor,setSelection:v=>selection=v};
}
async function binding(h){
 return {version:1,bookId:4,documentId:9,kind:h.state.kind,
  fullFingerprint:'a'.repeat(64),sourceDigest:Buffer.from(await webcrypto.subtle.digest(
   'SHA-256',new TextEncoder().encode('<p>Exact</p>'))).toString('hex'),
  runtimeLease:'actual-native-lease-123456789',generation:1};
}
(async()=>{
 let pass=0;
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  const got=await h.reader.capture(b,true);
  assert.equal(got.text,'Actual selected plain <text>');assert.equal(got.anchor.top,52);
  assert.equal(got.selectionKind,'text');
  assert.equal(JSON.stringify(got.selection),JSON.stringify({type:'canvasRange',startIndex:2,endIndex:29,zone:'main'}));
  await h.reader.restore(b,{type:'richdocViewport',top:87,left:1});assert.equal(h.viewport.scrollTop,87);pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  h.editor.getSelectionText=()=>{throw Error('must not read giant selection for position');};
  const got=await h.reader.capture(b,false);assert.equal(got.text,'');assert.equal(got.anchor.top,52);pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);h.setSelection('😀'.repeat(9000));
  await assert.rejects(h.reader.capture(b,true));pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  for(const key of ['bookId','documentId','fullFingerprint','runtimeLease','generation']){
   const bad={...b,[key]:key==='generation'?2:'wrong'};
   await assert.rejects(h.reader.capture(bad,true));
  }pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);h.state.generation++;
  await assert.rejects(h.reader.capture(b,false));pass++;
 }
 {
  const h=host(),b=await binding(h);h.state.readOnly=false;
  await assert.rejects(h.reader.bind(b));pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);h.reader.retire();
  await assert.rejects(h.reader.capture(b,true));pass++;
 }
 {
  const h=host(),b=await binding(h);b.sourceDigest='b'.repeat(64);
  await assert.rejects(h.reader.bind(b));pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  delete h.editor.command;
  await assert.rejects(h.reader.capture(b,true),/reading_range_unsupported/);
  // Positions must remain available without a selection range.
  const position=await h.reader.capture(b,false);assert.equal(position.anchor.top,52);pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  for(const range of [
   {startIndex:-1,endIndex:3,zone:'main'},
   {startIndex:4,endIndex:3,zone:'main'},
   {startIndex:3,endIndex:3,zone:'main'},
   {startIndex:0.5,endIndex:3,zone:'main'},
   {startIndex:0,endIndex:1000001,zone:'main'},
   {startIndex:0,endIndex:3,zone:'unknown'},
  ]){
   h.editor.command=()=>range;
   await assert.rejects(h.reader.capture(b,true),/reading_range_unsupported/);
  }pass++;
 }
 {
  const h=host(),b=await binding(h);await h.reader.bind(b);
  h.editor.command=()=>({startIndex:999999,endIndex:1000000,zone:'footer'});
  const got=await h.reader.capture(b,true);
  assert.equal(got.selection.startIndex,999999);assert.equal(got.selection.endIndex,1000000);assert.equal(got.selection.zone,'footer');pass++;
 }
 process.stdout.write(JSON.stringify({mockOnly:true,passed:pass})+'\n');
})().catch(()=>{process.stderr.write('mock reading protocol failed\n');process.exitCode=1;});
