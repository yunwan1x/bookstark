// Real homepage HTML/CSS/JS, mocked network only. Never touches production data.
const {chromium} = require('playwright');
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

async function serviceWorkerChecks() {
  const handlers = {}, pending = [];
  let network = 0, deleted = 0, offline = false;
  const origin = 'https://assistant.test';
  const sandbox = {URL,Request,Response,Headers,console,
    location:{origin}, self:{addEventListener:(name,fn)=>{handlers[name]=fn;}},
    caches:{open:async()=>({keys:async()=>[new Request(origin+'/api/blogs')],delete:async()=>{deleted++;return true;}})},
    fetch:async()=>{network++;if(offline)throw new Error('offline');return new Response('{"code":0}',{headers:{'Content-Type':'application/json'}});}
  };
  vm.runInNewContext(fs.readFileSync('static/sw.js','utf8'),sandbox);
  let response;
  function event(path,method='GET') {return {request:new Request(origin+path,{method}),respondWith:p=>{response=p;},waitUntil:p=>{assert(p instanceof Promise);pending.push(p);}};}
  handlers.fetch(event('/api/ai/assistant')); assert.equal((await response).status,200);
  handlers.fetch(event('/api/ai/assistant/drafts/test','POST')); await response; await Promise.all(pending); assert.equal(deleted,1);
  offline=true;
  handlers.fetch(event('/api/ai/assistant')); await assert.rejects(response,/offline/);
  handlers.fetch(event('/api/ai/assistant/chat','POST')); await assert.rejects(response,/offline/);
  assert.equal(network,4);
  assert.equal(sandbox.isOfflineQueueableMutation(new URL(origin+'/api/ai/assistant/chat'),'POST'),false);
  console.log('PASS assistant service worker: network-only reads, no offline replay, cache invalidation');
}

