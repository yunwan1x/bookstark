const {chromium}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  for(const [width,lang,theme] of [[1440,'zh','light'],[390,'en','dark'],[320,'zh','scholar-paper']]){
   const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
   let saved=null,fail=false,uploads=0;
   const items=[{link_name:'Example',link_url:'https://example.com',sort_weight:0,is_enabled:1,group_name:'Resources',group_order:0},
    {link_name:'Follow our channels',link_url:'',qr_code:'/upload-files/editor/code.png',description:'Scan this code',sort_weight:0,is_enabled:1,group_name:'Follow us',group_order:1},
    {link_name:'Follow our channels',link_url:'',qr_code:'/upload-files/editor/code-2.png',description:'Scan this code',sort_weight:1,is_enabled:1,group_name:'Follow us',group_order:1}];
   const translations=Object.fromEntries([...fs.readFileSync('i18n/'+lang+'.go','utf8').matchAll(/"([\w.]+)":\s*"([^"]*)"/g)].map(m=>[m[1],m[2]]));
   await page.route('http://footer.test/**',async route=>{
    const r=route.request(),url=new URL(r.url());
    if(url.pathname==='/api/admin/friend-links'){
     if(r.method()==='PUT'){if(fail)return route.fulfill({status:500,json:{code:500,message:'Save failed'}});saved=r.postDataJSON();return route.fulfill({json:{code:0}});}
     return route.fulfill({json:{code:0,data:{items}}});
    }
    if(url.pathname==='/api/uploads'){uploads++;return route.fulfill({json:{code:0,data:{url:'/upload-files/editor/new.png'}}});}
    if(url.pathname.startsWith('/upload-files/'))return route.fulfill({contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')});
    if(url.pathname.startsWith('/static/'))return route.fulfill({path:'.'+url.pathname});
    let panel=fs.readFileSync('templates/profile.html','utf8').split('<div id="panel-friend-links"')[1].split('\n            {{end}}')[0];
    panel='<div id="panel-friend-links"'+panel;
    panel=panel.replace('p-4 sm:p-7 hidden','p-4 sm:p-7').replace(/{{call .T "([^"]+)"}}/g,(_,k)=>translations[k]||k);
    const footer='<footer class="site-footer"><div class="site-footer-groups"><section class="site-footer-group"><h2>Resources</h2><ul><li><a href="https://example.com">Example</a></li></ul></section><section class="site-footer-group site-footer-social"><h2>Follow us</h2><div class="site-footer-social-title">Follow our channels</div><div class="site-footer-qr-list"><img src="/upload-files/editor/code.png" alt="Follow our channels"><img src="/upload-files/editor/code-2.png" alt="Follow our channels"></div><p class="site-footer-social-description">Scan this code</p></section></div><div class="site-footer-bottom">BookStark</div></footer>';
    return route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html data-theme="'+(theme==='dark'?'dark':'light')+'" data-theme-style="'+theme+'"><head><meta charset="UTF-8">'+['tailwind.min','variables','components','footer','footer-editor'].map(n=>'<link rel="stylesheet" href="/static/css/'+n+'.css">').join('')+'</head><body><main>'+panel+'</main>'+footer+'<script>window.__=k=>('+JSON.stringify(translations)+')[k]||k;window.csrfFetch=fetch;window.BookStarkErrors={clearField:id=>document.getElementById(id).textContent="",field:(id,e)=>{document.getElementById(id).textContent=e.message||e;document.getElementById(id).classList.remove("hidden")}};window.BSDialog={toast:()=>{},confirm2:async()=>true};</script><script src="/static/js/footer-editor.js"></script></body></html>'});
   });
   await page.goto('http://footer.test/profile');
   await page.waitForFunction(()=>!document.querySelector('#footer-save').disabled);
   assert.equal(await page.locator('.footer-editor-group').count(),2);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),JSON.stringify(await page.evaluate(()=>Array.from(document.querySelectorAll('body *')).filter(n=>n.scrollWidth>n.clientWidth+1).map(n=>({tag:n.tagName,cls:n.className,w:n.clientWidth,scroll:n.scrollWidth})).slice(0,15))));
   assert.equal(await page.locator('.site-footer-qr-list').evaluate(n=>getComputedStyle(n).display),'flex');
   assert.equal(await page.locator('.site-footer-qr-list img').count(),2);
   const imageBox=await page.locator('.site-footer-qr-list img').first().boundingBox();assert(imageBox.width>80);
   assert.equal(await page.locator('.footer-editor-group').nth(1).locator('.footer-editor-group-meta input').count(),2);
   await page.locator('input[type="file"]').setInputFiles({name:'qr.png',mimeType:'image/png',buffer:Buffer.from('test upload')});
   await page.waitForFunction(()=>document.querySelector('.footer-editor-media img').src.endsWith('/new.png'));
   await page.locator('#footer-save').click();await page.waitForFunction(()=>!document.querySelector('#footer-save').disabled);
   assert.equal(uploads,1);assert.equal(saved.items[1].qr_code,'/upload-files/editor/new.png');assert.equal(saved.items[1].link_name,'Follow our channels');assert.equal(saved.items[2].description,'Scan this code');assert.equal(saved.items[0].group_name,'Resources');
   fail=true;await page.locator('#footer-save').click();await page.waitForFunction(()=>document.querySelector('#friend-links-error').textContent==='Save failed');
   assert.equal(await page.locator('.footer-editor-item').count(),3);
   await page.locator('[onclick="FooterEditor.addGroup()"]').click();
   assert.equal(await page.locator('.footer-editor-group').count(),3);
   await page.locator('.footer-editor-group').last().locator('.footer-editor-group-head > button').click();
   assert.equal(await page.locator('.footer-editor-group').count(),2);
   assert.equal(await page.locator('input[type="number"]').count(),0);
   assert.equal(await page.locator('.footer-editor-item:not(.is-qr) input').count(),2);
   fail=false;
   await page.locator('#footer-simple').check();
   assert.equal(await page.locator('.is-qr').isVisible(),false);
   assert.equal(await page.locator('#footer-add-group').isVisible(),false);
   await page.locator('#footer-save').click();await page.waitForFunction(()=>!document.querySelector('#footer-save').disabled);
   assert.equal(saved.simple_mode,true);assert.equal(saved.items.length,3);assert.equal(saved.items[1].qr_code,'/upload-files/editor/new.png');
   await page.locator('#footer-simple').uncheck();assert(await page.locator('.is-qr').isVisible());
   await page.locator('.footer-editor-group-head .footer-editor-moves button').first().click();
   await page.locator('.footer-editor-group').last().locator('.footer-editor-group-head .footer-editor-moves button').first().click();
   await page.locator('#footer-save').click();await page.waitForFunction(()=>!document.querySelector('#footer-save').disabled);
   assert.equal(saved.simple_mode,false);assert.equal(saved.items[0].group_name,'Follow us');assert.equal(saved.items[0].group_order,0);
   await page.screenshot({path:'/tmp/bookstark-footer-'+width+'.png',fullPage:true});
   assert.deepEqual(errors,[]);console.log('PASS footer editor '+width+'px '+lang+' '+theme+': QR upload, save, failed-save preservation, group operations, responsive layout');await page.close();
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
