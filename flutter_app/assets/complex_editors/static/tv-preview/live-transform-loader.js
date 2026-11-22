/* Fragment preprocessing only; network requests remain normal browser requests. */
(() => {
'use strict';
const modes=Object.freeze({'ysp-tea':1,h5e:2});
function supported(name){return Object.hasOwn(modes,name)&&typeof globalThis.SuperliveTsTransform?.transform==='function';}
function createFragmentLoader(name,Hls){if(!supported(name))throw Error('Unsupported live stream preprocessing');const Base=Hls.DefaultConfig.loader;
 return class LiveFragmentLoader extends Base {
  constructor(config){super(config);this.transformStopped=false;}
  load(context,config,callbacks){this.transformStopped=false;const original=callbacks.onSuccess;const wrapped={...callbacks,onSuccess:(response,stats,ctx,details)=>{
   if(this.transformStopped)return;
   try{const data=response.data;if(!(data instanceof ArrayBuffer))throw Error('Expected complete TS fragment');
    // Bound allocation and processing to a normal live fragment size.
    if(data.byteLength>32*1024*1024)throw Error('Live fragment exceeds processing limit');
    const start=performance.now(),out=globalThis.SuperliveTsTransform.transform(data,modes[name],{normalizeAvc:true});
    const duration=performance.now()-start;globalThis.SuperliveTransforms.last={mode:name,bytes:data.byteLength,ms:duration};
    if(!this.transformStopped)original({...response,data:out.buffer.slice(out.byteOffset,out.byteOffset+out.byteLength)},stats,ctx,details);
   }catch(error){if(!this.transformStopped)callbacks.onError({code:0,text:'直播码流预处理失败：'+error.message},ctx,details,stats);}
  }};super.load(context,config,wrapped);}
  abort(){this.transformStopped=true;super.abort();}
  destroy(){this.transformStopped=true;super.destroy();}
 };
}
globalThis.SuperliveTransforms={supported,createFragmentLoader,last:null};
})();
