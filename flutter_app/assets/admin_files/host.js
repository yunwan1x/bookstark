/* Existing BookStark CodeMirror, isolated text only; never execute the document. */
(() => {
 'use strict';
 const bridge=window.BookStarkFileMessages;
 if(!bridge || !window.CMHtml) return;
 const MAX=2*1024*1024;
 let lease=null,generation=-1,view=null,retired=false,raw='',initial='',bom='',enabled=false;
 const encoder=new TextEncoder();
 const normalize=text=>text.replace(/\r\n|\r/g,'\n');
 function valid(text) {
  if(typeof text!=='string' || text.includes('\0') || encoder.encode(text).length>MAX) return false;
  for(let i=0;i<text.length;i++) {
   const n=text.charCodeAt(i);
   if(n>=0xd800 && n<=0xdbff) {
    const next=text.charCodeAt(++i);
    if(!(next>=0xdc00 && next<=0xdfff)) return false;
   } else if(n>=0xdc00 && n<=0xdfff) return false;
  }
  return true;
 }
 function send(type,extra={}) {
  if(!retired) bridge.postMessage(JSON.stringify({type,lease,generation,...extra}));
 }
 function rawOffset(text,position) {
  let rawIndex=0,canonicalIndex=0;
  while(canonicalIndex<position && rawIndex<text.length) {
   if(text[rawIndex]==='\r' && text[rawIndex+1]==='\n') rawIndex+=2;
   else rawIndex++;
   canonicalIndex++;
  }
  if(canonicalIndex!==position) throw Error('offset');
  return rawIndex;
 }
 function newline(text) {
  const breaks=text.match(/\r\n|\r|\n/g)||[];
  const count=new Map();
  for(const br of breaks) count.set(br,(count.get(br)||0)+1);
  return [...count].sort((a,b)=>b[1]-a[1])[0]?.[0]||'\n';
 }
 let ending='\n';
 const {EditorView,EditorState,keymap,defaultKeymap,history,historyKeymap,
   lineNumbers,drawSelection,highlightSpecialChars,Compartment}=window.CMHtml;
 const editMode=new Compartment();
 function candidate(transaction,before) {
  const edits=[];
  transaction.changes.iterChanges((from,to,_fromB,_toB,inserted)=>{
   edits.push([rawOffset(before,from),rawOffset(before,to),inserted.toString().replace(/\n/g,ending)]);
  });
  let next=before;
  for(let i=edits.length-1;i>=0;i--) {
   const [from,to,inserted]=edits[i];
   next=next.slice(0,from)+inserted+next.slice(to);
  }
  if(transaction.newDoc.toString()===normalize(initial)) next=initial;
  return next;
 }
 function apply(update) {
  if(retired || !update.docChanged) return;
  try {
   let next=raw;
   for(const transaction of update.transactions) {
    if(transaction.docChanged) next=candidate(transaction,next);
   }
   if(normalize(next)!==update.state.doc.toString() || !valid(bom+next)) throw Error('bounds');
   raw=next;
   send('changed',{dirty:raw!==initial,bytes:encoder.encode(bom+raw).length});
  } catch(_) { retire(); }
 }
 function retire() {
  if(retired) return;
  send('failed');
  retired=true;enabled=false;
  view?.destroy();view=null;raw='';initial='';bom='';lease=null;
  document.querySelector('#editor').replaceChildren();
 }
 // Browser clipboard/drag/navigation never bypass the Flutter confirmation path.
 for(const type of ['paste','copy','cut','drop','dragover']) {
  document.addEventListener(type,event=>event.preventDefault(),true);
 }
 document.addEventListener('click',event=>{
  if(event.target.closest?.('a')) event.preventDefault();
 },true);
 window.addEventListener('pagehide',retire);
 bridge.onmessage=event=>{
  if(retired) return;
  try {
   const message=JSON.parse(event.data);
   if(message.type==='configure') {
    if(lease!==null || !/^[a-f0-9]{64}$/.test(message.lease) ||
       !Number.isSafeInteger(message.generation) || message.generation<0 ||
       !valid(message.content)) throw Error('configure');
    lease=message.lease;generation=message.generation;
    // Keep the UTF-8 signature outside contenteditable. Android DOM
    // reconciliation may omit a leading replacement decoration during IME.
    bom=message.content.startsWith('\ufeff')?'\ufeff':'';
    raw=initial=message.content.slice(bom.length);
    ending=newline(initial);enabled=message.enabled!==false;
    document.documentElement.lang=message.english?'en':'zh';
    const state=EditorState.create({doc:normalize(raw),extensions:[
     lineNumbers(),drawSelection(),highlightSpecialChars(),history(),
     keymap.of([...defaultKeymap,...historyKeymap]),
     editMode.of([EditorView.editable.of(enabled),EditorState.readOnly.of(!enabled)]),
     EditorView.contentAttributes.of({role:'textbox','aria-label':message.english?'Remote file source':'远程文件源代码',
      spellcheck:'false',autocapitalize:'off',autocomplete:'off',autocorrect:'off'}),
     EditorState.transactionFilter.of(transaction=>{
      if(!transaction.docChanged) return transaction;
      try {
       if(normalize(raw)!==transaction.startState.doc.toString() || !valid(bom+candidate(transaction,raw))) {
        send('limit');return [];
       }
       return transaction;
      } catch(_) {send('limit');return [];}
     }),
     EditorView.updateListener.of(apply),
    ]});
    view=new EditorView({state,parent:document.querySelector('#editor')});
    // Capture the physical/native Enter before CodeMirror's Android delayed
    // DOM fallback. Preventing the DOM edit avoids reconciling two newlines.
    view.contentDOM.addEventListener('keydown',event=>{
     if(!enabled || event.isComposing || event.key!=='Enter' ||
        event.ctrlKey || event.altKey || event.metaKey) return;
     event.preventDefault();event.stopImmediatePropagation();
     view.observer.clearDelayedAndroidKey();
     view.observer.forceFlush();
     view.dispatch(view.state.replaceSelection('\n'),{
      scrollIntoView:true,userEvent:'input.type'});
    },true);

    send('ready');return;
   }
   if(message.lease!==lease || message.generation!==generation) return;
   switch(message.type) {
    case 'snapshot':
     if(typeof message.id!=='string' || message.id.length>64 || !view) return;
     {
      const id=message.id,current=view,currentLease=lease;
      // Native IME DOM changes and Android's delayed key may still be queued.
      // Drain the pinned CodeMirror observer before taking an exact snapshot.
      requestAnimationFrame(()=>requestAnimationFrame(()=>{
       if(retired || view!==current || lease!==currentLease) return;
       try {
        if(typeof current.observer?.forceFlush!=='function') throw Error('observer');
        current.observer.clearDelayedAndroidKey();
        current.observer.forceFlush();
        if(normalize(raw)!==current.state.doc.toString() || !valid(bom+raw)) throw Error('snapshot');
        send('snapshot',{id,content:bom+raw,dirty:raw!==initial});
       } catch(_) {retire();}
      }));
     }
     break;
    case 'enabled':
     enabled=message.value===true;
     view.dispatch({effects:editMode.reconfigure([EditorView.editable.of(enabled),EditorState.readOnly.of(!enabled)])});break;
    case 'focus':
     if(enabled) {view.focus();send('focused');}break;
    case 'insert':
     if(enabled && valid(message.content)) {
      view.dispatch(view.state.replaceSelection(normalize(message.content)));
     }break;
    case 'retire':retire();break;
   }
  } catch(_) {retire();}
 };
 bridge.postMessage(JSON.stringify({type:'boot'}));
})();
