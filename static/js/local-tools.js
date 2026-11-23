(function () {
  'use strict';
  const store = BookStarkLocalDrafts, E = BookStarkEditor;
  const el = id => document.getElementById(id), t = key => __('tools.' + key);
  let draft = null, revision = 0, ready = false, lastContent = '', lastTitle = '', dirty = false;
  let timer, saving = null, failed = false, adapter = null, mind = null, sheet = null;
  const uuid = () => crypto.randomUUID();
  function state(key) {
    el('toolsStatus').textContent = t(key) + (key === 'saved' && draft && draft.updated ? ' · ' + new Date(draft.updated).toLocaleTimeString(document.documentElement.lang,{hour:'2-digit',minute:'2-digit'}) : '');
    el('toolsStatus').dataset.state = key === 'saved' ? 'saved' : ['unsaved','conflict','unavailable'].includes(key) ? 'error' : '';
    el('toolsRetry').hidden = !['unsaved','unavailable'].includes(key);
    el('toolsCopy').hidden = key !== 'conflict';
  }
  function error(e) { BSDialog.toast(e.code === 'conflict' ? t('conflict') : e.message || t('unsaved'), 'error'); }
  window.BookStarkLocalFile = file => new Promise((resolve, reject) => {
    if (!file || !/^image\//.test(file.type) || file.size > 5*1024*1024) { reject(new Error(t('image_large'))); return; }
    const r = new FileReader(); r.onerror = () => reject(r.error); r.onload = () => resolve({ url:r.result }); r.readAsDataURL(file);
  });
  window.BookStarkUniverUploadImage = window.BookStarkLocalFile;
  function content() { return adapter ? adapter.get() : draft ? draft.content : ''; }
  function capture() {
    if (!ready || !draft) return false;
    let value;
    try { value = content(); } catch (_) { dirty=true; failed=true; state('unsaved'); return null; }
    if (value == null) return false;
    const title = el('toolsTitle').value.trim() || t('untitled');
    if (value === lastContent && title === lastTitle) return dirty;
    draft.content = value; draft.title = title; lastContent = value; lastTitle = title;
    dirty = true; return true;
  }
  function changed() {
    if (!ready) return;
    if (capture()) { state('saving'); clearTimeout(timer); timer = setTimeout(flush, 350); }
  }
  async function flush() {
    clearTimeout(timer); if (capture() === null) return false;
    if (saving) { await saving; if (!failed && dirty) return flush(); return !failed; }
    if (!dirty || !draft) return !failed;
    const snapshot = Object.assign({}, draft); dirty = false; failed = false; state('saving');
    saving = store.save(snapshot, revision).then(meta => {
      revision = meta.revision; draft.updated = meta.updated;
      history.replaceState(null, '', '/tools?draft=' + encodeURIComponent(draft.id));
      state(dirty ? 'saving' : 'saved');
    }).catch(e => { dirty = true; failed = true; state(e.code === 'conflict' ? 'conflict' : 'unsaved'); })
      .finally(() => { saving = null; });
    await saving;
    if (!failed && dirty) return flush();
    return !failed;
  }
  async function leave(url) {
    if (!(await flush()) && !(await BSDialog.confirm2(t('discard')))) return;
    dirty = false; ready = false; location.href = url;
  }
  async function refreshList() {
    try {
      const rows = await store.list(); el('toolsDrafts').replaceChildren();
      if (!rows.length) el('toolsDrafts').textContent = t('empty');
      rows.forEach(d => {
        const row = document.createElement('div'); row.className = 'local-draft-row';
        const a = document.createElement('a'); a.href = '/tools?draft=' + encodeURIComponent(d.id);
        if (draft && draft.id === d.id) a.setAttribute('aria-current','page');
        const title = document.createElement('strong'); title.textContent = d.title;
        const info = document.createElement('small'); info.textContent = t(d.type) + ' · ' + new Date(d.updated).toLocaleString(document.documentElement.lang);
        a.append(title,info); a.onclick = e => { e.preventDefault(); if (!draft || draft.id !== d.id) leave(a.href); else drawer(false); };
        const rename = document.createElement('button'); rename.className='row-action'; rename.setAttribute('aria-label',t('rename')); rename.innerHTML='<i class="fa-solid fa-pen" aria-hidden="true"></i>';
        rename.onclick = async () => {
          try {
            const name = await BSDialog.prompt2(t('rename'), d.title); if (!name || !name.trim()) return;
            if (draft && draft.id === d.id) { el('toolsTitle').value=name.slice(0,120); changed(); await flush(); }
            else { const old = await store.get(d.id); if (!old) throw new Error(t('missing')); old.title=name.trim().slice(0,120); await store.save(old,d.revision); }
          } catch(e) { error(e); }
        };
        const del = document.createElement('button'); del.className='row-action del'; del.setAttribute('aria-label',t('delete')); del.innerHTML='<i class="fa-solid fa-trash" aria-hidden="true"></i>';
        del.onclick = async () => {
          if (!(await BSDialog.confirm2(t('confirm_delete')))) return;
          try {
            const current = draft && draft.id === d.id;
            if (current) { clearTimeout(timer); await flush(); }
            await store.remove(d.id, current ? revision : d.revision);
            if (current) { dirty=false; ready=false; location.href='/tools'; }
          } catch(e) { error(e); }
        };
        row.append(a,rename,del); el('toolsDrafts').append(row);
      });
      el('toolsUsage').textContent = t('usage').replace('{count}',rows.length).replace('{size}',(rows.reduce((n,d)=>n+d.bytes,0)/1048576).toFixed(2));
    } catch (_) { el('toolsDrafts').textContent = t('unavailable'); }
  }
  function drawer(open) {
    el('toolsSidebar').classList.toggle('is-open',open); el('toolsBackdrop').hidden=!open;
    el('toolsDrawer').setAttribute('aria-expanded',String(open));
    if (open) el('toolsNew').focus(); else el('toolsDrawer').focus();
  }
  function download(value, name, mime) {
    const url = URL.createObjectURL(value instanceof Blob ? value : new Blob([value],{type:mime||'application/json'}));
    const a=document.createElement('a'); a.href=url; a.download=name; a.click(); setTimeout(()=>URL.revokeObjectURL(url),30000);
  }
  function filename() { return (el('toolsTitle').value.trim() || t('untitled')).replace(/[\\/:*?"<>|\x00-\x1f]/g,'_').slice(0,100); }
  function exportNative() {
    capture(); download(JSON.stringify({schema:'bookstark-local-draft',version:1,type:draft.type,title:el('toolsTitle').value||t('untitled'),content:content()},null,2),filename()+'.bookstark.json');
  }
  function exportMenu() {
    const menu=el('toolsExportMenu'); menu.replaceChildren();
    function item(label,fn) {
      const b=document.createElement('button'); b.type='button'; b.className='bs-btn bs-btn-cancel'; b.textContent=label;
      b.onclick=async()=>{el('toolsExport').open=false;try{await fn();}catch(e){error(e);}};menu.append(b);
    }
    item(t('native'),exportNative);
    if(draft.type==='markdown') item('Markdown (.md)',()=>download(content(),filename()+'.md','text/markdown;charset=utf-8'));
    if(draft.type==='richdoc') {
      item(t('text'),()=>download(adapter.instance.getText(),filename()+'.txt','text/plain;charset=utf-8'));
      item(t('pdf'),()=>adapter.instance.command('executePrint'));
    }
    if(draft.type==='drawing') item('Excalidraw (.excalidraw)',()=>download(JSON.stringify(Object.assign({type:'excalidraw',version:2,source:location.origin},JSON.parse(content()))),filename()+'.excalidraw'));
    if(draft.type==='mindmap') {
      item(t('png'),async()=>download(await mind.exportPng(),filename()+'.png','image/png'));
      item(t('svg'),()=>download(mind.exportSvg(),filename()+'.svg','image/svg+xml'));
    }
    if(draft.type==='spreadsheet') item(t('csv'),()=> {
      const workbook=JSON.parse(content()); const active=sheet && sheet.getActiveSheet && sheet.getActiveSheet();
      const id=active && active.getSheetId ? active.getSheetId() : workbook.sheetOrder[0];
      const cells=workbook.sheets[id].cellData||{};
      const rowKeys=Object.keys(cells).map(Number); const maxRow=Math.max(-1,...rowKeys);
      let maxCol=-1; rowKeys.forEach(r=>{maxCol=Math.max(maxCol,...Object.keys(cells[r]).map(Number));});
      if((maxRow+1)*(maxCol+1)>1000000)throw new Error(t('native_hint'));
      const rows=[];for(let r=0;r<=maxRow;r++){const row=[];for(let c=0;c<=maxCol;c++){
        const cell=(cells[r]||{})[c]||{}; let v=cell.v == null ? '' : String(cell.v);
        // Prevent spreadsheet formula injection in exported text cells.
        if(typeof cell.v==='string' && /^[=+@\-\t\r]/.test(v))v="'"+v;
        row.push('"'+v.replace(/"/g,'""')+'"');
      }rows.push(row.join(','));}download('\uFEFF'+rows.join('\r\n'),filename()+'.csv','text/csv;charset=utf-8');
    });
  }
  function loadAssets(loader) { return new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(new Error(t('load_error'))),25000);loader(()=>{clearTimeout(timeout);resolve();});}); }
  function waitUntil(check) { return new Promise((resolve,reject)=>{let count=0;const poll=setInterval(()=>{if(check()){clearInterval(poll);resolve();}else if(++count>250){clearInterval(poll);reject(new Error(t('load_error')));}},100);}); }
  async function mount() {
    document.body.classList.add('has-local-editor');
    el('toolsWelcome').hidden=true; el('toolsEditor').hidden=false; el('toolsLoading').hidden=false;
    el('toolsTitle').hidden=false; el('toolsTitle').value=draft.title;
    const host=el('toolsEditor');
    try {
      switch(draft.type) {
        case 'markdown': {
          host.innerHTML='<div id="localMarkdown"></div>';
          const instance=E.initCherry('localMarkdown',draft.content,changed);
          adapter={get:()=>instance.getMarkdown(),instance};break;
        }
        case 'richdoc': {
          host.innerHTML='<div id="localRichdoc"></div>';
          const instance=await BookStarkRichDoc.mount('localRichdoc',draft.content,{onChange:changed,localFile:window.BookStarkLocalFile});
          adapter={get:()=>instance.getContent(),instance};break;
        }
        case 'spreadsheet': {
          host.innerHTML='<div id="univer-sheet"></div>';
          await loadAssets(E.loadUniverAssets);sheet=E.initUniver('univer-sheet',draft.content||null,{});
          await waitUntil(()=>el('univer-sheet').style.visibility !== 'hidden' && el('univer-sheet').querySelector('canvas'));
          adapter={get:E.getSpreadsheetContent};break;
        }
        case 'mindmap': {
          host.innerHTML='<div id="mindmap-el"></div>';
          await loadAssets(E.loadMindElixirAssets);mind=E.initMindElixir(draft.content,{});
          mind.bus.addListener('operation',changed);adapter={get:E.getMindElixirData};break;
        }
        case 'drawing': {
          host.innerHTML='<div id="excalidraw-canvas"></div>';
          await loadAssets(E.loadExcalidrawAssets);E.initExcalidraw('excalidraw-canvas',draft.content||'{}',changed);
          await waitUntil(()=>document.querySelector('#excalidraw-canvas canvas'));
          adapter={get:E.getDrawingContent};break;
        }
        case 'presentation': {
          host.innerHTML='<div id="pptist-editor"></div>';
          await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(new Error(t('load_error'))),25000);BookStarkPPTist.mount('pptist-editor',draft.content||BookStarkPPTist.defaultContent(draft.title),{title:draft.title,onChange:changed,localFile:window.BookStarkLocalFile,loadingText:t('loading'),onReady:()=>{clearTimeout(timeout);resolve();}});});
          adapter={get:()=>BookStarkPPTist.getContent()};break;
        }
      }
      lastContent=content()||''; lastTitle=draft.title; ready=true;
      el('toolsLoading').hidden=true; el('toolsExport').hidden=false; exportMenu(); state(revision?'saved':'initial');
      // Poll adapters without change hooks (spreadsheet), and catch programmatic edits.
      setInterval(()=>{if(!ready || failed)return; if(draft.type==='spreadsheet' && !E.isSpreadsheetDirty() && !dirty)return; const before=lastContent;if(capture()===null)return;if(dirty && (lastContent!==before || !saving)){state('saving');flush();}},1000);
    } catch(e) { el('toolsLoading').textContent=t('load_error'); error(e); }
  }
  function validImported(obj) {
    if (!obj || obj.schema!=='bookstark-local-draft' || obj.version!==1 || !store.types.includes(obj.type) || typeof obj.content!=='string' || typeof obj.title!=='string')return false;
    if(obj.type==='markdown')return true;
    try { const data=JSON.parse(obj.content);
      if(!data || typeof data!=='object')return false;
      if(obj.type==='mindmap')return !!data.nodeData;
      if(obj.type==='spreadsheet')return !!data.sheets && Array.isArray(data.sheetOrder);
      if(obj.type==='presentation')return Array.isArray(data.slides) && data.slides.length>0;
      if(obj.type==='richdoc')return data.schema==='bookstark-richdoc' && !!data.data;
      return Array.isArray(data) || Array.isArray(data.elements);
    }catch(_){return false;}
  }
  el('toolsTitle').addEventListener('input',changed);
  el('toolsRetry').onclick=()=>{failed=false;flush();};
  el('toolsCopy').onclick=async()=>{if(saving)await saving;draft.id=uuid();revision=0;failed=false;dirty=true;await flush();await refreshList();};
  el('toolsDrawer').onclick=()=>drawer(!el('toolsSidebar').classList.contains('is-open'));
  el('toolsBackdrop').onclick=()=>drawer(false);
  el('toolsNew').onclick=()=>leave('/tools');
  el('toolsImport').onclick=()=>el('toolsImportFile').click();
  el('toolsImportFile').onchange=async event=>{
    const file=event.target.files[0];if(!file)return;
    try{
      if(file.size>30*1024*1024)throw new Error(t('invalid'));
      const obj=JSON.parse(await file.text());if(!validImported(obj))throw new Error(t('invalid'));
      if(!(await flush()))return;
      const imported={id:uuid(),title:obj.title.slice(0,120)||t('untitled'),type:obj.type,content:obj.content};
      await store.save(imported,0);dirty=false;ready=false;location.href='/tools?draft='+encodeURIComponent(imported.id);
    }catch(e){BSDialog.toast(t('invalid'),'error');}finally{event.target.value='';}
  };
  document.querySelector('.local-tools-brand').onclick=e=>{e.preventDefault();leave('/shares');};
  window.addEventListener('local-drafts-changed',refreshList);window.addEventListener('focus',refreshList);
  document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();flush();}if(e.key==='Escape'){el('toolsExport').open=false;drawer(false);}});
  document.addEventListener('visibilitychange',()=>{if(document.hidden)flush();});
  if (window.BookStarkNativeGuards) BookStarkNativeGuards.add(flush);
  window.addEventListener('bookstark:background', () => { flush(); });
  window.addEventListener('beforeunload',e=>{if(window.BookStarkHost?.isLeaving)return;capture();if(dirty||saving){flush();e.preventDefault();e.returnValue='';}});
  async function init() {
    const params=new URLSearchParams(location.search),id=params.get('draft'),type=params.get('type');
    try {
      if(id){draft=await store.get(id);if(!draft){el('toolsWelcome').querySelector('h2').textContent=t('missing');return;}revision=draft.revision;}
      else if(store.types.includes(type)){draft={id:uuid(),type,title:t('untitled')+' · '+t(type),content:''};}
      if(draft)await mount();
    }catch(e){state('unavailable');}
    await refreshList();
  }
  init();
})();
