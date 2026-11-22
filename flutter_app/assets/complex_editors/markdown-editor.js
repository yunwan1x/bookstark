/* Existing BookStark CodeMirror6 Markdown source, with an opaque preview. */
(function (global) {
  'use strict';
  const maxBytes = 20 * 1024 * 1024;
  const encoder = new TextEncoder();
  function sourceValid(value) {
    if (typeof value !== 'string' || encoder.encode(value).length > maxBytes) throw Error('invalid_markdown_source');
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const next = value.charCodeAt(++i);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw Error('invalid_markdown_unicode');
      } else if (c >= 0xdc00 && c <= 0xdfff) throw Error('invalid_markdown_unicode');
    }
    return value;
  }
  function escapeAttribute(value) {
    return String(value).replace(/[&"<>]/g, c => ({'&':'&amp;','"':'&quot;','<':'&lt;','>':'&gt;'}[c]));
  }
  function nonce() {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  }
  function styles() {
    if (document.getElementById('bookstark-markdown-style')) return;
    const node = document.createElement('style'); node.id = 'bookstark-markdown-style';
    node.textContent = '.markdown-host{display:flex;flex-direction:column;min-height:0;height:100%;background:#fff;border:1px solid #e3ddea;border-radius:10px;overflow:hidden;box-sizing:border-box}' +
      '.markdown-toolbar{display:flex;gap:4px;align-items:center;flex:0 0 48px;overflow-x:auto;padding:0 8px;border:0;border-bottom:1px solid #e3ddea;background:#faf9fc;box-sizing:border-box}' +
      '.markdown-toolbar button{flex:0 0 auto;min-width:32px;min-height:36px;border:0;border-radius:6px;background:transparent;color:#172033;font:600 15px system-ui;padding:4px 8px}' +
      '.markdown-toolbar button svg{display:block;width:18px;height:18px;margin:auto}' +
      '.markdown-toolbar button:disabled{opacity:.4}.markdown-toolbar button:hover{background:#eee6f8}' +
      '.markdown-toolbar button.markdown-preview-toggle{margin-left:auto;color:#6530ad;border:1px solid #b69acb;background:white;font-size:14px}' +
      '.markdown-workspace{position:relative;flex:1;min-height:0;overflow:hidden;border:0}' +
      '.markdown-source,.markdown-source .cm-editor{height:100%;min-height:0}.markdown-source .cm-scroller{overflow:auto;font:16px/1.65 ui-monospace,monospace}' +
      '.markdown-source .cm-gutters{background:#f7f8fb;border:0;color:#64748b}.markdown-source .cm-content{padding:8px 0}' +
      '.markdown-preview-frame{display:block;border:0;width:100%;height:100%;background:#fff;border:1px solid #e3ddea;border-radius:10px;overflow:hidden;box-sizing:border-box}' +
      '.markdown-preview-notice{position:absolute;inset:0;display:grid;place-items:center;padding:24px;background:#fff;color:#64748b;text-align:center}' +
      '.markdown-public-tabs{display:flex;gap:4px;width:100%;padding:3px;border:1px solid #e3ddea;border-radius:8px;background:#faf8fc}' +
      '.markdown-public-tabs button{flex:1;border:0;border-radius:6px;background:transparent;font:600 14px system-ui;color:#172033}' +
      '.markdown-public-tabs button[aria-pressed="true"]{background:#f1e8fc;color:#6530ad}' +
      '.markdown-workspace [hidden]{display:none!important}' +
      '.markdown-shared{border:0;background:transparent;gap:12px}' +
      '.markdown-shared>.markdown-public-tabs{flex:0 0 44px;box-sizing:border-box}' +
      '.markdown-shared>.markdown-toolbar{flex:0 0 44px;border:1px solid #e3ddea;border-radius:10px;gap:8px}' +
      '.markdown-shared>.markdown-toolbar[hidden]{display:none}' +
      '.markdown-shared>.markdown-workspace{border:1px solid #e3ddea;border-radius:10px;background:white}' +
      '.markdown-shared .markdown-preview-frame{border:0;border-radius:0}' +
      '.markdown-shared .cm-editor{background:transparent}' +
      '.markdown-shared.markdown-input-locked>.markdown-workspace{background:#eff0f5}';
    document.head.append(node);
  }
  async function mount(node, source, options) {
    sourceValid(source); styles(); options = options || {};
    const cm = global.CMHtml;
    if (!cm || !cm.markdown || !cm.EditorView) throw Error('markdown_engine_unavailable');
    const readOnly = options.readOnly === true, english = options.english === true;
    const sharedEditing = options.sharedMarkdownEditing === true;
    const localImages = options.localMarkdownImages === true;
    if(localImages && options.publicResourceRoot !== undefined)throw Error('invalid_local_markdown_images');
    const articleLayout = sharedEditing || localImages;
    let publicRoot = null;
    if (options.publicResourceRoot !== undefined) {
      if (typeof options.readOnly !== 'boolean' || (!readOnly && !sharedEditing) || typeof options.publicResourceRoot !== 'string' ||
          options.publicResourceRoot.length > 4096 || new TextEncoder().encode(source).length > 4*1024*1024)
        throw Error('invalid_public_markdown');
      publicRoot = new URL(options.publicResourceRoot);
      if (!['http:','https:'].includes(publicRoot.protocol) || !publicRoot.hostname ||
          publicRoot.username || publicRoot.password || publicRoot.href.includes('?') || publicRoot.href.includes('#'))
        throw Error('invalid_public_markdown_root');
      publicRoot = new URL(publicRoot.href.replace(/\/+$/,'')+'/');
    }
    let destroyed = false, frame = null, frameNonce = '', previewEpoch = 0, pending = null;
    let preview = false, previewDirty = false, original = source;
    let editByteLimit = maxBytes;
    function acceptSource(value) {
      sourceValid(value);
      if (encoder.encode(value).length > editByteLimit) throw Error('markdown_edit_limit');
      return value;
    }
    const t = (zh, en) => english ? en : zh;
    const alive = () => !destroyed && (!options.isCurrent || options.isCurrent());
    node.classList.add('markdown-host');
    if(articleLayout)node.classList.add('markdown-shared');
    const bar = document.createElement('div'); bar.className = 'markdown-toolbar';
    bar.setAttribute('role', 'toolbar'); bar.setAttribute('aria-label', t('Markdown 格式', 'Markdown formatting'));
    const workspace = document.createElement('div'); workspace.className = 'markdown-workspace';
    const sourceNode = document.createElement('div'); sourceNode.className = 'markdown-source';
    sourceNode.setAttribute('aria-label', t('Markdown 正文', 'Markdown source'));
    const notice = document.createElement('div'); notice.className = 'markdown-preview-notice'; notice.hidden = true;
    workspace.append(sourceNode, notice); node.append(bar, workspace);
    const view = new cm.EditorView({parent:sourceNode, state:cm.EditorState.create({
      doc:source, extensions:[
        cm.lineNumbers(), cm.highlightActiveLineGutter(), cm.history(),
        cm.markdown(), cm.syntaxHighlighting(cm.mdHighlight),
        cm.drawSelection(), cm.highlightSpecialChars(), cm.EditorView.lineWrapping,
        cm.EditorState.readOnly.of(readOnly), cm.EditorView.editable.of(!readOnly),
        cm.keymap.of([].concat(cm.defaultKeymap, cm.historyKeymap)),
        cm.EditorState.transactionFilter.of(transaction => {
          if (!transaction.docChanged || readOnly) return transaction;
          try { acceptSource(transaction.newDoc.toString()); return transaction; }
          catch (_) {
            if (alive() && typeof options.onLimitRejected === 'function')
              options.onLimitRejected({limit:editByteLimit});
            return [];
          }
        }),
        cm.EditorView.updateListener.of(update => {
          if (update.docChanged && alive()) {
            previewDirty = true;
            if (typeof options.onChange === 'function') options.onChange();
          }
        }),
        cm.EditorView.theme({'&':{height:'100%'},'.cm-content':{caretColor:'#6530ad'},'&.cm-focused':{outline:'none'}}),
      ],
    })});
    function icon(name) {
      const paths = {
        link:['M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2','M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2'],
        list:['M8 6h13','M8 12h13','M8 18h13','M3 6h.01','M3 12h.01','M3 18h.01'],
        undo:['M9 14L4 9l5-5','M4 9h10a6 6 0 0 1 0 12h-2'],
        redo:['M15 14l5-5-5-5','M20 9H10a6 6 0 0 0 0 12h2'],
      };
      const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
      svg.setAttribute('viewBox','0 0 24 24'); svg.setAttribute('aria-hidden','true');
      svg.setAttribute('fill','none'); svg.setAttribute('stroke','currentColor');
      svg.setAttribute('stroke-width','1.8'); svg.setAttribute('stroke-linecap','round');
      svg.setAttribute('stroke-linejoin','round');
      for(const data of paths[name]){
        const path=document.createElementNS('http://www.w3.org/2000/svg','path');
        path.setAttribute('d',data);svg.append(path);
      }
      return svg;
    }
    function button(label, text, action) {
      const value = document.createElement('button'); value.type = 'button';
      if(typeof text==='string')value.textContent=text;else value.append(text);
      if(text==='I')value.style.fontStyle='italic';
      value.setAttribute('aria-label', label); value.title = label;
      value.disabled = readOnly;
      value.addEventListener('click', () => {
        if (!alive() || readOnly || preview) return;
        view.focus(); action();
      });
      bar.append(value); return value;
    }
    function wrap(before, after) {
      const selected = view.state.selection.main, text = view.state.sliceDoc(selected.from, selected.to);
      view.dispatch({changes:{from:selected.from,to:selected.to,insert:before+text+after},
        selection:{anchor:selected.from+before.length,head:selected.from+before.length+text.length},
        userEvent:'input',scrollIntoView:true});
    }
    function prefix(value) {
      const line = view.state.doc.lineAt(view.state.selection.main.from);
      let from = line.from;
      if (from === 0) while(from < line.to && view.state.sliceDoc(from,from+1)==='\ufeff') from++;
      const current = view.state.sliceDoc(from, line.to);
      const remove = current.startsWith(value);
      view.dispatch({changes:{from,to:remove?from+value.length:from,insert:remove?'':value},
        selection:{anchor:from+(remove?0:value.length)},userEvent:'input',scrollIntoView:true});
    }
    const editButtons = [];
    editButtons.push(button(t('一级标题','Heading 1'),sharedEditing?'H':'H1',()=>prefix('# ')));
    editButtons.push(button(t('粗体','Bold'),'B',()=>wrap('**','**')));
    editButtons.push(button(t('斜体','Italic'),'I',()=>wrap('*','*')));
    editButtons.push(button(t('列表','List'),sharedEditing?icon('list'):'☷',()=>prefix('- ')));
    editButtons.push(button(t('插入链接','Insert link'),icon('link'),()=>wrap('[','](https://)')));
    editButtons.push(button(t('撤销','Undo'),icon('undo'),()=>cm.historyKeymap.find(k=>k.key==='Mod-z').run(view)));
    editButtons.push(button(t('重做','Redo'),icon('redo'),()=>{
      const command = cm.historyKeymap.find(k=>k.key==='Mod-y');
      if (command) command.run(view); else cm.historyKeymap.find(k=>k.key==='Mod-z').shift(view);
    }));
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'markdown-preview-toggle';
    bar.append(toggle);
    let publicTabs = null;
    if (publicRoot || localImages) {
      toggle.hidden = true;
      const group = document.createElement('div');
      group.className = 'markdown-public-tabs';
      const body = document.createElement('button'), raw = document.createElement('button');
      body.type = raw.type = 'button';
      body.textContent = articleLayout ? t('预览','Preview') : t('正文','Body');
      raw.textContent = articleLayout ? t('编辑','Edit') : t('源码','Source');
      body.addEventListener('click',()=>{if(!preview)toggle.click();});
      raw.addEventListener('click',()=>{if(preview)toggle.click();});
      if(articleLayout) {group.append(raw,body);node.insertBefore(group,bar);}
      else {group.append(body,raw);bar.append(group);}
      publicTabs = {body,raw};
    }
    function refreshChrome() {
      if(articleLayout)bar.hidden=preview;
      for (const item of editButtons) item.hidden = preview || readOnly;
      sourceNode.hidden = preview;
      if (frame) frame.hidden = !preview;
      toggle.textContent = preview ? (readOnly?t('查看源码','View source'):t('返回编辑','Back to editor')) : t('预览','Preview');
      toggle.setAttribute('aria-label', toggle.textContent);
      if(publicTabs) {
        publicTabs.body.setAttribute('aria-pressed',String(preview));
        publicTabs.raw.setAttribute('aria-pressed',String(!preview));
      }
    }
    function cancelPreview() {
      previewEpoch++;
      if (pending) { clearTimeout(pending.timer); pending.reject(Error('markdown_preview_retired')); pending = null; }
      frameNonce = '';
      if (frame) { frame.remove(); frame = null; }
      notice.hidden = true;
    }
    function message(event) {
      if (!alive() || !frame || event.source !== frame.contentWindow || event.origin !== 'null') return;
      const data = event.data;
      if (!data || typeof data !== 'object' || data.nonce !== frameNonce || data.epoch !== previewEpoch) return;
      if (data.type === 'bookstark-markdown-preview-link' && publicRoot &&
          typeof data.url === 'string' && data.url.length <= 8192) {
        try {
          const target = new URL(data.url);
          if (['http:','https:'].includes(target.protocol) && target.hostname &&
              !target.username && !target.password) {
            global.BookStarkEditorMessages?.postMessage(JSON.stringify({type:'publicExternalLink',url:target.href}));
          }
        } catch (_) {}
        return;
      }
      if (data.type === 'bookstark-markdown-preview-image-failed' && (publicRoot || localImages)) {
        try { global.BookStarkEditorMessages?.postMessage(JSON.stringify({type:publicRoot?'publicImageFailure':'localImageFailure'})); } catch (_) {}
        return;
      }
      if (data.type === 'bookstark-markdown-preview-bootstrap') {
        frame.contentWindow.postMessage({type:'bookstark-markdown-preview-source',nonce:frameNonce,
          epoch:previewEpoch,source:sourceValid(view.state.doc.toString()),english}, '*');
      } else if (data.type === 'bookstark-markdown-preview-ready' && pending) {
        clearTimeout(pending.timer); const done = pending.resolve; pending = null;
        notice.hidden = true; previewDirty = false; done();
      } else if (data.type === 'bookstark-markdown-preview-failed' && pending) {
        clearTimeout(pending.timer); const fail = pending.reject; pending = null; fail(Error('markdown_preview_failed'));
      }
    }
    global.addEventListener('message', message);
    async function showPreview() {
      if (!alive()) throw Error('markdown_editor_retired');
      sourceValid(view.state.doc.toString());
      preview = true; refreshChrome();
      if (frame && !previewDirty) return;
      cancelPreview(); const epoch = previewEpoch, channel = frameNonce = nonce();
      const origin = location.origin;
      const resources = publicRoot ? ' '+publicRoot.origin : '';
      const policy = "default-src 'none'; script-src " + origin + " 'nonce-" + channel + "' 'unsafe-eval'; " +
        "style-src " + origin + resources + " 'unsafe-inline'; img-src data: blob:" + resources + (localImages ? " "+origin : "") + "; font-src " + origin + resources + " data:; " +
        "connect-src 'none'; frame-src 'none'; worker-src 'none'; form-action 'none'; base-uri " +
        (publicRoot ? publicRoot.origin : "'none'") + "; object-src 'none'";
      frame = document.createElement('iframe'); frame.className = 'markdown-preview-frame';
      frame.title = t('Markdown 预览','Markdown preview'); frame.setAttribute('sandbox','allow-scripts');
      frame.referrerPolicy = 'no-referrer';
      const absolute = path => escapeAttribute(origin + path);
      const script = path => '<script nonce="' + channel + '" crossorigin="anonymous" src="' + absolute(path) + '"><\/script>';
      frame.srcdoc = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
        '<meta http-equiv="Content-Security-Policy" content="' + escapeAttribute(policy) + '">' +
        (publicRoot ? '<base href="'+escapeAttribute(publicRoot.href)+'">' : '') +
        '<link crossorigin="anonymous" rel="stylesheet" href="' + absolute('/static/css/variables.css') + '">' +
        '<link crossorigin="anonymous" rel="stylesheet" href="' + absolute('/static/css/cherry-markdown.min.css') + '">' +
        '<style>html,body{margin:0;background:#fff;color:#172033;font:16px/1.65 system-ui}#markdown-preview-root{padding:20px;box-sizing:border-box}.cherry{border:0;box-shadow:none}.cherry-markdown{padding:0!important}</style>' +
        script('/memory-storage.js') + script('/messages-' + (english?'en':'zh') + '.js') +
        script('/static/js/i18n.js') + script('/static/js/cherry-markdown.min.js') +
        (publicRoot ? script('/static/js/mathjax/tex-svg.js') : '') + script('/static/js/editor-common.js') +
        '<script nonce="' + channel + '" crossorigin="anonymous" data-channel="' + channel + '" data-epoch="' + epoch +
        '" data-local-images="' + (localImages?'true':'false') + '" data-public-links="' + (publicRoot?'true':'false') + '" data-parent-origin="' + escapeAttribute(origin) + '" src="' + absolute('/markdown-preview.js') + '"><\/script>' +
        '</head><body><main id="markdown-preview-root"></main></body></html>';
      const result = new Promise((resolve,reject) => {
        const timer = setTimeout(()=>{if(pending&&pending.epoch===epoch){pending=null;reject(Error('markdown_preview_timeout'));}},30000);
        pending = {epoch,resolve,reject,timer};
      });
      notice.textContent = t('正在加载预览…','Loading preview…'); notice.hidden = false;
      workspace.append(frame); refreshChrome();
      try { await result; } catch (error) {
        if (alive() && epoch === previewEpoch) {
          notice.textContent = t('预览暂时无法加载，原文已保留。','Preview unavailable. Original source is retained.');
          notice.hidden = false;
        }
        throw error;
      }
    }
    toggle.addEventListener('click', () => {
      if (!alive()) return;
      if (preview) { preview = false; notice.hidden = true; refreshChrome(); if(!readOnly)view.focus(); }
      else showPreview().catch(()=>{});
    });
    refreshChrome();
    const instance = {
      getMarkdown:()=>sourceValid(view.state.doc.toString()),
      setByteLimit:(limit)=>{
        if(!alive() || readOnly || !Number.isSafeInteger(limit) ||
            limit<1 || limit>editByteLimit) throw Error('invalid_markdown_limit');
        // Existing over-limit documents remain complete and unchanged. The
        // creation surface must keep them read-only rather than mount editable.
        if(encoder.encode(view.state.doc.toString()).length>limit)
          throw Error('markdown_existing_source_over_limit');
        editByteLimit=limit;
        return {limit:editByteLimit};
      },
      setInputLocked:(locked)=>{
        node.classList.toggle('markdown-input-locked',locked);
        for(const item of editButtons)item.disabled=readOnly||locked;
      },
      captureSelection:()=>({anchor:view.state.selection.main.anchor,head:view.state.selection.main.head}),
      insertAtSelection:(range,text)=>{
        if(!alive() || readOnly || !range || !Number.isInteger(range.anchor) ||
            !Number.isInteger(range.head) || range.anchor<0 || range.head<0 ||
            range.anchor>view.state.doc.length || range.head>view.state.doc.length ||
            typeof text!=='string') throw Error('invalid_markdown_insertion');
        const from=Math.min(range.anchor,range.head),to=Math.max(range.anchor,range.head);
        acceptSource(view.state.doc.sliceString(0,from)+text+view.state.doc.sliceString(to));
        view.dispatch({changes:{from,to,insert:text},selection:{anchor:from+text.length},
          userEvent:'input',scrollIntoView:true});
      },
      destroy:()=>{if(destroyed)return;destroyed=true;cancelPreview();global.removeEventListener('message',message);view.destroy();bar.remove();workspace.remove();original='';},
      showPreview,
    };
    if (readOnly && !sharedEditing) await showPreview();
    return instance;
  }
  global.BookStarkMarkdownEditor = Object.freeze({mount});
})(window);
