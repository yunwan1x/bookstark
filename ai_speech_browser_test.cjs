// Deterministic control/network tests in Chromium; real MP3 decode smoke when supplied.
const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--autoplay-policy=no-user-gesture-required']});
 try{
 for(const [lang,width] of [['zh',1440],['en',390],['zh',320]]){
 const page=await browser.newPage({viewport:{width,height:900}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('http://speech.test/**',r=>r.fulfill({body:'<!doctype html><html lang="'+lang+'"><body><article id="a"><p>你好，欢迎使用。</p></article><article id="b">Second answer</article></body></html>',contentType:'text/html'}));
 await page.goto('http://speech.test/');await page.addStyleTag({path:'static/css/ai-speech.css'});
 await page.evaluate(()=>{
 window.test={requests:[],aborted:0,played:0,revoked:0,mode:'ok',audios:[]};
 const original=URL.revokeObjectURL;URL.revokeObjectURL=function(u){test.revoked++;original.call(URL,u)};
 window.Audio=function(){const a={src:'',playbackRate:1,removeAttribute(k){this[k]=''}};test.audios.push(a);a.play=()=>{if(a.src.startsWith('blob:'))test.played++;return Promise.resolve()};a.pause=()=>{};a.load=()=>{};return a};
 window.csrfFetch=async(u,o)=>{
 test.requests.push(JSON.parse(o.body));o.signal.addEventListener('abort',()=>test.aborted++);
 const stream=new ReadableStream({start(c){
 if(test.mode==='hold'){o.signal.addEventListener('abort',()=>c.error(new DOMException('Aborted','AbortError')));return}
 const frame={event:'audio',data:btoa('mock audio')};c.enqueue(new TextEncoder().encode(JSON.stringify(frame)+'\n'+(test.mode==='truncated'?'':JSON.stringify({event:'done',bytes:10})+'\n')));c.close();
 }});return new Response(stream,{headers:{'Content-Type':'application/x-ndjson'}})
 };
 });
 await page.addScriptTag({path:'static/js/ai-speech.js'});
 await page.evaluate(()=>{
 if(AISpeech.clean('# 标题\n你好 **世界**。\n```js\nsecret()\n```\n[说明](https://a.test)\n<script>alert(1)</script>').includes('secret'))throw Error('code spoken');
 if(AISpeech.clean('{"x":1}'))throw Error('JSON spoken');
 if(AISpeech.split('好'.repeat(601)).some(s=>Array.from(s).length>200))throw Error('segment limit');
 AISpeech.mount(document.querySelector('#a'),'你好。'.repeat(210));AISpeech.mount(document.querySelector('#b'),'Second answer');
 });
 assert.equal(await page.locator('.ai-speech-controls').count(),2);assert.equal(await page.evaluate(()=>test.requests.length),0);
 const play=page.locator('#a .ai-speech-controls button').first();await play.click();await page.waitForFunction(()=>test.played===1&&test.requests.length===2);
 assert.match(await play.getAttribute('aria-label'),lang==='en'?/Pause/:/暂停/);await play.click();assert.match(await play.getAttribute('aria-label'),lang==='en'?/Resume/:/继续/);
 await play.click();await page.locator('#a select').last().selectOption('1.5');assert.equal(await page.evaluate(()=>test.audios[0].playbackRate),1.5);
 await page.locator('#b button').first().click();await page.waitForFunction(()=>test.aborted>=2);assert.equal(await page.locator('#a.ai-speech-active').count(),0);
 await page.evaluate(()=>document.querySelector('#b').remove());await page.waitForFunction(()=>!document.querySelector('.ai-speech-active'));
 await page.evaluate(()=>{test.mode='hold';test.requests=[]});await play.click();await page.waitForFunction(()=>test.requests.length===1);await page.locator('#a button').nth(1).click();await page.waitForFunction(()=>!document.querySelector('.ai-speech-active'));
 await page.evaluate(()=>{test.mode='truncated';test.played=0});await play.click();await page.waitForFunction(()=>document.querySelector('#a .ai-speech-progress').textContent.includes('失败')||document.querySelector('#a .ai-speech-progress').textContent.includes('failed'));
 assert.equal(await page.evaluate(()=>test.played),0);
 await page.evaluate(()=>{test.mode='ok'});await play.click();await page.waitForFunction(()=>test.played===1);await page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));assert.equal(await page.locator('.ai-speech-active').count(),0);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.deepEqual(errors,[]);await page.close();console.log('PASS speech lifecycle',lang,width);
 }
 // Real assistant scripts: a partial or failed answer must never get a read button.
 {
 const page=await browser.newPage();await page.route('http://speech.test/**',r=>r.fulfill({body:'<!doctype html><html><body></body></html>',contentType:'text/html'}));await page.goto('http://speech.test/');
 await page.addScriptTag({path:'static/js/ai-speech.js'});await page.addScriptTag({path:'static/js/ai-helper.js'});await page.addScriptTag({path:'static/js/ai-reading-assistant.js'});
 await page.evaluate(()=>{window.originalComplete=AIHelper.complete;AIHelper.complete=o=>{window.generation=o;return {abort(){}}};AIComposeDialog.open({title:'Test'});});
 await page.locator('.ai-dlg-prompt').fill('Summarize');await page.locator('.ai-dlg-btn-go').click();
 await page.evaluate(()=>generation.onChunk('partial','partial'));assert.equal(await page.locator('.ai-speech-controls').count(),0);
 await page.evaluate(()=>generation.onDone('Completed answer'));assert.equal(await page.locator('.ai-speech-controls').count(),1);
 await page.locator('.ai-dlg-btn-go').click();assert.equal(await page.locator('.ai-speech-controls').count(),0);
 await page.evaluate(()=>generation.onError('failed'));assert.equal(await page.locator('.ai-speech-controls').count(),0);await page.locator('.ai-dlg-close').click();
 await page.evaluate(()=>{window.AI_ENABLED=true;window.reading=AIReadingAssistant.create({title:'Reading'});reading.open()});
 await page.locator('.preview-ai-input').fill('Explain');await page.locator('.preview-ai-send').click();
 await page.evaluate(()=>generation.onChunk('partial','partial'));assert.equal(await page.locator('.ai-speech-controls').count(),0);
 await page.evaluate(()=>generation.onDone('Completed reading answer'));assert.equal(await page.locator('.from-ai .ai-speech-controls').count(),1);assert.equal(await page.locator('.from-user .ai-speech-controls').count(),0);
 await page.evaluate(()=>reading.close());assert.equal(await page.locator('.ai-speech-controls').count(),0);
 await page.evaluate(async()=>{window.fetchWithCurrentCSRF=async()=>new Response('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n');await new Promise((resolve,reject)=>{originalComplete({onDone:()=>reject(Error('truncated answer completed')),onError:()=>resolve()})})});await page.close();console.log('PASS compose and reading assistants: completed answers only');
 }
 if(process.env.TTS_MP3){
 const page=await browser.newPage();await page.goto('about:blank');await page.evaluate(async data=>{const audio=new Audio('data:audio/mpeg;base64,'+data);await new Promise((resolve,reject)=>{audio.onloadedmetadata=resolve;audio.onerror=()=>reject(Error('MP3 decode failed'));audio.load()});if(!(audio.duration>0))throw Error('empty duration')},fs.readFileSync(process.env.TTS_MP3).toString('base64'));await page.close();console.log('PASS real Yunxi MP3 browser decode');
 }
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
