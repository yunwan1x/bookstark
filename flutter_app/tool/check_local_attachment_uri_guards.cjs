'use strict';
// Run from flutter_app: node tool/check_local_attachment_uri_guards.cjs
// Optional repository root argument supports external review without copying source.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=process.argv[2]?path.resolve(process.argv[2]):path.resolve(__dirname,'..');
const read=name=>fs.readFileSync(path.join(root,'assets','complex_editors',name),'utf8');
function between(source,startAnchor,endAnchor,offset=0){
 const start=source.indexOf(startAnchor,offset);assert(start>=0,'Production guard start anchor missing');
 const end=source.indexOf(endAnchor,start+startAnchor.length);assert(end>start,'Production guard end anchor missing');
 return source.slice(start,end);
}
const host=read('host.js'),snippets={};
for(const [kind,name] of [['mindmap','Mindmap'],['richdoc','Richdoc']]){
 const offset=host.indexOf('function insertLocal'+name+'ImageSnapshot(');
 assert(offset>=0,'Production insertion anchor missing');
 snippets[kind]=between(host,'    const uri=new URL(reference);','    // ',offset);
}
const html=host.indexOf('function insertLocalHtmlAttachmentSnapshot(');
assert(html>=0,'Production HTML insertion anchor missing');
snippets.html=between(host,'    const uri = new URL(reference);','    const escape',html);
for(const kind of ['drawing','presentation'])
 snippets[kind]=between(read('local-'+kind+'.js'),'      const parsed=new URL(uri),parts=','      if(!resourceIDs');
const NativeURL=URL;
class ObservedWebViewURL extends NativeURL{get pathname(){const path=super.pathname;return this.protocol==='bookstark-attachment:'&&path.startsWith('/')?'//'+path:path;}}
const id='a'.repeat(32),prefix='bookstark-attachment:///'+id+'/';
const good=[prefix+'image.png',prefix+'%E5%9B%BE%20%23%25.png'];
const bad=['https://example.invalid/'+id+'/image.png','bookstark-attachment://host/'+id+'/image.png',prefix+'image.png?x',prefix+'image.png#x',prefix+'%2F.png',prefix+'%5C.png',prefix+'%00.png',prefix+'..',prefix+'',prefix+'x/y',prefix+'/image.png','bookstark-attachment:///bad/image.png','bookstark-attachment:'+id+'/image.png'];
let checks=0;
for(const Parser of [NativeURL,ObservedWebViewURL])for(const [kind,code] of Object.entries(snippets)){
 const guard=new Function('URL',['drawing','presentation'].includes(kind)?'uri':'reference','options',code);
 for(const ref of good){const name=decodeURIComponent(ref.slice(ref.lastIndexOf('/')+1));assert.doesNotThrow(()=>guard(Parser,ref,{name}));checks++;}
 for(const ref of bad){assert.throws(()=>guard(Parser,ref,{name:'image.png'}));checks++;}
}
assert.equal(new ObservedWebViewURL(prefix+'image.png').pathname.split('/').length,5);
let oldGuardFailures=0;
for(const [kind,code] of Object.entries(snippets)){
 const normalized=String.raw`pathname.replace(/^\/+/, '/').split('/')`;
 assert.equal(code.split(normalized).length-1,1,'Expected exact leading-slash normalization missing');
 const prior=code.replace(normalized,"pathname.split('/')");
 const guard=new Function('URL',['drawing','presentation'].includes(kind)?'uri':'reference','options',prior);
 assert.throws(()=>guard(ObservedWebViewURL,prefix+'image.png',{name:'image.png'}));
 oldGuardFailures++;
}
console.log(JSON.stringify({oldGuardFailures,passed:true,actualProductionGuards:5,parsers:2,checks,observedSplitLen:5,interiorAndAuthorityRejected:true}));
