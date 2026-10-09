// Actual service worker + language-switch handler, with cookie-based fixture pages.
const {chromium}=require('playwright');
const fs=require('node:fs');
const http=require('node:http');
const assert=require('node:assert/strict');
const base=fs.readFileSync('templates/base.html','utf8');
const switchScript=base.slice(base.indexOf('window.switchLang ='),base.indexOf('</script>',base.indexOf('window.switchLang =')));
(async()=>{
 const server=http.createServer((req,res)=>{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/api/lang') {
   res.setHeader('Set-Cookie','lang='+url.searchParams.get('lang')+'; Path=/; SameSite=Lax');
   res.setHeader('Content-Type','application/json');res.end('{"code":0}');return;
  }
  const file=url.pathname==='/sw.js'?'static/sw.js':url.pathname.slice(1);
  if(file.startsWith('static/')&&!file.includes('..')&&fs.existsSync(file)) {
   res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.html')?'text/html':'image/png');
   fs.createReadStream(file).pipe(res);return;
  }
  const lang=/(?:^|;\s*)lang=en(?:;|$)/.test(req.headers.cookie||'')?'en':'zh';
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><html lang="${lang}"><head><meta charset="utf-8"></head><body><h1>${lang}</h1><script>${switchScript}</script><script src="/static/js/sw-register.js"></script></body></html>`);
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const context=await browser.newContext({serviceWorkers:'allow'});
  const page=await context.newPage();
  const origin='http://127.0.0.1:'+server.address().port;
  await page.goto(origin+'/language');
  await page.evaluate(()=>navigator.serviceWorker.ready);
  await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
  const paths=['/books','/topics','/labels','/bookmarks','/nav','/shares'];
  for(const path of paths) {await page.goto(origin+path);assert.equal(await page.locator('h1').innerText(),'zh');}
  for(const lang of ['en','zh']) {
   await Promise.all([page.waitForNavigation(),page.evaluate(lang=>window.switchLang(lang),lang)]);
   // Deliberately reinsert a stale page to simulate an old tab finishing a request.
   await page.evaluate(async lang=>{
    const name=(await caches.keys()).find(k=>k.includes('dynamic'));
    const cache=await caches.open(name);
    await cache.put(new Request('/topics',{headers:{Accept:'text/html'}}),new Response('<h1>stale-'+lang+'</h1>',{headers:{'Content-Type':'text/html'}}));
   },lang);
   for(const path of paths) {
    await page.goto(origin+path);
    assert.equal(await page.locator('h1').innerText(),lang,'first visit after switch '+path);
   }
   console.log('PASS first navigation uses '+lang+' across knowledge/collections/resources, including seeded stale HTML');
  }
  await context.setOffline(true);
  await page.goto(origin+'/topics');assert.equal(await page.locator('h1').innerText(),'zh');
  console.log('PASS offline page fallback retained');
 } finally {await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
