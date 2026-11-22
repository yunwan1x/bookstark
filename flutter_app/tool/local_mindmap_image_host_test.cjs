'use strict';
// Actual own-host function with a strict MindElixir reshapeNode port mock.
// Not a vendor/browser/Native execution result.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2]||'assets/complex_editors/host.js','utf8');
const a=source.indexOf('  async function insertLocalMindmapImageSnapshot(');
const b=source.indexOf('  async function insertImageSnapshot(',a);
assert(a>=0&&b>a,'Actual local mindmap host command required');
const implementation=source.slice(a,b);
const uri='bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.png';
function fixture(){
  const document={nodeData:{id:'root',topic:'Root',children:[
    {id:'selected',topic:'Selected',custom:{keep:true}}]},unknown:{keep:true}};
  const node={isConnected:true,nodeObj:document.nodeData.children[0]};
  const state={source:JSON.stringify(document),closed:false,calls:0,dirty:false,
    refuse:false};
  const selected={kind:'mindmap',nodeId:'selected'};
  const item={generation:1,revision:1,created:Date.now(),
    normalized:state.source,imageSelection:structuredClone(selected)};
  const instance={currentNodes:[node],currentNode:node,
    reshapeNode:(actual,patch)=>{
      assert.equal(actual,node);state.calls++;
      if(state.refuse)return;
      Object.assign(actual.nodeObj,patch);
      state.source=JSON.stringify(document);
    }};
  const context={URL,TextEncoder,Date,Math,JSON,Array,Number,Error,Map,
    encoder:new TextEncoder(),active:{kind:'mindmap',readOnly:false,sourceReadOnly:false},
    ready:true,inputLocked:true,revision:1,userTouched:false,instance,
    exports:new Map([['snapshot',item]]),current:g=>g===1&&!state.closed,
    stable:s=>s,rawSnapshot:()=>state.source,getSource:()=>state.source,
    imageSelection:()=>{
      const nodes=instance.currentNodes.length?instance.currentNodes:
        instance.currentNode?[instance.currentNode]:[];
      return nodes.length===1&&nodes[0].isConnected?
        {kind:'mindmap',nodeId:nodes[0].nodeObj.id}:null;
    },
    maxBytes:()=>5*1024*1024,
    validate:(kind,text)=>{assert.equal(kind,'mindmap');
      assert.equal(typeof JSON.parse(text).nodeData.topic,'string');},
    changed:()=>{state.dirty=true;}};
  vm.createContext(context);
  vm.runInContext(implementation+'\nglobalThis.invoke=insertLocalMindmapImageSnapshot;',context);
  return {state,node,item,instance,context,invoke:context.invoke};
}
const options={width:1440,height:720};
let passed=0;
async function check(name,work){await work();passed++;}
(async()=>{
  await check('actual selected node reshapeNode port and one-use receipt',async()=>{
    const f=fixture();const receipt=await f.invoke('snapshot',uri,options);
    const value=JSON.parse(f.state.source);
    assert.deepEqual(value.nodeData.children[0].image,{url:uri,width:720,height:360});
    assert.deepEqual(value.nodeData.children[0].custom,{keep:true});
    assert.deepEqual(value.unknown,{keep:true});
    assert.equal(receipt.kind,'mindmap');assert.equal(f.state.dirty,true);
    assert.equal(f.state.calls,1);assert.equal(f.context.exports.has('snapshot'),false);
    await assert.rejects(()=>f.invoke('snapshot',uri,options));
    assert.equal(f.state.calls,1);
  });
  for(const mode of ['none','multiple','disconnected','drift','readOnly',
    'sourceReadOnly','wrongKind','closed','sourceChanged']){
    await check(mode+' rejects before actual SDK mutation',async()=>{
      const f=fixture();
      if(mode==='none'){f.instance.currentNodes=[];f.instance.currentNode=null;}
      if(mode==='multiple')f.instance.currentNodes=[f.node,f.node];
      if(mode==='disconnected')f.node.isConnected=false;
      if(mode==='drift')f.node.nodeObj.id='other';
      if(mode==='readOnly')f.context.active.readOnly=true;
      if(mode==='sourceReadOnly')f.context.active.sourceReadOnly=true;
      if(mode==='wrongKind')f.context.active.kind='richdoc';
      if(mode==='closed')f.state.closed=true;
      if(mode==='sourceChanged')f.state.source+=' ';
      await assert.rejects(()=>f.invoke('snapshot',uri,options));
      assert.equal(f.state.calls,0);
    });
  }
  await check('unchanged SDK result is not falsely acknowledged',async()=>{
    const f=fixture();f.state.refuse=true;
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/not_observed/);
    assert.equal(f.state.calls,1);assert.equal(f.state.dirty,false);
  });
  await check('merged full source capacity bound precedes mutation',async()=>{
    const f=fixture();f.context.getSource=()=>f.state.source+' '.repeat(5*1024*1024-500);
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/capacity/);
    assert.equal(f.state.calls,0);
  });
  for(const bad of ['https://example.test/a.png',uri+'?x=1',
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a%2fb.png']){
    await check('invalid local reference rejects before SDK',async()=>{
      const f=fixture();await assert.rejects(()=>f.invoke('snapshot',bad,options));
      assert.equal(f.state.calls,0);
    });
  }
  process.stdout.write(JSON.stringify({passed,enginePortMock:true,nativeEvidence:false})+'\n');
})().catch(error=>{process.stderr.write(error.stack+'\n');process.exitCode=1;});
