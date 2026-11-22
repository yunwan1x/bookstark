// Actual engine adapter functions, mocked SDK ports only. Not Native evidence.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=process.argv[2],url='https://owned.test/prefix/upload-files/a.png';
function read(p){return fs.readFileSync(root+'/'+p,'utf8');}
(async()=>{
 let checks=0;
 const drawing=read('static/js/excalidraw/excalidraw-percentages-BXMCSKIN.js');
 const code=drawing.slice(drawing.indexOf('function bookstarkOwnedImageSelection()'),drawing.indexOf('window.BookStarkExcalidraw = {'));
 assert(code.includes('er.addFiles')&&code.includes('_bookstarkConvertSkeleton'));
 function drawingRig(){
  let live=true;const calls=[],state={scrollX:10,scrollY:20,width:1000,height:600,zoom:{value:2},selectedElementIds:{selected:true}};
  const ctx={bookstarkReadingOnly13:false,er:{getAppState:()=>state,addFiles:v=>calls.push(['files',v])},gi:{},
   fetch:async(v,opts)=>{assert.equal(v,url);assert.equal(opts.credentials,'omit');assert.equal(opts.redirect,'error');
    return {ok:true,headers:{get:()=> 'image/png'},arrayBuffer:async()=>new Uint8Array([1]).buffer};},
   _bookstarkConvertSkeleton:v=>{calls.push(['convert',v]);return v;},
   _bookstarkApplyElements:(v,opts)=>calls.push(['apply',v,opts]),
   crypto:{getRandomValues:v=>v.fill(9)},Uint32Array,Array,Number,JSON,Error,Math,Date};
  vm.createContext(ctx);vm.runInContext(code,ctx);
  return {ctx,calls,state,guard:()=>live,retire:()=>{live=false;}};
 }
 {
  const h=drawingRig(),selection=h.ctx.bookstarkOwnedImageSelection();
  await h.ctx.bookstarkOwnedInsertImage(url,1440,960,selection,h.guard);
  assert.deepEqual(h.calls.map(v=>v[0]),['convert','files','apply']);
  assert.equal(h.calls[0][1][0].x,-10+1000/4-360);
  assert.equal(h.calls[1][1][0].dataURL,url);
  assert.equal(h.calls[1][1][0].mimeType,'image/png');
  assert.equal(Object.values(h.ctx.gi)[0],url);
  assert.equal(h.calls[2][2].append,true);checks++;
 }
 for(const mode of ['retired','selection','readonly']){
  const h=drawingRig(),selection=h.ctx.bookstarkOwnedImageSelection();
  if(mode==='retired')h.retire();
  if(mode==='selection')h.state.selectedElementIds.other=true;
  if(mode==='readonly')h.ctx.bookstarkReadingOnly13=true;
  await assert.rejects(h.ctx.bookstarkOwnedInsertImage(url,10,10,selection,h.guard));
  assert.equal(h.calls.length,0);checks++;
 }
 {
  const h=drawingRig(),selection=h.ctx.bookstarkOwnedImageSelection();
  h.ctx.fetch=async()=>{h.retire();return {ok:true,headers:{get:()=> 'image/png'},arrayBuffer:async()=>new Uint8Array([1]).buffer};};
  await assert.rejects(h.ctx.bookstarkOwnedInsertImage(url,1,1,selection,h.guard));
  assert.equal(h.calls.length,0);checks++;
 }
 const bundle=read('static/pptist/assets/index-DeKNemMI.js');
 const start=bundle.indexOf('window.BookStarkPPTistBridge={getPresentation:m,');
 const end=bundle.indexOf(',f||(window.onbeforeunload',start);
 assert(start>=0&&end>start);
 const bridgeCode=bundle.slice(start,end);
 function pptRig(){
  let live=true;const calls=[],r={slides:[{id:'slide-a'},{id:'slide-b'}],slideIndex:0,
   get currentSlide(){return this.slides[this.slideIndex];},updateSlideIndex(i){this.slideIndex=i;}};
  const ctx={window:{},r,n:{activeElementIdList:['selected']},m:()=>({slides:r.slides}),
   ownedReadOnly:false,d:true,h:false,JSON,Error,Promise,
   P0:()=>({createImageElement:async(v,guard)=>{assert.equal(v,url);if(!guard())throw Error('stale');calls.push(v);}})};
  vm.createContext(ctx);vm.runInContext(bridgeCode,ctx);
  return {ctx,r,calls,bridge:ctx.window.BookStarkPPTistBridge,guard:()=>live,retire:()=>{live=false;}};
 }
 {
  const h=pptRig(),selection=h.bridge.ownedImageSelection();
  await h.bridge.insertOwnedImage(url,selection,h.guard);assert.equal(h.calls.length,1);
  assert.equal(h.bridge.getReadingState().slideId,'slide-a');checks++;
 }
 for(const mode of ['retired','slide','selection','readonly']){
  const h=pptRig(),selection=h.bridge.ownedImageSelection();
  if(mode==='retired')h.retire();if(mode==='slide')h.r.slideIndex=1;
  if(mode==='selection')h.ctx.n.activeElementIdList.push('changed');
  if(mode==='readonly')h.ctx.ownedReadOnly=true;
  await assert.rejects(h.bridge.insertOwnedImage(url,selection,h.guard));
  assert.equal(h.calls.length,0);checks++;
 }
 {
  const h=pptRig();assert.equal(h.bridge.restoreReadingSlide('slide-b'),false);
  h.ctx.ownedReadOnly=true;
  assert.equal(h.bridge.restoreReadingSlide('missing'),false);
  assert.equal(h.bridge.restoreReadingSlide('slide-b'),true);
  assert.equal(h.bridge.getReadingState().slideId,'slide-b');checks++;
 }
 // The actual private image factory must invoke the passed guard after async decode.
 const factoryStart=bundle.indexOf('createImageElement:(m,ownedGuard)=>');
 const factoryEnd=bundle.indexOf(',createChartElement:',factoryStart);
 assert(factoryStart>=0&&factoryEnd>factoryStart);
 const factoryCode='({'+bundle.slice(factoryStart,factoryEnd)+'})';
 {
  let insertions=0,live=true,resolve;const image=new Promise(r=>resolve=r);
  const ctx={b3e:()=>image,a:{value:.5},o:{value:1000},s:()=>insertions++,Pn:()=> 'new-id',Error};
  vm.createContext(ctx);const factory=vm.runInContext(factoryCode,ctx);
  const pending=factory.createImageElement(url,()=>live);live=false;
  resolve({width:640,height:480});await assert.rejects(pending,/selection_changed/);
  assert.equal(insertions,0);checks++;
 }
 console.log(JSON.stringify({status:'PASS',checks,scope:'actual extracted adapter/functions with mock SDK ports only; no Native proof'}));
})().catch(e=>{console.error(e);process.exitCode=1;});
