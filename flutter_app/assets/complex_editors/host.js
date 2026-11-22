/* Existing SDK y3 cold image loading requires this pure dependency.
 * Copied exactly from static/js/utils.js computeDataURLHash (lines 38-52).
 * Keep global: the existing vendor resolves computeDataURLHash by name. */
function computeDataURLHash(dataURL) {
  if (!window.crypto || !window.crypto.subtle) {
    return Promise.reject(new Error('crypto.subtle not available'));
  }
  var parts = dataURL.split(',');
  var byteString = atob(parts[1]);
  var bytes = new Uint8Array(byteString.length);
  for (var i = 0; i < byteString.length; i++) {
    bytes[i] = byteString.charCodeAt(i);
  }
  return crypto.subtle.digest('SHA-256', bytes).then(function(hashBuffer) {
    var hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
  });
}

/* Thin adapter over existing BookStark engines. No account, network API, file
   path, persistence or automatic save capability is exposed by this host. */
(function () {
  'use strict';
  // The bundled Excalidraw build appends esm.sh as a fallback for every
  // FontFace, even when local assets exist. Resolve that exact version's font
  // references to the unchanged bundled files before the browser sees them.
  // No third-party source or general fetch/network behavior is modified.
  if (typeof window.FontFace === 'function') {
    const PlatformFontFace = window.FontFace;
    window.FontFace = class BookStarkBundledFontFace extends PlatformFontFace {
      constructor(family, source, descriptors) {
        if (typeof source === 'string') source = source.replace(
          /https:\/\/esm\.sh\/@excalidraw\/excalidraw@0\.18\.1\/dist\/prod\/fonts\/([A-Za-z0-9_./-]+\.woff2)/g,
          (_, path) => path.split('/').some(segment => segment === '..') ? 'about:blank' : new URL('/static/js/excalidraw/fonts/' + path, location.origin).href);
        super(family, source, descriptors);
      }
    };
  }
  const root = document.getElementById('editor-root');
  const statusElement = document.getElementById('host-status');
  const encoder = new TextEncoder();
  const kinds = new Set(['markdown', 'html', 'spreadsheet', 'drawing', 'mindmap', 'richdoc', 'presentation']);
  let sequence = 0, revision = 0, active = null, ready = false, closed = false;
  let original = '', baseline = '', baselineRaw = '', observed = '', dirty = false, instance = null, userTouched = false;
  let incoming = null, incomingSequence = 0;
  let localDrawing = null;
  let localPresentation = null;
  const cancellations = new Set(), exports = new Map(), scripts = new Map();
  function maxBytes(kind) { return (kind === 'presentation' || kind === 'markdown') ? 20 * 1024 * 1024 : 5 * 1024 * 1024; }
  function wellFormed(text) {
    for (let i = 0; i < text.length; i++) {
      const unit = text.charCodeAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) { const low = text.charCodeAt(++i); if (!(low >= 0xdc00 && low <= 0xdfff)) return false; }
      else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
    }
    return true;
  }
  function validate(kind, source) {
    if (!kinds.has(kind) || typeof source !== 'string' || !wellFormed(source) || encoder.encode(source).length > maxBytes(kind)) throw Error('invalid_document');
    if (kind === 'html' || kind === 'markdown') return null;
    let depth = 0, quoted = false, escaped = false;
    for (const char of source) {
      if (quoted) { if (escaped) escaped = false; else if (char === '\\') escaped = true; else if (char === '"') quoted = false; }
      else if (char === '"') quoted = true;
      else if (char === '{' || char === '[') { if (++depth > 64) throw Error('document_depth'); }
      else if (char === '}' || char === ']') depth--;
    }
    const data = JSON.parse(source);
    function check(value) { if (typeof value === 'number' && !Number.isFinite(value)) throw Error('invalid_number'); if (value && typeof value === 'object') Object.values(value).forEach(check); }
    check(data);
    if (!data || typeof data !== 'object') throw Error('invalid_document');
    if (kind === 'spreadsheet' && (!Array.isArray(data.sheetOrder) || !data.sheetOrder.length || !data.sheets || data.sheetOrder.some(id => typeof id !== 'string' || !data.sheets[id]))) throw Error('invalid_workbook');
    if (kind === 'drawing' && !(Array.isArray(data) || Array.isArray(data.elements))) throw Error('invalid_drawing');
    if (kind === 'mindmap' && (!data.nodeData || typeof data.nodeData !== 'object' || typeof data.nodeData.topic !== 'string')) throw Error('invalid_mindmap');
    if (kind === 'richdoc' && (data.schema !== 'bookstark-richdoc' || data.schema_version !== 1 || !data.data || !Array.isArray(data.data.main))) throw Error('invalid_richdoc');
    if (kind === 'presentation' && (!(data.width > 0) || !(data.height > 0) || !Array.isArray(data.slides) || !data.slides.length || data.slides.some(s => !s || typeof s.id !== 'string' || !Array.isArray(s.elements)))) throw Error('invalid_presentation');
    return data;
  }
  function current(generation) { return !closed && active && active.generation === generation; }
  let inputLocked = false;
  function state() { return {version: 1, generation: active ? active.generation : sequence, kind: active ? active.kind : null, ready, dirty, inputLocked, readOnly: !active || active.readOnly, sourceReadOnly: !!(active && active.sourceReadOnly), localDrawingResourceFailed: !!(localDrawing && localDrawing.failed), localPresentationResourceFailed: !!(localPresentation && localPresentation.failed), revision}; }
  function notify() {
    const value = state();
    if (window.BookStarkEditorMessages && typeof window.BookStarkEditorMessages.postMessage === 'function') window.BookStarkEditorMessages.postMessage(JSON.stringify({type: 'state', ...value}));
    window.dispatchEvent(new CustomEvent('bookstark-editor-state', {detail: value}));
  }
  function showStatus(text) { statusElement.textContent = text; statusElement.hidden = !text; }
  function element(id, className) { const node = document.createElement('div'); node.id = id; node.className = 'engine ' + (className || ''); root.insertBefore(node, statusElement); return node; }
  function script(path) {
    if (!scripts.has(path)) scripts.set(path, new Promise((resolve, reject) => { const node = document.createElement('script'); node.src = path; node.onload = resolve; node.onerror = () => { scripts.delete(path); reject(Error('asset_load_failed')); }; document.head.append(node); }));
    return scripts.get(path);
  }
  function callbackAsset(start, generation) {
    return new Promise((resolve, reject) => {
      const cancel = () => { clearTimeout(timer); cancellations.delete(cancel); reject(Error('retired_load')); };
      const timer = setTimeout(() => { cancellations.delete(cancel); reject(Error('asset_timeout')); }, 30000);
      cancellations.add(cancel);
      start(() => { clearTimeout(timer); cancellations.delete(cancel); if (current(generation)) resolve(); else reject(Error('retired_load')); });
    });
  }
  function destroyEngine() {
    if (localDrawing) localDrawing.retire();
    localDrawing = null;
    if (localPresentation) localPresentation.retire();
    localPresentation = null;
    for (const cancel of [...cancellations]) cancel();
    exports.clear();
    for (const action of [() => window.BookStarkUniverAdapter.destroy(), () => BookStarkEditor.destroyExcalidraw(), () => BookStarkEditor.destroyMindElixir(), () => window.BookStarkRichDoc && window.BookStarkRichDoc.destroy(), () => window.BookStarkPPTist && window.BookStarkPPTist.destroy(), () => instance && instance.destroy && instance.destroy()]) { try { action(); } catch (_) {} }
    instance = null;
    for (const node of root.querySelectorAll(':scope > .engine')) node.remove();
  }
  let reading = window.BookStarkReading13.create({
    root, state, instance: () => instance, original: () => original,
  });
  function rawSnapshot() {
    if (!ready || !active) throw Error('editor_not_ready');
    switch (active.kind) {
      case 'markdown': return active.readOnly ? original : instance.getMarkdown();
      case 'html': return active.readOnly ? original : instance.getMarkdown();
      case 'spreadsheet': return window.BookStarkUniverAdapter.getContent();
      case 'drawing': {
        const source = BookStarkEditor.getDrawingContent();
        return localDrawing ? localDrawing.canonicalSource(source) : source;
      }
      case 'mindmap': return BookStarkEditor.getMindElixirData();
      case 'richdoc': return instance.getContent();
      case 'presentation': { const source=window.BookStarkPPTist.getContent(); return localPresentation?localPresentation.canonicalSource(source):source; }
    }
    throw Error('unsupported_editor');
  }
  function stable(source) {
    if (active.kind === 'html' || active.kind === 'markdown') return source.replace(/\r\n|\r/g, '\n');
    if (active.kind !== 'spreadsheet') return source;
    const data = JSON.parse(source);
    for (const sheet of Object.values(data.sheets || {})) { delete sheet.scrollTop; delete sheet.scrollLeft; }
    return JSON.stringify(data);
  }
  function changed() {
    if (!userTouched || !ready || !active || active.readOnly || closed) return;
    const next = rawSnapshot(); validate(active.kind, next);
    const normalized = stable(next), nextDirty = normalized !== baseline;
    if (normalized !== observed || dirty !== nextDirty) {
      observed = normalized; dirty = nextDirty; revision++; notify();
    }
  }
  let changeTimer = null;
  function scheduleChange() { clearTimeout(changeTimer); changeTimer = setTimeout(() => { changeTimer = null; try { changed(); } catch (_) { showStatus('编辑内容暂时无法读取，请保留当前页面'); } }, 150); }
  function markUserCommand(event) {
    if (!ready || !active || active.readOnly || closed || inputLocked || event && !event.isTrusted) return;
    if (!userTouched) { baselineRaw = rawSnapshot(); baseline = stable(baselineRaw); observed = baseline; userTouched = true; }
  }
  for (const eventName of ['pointerdown', 'keydown', 'beforeinput', 'compositionstart']) root.addEventListener(eventName, markUserCommand, true);
  root.addEventListener('input', scheduleChange, true);
  root.addEventListener('keyup', scheduleChange, true);
  root.addEventListener('pointerup', scheduleChange, true);
  document.addEventListener('keydown', event => { if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); if (ready && active && !active.readOnly && !active.sourceReadOnly && !inputLocked) { changed(); const value = {type: 'saveRequested', ...state()}; if (window.BookStarkEditorMessages) window.BookStarkEditorMessages.postMessage(JSON.stringify(value)); window.dispatchEvent(new CustomEvent('bookstark-editor-save', {detail: value})); } } });
  async function load(kind, source, options) {
    if (closed) throw Error('editor_retired');
    const data = validate(kind, source); options = options || {};
    const sourceReadOnly = options.sourceReadOnly === true;
    if (options.sourceReadOnly !== undefined && typeof options.sourceReadOnly !== 'boolean') throw Error('invalid_source_read_only');
    if (sourceReadOnly && (kind !== 'html' || options.readOnly !== false)) throw Error('invalid_source_read_only');
    if (options.localDrawing !== undefined) {
      const binding = options.localDrawing;
      if (kind !== 'drawing' || options.readOnly !== false || sourceReadOnly ||
          options.sharedMarkdownEditing === true ||
          options.sharedComplexEditing === true ||
          options.publicComplexReadOnly === true ||
          options.publicResourceRoot != null || options.localMarkdownImages === true ||
          !binding || typeof binding.scope !== 'string' ||
          !/^[a-f0-9]{64}$/.test(binding.scope) ||
          !binding.resources || typeof binding.resources !== 'object' ||
          Array.isArray(binding.resources) ||
          Object.keys(binding.resources).length > 32 ||
          Object.entries(binding.resources).some(([fileId, resourceId]) =>
            !fileId || fileId.length > 256 || typeof resourceId !== 'string' ||
            !/^[a-f0-9]{64}$/.test(resourceId)))
        throw Error('invalid_local_drawing_binding');
    }
    if (options.localPresentation !== undefined) {
      const binding = options.localPresentation;
      if (kind !== 'presentation' || options.readOnly !== false || sourceReadOnly ||
          options.sharedMarkdownEditing === true ||
          options.sharedComplexEditing === true ||
          options.publicComplexReadOnly === true ||
          options.publicResourceRoot != null || options.localMarkdownImages === true ||
          !binding || typeof binding.scope !== 'string' ||
          !/^[a-f0-9]{64}$/.test(binding.scope) ||
          !binding.resources || typeof binding.resources !== 'object' ||
          Array.isArray(binding.resources) ||
          new Set(Object.values(binding.resources)).size > 32 || Object.keys(binding.resources).length > 55000 ||
          Object.entries(binding.resources).some(([fileId, resourceId]) =>
            !fileId || fileId.length > 256 || typeof resourceId !== 'string' ||
            !/^[a-f0-9]{64}$/.test(resourceId)))
        throw Error('invalid_local_presentation_binding');
    }
    ready = false; dirty = false; userTouched = false; inputLocked = sourceReadOnly || !!options.localDrawing || !!options.localPresentation; window.__BookStarkEditorInputGate.setLocked(inputLocked, sourceReadOnly); root.inert = !!options.localDrawing || !!options.localPresentation; destroyEngine();
    const generation = ++sequence;
    active = {kind, generation, readOnly: options.readOnly !== false, sourceReadOnly, localMarkdownImages:options.localMarkdownImages === true};
    original = source; baseline = ''; revision = 0; showStatus('正在加载编辑器…'); notify();
    try {
      const language = options.english ? 'en' : 'zh'; document.documentElement.lang = language;
      await script('/messages-' + language + '.js');
      if (!current(generation)) throw Error('retired_load');
      switch (kind) {
        case 'markdown': {
          const node = element('markdown-editor-container', 'markdown-host');
          await script('/static/js/codemirror-html.min.js');
          if (!current(generation)) throw Error('retired_load');
          instance = await window.BookStarkMarkdownEditor.mount(node, source, {
            readOnly: active.readOnly, english: options.english === true,
            publicResourceRoot: options.publicResourceRoot,
            sharedMarkdownEditing: options.sharedMarkdownEditing,
            localMarkdownImages: options.localMarkdownImages,
            isCurrent: () => current(generation), onChange: scheduleChange,
            onLimitRejected: (event) => {
              if(current(generation))showStatus(options.english===true
                ? 'Change rejected: source exceeds '+String(event.limit/(1024*1024))+' MiB or contains invalid Unicode. The previous source is unchanged.'
                : '本次修改未应用：源码超过'+String(event.limit/(1024*1024))+' MiB或包含无效字符，原文保持完整。');
            },
          });
          break;
        }
        case 'html': {
          const node = element('html-editor-container');
          if (active.readOnly) { const frame = document.createElement('iframe'); frame.className = 'html-preview'; frame.title = 'HTML 正文'; frame.setAttribute('sandbox', 'allow-scripts'); frame.referrerPolicy = 'no-referrer'; const previewPolicy = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'";
            const policyTag = '<meta http-equiv="Content-Security-Policy" content="' + previewPolicy + '">';
            const doctype = /^(\uFEFF?\s*<!doctype\s+html\s*>)/i.exec(source);
            const readingScript = reading.htmlScript(frame);
            frame.srcdoc = doctype ? doctype[0] + policyTag + readingScript + source.slice(doctype[0].length) : policyTag + readingScript + source; node.append(frame); }
          else { await script('/static/js/codemirror-html.min.js'); if (!current(generation)) throw Error('retired_load'); instance = BookStarkEditor.initHtmlEditor(node.id, source, scheduleChange, active.sourceReadOnly); if (!instance) throw Error('html_editor_unavailable'); }
          break;
        }
        case 'spreadsheet': {
          const node = element('univer-sheet'); await callbackAsset(done => window.BookStarkUniverAdapter.loadAssets(done), generation);
          if (!current(generation)) throw Error('retired_load'); instance = window.BookStarkUniverAdapter.init(node.id, data, {readonly: active.readOnly}); if (!instance) throw Error('spreadsheet_unavailable');
          await callbackAsset(done => { let attempts = 0; const poll = () => { if (!current(generation)) return; if (node.style.visibility !== 'hidden' || ++attempts > 100) done(); else setTimeout(poll, 50); }; poll(); }, generation);
          window.BookStarkUniverAdapter.setDirty(false); break;
        }
        case 'drawing': {
          const node = element('excalidraw-canvas'); await callbackAsset(done => BookStarkEditor.loadExcalidrawAssets(done), generation);
          if (!current(generation)) throw Error('retired_load');
          let drawingSource = source;
          if (options.localDrawing) {
            await script('/local-drawing.js');
            if (!current(generation)) throw Error('retired_load');
            localDrawing = window.BookStarkLocalDrawing.create({
              source, scope: options.localDrawing.scope,
              resources: options.localDrawing.resources,
              isCurrent: () => current(generation),
              onFailure: () => {
                if (!current(generation)) return;
                inputLocked = true;
                window.__BookStarkEditorInputGate.setLocked(true, false);
                root.inert = true;
                notify();
              },
            });
            drawingSource = localDrawing.prepareSource();
          }
          if (active.readOnly) BookStarkEditor.initExcalidrawPreview(node.id, drawingSource); else BookStarkEditor.initExcalidraw(node.id, drawingSource, scheduleChange);
          if (localDrawing) await localDrawing.waitReady();
          break;
        }
        case 'mindmap': {
          element('mindmap-el'); await callbackAsset(done => BookStarkEditor.loadMindElixirAssets(done), generation);
          if (!current(generation)) throw Error('retired_load'); instance = BookStarkEditor.initMindElixir(source, {readonly: active.readOnly}); if (!instance) throw Error('mindmap_unavailable');
          if (instance.bus && instance.bus.addListener) instance.bus.addListener('operation', scheduleChange); break;
        }
        case 'richdoc': {
          const node = element('richdoc-host', 'richdoc-host'); await script('/static/js/richdoc-editor.js'); if (!current(generation)) throw Error('retired_load');
          instance = await window.BookStarkRichDoc.mount(node.id, source, {readonly: active.readOnly, onChange: scheduleChange}); break;
        }
        case 'presentation': {
          const node = element('pptist-editor');
          await script('/static/js/pptist-adapter.js');
          if (!current(generation)) throw Error('retired_load');
          let presentationSource=source;
          if(options.localPresentation) {
            await script('/local-presentation.js');
            if(!current(generation))throw Error('retired_load');
            localPresentation=window.BookStarkLocalPresentation.create({
              source,scope:options.localPresentation.scope,
              resources:options.localPresentation.resources,
              isCurrent:()=>current(generation),
              onFailure:()=>{inputLocked=true;root.inert=true;
                window.__BookStarkEditorInputGate.setLocked(true,false);}
            });
            presentationSource=localPresentation.prepareSource();
          }
          await callbackAsset(done => window.BookStarkPPTist.mount(node.id,
            presentationSource,{readonly:active.readOnly,
            title:typeof options.title==='string'?options.title:'',
            onReady:done,onChange:scheduleChange}),generation);
          break;
        }
      }
      if (!current(generation)) throw Error('retired_load');
      ready = true;
      if (kind === 'presentation') {
        const frame = root.querySelector('iframe');
        if (!frame || frame.contentWindow.__BookStarkMemoryOnly !== true || frame.contentWindow.__BookStarkMemoryIndexedDB !== true || !frame.contentWindow.__BookStarkEditorInputGate) throw Error('frame_memory_storage_unavailable');
        for (const eventName of ['pointerdown', 'keydown', 'beforeinput', 'compositionstart']) frame.contentDocument.addEventListener(eventName, markUserCommand, true);
        for (const eventName of ['input', 'keyup', 'pointerup']) frame.contentDocument.addEventListener(eventName, scheduleChange, true);
      }
      const snapshot = rawSnapshot(); validate(kind, snapshot); baselineRaw = snapshot; baseline = stable(snapshot); observed = baseline; dirty = false;
      if ((localDrawing && !localDrawing.failed) ||
          (localPresentation && !localPresentation.failed)) {
        inputLocked = false;
        window.__BookStarkEditorInputGate.setLocked(false, false);
        root.inert = false;
      }
      showStatus(''); notify(); return state();
    } catch (error) {
      if (current(generation)) { ready = false; showStatus('编辑器暂时无法加载，原始内容已保留'); notify(); }
      throw error;
    }
  }
  function setMarkdownByteLimit(limit, generation) {
    if(!ready || !active || closed || active.generation!==generation ||
        active.kind!=='markdown' || active.readOnly || active.sourceReadOnly ||
        active.sharedMarkdownEditing || !inputLocked ||
        !instance || typeof instance.setByteLimit!=='function')
      throw Error('markdown_limit_not_authorized');
    const receipt=instance.setByteLimit(limit);
    return {generation,kind:'markdown',limit:receipt.limit};
  }
  function setInputLocked(value, generation) {
    if (typeof value !== 'boolean' || !ready || !active || closed || generation !== active.generation) throw Error('invalid_input_lock');
    if (active.sourceReadOnly && !value) throw Error('source_read_only');
    if (localPresentation && localPresentation.failed && !value) throw Error('local_presentation_resource_failed');
    if (localDrawing && localDrawing.failed && !value) throw Error('local_drawing_resource_failed');
    inputLocked = value;
    if(active.kind==='markdown' && instance.setInputLocked)instance.setInputLocked(value);
    window.__BookStarkEditorInputGate.setLocked(value, active.sourceReadOnly);
    // Keep the source selectable/copyable; CodeMirror readOnly plus the early
    // gate blocks edits without making this root inert.
    root.inert = active.sourceReadOnly ? false : value;
    const frame = active.kind === 'presentation' ? root.querySelector('iframe') : null;
    if (frame) {
      frame.contentWindow.__BookStarkEditorInputGate.setLocked(value);
      frame.contentDocument.body.inert = value;
      if (value && frame.contentDocument.activeElement && frame.contentDocument.activeElement.blur) frame.contentDocument.activeElement.blur();
    }
    if (value && document.activeElement && document.activeElement.blur) document.activeElement.blur();
    if (!value && userTouched && !active.readOnly) changed();
    notify(); return state();
  }
  function getSource() { if (!ready || !active || closed) throw Error('editor_not_ready'); if (active.readOnly || !userTouched) return original; changed(); if (!dirty) return original; const next = BookStarkMergeEditorSnapshot(active.kind, original, baselineRaw, rawSnapshot()); validate(active.kind, next); return next; }
  // Separate read-only capability policy. No API write/network/upload/export
  // capability is granted merely because a rich engine is mounted.
  let publicReadOnlyPolicyInstalled = false;
  function installPublicReadOnlyPolicy() {
    if (publicReadOnlyPolicyInstalled) return;
    publicReadOnlyPolicyInstalled = true;
    const allowed = value => { try { const u = new URL(value, location.href); return u.origin === location.origin &&
      (/^\/static\//.test(u.pathname) || /^\/messages-(?:zh|en)\.js$/.test(u.pathname)); } catch (_) { return false; } };
    const originalFetch = window.fetch.bind(window);
    window.fetch = (input, init) => {
      const method = String(init && init.method || input && input.method || 'GET').toUpperCase();
      const url = typeof input === 'string' || input instanceof URL ? String(input) : input.url;
      if (method !== 'GET' || !allowed(url)) return Promise.reject(Error('public_readonly_network_denied'));
      return originalFetch(input, Object.assign({}, init, {method:'GET', credentials:'omit'}));
    };
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method,url,...args) {
      if(String(method).toUpperCase() !== 'GET' || !allowed(String(url))) throw Error('public_readonly_network_denied');
      return originalOpen.call(this,method,url,...args);
    };
    const deny = () => { throw Error('public_readonly_capability_denied'); };
    for(const key of ['WebSocket','EventSource','Worker','SharedWorker','showOpenFilePicker','showSaveFilePicker','showDirectoryPicker'])
      try { Object.defineProperty(window,key,{value:deny,writable:false,configurable:false}); } catch (_) {}
    try { navigator.sendBeacon = () => false; } catch (_) {}
    document.addEventListener('click',event=>{const a=event.target.closest && event.target.closest('a[download]');
      if(a){event.preventDefault();event.stopImmediatePropagation();}},true);
  }
  function beginLoad(kind, length, digest, options) {
    if (closed || !kinds.has(kind) || !Number.isInteger(length) || length < 0 || length > maxBytes(kind) || !/^[a-f0-9]{64}$/.test(digest)) throw Error('invalid_load');
    options = options || {};
    if (options.publicResourceRoot !== undefined && !options.publicComplexReadOnly && !options.sharedComplexEditing &&
        (kind !== 'markdown' || typeof options.readOnly !== 'boolean' || (options.readOnly !== true && options.sharedMarkdownEditing !== true) || length > 4 * 1024 * 1024 ||
         typeof options.publicResourceRoot !== 'string' || options.publicResourceRoot.length > 4096)) throw Error('invalid_public_markdown');
    if (options.sharedComplexEditing !== undefined && options.sharedComplexEditing !== true) throw Error('invalid_shared_complex');
    if (options.sharedComplexEditing === true &&
        (kind === 'markdown' || options.publicResourceRoot === undefined || typeof options.readOnly !== 'boolean' ||
         options.sourceReadOnly === true || options.publicComplexReadOnly === true || options.sharedMarkdownEditing === true ||
         options.localMarkdownImages === true || length > maxBytes(kind) ||
         Object.keys(options).some(key => !['sharedComplexEditing','publicResourceRoot','readOnly','sourceReadOnly','english','title'].includes(key))))
      throw Error('invalid_shared_complex');
    if (options.publicComplexReadOnly !== undefined && options.publicComplexReadOnly !== true) throw Error('invalid_public_complex');
    if (options.publicComplexReadOnly === true &&
        (options.publicResourceRoot === undefined || options.readOnly !== true || options.sourceReadOnly === true ||
         options.sharedMarkdownEditing === true || options.localMarkdownImages === true ||
         !kinds.has(kind) || length > (kind === 'markdown' ? 4*1024*1024 : maxBytes(kind)) ||
         Object.keys(options).some(key => !['publicComplexReadOnly','publicResourceRoot','readOnly','sourceReadOnly','english','title'].includes(key))))
      throw Error('invalid_public_complex');
    if (options.localMarkdownImages !== undefined && typeof options.localMarkdownImages !== 'boolean')
      throw Error('invalid_local_markdown_images');
    if (options.localMarkdownImages === true &&
        (kind !== 'markdown' || options.publicResourceRoot !== undefined || options.sharedMarkdownEditing === true))
      throw Error('invalid_local_markdown_images');
    if (options.sharedMarkdownEditing !== undefined && typeof options.sharedMarkdownEditing !== 'boolean')
      throw Error('invalid_shared_markdown');
    if (options.sharedMarkdownEditing === true && options.publicResourceRoot === undefined)
      throw Error('missing_shared_markdown_root');
    if (options.publicResourceRoot !== undefined) {
      const root = new URL(options.publicResourceRoot);
      if (!['http:','https:'].includes(root.protocol) || !root.hostname ||
          root.username || root.password || root.href.includes('?') || root.href.includes('#') ||
          options.sourceReadOnly === true) throw Error('invalid_public_markdown_root');
    }
    if (options.sourceReadOnly !== undefined && typeof options.sourceReadOnly !== 'boolean') throw Error('invalid_source_read_only');
    if (options.sourceReadOnly === true && (kind !== 'html' || options.readOnly !== false)) throw Error('invalid_source_read_only');
    if(options.publicComplexReadOnly === true) installPublicReadOnlyPolicy();
    const id = crypto.randomUUID();
    incoming = {id, serial: ++incomingSequence, kind, length, digest, options, bytes: new Uint8Array(length), offset: 0, index: 0};
    return {id, bytes: length, chunkBytes: 262144};
  }
  function appendLoad(id, index, base64) {
    const record = incoming;
    if (closed || !record || record.id !== id || index !== record.index || typeof base64 !== 'string' || base64.length > 349528) throw Error('invalid_load_chunk');
    const text = atob(base64);
    if (!text.length || text.length > 262144 || btoa(text) !== base64 || record.offset + text.length > record.length) throw Error('invalid_load_chunk');
    for (let i = 0; i < text.length; i++) record.bytes[record.offset + i] = text.charCodeAt(i);
    record.offset += text.length; record.index++;
    return {id, index, received: record.offset};
  }
  function abortLoad(id) { if (incoming && incoming.id === id) { incoming = null; incomingSequence++; } return true; }
  async function commitLoad(id) {
    const record = incoming;
    if (closed || !record || record.id !== id || record.offset !== record.length) throw Error('incomplete_load');
    incoming = null;
    const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', record.bytes))].map(n => n.toString(16).padStart(2, '0')).join('');
    if (closed || record.serial !== incomingSequence || digest !== record.digest) throw Error('invalid_load_digest');
    const source = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(record.bytes);
    return load(record.kind, source, record.options);
  }
  function sourceSelection(source, engine, range) {
    if (!range || source.replace(/\r\n?|\n/g,'\n') !== engine.replace(/\r\n?|\n/g,'\n'))
      throw Error('invalid_markdown_selection');
    function offset(position) {
      if (!Number.isInteger(position) || position<0 || position>engine.length)
        throw Error('invalid_markdown_selection');
      let raw=0,normalized=0;
      while (raw<source.length && normalized<position) {
        if(source[raw]==='\r' && source[raw+1]==='\n')raw+=2;else raw++;
        normalized++;
      }
      if(normalized!==position)throw Error('invalid_markdown_selection');
      return raw;
    }
    return {anchor:offset(range.anchor),head:offset(range.head)};
  }
  function imageSelection() {
    if (!active || active.readOnly || active.sourceReadOnly) return null;
    if (active.kind === 'html') {
      const node = root.querySelector('#html-editor-container .cm-editor');
      const view = node && window.CMHtml && window.CMHtml.EditorView.findFromDOM(node);
      if (!view || !view.state || !view.state.selection) return null;
      const r = view.state.selection.main;
      return {kind:'html',from:r.from,to:r.to};
    }
    if (active.kind === 'richdoc') {
      if (!instance || !instance.instance || !instance.instance.command ||
          typeof instance.instance.command.executeImage !== 'function') return null;
      const r = instance.command('getRange');
      if (!r || !Number.isInteger(r.startIndex) || !Number.isInteger(r.endIndex) ||
          r.startIndex < 0 || r.endIndex < r.startIndex || r.endIndex > 1000000 ||
          !['main','header','footer'].includes(r.zone)) return null;
      const range = {startIndex:r.startIndex,endIndex:r.endIndex,zone:r.zone};
      for(const key of ['tableId','startTdIndex','endTdIndex','startTrIndex','endTrIndex','isCrossRowCol']) {
        const value = r[key];
        if(value === null || value === undefined) continue;
        if(key === 'tableId' ? typeof value !== 'string' || value.length > 128 :
           key === 'isCrossRowCol' ? typeof value !== 'boolean' :
           !Number.isInteger(value) || value < 0 || value > 1000000) return null;
        range[key] = value;
      }
      return {kind:'richdoc',range};
    }
    if (active.kind === 'drawing' || active.kind === 'presentation') {
      const adapter=active.kind==='drawing'?window.BookStarkExcalidraw:window.BookStarkPPTist;
      if(!adapter||typeof adapter.ownedImageSelection!=='function'||
         typeof adapter.insertOwnedImage!=='function')return null;
      return adapter.ownedImageSelection();
    }
    if (active.kind === 'spreadsheet') {
      if (!instance || typeof instance.getActiveSheet !== 'function' ||
          typeof instance.getActiveRange !== 'function') return null;
      const sheet=instance.getActiveSheet(), range=instance.getActiveRange();
      if (!sheet || typeof sheet.insertImage !== 'function' ||
          typeof sheet.getSheetId !== 'function' || !range ||
          typeof range.getRange !== 'function') return null;
      const id=sheet.getSheetId(), r=range.getRange();
      if(typeof id!=='string'||!id||id.length>256||!r) return null;
      for(const key of ['startRow','endRow','startColumn','endColumn'])
        if(!Number.isInteger(r[key])||r[key]<0||
           r[key]>(key.includes('Row')?1048575:16383)) return null;
      if(r.startRow>r.endRow||r.startColumn>r.endColumn) return null;
      return {kind:'spreadsheet',sheetId:id,startRow:r.startRow,endRow:r.endRow,
        startColumn:r.startColumn,endColumn:r.endColumn};
    }
    if (active.kind === 'mindmap') {
      if(!instance || typeof instance.reshapeNode!=='function')return null;
      const nodes=instance.currentNodes&&instance.currentNodes.length?
        instance.currentNodes:instance.currentNode?[instance.currentNode]:[];
      if(nodes.length!==1)return null;
      const node=nodes[0],id=node&&node.nodeObj&&node.nodeObj.id;
      if(!node.isConnected||typeof id!=='string'||!id||id.length>256)return null;
      return {kind:'mindmap',nodeId:id};
    }
    return null;
  }
  async function insertLocalRichdocImageSnapshot(id, reference, options) {
    const width=options&&options.width,height=options&&options.height;
    const item=exports.get(id);
    if(!item||!current(item.generation)||!ready||active.kind!=='richdoc'||
       active.readOnly||active.sourceReadOnly||!inputLocked||
       !item.imageSelection||item.imageSelection.kind!=='richdoc'||
       item.revision!==revision||Date.now()-item.created>120000||
       stable(rawSnapshot())!==item.normalized||
       JSON.stringify(imageSelection())!==JSON.stringify(item.imageSelection)||
       typeof reference!=='string'||reference.length>2048||
       !Number.isInteger(width)||!Number.isInteger(height)||width<1||height<1||
       width>16384||height>16384||width*height>32*1024*1024)
      throw Error('invalid_local_richdoc_image');
    const uri=new URL(reference);
    const path=uri.pathname.replace(/^\/+/, '/').split('/');
    const pieces=path.slice(1).map(decodeURIComponent);
    if(uri.protocol!=='bookstark-attachment:'||uri.host||uri.username||
       uri.password||uri.port||uri.search||uri.hash||
       path[0]!==''||pieces.length!==2||!(/^[a-f0-9]{32}$/).test(pieces[0])||
       !pieces[1]||pieces[1].length>255||pieces[1]==='.'||pieces[1]==='..'||
       Array.from(pieces[1]).some(c=>c.charCodeAt(0)<32||c.charCodeAt(0)===127||
         c.charCodeAt(0)===47||c.charCodeAt(0)===92))
      throw Error('invalid_local_richdoc_reference');
    // Canvas insertElementList inherits context keys from the actual selected
    // paragraph (table/list/title/area). Count that real metadata too; never
    // assume a 2 KiB style bound or omit unknown original envelope bytes.
    const paragraph=instance.command('getRangeParagraph');
    if(!Array.isArray(paragraph))throw Error('local_richdoc_context_unavailable');
    const inherited=['tdId','trId','tableId','level','titleId','title',
      'listId','listType','listStyle','areaId','area','rowFlex','rowMargin'];
    let contextBytes=0,contextNodes=0;
    function contextBound(node,depth) {
      if(++contextNodes>100000||depth>64)throw Error('local_richdoc_context_bound');
      if(Array.isArray(node)){for(const child of node)contextBound(child,depth+1);}
      else if(node&&typeof node==='object'){
        const attributes={};
        for(const key of inherited)if(node[key]!==undefined)attributes[key]=node[key];
        contextBytes=Math.max(contextBytes,encoder.encode(JSON.stringify(attributes)).length);
        for(const key of ['valueList','trList','tdList','value'])
          if(Array.isArray(node[key]))contextBound(node[key],depth+1);
      }
    }
    contextBound(paragraph,0);
    if(encoder.encode(getSource()).length+encoder.encode(reference).length+
       contextBytes+2048>maxBytes('richdoc'))
      throw Error('local_richdoc_image_capacity');
    userTouched=true;
    const scaledWidth=Math.min(width,720);
    await Promise.resolve(instance.command('executeImage',{
      value:reference,width:scaledWidth,
      height:Math.max(1,Math.round(height*scaledWidth/width))}));
    if(!current(item.generation))throw Error('retired_local_richdoc_image');
    const source=rawSnapshot();
    if(stable(source)===item.normalized)throw Error('local_richdoc_image_not_observed');
    validate('richdoc',source);
    changed();
    exports.delete(id);
    return {generation:item.generation,ready:true,kind:'richdoc',
      inputLocked:true,dirty:true};
  }
  async function insertLocalDrawingImageSnapshot(id, reference, options) {
    const item = exports.get(id), width = options && options.width,
      height = options && options.height;
    if (!item || !localDrawing || localDrawing.failed ||
        !current(item.generation) || !ready || active.kind !== 'drawing' ||
        active.readOnly || active.sourceReadOnly || !inputLocked ||
        !item.imageSelection || item.imageSelection.kind !== 'drawing' ||
        item.revision !== revision || Date.now() - item.created > 120000 ||
        stable(rawSnapshot()) !== item.normalized ||
        JSON.stringify(imageSelection()) !== JSON.stringify(item.imageSelection) ||
        typeof reference !== 'string' || reference.length > 2048 ||
        !Number.isInteger(width) || !Number.isInteger(height) ||
        width < 1 || height < 1 || width > 16384 || height > 16384 ||
        width * height > 32 * 1024 * 1024 ||
        !options || typeof options.resourceId !== 'string' ||
        !/^[a-f0-9]{64}$/.test(options.resourceId))
      throw Error('invalid_local_drawing_image');
    const url = localDrawing.approveSelection(options.resourceId, reference);
    const guard = () => !!localDrawing && !localDrawing.failed &&
      current(item.generation) && inputLocked &&
      revision === item.revision &&
      stable(rawSnapshot()) === item.normalized &&
      JSON.stringify(imageSelection()) === JSON.stringify(item.imageSelection);
    userTouched = true;
    await window.BookStarkExcalidraw.insertOwnedImage(
      url, width, height, item.imageSelection, guard);
    if (!current(item.generation) || !localDrawing || localDrawing.failed)
      throw Error('retired_local_drawing_image');
    const source = rawSnapshot();
    if (stable(source) === item.normalized)
      throw Error('local_drawing_image_not_observed');
    validate('drawing', source);
    changed();
    exports.delete(id);
    return {generation:item.generation, ready:true, kind:'drawing',
      inputLocked:true, dirty:true, localDrawingResourceFailed:false};
  }
  async function insertLocalPresentationImageSnapshot(id, reference, options) {
    const item = exports.get(id), width = options && options.width,
      height = options && options.height;
    if (!item || !localPresentation || localPresentation.failed ||
        !current(item.generation) || !ready || active.kind !== 'presentation' ||
        active.readOnly || active.sourceReadOnly || !inputLocked ||
        !item.imageSelection || item.imageSelection.kind !== 'presentation' ||
        item.revision !== revision || Date.now() - item.created > 120000 ||
        stable(rawSnapshot()) !== item.normalized ||
        JSON.stringify(imageSelection()) !== JSON.stringify(item.imageSelection) ||
        typeof reference !== 'string' || reference.length > 2048 ||
        !Number.isInteger(width) || !Number.isInteger(height) ||
        width < 1 || height < 1 || width > 16384 || height > 16384 ||
        width * height > 32 * 1024 * 1024 ||
        !options || typeof options.resourceId !== 'string' ||
        !/^[a-f0-9]{64}$/.test(options.resourceId))
      throw Error('invalid_local_presentation_image');
    const url = localPresentation.approveSelection(options.resourceId, reference);
    const guard = () => !!localPresentation && !localPresentation.failed &&
      current(item.generation) && inputLocked &&
      revision === item.revision &&
      stable(rawSnapshot()) === item.normalized &&
      JSON.stringify(imageSelection()) === JSON.stringify(item.imageSelection);
    userTouched = true;
    await window.BookStarkPPTist.insertOwnedImage(
      url, width, height, item.imageSelection, guard);
    if (!current(item.generation) || !localPresentation || localPresentation.failed)
      throw Error('retired_local_presentation_image');
    const source = rawSnapshot();
    if (stable(source) === item.normalized)
      throw Error('local_presentation_image_not_observed');
    validate('presentation', source);
    changed();
    exports.delete(id);
    return {generation:item.generation, ready:true, kind:'presentation',
      inputLocked:true, dirty:true, localPresentationResourceFailed:false};
  }
  async function insertLocalMindmapImageSnapshot(id, reference, options) {
    const width=options&&options.width,height=options&&options.height;
    const item=exports.get(id);
    if(!item||!current(item.generation)||!ready||active.kind!=='mindmap'||
       active.readOnly||active.sourceReadOnly||!inputLocked||
       !item.imageSelection||item.imageSelection.kind!=='mindmap'||
       item.revision!==revision||Date.now()-item.created>120000||
       stable(rawSnapshot())!==item.normalized||
       JSON.stringify(imageSelection())!==JSON.stringify(item.imageSelection)||
       typeof reference!=='string'||reference.length>2048||
       !Number.isInteger(width)||!Number.isInteger(height)||width<1||height<1||
       width>16384||height>16384||width*height>32*1024*1024)
      throw Error('invalid_local_mindmap_image');
    const uri=new URL(reference);
    const path=uri.pathname.replace(/^\/+/, '/').split('/');
    const pieces=path.slice(1).map(decodeURIComponent);
    if(uri.protocol!=='bookstark-attachment:'||uri.host||uri.username||
       uri.password||uri.port||uri.search||uri.hash||
       path[0]!==''||pieces.length!==2||!(/^[a-f0-9]{32}$/).test(pieces[0])||
       !pieces[1]||pieces[1].length>255||pieces[1]==='.'||pieces[1]==='..'||
       Array.from(pieces[1]).some(c=>c.charCodeAt(0)<32||c.charCodeAt(0)===127||
         c.charCodeAt(0)===47||c.charCodeAt(0)===92))
      throw Error('invalid_local_mindmap_reference');
    // MindElixir reshapeNode mutates the selected actual node only. Reserve
    // the full new image object and envelope overhead against MERGED source,
    // conservatively retaining old image bytes in the capacity estimate.
    const scaledWidth=Math.min(width,720);
    const image={url:reference,width:scaledWidth,
      height:Math.max(1,Math.round(height*scaledWidth/width))};
    if(encoder.encode(getSource()).length+
       encoder.encode(JSON.stringify({image})).length+1024>maxBytes('mindmap'))
      throw Error('local_mindmap_image_capacity');
    const nodes=instance.currentNodes&&instance.currentNodes.length?
      instance.currentNodes:instance.currentNode?[instance.currentNode]:[];
    if(nodes.length!==1||!nodes[0]||!nodes[0].isConnected||
       !nodes[0].nodeObj||nodes[0].nodeObj.id!==item.imageSelection.nodeId)
      throw Error('local_mindmap_selection_changed');
    userTouched=true;
    // Actual MindElixir Rt implementation merges image, rerenders the IMG,
    // links the map and emits its normal operation event.
    await Promise.resolve(instance.reshapeNode(nodes[0],{image}));
    if(!current(item.generation))throw Error('retired_local_mindmap_image');
    const source=rawSnapshot();
    if(stable(source)===item.normalized)throw Error('local_mindmap_image_not_observed');
    validate('mindmap',source);
    changed();
    exports.delete(id);
    return {generation:item.generation,ready:true,kind:'mindmap',
      inputLocked:true,dirty:true};
  }
  async function insertImageSnapshot(id, url, width, height) {
    const item = exports.get(id);
    if (!item || !current(item.generation) || !ready || active.readOnly ||
        active.sourceReadOnly || !inputLocked || !item.imageSelection ||
        item.revision !== revision || Date.now()-item.created > 120000 ||
        stable(rawSnapshot()) !== item.normalized ||
        JSON.stringify(imageSelection()) !== JSON.stringify(item.imageSelection) ||
        typeof url !== 'string' || url.length > 2048 ||
        !Number.isInteger(width) || !Number.isInteger(height) ||
        width < 1 || height < 1 || width > 8192 || height > 8192 ||
        width*height > 16*1024*1024) throw Error('invalid_image_insertion');
    const target = new URL(url);
    if (!['http:','https:'].includes(target.protocol) || target.username ||
        target.password || target.search || target.hash) throw Error('invalid_image_url');
    userTouched = true;
    if (active.kind === 'html') {
      const node = root.querySelector('#html-editor-container .cm-editor');
      const view = window.CMHtml.EditorView.findFromDOM(node);
      const escaped = url.replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;');
      const selected = item.imageSelection;
      view.dispatch({changes:{from:selected.from,to:selected.to,
        insert:'<img src="'+escaped+'" width="'+width+'" height="'+height+'" alt="">'}});
    } else if (active.kind === 'richdoc') {
      const scaledWidth = Math.min(width,720);
      await Promise.resolve(instance.command('executeImage',{value:url,width:scaledWidth,
        height:Math.max(1,Math.round(height*scaledWidth/width))}));
    } else if(active.kind==='spreadsheet'){
      const selected=item.imageSelection,sheet=instance.getActiveSheet();
      const inserted=await sheet.insertImage(url,selected.startColumn,selected.startRow);
      if(inserted===false)throw Error('image_insertion_refused');
    } else if(active.kind==='mindmap'){
      const nodes=instance.currentNodes&&instance.currentNodes.length?
        instance.currentNodes:[instance.currentNode];
      const node=nodes[0],scaledWidth=Math.min(width,720);
      instance.reshapeNode(node,{image:{url,width:scaledWidth,
        height:Math.max(1,Math.round(height*scaledWidth/width))}});
    } else if(active.kind==='drawing'||active.kind==='presentation'){
      const adapter=active.kind==='drawing'?window.BookStarkExcalidraw:window.BookStarkPPTist;
      await adapter.insertOwnedImage(url,width,height,item.imageSelection,()=>
        current(item.generation)&&ready&&!active.readOnly&&!active.sourceReadOnly&&
        inputLocked&&revision===item.revision&&stable(rawSnapshot())===item.normalized&&
        JSON.stringify(imageSelection())===JSON.stringify(item.imageSelection));
    } else throw Error('image_insertion_unsupported');
    if (!current(item.generation)) throw Error('retired_image_insertion');
    if(stable(rawSnapshot())===item.normalized)throw Error('image_insertion_not_observed');
    changed(); exports.delete(id); return state();
  }
  function insertLocalHtmlAttachmentSnapshot(id, reference, options) {
    const item = exports.get(id);
    if (!item || !current(item.generation) || !ready || !active ||
        active.kind !== 'html' || active.readOnly || active.sourceReadOnly ||
        !inputLocked || item.revision !== revision ||
        Date.now()-item.created > 120000 || !item.imageSelection ||
        item.imageSelection.kind !== 'html' ||
        stable(rawSnapshot()) !== item.normalized ||
        JSON.stringify(imageSelection()) !== JSON.stringify(item.imageSelection) ||
        typeof reference !== 'string' || reference.length > 2048 ||
        !options || !['image','file'].includes(options.kind)) {
      throw Error('local_attachment_insertion_denied');
    }
    const uri = new URL(reference);
    if (uri.protocol !== 'bookstark-attachment:' || uri.host || uri.username ||
        uri.password || uri.search || uri.hash) throw Error('local_attachment_uri');
    const parts = uri.pathname.replace(/^\/+/, '/').split('/');
    if (parts.length !== 3 || parts[0] !== '' ||
        !/^[a-f0-9]{32}$/.test(parts[1])) throw Error('local_attachment_uri');
    const name = decodeURIComponent(parts[2]);
    if (!name || name.length > 255 || name === '.' || name === '..' ||
        /[\\/\x00-\x1f\x7f]/.test(name) || options.name !== name) {
      throw Error('local_attachment_name');
    }
    const escape = text => text.replace(/&/g,'&amp;').replace(/"/g,'&quot;')
      .replace(/</g,'&lt;').replace(/>/g,'&gt;');
    let markup;
    if (options.kind === 'image') {
      const width=options.width,height=options.height;
      if (!Number.isInteger(width) || !Number.isInteger(height) ||
          width < 1 || height < 1 || width > 16384 || height > 16384 ||
          width*height > 32*1024*1024) throw Error('local_attachment_dimensions');
      markup='<img src="'+escape(reference)+'" width="'+width+
        '" height="'+height+'" alt="">';
    } else {
      markup='<a href="'+escape(reference)+'">'+escape(name)+'</a>';
    }
    const node=root.querySelector('#html-editor-container .cm-editor');
    const view=node && window.CMHtml && window.CMHtml.EditorView.findFromDOM(node);
    if (!view || !view.state) throw Error('local_attachment_editor_missing');
    const selection=item.imageSelection;
    const source=view.state.doc.toString();
    const next=source.slice(0,selection.from)+markup+source.slice(selection.to);
    if (new TextEncoder().encode(next).length > 5*1024*1024) {
      throw Error('local_attachment_source_limit');
    }
    userTouched=true;
    view.dispatch({changes:{from:selection.from,to:selection.to,insert:markup}});
    if (!current(item.generation) || stable(rawSnapshot()) === item.normalized) {
      throw Error('local_attachment_insertion_unobserved');
    }
    changed(); exports.delete(id); return state();
  }
  async function beginSnapshot() {
    if (!ready || !active || closed) throw Error('editor_not_ready');
    const owner = active.generation;
    // A selection-only snapshot stays byte-exact. Only an actual body edit
    // under the input lock forces the original engine's formula result barrier.
    if (active.kind === 'spreadsheet' && !active.readOnly && inputLocked && getSource() !== original) {
      await window.BookStarkUniverAdapter.waitForCalculation(10000);
      if (!current(owner)) throw Error('retired_snapshot');
    }
    const source = getSource(), engineSource = rawSnapshot(), normalized = stable(engineSource), generation = active.generation, capturedRevision = revision;
    validate(active.kind, source); const bytes = encoder.encode(source);
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    if (!current(generation)) throw Error('retired_snapshot');
    const now = Date.now(); for (const [id, item] of exports) if (now - item.created > 120000) exports.delete(id);
    if (exports.size >= 2) throw Error('snapshot_limit');
    const id = crypto.randomUUID(); exports.set(id, {bytes, normalized, engineSource,
      selection:active.kind==='markdown'&&instance.captureSelection?instance.captureSelection():null,
      imageSelection:imageSelection(),
      generation, revision: capturedRevision, created: now});
    return {id, generation, revision: capturedRevision, bytes: bytes.length, chunks: Math.ceil(bytes.length / 262144), sha256: [...digest].map(n => n.toString(16).padStart(2, '0')).join(''),
      ...(active.localMarkdownImages?{markdownSelection:sourceSelection(source,engineSource,instance.captureSelection())}:{})};
  }
  function readSnapshot(id, index) {
    const item = exports.get(id);
    if (!item || !current(item.generation) || Date.now() - item.created > 120000 || !Number.isInteger(index) || index < 0 || index >= Math.ceil(item.bytes.length / 262144)) throw Error('invalid_snapshot');
    const bytes = item.bytes.subarray(index * 262144, (index + 1) * 262144); let text = '';
    for (let offset = 0; offset < bytes.length; offset += 8192) text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
    return {id, generation: item.generation, index, base64: btoa(text)};
  }
  function insertMarkdownSnapshot(id, text) {
    const item=exports.get(id);
    if(!item || !current(item.generation) || !ready || active.kind!=='markdown' ||
        active.readOnly || !inputLocked || !item.selection ||
        Date.now()-item.created>120000 || item.revision!==revision ||
        stable(rawSnapshot())!==item.normalized || typeof text!=='string' ||
        !text.length || encoder.encode(text).length>65536)
      throw Error('invalid_markdown_insertion');
    validate('markdown',text);
    userTouched=true;
    instance.insertAtSelection(item.selection,text);
    changed();
    exports.delete(id);
    return state();
  }
  function acknowledgeSnapshot(id) {
    const item = exports.get(id);
    if (!item || !current(item.generation) || !ready || active.readOnly) throw Error('invalid_saved_snapshot');
    // The application calls this only after a real save receipt/readback. Newer
    // input remains dirty; no pending request may erase edits made meanwhile.
    original = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(item.bytes);
    baselineRaw = item.engineSource; baseline = item.normalized; dirty = stable(rawSnapshot()) !== baseline;
    exports.delete(id); notify(); return state();
  }
  function retire() { reading.retire(); closed = true; sequence++; incomingSequence++; incoming = null; ready = false; dirty = false; clearTimeout(changeTimer); changeTimer = null; destroyEngine(); active = null; original = ''; baseline = ''; baselineRaw = ''; observed = ''; showStatus('编辑器已关闭'); }
  window.BookStarkEditorHost = Object.freeze({bindPublicSelection: binding => reading.bindPublic(binding), capturePublicSelection: (binding) => reading.capture(binding, true), bindReading: binding => reading.bind(binding), captureReading: (binding, includeSelection) => reading.capture(binding, includeSelection), restoreReading: (binding, anchor) => reading.restore(binding, anchor), load, markUserCommand: () => markUserCommand(null), beginLoad, appendLoad, abortLoad, commitLoad, state, setInputLocked, getSource, setMarkdownByteLimit, beginSnapshot, readSnapshot, insertImageSnapshot, insertLocalHtmlAttachmentSnapshot, insertLocalRichdocImageSnapshot, insertLocalMindmapImageSnapshot, insertLocalDrawingImageSnapshot, insertLocalPresentationImageSnapshot, insertMarkdownSnapshot, acknowledgeSnapshot, endSnapshot: id => exports.delete(id), retire});
})();
