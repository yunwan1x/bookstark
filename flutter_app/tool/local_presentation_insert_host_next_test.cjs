'use strict';
// Runs the actual own-host insertion command. PPTist is a narrow port mock.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
const a=source.indexOf('  async function insertLocalPresentationImageSnapshot(');
const b=source.indexOf('  async function insertLocalMindmapImageSnapshot(',a);
assert(a>=0&&b>a);
const implementation=source.slice(a,b),uri='bookstark-attachment:///'+'a'.repeat(32)+'/a.png';
const resourceId='b'.repeat(64),runtime='https://editor.test/local-presentation/'+'c'.repeat(64)+'/'+resourceId;
function fixture() {
 const doc={slides:[{id:'actual',elements:[],unknown:42}],unknown:'keep'};
 const selected={kind:'presentation',slideId:'actual',elementIds:[]};
 const state={source:JSON.stringify(doc),closed:false,calls:0,dirty:false,refuse:false};
 const item={generation:1,revision:1,created:Date.now(),normalized:state.source,imageSelection:structuredClone(selected)};
 const adapter={failed:false,approveSelection:(id,ref)=>{assert.equal(id,resourceId);assert.equal(ref,uri);return runtime;}};
 const ctx={URL,JSON,Date,Math,Number,Error,Map,
  localPresentation:adapter,active:{kind:'presentation',readOnly:false,sourceReadOnly:false},
  ready:true,inputLocked:true,revision:1,userTouched:false,
  exports:new Map([['snapshot',item]]),current:g=>g===1&&!state.closed,
  stable:s=>s,rawSnapshot:()=>state.source,imageSelection:()=>selected,
  validate:(kind,text)=>{assert.equal(kind,'presentation');JSON.parse(text);},
  changed:()=>{state.dirty=true;},
  window:{BookStarkPPTist:{insertOwnedImage:async(url,w,h,selection,guard)=>{
    assert.equal(url,runtime);assert.equal(selection.slideId,'actual');
    if(!guard())throw Error('selection_changed');state.calls++;
    if(!state.refuse){doc.slides[0].elements.push({id:'real-sdk-image',type:'image',src:uri});
      state.source=JSON.stringify(doc);}
  }}}};
 vm.createContext(ctx);vm.runInContext(implementation+'\nglobalThis.invoke=insertLocalPresentationImageSnapshot;',ctx);
 return {state,selected,item,ctx,invoke:ctx.invoke};
}
(async()=>{
 let passed=0;const options={resourceId,width:32,height:16};
 {
  const f=fixture(),receipt=await f.invoke('snapshot',uri,options);
  assert.equal(receipt.kind,'presentation');assert.equal(receipt.localPresentationResourceFailed,false);
  assert.equal(f.state.calls,1);assert.equal(f.state.dirty,true);
  const saved=f.state.source,reopened=JSON.parse(saved);
  assert.equal(reopened.slides[0].elements[0].src,uri);
  assert.equal(reopened.slides[0].unknown,42);assert.equal(reopened.unknown,'keep');
  await assert.rejects(()=>f.invoke('snapshot',uri,options));assert.equal(f.state.calls,1);passed++;
 }
 for(const mode of ['slideChanged','sourceChanged','readOnly','retired','failed']) {
  const f=fixture();
  if(mode==='slideChanged')f.selected.slideId='other';
  if(mode==='sourceChanged')f.state.source+=' ';
  if(mode==='readOnly')f.ctx.active.readOnly=true;
  if(mode==='retired')f.state.closed=true;
  if(mode==='failed')f.ctx.localPresentation.failed=true;
  await assert.rejects(()=>f.invoke('snapshot',uri,options));assert.equal(f.state.calls,0);passed++;
 }
 {
  const f=fixture();f.state.refuse=true;
  await assert.rejects(()=>f.invoke('snapshot',uri,options),/not_observed/);
  assert.equal(f.state.dirty,false);passed++;
 }
 console.log(JSON.stringify({passed,enginePortMock:true,actualSDKRender:false,Android:false}));
})().catch(e=>{console.error(e);process.exitCode=1;});
