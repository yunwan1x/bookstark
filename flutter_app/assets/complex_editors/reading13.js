/* Reading-only commands. No content/save/network/file/account capability. */
(function () {
 'use strict';
 const enc=new TextEncoder(), hash=/^[a-f0-9]{64}$/;
 const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 const integer=(v,max=1000000000)=>Number.isInteger(v)&&v>=0&&v<=max;
 function plain(s) {
  if(typeof s!=='string'||enc.encode(s).length>32768)throw Error('reading_text_limit');
  for(let i=0;i<s.length;i++){const n=s.charCodeAt(i);if(n>=0xd800&&n<=0xdbff){const l=s.charCodeAt(++i);if(!(l>=0xdc00&&l<=0xdfff))throw Error('reading_unicode');}else if(n>=0xdc00&&n<=0xdfff)throw Error('reading_unicode');}
  return s;
 }
 function childBridge(nonce) {
  const path=n=>{const p=[];for(;n&&n!==document;n=n.parentNode){if(p.length>=64)throw Error('depth');p.unshift(Array.prototype.indexOf.call(n.parentNode.childNodes,n));}return p;};
  const node=p=>{if(!Array.isArray(p)||p.length>64)throw Error('path');let n=document;for(const i of p){if(!Number.isInteger(i)||i<0||i>100000||!n.childNodes[i])throw Error('path');n=n.childNodes[i];}return n;};
  addEventListener('message',e=>{
   const m=e.data;if(e.source!==parent||!m||m.channel!=='bookstark-reading13'||m.nonce!==nonce||typeof m.id!=='string'||m.id.length>128)return;
   try {
    let value;
    if(m.action==='capture'){
     const s=m.includeSelection?getSelection():null,text=s?s.toString():'';
     if(new TextEncoder().encode(text).length>32768)throw Error('text');
     const focus=document.elementFromPoint(Math.max(1,innerWidth/2),Math.min(8,Math.max(1,innerHeight/2)));
     const scrolls=[];for(let n=focus;n&&n!==document;n=n.parentNode){
      if(n.nodeType===1&&(n.scrollHeight>n.clientHeight||n.scrollWidth>n.clientWidth)){
       if(scrolls.length>=32)throw Error('scrolls');
       scrolls.push({path:path(n),top:Math.round(n.scrollTop),left:Math.round(n.scrollLeft)});
      }
     }
     const scrolling=document.scrollingElement;
     if(scrolling&&!scrolls.some(v=>JSON.stringify(v.path)===JSON.stringify(path(scrolling))))
      scrolls.push({path:path(scrolling),top:Math.round(scrolling.scrollTop),left:Math.round(scrolling.scrollLeft)});
     let selection=null;
     if(text && s && s.rangeCount===1){
      const r=s.getRangeAt(0);
      selection={type:'htmlDomRange',startPath:path(r.startContainer),startOffset:r.startOffset,
       endPath:path(r.endContainer),endOffset:r.endOffset};
     }
     value={text,anchor:{type:'htmlDomScroll',scrolls},selection};
    }else if(m.action==='restore'){
     const a=m.anchor;if(!a||a.type!=='htmlDomScroll'||!Array.isArray(a.scrolls)||a.scrolls.length>32)throw Error('anchor');
     const jobs=a.scrolls.map(v=>{if(!v||!Number.isInteger(v.top)||!Number.isInteger(v.left)||v.top<0||v.left<0||v.top>1e9||v.left>1e9)throw Error('offset');const n=node(v.path);if(n.nodeType!==1)throw Error('node');return[n,v];});
     for(const [n,v]of jobs){n.scrollTop=v.top;n.scrollLeft=v.left;}
     value={restored:true};
    }else return;
    parent.postMessage({channel:'bookstark-reading13',nonce,id:m.id,ok:true,value},'*');
   }catch(_){parent.postMessage({channel:'bookstark-reading13',nonce,id:m.id,ok:false},'*');}
  });
 }
 window.BookStarkReading13=Object.freeze({create(ctx){
  let binding=null,serial=0,dead=false,frame=null,nonce='',pending=new Map();
  function guard(b){const s=ctx.state();if(dead||!binding||!s.ready||!s.readOnly||s.inputLocked||s.generation!==binding.generation||!same(binding,b))throw Error('reading_owner');return s;}
  function frameMessage(e){const m=e.data;if(dead||!frame||e.source!==frame.contentWindow||!m||m.channel!=='bookstark-reading13'||m.nonce!==nonce)return;const job=pending.get(m.id);if(!job)return;pending.delete(m.id);clearTimeout(job.timer);m.ok?job.resolve(m.value):job.reject(Error('reading_frame'));}
  addEventListener('message',frameMessage);
  function rpc(action,anchor,includeSelection=true){return new Promise((resolve,reject)=>{
   if(!frame||!frame.contentWindow)return reject(Error('reading_frame_unavailable'));
   const id=String(++serial),timer=setTimeout(()=>{pending.delete(id);reject(Error('reading_timeout'));},3000);
   pending.set(id,{resolve,reject,timer});frame.contentWindow.postMessage({channel:'bookstark-reading13',nonce,id,action,anchor,includeSelection},'*');
  });}
  function sheet(){const w=ctx.instance();if(!w||typeof w.getActiveSheet!=='function')throw Error('reading_unsupported');const s=w.getActiveSheet();if(!s)throw Error('reading_unsupported');return[w,s];}
  function rangeData(r){if(!r)return null;const v=r.getRange();if(!v||!['startRow','endRow','startColumn','endColumn'].every(k=>integer(v[k],1048575))||v.endRow<v.startRow||v.endColumn<v.startColumn)throw Error('reading_range');return{startRow:v.startRow,endRow:v.endRow,startColumn:v.startColumn,endColumn:v.endColumn};}
  return Object.freeze({
   htmlScript(f){frame=f;nonce=Array.from(crypto.getRandomValues(new Uint8Array(16)),v=>v.toString(16).padStart(2,'0')).join('');return '<script>('+childBridge.toString()+')('+JSON.stringify(nonce)+');<\/script>';},
   async bindPublic(b){
    const s=ctx.state(),keys=['version','resource','identityDigest','kind','sourceDigest','runtimeLease','generation'];
    if(dead||!s.ready||!s.readOnly||s.inputLocked||!b||Object.keys(b).length!==keys.length||
       Object.keys(b).some(k=>!keys.includes(k))||b.version!==1||b.resource!=='public-share'||
       b.kind!==s.kind||!hash.test(b.identityDigest)||!hash.test(b.sourceDigest)||
       typeof b.runtimeLease!=='string'||b.runtimeLease.length<16||b.runtimeLease.length>128||
       b.generation!==s.generation)throw Error('public_reading_binding');
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(ctx.original()))),v=>v.toString(16).padStart(2,'0')).join('');
    if(dead||!ctx.state().readOnly||ctx.state().generation!==s.generation||digest!==b.sourceDigest)
      throw Error('public_reading_source_changed');
    binding=JSON.parse(JSON.stringify(b));return{binding};
   },
   async bind(b){
    const s=ctx.state();if(dead||!s.ready||!s.readOnly||!b||b.version!==1||!integer(b.bookId,Number.MAX_SAFE_INTEGER)||b.bookId<1||!integer(b.documentId,Number.MAX_SAFE_INTEGER)||b.documentId<1||b.kind!==s.kind||!hash.test(b.fullFingerprint)||!hash.test(b.sourceDigest)||typeof b.runtimeLease!=='string'||b.runtimeLease.length<16||b.runtimeLease.length>128||b.generation!==s.generation)throw Error('reading_binding');
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(ctx.original()))),v=>v.toString(16).padStart(2,'0')).join('');
    if(dead||ctx.state().generation!==s.generation||digest!==b.sourceDigest)throw Error('reading_source_changed');
    binding=JSON.parse(JSON.stringify(b));return{binding};
   },
   async capture(b,includeSelection=true){
    if(typeof includeSelection!=='boolean')throw Error('reading_selection_mode');
    guard(b);const kind=b.kind;let text='',anchor=null,supported=true,selectionKind='text',selection=null;
    if(kind==='html'){const v=await rpc('capture',null,includeSelection);text=plain(v.text);anchor=v.anchor;selection=v.selection;}
    else if(kind==='richdoc'){
     const e=ctx.instance(),n=ctx.root.querySelector('#richdoc-host .richdoc-canvas');
     if(!e||typeof e.getSelectionText!=='function'||!n)throw Error('reading_unsupported');
     text=includeSelection?plain(e.getSelectionText()):'';
     if(text){
      if(typeof e.command!=='function')throw Error('reading_range_unsupported');
      const r=e.command('getRange');
      if(!r||!Number.isInteger(r.startIndex)||!Number.isInteger(r.endIndex)||r.startIndex<0||r.endIndex<=r.startIndex||r.startIndex>1000000||r.endIndex>1000000||
        !['main','header','footer'].includes(r.zone))throw Error('reading_range_unsupported');
      selection={type:'canvasRange',startIndex:r.startIndex,endIndex:r.endIndex,zone:r.zone};
      for(const key of ['tableId','startTdIndex','endTdIndex','startTrIndex','endTrIndex','isCrossRowCol'])
       if(r[key]!==null&&r[key]!==undefined)selection[key]=r[key];
     }
     anchor={type:'richdocViewport',top:Math.round(n.scrollTop),left:Math.round(n.scrollLeft)};
    }else if(kind==='spreadsheet'){
     selectionKind='cells';
     const [w,s]=sheet(),range=w.getActiveRange&&w.getActiveRange(),r=rangeData(range);
     if(r&&includeSelection){
      const area=(r.endRow-r.startRow+1)*(r.endColumn-r.startColumn+1);
      if(area>4096)throw Error('reading_selection_limit');
      const values=range.getValues();
      selection={type:'sheetRange',sheetId:s.getSheetId(),...r};
      text=plain(values.map(row=>row.map(v=>{
       if(v===null||v===undefined)return '';if(!['string','number','boolean'].includes(typeof v)||typeof v==='number'&&!Number.isFinite(v))throw Error('reading_cell_type');return String(v);
      }).join('\t')).join('\n'));
     }
     if(typeof s.getScrollState!=='function'||typeof w.save!=='function')throw Error('reading_unsupported');
     const v=s.getScrollState(),id=s.getSheetId(),snapshot=w.save(),freeze=snapshot.sheets[id].freeze||{};
     const row=v.sheetViewStartRow+(freeze.ySplit||0),column=v.sheetViewStartColumn+(freeze.xSplit||0);
     if(typeof id!=='string'||id.length>256||!integer(row,1048575)||!integer(column,16383))throw Error('reading_viewport');
     anchor={type:'sheetViewportCell',sheetId:id,row,column,range:r};
    }else if(kind==='drawing'){
     selectionKind='elements';const adapter=window.BookStarkExcalidraw;
     if(!adapter||typeof adapter.captureReading13!=='function')throw Error('reading_unsupported');
     const value=adapter.captureReading13(includeSelection);text=plain(value.text);anchor=value.anchor;
     if(text&&anchor.elementIds.length)selection={type:'drawingElements',ids:[...anchor.elementIds].sort()};
    }else if(kind==='mindmap'){
     selectionKind='nodes';
     const mind=ctx.instance(),nodes=!includeSelection?[]:mind&&(mind.currentNodes&&mind.currentNodes.length?mind.currentNodes:mind.currentNode?[mind.currentNode]:[]);
     if(!mind||!mind.map||!nodes||nodes.length>128||typeof DOMMatrixReadOnly!=='function')throw Error('reading_unsupported');
     const ids=nodes.map(n=>{const id=n&&n.nodeObj&&n.nodeObj.id;if(typeof id!=='string'||id.length>256||!n.isConnected)throw Error('reading_node');return id;});
     text=plain(nodes.map(n=>n.textContent||'').join('\n'));
     if(text&&ids.length)selection={type:'mindmapNodes',ids};
     const matrix=new DOMMatrixReadOnly(getComputedStyle(mind.map).transform),scale=mind.scaleVal;
     if(!Number.isFinite(scale)||scale<.1||scale>30||![matrix.m41,matrix.m42].every(n=>Number.isFinite(n)&&Math.abs(n)<=1e9))throw Error('reading_viewport');
     anchor={type:'mindmapViewport',x:matrix.m41,y:matrix.m42,scale,nodeIds:ids};
    }else if(kind==='presentation'){
     selectionKind='slide';const adapter=window.BookStarkPPTist;
     if(!adapter||typeof adapter.captureReading13!=='function')throw Error('reading_unsupported');
     const v=adapter.captureReading13(includeSelection);text=plain(v.text);anchor=v.anchor;
     if(text)selection={type:'presentationSlide',slideId:anchor.slideId};
    }else{supported=false;selectionKind='none';}
    guard(b);const result={binding,text,anchor,supported,selectionKind,selection};if(enc.encode(JSON.stringify(result)).length>65536)throw Error('reading_result_limit');return result;
   },
   async restore(b,a){
    guard(b);if(!a||typeof a!=='object')throw Error('reading_anchor');
    if(b.kind==='html'){await rpc('restore',a);}
    else if(b.kind==='richdoc'&&a.type==='richdocViewport'&&integer(a.top)&&integer(a.left)){
     const n=ctx.root.querySelector('#richdoc-host .richdoc-canvas');if(!n)throw Error('reading_unsupported');n.scrollTop=a.top;n.scrollLeft=a.left;
    }else if(b.kind==='spreadsheet'&&a.type==='sheetViewportCell'&&typeof a.sheetId==='string'&&a.sheetId.length<=256&&integer(a.row,1048575)&&integer(a.column,16383)){
     const [w]=sheet(),s=w.getSheetBySheetId(a.sheetId);if(!s||typeof s.scrollToCell!=='function')throw Error('reading_sheet_missing');
     w.setActiveSheet(s);s.scrollToCell(a.row,a.column,0);
    }else if(b.kind==='drawing'&&a.type==='drawingViewport'){
     const adapter=window.BookStarkExcalidraw;
     if(!adapter||typeof adapter.restoreReading13!=='function'||adapter.restoreReading13(a)!==true)throw Error('reading_unsupported');
    }else if(b.kind==='mindmap'&&a.type==='mindmapViewport'){
     const mind=ctx.instance();
     if(!mind||!mind.map||![a.x,a.y].every(n=>typeof n==='number'&&Number.isFinite(n)&&Math.abs(n)<=1e9)||
       typeof a.scale!=='number'||!Number.isFinite(a.scale)||a.scale<.1||a.scale>30||
       !Array.isArray(a.nodeIds)||a.nodeIds.length>128)throw Error('reading_anchor');
     const nodes=Array.from(mind.container.querySelectorAll('me-tpc'));
     if(nodes.length>10000)throw Error('reading_node_limit');
     const selected=a.nodeIds.map(id=>{if(typeof id!=='string'||id.length>256)throw Error('reading_node');const n=nodes.find(n=>n.nodeObj&&n.nodeObj.id===id);if(!n)throw Error('reading_node_missing');return n;});
     if(selected.length&&typeof mind.selectNodes==='function')mind.selectNodes(selected);
     else if(selected.length===1&&typeof mind.selectNode==='function')mind.selectNode(selected[0]);
     else if(selected.length)throw Error('reading_unsupported');
     mind.scaleVal=a.scale;mind.map.style.transform='translate3d('+a.x+'px, '+a.y+'px, 0) scale('+a.scale+')';
    }else if(b.kind==='presentation'&&a.type==='presentationSlide'){
     const adapter=window.BookStarkPPTist;
     if(!adapter||typeof adapter.restoreReading13!=='function'||adapter.restoreReading13(a)!==true)throw Error('reading_unsupported');
    }else throw Error('reading_unsupported');
    guard(b);return{binding,restored:true};
   },
   retire(){dead=true;binding=null;removeEventListener('message',frameMessage);for(const job of pending.values()){clearTimeout(job.timer);job.reject(Error('reading_retired'));}pending.clear();frame=null;}
  });
 }});
})();
