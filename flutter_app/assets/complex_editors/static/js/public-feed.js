/* One public reading surface for guests and signed-in readers. */
(function () {
  'use strict';
  let content = document.querySelector('.public-content');
  function readState(root) { return JSON.parse(root.querySelector('.public-feed-state').textContent); }
  function hydrate(root, state) {
    window.__PUBLIC_NOTES__ = state.notes || {};
    window.__SHARE_COMMENTS_ENABLED__ = state.commentsEnabled;
    window.__SHARE_COMMENT_ACCOUNT__ = state.account || '';
    window.__SHARE_COMMENT_GUEST_NAME__ = state.guestName || '';
    window.__SHARE_COMMENT_MAX_LENGTH__ = state.commentMaxLength;
    resetShareNoteStore();
    const login=document.querySelector('.public-login');if(login)login.href=root.dataset.loginUrl;

    root.querySelectorAll('.public-items-bookmark .bm-row-favicon, [data-news-favicon]').forEach(icon => {
      let timer;
      function fallback() {
        clearTimeout(timer);
        if (!icon.isConnected) return;
        icon.insertAdjacentHTML('beforebegin', bookmarkFaviconFallback(icon.dataset.title, icon.dataset.url));
        icon.remove();
      }
      if (icon.hasAttribute('data-news-favicon')) {
        try {
          const site = new URL(icon.dataset.url);
          if (!['http:', 'https:'].includes(site.protocol)) { fallback(); return; }
          icon.src = '/api/favicon?url=' + encodeURIComponent(site.origin + '/favicon.ico');
        } catch (_) { fallback(); return; }
      }
      if (icon.hasAttribute('data-favicon-missing') || (icon.complete && !icon.naturalWidth)) { fallback(); return; }
      if (icon.complete && icon.naturalWidth) return;
      icon.addEventListener('error', fallback, {once: true});
      icon.addEventListener('load', () => clearTimeout(timer), {once: true});
      timer = setTimeout(fallback, 5000);
    });
    root.querySelectorAll('[data-bookmark-url]').forEach(node => {
      try { node.textContent = new URL(node.dataset.bookmarkUrl).hostname; } catch (_) {}
    });
    Object.entries(window.__PUBLIC_NOTES__).forEach(([key, note]) => {
      registerShareNote(key, {title: note.title, content: note.content || '', author: note.author, time: note.share_time, labels: note.labels});
    });
    root.querySelectorAll('.public-note-card').forEach(row => {
      const note = shareNoteStore[row.dataset.noteKey], body = row.querySelector('[data-note-content]');
      if (!note || !body) return;
      body.innerHTML = sanitizeRenderedHTML(marked.parse(note.content));
      body.querySelectorAll('img').forEach(img => { img.loading = 'lazy'; });
      prepareShareNoteImages(body);
    });
  }
  hydrate(content,readState(content));
  let renderedURL=location.pathname+location.search+location.hash, requestID=0, requestAbort;
  const historyData=()=>({...history.state,publicFeed:true,scrollY:window.scrollY});
  history.replaceState(historyData(),'',renderedURL);
  history.scrollRestoration='manual';
  let scrollTimer;
  window.addEventListener('scroll',()=>{
    clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>{
      if(renderedURL===location.pathname+location.search+location.hash)history.replaceState(historyData(),'',renderedURL);
    },150);
  },{passive:true});
  async function navigateFeed(url,options={}) {
    if(url.origin!==location.origin||!(url.pathname==='/shares'||(url.pathname==='/'&&!document.body.dataset.publicAccount)))return;
    const id=++requestID;requestAbort?.abort();requestAbort=new AbortController();
    const controller=requestAbort,timeout=setTimeout(()=>controller.abort(),15000);
    const previousY=window.scrollY;
    if(!options.pop)history.replaceState(historyData(),'',renderedURL);
    const message=content.querySelector('.public-load-status');message.hidden=true;message.textContent='';
    const feed=content.querySelector('.public-feed');
    let skeleton=feed.querySelector('.public-feed-skeleton');
    if(!skeleton){
      skeleton=document.createElement('div');skeleton.className='public-feed-skeleton';skeleton.setAttribute('aria-hidden','true');
      const rows=Math.max(4,Math.ceil(feed.getBoundingClientRect().height/100));
      skeleton.innerHTML=Array.from({length:rows},()=>'<div class="skeleton-row"><span class="skeleton public-skeleton-icon"></span><div class="skeleton-row-body"><div class="skeleton skeleton-row-title"></div><div class="skeleton public-skeleton-excerpt"></div><div class="skeleton public-skeleton-excerpt"></div><div class="skeleton skeleton-row-time"></div></div></div>').join('');
      feed.append(skeleton);
    }
    feed.querySelectorAll('.public-items,.public-pagination').forEach(node=>node.inert=true);
    content.setAttribute('aria-busy','true');
    try {
      if(navigator.onLine===false)throw Error(window.__('public.load_error'));
      const response=await fetch(url.href,{headers:{'X-BookStark-Feed':'content',Accept:'application/vnd.bookstark.feed+html'},credentials:'same-origin',cache:'no-store',signal:controller.signal});
      if(!response.ok||!['/shares','/'].includes(new URL(response.url).pathname))throw Error(window.__('public.load_error'));
      const doc=new DOMParser().parseFromString(await response.text(),'text/html');
      const next=doc.querySelector('.public-content');if(!next)throw Error(window.__('public.load_error'));
      const state=readState(next);
      if((state.account||'')!==(document.body.dataset.publicAccount||''))throw Error(window.__('public.session_changed'));
      if(id!==requestID)return;
      closeShareNoteViewer();closeShareImageLightbox();
      content.replaceWith(next);content=next;hydrate(content,state);
      renderedURL=url.pathname+url.search+url.hash;
      const y=options.pop?Number(options.scrollY)||0:options.replace?previousY:0;
      if(options.pop||options.replace)history.replaceState({...history.state,publicFeed:true,scrollY:y},'',renderedURL);
      else history.pushState({publicFeed:true,scrollY:y},'',renderedURL);
      window.scrollTo({top:y,behavior:'instant'});
      content.querySelector('.public-nav a[aria-current]')?.focus({preventScroll:true});
      document.dispatchEvent(new CustomEvent('bookstark:public-feed-updated'));
    } catch(error) {
      if(id!==requestID)return;
      const status=content.querySelector('.public-load-status');status.hidden=false;status.textContent=error.message===window.__('public.session_changed')?error.message:window.__('public.load_error');
      // A failed Back/Forward request must not leave the URL describing other content.
      if(options.pop)history.replaceState(historyData(),'',renderedURL);
      const sort=content.querySelector('#publicSort');if(sort){const current=new URL(renderedURL,location.origin).searchParams.get('sort')||'latest';[...sort.options].forEach(option=>option.selected=new URL(option.value,location.origin).searchParams.get('sort')===current);}
    } finally {clearTimeout(timeout);if(id===requestID){
      content.removeAttribute('aria-busy');
      content.querySelector('.public-feed-skeleton')?.remove();
      content.querySelectorAll('.public-items,.public-pagination').forEach(node=>node.inert=false);
    }}
  }
  document.addEventListener('click',event=>{
    if(event.defaultPrevented||event.button!==0||event.ctrlKey||event.metaKey||event.shiftKey||event.altKey)return;
    const link=event.target.closest('.public-nav a[href], .public-categories a[href], .public-pagination a[href], .public-items-bookmark .bm-label-badge[href], [data-news-source-link][href]');
    if(!link||link.target||link.hasAttribute('download'))return;
    const url=new URL(link.href);if(url.origin!==location.origin||url.pathname!=='/shares')return;
    event.preventDefault();navigateFeed(url);
  });
  document.addEventListener('submit',event=>{
    if(event.target.id!=='publicSearch')return;
    event.preventDefault();const url=new URL(event.target.action);url.search=new URLSearchParams(new FormData(event.target)).toString();navigateFeed(url);
  });
  document.addEventListener('change',event=>{if(event.target.matches('[data-news-language]')){const u=new URL(location.href);u.searchParams.set('language',event.target.value);u.searchParams.set('page','1');navigateFeed(u);}if(event.target.id==='publicSort')navigateFeed(new URL(event.target.value,location.href));});
  window.addEventListener('popstate',event=>navigateFeed(new URL(location.href),{pop:true,scrollY:event.state?.scrollY}));
  window.addEventListener('pagehide',()=>{requestID++;requestAbort?.abort();clearTimeout(scrollTimer);});

  // Save only this tab's reading position, not content or credentials.
  const positionKey = 'bookstark:public-login-return';
  document.querySelector('.public-login')?.addEventListener('click', () => {
    try { sessionStorage.setItem(positionKey, JSON.stringify({url: '/shares' + location.search, y: scrollY})); } catch (_) {}
  });
  try {
    const saved = JSON.parse(sessionStorage.getItem(positionKey) || 'null');
    if (document.body.dataset.publicAccount && saved && saved.url === location.pathname + location.search) {
      sessionStorage.removeItem(positionKey);
      requestAnimationFrame(() => scrollTo(0, saved.y));
    }
  } catch (_) {}

  async function api(url, method) {
    const res = await csrfFetch(url, {method, offlinePolicy: 'reject', lockKey: 'public:' + url});
    const result = await res.json().catch(() => ({}));
    if (!res.ok || result.code !== 0) throw new Error(result.message || window.__('share.pin.error'));
    return result;
  }
  document.addEventListener('click', async e => {
    document.querySelectorAll('.public-manage[open]').forEach(menu => {
      if (!menu.contains(e.target)) menu.open = false;
    });
    const btn = e.target.closest('[data-public-action]');
    if (!btn || btn.disabled) return;
    const action = btn.dataset.publicAction;
    btn.disabled = true;
    try {
      if (action === 'unpublish' && !await BSDialog.confirm2(formatDeleteConfirmation(window.__('public.unpublish_confirm'), btn.dataset.title, btn.dataset.id))) { btn.disabled = false; return; }
      const base = '/api/shares/' + encodeURIComponent(btn.dataset.type) + '/' + encodeURIComponent(btn.dataset.id);
      await api(base + (action === 'pin' ? '/pin' : ''), action === 'pin' ? 'PATCH' : 'DELETE');
      await navigateFeed(new URL(location.href), {replace:true});
      btn.disabled = false;
    } catch (err) { BSDialog.toast(err.message, 'error'); btn.disabled = false; }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && document.querySelector('#user-menu-trigger[aria-expanded="true"]')) {
      BookStarkHeaderMenus.closeAll(); document.getElementById('user-menu-trigger').focus();
    }
    if (e.key === 'Escape') document.querySelectorAll('.public-manage[open]').forEach(menu => {
      menu.open = false; menu.querySelector('summary').focus();
    });
  });

  document.addEventListener('click', e => {
    const btn = e.target.closest('[data-note-action]');
    if (!btn) return;
    const row = btn.closest('.public-note-card');
    if (btn.dataset.noteAction === 'copy') copyShareNoteContent(row.dataset.noteKey);
    if (btn.dataset.noteAction === 'expand') openShareNoteViewer(row.dataset.noteKey);
    if (btn.dataset.noteAction === 'comments') BookStarkShareComments.toggle(row.querySelector('.share-comments'), btn);
  });
})();
