'use strict';
// Actual owned host function + mocked CodeMirror boundary, never Native proof.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const host=fs.readFileSync(process.argv[2] || 'assets/complex_editors/host.js','utf8');
const begin=host.indexOf('  function insertLocalHtmlAttachmentSnapshot(');
const end=host.indexOf('  async function beginSnapshot()',begin);
assert(begin>=0&&end>begin,'exact local insertion function boundary');
const actual=host.slice(begin,end);
const reference='bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.png';
function fixture(original='\ufeff<p>Original😀</p>\r\n'){
  let source=original,selection={kind:'html',from:original.length,to:original.length};
  const snapshot={generation:1,revision:1,created:Date.now(),
    normalized:JSON.stringify(source),imageSelection:{...selection}};
  const transfers=new Map([['s',snapshot]]);
  const view={state:{doc:{toString:()=>source}},
    dispatch:({changes})=>{source=source.slice(0,changes.from)+changes.insert+source.slice(changes.to);}};
  const c={exports:transfers,current:()=>true,ready:true,
    active:{kind:'html',readOnly:false,sourceReadOnly:false},inputLocked:true,revision:1,
    stable:JSON.stringify,rawSnapshot:()=>source,imageSelection:()=>selection,
    root:{querySelector:()=>({})},window:{CMHtml:{EditorView:{findFromDOM:()=>view}}},
    userTouched:false,URL,TextEncoder,Date,
    changed:()=>{c.revision++;},state:()=>({ready:true,kind:'html',generation:1,inputLocked:true,dirty:true})};
  vm.createContext(c);vm.runInContext(actual+'\nthis.invoke=insertLocalHtmlAttachmentSnapshot;',c);
  return {c,transfers,original,get source(){return source;},
    mutate:value=>{source=value;},move:value=>{selection={kind:'html',from:value,to:value};},
    run:(uri=reference,options={kind:'image',name:'a.png',width:1,height:1})=>c.invoke('s',uri,options)};
}
let pass=0;
function test(name,run){run();pass++;process.stdout.write('PASS '+name+'\n');}
test('actual current-range image insertion preserves BOM and original UTF8',()=>{
  const f=fixture();const result=f.run();
  assert.equal(f.source,f.original+'<img src="'+reference+'" width="1" height="1" alt="">');
  assert.equal(result.dirty,true);assert.equal(f.transfers.size,0);
});
test('ordinary file link escapes actual filename and never becomes image',()=>{
  const f=fixture(),uri='bookstark-attachment:///bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/%3Cmanual%3E.pdf';
  f.run(uri,{kind:'file',name:'<manual>.pdf'});
  assert(f.source.endsWith('<a href="'+uri+'">&lt;manual&gt;.pdf</a>'));
});
for(const [name,mutate] of [
  ['source changed',f=>f.mutate('Changed source')],
  ['range changed',f=>f.move(0)],
  ['read only',f=>{f.c.active.readOnly=true;}],
  ['source read only',f=>{f.c.active.sourceReadOnly=true;}],
  ['retired runtime',f=>{f.c.current=()=>false;}],
  ['stale snapshot',f=>{f.transfers.get('s').created-=130000;}],
]){
  test(name+' rejects without body mutation',()=>{
    const f=fixture();mutate(f);const before=f.source;
    assert.throws(()=>f.run());assert.equal(f.source,before);
  });
}
test('network URL cannot use local insertion command',()=>{
  const f=fixture();assert.throws(()=>f.run('https://example.invalid/a.png'));
  assert.equal(f.source,f.original);
});
test('filename mismatch rejects unchanged source',()=>{
  const f=fixture();assert.throws(()=>f.run(reference,{kind:'file',name:'other.pdf'}));
  assert.equal(f.source,f.original);
});
test('oversized transaction is wholly rejected without source truncation',()=>{
  const f=fixture('x'.repeat(5*1024*1024-8));assert.throws(()=>f.run());
  assert.equal(f.source,f.original);
});
test('invalid raster dimensions reject unchanged source',()=>{
  const f=fixture();assert.throws(()=>f.run(reference,{kind:'image',name:'a.png',width:20000,height:1}));
  assert.equal(f.source,f.original);
});
process.stdout.write(JSON.stringify({mockCodeMirror:true,nativeEvidence:false,passed:pass})+'\n');
