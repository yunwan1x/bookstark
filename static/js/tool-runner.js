(function(){'use strict';
 const query=new URLSearchParams(location.search),runID=Number(query.get('open'));if(!runID)return;
 const store=window.BookStarkMarketStore,main=document.getElementById('marketMain'),t=key=>__('market.'+key);
 const source=row=>/^https?:\/\//.test(row.source)?row.source:'/market';
 async function exportData(row,values){const blob=new Blob([JSON.stringify({tool:row.id,values},null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='tool-data.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),10000);}
  function storageBootstrap(initial,token) {
    const values=Object.assign(Object.create(null),initial);
    const send=(op,key,value)=>parent.postMessage({market:token,op,key,value},'*');
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
  async function runTool(id) {
    if(!store.authenticated){location.href='/login?next='+encodeURIComponent(location.pathname+location.search);return;}
    main.hidden=true;document.getElementById('marketRunner').hidden=false;
    const save=document.getElementById('marketSaveStatus');
    try{
      const meta=await store.snapshot(id),pkg=meta,data={values:meta.values};
      if(!meta||!pkg){save.textContent=t('not_installed');return;}
      if(pkg.revision!==meta.revision||pkg.instance!==meta.instance){save.textContent=t('stale');return;}
      document.getElementById('marketRunnerTitle').textContent=meta.title;
      const frame=document.createElement('iframe');frame.title=meta.title;frame.setAttribute('sandbox','allow-scripts allow-forms allow-downloads');frame.referrerPolicy='no-referrer';
      const token=crypto.randomUUID(),json=value=>JSON.stringify(value).replace(/</g,'\\u003c');
      const assetPrefix='/api/tool-assets/'+meta.instance+'/';
      const doc=new DOMParser().parseFromString(pkg.content.split(assetPrefix).join(location.origin+assetPrefix),'text/html');
      doc.querySelectorAll('base').forEach(el=>el.remove());
      const policy=doc.createElement('meta');policy.httpEquiv='Content-Security-Policy';
      const assetRoot=location.origin+'/api/tool-assets/'+meta.instance+'/';
      policy.content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob: "+assetRoot+"; style-src 'unsafe-inline' "+assetRoot+"; img-src data: blob: "+assetRoot+"; font-src data: "+assetRoot+"; media-src blob: data: "+assetRoot+"; connect-src "+(meta.permissions?.network?"http: https: wss:":assetRoot)+"; form-action 'none'; frame-src 'none'";
      doc.head.prepend(policy);

      const base=doc.createElement('base');base.href=new URL(source(meta),location.origin).href;doc.head.prepend(base);
      const script=doc.createElement('script');script.textContent='('+storageBootstrap.toString()+')('+json(data?.values||{})+','+json(token)+');';doc.head.insertBefore(script,policy.nextSibling);
      const values=Object.assign(Object.create(null),data?.values||{}),operations=[];
      let pending=0,failed=false,draining=false;
      const retry=document.getElementById('marketRetry');
      async function drain() {
        if(draining)return;draining=true;failed=false;retry.hidden=true;save.setAttribute('role','status');
        while(operations.length){
          const message=operations[0];save.textContent=t('saving');
          try{await store.writeData(id,meta.revision,meta.instance,message.op,message.key,message.value);operations.shift();pending=operations.length;}
          catch(_){failed=true;save.setAttribute('role','alert');save.textContent=t('save_error');retry.hidden=false;break;}
        }
        if(!failed)save.textContent=t('saved');draining=false;
      }
      retry.onclick=drain;
      document.getElementById('marketRunExport').onclick=()=>exportData(meta,values).catch(()=>BSDialog.toast(t('failed'),'error'));
      window.addEventListener('message',event=>{
        const message=event.data;
        if(event.source!==frame.contentWindow||!message||message.market!==token)return;
        if(message.file===true){
          if(!['GET','PUT'].includes(message.method)||typeof message.name!=='string'||message.name.length>2048||(message.method==='PUT'&&!(message.content instanceof ArrayBuffer)))return;
          if(((message.method==='GET'&&!meta.permissions?.read_files)||(message.method==='PUT'&&!meta.permissions?.save_files))){frame.contentWindow?.postMessage({market:token,fileReply:true,request:message.request,error:t('failed')},'*');return;}
          store.file(id,meta.revision,meta.instance,message.method,message.name,message.content).then(content=>frame.contentWindow?.postMessage({market:token,fileReply:true,request:message.request,content},'*')).catch(()=>frame.contentWindow?.postMessage({market:token,fileReply:true,request:message.request,error:t('failed')},'*'));
          return;
        }
        if(!['set','remove','clear'].includes(message.op))return;
        if((message.op!=='clear'&&typeof message.key!=='string')||(message.op==='set'&&typeof message.value!=='string'))return;
        if(message.op==='set')values[message.key]=message.value;else if(message.op==='remove')delete values[message.key];else Object.keys(values).forEach(k=>delete values[k]);
        const last=operations.length-1;
        if(last>=(draining?1:0)&&message.op!=='clear'&&operations[last].op!=='clear'&&operations[last].key===message.key)operations[last]=message;
        else operations.push(message);
        pending=operations.length;
        if(pending>500){frame.remove();failed=true;save.setAttribute('role','alert');save.textContent=t('save_error');retry.hidden=false;return;}
        if(!failed)drain();
      });
      window.addEventListener('beforeunload',event=>{if(pending||failed){event.preventDefault();event.returnValue='';}});
      window.addEventListener('tool-market-changed',async()=>{try{const current=await store.get('tools',id);if(!current||current.revision!==meta.revision||current.instance!==meta.instance){frame.remove();save.setAttribute('role','alert');save.textContent=t('stale');}}catch(_){}});
      const check=setInterval(()=>{if(!document.hidden)window.dispatchEvent(new Event('tool-market-changed'));},15000);
      window.addEventListener('pagehide',()=>clearInterval(check),{once:true});
      frame.srcdoc='<!doctype html>'+doc.documentElement.outerHTML;document.getElementById('marketFrameHost').append(frame);
      await store.patch(id,{used:Date.now()});
    }catch(error){save.setAttribute('role','alert');save.textContent=t(error.message==='not_found'?'not_installed':'failed');}
  }
  runTool(runID);
})();
