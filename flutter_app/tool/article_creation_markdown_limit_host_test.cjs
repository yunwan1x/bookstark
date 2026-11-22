'use strict';
// Actual app-owned transaction-filter functions, mocked CM state. Host only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2]||'assets/complex_editors/markdown-editor.js','utf8');
function bodyAfter(marker){
 const start=source.indexOf(marker);assert(start>=0,'missing actual function');
 const open=source.indexOf('{',start);let depth=0,quote=null,escape=false;
 for(let i=open;i<source.length;i++){
  const c=source[i];
  if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote=null;continue;}
  if(c==="'"||c==='"'||c===String.fromCharCode(96)){quote=c;continue;}
  if(c==='{')depth++;else if(c==='}'&&--depth===0)return source.slice(open+1,i);
 }
 throw Error('unterminated actual function');
}
const valid=bodyAfter('function sourceValid(value)');
const accept=bodyAfter('function acceptSource(value)');
const filter=bodyAfter('cm.EditorState.transactionFilter.of(transaction =>');
const setLimit=bodyAfter('setByteLimit:(limit)=>');
let cases=0;
function fixture(limit=4*1024*1024){
 const state={TextEncoder,maxBytes:20*1024*1024,encoder:new TextEncoder(),
  editByteLimit:limit,readOnly:false,rejected:0,original:'Original',
  alive:()=>true,view:{state:{doc:{toString:()=>'Original'}}}};
 state.options={onLimitRejected:()=>state.rejected++};
 vm.createContext(state);
 vm.runInContext('function sourceValid(value){'+valid+'}\n'+
  'function acceptSource(value){'+accept+'}\n'+
  'this.filter=transaction=>{'+filter+'};\n'+
  'this.setLimit=limit=>{'+setLimit+'};',state);
 return state;
}
function transaction(text){return {docChanged:true,newDoc:{toString:()=>text}};}
function test(name,run){run();cases++;process.stdout.write('PASS '+name+'\n');}
test('BOM and multibyte exact limit accepted',()=>{
 const f=fixture(10),tx=transaction('\ufeff雪😀');
 assert.equal(new TextEncoder().encode(tx.newDoc.toString()).length,10);
 assert.equal(f.filter(tx),tx);assert.equal(f.rejected,0);
});
test('one extra Unicode scalar rejects entire paste',()=>{
 const f=fixture(10),tx=transaction('\ufeff雪😀x');
 assert.equal(f.filter(tx).length,0);assert.equal(f.rejected,1);
 assert.equal(f.original,'Original');
});
test('unpaired high and low surrogate rejected',()=>{
 const f=fixture();assert.equal(f.filter(transaction('x\ud800')).length,0);
 assert.equal(f.filter(transaction('x\udc00')).length,0);assert.equal(f.rejected,2);
});
test('undo is subject to the same full-source bound',()=>{
 const f=fixture(10),tx={...transaction('x'.repeat(11)),isUserEvent:x=>x==='undo'};
 assert.equal(f.filter(tx).length,0);assert.equal(f.original,'Original');
});
test('selection-only transaction does not rewrite source',()=>{
 const f=fixture(),tx={docChanged:false};assert.equal(f.filter(tx),tx);
});
test('limit monotonically decreases and readonly source cannot change it',()=>{
 const f=fixture();assert.equal(f.setLimit(20).limit,20);
 assert.throws(()=>f.setLimit(21));f.readOnly=true;assert.throws(()=>f.setLimit(10));
});
test('complete old overlimit source is retained when smaller limit rejected',()=>{
 const f=fixture(),old='\ufeff'+'x'.repeat(30);
 f.view.state.doc.toString=()=>old;
 assert.throws(()=>f.setLimit(20));assert.equal(f.view.state.doc.toString(),old);
});
process.stdout.write(JSON.stringify({passed:cases,android:false,realCodeMirror:false})+'\n');
