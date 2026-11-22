/* Apply only the web engine's changes to the original JSON. Its initial
   normalization must not erase unknown source fields or change untouched data. */
(function(global){
 'use strict';
 const missing=Symbol('missing');
 const map=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&value!==missing;
 const own=(value,key)=>Object.prototype.hasOwnProperty.call(value,key);
 function equal(a,b){
  if(a===b)return true;
  if(Array.isArray(a)&&Array.isArray(b))return a.length===b.length&&a.every((v,i)=>equal(v,b[i]));
  if(map(a)&&map(b)){const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(k=>own(b,k)&&equal(a[k],b[k]));}
  return false;
 }
 function extras(original,baseline){
  if(map(original)){if(!map(baseline))return true;return Object.keys(original).some(k=>!own(baseline,k)||extras(original[k],baseline[k]));}
  if(Array.isArray(original)){if(!Array.isArray(baseline)||original.length!==baseline.length)return true;return original.some((v,i)=>extras(v,baseline[i]));}
  return false;
 }
 function keyed(array){return array.length>0&&array.every(v=>map(v)&&typeof v.id==='string')&&new Set(array.map(v=>v.id)).size===array.length;}
 function delta(original,baseline,edited){
  if(equal(baseline,edited))return original;
  if(map(baseline)&&map(edited)){
   if(!map(original))return edited;
   const result=Object.create(null);for(const key of Object.keys(original))result[key]=original[key];
   for(const key of new Set([...Object.keys(baseline),...Object.keys(edited)])){
    if(!own(edited,key)){delete result[key];continue;}
    if(!own(baseline,key)){result[key]=edited[key];continue;}
    const next=delta(own(original,key)?original[key]:missing,baseline[key],edited[key]);
    if(next===missing)delete result[key];else result[key]=next;
   }
   return result;
  }
  if(Array.isArray(baseline)&&Array.isArray(edited)&&Array.isArray(original)){
   if(keyed(baseline)&&keyed(edited)){
    const before=new Map(baseline.map(v=>[v.id,v]));let originals;
    if(keyed(original)){
     originals=new Map(original.map(v=>[v.id,v]));
     // Normalized keyed IDs cannot be aligned by position: the engine may
     // reorder entries. Refuse rather than erase source IDs/unknown fields.
     if(original.length!==baseline.length||baseline.some(v=>!originals.has(v.id)))throw Error('ambiguous_array_preservation');
    }
    else if(original.length===baseline.length)originals=new Map(baseline.map((v,i)=>[v.id,original[i]]));
    else if(!extras(original,baseline))return edited;
    else throw Error('ambiguous_array_preservation');
    return edited.map(v=>before.has(v.id)?delta(originals.has(v.id)?originals.get(v.id):missing,before.get(v.id),v):v);
   }
   if(original.length===baseline.length&&baseline.length===edited.length)return edited.map((v,i)=>delta(original[i],baseline[i],v));
   if(!extras(original,baseline))return edited;
   // Reuse exact unchanged entries. A changed anonymous item with hidden source
   // attributes is ambiguous: preserve the original by refusing the save.
   const used=new Set();return edited.map(value=>{
    const index=baseline.findIndex((item,i)=>!used.has(i)&&equal(item,value));
    if(index>=0&&index<original.length){used.add(index);return original[index];}
    throw Error('ambiguous_array_preservation');
   });
  }
  return edited;
 }
 function merge(kind,source,baselineSource,editedSource){
  if(kind==='html'||kind==='markdown'){
   // CodeMirror exports its document with LF. Preserve a uniform original
   // newline convention when editing, while untouched exports use the exact
   // original source in host.getSource(). Mixed conventions keep engine output.
   const breaks=source.match(/\r\n|\r|\n/g);
   if(breaks&&breaks.length&&breaks.every(value=>value===breaks[0])&&breaks[0]!=='\n'){
    return editedSource.replace(/\r\n|\r|\n/g,breaks[0]);
   }
   return editedSource;
  }
  const original=JSON.parse(source),baseline=JSON.parse(baselineSource),edited=JSON.parse(editedSource);
  const result=delta(original,baseline,edited);
  if(kind==='spreadsheet'){
   if(!map(result)||result.id!==original.id)throw Error('workbook_identity_changed');
   // Formula caches legitimately update on an explicit edit/save even when the
   // first engine render had already recalculated its intentionally old cache.
   for(const [id,sheet] of Object.entries(edited.sheets||{}))for(const [rowKey,row] of Object.entries(sheet.cellData||{}))for(const [colKey,cell] of Object.entries(row||{})){
    if(!map(cell)||!(cell.f||cell.si))continue;
    const target=result.sheets&&result.sheets[id]&&result.sheets[id].cellData&&result.sheets[id].cellData[rowKey]&&result.sheets[id].cellData[rowKey][colKey];
    if(!map(target))continue;
    for(const key of ['v','t']){if(own(cell,key))target[key]=cell[key];else delete target[key];}
   }
  }
  return JSON.stringify(result);
 }
 global.BookStarkMergeEditorSnapshot=merge;
 if(typeof module==='object'&&module.exports)module.exports={merge,equal};
})(typeof window==='undefined'?globalThis:window);
