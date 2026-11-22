/* Ordinary local PPT images: typed source paths, opaque runtime IDs, canonical snapshots.
 * Uses the existing PPTist engine and its initialized acknowledgement. */
(function(global) {
  'use strict';
  const hash=/^[a-f0-9]{64}$/, clone=v=>JSON.parse(JSON.stringify(v));
  const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
  function slots(value) {
    if(!object(value)||!Array.isArray(value.slides)||value.slides.length>5000)
      throw Error('local_presentation_source');
    const result=new Map();let count=0;
    value.slides.forEach((slide,si)=>{
      if(!object(slide)||!Array.isArray(slide.elements))
        throw Error('local_presentation_slide');
      count+=slide.elements.length;
      if(count>50000)throw Error('local_presentation_element_bound');
      slide.elements.forEach((element,ei)=>{
        if(object(element)&&element.type==='image')
          result.set('slides/'+si+'/elements/'+ei+'/src',[element,'src',slide.id,element.id]);
      });
      const b=slide.background;
      if(object(b)&&b.type==='image') {
        if(!object(b.image))throw Error('local_presentation_background');
        result.set('slides/'+si+'/background/image/src',[b.image,'src',slide.id,'background']);
      }
    });
    return result;
  }
  function create(options) {
    if(!options||typeof options.source!=='string'||!hash.test(options.scope)||
        !object(options.resources)||typeof options.isCurrent!=='function'||
        typeof options.onFailure!=='function'||global.location.protocol!=='https:')
      throw Error('local_presentation_binding');
    const original=JSON.parse(options.source), originals=slots(original);
    const base=new URL('/local-presentation/'+options.scope+'/',global.location.origin).href;
    const canonicalByURL=new Map(), resourceIDs=new Set();
    let closed=false,failed=false;
    function alive(){try{return !closed&&options.isCurrent()===true;}catch(_){return false;}}
    function guard(){if(!alive())throw Error('local_presentation_retired');}
    function fail(){if(!failed){failed=true;if(alive())options.onFailure();}}
    for(const [key,id] of Object.entries(options.resources)) {
      const slot=originals.get(key);
      if(!slot||typeof slot[0][slot[1]]!=='string'||!hash.test(id))
        throw Error('local_presentation_resource_binding');
      const canonical=slot[0][slot[1]],old=canonicalByURL.get(base+id);
      if(old!==undefined&&old!==canonical)throw Error('local_presentation_identity_changed');
      resourceIDs.add(id);canonicalByURL.set(base+id,canonical);
    }
    if(resourceIDs.size>32)throw Error('local_presentation_resource_bound');
    function prepareSource() {
      guard();const value=clone(original);
      for(const [key,[node,field]] of slots(value)) {
        const id=options.resources[key];
        if(typeof id!=='string'){fail();delete node[field];}
        else node[field]=base+id;
      }
      return JSON.stringify(value);
    }
    function canonicalSource(source) {
      guard();const value=JSON.parse(source);
      for(const [key,[node,field,slideId,elementId]] of slots(value)) {
        const raw=node[field],canonical=canonicalByURL.get(raw);
        if(canonical!==undefined)node[field]=canonical;
        else if(typeof raw==='string'&&raw.startsWith(base)) {
          fail();throw Error('local_presentation_unknown_runtime_resource');
        } else if(![...canonicalByURL.values()].includes(raw)) {
          fail();
          // An unavailable initial raster keeps its exact source for recovery.
          // No blank presentation or default slide may replace the document.
          const old=originals.get(key);
          if(raw===undefined&&old&&old[2]===slideId&&old[3]===elementId)
            node[field]=old[0][old[1]];
        }
      }
      return JSON.stringify(value);
    }
    function approveSelection(id,uri) {
      guard();
      if(failed||!hash.test(id)||typeof uri!=='string'||uri.length>2048)
        throw Error('local_presentation_selection');
      const parsed=new URL(uri),parts=parsed.pathname.replace(/^\/+/, '/').split('/').slice(1).map(decodeURIComponent);
      if(parsed.protocol!=='bookstark-attachment:'||parsed.host||parsed.username||
          parsed.password||parsed.port||parsed.search||parsed.hash||
          parts.length!==2||!(/^[a-f0-9]{32}$/).test(parts[0])||
          !parts[1]||parts[1].length>255||parts[1]==='.'||parts[1]==='..'||
          /[\\/\x00-\x1f\x7f]/.test(parts[1]))
        throw Error('local_presentation_selection_uri');
      if(!resourceIDs.has(id)&&resourceIDs.size>=32)throw Error('local_presentation_resource_bound');
      const url=base+id,old=canonicalByURL.get(url);
      if(old!==undefined&&old!==uri)throw Error('local_presentation_identity_changed');
      resourceIDs.add(id);canonicalByURL.set(url,uri);return url;
    }
    function retire(){closed=true;canonicalByURL.clear();resourceIDs.clear();}
    return Object.freeze({prepareSource,canonicalSource,approveSelection,retire,
      get failed(){return failed;},get complete(){return !failed;}});
  }
  global.BookStarkLocalPresentation=Object.freeze({create});
})(typeof window==='undefined'?globalThis:window);
