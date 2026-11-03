const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try{
 const page=await browser.newPage(); const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('about:blank');
 await page.setContent('<article id="answer"><p>流式朗读测试</p></article>');
 await page.evaluate(()=>{
 window.test={appended:0,ended:0,requests:0,played:0};
 class Source extends EventTarget {
  static isTypeSupported(type){return type==='audio/mpeg'}
  constructor(){super();this.readyState='closed';window.source=this}
  addSourceBuffer(){const b=new EventTarget();b.updating=false;b.appendBuffer=part=>{test.appended+=part.length;b.updating=true;queueMicrotask(()=>{b.updating=false;b.dispatchEvent(new Event('updateend'))})};return b}
  endOfStream(){this.readyState='ended';test.ended++;test.audio.onended()}
 }
 window.MediaSource=Source;
 URL.createObjectURL=()=> 'blob:stream';URL.revokeObjectURL=()=>{};
 window.Audio=function(){const a=test.audio={src:'',pause(){},load(){},removeAttribute(k){this[k]=''},play(){if(this.src==='blob:stream'){test.played++;queueMicrotask(()=>{source.readyState='open';source.dispatchEvent(new Event('sourceopen'))})}return Promise.resolve()}};return a};
 window.csrfFetch=async()=>{test.requests++;return new Response(new ReadableStream({start(c){test.send=msg=>c.enqueue(new TextEncoder().encode(JSON.stringify(msg)+'\n'));test.close=()=>c.close();test.send({event:'audio',data:btoa('first audio')})}}),{headers:{'Content-Type':'application/x-ndjson'}})};
 });
 await page.addScriptTag({path:'static/js/ai-speech.js'});
 await page.evaluate(()=>AISpeech.mount(document.querySelector('#answer'),'流式朗读测试。'));
 const play=page.locator('button').first();await play.click();
 await page.waitForFunction(()=>test.appended===11);
 assert.equal(await page.evaluate(()=>test.ended),0,'audio appended before completion');
 assert.equal(await page.evaluate(()=>test.played),1);
 await play.click();assert.match(await play.getAttribute('aria-label'),/继续|Resume/);await play.click();
 await page.evaluate(()=>{test.send({event:'audio',data:btoa('second')});test.send({event:'done',bytes:17});test.close()});
 await page.waitForFunction(()=>test.ended===1&&!document.querySelector('.ai-speech-active'));
 assert.equal(await page.evaluate(()=>test.appended),17);
 // A failure after initial playback must stop and report the interrupted stream.
 await play.click();await page.waitForFunction(()=>test.requests===2&&test.appended===28);
 await page.evaluate(()=>{test.send({event:'error',message:'interrupted'});test.close()});
 await page.waitForFunction(()=>document.querySelector('.ai-speech-progress').textContent.includes('失败'));
 assert.equal(await page.locator('.ai-speech-active').count(),0);
 assert.deepEqual(errors,[]);console.log('PASS incremental audio before done, pause/resume, completion, upstream error');
 if (process.env.TTS_MP3) {
 const real=await browser.newPage();await real.goto('about:blank');await real.setContent('<article id="real">真实 MP3 流式播放</article>');
 await real.evaluate(data=>{
 const bytes=Uint8Array.from(atob(data),c=>c.charCodeAt(0));
 window.realTest={playing:false,done:false};
 const NativeAudio=window.Audio;window.Audio=function(){const audio=new NativeAudio();audio.addEventListener('playing',()=>{realTest.playing=true});return audio};
 window.csrfFetch=async()=>new Response(new ReadableStream({start(c){
 const send=msg=>c.enqueue(new TextEncoder().encode(JSON.stringify(msg)+'\n'));
 // Deliver sufficient MP3 data to start decoding, holding completion back.
 send({event:'audio',data:btoa(String.fromCharCode(...bytes))});
 realTest.finish=()=>{realTest.done=true;send({event:'done',bytes:bytes.length});c.close()};
 }}),{headers:{'Content-Type':'application/x-ndjson'}});
 },fs.readFileSync(process.env.TTS_MP3).toString('base64'));
 await real.addScriptTag({path:'static/js/ai-speech.js'});await real.evaluate(()=>AISpeech.mount(document.querySelector('#real'),'真实流式播放。'));
 await real.locator('button').first().click();await real.waitForFunction(()=>realTest.playing);
 assert.equal(await real.evaluate(()=>realTest.done),false,'real MP3 starts before done frame');
 await real.evaluate(()=>realTest.finish());await real.waitForFunction(()=>!document.querySelector('.ai-speech-active'));
 await real.close();console.log('PASS real MP3 decoding and playback before stream completion');
 }
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
