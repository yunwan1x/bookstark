// First-paint/runtime precedence without a live service or account.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),assert=require('assert/strict');
const templates=['base','editor_common','notes_public','login','register','forgot_password','reset_password'];
(async()=>{const b=await chromium.launch({args:['--no-sandbox']});try{
const c=await b.newContext();await c.route('**/*',r=>{const u=new URL(r.request().url());if(u.pathname.startsWith('/static/'))return r.fulfill({path:'.'+u.pathname});const name=u.pathname.slice(1)||'base';const boot=fs.readFileSync('templates/'+name+'.html','utf8').match(/<script>(\(function\(\)\{var k='bookstark-theme'[\s\S]*?)<\/script>/)[1];const fallback=u.searchParams.get('default')||'light';return r.fulfill({contentType:'text/html',body:`<!doctype html><html><head><meta name="bookstark-default-theme" content="${fallback}"><script>${boot};window.firstTheme=document.documentElement.dataset.themeStyle;</script></head><body><script src="/static/js/theme.js"></script><script>BookStarkTheme.apply(BookStarkTheme.get())</script></body></html>`})});
const p=await c.newPage();
for(const name of templates){await p.goto('http://guest.test/'+name+'?default=hud');assert.equal(await p.evaluate(()=>firstTheme),'hud');assert.equal(await p.evaluate(()=>BookStarkTheme.get()),'hud');assert.equal(await p.evaluate(()=>localStorage.getItem('bookstark-theme')),null);}
await p.goto('http://guest.test/base?default=glass');assert.equal(await p.evaluate(()=>firstTheme),'glass');assert.equal(await p.evaluate(()=>document.documentElement.dataset.theme),'light');
await p.evaluate(()=>BookStarkTheme.set('apple'));await p.goto('http://guest.test/base?default=hud');assert.equal(await p.evaluate(()=>firstTheme),'apple');assert.equal(await p.evaluate(()=>BookStarkTheme.get()),'apple');
await p.evaluate(()=>localStorage.setItem('bookstark-theme','__proto__'));await p.reload();assert.equal(await p.evaluate(()=>firstTheme),'hud');assert.equal(await p.evaluate(()=>localStorage.getItem('bookstark-theme')),null);
await p.goto('http://guest.test/base?default=light');assert.equal(await p.evaluate(()=>BookStarkTheme.get()),'light');
const other=await c.newPage();await other.goto('http://guest.test/base?default=hud');await p.evaluate(()=>BookStarkTheme.set('glass'));await other.waitForFunction(()=>BookStarkTheme.get()==='glass');await p.evaluate(()=>localStorage.removeItem('bookstark-theme'));await other.waitForFunction(()=>BookStarkTheme.get()==='hud');
console.log('PASS seven first-paint entries, guest fallback, saved preference priority, invalid preference recovery, default changes, authenticated fallback and storage removal');
}finally{await b.close()}})().catch(e=>{console.error(e);process.exitCode=1});
