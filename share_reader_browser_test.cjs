// Tests production share-view functions and styles locally; never runs a remote browser.
const fs=require('node:fs'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const template=fs.readFileSync('templates/share_view.html','utf8');
function source(name){
 const start=template.indexOf('    function '+name+'(');
 assert(start>=0,'missing '+name);
 const end=template.indexOf('\n    }\n',start);
 const code=template.slice(start,end+7);new Function(code);return code;
}
const names=['getShareLayoutStorage','readShareLayoutState','writeShareLayoutState','setShareSidebarCollapsed','isCompactShareViewport','applyShareLayoutState','enterShareReaderFullscreen','exitShareReaderFullscreen','toggleShareSidebar','openMobileDrawer','closeMobileDrawer','switchShareTab','switchBookTab','onFullpage','setShareOutlineAvailable','setShareReaderType','buildShareToc','setActiveTocItem','bindTocObserver','renderShareContent'];
const functions=names.map(source).join('\n');
// Syntax-check inline scripts from real Go-rendered pages when snapshots exist.
for(const kind of ['markdown','html','richdoc','spreadsheet','presentation','drawing','mindmap','book'])for(const lang of ['zh','en']){
 const file='/tmp/share-reader-'+kind+'-'+lang+'.html';
 if(fs.existsSync(file))for(const match of fs.readFileSync(file,'utf8').matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))new Function(match[1]);
}
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage']});
 try{
 for(const width of [1440,390]){
  const page=await browser.newPage({viewport:{width,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('http://reader.test/**',r=>r.fulfill({body:'<!doctype html><html><body></body></html>'}));
  await page.goto('http://reader.test/');
  await page.setContent(`<style>${template.match(/<style>([\s\S]*?)<\/style>/)[1]}</style>
   <button id="share-reader-exit-btn" class="share-reader-exit-btn" onclick="exitShareReaderFullscreen()">Exit</button>
   <div class="share-view-shell"><div id="drawerOverlay" class="drawer-overlay"></div><div id="sidebar">
   <button id="share-tab-meta" class="active">Info</button><button id="share-tab-tree">Chapters</button><button id="share-tab-outline" hidden>Outline</button>
   <div id="share-panel-meta" class="active"></div><div id="share-panel-tree"><a id="chapter" href="#">Chapter</a></div><div id="share-panel-outline" hidden><div id="outline-content"></div><div id="share-toc-empty"></div></div></div>
   <div class="share-main"><div class="share-topbar"><button id="share-expand-btn"></button><button id="share-reader-fullscreen-btn" hidden onclick="enterShareReaderFullscreen()">Read</button><button id="share-copy-content-btn">Copy</button></div>
   <div id="content-scroll"><div id="preview-wrap"><div id="preview-area"></div></div></div><div id="share-footer">Footer</div></div></div>`);
  await page.addScriptTag({content:fs.readFileSync('static/js/utils.js','utf8')});
  await page.addScriptTag({content:`var shareIdentify='article-a',shareType='blog',shareDocType='markdown',shareTitle='Title';
   var SHARE_LAYOUT_STORAGE_KEY='bookstark:share-view-layout:v1',_sidebarCollapsed=false,_shareReaderDocType='',_shareOutlineAvailable=false,_shareRenderVersion=0,_shareTocObserver=null,_shareHeadings=[];
   window.__=k=>k;window.BookStarkTabURL={set:function(){}};var delayed=[];
   var BookStarkEditor={renderContent:function(id,content,type,opts){
    document.getElementById(id).innerHTML=type==='markdown'?'<div class="cherry-previewer">'+content+'</div>':'<div>Embedded tool</div>';
    if(type==='markdown')delayed.push(opts.onTocReady);else if(opts.onFullpage)opts.onFullpage();
   }};
   ${functions}`});
  const escapeStart=template.indexOf("    document.addEventListener('keydown'",template.indexOf('    function exitShareReaderFullscreen()'));
  await page.addScriptTag({content:'function closeShareCommentsPanel(){}\n'+template.slice(escapeStart,template.indexOf('    function toggleShareSidebar()',escapeStart))});
  await page.evaluate(()=>{
   localStorage.setItem(SHARE_LAYOUT_STORAGE_KEY,JSON.stringify({readerFullscreen:true}));
   renderShareContent('<h1>First</h1><h2>Second</h2>','markdown');delayed.shift()();
  });
  assert.equal(await page.locator('body').evaluate(n=>n.classList.contains('share-reader-fullscreen')),false,'ignore old global fullscreen');
  assert(await page.locator('#share-reader-fullscreen-btn').isVisible());assert(await page.locator('#share-tab-outline').isVisible());
  assert.equal(await page.locator('.outline-item').count(),2);
  await page.locator('#share-reader-fullscreen-btn').click();assert(await page.locator('#share-reader-exit-btn').isVisible());
  await page.locator('#share-reader-exit-btn').click();assert.equal(await page.locator('#share-reader-exit-btn').isVisible(),false);
  await page.evaluate(()=>enterShareReaderFullscreen());await page.keyboard.press('Escape');assert.equal(await page.locator('#share-reader-exit-btn').isVisible(),false,'Escape exits reading fullscreen');
  await page.evaluate(()=>{enterShareReaderFullscreen();shareIdentify='article-b';renderShareContent('No headings','markdown');delayed.shift()();});
  assert.equal(await page.locator('#share-reader-exit-btn').isVisible(),false,'no fullscreen inherited across articles');
  assert.equal(await page.locator('#share-tab-outline').isVisible(),false,'headingless Markdown has no outline');
  assert(await page.locator('#share-reader-fullscreen-btn').isVisible(),'headingless Markdown still supports reading');
  await page.evaluate(()=>{shareIdentify='article-a';renderShareContent('<h1>Heading</h1>','markdown');delayed.shift()();});
  assert(await page.locator('#share-reader-exit-btn').isVisible(),'restore only this article preference');
  for(const type of ['html','richdoc','spreadsheet','presentation','drawing','mindmap']){
   await page.evaluate(type=>{
    shareType='book';renderShareContent('<h1>Not an outer heading</h1>',type);
    switchBookTab('outline');enterShareReaderFullscreen();
   },type);
   assert.equal(await page.locator('#share-reader-fullscreen-btn').isVisible(),false,type+' no outer fullscreen');
   assert.equal(await page.locator('#share-reader-exit-btn').isVisible(),false,type+' exits inherited fullscreen');
   assert.equal(await page.locator('#share-tab-outline').isVisible(),false,type+' no outer outline');
   assert.equal(await page.locator('#share-panel-outline').isVisible(),false,type+' no empty outline panel');
   assert(await page.locator('#share-tab-tree').isVisible(),type+' keeps chapter navigation');
   assert(await page.locator('#share-panel-tree').evaluate(n=>n.classList.contains('active')),type+' chapter panel active');
  }
  await page.evaluate(()=>{
   renderShareContent('<h1>Valid</h1>','markdown');delayed.shift()();
   switchBookTab('outline');exitShareReaderFullscreen();
  });
  assert(await page.locator('#share-tab-outline').isVisible(),'return from tool to Markdown restores outline');
  assert.equal(await page.locator('.outline-item').count(),1);
  await page.evaluate(()=>{renderShareContent('<h1>Stale</h1>','markdown');renderShareContent('Tool','html');delayed.shift()();});
  assert.equal(await page.locator('#share-tab-outline').isVisible(),false,'stale async Markdown callback cannot restore tool outline');
  assert.equal(await page.locator('.outline-item').count(),0,'no stale outline entries');
  await page.evaluate(()=>{shareType='blog';switchShareTab('outline');});
  assert(await page.locator('#share-panel-meta').evaluate(n=>n.classList.contains('active')),'invalid article outline URL falls back to info');
  assert.deepEqual(errors,[]);console.log('PASS',width,'all 7 types, headings, fullscreen storage, chapter navigation, stale callbacks');
  await page.close();
 }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