(async()=>{
  await serviceWorkerChecks();
  const browser = await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
  try {
    for (const [lang,width] of [['zh',1440],['en',390],['zh',320]]) {
      const page=await browser.newPage({viewport:{width,height:900}}), errors=[];
      page.on('pageerror',e=>errors.push(e.message));
      let session={id:'session-1',messages:[],drafts:[],busy:false}, saves=0, chats=0, fail=false, homeLoads=0;
      await page.route('http://assistant.test/**',async route=>{
        const req=route.request(),url=new URL(req.url());
        if(url.pathname==='/api/home'){homeLoads++;return route.fulfill({json:{code:0,sections:[],layout:[]}});}
        if(url.pathname==='/api/ai/assistant')return route.fulfill({json:{code:0,session}});
        if(url.pathname==='/api/ai/assistant/chat'){
          chats++;assert.equal(req.postDataJSON().session_id,session.id);assert.equal(req.postDataJSON().message,'Draft a note');
          if(fail)return route.fulfill({status:502,json:{code:502,message:'AI unavailable'}});
          session.messages=[{role:'user',content:'Draft a note',created_at:1791791800},{role:'assistant',created_at:1791791810,content:'<img src=x onerror="window.xss=1"> Please review.',sources:[{title:'Source',url:'/notes?id=1'},{title:'Unsafe',url:'javascript:alert(1)'}]}];
          session.drafts=[{id:'draft-1',payload:{kind:'note',title:'My note',content:'<script>window.xss=1</script>\n# Learning'},status:'pending',url:''}];
          return route.fulfill({json:{code:0,session}});
        }
        if(url.pathname==='/api/ai/assistant/drafts/draft-1'){
          saves++;assert.equal(req.postDataJSON().action,'confirm');assert.equal(Object.keys(req.postDataJSON()).length,2);
          session.drafts[0].status='done';session.drafts[0].url='/notes?tab=notes&id=99';
          await new Promise(resolve=>setTimeout(resolve,80));
          return route.fulfill({json:{code:0,draft:session.drafts[0]}});
        }
        if(url.pathname==='/api/ai/assistant/reset'){session={id:'session-2',messages:[],drafts:[],busy:false};return route.fulfill({json:{code:0,session}});}
        if(url.pathname.startsWith('/static/'))return route.fulfill({path:'.'+url.pathname});
        const translations=Object.fromEntries([...fs.readFileSync('i18n/'+lang+'.go','utf8').matchAll(/"([\w.]+)":\s*"([^"]*)"/g)].map(m=>[m[1],m[2]]));
        let html=fs.readFileSync('templates/home.html','utf8').replace('{{template "assistant-widget" .}}',fs.readFileSync('templates/assistant.html','utf8')).replace(/\{\{call \.T "([^"]+)"\}\}/g,(_,k)=>translations[k]||k).replace(/\{\{[^}]*\}\}/g,'');
        html=html.replace('<head>','<head><script>window.csrfFetch=window.fetch; window.__currentLang="'+lang+'";document.documentElement.lang="'+lang+'";</script><link rel="stylesheet" href="/static/css/font-awesome.min.css"><link rel="stylesheet" href="/static/css/variables.css"><link rel="stylesheet" href="/static/css/components.css">');
        return route.fulfill({contentType:'text/html',body:html});
      });
      await page.goto('http://assistant.test/home');
      await page.locator('#homeAssistantOpen').click();
      await page.waitForFunction(()=>!document.querySelector('#homeAssistantSend').disabled);
      assert.equal(await page.locator('#homeAssistantRefresh').isVisible(),false);
      assert.equal(await page.locator('#homeAssistantDisclosure').isVisible(),false);
      await page.locator('#homeAssistantInfo').click();assert.equal(await page.locator('#homeAssistantDisclosure').isVisible(),true);
      await page.locator('#homeAssistantInfo').click();
      assert.equal(await page.locator('#homeAssistantForm #homeAssistantReset').count(),1);
      assert.equal(await page.locator('#homeAssistantTitle').innerText(),lang==='en'?'AI assistant':'AI 助手');
      await page.locator('#homeAssistantInput').fill('Draft a note');
      await page.locator('#homeAssistantSend').click();
      await page.waitForSelector('[data-draft-id="draft-1"]');assert.equal(saves,0);
      assert.equal(await page.locator('.home-assistant-avatar .fa-user').count(),1);
      assert.equal(await page.locator('.home-assistant-avatar .fa-robot').count(),1);
      assert.equal(await page.locator('.home-assistant-message-head time[datetime]').count(),2);
      await page.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copiedAssistantText=text;}}}));
      await page.locator('.home-assistant-copy').first().click();
      assert.equal(await page.evaluate(()=>window.copiedAssistantText),'Draft a note');
      await page.locator('.home-assistant-copy').nth(1).click();
      assert.equal(await page.evaluate(()=>window.copiedAssistantText),'<img src=x onerror="window.xss=1"> Please review.');
      assert.equal(await page.locator('#homeAssistantMessages img, #homeAssistantDrafts script').count(),0);
      assert.equal(await page.evaluate(()=>window.xss),undefined);
      assert.equal(await page.locator('.home-assistant-sources a').count(),1);
      assert.equal(await page.locator('.home-assistant-sources a').getAttribute('rel'),'noopener noreferrer');
      const bounds=await page.locator('#homeAssistant').boundingBox();assert(bounds.x>=-1&&bounds.x+bounds.width<=width+1);
      assert(Math.abs(bounds.width-(width>640?420:width))<2);
      assert.equal(await page.locator('#homeAssistant').evaluate(n=>n.matches(':modal')),width<=640);
      assert.equal(await page.locator('#homeAssistant').evaluate(n=>n.scrollWidth<=n.clientWidth+1),true);
      await page.locator('[data-draft-id="draft-1"] button').first().evaluate(b=>{b.click();b.click();});
      await page.waitForSelector('[data-draft-id="draft-1"] a');assert.equal(saves,1);assert(homeLoads>=2);
      assert.equal(await page.locator('[data-draft-id="draft-1"] a').getAttribute('target'),'_blank');
      if(width===390)await page.screenshot({path:'/tmp/bookstark-assistant-mobile.png'});
      if(width===1440)await page.screenshot({path:'/tmp/bookstark-assistant-desktop.png'});
      await page.locator('#homeAssistantClose').click();await page.locator('#homeAssistantOpen').click();
      await page.waitForSelector('[data-draft-id="draft-1"] a');assert.equal(saves,1);
      await page.waitForFunction(()=>!document.querySelector('#homeAssistantReset').disabled);
      await page.locator('#homeAssistantReset').click();await page.locator('#homeAssistantResetCancel').click();
      assert.equal(await page.locator('[data-draft-id="draft-1"]').count(),1);
      await page.locator('#homeAssistantReset').click();await page.locator('#homeAssistantResetConfirm').click();
      await page.waitForFunction(()=>document.querySelector('#homeAssistantDrafts').children.length===0);
      fail=true;await page.locator('#homeAssistantInput').fill('Draft a note');await page.locator('#homeAssistantSend').click();
      await page.waitForFunction(()=>document.querySelector('#homeAssistantStatus').textContent==='AI unavailable');
      assert.equal(await page.locator('#homeAssistantRefresh').isVisible(),true);
      assert.equal(await page.locator('#homeAssistantInput').inputValue(),'Draft a note');assert.equal(chats,2);
      assert.equal(await page.locator('#homeAssistantSend').isEnabled(),true);
      // Delayed ReadableStream: assert that text paints BEFORE the done event,
      // including UTF-8 split byte-by-byte, CRLF and multi-line SSE data.
      await page.evaluate(()=>{
        const original=window.csrfFetch;
        let committed=null;
        window.csrfFetch=async(url,options)=>{
          if(url.endsWith('/assistant')&&committed)return new Response(JSON.stringify({code:0,session:committed}),{headers:{'Content-Type':'application/json'}});
          if(!url.endsWith('/chat'))return original(url,options);
          if(options.headers.Accept!=='text/event-stream'||options.offlinePolicy!=='reject')throw new Error('missing streaming/offline policy');
          return new Response(new ReadableStream({start(controller){
            const encoder=new TextEncoder();
            function push(frame){for(const byte of encoder.encode(frame))controller.enqueue(new Uint8Array([byte]));}
            function event(name,data){push('event: '+name+'\r\ndata: '+JSON.stringify(data)+'\r\n\r\n');}
            options.signal.addEventListener('abort',()=>controller.error(new DOMException('Aborted','AbortError')),{once:true});
            event('round',{round:1});event('progress',{tool:'search'});
            push('event: delta\r\ndata: {"text":\r\ndata: "你好"}\r\n\r\n');
            window.finishAssistantStream=mode=>{
              if(mode==='error')event('error',{code:502,message:'Stream unavailable'});
              else if(mode==='invalid')push('event: delta\ndata: {broken\n\n');
              else if(mode==='done'){
                event('delta',{text:'，完成'});
                committed={id:'session-2',messages:[{role:'user',content:'Draft a note'},{role:'assistant',content:'你好，完成'}],drafts:[],busy:false};
                event('done',{code:0,session_id:'session-2'});
              }
              controller.close();
            };
          }}),{headers:{'Content-Type':'text/event-stream'}});
        };
      });
      for(const mode of ['done','cut','error','invalid','abort']){
        await page.locator('#homeAssistantInput').fill('Draft a note');await page.locator('#homeAssistantSend').click();
        await page.waitForFunction(()=>document.querySelector('[data-streaming="true"] .home-assistant-text')?.textContent==='你好');
        assert.equal(await page.locator('#homeAssistantSend').isEnabled(),false);
        assert.equal(await page.locator('#homeAssistantDrafts button').count(),0);
        if(mode==='done') {
          await page.locator('#homeAssistantClose').click();
          await page.waitForFunction(()=>!document.querySelector('#homeAssistant').open);
          assert.equal(await page.locator('#homeAssistantOpen').getAttribute('data-busy'),'true');
        }
        if(mode==='abort')await page.locator('#homeAssistantStop').click();else await page.evaluate(m=>window.finishAssistantStream(m),mode);
        await page.waitForFunction(()=>!document.querySelector('#homeAssistantSend').disabled);
        if(mode==='done'){
          assert.equal(await page.locator('.assistant-indicator').isVisible(),true);
          await page.locator('#homeAssistantOpen').click();
          await page.waitForFunction(()=>!document.querySelector('#homeAssistantSend').disabled);
          assert.equal(await page.locator('.assistant-indicator').isVisible(),false);
          assert.equal(await page.locator('[data-streaming]').count(),0);
          assert.equal(await page.locator('#homeAssistantInput').inputValue(),'');
          assert((await page.locator('#homeAssistantMessages').innerText()).includes('你好，完成'));
        }else{
          assert.equal(await page.locator('[data-streaming="incomplete"]').count(),1);
          assert.equal(await page.locator('#homeAssistantInput').inputValue(),'Draft a note');
          assert(!/JSON.parse|Unexpected token/.test(await page.locator('#homeAssistantStatus').innerText()));
          if(mode==='error')assert.equal(await page.locator('#homeAssistantStatus').innerText(),'Stream unavailable');
        }
      }
      console.log('PASS '+lang+' '+width+'px: live SSE, split UTF-8, truncation, stream error, malformed data, cancellation');
      await page.locator('#homeAssistantClose').click();
      const launcher=await page.locator('#homeAssistantOpen').boundingBox();
      await page.mouse.move(launcher.x+26,launcher.y+26);await page.mouse.down();await page.mouse.move(28,200,{steps:8});await page.mouse.up();
      assert.equal(await page.locator('#homeAssistant').evaluate(n=>n.open),false);
      assert((await page.locator('#homeAssistantOpen').boundingBox()).x<20);
      assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('bookstark-assistant-position')).side),'left');
      assert.deepEqual(errors,[]);await page.close();console.log('PASS '+lang+' '+width+'px: drafts, confirmation, XSS, reopen, reset, errors, responsive bounds');
    }
  }finally{await browser.close();}
})().catch(err=>{console.error(err);process.exitCode=1;});
