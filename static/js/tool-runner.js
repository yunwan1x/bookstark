(function(){'use strict';
 const root=document.getElementById('toolRuntime');if(!root)return;
 const id=Number(root.dataset.toolId),store=BookStarkMarketStore,U=ToolMarketUI,t=key=>__('market.'+key),e=U.esc;
 const host=document.getElementById('marketFrameHost'),state=document.getElementById('toolRuntimeState'),message=document.getElementById('toolRuntimeMessage'),retry=document.getElementById('toolRuntimeRetry'),banner=document.getElementById('toolRuntimeSaveError'),retrySave=document.getElementById('toolRuntimeRetrySave');
 const back=document.getElementById('toolRuntimeBack'),fullscreen=document.getElementById('toolRuntimeFullscreen'),exit=document.getElementById('toolRuntimeExit'),more=document.getElementById('toolRuntimeMore'),info=document.getElementById('toolRuntimeInfo'),exportButton=document.getElementById('toolRuntimeExport'),newTab=document.getElementById('toolRuntimeNewTab');
 const params=new URLSearchParams(location.search);back.href=U.marketReturn(params.get('return')||'/market?status=installed');newTab.href=location.pathname+location.search;
 let meta=null,frame=null,values=Object.create(null),operations=[],draining=false,failed=false,pendingFiles=0,allowLeave=false,navigating=false,stale=false;
 const waiters=new Set(),dirty=()=>operations.length>0||failed||pendingFiles>0;
 function settled(){if((!operations.length&&!pendingFiles)||failed){for(const resolve of waiters)resolve();waiters.clear();}}
 function showState(key){state.hidden=false;message.textContent=t(key);document.getElementById('toolRuntimeSkeleton').hidden=true;retry.hidden=key==='not_installed';host.setAttribute('aria-busy','false');}
 function setFullscreen(on){document.body.classList.toggle('tool-runtime-fullscreen',on);fullscreen.setAttribute('aria-pressed',String(on));exit.hidden=!on;if(on)exit.focus();else fullscreen.focus();BSActionDropdown.close(more);}
 fullscreen.onclick=()=>setFullscreen(true);exit.onclick=()=>setFullscreen(false);
 document.addEventListener('keydown',event=>{if(event.key==='Escape'&&document.body.classList.contains('tool-runtime-fullscreen')){event.preventDefault();setFullscreen(false);}});
 async function navigate(action){
  if(navigating)return;navigating=true;
  try{
   if(dirty()&&!failed){let finish,timer;await Promise.race([new Promise(resolve=>{finish=resolve;waiters.add(resolve);}),new Promise(resolve=>{timer=setTimeout(resolve,1500);})]);clearTimeout(timer);waiters.delete(finish);}
   if(dirty()&&!await BSDialog.confirm2(t('run_leave_confirm')))return;
   allowLeave=true;action();
  }finally{navigating=false;}
 }
 back.onclick=event=>{if(event.button||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;event.preventDefault();navigate(()=>location.assign(back.href));};
 const refresh=()=>navigate(()=>location.reload());document.getElementById('toolRuntimeRefresh').onclick=refresh;document.querySelector('[data-runtime=refresh]').onclick=()=>{BSActionDropdown.close(more);refresh();};retry.onclick=refresh;
 window.addEventListener('beforeunload',event=>{if(!allowLeave&&dirty()){event.preventDefault();event.returnValue='';}});
 function exportData(){
  if(!meta)return;
  try{const blob=new Blob([JSON.stringify({tool:meta.id,values},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='tool-data.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),10000);}
  catch(_){BSDialog.toast(t('failed'),'error');}
  BSActionDropdown.close(more);
 }
 exportButton.onclick=exportData;document.getElementById('toolRuntimeExportError').onclick=exportData;
 info.onclick=()=>{
  if(!meta)return;BSActionDropdown.close(more);
  const p=meta.permissions||{},permissions=[p.read_files?t('run_read_files'):'',p.save_files?t('run_save_files'):'',p.network?t('run_network_on'):t('run_network_off')].filter(Boolean);
  U.modal(t('run_info'),'<dl class="tool-runtime-info"><dt>'+t('run_name')+'</dt><dd>'+e(meta.title)+'</dd><dt>'+t('run_version')+'</dt><dd>v'+e(meta.version)+'</dd><dt>'+t('run_source')+'</dt><dd>'+e(meta.source||location.origin+'/market')+'</dd><dt>'+t('run_permissions')+'</dt><dd><ul>'+permissions.map(p=>'<li>'+e(p)+'</li>').join('')+'</ul></dd></dl>');
 };
 async function drain(){
  if(draining)return;draining=true;failed=false;retrySave.disabled=true;
  try{while(operations.length){const item=operations[0];try{await store.writeData(id,meta.revision,meta.instance,item.op,item.key,item.value);operations.shift();}catch(_){failed=true;banner.hidden=false;break;}}}
  finally{draining=false;retrySave.disabled=false;if(!failed)banner.hidden=true;settled();}
 }
 retrySave.onclick=drain;
  function storageBootstrap(initial,token) {
    const values=Object.assign(Object.create(null),initial);
    const send=(op,key,value)=>parent.postMessage({market:token,op,key,value},'*');
    window.addEventListener('keydown',event=>{if(event.key==='Escape'&&!event.defaultPrevented)send('exit-fullscreen');});
    const methods={getItem:key=>Object.hasOwn(values,String(key))?values[String(key)]:null,setItem:(key,value)=>{key=String(key);value=String(value);const next={...values,[key]:value};if(new Blob([JSON.stringify(next)]).size>5*1024*1024)throw new DOMException('Storage quota','QuotaExceededError');values[key]=value;send('set',key,value);},removeItem:key=>{key=String(key);delete values[key];send('remove',key);},clear:()=>{Object.keys(values).forEach(k=>delete values[k]);send('clear');},key:index=>Object.keys(values)[index]??null};
    const storage=new Proxy(methods,{get:(target,key)=>key==='length'?Object.keys(values).length:key in target?target[key]:values[key],set:(target,key,value)=>{methods.setItem(key,value);return true;},deleteProperty:(target,key)=>{methods.removeItem(key);return true;},ownKeys:()=>Object.keys(values),getOwnPropertyDescriptor:(target,key)=>Object.hasOwn(values,key)?{enumerable:true,configurable:true,value:values[key]}:undefined});
    Object.defineProperty(window,'localStorage',{value:storage});
    let fileSequence=0;
    const files=new Map();
    window.addEventListener('message',event=>{
      const message=event.data;if(event.source!==parent||!message||message.market!==token||!message.fileReply)return;
      const pending=files.get(message.request);if(!pending)return;files.delete(message.request);clearTimeout(pending.timer);
      if(message.error)pending.reject(Error(message.error));else pending.resolve(message.content?new Uint8Array(message.content):undefined);
    });
    function fileRequest(method,name,content){
      return new Promise((resolve,reject)=>{
        if(files.size>=32)return reject(Error('Too many file requests'));
        const request=++fileSequence,timer=setTimeout(()=>{files.delete(request);reject(Error('File request timed out'));},30000);
        files.set(request,{resolve,reject,timer});parent.postMessage({market:token,file:true,request,method,name,content},'*');
      });
    }
    window.BookStark={files:{read:name=>fileRequest('GET',name),write:async(name,value)=>{
      const content=typeof value==='string'?new TextEncoder().encode(value).buffer:value instanceof Blob?await value.arrayBuffer():value instanceof ArrayBuffer?value:value.buffer.slice(value.byteOffset,value.byteOffset+value.byteLength);
      return fileRequest('PUT',name,content);
    }}};

    let session=Object.create(null);
    Object.defineProperty(window,'sessionStorage',{value:{getItem:k=>session[String(k)]??null,setItem:(k,v)=>{session[String(k)]=String(v);},removeItem:k=>{delete session[String(k)];},clear:()=>{session=Object.create(null);},key:i=>Object.keys(session)[i]??null,get length(){return Object.keys(session).length;}}});
  }
 async function run(){
  try{
   meta=await store.snapshot(id);
   document.title=meta.title+' · BookStark';document.getElementById('toolRuntimeTitle').textContent=meta.title;document.getElementById('toolRuntimeIcon').innerHTML=BookStarkToolAppearance.html(meta,true);
   values=Object.assign(Object.create(null),meta.values||{});info.disabled=false;exportButton.disabled=false;
   newTab.hidden=!!window.BookStarkHost?.available;if(window.BookStarkClient)Promise.resolve(BookStarkClient.ready).then(ready=>{if(ready)newTab.hidden=true;}).catch(()=>{});
   frame=document.createElement('iframe');frame.title=meta.title;frame.setAttribute('sandbox','allow-scripts allow-forms allow-downloads');frame.referrerPolicy='no-referrer';
   const token=crypto.randomUUID(),json=value=>JSON.stringify(value).replace(/</g,'\u003c'),assetPrefix='/api/tool-assets/'+meta.instance+'/';
   const doc=new DOMParser().parseFromString(meta.content.split(assetPrefix).join(location.origin+assetPrefix),'text/html');doc.querySelectorAll('base').forEach(el=>el.remove());
   const assetRoot=location.origin+assetPrefix,policy=doc.createElement('meta');policy.httpEquiv='Content-Security-Policy';
   policy.content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob: "+assetRoot+"; style-src 'unsafe-inline' "+assetRoot+"; img-src data: blob: "+assetRoot+"; font-src data: "+assetRoot+"; media-src blob: data: "+assetRoot+"; connect-src "+(meta.permissions?.network?"http: https: wss:":assetRoot)+"; form-action 'none'; frame-src 'none'";
   doc.head.prepend(policy);
   const base=doc.createElement('base');base.href=new URL(/^https?:\/\//.test(meta.source)?meta.source:'/market',location.origin).href;doc.head.prepend(base);
   const script=doc.createElement('script');script.textContent='('+storageBootstrap.toString()+')('+json(meta.values||{})+','+json(token)+');';doc.head.insertBefore(script,policy.nextSibling);
   window.addEventListener('message',event=>{
    const item=event.data;if(stale||event.source!==frame.contentWindow||!item||item.market!==token)return;
    if(item.op==='exit-fullscreen'){if(document.body.classList.contains('tool-runtime-fullscreen'))setFullscreen(false);return;}
    if(item.file===true){
     if(!['GET','PUT'].includes(item.method)||typeof item.name!=='string'||item.name.length>2048||(item.method==='PUT'&&!(item.content instanceof ArrayBuffer)))return;
     if((item.method==='GET'&&!meta.permissions?.read_files)||(item.method==='PUT'&&!meta.permissions?.save_files)){frame.contentWindow?.postMessage({market:token,fileReply:true,request:item.request,error:t('failed')},'*');return;}
     if(item.method==='PUT')pendingFiles++;
     store.file(id,meta.revision,meta.instance,item.method,item.name,item.content).then(content=>frame.contentWindow?.postMessage({market:token,fileReply:true,request:item.request,content},'*')).catch(()=>frame.contentWindow?.postMessage({market:token,fileReply:true,request:item.request,error:t('failed')},'*')).finally(()=>{if(item.method==='PUT')pendingFiles--;settled();});
     return;
    }
    if(!['set','remove','clear'].includes(item.op)||(item.op!=='clear'&&typeof item.key!=='string')||(item.op==='set'&&typeof item.value!=='string'))return;
    if(item.op==='set')values[item.key]=item.value;else if(item.op==='remove')delete values[item.key];else Object.keys(values).forEach(key=>delete values[key]);
    const last=operations.length-1;if(last>=(draining?1:0)&&item.op!=='clear'&&operations[last].op!=='clear'&&operations[last].key===item.key)operations[last]=item;else operations.push(item);
    if(operations.length>500){frame.remove();banner.hidden=false;failed=true;showState('failed');return;}
    if(!failed)drain();
   });
   frame.addEventListener('load',()=>{if(!stale){state.hidden=true;host.setAttribute('aria-busy','false');}},{once:true});
   frame.srcdoc='<!doctype html>'+doc.documentElement.outerHTML;host.append(frame);
   const check=async()=>{if(stale)return;try{const current=await store.get('tools',id);if(!current||current.revision!==meta.revision||current.instance!==meta.instance){stale=true;frame.remove();showState('stale');}}catch(_){}};
   window.addEventListener('tool-market-changed',check);const timer=setInterval(()=>{if(!document.hidden)check();},15000);window.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
   store.patch(id,{used:Date.now()}).catch(()=>{});
  }catch(error){showState(error.message==='not_found'?'not_installed':'failed');}
 }
 run();
})();
