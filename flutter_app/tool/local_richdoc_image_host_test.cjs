'use strict';
// Actual extracted own-host function, mocked canvas-editor command port.
// This is not a browser/Native pass.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2]||'assets/complex_editors/host.js','utf8');
const start=source.indexOf('  async function insertLocalRichdocImageSnapshot(');
const end=source.indexOf('  async function insertImageSnapshot(',start);
assert(start>=0&&end>start,'Actual local richdoc host function required');
const implementation=source.slice(start,end);
const uri='bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.png';
function fixture(){
  const value={schema:'bookstark-richdoc',schema_version:1,
    data:{main:[{value:'Original'}]}};
  const range={kind:'richdoc',range:{startIndex:0,endIndex:0,zone:'main'}};
  const state={source:JSON.stringify(value),range,closed:false,
    commands:0,dirty:false,refuse:false};
  const item={generation:1,revision:1,created:Date.now(),
    normalized:state.source,imageSelection:structuredClone(range)};
  const context={
    URL,TextEncoder,Date,Math,JSON,Array,Number,Error,Map,
    encoder:new TextEncoder(),
    active:{kind:'richdoc',readOnly:false,sourceReadOnly:false,generation:1},
    ready:true,inputLocked:true,revision:1,userTouched:false,
    exports:new Map([['snapshot',item]]),
    current:g=>g===1&&!state.closed,
    stable:s=>s,rawSnapshot:()=>state.source,getSource:()=>state.source,
    imageSelection:()=>structuredClone(state.range),
    maxBytes:()=>5*1024*1024,
    validate:(kind,text)=>{
      assert.equal(kind,'richdoc');
      assert.equal(JSON.parse(text).schema,'bookstark-richdoc');
      assert(Buffer.byteLength(text)<=5*1024*1024);
    },
    changed:()=>{state.dirty=true;},
    instance:{command:(name,options)=>{
      if(name==='getRangeParagraph')return JSON.parse(state.source).data.main;
      assert.equal(name,'executeImage');
      state.commands++;
      if(state.refuse)return null;
      const document=JSON.parse(state.source);
      document.data.main.push({type:'image',...options});
      state.source=JSON.stringify(document);
      return 'real-command-port-fixture-id';
    }},
  };
  vm.createContext(context);
  vm.runInContext(implementation+
    '\nglobalThis.invoke=insertLocalRichdocImageSnapshot;',context);
  return {state,item,context,invoke:context.invoke};
}
const options={width:1440,height:720,scope:'c'.repeat(64),scopeEpoch:1,
  identityDigest:'a'.repeat(64),sourceDigest:'b'.repeat(64)};
let passed=0;
async function check(name,operation){
  await operation();passed++;
}
(async()=>{
  await check('actual executeImage port and observed source; no direct JSON host mutation',
    async()=>{
      const f=fixture();
      const result=await f.invoke('snapshot',uri,options);
      const image=JSON.parse(f.state.source).data.main[1];
      assert.deepEqual(image,{type:'image',value:uri,width:720,height:360});
      assert.equal(f.state.commands,1);
      assert.equal(f.state.dirty,true);
      assert.equal(result.kind,'richdoc');
      assert.equal(f.context.exports.has('snapshot'),false);
      await assert.rejects(()=>f.invoke('snapshot',uri,options));
      assert.equal(f.state.commands,1);
    });
  for(const mode of ['readOnly','sourceReadOnly','wrongKind','closed','rangeDrift']){
    await check(mode+' refuses before engine mutation',async()=>{
      const f=fixture();
      if(mode==='readOnly')f.context.active.readOnly=true;
      if(mode==='sourceReadOnly')f.context.active.sourceReadOnly=true;
      if(mode==='wrongKind')f.context.active.kind='mindmap';
      if(mode==='closed')f.state.closed=true;
      if(mode==='rangeDrift')f.state.range.range.startIndex=1;
      await assert.rejects(()=>f.invoke('snapshot',uri,options));
      assert.equal(f.state.commands,0);
    });
  }
  await check('actual unchanged engine result is not falsely acknowledged',async()=>{
    const f=fixture();f.state.refuse=true;
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/not_observed/);
    assert.equal(f.state.commands,1);assert.equal(f.state.dirty,false);
  });
  for(const bad of ['https://example.test/a.png',uri+'?x=1',
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa//a.png',
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a%2fb.png']){
    await check('unapproved reference refuses before engine mutation',async()=>{
      const f=fixture();
      await assert.rejects(()=>f.invoke('snapshot',bad,options));
      assert.equal(f.state.commands,0);
    });
  }
  await check('capacity bound rejects whole transaction before engine mutation',async()=>{
    const f=fixture();
    const value=JSON.parse(f.state.source);
    value.data.main[0].value='x'.repeat(5*1024*1024-1000);
    f.state.source=JSON.stringify(value);f.item.normalized=f.state.source;
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/capacity/);
    assert.equal(f.state.commands,0);
  });
  await check('actual inherited area metadata counted before mutation',async()=>{
    const f=fixture();
    const value=JSON.parse(f.state.source);
    value.data.main[0].area={description:'x'.repeat(3*1024*1024)};
    f.state.source=JSON.stringify(value);f.item.normalized=f.state.source;
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/capacity/);
    assert.equal(f.state.commands,0);
  });
  await check('unknown original envelope counted through real getSource seam',async()=>{
    const f=fixture();
    f.context.getSource=()=>f.state.source+' '.repeat(5*1024*1024-1000);
    await assert.rejects(()=>f.invoke('snapshot',uri,options),/capacity/);
    assert.equal(f.state.commands,0);
  });
  process.stdout.write(JSON.stringify({passed,enginePortMock:true,
    nativeEvidence:false})+'\n');
})().catch(error=>{process.stderr.write(error.stack+'\n');process.exitCode=1;});
