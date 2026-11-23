(function () {
  'use strict';
  const store=window.BookStarkMarketStore, t=key=>__('market.'+key), e=escHtml;
  const query=new URLSearchParams(location.search), installedView=query.get('view')==='installed', runID=Number(query.get('open'));
  const main=document.getElementById('marketMain'), items=document.getElementById('marketItems');
  let catalog=[], installed=[], catalogOK=false, filter='all', search='', limit=24, selected=0, busy=false, installationError='';
  const revision=row=>'r.'+row.revision.slice(0,8);
  const source=row=>/^https?:\/\//.test(row.source)?row.source:'/shares/'+encodeURIComponent(row.source);
  let marketServer=query.get('server')||'';
  const openURL=id=>'/market?open='+id;
  const button=(action,id,label,primary=false)=>'<button type="button" class="bs-btn '+(primary?'bs-btn-primary':'bs-btn-cancel')+'" data-market-action="'+action+'" data-id="'+id+'">'+e(label)+'</button>';
  const icon=row=>/电视|tv|video/i.test(row.title)?'fa-tv':/游戏|game|arcade/i.test(row.title)?'fa-gamepad':/画|craft|draw/i.test(row.title)?'fa-pen-ruler':/投资|finance/i.test(row.title)?'fa-chart-line':'fa-code';
  function state(row) { const latest=catalog.find(x=>x.id===row.id); return !catalogOK?'':!latest?'unavailable':latest.revision!==row.revision?'updates':'latest'; }
  function status(message) { const el=document.getElementById('marketStatus'); if(el){el.hidden=!message;el.textContent=message;} }
  function menu(row) {
    const actions=[['details','details'],['pin',row.pinned?'unpin':'pin'],['export','export'],['uninstall','uninstall']];
    return '<div class="bs-action-dropdown"><button type="button" class="row-action bs-action-dd-btn" data-bs-action-dropdown-toggle aria-haspopup="menu" aria-expanded="false" aria-label="'+e(t('menu'))+'"><i class="fa-solid fa-ellipsis" aria-hidden="true"></i></button><div class="bs-action-dd-menu" role="menu">'+actions.map(([a,l])=>'<button type="button" role="menuitem" class="bs-action-menu-item '+(a==='uninstall'?'market-danger':'')+'" data-market-action="'+a+'" data-id="'+row.id+'">'+e(t(l))+'</button>').join('')+'</div></div>';
  }
  function actions(row, compact=false, badge=true) {
    const local=installed.find(x=>x.id===row.id);
    if(!local)return button('install',row.id,t('install'),true);
    return (badge?'<span class="tag-badge '+(state(local)==='updates'?'market-state-update':'market-state-installed')+'">'+e(t(state(local)==='updates'?'updates':'installed'))+'</span>':'')+(state(local)==='updates'?button('update',row.id,t('update'),true):'')+'<a class="bs-btn '+(state(local)==='updates'?'bs-btn-cancel':'bs-btn-primary')+'" href="'+openURL(row.id)+'">'+e(t('open'))+'</a>'+(!compact?menu(local):'');
  }
  function renderDetail() {
    const el=document.getElementById('marketDetail'); if(!el)return;
    const row=installed.find(x=>x.id===selected)||catalog.find(x=>x.id===selected);
    if(!row){el.innerHTML='<h2>'+e(t('mine'))+'</h2><div id="marketShortcuts"></div>';renderShortcuts();return;}
    el.innerHTML='<div class="market-detail-title"><span class="market-icon"><i class="fa-solid '+icon(row)+'" aria-hidden="true"></i></span><h2>'+e(row.title)+'</h2></div><dl class="market-detail-list"><dt>'+e(t('author'))+'</dt><dd>'+e(row.author)+'</dd><dt>'+e(t('version'))+'</dt><dd>'+e(revision(row))+'</dd><dt>'+e(t('data'))+'</dt><dd>'+e(t('local'))+'</dd></dl><a class="bs-btn bs-btn-primary" href="'+source(row)+'">'+e(t('source'))+'</a><button type="button" class="row-action" title="'+e(t('storage_help'))+'" aria-label="'+e(t('storage_help'))+'"><i class="fa-regular fa-circle-question" aria-hidden="true"></i></button>';
  }
  function renderShortcuts() {
    const el=document.getElementById('marketShortcuts');if(!el)return;
    const rows=installed.filter(x=>x.pinned).slice(0,6);
    el.innerHTML=rows.length?rows.map(row=>'<a class="market-shortcut" href="'+openURL(row.id)+'"><i class="fa-solid '+icon(row)+'" aria-hidden="true"></i><strong>'+e(row.title)+'</strong>'+(state(row)==='updates'?'<span class="tag-badge market-state-update">'+e(t('updates'))+'</span>':'')+'<span aria-hidden="true">›</span></a>').join(''):'<a href="/market">'+e(t('browse'))+'</a>';
  }
  function render() {
    document.querySelectorAll('[data-market-card]').forEach(el=>{const id=Number(el.dataset.marketCard),row=catalog.find(x=>x.id===id)||installed.find(x=>x.id===id);el.innerHTML=row?actions(row,true):'';});
    renderShortcuts();
    if(!items)return;
    if(installedView&&!selected&&installed.length)selected=installed[0].id;
    const all=installedView?installed:catalog;
    const rows=all.filter(row=>(filter!=='updates'||installed.some(x=>x.id===row.id&&state(x)==='updates'))&&[row.title,row.author,row.description].some(s=>(s||'').toLowerCase().includes(search)));
    items.innerHTML=rows.slice(0,limit).map(row=>'<article class="market-row" data-tool-id="'+row.id+'"><span class="market-icon"><i class="fa-solid '+icon(row)+'" aria-hidden="true"></i></span><div><h2 class="list-row-title"><button type="button" data-market-action="details" data-id="'+row.id+'">'+e(row.title)+'</button></h2>'+(row.description?'<p>'+e(row.description.slice(0,160))+'</p>':'')+'<div class="market-meta"><span>'+e(row.author)+'</span><span>'+e(revision(row))+'</span>'+(installedView?'<span>'+e(row.used?new Date(row.used).toLocaleString(document.documentElement.lang):t('never'))+'</span>':'')+'</div></div><div class="market-actions">'+actions(row)+'</div></article>').join('')||'<div class="public-empty">'+e(t(search?'no_match':'empty'))+'</div>';
    if(installedView && rows.length) items.innerHTML='<div class="market-table-wrap"><table class="market-table"><thead><tr><th>'+e(t('tool'))+'</th><th>'+e(t('version'))+'</th><th>'+e(t('status'))+'</th><th>'+e(t('used'))+'</th><th>'+e(t('actions'))+'</th></tr></thead><tbody>'+rows.slice(0,limit).map(row=>'<tr class="market-row'+(selected===row.id?' is-selected':'')+'" data-tool-id="'+row.id+'"><td><div class="market-table-name"><span class="market-icon"><i class="fa-solid '+icon(row)+'" aria-hidden="true"></i></span><h2 class="list-row-title"><button type="button" data-market-action="details" data-id="'+row.id+'">'+e(row.title)+'</button></h2></div></td><td class="market-table-version">'+e(revision(row))+(state(row)==='updates'?'<br>→ '+e(revision(catalog.find(x=>x.id===row.id))):'')+'</td><td><span class="tag-badge '+(state(row)==='updates'?'market-state-update':'market-state-installed')+'">'+e(t(state(row)||'installed'))+'</span></td><td class="market-table-used">'+e(row.used?new Date(row.used).toLocaleDateString(document.documentElement.lang):t('never'))+'</td><td><div class="market-actions">'+actions(row,false,false)+'</div></td></tr>').join('')+'</tbody></table></div>';
    document.getElementById('marketMore').hidden=rows.length<=limit;
    document.getElementById('marketUpdateCount').textContent=installed.filter(x=>state(x)==='updates').length;
    renderDetail();
  }
  async function requestJSON(path) {
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
    try{const response=await fetch(path,{cache:'no-store',signal:controller.signal});if(!response.ok)throw Error('network');return await response.json();}
    finally{clearTimeout(timer);}
  }
  async function refreshCatalog(report=false) {
    const btn=document.getElementById('marketCheck');if(btn)btn.disabled=true;
    try {
      const result=await requestJSON('/api/tool-market');if(!Array.isArray(result.tools))throw Error('catalog');
      catalog=marketServer?[]:result.tools;
      const servers=new Set(installed.filter(x=>/^https?:\/\//.test(x.source)).map(x=>new URL(x.source).origin));if(marketServer)servers.add(marketServer);
      for(const server of servers){const response=await fetchWithCurrentCSRF('/api/tool-sources',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({server})});if(!response.ok)throw Error('catalog');const remote=await response.json();catalog.push(...remote.tools);}
      catalogOK=true;
      status(installationError);if(report&&!installationError)BSDialog.toast(t('checked'),'success');
    }catch(_){catalogOK=false;status(t('catalog_failed'));}
    finally{if(btn)btn.disabled=false;render();}
  }
  async function loadPackage(id) { return requestJSON((id<0?'/api/tool-sources/':'/api/tool-market/')+id); }
  async function exportData(row, values) {
    const data=values?null:await store.get('data',row.id), blob=new Blob([JSON.stringify({format:'bookstark-tool-data',version:1,tool:{id:row.id,title:row.title,revision:row.revision},values:values||data?.values||{}},null,2)],{type:'application/json'});
    const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='bookstark-tool-'+row.id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);BSDialog.toast(t('export_ok'),'success');
  }
  document.addEventListener('click',async event=>{
    const el=event.target.closest('[data-market-action]');if(!el||busy)return;
    const id=Number(el.dataset.id),action=el.dataset.marketAction,local=installed.find(x=>x.id===id),row=local||catalog.find(x=>x.id===id);if(!row)return;
    const dropdown=el.closest('.bs-action-dropdown'); if(dropdown){dropdown.classList.remove('open');dropdown.querySelector('.bs-action-dd-btn').setAttribute('aria-expanded','false');}
    busy=true;el.disabled=true;
    try{
      if(action==='details'){if(!main){location.href='/market?view=installed&selected='+id;return;}selected=id;render();}
      else if(action==='install'||action==='update'){
        if(!store.authenticated){location.href='/login?next='+encodeURIComponent(location.pathname+location.search);return;}
        const pkg=await loadPackage(id);
        if(local?.revision===pkg.revision){await refreshCatalog();return;}
        const approved=await BSDialog.confirm2(action==='install'?t('confirm_install'):t('confirm_update')+' · '+row.title,{description:(local?revision(local)+' → '+revision(pkg)+'\n'+t('update_help'):pkg.title+'\n'+t('install_help')),confirmLabel:t(action)});
        if(approved){await store.install(pkg,local?.revision||null,local?.instance);BSDialog.toast(t(local?'updated_ok':'installed_ok'),'success');await refreshCatalog();}
      }else if(action==='uninstall'){
        if(await BSDialog.confirm2(t('confirm_uninstall')+' · '+row.title,{description:t('uninstall_help'),confirmLabel:t('uninstall')})){
          await store.remove(id,local.revision,local.instance);BSDialog.toast(t('removed_ok'),'success');
        }
      }else if(action==='pin')await store.patch(id,{pinned:!local.pinned});
      else if(action==='export')await exportData(row);
    }catch(error){BSDialog.toast(t(['cleanup_pending','resource_download_failed'].includes(error.message)?error.message:'failed'),'error');}
    finally{busy=false;el.disabled=false;await refreshInstalled();}
  });
  async function refreshInstalled(){try{installed=await store.list();installationError='';render();}catch(error){installationError=t(['cleanup_pending','resource_download_failed'].includes(error.message)?error.message:'failed');status(installationError);}}
  window.addEventListener('tool-market-changed',refreshInstalled);
  window.addEventListener('focus',refreshInstalled);
  document.addEventListener('bookstark:public-feed-updated',render);
  if(main){
    selected=Number(query.get('selected'));
    document.getElementById('marketHeading').textContent=t(installedView?'mine':'title');
    document.getElementById(installedView?'marketInstalledTab':'marketCatalogTab').setAttribute('aria-current','page');
    document.getElementById('marketSource').hidden=installedView;
    document.getElementById('marketServer').value=marketServer;
    document.getElementById('marketSource').onsubmit=event=>{event.preventDefault();if(!store.authenticated){location.href='/login?next='+encodeURIComponent(location.href);return;}marketServer=document.getElementById('marketServer').value.trim().replace(/\/$/,'');const url=new URL(location.href);url.searchParams.set('server',marketServer);history.replaceState(null,'',url);refreshCatalog();};
    document.getElementById('marketLocal').onclick=()=>{marketServer='';document.getElementById('marketServer').value='';const url=new URL(location.href);url.searchParams.delete('server');history.replaceState(null,'',url);refreshCatalog();};
    document.getElementById('marketSearch').onsubmit=event=>{event.preventDefault();search=document.getElementById('marketQuery').value.trim().toLowerCase();limit=24;render();};
    document.getElementById('marketQuery').oninput=()=>{search=document.getElementById('marketQuery').value.trim().toLowerCase();limit=24;render();};
    document.getElementById('marketCheck').onclick=async()=>{await refreshInstalled();await refreshCatalog(true);};
    document.getElementById('marketMore').onclick=()=>{limit+=24;render();};
    document.querySelectorAll('[data-market-filter]').forEach(btn=>{btn.onclick=()=>{filter=btn.dataset.marketFilter;limit=24;document.querySelectorAll('[data-market-filter]').forEach(x=>x.setAttribute('aria-pressed',String(x===btn)));render();};});
  }
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
      const base=doc.createElement('base');base.href=new URL(source(meta),location.origin).href;doc.head.prepend(base);
      const script=doc.createElement('script');script.textContent='('+storageBootstrap.toString()+')('+json(data?.values||{})+','+json(token)+');';doc.head.prepend(script);
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
  if(main&&runID)runTool(runID);else{status(t('loading'));refreshInstalled().then(()=>refreshCatalog());}
})();
