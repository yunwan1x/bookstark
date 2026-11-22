// Pure offline host contract; no browser/Native/ADB/network. Not an engine proof.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
const start=source.indexOf('  function imageSelection() {');
const end=source.indexOf('  async function beginSnapshot() {',start);
assert(start>=0&&end>start,'actual host image functions required');
const code=source.slice(start,end);
const url='https://owned.test/prefix/upload-files/image.png';
function rig(kind='richdoc'){
 let content='actual baseline',changes=0;const calls=[];
 const range={startIndex:2,endIndex:2,zone:'main'};
 const view={state:{selection:{main:{from:2,to:2}}},dispatch(v){calls.push(['dispatch',v]);content='changed';}};
 const instance={instance:{command:{executeImage(){}}},command(name,value){
  if(name==='getRange')return {...range};
  assert.equal(name,'executeImage');calls.push([name,value]);content='changed';
 }};
 const cellRange={startRow:7,endRow:8,startColumn:3,endColumn:4};
 const selectedNode={isConnected:true,nodeObj:{id:'selected-node'}};
 const sheet={getSheetId:()=> 'sheet-a',async insertImage(value,column,row){
   calls.push(['insertImage',value,column,row]);content='changed';return true;
 }};
 if(kind==='spreadsheet'){
   instance.getActiveSheet=()=>sheet;
   instance.getActiveRange=()=>({getRange:()=>({...cellRange})});
 }
 if(kind==='mindmap'){
   instance.currentNodes=[selectedNode];
   instance.reshapeNode=(node,patch)=>{assert.equal(node,selectedNode);
     calls.push(['reshapeNode',patch]);content='changed';};
 }
 const item={generation:1,revision:3,created:Date.now(),normalized:content};
 const ctx={active:{kind,generation:1,readOnly:false,sourceReadOnly:false},ready:true,
  inputLocked:true,closed:false,revision:3,userTouched:false,instance,
  root:{querySelector:()=>({})},window:{CMHtml:{EditorView:{findFromDOM:()=>view}}},
  exports:new Map([['frozen',item]]),current:g=>g===1,stable:v=>v,rawSnapshot:()=>content,
  changed:()=>changes++,state:()=>({ready:true,kind,generation:1,dirty:content!=='actual baseline',inputLocked:true}),
  URL,Date,Promise,Error,JSON,Number,Math};
 vm.createContext(ctx);vm.runInContext(code,ctx);
 item.imageSelection=ctx.imageSelection();
 return {ctx,item,calls,range,view,sheet,cellRange,selectedNode,get changes(){return changes;}};
}
(async()=>{
 let checks=0;
 {
  const h=rig();const result=await h.ctx.insertImageSnapshot('frozen',url,1440,960);
  assert.equal(h.calls.length,1);assert.equal(h.calls[0][0],'executeImage');
  assert.equal(h.calls[0][1].value,url);assert.equal(h.calls[0][1].width,720);
  assert.equal(h.calls[0][1].height,480);assert.equal(result.dirty,true);
  assert.equal(h.changes,1);assert.equal(h.ctx.exports.size,0);checks++;
 }
 {
  const h=rig('html');await h.ctx.insertImageSnapshot('frozen',url,640,480);
  assert.equal(h.calls.length,1);assert.equal(h.calls[0][0],'dispatch');
  const change=h.calls[0][1].changes;
  assert.equal(change.from,2);assert.equal(change.to,2);
  assert.equal(change.insert,'<img src="'+url+'" width="640" height="480" alt="">');checks++;
 }
 for(const mode of ['range','generation','expired','unlocked','readonly','sourceReadonly','revision','missing']){
  const h=rig();
  if(mode==='range')h.range.startIndex=1;
  if(mode==='generation')h.item.generation=2;
  if(mode==='expired')h.item.created=Date.now()-120001;
  if(mode==='unlocked')h.ctx.inputLocked=false;
  if(mode==='readonly')h.ctx.active.readOnly=true;
  if(mode==='sourceReadonly')h.ctx.active.sourceReadOnly=true;
  if(mode==='revision')h.ctx.revision=4;
  if(mode==='missing')h.ctx.exports.clear();
  await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,1,1));
  assert.equal(h.calls.length,0);assert.equal(h.changes,0);checks++;
 }
 for(const kind of ['drawing','presentation']){
  const h=rig(kind);assert.equal(h.item.imageSelection,null);
  await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,1,1));
  assert.equal(h.calls.length,0);checks++;
 }
 for(const kind of ['spreadsheet','mindmap']){
  const h=rig(kind);assert.equal(h.item.imageSelection.kind,kind);
  const result=await h.ctx.insertImageSnapshot('frozen',url,1440,960);
  assert.equal(result.dirty,true);assert.equal(h.changes,1);assert.equal(h.calls.length,1);
  if(kind==='spreadsheet'){
   assert.deepEqual(h.calls[0],['insertImage',url,3,7]);
  }else{
   assert.equal(h.calls[0][0],'reshapeNode');
   assert.equal(h.calls[0][1].image.url,url);
   assert.equal(h.calls[0][1].image.width,720);
   assert.equal(h.calls[0][1].image.height,480);
  }
  checks++;
 }
 for(const mode of ['cell','sheet','rangeMissing','nodeChanged','nodeDisconnected','multiNode']){
  const kind=mode.startsWith('node')||mode==='multiNode'?'mindmap':'spreadsheet';
  const h=rig(kind);
  if(mode==='cell')h.cellRange.startRow++;
  if(mode==='sheet')h.sheet.getSheetId=()=> 'sheet-b';
  if(mode==='rangeMissing')h.ctx.instance.getActiveRange=()=>null;
  if(mode==='nodeChanged')h.selectedNode.nodeObj.id='other-node';
  if(mode==='nodeDisconnected')h.selectedNode.isConnected=false;
  if(mode==='multiNode')h.ctx.instance.currentNodes.push({isConnected:true,nodeObj:{id:'second'}});
  await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,1,1));
  assert.equal(h.calls.length,0);assert.equal(h.changes,0);checks++;
 }
 {
  const h=rig('spreadsheet');h.sheet.insertImage=async()=>false;
  await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,1,1),/refused/);
  assert.equal(h.changes,0);checks++;
 }
 {
  const h=rig('mindmap');h.ctx.instance.reshapeNode=()=>{};
  await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,1,1),/not_observed/);
  assert.equal(h.changes,0);checks++;
 }
 for(const value of ['https://user:fixture@owned.test/prefix/upload-files/a.png',
   url+'?token=not-allowed',url+'#fragment','file:///tmp/a.png']){
  const h=rig();await assert.rejects(h.ctx.insertImageSnapshot('frozen',value,1,1));
  assert.equal(h.calls.length,0);checks++;
 }
 {
  const h=rig();await assert.rejects(h.ctx.insertImageSnapshot('frozen',url,8192,8192));
  assert.equal(h.calls.length,0);checks++;
 }
 console.log(JSON.stringify({status:'PASS',checks,scope:'offline real host functions with mocked actual API ports; not Native/engine proof'}));
})().catch(e=>{console.error(e);process.exitCode=1;});
