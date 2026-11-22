'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const script=fs.readFileSync(process.argv[2],'utf8');
const scope='a'.repeat(64),id='b'.repeat(64);
const uri='bookstark-attachment:///'+'c'.repeat(32)+'/actual.png';
const runtime='https://editor.test/local-presentation/'+scope+'/'+id;
const key='slides/0/elements/0/src',background='slides/0/background/image/src';
function source(){return {slides:[{id:'actual-slide',elements:[
  {id:'actual-image',type:'image',src:uri,unknown:'keep'},
  {id:'text',type:'text',content:uri},
  {id:'audio',type:'audio',src:'https://outside.invalid/not-image'}
],background:{type:'image',image:{src:uri,size:'cover'}},notes:uri}],
unknown:{src:uri,type:'image'}};}
function fixture(resources={[key]:id,[background]:id}) {
  let current=true,failures=0;const ctx={URL,location:{protocol:'https:',origin:'https://editor.test'}};
  ctx.window=ctx;vm.runInNewContext(script,ctx);
  const adapter=ctx.BookStarkLocalPresentation.create({source:JSON.stringify(source()),
    scope,resources,isCurrent:()=>current,onFailure:()=>failures++});
  return {adapter,retireOwner:()=>current=false,get failures(){return failures;}};
}
let count=0;
{
 const f=fixture(),prepared=JSON.parse(f.adapter.prepareSource());
 assert.equal(prepared.slides[0].elements[0].src,runtime);
 assert.equal(prepared.slides[0].background.image.src,runtime);
 assert.equal(prepared.slides[0].elements[1].content,uri);
 assert.equal(prepared.slides[0].elements[2].src,'https://outside.invalid/not-image');
 assert.equal(prepared.unknown.src,uri);
 const canonical=JSON.parse(f.adapter.canonicalSource(JSON.stringify(prepared)));
 assert.deepEqual(canonical,source());assert.equal(f.failures,0);count++;
}
{
 const f=fixture({}),prepared=f.adapter.prepareSource();
 assert.equal(f.adapter.failed,true);assert.equal(f.failures,1);
 const recovered=JSON.parse(f.adapter.canonicalSource(prepared));
 assert.equal(recovered.slides[0].elements[0].src,uri);
 assert.equal(recovered.slides[0].background.image.src,uri);count++;
}
{
 const f=fixture(),selected='bookstark-attachment:///'+'d'.repeat(32)+'/new.png';
 const url=f.adapter.approveSelection('e'.repeat(64),selected);
 const prepared=JSON.parse(f.adapter.prepareSource());
 prepared.slides[0].elements.push({id:'real-sdk-added',type:'image',src:url});
 const snapshot=JSON.parse(f.adapter.canonicalSource(JSON.stringify(prepared)));
 assert.equal(snapshot.slides[0].elements[3].src,selected);
 assert.equal(snapshot.slides[0].elements[0].unknown,'keep');count++;
}
{
 const f=fixture(),prepared=JSON.parse(f.adapter.prepareSource());
 prepared.slides[0].elements[0].src=runtime.slice(0,-1)+'f';
 assert.throws(()=>f.adapter.canonicalSource(JSON.stringify(prepared)),/unknown_runtime_resource/);
 assert.equal(f.adapter.failed,true);count++;
}
{
 const f=fixture();assert.throws(()=>f.adapter.approveSelection('e'.repeat(64),
  'https://outside.invalid/image.png'),/selection_uri/);count++;
}
{
 assert.throws(()=>fixture({'slides/0/notes':id}),/resource_binding/);count++;
}
{
 const f=fixture();f.retireOwner();assert.throws(()=>f.adapter.prepareSource(),/retired/);count++;
}
{
 const f=fixture();f.adapter.retire();assert.throws(()=>f.adapter.canonicalSource('{}'),/retired/);count++;
}
console.log(JSON.stringify({passed:count,scope:'resource adapter only; no SDK render/Android claim'}));
