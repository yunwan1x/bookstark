/* Ordinary-local drawing resources. This adapter has no network/account,
 * storage, filesystem or editor-save API. Native serves exact opaque IDs. */
(function(global) {
  'use strict';
  const hash = /^[a-f0-9]{64}$/;
  const own = (value,key) => Object.prototype.hasOwnProperty.call(value,key);
  const object = value => value !== null && typeof value === 'object' &&
      !Array.isArray(value);
  const clone = value => JSON.parse(JSON.stringify(value));
  function images(elements) {
    if (!Array.isArray(elements) || elements.length > 50000)
      throw Error('local_drawing_elements');
    const ids=new Set();
    for (const el of elements) {
      if (!object(el) || el.type !== 'image' || el.isDeleted === true) continue;
      if (typeof el.fileId !== 'string' || !el.fileId || el.fileId.length>256)
        throw Error('local_drawing_file_id');
      ids.add(el.fileId);
      if(ids.size>32)throw Error('local_drawing_resource_bound');
    }
    return ids;
  }
  function create(options) {
    if (!options || typeof options.source!=='string' ||
        typeof options.scope!=='string' || !hash.test(options.scope) ||
        !object(options.resources) ||
        typeof options.isCurrent!=='function' ||
        typeof options.onFailure!=='function' ||
        global.location.protocol!=='https:')
      throw Error('local_drawing_binding');
    const original=JSON.parse(options.source);
    const legacy=Array.isArray(original);
    if (!legacy && (!object(original) || !Array.isArray(original.elements)))
      throw Error('local_drawing_source');
    const originalElements=legacy?original:original.elements;
    const originalFiles=legacy?{}:original.files||{};
    if (!object(originalFiles))throw Error('local_drawing_files');
    const activeIds=images(originalElements);
    const base=new URL('/local-drawing/'+options.scope+'/',global.location.origin).href;
    const canonicalByURL=new Map(), resourceIDs=new Set(), cancels=new Set();
    let closed=false,failed=false,firstElements=null;
    function alive() {
      try{return !closed&&options.isCurrent()===true;}catch(_){return false;}
    }
    function guard() {if(!alive())throw Error('local_drawing_retired');}
    function fail() {
      if(!failed){failed=true;if(alive())options.onFailure();}
    }
    for(const [fileID,id] of Object.entries(options.resources)) {
      if(!activeIds.has(fileID)||typeof id!=='string'||!hash.test(id)||!object(originalFiles[fileID])||
          typeof originalFiles[fileID].dataURL!=='string')
        throw Error('local_drawing_resource_binding');
      resourceIDs.add(id);
      canonicalByURL.set(base+id,originalFiles[fileID].dataURL);
    }
    if(resourceIDs.size>32)throw Error('local_drawing_resource_bound');
    function prepareSource() {
      guard();
      const result=legacy?{elements:clone(original),appState:{},files:{}}:clone(original);
      const safe=Object.create(null);
      for(const id of activeIds) {
        if(!own(options.resources,id)){fail();continue;}
        const item=originalFiles[id];
        safe[id]=clone(item);
        safe[id].dataURL=base+options.resources[id];
      }
      // Unused file strings are not resource authority and must not reach y3.
      result.files=safe;
      return JSON.stringify(result);
    }
    function canonicalSource(sdkSource) {
      guard();
      const value=JSON.parse(sdkSource);
      if(!object(value)||!Array.isArray(value.elements)||
          (value.files!=null&&!object(value.files)))
        throw Error('local_drawing_sdk_snapshot');
      const files=value.files||{};
      const used=images(value.elements);
      // Canonicalize unused SDK files too: a deleted image may remain in its
      // cache. Ephemeral runtime URLs must never enter a draft or SQL.
      for(const [id,item] of Object.entries(files)) {
        if(!object(item))continue;
        const canonical=canonicalByURL.get(item.dataURL);
        if(canonical!==undefined)item.dataURL=canonical;
        else if(typeof item.dataURL==='string'&&item.dataURL.startsWith(base)) {
          fail();throw Error('local_drawing_unknown_runtime_resource');
        } else if(used.has(id))fail();
      }
      for(const id of used) {
        const item=files[id];
        if(!object(item)) {
          fail();
          if(!object(originalFiles[id]))
            throw Error('local_drawing_image_source_unavailable');
          // Legacy SDK y3 may drop a failed file. Preserve its full descriptor
          // for the draft/export; the Flutter owner disables Save on failure.
          Object.defineProperty(files,id,{value:clone(originalFiles[id]),
              enumerable:true,writable:true,configurable:true});
          continue;
        }
        // All SDK virtual URLs were canonicalized above. Only exact original
        // or explicitly approved source values may represent an active file.
        if(![...canonicalByURL.values()].includes(item.dataURL))fail();
      }
      value.files=files;
      if(firstElements===null)firstElements=JSON.stringify(value.elements);
      if(legacy) {
        if(Object.keys(files).length===0)return JSON.stringify(value.elements);
        if(typeof global.BookStarkMergeEditorSnapshot!=='function')
          throw Error('local_drawing_preservation_unavailable');
        // Explicit actual SDK image insertion upgrades the legacy array to the
        // SDK's real files envelope, retaining unknown original element data.
        value.elements=JSON.parse(global.BookStarkMergeEditorSnapshot(
          'drawing',options.source,firstElements,JSON.stringify(value.elements)));
      }
      return JSON.stringify(value);
    }
    function approveSelection(id,uri) {
      guard();
      if(failed||typeof id!=='string'||!hash.test(id)||typeof uri!=='string'||uri.length>2048)
        throw Error('local_drawing_selection');
      const parsed=new URL(uri),parts=parsed.pathname.replace(/^\/+/, '/').split('/').slice(1).map(decodeURIComponent);
      if(parsed.protocol!=='bookstark-attachment:'||parsed.host||parsed.username||
          parsed.password||parsed.port||parsed.search||parsed.hash||
          parts.length!==2||!(/^[a-f0-9]{32}$/).test(parts[0])||
          !parts[1]||parts[1].length>255||parts[1]==='.'||parts[1]==='..'||
          /[\\/\x00-\x1f\x7f]/.test(parts[1]))
        throw Error('local_drawing_selection_uri');
      if(!resourceIDs.has(id)&&resourceIDs.size>=32)
        throw Error('local_drawing_resource_bound');
      const url=base+id,old=canonicalByURL.get(url);
      if(old!==undefined&&old!==uri)throw Error('local_drawing_identity_changed');
      resourceIDs.add(id);canonicalByURL.set(url,uri);
      return url;
    }
    function waitReady() {
      guard();
      const sdk=global.BookStarkExcalidraw;
      if(!sdk||typeof sdk.ownedInitializationState!=='function')
        return Promise.reject(Error('local_drawing_initialization_ack_missing'));
      const generation=sdk.ownedInitializationState().generation;
      return new Promise((resolve,reject)=>{
        const deadline=performance.now()+30000;
        let timer=null;
        const finish=(error,value)=>{
          if(timer!==null)clearInterval(timer);
          cancels.delete(cancel);
          error?reject(error):resolve(value);
        };
        const cancel=()=>finish(Error('local_drawing_retired'));
        cancels.add(cancel);
        const poll=()=>{
          try {
            guard();
            const value=sdk.ownedInitializationState();
            if(value.generation!==generation||value.failed===true)
              throw Error('local_drawing_initialization_changed');
            if(value.ready===true&&value.sourceLoaded===true&&value.loading===false)
              return finish(null,{generation,resourcesComplete:!failed});
            if(performance.now()>=deadline)
              throw Error('local_drawing_initialization_timeout');
          } catch(error){finish(error);}
        };
        timer=setInterval(poll,20);poll();
      });
    }
    function retire() {
      if(closed)return;closed=true;
      for(const cancel of [...cancels])cancel();
      canonicalByURL.clear();resourceIDs.clear();
    }
    return Object.freeze({prepareSource,canonicalSource,approveSelection,waitReady,
      retire,get complete(){return !failed;},get failed(){return failed;}});
  }
  global.BookStarkLocalDrawing=Object.freeze({create});
})(typeof window==='undefined'?globalThis:window);
