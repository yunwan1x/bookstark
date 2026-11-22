'use strict';
// node tool/check_drawing_initial_image_dependency.cjs [flutter_app_root]
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const root=process.argv[2]?path.resolve(process.argv[2]):path.resolve(__dirname,'..');
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const host=read('assets/complex_editors/host.js'),utils=read('assets/complex_editors/static/js/utils.js');
function extract(source,start,end){const i=source.indexOf(start);assert(i>=0,'Dependency source anchor missing');const j=source.indexOf(end,i+start.length);assert(j>i,'Dependency source end missing');return source.slice(i,j);}
const pure=extract(utils,'function computeDataURLHash(dataURL) {','\n}\n')+'\n}';
const helper=extract(host,'function computeDataURLHash(dataURL) {','\n}\n')+'\n}';
assert.equal(helper,pure,'Host helper must exactly retain existing pure utility implementation');
assert(host.indexOf(helper)<host.indexOf('(function () {'),'Global helper must precede host IIFE');
const vendor=read('assets/complex_editors/static/js/excalidraw/excalidraw-percentages-BXMCSKIN.js');
const chain=extract(vendor,'function Wh(e) {','\nfunction eF(')+
 extract(vendor,'function nF(e) {','\nfunction aF(')+extract(vendor,'function y3(e) {','\nfunction w3(');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=','base64');
assert(png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])));
const originalURL='https://local.invalid/local-drawing/'+'a'.repeat(64)+'/'+'b'.repeat(64);
(async()=>{
 let tests=0;
 for(const installed of [false,true]){
  const warnings=[];let requests=0;
  class Reader{readAsDataURL(blob){blob.arrayBuffer().then(buffer=>{this.result='data:'+blob.type+';base64,'+Buffer.from(buffer).toString('base64');this.onload();},error=>this.onerror(error));}}
  const c=vm.createContext({Blob,Uint8Array,FileReader:Reader,atob,crypto:crypto.webcrypto,window:{crypto:crypto.webcrypto},gi:{},Zr:{},
   console:{warn:(label,url,error)=>warnings.push(error&&error.name)},
   fetch:async url=>{assert.equal(url,originalURL);requests++;return{blob:async()=>new Blob([png],{type:'image/png'})};}});
  if(installed)vm.runInContext(helper,c);vm.runInContext(chain,c);
  c.input={elements:[{type:'image',fileId:'image-file'}],files:{'image-file':{id:'image-file',mimeType:'image/png',dataURL:originalURL}}};
  await vm.runInContext('y3(input)',c);
  assert.equal(requests,1);assert.equal(c.gi['image-file'],originalURL);
  if(installed){
   assert.equal(Object.keys(c.input.files).length,1);assert.equal(warnings.length,0);
   const hash=await vm.runInContext("computeDataURLHash(input.files['image-file'].dataURL)",c);
   assert.equal(hash,crypto.createHash('sha256').update(png).digest('hex'));
  }else{assert.equal(Object.keys(c.input.files).length,0);assert.deepEqual(warnings,['ReferenceError']);}
  tests++;
 }
 console.log(JSON.stringify({passed:true,cases:tests,actualVendorColdChain:true,missingDependencyDeletesFile:true,
  installedDependencyRetainsFile:true,originalURIMappingPreserved:true,PNGHashMatches:true,networkRequests:0}));
})().catch(()=>{console.error('drawing_initial_dependency_regression_failed');process.exit(1)});
