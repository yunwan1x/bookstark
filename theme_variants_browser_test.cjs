// Local Chromium + mocked APIs only. Never launches a browser on production.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage']});
 try {
  for(const [lang,width] of [['zh',320],['zh',1440],['en',390],['en',1440]]){
   const page=await browser.newPage({viewport:{width,height:1000},reducedMotion:'reduce',hasTouch:width<=640,isMobile:width<=640}),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{localStorage.setItem('bookstark-theme','nvidia');localStorage.setItem('bookstark-science-background','off');});
   await page.route('**/*',async route=>{
    const u=new URL(route.request().url());
    if(u.hostname!=='theme.test')return route.abort();
    if(u.pathname==='/home')return route.fulfill({contentType:'text/html',body:fs.readFileSync('/tmp/home-b1-'+lang+'.html','utf8')});
    if(u.pathname.startsWith('/static/'))return route.fulfill({path:'.'+u.pathname});
    if(u.pathname==='/api/home')return route.fulfill({json:{code:0,layout:null,activity:{},recent:[],sections:['notes','articles','tasks'].map(key=>({key,total:1,items:[{title:'Example',url:'/notes',date:'2026-10-28'}]}))}});
    return route.fulfill({status:404,body:''});
   });
   await page.goto('http://theme.test/home');
   await page.waitForFunction(()=>window.BookStarkTheme&&document.getElementById('homeGrid').getAttribute('aria-busy')==='false');
   const inspect=()=>page.evaluate(()=>{
    const root=document.documentElement,cs=getComputedStyle(root),cta=getComputedStyle(document.querySelector('.home-primary'));
    return {style:root.dataset.themeStyle,scheme:root.dataset.theme,primary:cs.getPropertyValue('--color-primary').trim(),bg:cs.getPropertyValue('--color-bg').trim(),ctaText:cta.color,ctaBg:cta.backgroundColor,overflow:document.documentElement.scrollWidth>innerWidth};
   });
   let state=await inspect();
   assert.equal(state.style,'nvidia');assert.equal(state.scheme,'dark');assert.equal(state.primary,'#76b900');
   assert.equal(state.bg,'#000000');assert.equal(state.ctaText,'rgb(0, 0, 0)');assert.equal(state.ctaBg,'rgb(118, 185, 0)');
   assert.equal(state.overflow,false);
   // Brand green CTA + near-black ink exceed WCAG AA for ordinary text.
   const contrast=await page.evaluate(()=>{
    const luminance=c=>{const rgb=c.match(/\d+/g).slice(0,3).map(Number).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;});return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};
    const cs=getComputedStyle(document.querySelector('.home-primary')),a=luminance(cs.color),b=luminance(cs.backgroundColor);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
   });assert(contrast>=4.5);
   await page.screenshot({path:'/tmp/bookstark-nvidia-'+lang+'-'+width+'.png',fullPage:true});
   assert.equal(await page.locator('.home-card').first().evaluate(n=>getComputedStyle(n).borderRadius),'4px');
   await page.evaluate(()=>BookStarkTheme.set('apple'));
   await page.waitForFunction(()=>getComputedStyle(document.querySelector('.home-primary')).backgroundColor==='rgb(0, 102, 204)');
   state=await inspect();
   assert.equal(state.style,'apple');assert.equal(state.scheme,'light');assert.equal(state.primary,'#0066cc');assert.equal(state.bg,'#f5f5f7');
   assert.equal(state.ctaText,'rgb(255, 255, 255)');assert.equal(state.ctaBg,'rgb(0, 102, 204)');assert.equal(state.overflow,false);
   assert.equal(await page.locator('.home-card').first().evaluate(n=>getComputedStyle(n).borderRadius),'10px');
   await page.screenshot({path:'/tmp/bookstark-apple-'+lang+'-'+width+'.png',fullPage:true});
   await page.evaluate(()=>BookStarkTheme.set('light'));state=await inspect();assert.equal(state.primary,'#2563eb');assert.equal(state.scheme,'light');
   await page.evaluate(()=>BookStarkTheme.toggle());assert.equal((await inspect()).style,'nvidia');
   await page.evaluate(()=>window.dispatchEvent(new StorageEvent('storage',{key:'bookstark-theme',newValue:'light'})));
   assert.equal((await inspect()).style,'light');
   // Every first-paint entry migrates all old/invalid preferences consistently.
   for(const template of ['base','editor_common','notes_public','login','register','forgot_password','reset_password']){
    const source=fs.readFileSync('templates/'+template+'.html','utf8');
    const bootstrap=source.split('<script>').slice(1).map(s=>s.split('</script>')[0]).find(s=>s.includes('s={light:'));
    for(const valid of ['light','nvidia','apple']){
     const result=await page.evaluate(({bootstrap,valid})=>{localStorage.setItem('bookstark-theme',valid);(0,eval)(bootstrap);return [document.documentElement.dataset.themeStyle,document.documentElement.dataset.theme];},{bootstrap,valid});
     assert.deepEqual(result,[valid,valid==='nvidia'?'dark':'light'],template+' valid '+valid);
    }
    for(const old of ['nvidia-apple','dark','notion-pro','scholar-paper','linear-saas','apple-minimal','__proto__']){
     const result=await page.evaluate(({bootstrap,old})=>{localStorage.setItem('bookstark-theme',old);(0,eval)(bootstrap);return [document.documentElement.dataset.themeStyle,document.documentElement.dataset.theme,localStorage.getItem('bookstark-theme')];},{bootstrap,old});
     assert.deepEqual(result,['light','light','light'],template+' '+old);
    }
   }
   assert.equal(await page.evaluate(()=>BookStarkTheme.normalize('__proto__')),'light');
   await page.addStyleTag({url:'/static/css/cherry-theme-dark.css'});
   const editor=await page.evaluate(()=>{
    BookStarkTheme.set('nvidia');
    const fixture=document.createElement('div');fixture.className='cherry theme__dark';fixture.hidden=true;
    fixture.innerHTML='<div class="cherry-editor"></div><div class="cherry-previewer"><a href="/notes">Example</a></div><div class="cm-editor"></div>';
    document.body.append(fixture);
    const result=Array.from(fixture.children).map(n=>getComputedStyle(n).backgroundColor);
    const link=getComputedStyle(fixture.querySelector('a')).color;fixture.remove();return {result,link};
   });
   assert.deepEqual(editor.result,['rgb(26, 26, 26)','rgb(26, 26, 26)','rgb(26, 26, 26)']);
   assert.equal(editor.link,'rgb(180, 229, 102)');
   assert.deepEqual(errors,[]);
   console.log('PASS themes, CTA contrast, old preference migration, first paint, storage sync',lang,width);
   await page.close();
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
