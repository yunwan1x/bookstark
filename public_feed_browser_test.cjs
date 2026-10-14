const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage']});
 try {
  for(const [width,lang,theme] of [[1440,'zh','light'],[390,'zh','light'],[320,'en','dark'],[768,'en','scholar-paper']]){
   for(const kind of (process.env.PUBLIC_FEED_TEST_TYPES||'article,note,book,bookmark').split(',')){
   for(const signedIn of [false,true]) {
   const page=await browser.newPage({viewport:{width,height:1000}}),errors=[];let commentPosts=[],commentItems=[],rejectComment=false;
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(theme=>localStorage.setItem('bookstark-theme',theme),theme);
   await page.route('http://public.test/**',route=>{
    const url=new URL(route.request().url());
    if(url.pathname.startsWith('/static/'))return route.fulfill({path:'.'+url.pathname});
    if(url.pathname==='/shares')return route.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync('/tmp/public-feed-'+lang+'-'+kind+(signedIn?'-auth':'')+'.html','utf8')});
    if(url.pathname==='/api/csrf-token')return route.fulfill({json:{code:0},headers:{'Set-Cookie':'csrf_token=test; Path=/; SameSite=Lax'}});
    if(url.pathname.startsWith('/api/shares/')&&url.pathname.endsWith('/comments')){
     if(route.request().method()==='POST'){
      const payload=route.request().postDataJSON();commentPosts.push(payload);
      if(rejectComment)return route.fulfill({status:400,json:{code:400,message:'TEST_REJECTED'}});
      commentItems=[{comment_id:1,author_name:payload.author_name||'Account',content:payload.content,create_time:'2026-10-14T12:00:00Z',replies:[]}];
      return route.fulfill({json:{code:0}});
     }
     return route.fulfill({json:{code:0,data:commentItems,total:commentItems.length}});
    }
    return route.fulfill({status:404,body:''});
   });
   await page.goto('http://public.test/shares');
   await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').first().waitFor();
   if(kind==='note')await page.locator('[data-note-content] strong').first().waitFor();
   assert.equal(await page.locator('html').getAttribute('lang'),lang);
   assert.equal(await page.locator('.bookstark-science-bg').count(),0);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'horizontal overflow '+width);
   assert.equal(await page.locator(kind==='bookmark'?'.bm-row':'.public-entry').count(),kind==='article'?2:1);
   assert.equal(await page.locator('.public-nav a').count(),4);
   assert.equal(await page.locator('.public-nav a i').count(),4);
   const current=new URL(await page.locator('.public-nav a[aria-current]').getAttribute('href'),'http://public.test');
   assert.equal(current.pathname,'/shares');assert.equal(current.searchParams.get('type'),kind);
   assert.equal(await page.locator('.public-account').count(),signedIn?1:0);
   assert.equal(await page.locator('.public-login').count(),signedIn?0:1);
   if(signedIn){
    await page.locator('#user-menu-trigger').click();assert(await page.locator('#user-menu-dropdown').isVisible());
    await page.locator('#user-menu-trigger').press('Escape');await page.locator('#user-menu-dropdown').waitFor({state:'hidden'});assert.equal(await page.locator('#user-menu-dropdown').isVisible(),false);
    assert(await page.locator('[data-public-action="unpublish"]').count()=== (kind==='bookmark'?0:kind==='article'?2:1));
   } else assert.equal(await page.locator('[data-public-action]').count(),0);
   if(kind==='article')assert.equal(await page.locator('.public-content-type').count(),2);
   if(kind==='note'){assert.equal(await page.locator('.public-note-card .public-entry-heading h2').count(),0);assert.equal(await page.locator('.public-read-link').count(),0);assert(await page.locator('.public-note-author').isVisible());}
   if(kind==='book')assert(await page.locator('.public-book-cover').isVisible());
   if(kind==='bookmark'){
    assert.equal(await page.locator('.bm-row > .row-action').count(),0,'no separate bookmark action column');
    const action=page.locator('.public-bookmark-author .row-action');
    assert.equal(await action.count(),signedIn?1:0);
    if(signedIn){
     const aligned=await action.evaluate(n=>{const a=n.getBoundingClientRect(),b=n.parentElement.querySelector('.bm-row-account').getBoundingClientRect();return a.x>=b.right&&Math.abs(a.y+a.height/2-b.y-b.height/2)<1;});
     assert(aligned,'bookmark action must follow author on the same row');
     assert((await action.getAttribute('href')).startsWith('/bookmarks?id='));
    }
   }
   if(kind!=='bookmark'){
    const badge=page.locator('.public-pinned').first();
    assert(await badge.count()>0,'missing pinned fixture');
    assert.equal(await badge.evaluate(n=>getComputedStyle(n).alignItems),'center');
    if(kind!=='note'){
     assert.equal(await badge.locator('..').getAttribute('class'),'public-entry-heading');
     const aligned=await badge.evaluate(n=>{const title=n.parentElement.querySelector('h2'),a=n.getBoundingClientRect(),b=title.getBoundingClientRect();return {delta:Math.abs(a.y+a.height/2-b.y-b.height/2),before:n.compareDocumentPosition(title)&Node.DOCUMENT_POSITION_FOLLOWING};});
     assert(aligned.before,'badge must precede title');
     if(width>=768)assert(aligned.delta<1,'badge/title vertical alignment');
    }
   }
   assert.notEqual(await page.locator('.public-categories').evaluate(n=>getComputedStyle(n).backgroundColor),'rgba(0, 0, 0, 0)');
   if(width<=640){
    assert.equal(await page.locator('.public-search').isVisible(),false);
    await page.locator('.public-search-toggle').click();assert(await page.locator('.public-search').isVisible());
    await page.locator('[name="keyword"]').press('Escape');assert.equal(await page.locator('.public-search').isVisible(),false);
    assert(await page.locator('.public-categories nav').isVisible());
    assert.equal(await page.locator('.public-info').isVisible(),false);
   }
   if(kind==='note'){
    const alignment=await page.locator('.public-note-author-name').evaluate(n=>{
     const a=n.getBoundingClientRect(),b=n.parentElement.querySelector('.public-note-actions').getBoundingClientRect();
     return {sameRow:Math.abs(a.y+a.height/2-b.y-b.height/2)<1,after:b.x>=a.right};
    });
    assert(alignment.sameRow&&alignment.after,'note actions must be beside the author');
    await page.evaluate(()=>window.scrollTo(0,500));
    assert.equal(await page.locator('.public-header').evaluate(n=>Math.round(n.getBoundingClientRect().top)),0,'header stays at viewport top');
    await page.evaluate(()=>window.scrollTo(0,0));
    assert.equal(await page.evaluate(()=>Boolean(window.__noteXss)),false);
    assert.equal(await page.locator('[data-note-content] script').count(),0);
    assert(await page.locator('[data-note-content] strong').count()>0);
    const noteBody=page.locator('[data-note-content]');
    assert.equal(await noteBody.locator('h2').evaluate(n=>getComputedStyle(n).display),'block');
    assert(await noteBody.locator('ul li').count()>0);assert(await noteBody.locator('blockquote').count()>0);assert(await noteBody.locator('pre code').count()>0);
    assert((await noteBody.innerText()).includes('LAST_VISIBLE_NOTE_LINE'));
    const full=await noteBody.evaluate(n=>({max:getComputedStyle(n).maxHeight,height:n.clientHeight,scroll:n.scrollHeight,bottom:n.getBoundingClientRect().bottom,last:n.lastElementChild.getBoundingClientRect().bottom}));
    assert.equal(full.max,'none');assert(full.height>360);assert(full.scroll<=full.height+1);assert(full.last<=full.bottom+1,'last line is not clipped');
    await page.locator('[data-note-content] img').click();assert(await page.locator('#shareNoteImageLightboxOverlay').isVisible());
    await page.locator('#shareNoteImageLightboxCloseBtn').press('Escape');assert.equal(await page.locator('#shareNoteImageLightboxOverlay').isVisible(),false);
    await page.locator('[data-note-action="expand"]').click();assert(await page.locator('#shareNoteViewerOverlay').isVisible());
    assert(await page.locator('#shareNoteViewerContent').textContent());
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'viewer overflow '+width);
    await page.locator('.note-viewer-close').press('Escape');assert.equal(await page.locator('#shareNoteViewerOverlay').isVisible(),false);
    await page.locator('[data-note-action="comments"]').click();assert(await page.locator('.share-comments').isVisible());
    const comments=page.locator('.share-comments'),form=comments.locator('form').first();
    await page.waitForFunction(()=>document.querySelector('.share-comments-list').textContent&&!document.querySelector('.share-comments-list').textContent.includes('Loading'));
    assert.equal(await comments.locator('.share-comments-count').textContent(),'0');
    assert.equal(await comments.locator('.share-comments-title').evaluate(n=>getComputedStyle(n).fontWeight),'500');
    assert.equal(await form.locator('.share-comment-email').count(),0);
    if(signedIn){assert.equal(await form.locator('.public-comment-avatar').count(),1);assert.equal(await form.locator('.share-comment-author').count(),0);}
    else{
     const guest=await page.evaluate(()=>window.__SHARE_COMMENT_GUEST_NAME__);
     assert(guest,'guest name comes from backend IP');
     assert.equal(await form.locator('input.share-comment-author').inputValue(),guest);
     assert.equal(await form.locator('.public-comment-avatar').count(),0);
     await form.locator('input.share-comment-author').fill('Guest');
    }
    await form.locator('[type="submit"]').click();assert.equal(commentPosts.length,0,'empty comment must not post');
    await form.locator('textarea').fill('<img src=x onerror="window.__commentXss=1">');
    rejectComment=true;await form.locator('[type="submit"]').click();await page.waitForFunction(()=>document.querySelector('.share-comments-actions .share-comments-state').textContent==='TEST_REJECTED');
    assert((await form.locator('textarea').inputValue()).includes('<img'));
    rejectComment=false;await form.locator('[type="submit"]').click();await comments.locator('.share-comment-item').first().waitFor();
    assert.equal(await comments.locator('.share-comment-content img').count(),0);
    assert.equal(await page.evaluate(()=>window.__commentXss),undefined);
    assert.equal(await comments.locator('.share-comments-count').textContent(),'1');
    assert.equal(commentPosts.at(-1).author_name,signedIn?'':'Guest');
    await comments.locator('.share-comment-reply').first().click();
    const reply=comments.locator('.share-comment-reply-form');await reply.locator('textarea').fill('Reply');await reply.locator('[type="submit"]').click();
    await page.waitForFunction(()=>document.querySelector('.share-comment-content')?.textContent==='Reply');
    assert.equal(commentPosts.at(-1).parent_comment_id,1);assert.equal(commentPosts.at(-1).reply_to_comment_id,1);
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'comments overflow');
    await comments.screenshot({path:'/tmp/bookstark-comments-'+width+'-'+(signedIn?'account':'guest')+'.png'});
    await comments.locator('.public-comments-collapse').click();assert.equal(await comments.isVisible(),false);
    assert.equal(await page.locator('[data-note-action="comments"]').getAttribute('aria-expanded'),'false');
    await page.locator('[data-note-action="comments"]').click();assert(await comments.isVisible());
    await page.locator('[data-note-action="comments"]').click();assert.equal(await comments.isVisible(),false);
   }
   assert.deepEqual(errors,[]);
   await page.screenshot({path:'/tmp/bookstark-public-'+kind+'-'+width+'.png',fullPage:true});
   console.log('PASS '+kind+' '+width+' '+lang+' '+theme+' '+(signedIn?'authenticated':'guest')+' layout, navigation and controls');await page.close();
   }
   }
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
