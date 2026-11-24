(function(){'use strict';
 const root=document.getElementById('toolRuntime');if(!root)return;
 const runtime=window.BookStarkToolRuntime||{},permissionsUI=BookStarkToolPermissions;
 const id=Number(root.dataset.toolId),store=BookStarkMarketStore,U=ToolMarketUI,t=key=>__('market.'+key),e=U.esc;
 const host=document.getElementById('marketFrameHost'),state=document.getElementById('toolRuntimeState'),message=document.getElementById('toolRuntimeMessage'),retry=document.getElementById('toolRuntimeRetry'),banner=document.getElementById('toolRuntimeSaveError'),retrySave=document.getElementById('toolRuntimeRetrySave');
 const back=document.getElementById('toolRuntimeBack'),fullscreen=document.getElementById('toolRuntimeFullscreen'),exit=document.getElementById('toolRuntimeExit'),more=document.getElementById('toolRuntimeMore'),info=document.getElementById('toolRuntimeInfo'),exportButton=document.getElementById('toolRuntimeExport'),newTab=document.getElementById('toolRuntimeNewTab');
 const params=new URLSearchParams(location.search);back.href=U.marketReturn(params.get('return')||'/market?status=installed');newTab.href=location.pathname+location.search;
 const hint=document.getElementById('toolRuntimeHint'),stateActions=document.getElementById('toolRuntimeStateActions'),stateBack=document.getElementById('toolRuntimeStateBack'),identity=document.getElementById('toolRuntimeIdentity');stateBack.href=back.href;
 let meta=null,frame=null,values=Object.create(null),operations=[],draining=false,failed=false,pendingFiles=0,allowLeave=false,navigating=false,stale=false;
 let loadPhase='loading';
 const slowTimer=setTimeout(()=>{if(loadPhase!=='loading')return;loadPhase='slow';state.dataset.phase='slow';message.textContent=t('run_slow');hint.textContent=t('run_slow_hint');hint.hidden=false;stateActions.hidden=false;},8000);
 function completeLoading(){if(stale||loadPhase==='error')return;clearTimeout(slowTimer);loadPhase='ready';state.dataset.phase='ready';state.hidden=true;host.setAttribute('aria-busy','false');}
 function updateIdentity(row){
  document.title=row.title+' · BookStark';document.getElementById('toolRuntimeTitle').textContent=row.title;document.getElementById('toolRuntimeIcon').innerHTML=BookStarkToolAppearance.html(row,true);identity.classList.remove('is-pending');
  document.getElementById('toolRuntimeLaunchIcon').innerHTML=BookStarkToolAppearance.html(row);
  if(loadPhase==='loading')message.textContent=t('run_loading_named').replace('%s',row.title);
 }
 const waiters=new Set(),dirty=()=>operations.length>0||failed||pendingFiles>0;
 function settled(){if((!operations.length&&!pendingFiles)||failed){for(const resolve of waiters)resolve();waiters.clear();}}
 function showState(key){clearTimeout(slowTimer);loadPhase='error';state.dataset.phase='error';state.hidden=false;message.textContent=t(key);document.getElementById('toolRuntimeAnnouncement').setAttribute('role','alert');hint.hidden=true;stateActions.hidden=false;retry.hidden=key==='not_installed';host.setAttribute('aria-busy','false');frame?.remove();if(!meta){identity.classList.remove('is-pending');document.getElementById('toolRuntimeTitle').textContent=t('tools');document.getElementById('toolRuntimeIcon').innerHTML=BookStarkToolAppearance.html({});}}
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
 stateBack.onclick=back.onclick;
 const refresh=()=>navigate(()=>location.reload());document.getElementById('toolRuntimeRefresh').onclick=refresh;document.querySelector('[data-runtime=refresh]').onclick=()=>{BSActionDropdown.close(more);refresh();};retry.onclick=refresh;
 window.addEventListener('beforeunload',event=>{if(!allowLeave&&dirty()){event.preventDefault();event.returnValue='';}});
 window.addEventListener('pagehide',()=>clearTimeout(slowTimer),{once:true});
 function exportData(){
  if(!meta)return;
  try{const blob=new Blob([JSON.stringify({tool:meta.id,values},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='tool-data.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),10000);}
  catch(_){BSDialog.toast(t('failed'),'error');}
  BSActionDropdown.close(more);
 }
 exportButton.onclick=exportData;document.getElementById('toolRuntimeExportError').onclick=exportData;
 info.onclick=()=>{
  if(!meta)return;BSActionDropdown.close(more);
  const p=meta.permissions||{};
  U.modal(t('run_info'),'<dl class="tool-runtime-info"><dt>'+t('run_name')+'</dt><dd>'+e(meta.title)+'</dd><dt>'+t('run_version')+'</dt><dd>v'+e(meta.version)+'</dd><dt>'+t('run_source')+'</dt><dd>'+e(meta.source||location.origin+'/market')+'</dd><dt>'+t('run_permissions')+'</dt><dd>'+permissionsUI.list(p)+'</dd></dl>');
 };
 async function drain(){
  if(draining)return;draining=true;failed=false;retrySave.disabled=true;
  try{while(operations.length){const item=operations[0];try{await store.writeData(id,meta.revision,meta.instance,item.op,item.key,item.value);operations.shift();}catch(_){failed=true;banner.hidden=false;break;}}}
  finally{draining=false;retrySave.disabled=false;if(!failed)banner.hidden=true;settled();}
 }
 retrySave.onclick=drain;
  function storageBootstrap(initial,token,parentOrigin) {
    const values=Object.assign(Object.create(null),initial);
    window.addEventListener('load',()=>parent.postMessage({market:token,op:'runtime-ready'},parentOrigin),{once:true});
    const send=(op,key,value)=>parent.postMessage({market:token,op,key,value},parentOrigin);
    window.addEventListener('error',event=>{const node=event.target;if(node?.tagName==='SCRIPT'&&node.src||node?.tagName==='LINK'&&node.relList.contains('stylesheet'))send('resource-error');},true);
    window.addEventListener('keydown',event=>{if(event.key==='Escape'&&!event.defaultPrevented)send('exit-fullscreen');});
    const methods={getItem:key=>Object.hasOwn(values,String(key))?values[String(key)]:null,setItem:(key,value)=>{key=String(key);value=String(value);const next={...values,[key]:value};if(new Blob([JSON.stringify(next)]).size>5*1024*1024)throw new DOMException('Storage quota','QuotaExceededError');values[key]=value;send('set',key,value);},removeItem:key=>{key=String(key);delete values[key];send('remove',key);},clear:()=>{Object.keys(values).forEach(k=>delete values[k]);send('clear');},key:index=>Object.keys(values)[index]??null};
    const storage=new Proxy(methods,{get:(target,key)=>key==='length'?Object.keys(values).length:key in target?target[key]:values[key],set:(target,key,value)=>{methods.setItem(key,value);return true;},deleteProperty:(target,key)=>{methods.removeItem(key);return true;},ownKeys:()=>Object.keys(values),getOwnPropertyDescriptor:(target,key)=>Object.hasOwn(values,key)?{enumerable:true,configurable:true,value:values[key]}:undefined});
    Object.defineProperty(window,'localStorage',{value:storage});
    let fileSequence=0;
    const files=new Map();
    window.addEventListener('message',event=>{
      const message=event.data;if(event.source!==parent||event.origin!==parentOrigin||!message||message.market!==token||!message.fileReply)return;
      const pending=files.get(message.request);if(!pending)return;files.delete(message.request);clearTimeout(pending.timer);
      if(message.error)pending.reject(Object.assign(Error(message.error),{code:message.error}));else pending.resolve(message.content?new Uint8Array(message.content):message.result);
    });
    function fileRequest(method,name,content,options){
      return new Promise((resolve,reject)=>{
        if(typeof name!=='string'||name.length>2048||(['rename','move','copy'].includes(method)&&typeof options?.to!=='string'))return reject(Object.assign(Error('invalid_path'),{code:'invalid_path'}));
        if(files.size>=32)return reject(Error('Too many file requests'));
        const request=++fileSequence,timer=setTimeout(()=>{files.delete(request);reject(Error('File request timed out'));},30000);
        files.set(request,{resolve,reject,timer});parent.postMessage({market:token,file:true,request,method,name,content,options},parentOrigin);
      });
    }
    window.BookStark={files:{read:name=>fileRequest('GET',name),write:async(name,value)=>{
      const content=typeof value==='string'?new TextEncoder().encode(value).buffer:value instanceof Blob?await value.arrayBuffer():value instanceof ArrayBuffer?value:value.buffer.slice(value.byteOffset,value.byteOffset+value.byteLength);
      return fileRequest('PUT',name,content);
    },list:(name='')=>fileRequest('list',name),stat:(name='')=>fileRequest('stat',name),exists:(name='')=>fileRequest('exists',name),
    mkdir:(name,options={})=>fileRequest('mkdir',name,undefined,{recursive:options.recursive===true}),
    remove:(name,options={})=>fileRequest('remove',name,undefined,{recursive:options.recursive===true}),
    rename:(name,to)=>fileRequest('rename',name,undefined,{to}),move:(name,to)=>fileRequest('move',name,undefined,{to}),
    copy:(name,to)=>fileRequest('copy',name,undefined,{to})}};

    let socketSequence=0;
    const sockets=new Map();
    class ToolSocket extends EventTarget {
      constructor(id){super();this.id=id;this.readyState=0;this.binaryType='arraybuffer';this.bufferedAmount=0;this.pending=new Map();this.chain=Promise.resolve();this.closed=new Promise(resolve=>this.finish=resolve);}
      emit(type,event){this.dispatchEvent(event);if(typeof this['on'+type]==='function')this['on'+type](event);}
      send(value){
        const task=this.chain.then(async()=>{
          if(this.readyState!==1)throw Object.assign(Error('socket_closed'),{code:'socket_closed'});
          const bytes=typeof value==='string'?new TextEncoder().encode(value):value instanceof Blob?new Uint8Array(await value.arrayBuffer()):value instanceof ArrayBuffer?new Uint8Array(value):ArrayBuffer.isView(value)?new Uint8Array(value.buffer,value.byteOffset,value.byteLength):null;
          if(!bytes)throw TypeError('Expected string, Blob, ArrayBuffer or typed array');
          if(bytes.byteLength>1024*1024)throw new DOMException('Socket write exceeds 1 MiB','QuotaExceededError');
          this.bufferedAmount+=bytes.byteLength;
          try{for(let offset=0;offset<bytes.byteLength;offset+=65536){const data=bytes.slice(offset,offset+65536).buffer,request=++socketSequence;await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(request);reject(Error('socket_write_timeout'));},30000);this.pending.set(request,{resolve,reject,timer});parent.postMessage({market:token,socket:true,id:this.id,op:'send',request,data},parentOrigin);});}}
          finally{this.bufferedAmount-=bytes.byteLength;}
        });this.chain=task.catch(()=>{});return task;
      }
      close(){if(this.readyState>=2)return;this.readyState=2;parent.postMessage({market:token,socket:true,id:this.id,op:'close'},parentOrigin);}
      get readable(){if(!this.input)this.input=new ReadableStream({start:controller=>this.reader=controller,cancel:()=>this.close()},{highWaterMark:1024*1024,size:chunk=>chunk.byteLength});return this.input;}
      get writable(){if(!this.output)this.output=new WritableStream({write:data=>this.send(data),close:()=>this.close(),abort:()=>this.close()});return this.output;}
    }
    function finishSocket(socket,code,reason){
      if(socket.readyState===3)return;socket.readyState=3;clearTimeout(socket.timer);sockets.delete(socket.id);
      for(const job of socket.pending.values()){clearTimeout(job.timer);job.reject(Object.assign(Error(reason||'socket_closed'),{code:reason||'socket_closed'}));}socket.pending.clear();
      if(socket.reject){socket.reject(Object.assign(Error(reason||'connect_failed'),{code:reason||'connect_failed'}));socket.reject=null;}
      try{socket.reader?.close();}catch(_){}
      socket.finish({code,reason});socket.emit('close',new CloseEvent('close',{code,reason,wasClean:code===1000}));
    }
    window.addEventListener('message',event=>{
      const message=event.data;if(event.source!==parent||event.origin!==parentOrigin||message?.market!==token||message.socket!==true)return;
      const socket=sockets.get(message.id);if(!socket)return;
      if(message.op==='open'){clearTimeout(socket.timer);socket.readyState=1;socket.reject=null;socket.resolve(socket);socket.emit('open',new Event('open'));}
      else if(message.op==='data'&&message.data instanceof ArrayBuffer){
        if(socket.reader){if(socket.reader.desiredSize<0){socket.close();return;}socket.reader.enqueue(new Uint8Array(message.data));}
        const data=socket.binaryType==='blob'?new Blob([message.data]):message.data;socket.emit('message',new MessageEvent('message',{data}));
      }else if(message.op==='ack'){const job=socket.pending.get(message.request);if(!job)return;clearTimeout(job.timer);socket.pending.delete(message.request);if(message.error)job.reject(Object.assign(Error(message.error),{code:message.error}));else job.resolve();}
      else if(message.op==='error'){try{socket.emit('error',new Event('error'));}finally{finishSocket(socket,1011,message.error);}}
      else if(message.op==='close')finishSocket(socket,message.code||1000,message.reason||'');
    });
    window.BookStark.sockets={connect:(host,port)=>new Promise((resolve,reject)=>{
      if(typeof host==='object'&&host){port=host.port;host=host.host;}
      if(typeof host!=='string'||!Number.isInteger(port)||port<1||port>65535){reject(TypeError('Invalid TCP host or port'));return;}
      if(sockets.size>=8){reject(Error('socket_limit'));return;}
      const socket=new ToolSocket(++socketSequence);socket.resolve=resolve;socket.reject=reject;sockets.set(socket.id,socket);
      socket.timer=setTimeout(()=>{socket.close();finishSocket(socket,1011,'connect_timeout');},10000);
      parent.postMessage({market:token,socket:true,id:socket.id,op:'connect',host,port},parentOrigin);
    })};

    let session=Object.create(null);
    Object.defineProperty(window,'sessionStorage',{value:{getItem:k=>session[String(k)]??null,setItem:(k,v)=>{session[String(k)]=String(v);},removeItem:k=>{delete session[String(k)];},clear:()=>{session=Object.create(null);},key:i=>Object.keys(session)[i]??null,get length(){return Object.keys(session).length;}}});
  }
 async function run(){
  try{
   meta=await store.snapshot(id);
   updateIdentity(meta);
   values=Object.assign(Object.create(null),meta.values||{});info.disabled=false;exportButton.disabled=false;
   newTab.hidden=!!window.BookStarkHost?.available;if(window.BookStarkClient)Promise.resolve(BookStarkClient.ready).then(ready=>{if(ready)newTab.hidden=true;}).catch(()=>{});
   frame=document.createElement('iframe');frame.title=meta.title;const isolated=!!runtime.url&&runtime.instance===meta.instance&&runtime.revision===meta.revision;
   if(runtime.url&&!isolated)throw Error('conflict');
   if(isolated&&new URL(runtime.url).origin===location.origin)throw Error('unsafe tool origin');
   frame.setAttribute('sandbox',permissionsUI.sandbox(meta.permissions,isolated));frame.setAttribute('allow',permissionsUI.allow(meta.permissions,isolated));frame.referrerPolicy='no-referrer';
   const token=crypto.randomUUID(),targetOrigin=isolated?runtime.origin:'*',json=value=>JSON.stringify(value).replace(/</g,'\\u003c'),assetPrefix='/api/tool-assets/'+meta.instance+'/';
   const doc=new DOMParser().parseFromString(meta.content.split(assetPrefix).join(location.origin+assetPrefix),'text/html');doc.querySelectorAll('base').forEach(el=>el.remove());
   const assetRoot=location.origin+assetPrefix,policy=doc.createElement('meta');policy.httpEquiv='Content-Security-Policy';
   const network=meta.permissions?.network?' http: https: wss:':'',formAction=meta.permissions?.network&&permissionsUI.effective(meta.permissions).forms?'http: https:':"'none'";
   policy.content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob: "+assetRoot+network+"; style-src 'unsafe-inline' "+assetRoot+network+"; img-src data: blob: "+assetRoot+network+"; font-src data: "+assetRoot+network+"; media-src blob: data: "+assetRoot+network+"; connect-src "+assetRoot+network+"; form-action "+formAction+"; frame-src 'none'; object-src 'none'";
   doc.head.prepend(policy);
   if(!isolated){const base=doc.createElement('base');base.href=new URL(/^https?:\/\//.test(meta.source)?meta.source:'/market',location.origin).href;doc.head.prepend(base);}
   const script=doc.createElement('script');script.textContent='('+storageBootstrap.toString()+')('+json(meta.values||{})+','+json(token)+','+json(location.origin)+');';doc.head.insertBefore(script,policy.nextSibling);
   const sockets=new Map(),closeSockets=()=>{for(const record of sockets.values()){clearTimeout(record.timer);record.ws.close();}sockets.clear();};
   window.addEventListener('pagehide',closeSockets,{once:true});
   window.addEventListener('message',event=>{
    const item=event.data;if(stale||event.source!==frame.contentWindow||event.origin!==(isolated?runtime.origin:'null')||!item)return;
    if(isolated&&item.toolFrame===runtime.nonce&&item.ready===true){frame.contentWindow.postMessage({toolFrame:runtime.nonce,html:'<!doctype html>'+doc.documentElement.outerHTML},runtime.origin);return;}
    if(item.market!==token)return;
    if(item.op==='runtime-ready'){completeLoading();return;}
    if(item.op==='exit-fullscreen'){if(document.body.classList.contains('tool-runtime-fullscreen'))setFullscreen(false);return;}
    if(item.op==='resource-error'){if(loadPhase==='loading'||loadPhase==='slow')showState('run_resource_failed');return;}
    if(item.socket===true){
     if(!Number.isSafeInteger(item.id)||item.id<1)return;
     const reply=value=>frame.contentWindow?.postMessage({market:token,socket:true,id:item.id,...value},targetOrigin);
     if(!meta.permissions?.socket_tcp){reply({op:'error',error:'permission_denied'});return;}
     if(item.op==='connect'){
      if(sockets.has(item.id)||sockets.size>=8){reply({op:'error',error:'socket_limit'});return;}
      if(typeof item.host!=='string'||item.host.length>253||!Number.isInteger(item.port)||item.port<1||item.port>65535){reply({op:'error',error:'invalid_socket_target'});return;}
      if(!runtime.socket_proxy){reply({op:'error',error:'socket_proxy_disabled'});return;}
      const url=new URL('/api/tool-installs/'+id+'/socket',location.origin);url.protocol=location.protocol==='https:'?'wss:':'ws:';url.search=new URLSearchParams({revision:meta.revision,instance:meta.instance,host:item.host,port:String(item.port)});
      const ws=new WebSocket(url),record={ws,opened:false};ws.binaryType='arraybuffer';sockets.set(item.id,record);
      record.timer=setTimeout(()=>{reply({op:'error',error:'connect_timeout'});ws.close();},8000);
      ws.onmessage=event=>{if(!record.opened){let hello;try{hello=JSON.parse(event.data);}catch(_){}if(!hello?.connected){ws.close();return;}record.opened=true;clearTimeout(record.timer);reply({op:'open'});return;}if(event.data instanceof ArrayBuffer)reply({op:'data',data:event.data});};
      ws.onerror=()=>reply({op:'error',error:'connect_failed'});
      ws.onclose=event=>{clearTimeout(record.timer);sockets.delete(item.id);reply({op:'close',code:event.code,reason:event.reason||(!record.opened?'connect_failed':'')});};
     }else {
      const record=sockets.get(item.id);if(!record){reply({op:'error',error:'socket_closed'});return;}
      if(item.op==='close'){record.ws.close();return;}
      if(item.op==='send'&&Number.isSafeInteger(item.request)&&item.data instanceof ArrayBuffer&&item.data.byteLength<=65536){
       if((record.queued||0)>=16){reply({op:'ack',request:item.request,error:'socket_backpressure'});return;}
       record.queued=(record.queued||0)+1;
       const transmit=async()=>{const deadline=Date.now()+10000;while(record.ws.bufferedAmount>256*1024){if(record.ws.readyState!==WebSocket.OPEN||Date.now()>deadline)throw Error('socket_backpressure');await new Promise(resolve=>setTimeout(resolve,20));}if(record.ws.readyState!==WebSocket.OPEN)throw Error('socket_closed');record.ws.send(item.data);reply({op:'ack',request:item.request});};
       record.queue=(record.queue||Promise.resolve()).then(transmit).catch(error=>{reply({op:'ack',request:item.request,error:error.message});record.ws.close();}).finally(()=>record.queued--);
      }
     }
     return;
    }
    if(item.file===true){
     const requirements={GET:[true,false],PUT:[false,true],list:[true,false],stat:[true,false],exists:[true,false],mkdir:[false,true],remove:[false,true],rename:[false,true],move:[false,true],copy:[true,true]},required=Object.hasOwn(requirements,item.method)?requirements[item.method]:null;
     if(!required||typeof item.name!=='string'||item.name.length>2048||!Number.isSafeInteger(item.request)||(item.method==='PUT'&&!(item.content instanceof ArrayBuffer)))return;
     const reply=value=>frame.contentWindow?.postMessage({market:token,fileReply:true,request:item.request,...value},targetOrigin);
     if(required[0]&&!meta.permissions?.read_files||required[1]&&!meta.permissions?.save_files){reply({error:'permission_denied'});return;}
     if(required[1])pendingFiles++;
     const options=item.options||{},operation={op:item.method,path:item.name,to:options.to,recursive:options.recursive===true};
     const task=['GET','PUT'].includes(item.method)?store.file(id,meta.revision,meta.instance,item.method,item.name,item.content).then(content=>({content})):store.fileOperation(id,meta.revision,meta.instance,operation).then(result=>({result}));
     task.then(reply).catch(error=>reply({error:error.message||'storage'})).finally(()=>{if(required[1])pendingFiles--;settled();});
     return;
    }
    if(!['set','remove','clear'].includes(item.op)||(item.op!=='clear'&&typeof item.key!=='string')||(item.op==='set'&&typeof item.value!=='string'))return;
    if(item.op==='set')values[item.key]=item.value;else if(item.op==='remove')delete values[item.key];else Object.keys(values).forEach(key=>delete values[key]);
    const last=operations.length-1;if(last>=(draining?1:0)&&item.op!=='clear'&&operations[last].op!=='clear'&&operations[last].key===item.key)operations[last]=item;else operations.push(item);
    if(operations.length>500){frame.remove();banner.hidden=false;failed=true;showState('failed');return;}
    if(!failed)drain();
   });
   frame.addEventListener('error',()=>showState('run_resource_failed'),{once:true});
   if(isolated)frame.src=runtime.url;else frame.srcdoc='<!doctype html>'+doc.documentElement.outerHTML;host.append(frame);
   const unavailable=permissionsUI.selected(meta.permissions).some(spec=>spec.policy&&!['fullscreen','autoplay','picture-in-picture'].includes(spec.policy));
   const notices=[];if(!isolated&&unavailable)notices.push(ToolMarketUI.text('此环境未配置独立运行来源，设备与剪贴板等能力不可用。','Device and clipboard capabilities are unavailable until an isolated runtime origin is configured.'));if(meta.permissions?.socket_tcp&&!runtime.socket_proxy)notices.push(ToolMarketUI.text('此服务器未开启工具 TCP 代理。','The tool TCP proxy is disabled on this server.'));if(notices.length){const note=document.getElementById('toolRuntimeCapabilities');note.textContent=notices.join(' ');note.hidden=false;}
   const check=async()=>{if(stale)return;try{const current=await store.get('tools',id);if(!current||current.revision!==meta.revision||current.instance!==meta.instance){stale=true;closeSockets();frame.remove();showState('stale');}}catch(_){}};
   window.addEventListener('tool-market-changed',check);const timer=setInterval(()=>{if(!document.hidden)check();},15000);window.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
   store.patch(id,{used:Date.now()}).catch(()=>{});
  }catch(error){showState(error.message==='not_found'?'not_installed':'failed');}
 }
 run();
})();
