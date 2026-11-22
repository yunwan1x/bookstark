'use strict';
// Host protocol test only. This never claims Excalidraw rendered a bitmap.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const script = fs.readFileSync(process.argv[2], 'utf8');
const scope = 'a'.repeat(64), resource = 'b'.repeat(64);
const uri = 'bookstark-attachment:///' + 'c'.repeat(32) + '/actual.png';
const runtime = 'https://editor.test/local-drawing/' + scope + '/' + resource;
function fixture(source, resources = {one:resource}) {
  let current = true, failures = 0;
  const ack = {generation:1, ready:true, sourceLoaded:true, loading:false, failed:false};
  const context = {URL, setInterval, clearInterval, performance,
    location:{protocol:'https:', origin:'https://editor.test'},
    BookStarkExcalidraw:{ownedInitializationState:()=>({...ack})}};
  context.window = context;
  vm.runInNewContext(script, context);
  const adapter = context.BookStarkLocalDrawing.create({
    source:JSON.stringify(source), scope, resources,
    isCurrent:()=>current, onFailure:()=>failures++,
  });
  return {adapter, ack, retireOwner:()=>{current=false;},
    get failures(){return failures;}};
}
function source() {
  return {elements:[{id:'image1',type:'image',fileId:'one',isDeleted:false}],
    files:{one:{id:'one',dataURL:uri,mimeType:'image/png',unknown:'keep'},
      unused:{id:'unused',dataURL:'https://outside.invalid/do-not-fetch'}},
    appState:{unknown:42}, envelope:'keep'};
}
(async()=>{
  let count=0;
  {
    const f=fixture(source()), prepared=JSON.parse(f.adapter.prepareSource());
    assert.equal(prepared.files.one.dataURL,runtime);
    assert.equal(Object.hasOwn(prepared.files,'unused'),false);
    assert.equal(prepared.envelope,'keep');
    assert.equal(JSON.parse(f.adapter.canonicalSource(JSON.stringify(prepared))).files.one.dataURL,uri);
    assert.equal(f.failures,0); count++;
  }
  {
    const f=fixture(source(),{}), prepared=JSON.parse(f.adapter.prepareSource());
    assert.equal(Object.keys(prepared.files).length,0);
    assert.equal(f.adapter.failed,true); assert.equal(f.failures,1);
    const restored=JSON.parse(f.adapter.canonicalSource(JSON.stringify(prepared)));
    assert.equal(restored.files.one.dataURL,uri);
    assert.equal(restored.files.one.unknown,'keep'); count++;
  }
  {
    const f=fixture(source()), prepared=JSON.parse(f.adapter.prepareSource());
    delete prepared.files.one;
    const restored=JSON.parse(f.adapter.canonicalSource(JSON.stringify(prepared)));
    assert.equal(restored.files.one.dataURL,uri);
    assert.equal(f.adapter.failed,true); assert.equal(f.failures,1);count++;
  }
  {
    const f=fixture({elements:[],files:{}},{});
    const newId='d'.repeat(64);
    const url=f.adapter.approveSelection(newId,uri);
    const value={elements:[{id:'new',type:'image',fileId:'sdk-new'}],
      files:{'sdk-new':{id:'sdk-new',dataURL:url}}};
    assert.equal(JSON.parse(f.adapter.canonicalSource(JSON.stringify(value))).files['sdk-new'].dataURL,uri);
    assert.throws(()=>f.adapter.approveSelection(newId,uri+'changed'));
    count++;
  }
  {
    const f=fixture(source()), prepared=JSON.parse(f.adapter.prepareSource());
    prepared.files.one.dataURL='https://editor.test/local-drawing/'+scope+'/'+'e'.repeat(64);
    assert.throws(()=>f.adapter.canonicalSource(JSON.stringify(prepared)));
    assert.equal(f.adapter.failed,true);count++;
  }
  {
    const f=fixture(source());
    const ready=await f.adapter.waitReady();
    assert.equal(ready.generation,1);
    assert.equal(ready.resourcesComplete,true);count++;
  }
  {
    const f=fixture(source());f.ack.ready=false;
    const waiting=f.adapter.waitReady();f.adapter.retire();
    await assert.rejects(waiting,/retired/);
    assert.throws(()=>f.adapter.prepareSource(),/retired/);count++;
  }
  {
    const f=fixture(source());f.retireOwner();
    assert.throws(()=>f.adapter.approveSelection(resource,uri),/retired/);
    await assert.rejects(async()=>f.adapter.waitReady(),/retired/);count++;
  }
  console.log(JSON.stringify({passed:count,scope:'owned adapter protocol only; no SDK/render/Native claim'}));
})().catch(error=>{console.error(error);process.exitCode=1;});
