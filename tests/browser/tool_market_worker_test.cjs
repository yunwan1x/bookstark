require('./repo-root.cjs');
const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const source=fs.readFileSync('static/sw.js','utf8');
function worker(options={}) {
 let handler;
 const env={URL,Response,Request,AbortController,setTimeout,clearTimeout,location:new URL('https://books.test'),self:{addEventListener:(type,fn)=>{if(type==='fetch')handler=fn;}},...options};
 vm.createContext(env);vm.runInContext(source,env);return handler;
}
test('market catalog and manifests never fall back to cached publications',()=>{
 const handler=worker({caches:{match:()=>{throw Error('must not read stale manifests');}}});
 for(const path of ['/market/index.json','/market/versions/revision','/market/login','/__bookstark/open/capability','/api/blogs/12/tool','/api/tool-assets/instance/epoch/image.png','/api/tool-sources/1','/api/tool-market','/api/tool-market/12','/api/tool-installs','/api/tool-installs/12?part=data']){
  let intercepted=false;
  handler({request:new Request('https://books.test'+path),respondWith:()=>{intercepted=true;}});
  assert.equal(intercepted,false,path);
 }
});
test('market shell never uses another accounts cached workspace',async()=>{
 for(const offline of [false,true]){
  let result;
  const handler=worker({fetch:async()=>{if(offline)throw Error('offline');return new Response('current workspace');},caches:{match:async path=>{assert.equal(path,'/static/offline.html');return undefined;}}});
  handler({request:new Request('https://books.test/market?view=installed',{headers:{accept:'text/html'}}),respondWith:value=>{result=value;}});
  const response=await result;
  assert.equal(response.status,offline?503:200);
  if(!offline)assert.equal(await response.text(),'current workspace');
 }
});

test('tool mutations are never queued for replay after an uninstall',()=>{
 let env={URL,Response,Request,AbortController,setTimeout,clearTimeout,location:new URL('https://books.test'),self:{addEventListener:()=>{}}};
 vm.createContext(env);vm.runInContext(source,env);
 for(const method of ['POST','DELETE'])assert.equal(env.isOfflineQueueableMutation(new URL('https://books.test/api/blogs/12/tool'),method,new Request('https://books.test/api/blogs/12/tool',{method})),false);
 for(const method of ['PUT','POST','DELETE'])assert.equal(env.isOfflineQueueableMutation(new URL('https://books.test/api/tool-installs/12'),method,new Request('https://books.test/api/tool-installs/12',{method})),false);
});
