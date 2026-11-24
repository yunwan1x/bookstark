const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const root=require('./repo-root.cjs');
const source=fs.readFileSync(root+'/static/js/utils.js','utf8');
const end=source.indexOf('window.BookStarkRequestLock =');
const start=source.lastIndexOf('(function()',source.indexOf('API_CACHE_STALE'));
const listener=source.slice(start,end);
test('opaque sandbox service worker getter cannot abort shared utilities',()=>{
 const navigator={};Object.defineProperty(navigator,'serviceWorker',{get(){throw new DOMException('sandboxed','SecurityError')}});
 assert.doesNotThrow(()=>vm.runInNewContext(listener,{navigator}));
});
test('unsupported service worker has no listener',()=>assert.doesNotThrow(()=>vm.runInNewContext(listener,{navigator:{}})));
test('supported service worker still reports stale API data',()=>{
 let callback;const messages=[];
 const BSDialog={toast(...args){messages.push(args)}};
 vm.runInNewContext(listener,{navigator:{serviceWorker:{addEventListener(type,fn){assert.equal(type,'message');callback=fn}}},window:{BSDialog},BSDialog,Date});
 callback({data:{type:'API_CACHE_STALE'}});callback({data:{type:'API_CACHE_STALE'}});
 assert.equal(messages.length,1);assert.equal(messages[0][1],'warning');
});
