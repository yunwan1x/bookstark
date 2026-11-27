(function () {
  'use strict';
  const workspace=document.body.dataset.marketWorkspace||'guest';
  const authenticated=workspace!=='guest';
  const channel=typeof BroadcastChannel==='function'?new BroadcastChannel('bookstark-market-'+workspace):null;
  const DB_NAME='bookstark-tool-offline-v1',DB_VERSION=1;

  function announce(){window.dispatchEvent(new Event('tool-market-changed'));if(channel)channel.postMessage('changed');}
  if(channel)channel.onmessage=()=>window.dispatchEvent(new Event('tool-market-changed'));

  function isNetworkFailure(err){
    if(!err)return false;
    if(err.httpStatus)return false;
    if(err.name==='TypeError')return true;
    if(err.name==='AbortError'&&navigator.onLine===false)return true;
    return navigator.onLine===false&&!err.code;
  }

  let dbPromise=null;
  function openDB(){
    if(typeof indexedDB==='undefined')return Promise.resolve(null);
    if(dbPromise)return dbPromise;
    dbPromise=new Promise(resolve=>{
      try{
        const req=indexedDB.open(DB_NAME,DB_VERSION);
        req.onupgradeneeded=e=>{
          const db=e.target.result;
          if(!db.objectStoreNames.contains('lists'))db.createObjectStore('lists',{keyPath:'workspace'});
          if(!db.objectStoreNames.contains('runtimes'))db.createObjectStore('runtimes',{keyPath:'key'});
          if(!db.objectStoreNames.contains('resources'))db.createObjectStore('resources',{keyPath:'key'});
          if(!db.objectStoreNames.contains('queue'))db.createObjectStore('queue',{keyPath:'seq',autoIncrement:true});
        };
        req.onsuccess=e=>{
          const db=e.target.result;
          db.onversionchange=()=>{db.close();dbPromise=null;};
          resolve(db);
        };
        req.onerror=()=>{dbPromise=null;resolve(null);};
      }catch(_){dbPromise=null;resolve(null);}
    });
    return dbPromise;
  }

  function idbGet(storeName,key){
    return openDB().then(db=>!db?null:new Promise(resolve=>{
      try{
        const tx=db.transaction(storeName,'readonly'),req=tx.objectStore(storeName).get(key);
        req.onsuccess=()=>resolve(req.result??null);
        req.onerror=()=>resolve(null);
      }catch(_){resolve(null);}
    }));
  }

  function idbPut(storeName,value){
    return openDB().then(db=>!db?undefined:new Promise(resolve=>{
      try{
        const tx=db.transaction(storeName,'readwrite');
        tx.objectStore(storeName).put(value);
        tx.oncomplete=()=>resolve();
        tx.onerror=()=>resolve();
      }catch(_){resolve();}
    }));
  }

  function idbDelete(storeName,key){
    return openDB().then(db=>!db?undefined:new Promise(resolve=>{
      try{
        const tx=db.transaction(storeName,'readwrite');
        tx.objectStore(storeName).delete(key);
        tx.oncomplete=()=>resolve();
        tx.onerror=()=>resolve();
      }catch(_){resolve();}
    }));
  }

  function idbGetAll(storeName){
    return openDB().then(db=>!db?[]:new Promise(resolve=>{
      try{
        const tx=db.transaction(storeName,'readonly'),req=tx.objectStore(storeName).getAll();
        req.onsuccess=()=>resolve(req.result||[]);
        req.onerror=()=>resolve([]);
      }catch(_){resolve([]);}
    }));
  }

  function idbAdd(storeName,value){
    return openDB().then(db=>!db?undefined:new Promise(resolve=>{
      try{
        const tx=db.transaction(storeName,'readwrite');
        tx.objectStore(storeName).add(value);
        tx.oncomplete=()=>resolve();
        tx.onerror=()=>resolve();
      }catch(_){resolve();}
    }));
  }

  const runtimeKey=id=>workspace+':'+String(id);
  const resourceKey=(id,kind,name)=>workspace+':'+String(id)+':'+kind+':'+String(name||'');

  async function request(path,method='GET',body){
    if(!authenticated)throw Error('login');
    if(navigator.onLine===false)throw new TypeError('offline');
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),150000);
    try{
      const options={method,cache:'no-store',signal:controller.signal};
      if(body!==undefined){options.headers={'Content-Type':'application/json'};options.body=JSON.stringify(body);}
      const response=await fetchWithCurrentCSRF('/api/tool-installs'+path,options);
      if(!response.ok){
        const error=await response.json().catch(()=>({}));
        const err=Error(response.status===401?'login':error.error||'storage');
        err.httpStatus=response.status;
        throw err;
      }
      return await response.json();
    }finally{clearTimeout(timer);}
  }

  function applyValueOp(values,op,key,value){
    const next=Object.assign(Object.create(null),values||{});
    if(op==='set')next[key]=value;
    else if(op==='remove')delete next[key];
    else if(op==='clear')Object.keys(next).forEach(k=>delete next[k]);
    return next;
  }

  async function updateCachedRuntimeValues(id,op,key,value){
    const rec=await idbGet('runtimes',runtimeKey(id));
    if(!rec||!rec.data)return;
    rec.data.values=applyValueOp(rec.data.values,op,key,value);
    rec.updatedAt=Date.now();
    await idbPut('runtimes',rec);
  }

  async function pendingCount(toolId){
    const all=await idbGetAll('queue');
    return all.filter(item=>item.workspace===workspace&&(toolId==null||String(item.toolId)===String(toolId))).length;
  }

  function notifyOfflineQueue(toolId,count,synced){
    window.dispatchEvent(new CustomEvent('tool-offline-queue-changed',{detail:{toolId:Number(toolId),pending:count,synced:Number(synced||0)}}));
  }

  async function enqueueOp(item){
    await idbAdd('queue',Object.assign({workspace,ts:Date.now()},item));
    const count=await pendingCount(item.toolId);
    notifyOfflineQueue(item.toolId,count,0);
    return count;
  }

  async function sendFileDirect(id,revision,instance,method,name,content){
    if(navigator.onLine===false)throw new TypeError('offline');
    const url='/api/tool-installs/'+id+'/files/'+name.split('/').map(encodeURIComponent).join('/');
    const options={method,cache:'no-store',headers:{'X-Tool-Revision':revision,'X-Tool-Instance':instance}};
    if(method==='PUT'){options.headers['Content-Type']='application/octet-stream';options.body=content;}
    const response=await fetchWithCurrentCSRF(url,options);
    if(!response.ok){
      const body=await response.json().catch(()=>({}));
      const err=Error(body.error||'storage');
      err.httpStatus=response.status;
      throw err;
    }
    return method==='GET'?response.arrayBuffer():undefined;
  }

  async function sendFileOpDirect(id,revision,instance,operation){
    if(navigator.onLine===false)throw new TypeError('offline');
    const response=await fetchWithCurrentCSRF('/api/tool-installs/'+id+'/files',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/json','X-Tool-Revision':revision,'X-Tool-Instance':instance},body:JSON.stringify(operation)});
    const data=await response.json().catch(()=>({}));
    if(!response.ok){
      const err=Error(data.error||'storage');
      err.httpStatus=response.status;
      throw err;
    }
    return data.result;
  }

  let flushing=false;
  async function flushOfflineQueue(targetToolId){
    if(!authenticated||flushing||navigator.onLine===false)return 0;
    flushing=true;
    let synced=0;
    try{
      const all=await idbGetAll('queue');
      const items=all
        .filter(item=>item.workspace===workspace&&(targetToolId==null||String(item.toolId)===String(targetToolId)))
        .sort((a,b)=>a.seq-b.seq);
      if(!items.length)return 0;

      const latestMeta=new Map();
      async function resolveTarget(item){
        if(latestMeta.has(item.toolId))return latestMeta.get(item.toolId);
        let rev=item.revision,inst=item.instance;
        try{
          const live=await request('/'+item.toolId);
          if(live&&live.revision&&live.instance){rev=live.revision;inst=live.instance;}
        }catch(_){}
        const pair={revision:rev,instance:inst};
        latestMeta.set(item.toolId,pair);
        return pair;
      }

      for(const item of items){
        try{
          const target=await resolveTarget(item);
          if(item.kind==='data'){
            await request('/'+item.toolId+'/data','POST',{revision:target.revision,instance:target.instance,op:item.op,key:item.key,value:item.value});
          }else if(item.kind==='file_put'){
            await sendFileDirect(item.toolId,target.revision,target.instance,'PUT',item.name,item.content);
          }else if(item.kind==='file_op'){
            await sendFileOpDirect(item.toolId,target.revision,target.instance,item.operation);
          }
          await idbDelete('queue',item.seq);
          synced++;
        }catch(err){
          if(isNetworkFailure(err))break;
          // Drop permanent 4xx errors (except 401/409 which may recover after re-auth)
          if(err.httpStatus&&err.httpStatus>=400&&err.httpStatus<500&&err.httpStatus!==401&&err.httpStatus!==409){
            await idbDelete('queue',item.seq);
          }else{
            break;
          }
        }
      }
      if(synced>0){
        const remaining=await pendingCount(targetToolId);
        notifyOfflineQueue(targetToolId??0,remaining,synced);
      }
      return synced;
    }finally{
      flushing=false;
    }
  }

  async function list(){
    if(!authenticated)return [];
    try{
      const tools=(await request('')).tools||[];
      await idbPut('lists',{workspace,tools,updatedAt:Date.now()});
      return tools;
    }catch(err){
      if(!isNetworkFailure(err))throw err;
      const cached=await idbGet('lists',workspace);
      if(cached&&Array.isArray(cached.tools))return cached.tools;
      throw err;
    }
  }

  async function get(name,id){
    try{
      return await request('/'+id+(name==='packages'?'?part=package':name==='data'?'?part=data':''));
    }catch(error){
      if(error.message==='not_found')return undefined;
      if(isNetworkFailure(error)){
        const cached=await idbGet('runtimes',runtimeKey(id));
        if(cached&&cached.data)return cached.data;
      }
      throw error;
    }
  }

  async function snapshot(id){
    if(navigator.onLine!==false){
      try{await flushOfflineQueue(id);}catch(_){}
    }
    try{
      const data=await request('/'+id+'?part=runtime');
      await idbPut('runtimes',{key:runtimeKey(id),workspace,toolId:Number(id),data,updatedAt:Date.now()});
      return data;
    }catch(err){
      if(!isNetworkFailure(err))throw err;
      const cached=await idbGet('runtimes',runtimeKey(id));
      if(cached&&cached.data){
        const copy=Object.assign({},cached.data,{_offline:true,values:Object.assign(Object.create(null),cached.data.values||{})});
        const allQ=await idbGetAll('queue');
        allQ.filter(q=>q.workspace===workspace&&String(q.toolId)===String(id)&&q.kind==='data').sort((a,b)=>a.seq-b.seq).forEach(q=>{
          copy.values=applyValueOp(copy.values,q.op,q.key,q.value);
        });
        return copy;
      }
      throw err;
    }
  }

  async function install(pkg,expected,instance){
    await request('/'+pkg.id,'PUT',{revision:pkg.revision,hash:pkg.hash||'',expected:expected||'',instance:instance||''});
    announce();
  }

  async function remove(id,revision,instance,keep_data=false){
    await request('/'+id,'DELETE',{revision,instance,keep_data});
    await idbDelete('runtimes',runtimeKey(id));
    announce();
  }

  async function patch(id,values){
    try{
      return await request('/'+id,'PATCH',values);
    }catch(err){
      if(isNetworkFailure(err))return;
      throw err;
    }
  }

  async function writeData(id,revision,instance,op,key,value){
    try{
      const res=await request('/'+id+'/data','POST',{revision,instance,op,key,value});
      await updateCachedRuntimeValues(id,op,key,value);
      return res;
    }catch(err){
      if(!isNetworkFailure(err))throw err;
      await updateCachedRuntimeValues(id,op,key,value);
      await enqueueOp({toolId:Number(id),kind:'data',revision,instance,op,key,value});
      return {offlineQueued:true};
    }
  }

  async function file(id,revision,instance,method,name,content){
    try{
      const result=await sendFileDirect(id,revision,instance,method,name,content);
      if(method==='GET'&&result instanceof ArrayBuffer){
        await idbPut('resources',{key:resourceKey(id,'file',name),workspace,toolId:Number(id),kind:'file',name,value:result.slice(0),updatedAt:Date.now()});
      }else if(method==='PUT'&&content instanceof ArrayBuffer){
        await idbPut('resources',{key:resourceKey(id,'file',name),workspace,toolId:Number(id),kind:'file',name,value:content.slice(0),updatedAt:Date.now()});
      }
      return result;
    }catch(err){
      if(!isNetworkFailure(err))throw err;
      if(method==='GET'){
        const cached=await idbGet('resources',resourceKey(id,'file',name));
        if(cached&&cached.value instanceof ArrayBuffer)return cached.value.slice(0);
        throw Object.assign(Error('offline_unavailable'),{code:'offline_unavailable'});
      }
      if(method==='PUT'){
        const copy=content instanceof ArrayBuffer?content.slice(0):new ArrayBuffer(0);
        await idbPut('resources',{key:resourceKey(id,'file',name),workspace,toolId:Number(id),kind:'file',name,value:copy,updatedAt:Date.now()});
        await enqueueOp({toolId:Number(id),kind:'file_put',revision,instance,name,content:copy});
        return {offlineQueued:true};
      }
      throw err;
    }
  }

  async function fileOperation(id,revision,instance,operation){
    const op=operation&&operation.op,name=operation&&operation.path||'';
    try{
      const result=await sendFileOpDirect(id,revision,instance,operation);
      if(op==='secret_get'){
        await idbPut('resources',{key:resourceKey(id,'secret',name),workspace,toolId:Number(id),kind:'secret',name,value:result??null,updatedAt:Date.now()});
      }else if(op==='secret_set'){
        await idbPut('resources',{key:resourceKey(id,'secret',name),workspace,toolId:Number(id),kind:'secret',name,value:operation.value,updatedAt:Date.now()});
      }else if(op==='secret_remove'){
        await idbDelete('resources',resourceKey(id,'secret',name));
      }else if(op==='list'||op==='exists'||op==='stat'){
        await idbPut('resources',{key:resourceKey(id,op,name),workspace,toolId:Number(id),kind:op,name,value:result,updatedAt:Date.now()});
      }
      return result;
    }catch(err){
      if(!isNetworkFailure(err))throw err;
      if(op==='secret_get'){
        const cached=await idbGet('resources',resourceKey(id,'secret',name));
        return cached?cached.value:null;
      }
      if(op==='secret_set'){
        await idbPut('resources',{key:resourceKey(id,'secret',name),workspace,toolId:Number(id),kind:'secret',name,value:operation.value,updatedAt:Date.now()});
        await enqueueOp({toolId:Number(id),kind:'file_op',revision,instance,operation});
        return true;
      }
      if(op==='secret_remove'){
        await idbDelete('resources',resourceKey(id,'secret',name));
        await enqueueOp({toolId:Number(id),kind:'file_op',revision,instance,operation});
        return true;
      }
      if(op==='list'||op==='exists'||op==='stat'){
        const cached=await idbGet('resources',resourceKey(id,op,name));
        if(cached)return cached.value;
        return op==='list'?[]:op==='exists'?false:null;
      }
      throw Object.assign(Error('offline_unavailable'),{code:'offline_unavailable'});
    }
  }

  async function warmToolAssets(meta){
    if(!meta||meta._offline||meta.distribution!=='files'||!meta.asset_base||typeof caches==='undefined')return;
    try{
      const base=new URL('./',new URL(meta.entry||'index.html',location.origin+meta.asset_base)).href;
      const doc=new DOMParser().parseFromString(meta.content||'','text/html');
      const urls=new Set();
      doc.querySelectorAll('script[src],link[href],img[src]').forEach(el=>{
        const raw=el.getAttribute('src')||el.getAttribute('href')||'';
        if(!raw||raw.startsWith('data:')||raw.startsWith('blob:')||raw.startsWith('#'))return;
        try{
          const resolved=new URL(raw,base);
          if(resolved.origin===location.origin&&resolved.pathname.startsWith('/api/tool-assets/'))urls.add(resolved.href);
        }catch(_){}
      });
      const cache=await caches.open('bookstark-tools-v1');
      const cssUrls=[];
      await Promise.all(Array.from(urls).map(async href=>{
        try{
          let resp=await cache.match(href);
          if(!resp){
            resp=await fetch(href,{credentials:'same-origin'});
            if(resp.ok&&resp.status===200)await cache.put(href,resp.clone());
          }
          if(resp&&resp.ok&&href.toLowerCase().includes('.css'))cssUrls.push({href,resp});
        }catch(_){}
      }));
      // Also warm font/image url(...) references declared inside tool CSS files (e.g. fa-solid-900.woff2)
      const subUrls=new Set();
      for(const item of cssUrls){
        try{
          const text=await item.resp.clone().text();
          const re=/url\(\s*['"]?([^)'"\s]+)['"]?\s*\)/g;
          let m;
          while((m=re.exec(text))!==null){
            const raw=m[1];
            if(!raw||raw.startsWith('data:')||raw.startsWith('blob:'))continue;
            try{
              const resolved=new URL(raw,item.href);
              if(resolved.origin===location.origin&&resolved.pathname.startsWith('/api/tool-assets/'))subUrls.add(resolved.href);
            }catch(_){}
          }
        }catch(_){}
      }
      await Promise.all(Array.from(subUrls).map(async href=>{
        try{
          if(await cache.match(href))return;
          const resp=await fetch(href,{credentials:'same-origin'});
          if(resp.ok&&resp.status===200)await cache.put(href,resp.clone());
        }catch(_){}
      }));
    }catch(_){}
  }

  function clearOfflineData(){
    dbPromise=null;
    return new Promise(resolve=>{
      try{
        const req=indexedDB.deleteDatabase(DB_NAME);
        req.onsuccess=req.onerror=req.onblocked=()=>resolve();
      }catch(_){resolve();}
    });
  }

  window.addEventListener('online',()=>{
    if(authenticated)flushOfflineQueue().catch(()=>{});
  });

  window.BookStarkMarketStore={
    authenticated,list,get,install,remove,patch,writeData,file,fileOperation,
    snapshot,flushOfflineQueue,pendingCount,warmToolAssets,clearOfflineData
  };
})();
