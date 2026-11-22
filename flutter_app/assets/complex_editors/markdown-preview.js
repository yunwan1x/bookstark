/* Opaque sandbox child. It never receives the parent's native message bridge. */
(function () {
  'use strict';
  const script = document.currentScript;
  const nonce = script.dataset.channel, epoch = Number(script.dataset.epoch), origin = script.dataset.parentOrigin;
  const maxBytes = 20 * 1024 * 1024;
  if (!/^[a-f0-9]{32}$/.test(nonce) || !Number.isSafeInteger(epoch) || epoch < 1 ||
      !/^https?:\/\/[^/?#]+$/.test(origin)) return;
  let loaded = false, instance = null;
  const send = type => parent.postMessage({type,nonce,epoch},origin);
  // Links and form navigation never acquire top-frame or network privileges.
  document.addEventListener('click', event => {
    const link = event.target instanceof Element && event.target.closest('a[href]');
    if (!link) return;
    if (script.dataset.publicLinks === 'true' && event.isTrusted) {
      const href = link.getAttribute('href') || '';
      if (href.startsWith('#')) {
        event.preventDefault();
        try { document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView(); } catch (_) {}
        return;
      }
      try {
        const target = new URL(href,document.baseURI);
        if (['http:','https:'].includes(target.protocol) && !target.username && !target.password &&
            target.href.length <= 8192) {
          // Keep the opaque document in place. Parent frame-src intentionally
          // denies HTTP navigation; Native checks transient user activation
          // before Flutter presents its external-link confirmation.
          event.preventDefault();
          parent.postMessage({type:'bookstark-markdown-preview-link',nonce,epoch,url:target.href},origin);
          return;
        }
      } catch (_) {}
    }
    event.preventDefault();
  },true);
  let imageFailureSent = false;
  document.addEventListener('error', event => {
    if ((script.dataset.publicLinks === 'true' || script.dataset.localImages === 'true') && !imageFailureSent &&
        event.target instanceof HTMLImageElement) {
      imageFailureSent = true; send('bookstark-markdown-preview-image-failed');
    }
  },true);
  document.addEventListener('submit',event=>event.preventDefault(),true);
  addEventListener('message', async event => {
    const data = event.data;
    if (loaded || event.source !== parent || event.origin !== origin || !data ||
        data.type !== 'bookstark-markdown-preview-source' || data.nonce !== nonce || data.epoch !== epoch ||
        typeof data.source !== 'string' || new TextEncoder().encode(data.source).length > maxBytes) return;
    loaded = true;
    try {
      if (typeof BookStarkEditor === 'undefined' || !window.Cherry || window.BookStarkEditorMessages !== undefined) throw Error('preview_isolation_failed');
      // Loading a script does not imply MathJax has completed its asynchronous
      // startup. The existing Cherry adapter uses synchronous tex2svg: mounting
      // while startup is pending can permanently flatten the initial formula.
      if (script.dataset.publicLinks === 'true') {
        if (!window.MathJax?.startup?.promise) throw Error('math_runtime_unavailable');
        await window.MathJax.startup.promise;
        if (typeof window.MathJax.tex2svg !== 'function') throw Error('math_runtime_unavailable');
      }
      // BOMs remain exact in the source/snapshot; omit only for Markdown presentation.
      const presentedSource = data.source.replace(/^\ufeff+/, '');
      if (script.dataset.localImages === 'true') {
        const config = BookStarkEditor.getCherryConfig({
          id:'markdown-preview-root',value:presentedSource,isPreviewOnly:true,
          editor:{defaultModel:'previewOnly'},
        });
        config.callback = Object.assign({},config.callback,{
          afterInit:()=>send('bookstark-markdown-preview-ready'),
          beforeImageMounted:(property,raw)=>{
            try {
              const candidate=typeof raw==='string' && raw.startsWith('<') && raw.endsWith('>')
                ? raw.slice(1,-1) : raw;
              // Older Android WebViews parse non-special schemes as opaque
              // paths. Match this fixed repository URI without URL.pathname.
              const match=typeof candidate==='string' && candidate.length<=2048 &&
                /^bookstark-attachment:\/\/\/([a-f0-9]{32})\/([^/?#]+)$/.exec(candidate);
              if(!match) return {srcProp:'src',src:'about:blank#invalid-local-image'};
              const parts=[match[1],match[2]];
              const name=decodeURIComponent(parts[1]);
              if(!name || name.length>255 || name==='.' || name==='..' ||
                  /[\\/\x00-\x1f\x7f]/.test(name))
                return {srcProp:'src',src:'about:blank#invalid-local-image'};
              return {srcProp:'src',src:origin+'/__bookstark_local_image/'+parts.join('/')};
            } catch(_) { return {srcProp:'src',src:'about:blank#invalid-local-image'}; }
          },
        });
        instance = new Cherry(config);
      } else {
        instance = BookStarkEditor.initPreview('markdown-preview-root', presentedSource, {
          afterInit:()=>send('bookstark-markdown-preview-ready'),
        });
      }
      if (!instance) throw Error('preview_unavailable');
    } catch (_) { send('bookstark-markdown-preview-failed'); }
  });
  addEventListener('pagehide',()=>{try{if(instance)instance.destroy();}catch(_){}instance=null;});
  send('bookstark-markdown-preview-bootstrap');
})();
