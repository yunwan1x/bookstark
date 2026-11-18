/* Extend direct/public provincial sources with the official CCTV public API. */
(() => {
'use strict';
const previous=globalThis.SuperliveResolvers;
function h5eUrl(url){try{const u=new URL(url);return u.protocol==='https:'&&/\/(?:ld[^/]*cctvwbcd|[^/]*cdrmld)[^/]*\//i.test(u.pathname)||u.protocol==='https:'&&/\/cdrmld[^/]*\//i.test(u.pathname)}catch{return false}}
globalThis.SuperliveResolvers=Object.freeze({
 canResolve:source=>!!globalThis.SuperliveCctv?.canResolve(source)||previous.canResolve(source),
 async resolve(source,options={}){
  if(globalThis.SuperliveCctv?.canResolve(source))return globalThis.SuperliveCctv.resolve(source,options);
  const resolved=await previous.resolve(source,options);
  return h5eUrl(resolved.url)?{...resolved,transform:'h5e'}:resolved;
 }
});
})();
