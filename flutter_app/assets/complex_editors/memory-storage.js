/* Session-only Web Storage for trusted packaged editors and their PPT frame.
   Content recovery belongs to Flutter's typed controller, never web persistence. */
(function(){
 'use strict';
 if(window.__BookStarkMemoryOnly===true)return;
 let inputLocked=false;
 let selectionOnly=false;
 const gate=Object.freeze({get locked(){return inputLocked;},setLocked(value,allowSelection){if(typeof value!=='boolean'||allowSelection!==undefined&&typeof allowSelection!=='boolean')throw Error('invalid_input_gate');inputLocked=value;selectionOnly=value&&allowSelection===true;}});
 Object.defineProperty(window,'__BookStarkEditorInputGate',{value:gate,writable:false,configurable:false});
 const selectionKeys=new Set(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End','PageUp','PageDown']);
 function allowedSelectionEvent(event){
  if(!selectionOnly)return false;
  if(['pointerdown','pointerup','mousedown','mouseup','touchstart','touchend','wheel'].includes(event.type))return true;
  if(event.type==='keyup'||event.type==='keypress')return true;
  if(event.type!=='keydown')return false;
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='c')return true;
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='a')return true;
  return selectionKeys.has(event.key);
 }
 for(const name of ['keydown','keyup','keypress','beforeinput','input','compositionstart','compositionupdate','compositionend','paste','cut','drop','dragstart','pointerdown','pointerup','mousedown','mouseup','touchstart','touchend','wheel']){
  window.addEventListener(name,event=>{if(inputLocked&&!allowedSelectionEvent(event)){if(event.cancelable)event.preventDefault();event.stopImmediatePropagation();}},{capture:true,passive:false});
 }

 function storage(){
  const values=new Map();
  const methods={getItem:key=>values.has(String(key))?values.get(String(key)):null,setItem:(key,value)=>{values.set(String(key),String(value));},removeItem:key=>{values.delete(String(key));},clear:()=>values.clear(),key:index=>[...values.keys()][Number(index)]??null};
  return new Proxy(Object.create(null),{
   get:(_,key)=>key==='length'?values.size:key===Symbol.toStringTag?'Storage':Object.prototype.hasOwnProperty.call(methods,key)?methods[key]:values.get(String(key)),
   set:(_,key,value)=>{values.set(String(key),String(value));return true;},
   deleteProperty:(_,key)=>{values.delete(String(key));return true;},
   ownKeys:()=>[...values.keys()],
   getOwnPropertyDescriptor:(_,key)=>values.has(String(key))?{value:values.get(String(key)),enumerable:true,writable:true,configurable:true}:undefined,
  });
 }
 try{
  for(const key of ['localStorage','sessionStorage']){const value=storage();Object.defineProperty(window,key,{get:()=>value,configurable:false,enumerable:true});}
  Object.defineProperty(window,'indexedDB',{value:undefined,writable:true,configurable:true});
  Object.defineProperty(window,'webkitIndexedDB',{value:undefined,writable:true,configurable:true});
  Object.defineProperty(window,'__BookStarkMemoryOnly',{value:true,writable:false,configurable:false});
 }catch(_){throw Error('editor_memory_storage_unavailable');}
})();
