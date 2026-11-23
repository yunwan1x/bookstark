const {renameDraft}=require('./local-tools-helpers.cjs');
const REPO_ROOT = require('./repo-root.cjs');
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const origin = process.env.BOOKSTARK_TEST_ORIGIN;
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:1440,height:1000}});
 const page=await context.newPage();const errors=[],writes=[];
 page.on('pageerror',e=>{errors.push(e.message);console.log('PAGE ERROR',e.message)});
 context.on('request',r=>{if(r.url().startsWith(origin+'/api/') && !['GET','HEAD'].includes(r.method()))writes.push(r.url())});
 const ready=async()=>{await page.locator('#toolsExport').waitFor({state:'visible',timeout:45000});};
 const saved=async()=>{await page.waitForFunction(()=>document.querySelector('#toolsStatus').dataset.state==='saved');};
 try {
  await page.goto(origin+'/shares');
  assert.equal(await page.locator('.public-tools-card .local-tool-grid a').count(),6);
  assert.equal(await page.locator('.public-tools-card a[href*="type=html"]').count(),0);
  await page.goto(origin+'/tools?type=markdown');await ready();
  assert.equal(await page.locator('#toolsTitle,#toolsDocument,.local-document-toolbar').count(),0,'redundant file toolbar must be removed');
  await page.locator('[data-tools-rename]').waitFor({state:'visible'});
  assert.equal(await page.locator('#toolsDrafts a[aria-current=page]').count(),1,'unsaved draft must appear in sidebar');
  const editorTop=await page.locator('#toolsEditor').boundingBox(),header=await page.locator('.local-tools-header').boundingBox();
  assert.ok(Math.abs(editorTop.y-(header.y+header.height))<2,'editor must start directly below the header');
  // Real keyboard edit, autosave, reload, export and reimport.
  await page.locator('#localMarkdown .cm-content').click();await page.keyboard.type('# Local draft\n\nHello browser');
  await renameDraft(page,'Local markdown');await saved();
  const id=new URL(page.url()).searchParams.get('draft');assert.ok(id);
  // Compact headers retain the current name and save state, with usable icon actions.
  for (const width of [320,390]) {
   await page.setViewportSize({width,height:844});
   assert.equal(await page.locator('#toolsCurrentTitle').isVisible(),true);
   assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Local markdown');
   assert.equal(await page.locator('#toolsCompactStatus').getAttribute('data-state'),'saved');
   for(const action of ['#toolsBack','#toolsExport summary']) {
    const box=await page.locator(action).boundingBox();assert.ok(box.width>=44&&box.height>=44);
    assert.equal(await page.locator(action+' span').isVisible(),false);
   }
   await page.locator('#toolsExport summary').click();await page.locator('#toolsExportMenu button').first().waitFor({state:'visible'});await page.keyboard.press('Escape');
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   await page.screenshot({path:'/tmp/bookstark-local-editor-mobile-'+width+'.png'});
  }
  await page.setViewportSize({width:1440,height:1000});
  await page.locator('#toolsDrawer').click();assert.equal(await page.locator('#toolsCurrentTitle').isVisible(),true);
  await page.locator('#toolsDrawer').click();assert.equal(await page.locator('#toolsCurrentTitle').isVisible(),false);
  // The explicit return button must flush an edit before leaving the workspace.
  await renameDraft(page,'Saved by back');
  await page.locator('#toolsBack').click();await page.waitForURL(url=>url.pathname==='/shares');
  await page.goto(origin+'/tools?draft='+id);await ready();
  assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Saved by back');
  // Failed saves still offer cancellation through the shared confirmation dialog.
  await page.evaluate(()=>{window.restoreDraftSave=BookStarkLocalDrafts.save;BookStarkLocalDrafts.save=async()=>{throw new Error('storage unavailable');};});
  await renameDraft(page,'Keep this unsaved title');
  await page.locator('#toolsBack').click();await page.locator('.bs-dialog-overlay.active').waitFor();
  await page.locator('.bs-dialog-overlay.active .bs-btn-cancel').click();
  assert.equal(new URL(page.url()).pathname,'/tools');
  assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Keep this unsaved title');
  await page.evaluate(()=>{BookStarkLocalDrafts.save=window.restoreDraftSave;delete window.restoreDraftSave;});
  await page.locator('#toolsRetry').click();await saved();
  await renameDraft(page,'Local markdown');await saved();
  await page.reload();await ready();assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Local markdown');
  assert.ok((await page.locator('#localMarkdown').innerText()).includes('Hello browser'));
  await page.locator('#toolsExport summary').click();
  const downloadPromise=page.waitForEvent('download');downloadPromise.catch(()=>{});await page.locator('#toolsExportMenu button').first().click();
  const download=await downloadPromise; const data=JSON.parse(fs.readFileSync(await download.path(),'utf8'));
  assert.equal(data.type,'markdown');assert.ok(data.content.includes('Hello browser'));
  await page.setInputFiles('#toolsImportFile',{name:'test.bookstark.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(data))});
  await page.waitForURL(u=>u.searchParams.get('draft') && u.searchParams.get('draft')!==id);await ready();
  assert.equal((await page.evaluate(()=>BookStarkLocalDrafts.list())).length,2);
  for(const type of ['mindmap','richdoc','spreadsheet','drawing','presentation']){
   console.log('TEST TYPE',type);await page.goto(origin+'/tools?type='+type);await ready();
   if(type==='presentation'){await page.waitForFunction(()=>{const f=document.querySelector('#pptist-editor iframe');return f?.contentWindow?.BookStarkPPTistBridge},{timeout:45000});await page.frameLocator('#pptist-editor iframe').getByText('添加幻灯片',{exact:true}).first().click();}
   if(type==='drawing')await page.waitForSelector('.excalidraw');
   if(type==='spreadsheet'){await page.waitForFunction(()=>BookStarkUniverAdapter.running);const bounds=await page.locator('#toolsEditor').boundingBox();await page.mouse.dblclick(bounds.x+80,bounds.y+136);await page.keyboard.type('42');await page.keyboard.press('Enter');await page.waitForFunction(()=>{const w=JSON.parse(BookStarkUniverAdapter.getContent());return String(w.sheets[w.sheetOrder[0]].cellData?.[0]?.[0]?.v)==='42';});}
   if(type==='mindmap'){await page.locator('me-tpc').first().dblclick();await page.keyboard.press('Control+a');await page.keyboard.type('Local mind map');await page.keyboard.press('Enter');}
   if(type==='richdoc')await page.evaluate(async()=>{
    BookStarkRichDoc.active.command('executeSetRange',0,0);BookStarkRichDoc.active.insertAIText('Local document text',false,false);
    const canvas=document.createElement('canvas');canvas.width=20;canvas.height=20;canvas.getContext('2d').fillRect(0,0,20,20);
    const blob=await new Promise(r=>canvas.toBlob(r));await BookStarkRichDoc.active.insertImageFile(new File([blob],'local.png',{type:'image/png'}));
   });
   if(type==='drawing')await page.evaluate(()=>BookStarkExcalidraw.applySkeleton([{type:'rectangle',x:100,y:100,width:200,height:100}]));
   await renameDraft(page,'Local '+type);await saved();
   const before=await page.evaluate(async()=>BookStarkLocalDrafts.get(new URL(location.href).searchParams.get('draft')));assert.ok(before.content.length>0,type+' has content');if(type==='richdoc'){assert.ok(await page.evaluate(()=>BookStarkRichDoc.active.getText().includes('Local document text')));assert.ok(before.content.includes('data:image/png'));}if(type==='drawing')assert.equal(JSON.parse(before.content).elements.length,1);if(type==='presentation')assert.equal(JSON.parse(before.content).slides.length,2);if(type==='spreadsheet'){const w=JSON.parse(before.content);assert.equal(String(w.sheets[w.sheetOrder[0]].cellData[0][0].v),'42');}
   await page.reload();await ready();assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Local '+type);
   const after=await page.evaluate(async()=>BookStarkLocalDrafts.get(new URL(location.href).searchParams.get('draft')));assert.equal(after.id,before.id);
   await page.locator('#toolsExport summary').click();const pending=page.waitForEvent('download');await page.locator('#toolsExportMenu button').first().click();
   const dl=await pending;const exported=JSON.parse(fs.readFileSync(await dl.path(),'utf8'));assert.equal(exported.type,type);assert.ok(exported.content.length>0);
   if(type!=='presentation'){
    await page.locator('#toolsExport summary').click();const extra=page.waitForEvent('download');extra.catch(()=>{});
    await page.locator('#toolsExportMenu button').nth(type==='mindmap'?2:1).click();const asset=await extra;
    const raw=fs.readFileSync(await asset.path(),'utf8');assert.ok(raw.length>0);
    if(type==='spreadsheet')assert.ok(raw.includes('42'));
    if(type==='richdoc')assert.ok(raw.includes('Local document text'));
    if(type==='mindmap')assert.ok(raw.includes('<svg'));
   }
   await page.screenshot({path:'/tmp/bookstark-local-'+type+'.png'});
   await page.setInputFiles('#toolsImportFile',{name:'roundtrip.bookstark.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(exported))});
   await page.waitForURL(u=>u.searchParams.get('draft') && u.searchParams.get('draft')!==after.id);await ready();
   assert.equal(await page.locator('#toolsCurrentTitle').textContent(),'Local '+type);
  }
  // A rejected IndexedDB transaction must stay visibly unsaved, then retry without duplicating.
  await page.goto(origin+'/tools?draft='+id);await ready();
  await page.evaluate(()=>{window.originalLocalSave=BookStarkLocalDrafts.save;BookStarkLocalDrafts.save=()=>Promise.reject(new DOMException('Full','QuotaExceededError'));});
  await renameDraft(page,'Retry title');await page.locator('#toolsRetry').waitFor({state:'visible'});
  assert.equal(await page.locator('#toolsStatus').getAttribute('data-state'),'error');
  await page.evaluate(()=>BookStarkLocalDrafts.save=window.originalLocalSave);await page.locator('#toolsRetry').click();await saved();
  assert.equal(new URL(page.url()).searchParams.get('draft'),id);
  const second=await context.newPage();await second.goto(page.url());await second.locator('#toolsExport').waitFor({state:'visible'});
  await renameDraft(second,'Other tab title');await second.waitForFunction(()=>document.querySelector('#toolsStatus').dataset.state==='saved');
  await renameDraft(page,'Keep my copy');await page.locator('#toolsCopy').waitFor({state:'visible'});
  await page.locator('#toolsCopy').click();await saved();assert.notEqual(new URL(page.url()).searchParams.get('draft'),id);
  assert.equal(await page.evaluate(async id=>(await BookStarkLocalDrafts.get(id)).title,id),'Other tab title');await second.close();
  // Concurrent tabs must not silently overwrite or resurrect a deleted draft.
  const concurrency=await page.evaluate(async()=>{
   const s=BookStarkLocalDrafts,d={id:crypto.randomUUID(),title:'Concurrency',type:'markdown',content:'one'};
   await s.save(d,0);await s.save({...d,content:'two'},1);
   let conflict=false;try{await s.save({...d,content:'lost'},1)}catch(e){conflict=e.code==='conflict'}
   const current=await s.get(d.id);await s.remove(d.id,2);
   let deleted=false;try{await s.save(d,2)}catch(e){deleted=e.code==='conflict'}return{conflict,deleted,content:current.content};
  });assert.deepEqual(concurrency,{conflict:true,deleted:true,content:'two'});
  // No HTML import, or malformed rich documents.
  await page.setInputFiles('#toolsImportFile',{name:'bad.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({schema:'bookstark-local-draft',version:1,type:'html',title:'x',content:'<script>'}))});
  await page.waitForTimeout(300);assert.ok(!page.url().includes('type=html'));
  for(const lang of ['zh','en']) for(const theme of ['light','nvidia']) for(const width of [320,390,768,1440]){
   await context.addCookies([{name:'lang',value:lang,url:origin}]);await page.setViewportSize({width,height:900});await page.goto(origin+'/tools');
   await page.evaluate(theme=>localStorage.setItem('bookstark-theme',theme),theme);await page.reload();
   assert.equal(await page.locator('#toolsWelcome .local-tool-grid a').count(),6);
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
   await page.locator('#toolsBack').waitFor({state:'visible'});
   if(width<=640){
    assert.equal(await page.locator('#toolsBack span').isVisible(),false,'mobile return button must use only its icon');
    assert.ok((await page.locator('#toolsBack').boundingBox()).width>=44,'mobile return touch target is too small');
   }else assert.equal(await page.locator('#toolsBack span').isVisible(),true);
   const layout=await page.evaluate(()=>{
    const rect=selector=>{const b=document.querySelector(selector).getBoundingClientRect();return {x:b.x,y:b.y,width:b.width,height:b.height,center:b.y+b.height/2,right:b.right};};
    return {header:rect('.local-tools-header'),title:rect('.local-tools-header h1'),back:rect('#toolsBack'),brand:rect('.local-tools-brand')};
   });
   assert.ok(Math.abs(layout.title.center-layout.back.center)<2,'heading and return button are misaligned');
   assert.ok(layout.back.right<=width && layout.back.x>=0,'return button is clipped');
   if(width>640)assert.ok(Math.abs(layout.title.center-layout.brand.center)<2,'brand and heading are misaligned');
   if(width<=640){
    await page.locator('#toolsDrawer').click();assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'true');
    assert.equal(await page.locator('#toolsSidebar').getAttribute('aria-modal'),'true');
    await page.locator('#toolsSidebarClose').click();assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'false');
    await page.locator('#toolsDrawer').click();
    if(width===390 && lang==='zh' && theme==='light')await page.screenshot({path:'/tmp/bookstark-tools-mobile-drawer.png'});
    await page.keyboard.press('Escape');assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'false');
    await page.locator('#toolsDrawer').click();await page.locator('#toolsBackdrop').click({position:{x:width-8,y:500}});
   }
   if(width===1440 && lang==='zh' && theme==='light'){
    const expanded=await page.locator('.local-tools-main').boundingBox();
    await page.locator('#toolsDrawer').click();
    assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'false');
    const collapsed=await page.locator('.local-tools-main').boundingBox();
    assert.ok(collapsed.width-expanded.width>=160,'collapsing sidebar did not free workspace width');
    await page.locator('#toolsNew').waitFor({state:'visible'});await page.locator('#toolsImport').waitFor({state:'visible'});
    await page.reload();assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'false');
    await page.screenshot({path:'/tmp/bookstark-tools-desktop-collapsed.png'});
    await page.locator('#toolsDrawer').click();assert.equal(await page.locator('#toolsDrawer').getAttribute('aria-expanded'),'true');
   }
   await page.screenshot({path:`/tmp/bookstark-local-home-${lang}-${theme}-${width}.png`});
  }
  await page.goto(origin+'/shares');await page.screenshot({path:'/tmp/bookstark-local-sidebar.png',fullPage:true});await page.waitForFunction(()=>document.querySelectorAll('#publicLocalDrafts a').length===2);
  assert.equal(writes.length,0,'tools must never write server APIs');assert.deepEqual(errors,[]);
  console.log('PASS local editors, IndexedDB persistence, import/export, conflicts, responsive themes, aligned headers, persistent sidebar collapse, save-before-return and no API writes');
 }catch(e){await page.screenshot({path:'/tmp/bookstark-local-test-error.png'}).catch(()=>{});throw e;}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
