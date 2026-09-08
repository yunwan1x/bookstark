/**
 * BookStark Unified Editor
 * Handles both book editing (with doc tree) and blog editing (single document)
 */

(function() {
  (function setupEditorViewportHeight() {
    var root = document.documentElement;
    function applyEditorViewportHeight() {
      var vv = window.visualViewport;
      var height = vv && vv.height ? vv.height : window.innerHeight;
      if (height) root.style.setProperty('--editor-viewport-height', Math.round(height) + 'px');
    }
    applyEditorViewportHeight();
    window.addEventListener('resize', applyEditorViewportHeight, { passive: true });
    window.addEventListener('orientationchange', applyEditorViewportHeight, { passive: true });
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', applyEditorViewportHeight, { passive: true });
      window.visualViewport.addEventListener('scroll', applyEditorViewportHeight, { passive: true });
    }
  })();

  var IS_BOOK = window.EDITOR_TYPE === 'book';

  function getInitialMode() {
    var modeParam = '';
    try {
      modeParam = new URLSearchParams(window.location.search).get('mode') || '';
    } catch(e) {}
    if (modeParam === 'edit' || modeParam === 'preview') return modeParam;
    return IS_BOOK ? 'edit' : 'preview';
  }

  // ======== Shared State ========
  var currentMarkdown = '';
  var cherryEditor = null;
  var cherryPreview = null;
  var htmlEditor = null;
  var richdocEditor = null;
  var currentDocType = 'markdown';
  var mode = getInitialMode();
  var saveMgr = null;
  var currentPagerPage = 'edit';
  var _previewNeedsRefresh = true;
  var spreadsheetCheckInterval = null;

  // Expose getter for editor-common.js
  window._getCurrentMarkdown = function() { return currentMarkdown; };

  function fetchRawHTMLContent(url, options) {
    if (!url) return Promise.resolve('');
    options = options || {};
    if (!options.cache) options.cache = 'no-store';
    return fetch(url, options).then(function(r) {
      return r.text().then(function(text) {
        if (r.ok) return text;
        var message = text || 'HTML 内容加载失败';
        try {
          var data = JSON.parse(text);
          message = data.message || message;
        } catch(e) {}
        var err = new Error(message);
        if (r.status === 400 || r.status === 401 || r.status === 403) err.isAuthError = true;
        throw err;
      });
    });
  }

  // ======== Book-Only State ========
  var bookId, bookName;
  var docTree = [];
  var currentDocId = null;
  var docLoadSequence = 0;
  var docLoadController = null;
  var docLoadPending = false;
  var prevDocId = 0, nextDocId = 0;
  var collapsedIds = new Set();
  var docShareStatus = {};

  function loadCollapsedState() {
    try {
      var saved = localStorage.getItem('bookstark_collapsed_' + bookId);
      if (saved) {
        var arr = JSON.parse(saved);
        if (Array.isArray(arr)) collapsedIds = new Set(arr);
      }
    } catch(e) {}
  }

  function saveCollapsedState() {
    try {
      localStorage.setItem('bookstark_collapsed_' + bookId, JSON.stringify(Array.from(collapsedIds)));
    } catch(e) {}
  }
  var blogId, blogTitle;

  var OfflineBlogVault = (function() {
    var DB_NAME = 'bookstark-offline-vault';
    var DB_VERSION = 2;
    var STORE = 'encrypted_blogs';

    function supported() {
      return !!(window.indexedDB && window.crypto && window.crypto.subtle && window.TextEncoder && window.TextDecoder);
    }

    function openDB() {
      return new Promise(function(resolve, reject) {
        if (!supported()) {
          reject(new Error('当前浏览器不支持本地加密缓存'));
          return;
        }
        var req = indexedDB.open(DB_NAME, DB_VERSION);
        req.onupgradeneeded = function() {
          var db = req.result;
          if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: 'id' });
          if (!db.objectStoreNames.contains('encrypted_shares')) db.createObjectStore('encrypted_shares', { keyPath: 'id' });
        };
        req.onsuccess = function() { resolve(req.result); };
        req.onerror = function() { reject(req.error || new Error('打开本地缓存失败')); };
      });
    }

    function txStore(mode) {
      return openDB().then(function(db) {
        return db.transaction(STORE, mode).objectStore(STORE);
      });
    }

    function bytesToB64(bytes) {
      var binary = '';
      var chunkSize = 0x8000;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
      }
      return btoa(binary);
    }

    function b64ToBytes(str) {
      var binary = atob(str);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      return bytes;
    }

    function deriveKey(password, salt) {
      var enc = new TextEncoder();
      return crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']).then(function(baseKey) {
        return crypto.subtle.deriveKey(
          { name: 'PBKDF2', salt: salt, iterations: 100000, hash: 'SHA-256' },
          baseKey,
          { name: 'AES-GCM', length: 256 },
          false,
          ['encrypt', 'decrypt']
        );
      });
    }

    function put(record) {
      return txStore('readwrite').then(function(store) {
        return new Promise(function(resolve, reject) {
          var req = store.put(record);
          req.onsuccess = function() { resolve(); };
          req.onerror = function() { reject(req.error || new Error('写入本地缓存失败')); };
        });
      });
    }

    function get(id) {
      return txStore('readonly').then(function(store) {
        return new Promise(function(resolve, reject) {
          var req = store.get(String(id));
          req.onsuccess = function() { resolve(req.result || null); };
          req.onerror = function() { reject(req.error || new Error('读取本地缓存失败')); };
        });
      });
    }

    function save(id, password, content) {
      if (!password) return Promise.resolve();
      var salt = crypto.getRandomValues(new Uint8Array(16));
      var nonce = crypto.getRandomValues(new Uint8Array(12));
      var enc = new TextEncoder();
      return deriveKey(password, salt).then(function(key) {
        return crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, enc.encode(content || ''));
      }).then(function(cipher) {
        return put({
          id: String(id),
          title: blogTitle || '',
          editorType: currentDocType || 'markdown',
          modifyTime: window.BLOG_MODIFY_TIME || '',
          updatedAt: Date.now(),
          salt: bytesToB64(salt),
          nonce: bytesToB64(nonce),
          cipher: bytesToB64(new Uint8Array(cipher))
        });
      }).catch(function(err) {
        console.warn('Encrypted offline cache save failed:', err);
      });
    }

    function load(id, password) {
      return get(id).then(function(record) {
        if (!record) throw new Error('没有可用的本地离线缓存');
        return deriveKey(password, b64ToBytes(record.salt)).then(function(key) {
          return crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64ToBytes(record.nonce) }, key, b64ToBytes(record.cipher));
        });
      }).then(function(plain) {
        return new TextDecoder().decode(plain);
      }).catch(function(err) {
        if (/本地离线缓存/.test(err.message || '')) throw err;
        throw new Error('本地缓存解密失败，密码可能不正确');
      });
    }

    return { save: save, load: load, supported: supported };
  })();

  if (IS_BOOK) {
    bookId = window.BOOK_ID;
    bookName = window.BOOK_NAME;
  } else {
    blogId = window.BLOG_ID;
    blogTitle = window.BLOG_TITLE;
    currentMarkdown = window.BLOG_CONTENT || '';
    currentDocType = window.BLOG_EDITOR_TYPE || 'markdown';
  }

  var statusbarPathItems = [];

  function formatStatusbarShortDate(timeStr) {
    var s = String(timeStr || '').trim();
    if (!s) return '';
    if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.substring(5, 10);
    return s.split(/\s+/)[0] || s;
  }

  function updateStatusbarModifyTime(timeStr) {
    var mtEl = document.getElementById('doc-modify-time');
    if (!mtEl) return;
    if (!timeStr) {
      mtEl.title = '';
      var emptyFullSpan = mtEl.querySelector('.statusbar-time-full');
      var emptyShortSpan = mtEl.querySelector('.statusbar-time-short');
      if (emptyFullSpan) emptyFullSpan.textContent = '';
      if (emptyShortSpan) emptyShortSpan.textContent = '';
      return;
    }
    mtEl.title = window.__('editor.doc.modify_time').replace('{time}', timeStr);
    var fullSpan = mtEl.querySelector('.statusbar-time-full');
    var shortSpan = mtEl.querySelector('.statusbar-time-short');
    if (fullSpan) fullSpan.textContent = window.__('editor.doc.modify_time').replace('{time}', timeStr);
    if (shortSpan) shortSpan.textContent = formatStatusbarShortDate(timeStr);
  }

  function setStatusbarDocTitle(title, pathItems) {
    var btn = document.getElementById('statusbar-doc-title');
    var text = String(title || '').trim();
    if (!btn) return;
    btn.textContent = text || (IS_BOOK ? (bookName || '') : (blogTitle || ''));
    btn.title = btn.textContent;
    btn.setAttribute('aria-label', btn.textContent);
    statusbarPathItems = (pathItems && pathItems.length ? pathItems : [{ name: btn.textContent }]).filter(function(item) {
      return item && String(item.name || '').trim();
    });
  }

  function closeStatusbarPathSheet() {
    var overlay = document.getElementById('statusbarPathOverlay');
    if (overlay) overlay.classList.remove('open');
  }

  function ensureStatusbarPathSheet() {
    var overlay = document.getElementById('statusbarPathOverlay');
    if (overlay) return overlay;
    overlay = document.createElement('div');
    overlay.id = 'statusbarPathOverlay';
    overlay.className = 'statusbar-path-overlay';
    overlay.innerHTML =
      '<div class="statusbar-path-sheet" role="dialog" aria-modal="true" aria-labelledby="statusbarPathTitle">' +
        '<div class="statusbar-path-header">' +
          '<span id="statusbarPathTitle">当前位置</span>' +
          '<button class="statusbar-path-close" type="button" aria-label="关闭"><i class="fa-solid fa-xmark"></i></button>' +
        '</div>' +
        '<div class="statusbar-path-list" id="statusbarPathList"></div>' +
      '</div>';
    overlay.addEventListener('click', function(event) {
      if (event.target === overlay) closeStatusbarPathSheet();
    });
    overlay.querySelector('.statusbar-path-close').addEventListener('click', closeStatusbarPathSheet);
    document.body.appendChild(overlay);
    return overlay;
  }

  function openStatusbarPathSheet() {
    var overlay = ensureStatusbarPathSheet();
    var list = overlay.querySelector('#statusbarPathList');
    var items = statusbarPathItems.length ? statusbarPathItems : [{ name: IS_BOOK ? bookName : blogTitle }];
    list.innerHTML = items.map(function(item, idx) {
      var clickable = IS_BOOK && item.id && item.id !== currentDocId;
      return '<button type="button" class="statusbar-path-item' + (clickable ? ' clickable' : '') + '" data-doc-id="' + (clickable ? item.id : '') + '">' +
        '<span class="statusbar-path-index">' + (idx + 1) + '</span>' +
        '<span class="statusbar-path-name">' + escHtml(item.name || '') + '</span>' +
      '</button>';
    }).join('');
    list.querySelectorAll('[data-doc-id]').forEach(function(btn) {
      var id = Number(btn.getAttribute('data-doc-id') || 0);
      if (!id) return;
      btn.addEventListener('click', function() {
        closeStatusbarPathSheet();
        loadDoc(id);
      });
    });
    overlay.classList.add('open');
  }
  window.openStatusbarPathSheet = openStatusbarPathSheet;
  window.closeStatusbarPathSheet = closeStatusbarPathSheet;

  setStatusbarDocTitle(IS_BOOK ? bookName : blogTitle, IS_BOOK ? [{ name: bookName }] : [{ name: '文章' }, { name: blogTitle }]);

  var activeSidebarTab = localStorage.getItem('bookstark_sidebar_tab') || (IS_BOOK ? 'tree' : 'outline');

  // ======== Shared: renderContent ========
  var cherryContainerReady = false;
  var onChangeCallback = function(md) {
    currentMarkdown = md;
    _previewNeedsRefresh = true;
    if (saveMgr) saveMgr.onContentChange();
    debouncedOutlineUpdate();
    BookStarkEditor.updateCharCount();
    updateEditorPlaceholder();
  };

  function ensureCherryContainer() {
    var editorArea = document.getElementById('editor-area');
    if (!editorArea) return;
    if (!cherryContainerReady) {
      editorArea.innerHTML = '<div id="cherry-container" style="height:100%"></div>';
      cherryContainerReady = true;
    }
  }

  function isEmptyContent(content) {
    return !content || !content.trim();
  }

  function showPreviewPlaceholder(container, docType) {
    var existing = container.querySelector('.doc-empty-placeholder');
    if (existing) return;
    var hint = docType === 'html' ? '开始编写 HTML 内容...' : '开始编写文档内容...';
    var el = document.createElement('div');
    el.className = 'doc-empty-placeholder';
    var inner = '<div class="doc-empty-placeholder-inner"><i class="fa-regular fa-file-lines"></i><p>' + hint + '</p>';
    // Show "AI 写一稿" call-to-action when:
    //  - markdown doc inside a book (chapter context available)
    //  - AI assistant globals are loaded (script + admin enabled flag is checked at call time)
    // Markdown / HTML 文本类文档都可触发 AI 起稿
    var effectiveType = docType || currentDocType;
    var canAIDraft = (effectiveType === 'markdown' || effectiveType === 'html')
      && window.AI_ENABLED === true
      && typeof window.openEditorAI === 'function'
      && (function() {
        var b = (typeof window.__bookGetEditorContext === 'function')
          ? window.__bookGetEditorContext() : null;
        if (b && b.chapterName) return true;
        // Article (blog) editor: BLOG_ID is injected only there.
        return !!(window.BLOG_ID && String(window.BLOG_TITLE || '').trim());
      })();
    if (canAIDraft) {
      var label = (window.__ && window.__('editor.ai.cta.draft')) || 'AI 写一稿';
      var inBook = (function() {
        var b = (typeof window.__bookGetEditorContext === 'function')
          ? window.__bookGetEditorContext() : null;
        return !!(b && b.chapterName);
      })();
      var hintKey;
      if (effectiveType === 'html') hintKey = 'editor.ai.cta.hint.html';
      else hintKey = inBook ? 'editor.ai.cta.hint' : 'editor.ai.cta.hint.article';
      var fallback;
      if (effectiveType === 'html') fallback = '基于章节/文章标题，生成一段可粘贴的 HTML';
      else fallback = inBook ? '基于本章标题与同书其他章节，生成一份初稿' : '基于文章标题与标签，生成一份初稿';
      var sub = (window.__ && window.__(hintKey)) || fallback;
      inner += '<button type="button" class="doc-empty-ai-btn" onclick="openEditorAI()">'
        + '<i class="fa-solid fa-wand-magic-sparkles"></i> ' + label
        + '</button>'
        + '<p class="doc-empty-ai-hint">' + sub + '</p>';
    }
    inner += '</div>';
    el.innerHTML = inner;
    container.appendChild(el);
  }

  function removePreviewPlaceholder(container) {
    var el = container.querySelector('.doc-empty-placeholder');
    if (el) el.remove();
  }

  function destroyMarkdownPreview() {
    closePreviewSearchPanel();
    closeMarkdownPreviewAI();
    if (cherryPreview) {
      try { cherryPreview.destroy(); } catch(e) {}
    }
    cherryPreview = null;
    window._cherryPreview = null;
  }

  function renderMarkdownPreview(previewArea) {
    if (!previewArea) return;
    destroyMarkdownPreview();
    previewArea.innerHTML = '<div id="cherry-preview"></div>';
    cherryPreview = BookStarkEditor.initPreview('cherry-preview', currentMarkdown);
    window._cherryPreview = cherryPreview;
  }

  function updateEditorPlaceholder() {
    // HTML editor textarea already has placeholder attribute set in initHtmlEditor
    // Cherry Markdown editor has its own editing area, no overlay needed
  }

  function renderContent() {
    // 同步顶栏按钮显隐（save / share / tag / ai / draft banner）。
    // 历史 bug：desktop 模式下 mode 初始 = 'preview' 和首次进入时 mode 不变，
    // switchMode/switchPagerPage 都不会触发，导致 ai-btn 永远停在 display:none。
    // 在每次 renderContent 时同步一次，覆盖所有 docType 与初次/切换路径。
    updateEditButtons(mode === 'preview');
    var previewArea = document.getElementById('preview-area');
    var editorArea = document.getElementById('editor-area');
    var editorPage = document.getElementById('editor-page');
    var previewPage = document.getElementById('preview-page');
    var excalidrawContainer = document.getElementById('excalidraw-container');
    if (excalidrawContainer) {
      excalidrawContainer.classList.add('hidden');
      excalidrawContainer.classList.remove('spreadsheet-fullwidth');
      excalidrawContainer.style.height = '';
    }
    var mindmapContainer = document.getElementById('mindmap-container');
    if (mindmapContainer) {
      mindmapContainer.classList.add('hidden');
      mindmapContainer.classList.remove('spreadsheet-fullwidth');
    }
    var univerContainer = document.getElementById('univer-container');
    if (univerContainer) {
      univerContainer.style.height = '';
    }
    var presentationContainer = document.getElementById('presentation-container');
    if (presentationContainer) {
      presentationContainer.classList.add('hidden');
      presentationContainer.classList.remove('presentation-fullwidth');
    }
    if (window.BookStarkPPTist) BookStarkPPTist.destroy();
    // Clean up mobile full-width from spreadsheet/drawing
    if (editorPage) editorPage.classList.remove('spreadsheet-mobile-full');
    if (previewPage) previewPage.style.display = '';
    document.body.classList.remove('compact-mode-toggle');
    if (currentDocType !== 'markdown') destroyMarkdownPreview();

    if (currentDocType === 'spreadsheet') {
      renderSpreadsheetContent();
      return;
    }

    if (currentDocType === 'presentation') {
      renderPresentationContent();
      return;
    }

    if (currentDocType === 'drawing') {
      renderDrawingContent();
      return;
    }

    if (currentDocType === 'mindmap') {
      renderMindmapContent();
      return;
    }

    if (currentDocType === 'html') {
      destroyMarkdownPreview();
      // Restore char-count hidden by spreadsheet mode
      var cc = document.getElementById('char-count');
      if (cc) cc.style.display = '';
      // Clean up spreadsheet mobile styles
      if (editorPage) editorPage.classList.remove('spreadsheet-mobile-full');
      if (previewPage) previewPage.style.display = '';
      renderHtmlContent(previewArea, editorArea, editorPage, previewPage);
      BookStarkEditor.updateCharCount();
      return;
    }

    if (currentDocType === 'richdoc') {
      destroyMarkdownPreview();
      if (previewArea) previewArea.classList.remove('html-fullwidth');
      if (previewPage) {
        previewPage.classList.remove('active-desktop');
        previewPage.style.display = 'none';
      }
      if (editorPage) {
        editorPage.classList.add('active-desktop');
        editorPage.classList.remove('spreadsheet-mobile-full');
      }
      var richTabs = document.querySelector('.pager-tabs');
      if (richTabs) richTabs.style.display = 'none';
      if (editorArea) {
        editorArea.style.display = '';
        if (!richdocEditor) {
          editorArea.innerHTML = '<div id="richdoc-container" class="richdoc-container"></div>';
          BookStarkRichDoc.mount('richdoc-container', currentMarkdown || BookStarkRichDoc.defaultContent(), {
            readonly: false,
            author: window.ACCOUNT || '当前用户',
            onChange: function() {
              if (!richdocEditor) return;
              try { currentMarkdown = richdocEditor.getContent(); } catch (e) { BookStarkEditor.toast(e.message, 'error'); return; }
              _previewNeedsRefresh = true;
              if (saveMgr) saveMgr.onContentChange();
            }
          }).then(function(instance) {
            richdocEditor = instance;
            window._richdocEditor = instance;
            richdocEditor.setReadonly(mode === 'preview');
          }).catch(function(error) { BookStarkEditor.toast(error.message || '富文档加载失败', 'error'); });
        } else {
          richdocEditor.setReadonly(mode === 'preview');
        }
      }
      var richCount = document.getElementById('char-count');
      if (richCount) richCount.style.display = 'none';
      return;
    }

    // Markdown documents: remove HTML fullwidth class
    if (previewArea) previewArea.classList.remove('html-fullwidth');
    // Clean up spreadsheet mobile styles
    if (editorPage) editorPage.classList.remove('spreadsheet-mobile-full');
    if (previewPage) previewPage.style.display = '';
    // Restore char-count hidden by spreadsheet mode
    var ccMd = document.getElementById('char-count');
    if (ccMd) ccMd.style.display = '';

    if (isMobile()) {
      // Mobile: both pages always rendered, pager controls visibility
      // Editor page
      ensureCherryContainer();
      if (!cherryEditor) {
        cherryEditor = BookStarkEditor.initCherry('cherry-container', currentMarkdown, onChangeCallback);
        window._cherryEditor = cherryEditor;
      } else {
        try { cherryEditor.setMarkdown(currentMarkdown); } catch(e) {}
      }
      // Preview page
      if (previewArea) {
        renderMarkdownPreview(previewArea);
        if (isEmptyContent(currentMarkdown)) showPreviewPlaceholder(previewArea, 'markdown');
        _previewNeedsRefresh = false;
      }
      // Set initial pager position based on mode
      if (mode === 'preview') {
        switchPagerPage('preview');
      } else {
        switchPagerPage('edit');
      }
    } else {
      // Desktop: show/hide pages
      if (mode === 'preview') {
        // Destroy editor instances before clearing their DOM so that
        // subsequent setMarkdown() calls don't silently fail on detached DOM.
        if (cherryEditor) { try { cherryEditor.destroy(); } catch(e) {} cherryEditor = null; window._cherryEditor = null; }
        if (htmlEditor) { try { htmlEditor.destroy(); } catch(e) {} htmlEditor = null; }
        if (previewPage) previewPage.classList.add('active-desktop');
        if (editorPage) editorPage.classList.remove('active-desktop');
        renderMarkdownPreview(previewArea);
        if (editorArea) editorArea.innerHTML = '';
        cherryContainerReady = false;
        if (previewArea && isEmptyContent(currentMarkdown)) showPreviewPlaceholder(previewArea, 'markdown');
      } else {
        if (editorPage) editorPage.classList.add('active-desktop');
        if (previewPage) previewPage.classList.remove('active-desktop');
        ensureCherryContainer();
        if (!cherryEditor) {
          cherryEditor = BookStarkEditor.initCherry('cherry-container', currentMarkdown, onChangeCallback);
          window._cherryEditor = cherryEditor;
        } else {
          try { cherryEditor.setMarkdown(currentMarkdown); } catch(e) {}
        }
      }
    }
    BookStarkEditor.updateCharCount();
    updateEditorPlaceholder();
  }

  function renderHtmlContent(previewArea, editorArea, editorPage, previewPage) {
    // HTML documents: preview area uses full width (no max-width constraint)
    if (previewArea) previewArea.classList.add('html-fullwidth');
    var htmlEmpty = isEmptyContent(currentMarkdown);

    // 确保 HTML 预览容器存在（复用已有容器，避免重建 iframe）
    function ensureHtmlPreviewContainer() {
      if (!previewArea) return;
      if (!previewArea.querySelector('#html-preview-container')) {
        previewArea.innerHTML = '<div id="html-preview-container"></div>';
      }
    }

    // 确保 HTML 编辑容器存在（复用已有容器）
    function ensureHtmlEditorContainer() {
      if (!editorArea) return;
      if (!editorArea.querySelector('#html-editor-container')) {
        editorArea.innerHTML = '<div id="html-editor-container" style="height:100%"></div>';
      }
    }

    function renderHtmlPreview() {
      ensureHtmlPreviewContainer();
      var container = previewArea.querySelector('#html-preview-container');
      if (htmlEmpty) {
        container.innerHTML = '';
        showPreviewPlaceholder(container, 'html');
      } else {
        removePreviewPlaceholder(container);
        BookStarkEditor.initHtmlPreview('html-preview-container', currentMarkdown);
      }
    }

    if (isMobile()) {
      // Mobile: editor page
      ensureHtmlEditorContainer();
      if (!htmlEditor) {
        htmlEditor = BookStarkEditor.initHtmlEditor('html-editor-container', currentMarkdown, onChangeCallback);
      } else {
        try { htmlEditor.setMarkdown(currentMarkdown); } catch(e) {}
      }
      // Preview page
      renderHtmlPreview();
      _previewNeedsRefresh = false;
      if (mode === 'preview') {
        switchPagerPage('preview');
      } else {
        switchPagerPage('edit');
      }
    } else {
      // Desktop
      if (mode === 'preview') {
        if (htmlEditor) { try { htmlEditor.destroy(); } catch(e) {} htmlEditor = null; }
        if (previewPage) previewPage.classList.add('active-desktop');
        if (editorPage) editorPage.classList.remove('active-desktop');
        renderHtmlPreview();
        if (editorArea) editorArea.innerHTML = '';
      } else {
        if (editorPage) editorPage.classList.add('active-desktop');
        if (previewPage) previewPage.classList.remove('active-desktop');
        ensureHtmlEditorContainer();
        if (!htmlEditor) {
          htmlEditor = BookStarkEditor.initHtmlEditor('html-editor-container', currentMarkdown, onChangeCallback);
        } else {
          try { htmlEditor.setMarkdown(currentMarkdown); } catch(e) {}
        }
      }
    }
    updateEditorPlaceholder();
  }

  function renderSpreadsheetContent() {
    // Reset abort flag — it was set during destroy of previous spreadsheet,
    // but we're now rendering a new one so initialization should proceed.
    BookStarkEditor._loadAborted = false;

    // Mark compact mode toggle for CSS targeting (show mode toggle in topbar on mobile)
    document.body.classList.add('compact-mode-toggle');

    var editorArea = document.getElementById('editor-area');
    var previewArea = document.getElementById('preview-area');
    var univerContainer = document.getElementById('univer-container');
    var editorPage = document.getElementById('editor-page');
    var previewPage = document.getElementById('preview-page');

    // Spreadsheet always shows in editor-page (univer-container lives there)
    if (editorPage) {
      editorPage.classList.add('active-desktop');
      editorPage.style.overflow = 'hidden';
    }
    if (previewPage) previewPage.classList.remove('active-desktop');

    if (editorArea) editorArea.style.display = 'none';
    if (previewArea) previewArea.style.display = 'none';

    if (univerContainer) {
      univerContainer.classList.remove('hidden');
      univerContainer.classList.add('spreadsheet-fullwidth');
    }

    // Enable mode toggle for spreadsheet (edit / preview)
    var modeToggle = document.getElementById('mode-toggle');
    if (modeToggle) {
      modeToggle.style.display = '';
      modeToggle.disabled = false;
      modeToggle.classList.remove('opacity-40', 'cursor-not-allowed');
    }
    var modeIcon = document.getElementById('mode-icon');
    var modeLabel = document.getElementById('mode-label');

    var isReadonly = (mode === 'preview');
    if (modeIcon) modeIcon.className = isReadonly ? 'fa-solid fa-eye' : 'fa-solid fa-pen-to-square';
    if (modeLabel) modeLabel.textContent = isReadonly ? window.__('editor.mode.preview') : window.__('editor.mode.edit');
    if (modeToggle) {
      if (isReadonly) {
        modeToggle.classList.add('active');
      } else {
        modeToggle.classList.remove('active');
      }
    }

    var charCount = document.getElementById('char-count');
    if (charCount) charCount.style.display = '';
    BookStarkEditor.updateCharCount();

    var outlinePanel = document.getElementById('outline-panel');
    if (outlinePanel) {
      var outlineContent = outlinePanel.querySelector('.outline-content');
      if (outlineContent) {
        outlineContent.innerHTML = '<p class="text-sm text-slate-500 p-4">' + window.__('editor.spreadsheet.no_outline') + '</p>';
      }
    }

    if (BookStarkEditor.isMobile()) {
      // Mobile: hide pager tabs FIRST so height calculation accounts for reclaimed space
      var pagerTabs = document.querySelector('.pager-tabs');
      if (pagerTabs) pagerTabs.style.display = 'none';
      var track = document.getElementById('pagerTrack');
      if (track) track.classList.remove('show-preview');
      // Set explicit height after layout reflow (pager-tabs hidden frees 40px)
      if (univerContainer) {
        requestAnimationFrame(function() {
          var pager = document.getElementById('contentPager');
          if (pager) {
            var ph = pager.getBoundingClientRect().height;
            if (ph > 10) univerContainer.style.height = ph + 'px';
            else univerContainer.style.height = '60vh';
          }
        });
      }
    } else if (univerContainer) {
      univerContainer.style.height = '';
    }

    // Initialize Univer with the current mode.
    var needsInit = !BookStarkEditor._univerRunning;
    var loading = document.getElementById('univer-loading');
    var sheet = document.getElementById('univer-sheet');
    if (needsInit) {
      if (loading) {
        loading.style.display = '';
        loading.innerHTML = '<div class="text-sm text-slate-500">' + window.__('editor.univer.loading') + '</div>';
      }
      if (sheet) sheet.style.visibility = 'hidden';
    }
    function showSpreadsheet() {
      if (sheet) sheet.style.visibility = '';
      if (loading) {
        loading.innerHTML = '';
        loading.style.display = 'none';
      }
    }
    if (needsInit) {
      if (window.UniverBookStark) {
        BookStarkEditor.initUniver('univer-sheet', currentMarkdown, { readonly: isReadonly });
      } else {
        BookStarkEditor.loadUniverAssets(function() {
          if (BookStarkEditor._loadAborted) {
            BookStarkEditor._loadAborted = false;
            return;
          }
          BookStarkEditor.initUniver('univer-sheet', currentMarkdown, { readonly: isReadonly });
        });
      }
    } else if (BookStarkEditor._univerRunning) {
      showSpreadsheet();
      // Viewport changed (e.g. desktop ←→ mobile) — recalc readonly layout
      // so work-area/container heights match the new viewport size.
      BookStarkEditor.applyUniverReadonly(mode === 'preview');
    }
  }

  function renderPresentationContent() {
    var editorArea = document.getElementById('editor-area');
    var previewArea = document.getElementById('preview-area');
    var editorPage = document.getElementById('editor-page');
    var previewPage = document.getElementById('preview-page');
    var container = document.getElementById('presentation-container');
    var modeToggle = document.getElementById('mode-toggle');
    var pagerTabs = document.querySelector('.pager-tabs');
    var charCount = document.getElementById('char-count');
    var outlinePanel = document.getElementById('outline-panel');

    document.body.classList.add('compact-mode-toggle');
    if (editorArea) editorArea.style.display = 'none';
    if (previewArea) previewArea.style.display = 'none';
    if (editorPage) {
      editorPage.classList.add('active-desktop', 'spreadsheet-mobile-full');
      editorPage.style.overflow = 'hidden';
    }
    if (previewPage) {
      previewPage.classList.remove('active-desktop');
      previewPage.style.display = 'none';
    }
    if (container) {
      container.classList.remove('hidden');
      container.classList.add('presentation-fullwidth');
    }
    if (modeToggle) modeToggle.style.display = 'none';
    if (pagerTabs) pagerTabs.style.display = 'none';
    if (charCount) charCount.style.display = 'none';
    if (outlinePanel) {
      var outlineContent = outlinePanel.querySelector('.outline-content');
      if (outlineContent) {
        outlineContent.innerHTML = '<p class="text-sm text-slate-500 p-4">' + window.__('editor.presentation.no_outline') + '</p>';
      }
    }

    var titleEl = document.querySelector('.breadcrumb-current');
    var title = titleEl ? titleEl.textContent.trim() : (blogTitle || window.__('editor.presentation.default_name'));
    BookStarkPPTist.mount('pptist-editor', currentMarkdown || BookStarkPPTist.defaultContent(title), {
      title: title,
      readonly: false,
      loadingText: window.__('editor.presentation.loading'),
      onChange: function(content) {
        currentMarkdown = content;
        _previewNeedsRefresh = true;
        if (saveMgr) saveMgr.onContentChange();
      }
    });
    updateEditButtons(false);
  }

  function renderDrawingContent() {
    BookStarkEditor._loadAborted = false;

    // Mark compact mode toggle for CSS targeting (show mode toggle in topbar on mobile)
    document.body.classList.add('compact-mode-toggle');

    var editorArea = document.getElementById('editor-area');
    var previewArea = document.getElementById('preview-area');
    var univerContainer = document.getElementById('univer-container');
    var excalidrawContainer = document.getElementById('excalidraw-container');
    var editorPage = document.getElementById('editor-page');
    var previewPage = document.getElementById('preview-page');

    if (editorPage) {
      editorPage.classList.add('active-desktop');
      editorPage.style.overflow = 'hidden';
    }
    if (previewPage) previewPage.classList.remove('active-desktop');

    if (editorArea) editorArea.style.display = 'none';
    if (previewArea) previewArea.style.display = 'none';
    if (univerContainer) univerContainer.classList.add('hidden');

    if (excalidrawContainer) {
      excalidrawContainer.classList.remove('hidden');
    }

    // Mode toggle
    var modeToggle = document.getElementById('mode-toggle');
    if (modeToggle) {
      modeToggle.style.display = '';
      modeToggle.disabled = false;
      modeToggle.classList.remove('opacity-40', 'cursor-not-allowed');
    }
    var modeIcon = document.getElementById('mode-icon');
    var modeLabel = document.getElementById('mode-label');
    var isReadonly = (mode === 'preview');
    if (modeIcon) modeIcon.className = isReadonly ? 'fa-solid fa-eye' : 'fa-solid fa-pen-to-square';
    if (modeLabel) modeLabel.textContent = isReadonly ? window.__('editor.mode.preview') : window.__('editor.mode.edit');
    if (modeToggle) {
      if (isReadonly) modeToggle.classList.add('active');
      else modeToggle.classList.remove('active');
    }

    // Char count — show element count
    var charCount = document.getElementById('char-count');
    if (charCount) charCount.style.display = '';
    updateDrawingCharCount();

    // Outline
    var outlinePanel = document.getElementById('outline-panel');
    if (outlinePanel) {
      var outlineContent = outlinePanel.querySelector('.outline-content');
      if (outlineContent) {
        outlineContent.innerHTML = '<p class="text-sm text-slate-500 p-4">' + window.__('editor.drawing.no_outline') + '</p>';
      }
    }

    // Mobile: hide pager tabs FIRST so height calculation accounts for reclaimed space
    if (BookStarkEditor.isMobile()) {
      var pagerTabs = document.querySelector('.pager-tabs');
      if (pagerTabs) pagerTabs.style.display = 'none';
      var track = document.getElementById('pagerTrack');
      if (track) track.classList.remove('show-preview');
      // Set explicit height after layout reflow (pager-tabs hidden frees 40px)
      if (excalidrawContainer) {
        requestAnimationFrame(function() {
          var pager = document.getElementById('contentPager');
          if (pager) {
            var ph = pager.getBoundingClientRect().height;
            if (ph > 10) excalidrawContainer.style.height = ph + 'px';
            else excalidrawContainer.style.height = '60vh';
          }
        });
      }
    } else if (excalidrawContainer) {
      excalidrawContainer.style.height = '';
    }

    // Init Excalidraw — use initExcalidraw (edit) or initExcalidrawPreview
    // (view mode with hand tool + zoom). Both are fast; assets stay loaded.
    var needsInit = !BookStarkEditor._excalidrawRunning;
    // Loading indicator on first init only
    var loading = document.getElementById('excalidraw-loading');
    var canvas = document.getElementById('excalidraw-canvas');
    if (needsInit) {
      if (loading) {
        loading.style.display = '';
        loading.innerHTML = '<div class="text-sm text-slate-500">' + window.__('editor.excalidraw.loading') + '</div>';
      }
      if (canvas) canvas.style.display = 'none';
    }

    function doInit() {
      if (canvas) canvas.style.display = '';
      if (isReadonly) {
        BookStarkEditor.initExcalidrawPreview('excalidraw-canvas', currentMarkdown);
      } else {
        // Skip the first onChange fire which happens during initial render
        // (Excalidraw fires onChange with the initial scene data on mount).
        var _excalidrawSkipFirst = true;
        BookStarkEditor.initExcalidraw('excalidraw-canvas', currentMarkdown, function() {
          if (_excalidrawSkipFirst) { _excalidrawSkipFirst = false; return; }
          BookStarkEditor.setDrawingDirty(true);
          if (saveMgr) saveMgr.onContentChange();
        });
      }
      if (loading) {
        loading.innerHTML = '';
        loading.style.display = 'none';
      }
      syncExcalidrawTheme();
      // On mobile (<= 768px), hide remaining toolbar in preview mode
      if (window.innerWidth <= 768 && isReadonly) {
        var styleId = 'excalidraw-preview-mobile';
        if (!document.getElementById(styleId)) {
          var s = document.createElement('style');
          s.id = styleId;
          s.textContent = '.excalidraw .App-menu_top, .excalidraw .layer-ui__wrapper { display: none !important; }';
          document.head.appendChild(s);
        }
      }
    }

    if (needsInit) {
      BookStarkEditor.loadExcalidrawAssets(function() {
        if (BookStarkEditor._loadAborted) {
          BookStarkEditor._loadAborted = false;
          return;
        }
        doInit();
      });
    } else {
      doInit();
    }
  }

  function renderMindmapContent() {
    BookStarkEditor._loadAborted = false;
    document.body.classList.add('compact-mode-toggle');
    var isReadonly = (mode === 'preview');
    var univerContainer = document.getElementById('univer-container');
    var excalidrawContainer = document.getElementById('excalidraw-container');
    var editorPage = document.getElementById('editor-page');
    var previewPage = document.getElementById('preview-page');
    if (univerContainer) univerContainer.classList.add('hidden');
    if (excalidrawContainer) excalidrawContainer.classList.add('hidden');

    var mindmapContainer = document.getElementById('mindmap-container');
    if (mindmapContainer) {
      mindmapContainer.classList.remove('hidden');
      mindmapContainer.classList.add('spreadsheet-fullwidth');
    }

    if (editorPage) {
      editorPage.classList.add('active-desktop');
      editorPage.classList.add('spreadsheet-mobile-full');
    }
    if (previewPage) previewPage.classList.remove('active-desktop');

    var ea = document.getElementById('editor-area');
    if (ea) ea.style.display = 'none';
    var pa = document.getElementById('preview-area');
    if (pa) pa.style.display = 'none';
    var cc = document.getElementById('char-count');
    if (cc) cc.style.display = 'none';

    // Show mode-toggle for mindmap (edit ↔ preview)
    var mt = document.getElementById('mode-toggle');
    var modeIcon = document.getElementById('mode-icon');
    var modeLabel = document.getElementById('mode-label');
    if (mt && modeIcon && modeLabel) {
      mt.style.display = '';
      if (mode === 'preview') {
        mt.classList.add('active');
        modeIcon.className = 'fa-solid fa-eye';
        modeIcon.style.marginRight = '3px';
        modeIcon.style.fontSize = '10px';
        modeLabel.textContent = window.__('editor.mode.preview');
      } else {
        mt.classList.remove('active');
        modeIcon.className = 'fa-solid fa-pen-to-square';
        modeIcon.style.marginRight = '3px';
        modeIcon.style.fontSize = '10px';
        modeLabel.textContent = window.__('editor.mode.edit');
      }
    }

    var pagerTabs = document.querySelector('.pager-tabs');
    if (pagerTabs) pagerTabs.style.display = 'none';

    if (!BookStarkEditor._mindElixirRunning) {
      var loading = document.getElementById('mindmap-loading');
      var mindEl = document.getElementById('mindmap-el');
      if (loading) loading.innerHTML = '<div class="text-sm text-slate-500">' + window.__('editor.mindmap.loading') + '</div>';
      if (mindEl) mindEl.style.visibility = 'hidden';
      BookStarkEditor.loadMindElixirAssets(function() {
        if (BookStarkEditor._loadAborted) return;
        var mind = BookStarkEditor.initMindElixir(currentMarkdown, { readonly: isReadonly });
        if (mind) {
          if (saveMgr) {
            mind.bus.addListener('operation', function() {
              if (mode !== 'preview') saveMgr.onContentChange();
            });
          }
        }
        if (mindEl) mindEl.style.visibility = '';
        if (loading) {
          loading.innerHTML = '';
          loading.style.display = 'none';
        }
      });
    } else {
      var existingMindEl = document.getElementById('mindmap-el');
      var existingLoading = document.getElementById('mindmap-loading');
      if (existingMindEl) existingMindEl.style.display = '';
      if (existingLoading) existingLoading.style.display = 'none';
    }
  }

  function updateDrawingCharCount() {
    var charCountEl = document.getElementById('char-count');
    if (!charCountEl) return;
    var count = 0;
    try {
      var data = JSON.parse(currentMarkdown);
      if (data && data.elements) count = data.elements.length;
    } catch(e) {}
    var label = charCountEl.querySelector('.statusbar-text-label');
    charCountEl.innerHTML = (label ? label.outerHTML : '') + count + ' 个元素';
  }

  function syncExcalidrawTheme() {
    if (!window.BookStarkExcalidraw) return;
    var theme = document.documentElement.getAttribute('data-theme');
    window.BookStarkExcalidraw.setTheme(theme === 'dark' ? 'dark' : 'light');
  }

  var previewSearchState = { panel: null, input: null, count: null, matches: [], index: -1 };

  function tryOpenCherrySearch(instance) {
    if (!instance) return false;
    try {
      if (instance.toolbar && instance.toolbar.toolbarHandlers && typeof instance.toolbar.toolbarHandlers.search === 'function') {
        instance.toolbar.toolbarHandlers.search();
      }
      if (instance.searchBoxInstance && typeof instance.searchBoxInstance.isVisible === 'function' && instance.searchBoxInstance.isVisible() && hasVisibleCherrySearchInput()) {
        focusCherrySearchInput();
        return true;
      }
    } catch(e) {}
    try {
      if (instance.searchBoxInstance && typeof instance.searchBoxInstance.show === 'function') {
        instance.searchBoxInstance.show();
        if (hasVisibleCherrySearchInput()) {
          focusCherrySearchInput();
          return true;
        }
      }
    } catch(e) {}
    return false;
  }

  function focusCherrySearchInput() {
    setTimeout(function() {
      var input = document.querySelector('.ace_search_field');
      if (input) {
        input.focus();
        input.select();
      }
    }, 0);
  }

  function hasVisibleCherrySearchInput() {
    var input = document.querySelector('.ace_search_field');
    return !!(input && (input.offsetWidth || input.offsetHeight || input.getClientRects().length));
  }

  function ensurePreviewSearchPanel() {
    var previewArea = document.getElementById('preview-area');
    if (!previewArea) return null;
    if (previewSearchState.panel && document.body.contains(previewSearchState.panel)) return previewSearchState.panel;

    var panel = document.createElement('div');
    panel.className = 'preview-search-panel';
    panel.id = 'previewSearchPanel';
    panel.innerHTML =
      '<i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>' +
      '<input type="search" class="preview-search-input" id="previewSearchInput" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">' +
      '<span class="preview-search-count" id="previewSearchCount">0/0</span>' +
      '<button type="button" class="preview-search-icon-btn" id="previewSearchPrev" aria-label="Prev"><i class="fa-solid fa-chevron-up"></i></button>' +
      '<button type="button" class="preview-search-icon-btn" id="previewSearchNext" aria-label="Next"><i class="fa-solid fa-chevron-down"></i></button>' +
      '<button type="button" class="preview-search-icon-btn" id="previewSearchClose" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>';
    previewArea.insertBefore(panel, previewArea.firstChild);

    previewSearchState.panel = panel;
    previewSearchState.input = panel.querySelector('#previewSearchInput');
    previewSearchState.count = panel.querySelector('#previewSearchCount');
    previewSearchState.input.placeholder = window.__ ? window.__('editor.preview.search.placeholder') : 'Search preview content';
    previewSearchState.input.addEventListener('input', runPreviewSearch);
    previewSearchState.input.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (e.shiftKey) movePreviewSearch(-1); else movePreviewSearch(1);
      } else if (e.key === 'Escape') {
        closePreviewSearchPanel();
      }
    });
    panel.querySelector('#previewSearchPrev').addEventListener('click', function() { movePreviewSearch(-1); });
    panel.querySelector('#previewSearchNext').addEventListener('click', function() { movePreviewSearch(1); });
    panel.querySelector('#previewSearchClose').addEventListener('click', closePreviewSearchPanel);
    return panel;
  }

  function openMarkdownPreviewSearch() {
    if (currentDocType !== 'markdown') return;
    if (tryOpenCherrySearch(cherryPreview)) return;
    if (!isMobile() && tryOpenCherrySearch(cherryEditor)) return;
    var panel = ensurePreviewSearchPanel();
    if (!panel) return;
    var input = previewSearchState.input;
    if (input) {
      input.focus();
      input.select();
      runPreviewSearch();
    }
  }
  window.openMarkdownPreviewSearch = openMarkdownPreviewSearch;

  var previewAIState = { panel: null, ctrl: null, contextRange: null, contextText: '', contextKind: '', cleanupDrag: null, cleanupSelection: null, cleanupHighlight: null, cleanupViewport: null };

  function syncPreviewAIViewportHeight() {
    var panel = previewAIState.panel;
    if (!panel || !document.body.contains(panel)) return;
    var vv = window.visualViewport;
    var height = vv && vv.height ? vv.height : (window.innerHeight || document.documentElement.clientHeight || 0);
    if (height > 0) {
      panel.style.setProperty('--preview-ai-viewport-height', Math.round(height) + 'px');
    }
    if (isMobile()) {
      panel.style.left = '';
      panel.style.right = '';
      panel.style.top = '';
      panel.style.bottom = '';
    }
  }

  function bindPreviewAIViewportSync() {
    syncPreviewAIViewportHeight();
    var visualViewport = window.visualViewport;
    if (visualViewport && visualViewport.addEventListener) {
      visualViewport.addEventListener('resize', syncPreviewAIViewportHeight);
      visualViewport.addEventListener('scroll', syncPreviewAIViewportHeight);
    }
    window.addEventListener('resize', syncPreviewAIViewportHeight);
    return function() {
      if (visualViewport && visualViewport.removeEventListener) {
        visualViewport.removeEventListener('resize', syncPreviewAIViewportHeight);
        visualViewport.removeEventListener('scroll', syncPreviewAIViewportHeight);
      }
      window.removeEventListener('resize', syncPreviewAIViewportHeight);
    };
  }

  function closeMarkdownPreviewAI() {
    if (previewAIState.ctrl) {
      try { previewAIState.ctrl.abort(); } catch(e) {}
      previewAIState.ctrl = null;
    }
    if (previewAIState.cleanupDrag) {
      try { previewAIState.cleanupDrag(); } catch(e) {}
      previewAIState.cleanupDrag = null;
    }
    if (previewAIState.cleanupSelection) {
      try { previewAIState.cleanupSelection(); } catch(e) {}
      previewAIState.cleanupSelection = null;
    }
    if (previewAIState.cleanupViewport) {
      try { previewAIState.cleanupViewport(); } catch(e) {}
      previewAIState.cleanupViewport = null;
    }
    clearPreviewAISelectionHighlight();
    if (previewAIState.panel && previewAIState.panel.parentNode) {
      previewAIState.panel.parentNode.removeChild(previewAIState.panel);
    }
    previewAIState.panel = null;
    previewAIState.contextRange = null;
    previewAIState.contextText = '';
    previewAIState.contextKind = '';
  }

  function escapePreviewAIHTML(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function summarizePreviewAIText(text) {
    text = String(text || '').replace(/\s+/g, ' ').trim();
    return text.length > 180 ? text.slice(0, 180) + '...' : text;
  }

  function renderPreviewAIMarkdown(el, text) {
    if (!el) return;
    el.classList.add('note-content');
    if (typeof marked !== 'undefined' && marked.parse) {
      el.innerHTML = marked.parse(String(text || ''));
    } else {
      el.textContent = String(text || '');
    }
  }

  function copyPreviewAIMessage(btn) {
    var msg = btn && btn.closest ? btn.closest('.preview-ai-message') : null;
    var raw = msg ? (msg.getAttribute('data-raw') || msg.innerText || '') : '';
    raw = raw.trim();
    if (!raw) return;
    function done() {
      btn.classList.add('copied');
      btn.innerHTML = '<i class="fa-solid fa-check"></i>';
      setTimeout(function() {
        btn.classList.remove('copied');
        btn.innerHTML = '<i class="fa-regular fa-copy"></i>';
      }, 1000);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(raw).then(done, function() {});
      return;
    }
    var ta = document.createElement('textarea');
    ta.value = raw;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch(e) {}
    document.body.removeChild(ta);
  }

  function getMarkdownPreviewRoot() {
    var previewRoot = document.getElementById('cherry-preview');
    if (previewRoot) return previewRoot.querySelector('.cherry-previewer') || previewRoot;
    return document.getElementById('preview-area');
  }

  function getMarkdownPreviewText() {
    var root = getMarkdownPreviewRoot();
    var text = root ? root.innerText : '';
    if (!String(text || '').trim()) text = currentMarkdown || '';
    return String(text || '').trim();
  }

  function getMarkdownPreviewSelection() {
    var root = getMarkdownPreviewRoot();
    var sel = window.getSelection ? window.getSelection() : null;
    if (!root || !sel || sel.rangeCount === 0) return null;
    var text = String(sel.toString() || '').trim();
    if (!text) return null;
    var range = sel.getRangeAt(0);
    var common = range.commonAncestorContainer;
    var host = common && (common.nodeType === 1 ? common : common.parentElement);
    if (!host || !root.contains(host)) return null;
    return { text: text, range: range.cloneRange(), kind: 'selection' };
  }

  function locateMarkdownPreviewSelection() {
    var range = previewAIState.contextRange;
    if (!range || previewAIState.contextKind !== 'selection') return false;
    var root = getMarkdownPreviewRoot();
    if (!root) return false;
    try {
      var sel = window.getSelection();
      if (sel) {
        sel.removeAllRanges();
        sel.addRange(range);
      }
      renderPreviewAISelectionHighlight(range);
      var rect = range.getBoundingClientRect();
      var previewArea = document.getElementById('preview-area') || root;
      if (rect && previewArea) {
        var areaRect = previewArea.getBoundingClientRect();
        var nextTop = previewArea.scrollTop + (rect.top - areaRect.top) - (previewArea.clientHeight / 2);
        previewArea.scrollTo({ top: Math.max(0, nextTop), behavior: 'smooth' });
      }
      if (root.focus) {
        if (!root.hasAttribute('tabindex')) root.setAttribute('tabindex', '-1');
        root.focus({ preventScroll: true });
      }
      return true;
    } catch(e) {
      return false;
    }
  }

  function clearPreviewAISelectionHighlight() {
    if (window.CSS && CSS.highlights && CSS.highlights.delete) {
      try { CSS.highlights.delete('preview-ai-selection'); } catch(e) {}
    }
    if (previewAIState.cleanupHighlight) {
      try { previewAIState.cleanupHighlight(); } catch(e) {}
      previewAIState.cleanupHighlight = null;
    }
    var layer = document.querySelector('.preview-ai-selection-overlay');
    if (layer && layer.parentNode) layer.parentNode.removeChild(layer);
  }

  function renderPreviewAISelectionHighlight(range) {
    clearPreviewAISelectionHighlight();
    if (!range) return;
    if (window.CSS && CSS.highlights && window.Highlight) {
      try {
        CSS.highlights.set('preview-ai-selection', new Highlight(range));
        return;
      } catch(e) {}
    }

    var layer = document.createElement('div');
    layer.className = 'preview-ai-selection-overlay';
    document.body.appendChild(layer);

    function paint() {
      layer.innerHTML = '';
      var rects = [];
      try { rects = Array.prototype.slice.call(range.getClientRects()); } catch(e) { rects = []; }
      rects.forEach(function(rect) {
        if (!rect || rect.width <= 0 || rect.height <= 0) return;
        var mark = document.createElement('div');
        mark.className = 'preview-ai-selection-rect';
        mark.style.left = rect.left + 'px';
        mark.style.top = rect.top + 'px';
        mark.style.width = rect.width + 'px';
        mark.style.height = rect.height + 'px';
        layer.appendChild(mark);
      });
    }

    paint();
    window.addEventListener('resize', paint);
    document.addEventListener('scroll', paint, true);
    previewAIState.cleanupHighlight = function() {
      window.removeEventListener('resize', paint);
      document.removeEventListener('scroll', paint, true);
    };
  }

  function buildPreviewAIPrompt(userPrompt) {
    var ctx = previewAIState.contextText || '';
    if (ctx) {
      return '【阅读上下文】\n' + ctx + '\n\n【问题】\n' + userPrompt;
    }
    return userPrompt;
  }

  function ensureMarkdownPreviewAI() {
    if (previewAIState.panel && document.body.contains(previewAIState.panel)) return previewAIState.panel;

    var panel = document.createElement('section');
    panel.className = 'preview-ai-panel';
    panel.id = 'previewAIPanel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-modal', 'false');
    panel.setAttribute('aria-label', '阅读助手');
    panel.innerHTML =
      '<div class="preview-ai-header">' +
        '<div class="preview-ai-title"><i class="fa-solid fa-wand-magic-sparkles"></i><span>阅读助手</span></div>' +
        '<div class="preview-ai-window-actions">' +
          '<button type="button" class="preview-ai-maximize" aria-label="最大化" title="最大化" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
          '<button type="button" class="preview-ai-toggle" aria-label="收起" title="收起">_</button>' +
          '<button type="button" class="preview-ai-close" aria-label="关闭" title="关闭"><i class="fa-solid fa-xmark"></i></button>' +
        '</div>' +
      '</div>' +
      '<div class="preview-ai-context-strip">' +
        '<div class="preview-ai-context-actions">' +
          '<button type="button" class="preview-ai-chip" data-context="full">全文</button>' +
          '<button type="button" class="preview-ai-chip" data-context="clear">清空</button>' +
        '</div>' +
        '<span class="preview-ai-context-badge">未选择上下文</span>' +
      '</div>' +
      '<div class="preview-ai-conversation" aria-live="polite"></div>' +
      '<form class="preview-ai-composer">' +
        '<textarea class="preview-ai-input" rows="3" placeholder="问一个和当前文档有关的问题..."></textarea>' +
        '<div class="preview-ai-composer-actions">' +
          '<div class="preview-ai-suggestion-row"></div>' +
          '<div class="preview-ai-submit-actions">' +
            '<button type="submit" class="preview-ai-send">发送</button>' +
            '<button type="button" class="preview-ai-stop" style="display:none;">停止</button>' +
          '</div>' +
        '</div>' +
      '</form>';
    document.body.appendChild(panel);

    var maxBtn = panel.querySelector('.preview-ai-maximize');
    var toggleBtn = panel.querySelector('.preview-ai-toggle');
    panel.querySelector('.preview-ai-close').addEventListener('click', closeMarkdownPreviewAI);
    maxBtn.addEventListener('click', function() {
      setPreviewAIMaximized(panel, !panel.classList.contains('preview-ai-maximized'), maxBtn);
    });
    toggleBtn.addEventListener('click', function() {
      var nextCollapsed = !panel.classList.contains('drawing-ai-collapsed');
      setPreviewAICollapsed(panel, nextCollapsed, toggleBtn);
    });
    panel.querySelector('[data-context="full"]').addEventListener('click', function() {
      var text = getMarkdownPreviewText();
      if (!text) {
        if (window.BSDialog) BSDialog.toast('当前文档没有内容', 'warning');
        return;
      }
      setPreviewAIContext('full', text, null);
    });
    panel.querySelector('[data-context="clear"]').addEventListener('click', function() {
      try {
        var sel = window.getSelection && window.getSelection();
        if (sel) sel.removeAllRanges();
      } catch(e) {}
      setPreviewAIContext('', '', null);
    });
    panel.querySelector('.preview-ai-context-badge').addEventListener('click', function(e) {
      if (!e.target || !e.target.closest || !e.target.closest('.preview-ai-context-locator')) return;
      locateMarkdownPreviewSelection();
    });
    panel.querySelector('.preview-ai-conversation').addEventListener('click', function(e) {
      var btn = e.target && e.target.closest ? e.target.closest('.preview-ai-copy') : null;
      if (btn) copyPreviewAIMessage(btn);
    });
    panel.querySelector('.preview-ai-composer').addEventListener('submit', function(e) {
      e.preventDefault();
      sendPreviewAI();
    });
    panel.querySelector('.preview-ai-input').addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        sendPreviewAI();
      }
    });
    panel.querySelector('.preview-ai-stop').addEventListener('click', function() {
      if (previewAIState.ctrl) {
        try { previewAIState.ctrl.abort(); } catch(e) {}
        previewAIState.ctrl = null;
      }
      setPreviewAIRunning(false);
    });

    previewAIState.panel = panel;
    previewAIState.cleanupDrag = _makeDrawingAIDraggable(panel, '.preview-ai-header');
    previewAIState.cleanupSelection = bindPreviewAISelectionSync();
    previewAIState.cleanupViewport = bindPreviewAIViewportSync();
    return panel;
  }

  function bindPreviewAISelectionSync() {
    var timer = null;
    function schedule() {
      if (timer) clearTimeout(timer);
      timer = setTimeout(function() {
        var panel = previewAIState.panel;
        if (!panel || !document.body.contains(panel)) return;
        var active = document.activeElement;
        if (active && panel.contains(active)) return;
        var sel = getMarkdownPreviewSelection();
        if (sel) setPreviewAIContext('selection', sel.text, sel.range);
      }, 80);
    }
    document.addEventListener('selectionchange', schedule);
    document.addEventListener('mouseup', schedule, true);
    document.addEventListener('keyup', schedule, true);
    return function() {
      if (timer) clearTimeout(timer);
      document.removeEventListener('selectionchange', schedule);
      document.removeEventListener('mouseup', schedule, true);
      document.removeEventListener('keyup', schedule, true);
    };
  }

  function getPreviewAIActions() {
    if (previewAIState.contextText && previewAIState.contextKind === 'selection') {
      return [
        { label: '解释这段', prompt: '请解释这段内容的含义，并指出它在全文中的作用。' },
        { label: '提炼要点', prompt: '请把这段内容提炼成 3-5 个要点。' },
        { label: '继续追问', prompt: '请基于这段内容提出 5 个值得继续追问的问题。' },
        { label: '反向质疑', prompt: '请从反方或审稿人的角度质疑这段内容。' }
      ];
    }
    return [
      { label: '总结全文', prompt: '请总结全文，先给一句话结论，再列出 5 个核心要点。' },
      { label: '找漏洞', prompt: '请检查全文的逻辑漏洞、证据不足和表达含混之处。' },
      { label: '提问题', prompt: '请基于全文提出 8 个可以继续研究或写作的问题。' },
      { label: '给结论', prompt: '请提炼全文可以直接采用的结论和行动建议。' }
    ];
  }

  function renderPreviewAISuggestions() {
    var panel = previewAIState.panel;
    if (!panel) return;
    var row = panel.querySelector('.preview-ai-suggestion-row');
    var actions = getPreviewAIActions();
    row.innerHTML = actions.map(function(a, i) {
      return '<button type="button" class="preview-ai-suggestion" data-idx="' + i + '">' + escapePreviewAIHTML(a.label) + '</button>';
    }).join('');
    Array.prototype.forEach.call(row.querySelectorAll('.preview-ai-suggestion'), function(btn) {
      btn.addEventListener('click', function() {
        var action = actions[parseInt(btn.getAttribute('data-idx'), 10)];
        if (!action) return;
        var input = panel.querySelector('.preview-ai-input');
        input.value = action.prompt;
        input.focus();
      });
    });
  }

  function setPreviewAIContext(kind, text, range) {
    var panel = previewAIState.panel;
    if (!panel) return;
    text = String(text || '').trim();
    previewAIState.contextKind = text ? kind : '';
    previewAIState.contextText = text;
    previewAIState.contextRange = (kind === 'selection' && range) ? range : null;
    if (previewAIState.contextRange) {
      renderPreviewAISelectionHighlight(previewAIState.contextRange);
    } else {
      clearPreviewAISelectionHighlight();
    }
    var badge = panel.querySelector('.preview-ai-context-badge');
    if (text) {
      if (kind === 'selection') {
        badge.innerHTML = '<button type="button" class="preview-ai-context-locator" title="定位到选区">选区</button> · ' + text.length + ' 字';
      } else {
        badge.textContent = '全文 · ' + text.length + ' 字';
      }
    } else {
      badge.textContent = '未选择上下文';
    }
    renderPreviewAISuggestions();
  }

  function appendPreviewAIMessage(role, text) {
    var panel = previewAIState.panel;
    if (!panel) return null;
    var list = panel.querySelector('.preview-ai-conversation');
    var msg = document.createElement('div');
    msg.className = 'preview-ai-message ' + (role === 'user' ? 'from-user' : 'from-ai');
    if (role === 'ai') {
      msg.classList.add('note-content');
      msg.setAttribute('data-raw', text || '');
      var copy = document.createElement('button');
      copy.type = 'button';
      copy.className = 'preview-ai-copy';
      copy.title = '复制';
      copy.setAttribute('aria-label', '复制 AI 回复');
      copy.innerHTML = '<i class="fa-regular fa-copy"></i>';
      var content = document.createElement('div');
      content.className = 'preview-ai-message-content';
      msg.appendChild(copy);
      msg.appendChild(content);
      renderPreviewAIMarkdown(content, text || '');
    } else {
      msg.textContent = text || '';
    }
    list.appendChild(msg);
    list.scrollTop = list.scrollHeight;
    return msg;
  }

  function updatePreviewAIMessage(el, text) {
    if (!el) return;
    el.setAttribute('data-raw', text || '');
    var content = el.querySelector('.preview-ai-message-content') || el;
    renderPreviewAIMarkdown(content, text || '');
  }

  function setPreviewAIMaximized(panel, maximized, btn) {
    if (!panel) return;
    maximized = !!maximized;
    var toggleBtn = panel.querySelector('.preview-ai-toggle');
    if (maximized && panel.classList.contains('drawing-ai-collapsed')) setPreviewAICollapsed(panel, false, toggleBtn);
    if (maximized && !panel.classList.contains('preview-ai-maximized')) {
      panel._previewAICompactStyle = _snapshotAIFloatStyle(panel);
      _clearAIFloatBoxStyle(panel);
    } else if (!maximized && panel._previewAICompactStyle) {
      _applyAIFloatStyle(panel, panel._previewAICompactStyle);
      panel._previewAICompactStyle = null;
    }
    panel.classList.toggle('preview-ai-maximized', maximized);
    if (btn) {
      btn.setAttribute('aria-pressed', maximized ? 'true' : 'false');
      btn.setAttribute('aria-label', maximized ? '还原' : '最大化');
      btn.setAttribute('title', maximized ? '还原' : '最大化');
      btn.innerHTML = '<i class="fa-solid ' + (maximized ? 'fa-compress' : 'fa-expand') + '"></i>';
    }
  }

  function setPreviewAICollapsed(panel, collapsed, toggleBtn) {
    if (!panel) return;
    collapsed = !!collapsed;
    var maxBtn = panel.querySelector('.preview-ai-maximize');
    if (collapsed && panel.classList.contains('preview-ai-maximized')) setPreviewAIMaximized(panel, false, maxBtn);
    _setAIFloatCollapsed(panel, collapsed, toggleBtn);
  }

  function setPreviewAIRunning(on) {
    var panel = previewAIState.panel;
    if (!panel) return;
    var send = panel.querySelector('.preview-ai-send');
    var stop = panel.querySelector('.preview-ai-stop');
    var input = panel.querySelector('.preview-ai-input');
    send.style.display = on ? 'none' : '';
    stop.style.display = on ? '' : 'none';
    input.disabled = on;
    Array.prototype.forEach.call(panel.querySelectorAll('.preview-ai-chip,.preview-ai-suggestion'), function(btn) {
      btn.disabled = on;
    });
  }

  function sendPreviewAI() {
    var panel = previewAIState.panel;
    if (!panel || typeof AIHelper === 'undefined') return;
    var input = panel.querySelector('.preview-ai-input');
    var prompt = String(input.value || '').trim();
    if (!prompt) {
      input.focus();
      return;
    }
    if (!previewAIState.contextText) {
      var sel = getMarkdownPreviewSelection();
      if (sel) setPreviewAIContext('selection', sel.text, sel.range);
    }
    appendPreviewAIMessage('user', prompt);
    input.value = '';
    var aiMsg = appendPreviewAIMessage('ai', '思考中...');
    var systemPrompt = (_buildEditorSystemPrompt('markdown') || '') + '\n你现在处于 Markdown 预览阅读模式。回答用户关于文档内容的问题，不要输出编辑器操作指令。';
    setPreviewAIRunning(true);
    var generated = '';
    previewAIState.ctrl = AIHelper.complete({
      messages: AIHelper.buildMessages(systemPrompt, buildPreviewAIPrompt(prompt)),
      scene: 'editor_preview',
      onChunk: function(_chunk, full) {
        generated = full || generated;
        updatePreviewAIMessage(aiMsg, generated || '思考中...');
        var list = panel.querySelector('.preview-ai-conversation');
        if (list) list.scrollTop = list.scrollHeight;
      },
      onDone: function(full) {
        previewAIState.ctrl = null;
        generated = full || generated;
        updatePreviewAIMessage(aiMsg, generated.trim() || '没有生成内容');
        setPreviewAIRunning(false);
      },
      onError: function(msg) {
        previewAIState.ctrl = null;
        aiMsg.textContent = msg || (window.__('note.ai.toast.error') || 'AI 调用失败');
        aiMsg.classList.add('is-error');
        setPreviewAIRunning(false);
      }
    });
  }

  function openMarkdownPreviewAI() {
    if (currentDocType !== 'markdown') return;
    if (typeof AIHelper === 'undefined') {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    refreshPreview();
    var panel = ensureMarkdownPreviewAI();
    syncPreviewAIViewportHeight();
    panel.classList.add('open');
    syncPreviewAIViewportHeight();
    var selected = getMarkdownPreviewSelection();
    if (selected) {
      setPreviewAIContext('selection', selected.text, selected.range);
    } else if (!previewAIState.contextText) {
      setPreviewAIContext('', '', null);
    } else {
      setPreviewAIContext(previewAIState.contextKind, previewAIState.contextText, previewAIState.contextRange);
    }
    var input = panel.querySelector('.preview-ai-input');
    setTimeout(function() { if (input) input.focus(); }, 30);
  }
  window.openMarkdownPreviewAI = openMarkdownPreviewAI;

  function closePreviewSearchPanel() {
    clearPreviewSearchHighlights();
    if (previewSearchState.panel && previewSearchState.panel.parentNode) {
      previewSearchState.panel.parentNode.removeChild(previewSearchState.panel);
    }
    previewSearchState.panel = null;
    previewSearchState.input = null;
    previewSearchState.count = null;
    previewSearchState.matches = [];
    previewSearchState.index = -1;
  }

  function clearPreviewSearchHighlights() {
    var root = document.getElementById('preview-area');
    if (!root) return;
    var marks = Array.prototype.slice.call(root.querySelectorAll('mark.preview-search-hit'));
    marks.forEach(function(mark) {
      var parent = mark.parentNode;
      if (!parent) return;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    });
    previewSearchState.matches = [];
    previewSearchState.index = -1;
  }

  function runPreviewSearch() {
    var input = previewSearchState.input;
    var query = input ? input.value : '';
    var previewRoot = document.getElementById('cherry-preview');
    var preview = previewRoot ? (previewRoot.querySelector('.cherry-previewer') || previewRoot) : null;
    clearPreviewSearchHighlights();
    if (!preview || !query) {
      updatePreviewSearchCount();
      return;
    }
    var needle = query.toLowerCase();
    var nodes = [];
    var walker = document.createTreeWalker(preview, NodeFilter.SHOW_TEXT, {
      acceptNode: function(node) {
        var text = node.nodeValue || '';
        if (!text || text.toLowerCase().indexOf(needle) === -1) return NodeFilter.FILTER_REJECT;
        var parent = node.parentElement;
        if (!parent) return NodeFilter.FILTER_REJECT;
        if (parent.closest('.preview-search-panel,.preview-search-hit,script,style,textarea,input,button')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    while (walker.nextNode()) nodes.push(walker.currentNode);

    nodes.forEach(function(node) {
      var text = node.nodeValue || '';
      var lower = text.toLowerCase();
      var frag = document.createDocumentFragment();
      var cursor = 0;
      var idx = lower.indexOf(needle);
      while (idx !== -1) {
        if (idx > cursor) frag.appendChild(document.createTextNode(text.slice(cursor, idx)));
        var mark = document.createElement('mark');
        mark.className = 'preview-search-hit';
        mark.textContent = text.slice(idx, idx + query.length);
        frag.appendChild(mark);
        previewSearchState.matches.push(mark);
        cursor = idx + query.length;
        idx = lower.indexOf(needle, cursor);
      }
      if (cursor < text.length) frag.appendChild(document.createTextNode(text.slice(cursor)));
      if (node.parentNode) node.parentNode.replaceChild(frag, node);
    });

    if (previewSearchState.matches.length > 0) {
      previewSearchState.index = 0;
      activatePreviewSearchMatch();
    } else {
      updatePreviewSearchCount();
    }
  }

  function movePreviewSearch(delta) {
    var total = previewSearchState.matches.length;
    if (!total) {
      runPreviewSearch();
      return;
    }
    previewSearchState.index = (previewSearchState.index + delta + total) % total;
    activatePreviewSearchMatch();
  }

  function activatePreviewSearchMatch() {
    previewSearchState.matches.forEach(function(el) { el.classList.remove('active'); });
    var active = previewSearchState.matches[previewSearchState.index];
    if (active) {
      active.classList.add('active');
      active.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
    }
    updatePreviewSearchCount();
  }

  function updatePreviewSearchCount() {
    if (!previewSearchState.count) return;
    var total = previewSearchState.matches.length;
    if (!total && previewSearchState.input && previewSearchState.input.value) {
      previewSearchState.count.textContent = window.__ ? window.__('editor.preview.search.no_match') : 'No matches';
    } else {
      previewSearchState.count.textContent = total ? ((previewSearchState.index + 1) + '/' + total) : '0/0';
    }
  }

  // ======== Shared: switchMode ========
  function updateEditButtons(isPreview) {
    var saveBtn = document.getElementById('save-btn');
    var shareBtn = document.getElementById('share-btn');
    var tagBtn = document.getElementById('tagToggleBtn');
    var aiBtn = document.getElementById('ai-btn');
    var previewSearchBtn = document.getElementById('preview-search-btn');
    var draftBanner = document.getElementById('draft-banner');
    if (saveBtn) saveBtn.style.display = isPreview ? 'none' : '';
    if (shareBtn) shareBtn.style.display = isPreview ? 'none' : '';
    if (tagBtn) tagBtn.style.display = isPreview ? 'none' : '';
    if (previewSearchBtn) previewSearchBtn.style.display = (isPreview && currentDocType === 'markdown') ? '' : 'none';
    // AI 按钮在文本类文档和画板文档显示；画板使用专门的 Excalidraw skeleton 生成链路。
    if (aiBtn) {
      var aiSupported = currentDocType === 'markdown' || currentDocType === 'html' || currentDocType === 'drawing' || currentDocType === 'richdoc';
      var previewAISupported = isPreview && currentDocType === 'markdown';
      aiBtn.style.display = (!aiSupported || (isPreview && !previewAISupported)) ? 'none' : '';
      if (!previewAISupported && previewAIState.panel) closeMarkdownPreviewAI();
    }
    if (draftBanner) draftBanner.style.display = isPreview ? 'none' : '';
  }

  function switchMode(m) {
    if (m === mode) return;
    // Sync content from editor before switching away
    if (cherryEditor) {
      currentMarkdown = cherryEditor.getMarkdown();
    }
    if (htmlEditor) {
      currentMarkdown = htmlEditor.getMarkdown();
    }
    if (currentDocType === 'richdoc') {
      mode = m;
      if (richdocEditor) richdocEditor.setReadonly(mode === 'preview');
      var richToggle = document.getElementById('mode-toggle');
      var richIcon = document.getElementById('mode-icon');
      var richLabel = document.getElementById('mode-label');
      if (richToggle && richIcon && richLabel) {
        richToggle.classList.toggle('active', mode === 'preview');
        richIcon.className = mode === 'preview' ? 'fa-solid fa-eye' : 'fa-solid fa-pen-to-square';
        richLabel.textContent = window.__(mode === 'preview' ? 'editor.mode.preview' : 'editor.mode.edit');
      }
      updateEditButtons(mode === 'preview');
      return;
    }
    // For spreadsheet/drawing/mindmap, save current content and re-init in the new mode
    if (currentDocType === 'spreadsheet' || currentDocType === 'drawing' || currentDocType === 'mindmap') {
      if (currentDocType === 'spreadsheet') {
        var content = BookStarkEditor.getSpreadsheetContent();
        if (content) currentMarkdown = content;
      } else if (currentDocType === 'drawing') {
        var drawingContent = BookStarkEditor.getDrawingContent();
        if (drawingContent) currentMarkdown = drawingContent;
      } else if (currentDocType === 'mindmap') {
        var mindData = BookStarkEditor.getMindElixirData();
        if (mindData) currentMarkdown = mindData;
      }
      mode = m;
      if (currentDocType === 'spreadsheet') {
        if (BookStarkEditor._univerRunning) {
          BookStarkEditor.applyUniverReadonly(mode === 'preview');
        } else {
          BookStarkEditor.destroyUniver();
          var container = document.getElementById('univer-sheet');
          if (container) container.innerHTML = '';
          var loading = document.getElementById('univer-loading');
          if (loading) loading.style.display = '';
          BookStarkEditor.loadUniverAssets(function() {
            if (BookStarkEditor._loadAborted) {
              BookStarkEditor._loadAborted = false;
              return;
            }
            renderSpreadsheetContent();
          });
        }
      } else if (currentDocType === 'mindmap') {
        // Destroy and re-init with new editable setting
        BookStarkEditor.destroyMindElixir();
        var mindEl = document.getElementById('mindmap-el');
        if (mindEl) mindEl.innerHTML = '';
        var mindLoading = document.getElementById('mindmap-loading');
        if (mindLoading) { mindLoading.style.display = ''; mindLoading.innerHTML = ''; }
        renderMindmapContent();
      } else {
        // Excalidraw: destroy instance but keep assets loaded,
        // then re-init in the new mode.
        BookStarkEditor.destroyExcalidraw(true); /* keepAssets */
        renderDrawingContent();
      }
      // Update toggle UI
      var toggleBtn = document.getElementById('mode-toggle');
      var modeIcon = document.getElementById('mode-icon');
      var modeLabel = document.getElementById('mode-label');
      if (toggleBtn && modeIcon && modeLabel) {
        if (mode === 'preview') {
          toggleBtn.classList.add('active');
          modeIcon.className = 'fa-solid fa-eye';
          modeLabel.textContent = window.__('editor.mode.preview');
        } else {
          toggleBtn.classList.remove('active');
          modeIcon.className = 'fa-solid fa-pen-to-square';
          modeLabel.textContent = window.__('editor.mode.edit');
        }
      }
      updateEditButtons(mode === 'preview');
      // Mobile: keep pager on editor page for spreadsheet/drawing (they render there)
      if (isMobile()) {
        var track = document.getElementById('pagerTrack');
        if (track) track.classList.remove('show-preview');
      }
      return;
    }
    mode = m;

    var toggleBtn = document.getElementById('mode-toggle');
    var modeIcon = document.getElementById('mode-icon');
    var modeLabel = document.getElementById('mode-label');
    if (toggleBtn && modeIcon && modeLabel) {
      if (mode === 'preview') {
        toggleBtn.classList.add('active');
        modeIcon.className = 'fa-solid fa-eye';
        modeLabel.textContent = window.__('editor.mode.preview');
      } else {
        toggleBtn.classList.remove('active');
        modeIcon.className = 'fa-solid fa-pen-to-square';
        modeLabel.textContent = window.__('editor.mode.edit');
      }
    }
    updateEditButtons(mode === 'preview');

    if (isMobile()) {
      // Mobile: control pager position
      switchPagerPage(mode === 'preview' ? 'preview' : 'edit');
    } else {
      renderContent();
    }
  }
  window.switchMode = switchMode;

  function toggleMode() {
    switchMode(mode === 'preview' ? 'edit' : 'preview');
  }
  window.toggleMode = toggleMode;

  // ======== Mobile: Pager Functions ========
  function switchPagerPage(page) {
    var track = document.getElementById('pagerTrack');
    var tabEdit = document.getElementById('tabEdit');
    var tabPreview = document.getElementById('tabPreview');
    var indicator = document.getElementById('pagerIndicator');
    if (!track) return;

    // Spreadsheet/Drawing/Mindmap: delegate to switchMode for proper init/destroy
    if (currentDocType === 'spreadsheet' || currentDocType === 'drawing' || currentDocType === 'mindmap') {
      var targetMode = page === 'preview' ? 'preview' : 'edit';
      if (targetMode !== mode) {
        switchMode(targetMode);
      }
      // switchMode handles pager positioning, just update tabs/indicator here
      if (page === 'preview') {
        if (tabEdit) tabEdit.classList.remove('active');
        if (tabPreview) tabPreview.classList.add('active');
        if (indicator) indicator.classList.add('right');
      } else {
        if (tabEdit) tabEdit.classList.add('active');
        if (tabPreview) tabPreview.classList.remove('active');
        if (indicator) indicator.classList.remove('right');
      }
      currentPagerPage = page;
      return;
    }

    if (page === 'preview') {
      track.classList.add('show-preview');
      if (tabEdit) tabEdit.classList.remove('active');
      if (tabPreview) tabPreview.classList.add('active');
      if (indicator) indicator.classList.add('right');
      refreshPreview();
      // Sync mode state
      mode = 'preview';
      var toggleBtn = document.getElementById('mode-toggle');
      var modeIcon = document.getElementById('mode-icon');
      var modeLabel = document.getElementById('mode-label');
      if (toggleBtn && modeIcon && modeLabel) {
        toggleBtn.classList.add('active');
        modeIcon.className = 'fa-solid fa-eye';
        modeLabel.textContent = window.__('editor.mode.preview');
      }
      updateEditButtons(true);
    } else {
      track.classList.remove('show-preview');
      if (tabEdit) tabEdit.classList.add('active');
      if (tabPreview) tabPreview.classList.remove('active');
      if (indicator) indicator.classList.remove('right');
      // Sync mode state
      mode = 'edit';
      var toggleBtn2 = document.getElementById('mode-toggle');
      var modeIcon2 = document.getElementById('mode-icon');
      var modeLabel2 = document.getElementById('mode-label');
      if (toggleBtn2 && modeIcon2 && modeLabel2) {
        toggleBtn2.classList.remove('active');
        modeIcon2.className = 'fa-solid fa-pen-to-square';
        modeLabel2.textContent = window.__('editor.mode.edit');
      }
      updateEditButtons(false);
    }
    currentPagerPage = page;
  }
  window.switchPagerPage = switchPagerPage;

  function refreshPreview() {
    if (currentDocType === 'spreadsheet') return;
    if (!_previewNeedsRefresh) return;
    var previewArea = document.getElementById('preview-area');
    if (!previewArea) return;
    // Sync content from editor before previewing
    if (cherryEditor) {
      currentMarkdown = cherryEditor.getMarkdown();
    }
    if (htmlEditor) {
      currentMarkdown = htmlEditor.getMarkdown();
    }
    if (currentDocType === 'html') {
      if (!previewArea.querySelector('#html-preview-container')) {
        previewArea.innerHTML = '<div id="html-preview-container"></div>';
      }
      var container = previewArea.querySelector('#html-preview-container');
      if (isEmptyContent(currentMarkdown)) {
        container.innerHTML = '';
        showPreviewPlaceholder(container, 'html');
      } else {
        removePreviewPlaceholder(container);
        BookStarkEditor.initHtmlPreview('html-preview-container', currentMarkdown);
      }
    } else {
      renderMarkdownPreview(previewArea);
      if (isEmptyContent(currentMarkdown)) showPreviewPlaceholder(previewArea, 'markdown'); else removePreviewPlaceholder(previewArea);
    }
    _previewNeedsRefresh = false;
  }

  function setupPagerSwipe() {
    var pager = document.getElementById('contentPager');
    if (!pager) return;
    var startX = 0, startY = 0, isHorizontalSwipe = false;
    pager.addEventListener('touchstart', function(e) {
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      isHorizontalSwipe = false;
    }, { passive: true });
    pager.addEventListener('touchmove', function(e) {
      var dx = e.touches[0].clientX - startX;
      var dy = e.touches[0].clientY - startY;
      if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 10) {
        isHorizontalSwipe = true;
      }
    }, { passive: true });
    pager.addEventListener('touchend', function(e) {
      if (!isHorizontalSwipe) return;
      if (currentDocType === 'spreadsheet' || currentDocType === 'drawing' || currentDocType === 'mindmap') return;
      if (currentDocType === 'presentation') return;
      var dx = e.changedTouches[0].clientX - startX;
      if (dx < -50 && currentPagerPage === 'edit') switchPagerPage('preview');
      if (dx > 50 && currentPagerPage === 'preview') switchPagerPage('edit');
    }, { passive: true });
  }

  // ======== Shared: Draft recovery banner ========
  function onSpecialDocContentChange() {
    if (currentDocType === 'drawing') {
      BookStarkEditor.setDrawingDirty(true);
    }
    if (saveMgr) saveMgr.onContentChange();
    BookStarkEditor.updateCharCount();
  }

  function applyDraftContentToActiveEditor(content) {
    currentMarkdown = content || '';
    _previewNeedsRefresh = true;

    if (currentDocType === 'markdown') {
      if (cherryEditor) {
        try { cherryEditor.setMarkdown(currentMarkdown); } catch(e) {}
      } else {
        renderContent();
      }
    } else if (currentDocType === 'html') {
      if (htmlEditor) {
        try { htmlEditor.setMarkdown(currentMarkdown); } catch(e) {}
      } else {
        renderContent();
      }
    } else if (currentDocType === 'spreadsheet') {
      BookStarkEditor.loadSpreadsheetData(content, { readonly: mode === 'preview' });
    } else if (currentDocType === 'drawing') {
      BookStarkEditor.loadDrawingData(content, { readonly: mode === 'preview', onChange: onSpecialDocContentChange });
    } else if (currentDocType === 'mindmap') {
      BookStarkEditor.loadMindElixirData(content, { readonly: mode === 'preview', onChange: onSpecialDocContentChange });
    } else if (currentDocType === 'presentation') {
      BookStarkPPTist.setContent(content);
    } else {
      renderContent();
    }

    BookStarkEditor.updateCharCount();
  }

  function showDraftBanner(serverContent, draftContent) {
    hideDraftBanner();
    var container = document.getElementById('contentPager');
    if (!container) return;
    var banner = document.createElement('div');
    banner.className = 'draft-banner';
    banner.id = 'draft-banner';
    if (mode === 'preview') banner.style.display = 'none';
    banner.innerHTML =
      '<i class="fa-solid fa-clock-rotate-left"></i>' +
      '<span class="draft-banner-text">检测到未保存的草稿，是否恢复？</span>' +
      '<div class="draft-banner-actions">' +
        '<button class="draft-banner-btn restore" id="draft-restore-btn">恢复草稿</button>' +
        '<button class="draft-banner-btn discard" id="draft-discard-btn">丢弃草稿</button>' +
      '</div>';
    container.parentNode.insertBefore(banner, container);
    document.getElementById('draft-restore-btn').onclick = function() {
      applyDraftContentToActiveEditor(draftContent);
      if (saveMgr) saveMgr.setSaveStatus('unsaved');
      hideDraftBanner();
      BookStarkEditor.toast('已恢复草稿', 'success');
    };
    document.getElementById('draft-discard-btn').onclick = function() {
      applyDraftContentToActiveEditor(serverContent);
      if (saveMgr) {
        saveMgr.discardDraft();
        saveMgr.setLastSaved(serverContent);
      }
      hideDraftBanner();
      BookStarkEditor.updateCharCount();
      BookStarkEditor.toast('已丢弃草稿', 'success');
    };
  }

  function hideDraftBanner() {
    var b = document.getElementById('draft-banner');
    if (b) b.parentNode.removeChild(b);
  }

  // ======== Shared: manualSave ========
  function manualSave() {
    if (cherryEditor) {
      currentMarkdown = cherryEditor.getMarkdown();
    }
    if (htmlEditor) {
      currentMarkdown = htmlEditor.getMarkdown();
    }
    if (currentDocType === 'spreadsheet') {
      var content = BookStarkEditor.getSpreadsheetContent();
      if (content) currentMarkdown = content;
    }
    if (currentDocType === 'presentation' && window.BookStarkPPTist) {
      currentMarkdown = BookStarkPPTist.getContent() || currentMarkdown;
    }
    if (saveMgr) saveMgr.manualSave();
  }
  window.manualSave = manualSave;

  function setupEditorBackConfirm() {
    var backBtn = document.getElementById('editorBackBtn');
    if (!backBtn) return;
    backBtn.addEventListener('click', function(e) {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      e.preventDefault();
      var target = backBtn.getAttribute('href') || '/';
      var status = saveMgr && saveMgr.getSaveStatus ? saveMgr.getSaveStatus() : 'saved';
      var msg = (status === 'unsaved' || status === 'saving')
        ? '当前内容还没有完成保存，确定要返回吗？'
        : '确定离开编辑器并返回上一页吗？';
      var confirmFn = window.BSDialog && typeof BSDialog.confirm2 === 'function'
        ? BSDialog.confirm2(msg)
        : Promise.resolve(window.confirm(msg));
      confirmFn.then(function(ok) {
        if (ok) window.location.href = target;
      });
    });
  }

  // ======== Shared: AI assistant ========
  function _getEditorSelection() {
    // Cherry exposes its internal CodeMirror 6 view at
    // cherryEditor.editor.editor.view (private API but stable across
    // recent versions). Fallback to the .cm-editor DOM .cmView in case
    // future cherry versions move it.
    if (cherryEditor) {
      var view = null;
      try {
        view = cherryEditor.editor && cherryEditor.editor.editor && cherryEditor.editor.editor.view;
      } catch (e) {}
      if (!view) {
        var cmRoot = document.querySelector('#cherry-container .cm-editor');
        view = cmRoot && cmRoot.cmView && cmRoot.cmView.view;
      }
      if (view && view.state) {
        var sel = view.state.selection.main;
        var doc = view.state.doc;
        var text = doc.sliceString(sel.from, sel.to);
        return { text: text, from: sel.from, to: sel.to, view: view, kind: 'cm' };
      }
    }
    if (htmlEditor) {
      // Our html editor is also CM6-backed via window.CMHtml. We expose the
      // view directly via getView() — preferred path. Fallback to DOM lookup.
      var hv = null;
      try { hv = htmlEditor.getView && htmlEditor.getView(); } catch (e) {}
      if (!hv) {
        var hr = document.querySelector('#html-editor-container .cm-editor');
        hv = hr && hr.cmView && hr.cmView.view;
      }
      if (hv && hv.state) {
        var hs = hv.state.selection.main;
        return { text: hv.state.doc.sliceString(hs.from, hs.to), from: hs.from, to: hs.to, view: hv, kind: 'cm' };
      }
    }
    if (currentDocType === 'richdoc' && richdocEditor) {
      return { text: richdocEditor.getSelectionText(), kind: 'richdoc' };
    }
    return null;
  }

  function _getEditorFullRange() {
    if (cherryEditor && currentDocType === 'markdown') {
      var sel = _getEditorSelection();
      if (sel && sel.view && sel.view.state && sel.view.state.doc) {
        return {
          text: sel.view.state.doc.toString(),
          from: 0,
          to: sel.view.state.doc.length,
          view: sel.view,
          kind: 'cm'
        };
      }
      var md = '';
      try { md = cherryEditor.getMarkdown ? cherryEditor.getMarkdown() : cherryEditor.getValue(); } catch(e) {}
      return { text: md || '', from: 0, to: (md || '').length, view: null, kind: 'fallback' };
    }
    if (htmlEditor && currentDocType === 'html') {
      var hsel = _getEditorSelection();
      if (hsel && hsel.view && hsel.view.state && hsel.view.state.doc) {
        return {
          text: hsel.view.state.doc.toString(),
          from: 0,
          to: hsel.view.state.doc.length,
          view: hsel.view,
          kind: 'cm'
        };
      }
      var html = '';
      try { html = htmlEditor.getMarkdown(); } catch(e) {}
      return { text: html || '', from: 0, to: (html || '').length, view: null, kind: 'fallback' };
    }
    if (currentDocType === 'richdoc' && richdocEditor) {
      var richText = richdocEditor.getText();
      return { text: richText || '', from: 0, to: (richText || '').length, view: null, kind: 'richdoc', full: true };
    }
    return { text: currentMarkdown || '', from: 0, to: (currentMarkdown || '').length, view: null, kind: 'fallback' };
  }

  function _selectEditorRange(range, center) {
    if (!range || !range.view || !range.view.state) return false;
    var docLen = range.view.state.doc.length;
    var from = Math.max(0, Math.min(docLen, Number(range.from) || 0));
    var to = Math.max(from, Math.min(docLen, Number(range.to) || from));
    range.view.dispatch({ selection: { anchor: from, head: to } });
    if (center && range.view.scrollDOM && range.view.coordsAtPos) {
      try {
        var coords = range.view.coordsAtPos(from) || range.view.coordsAtPos(to);
        var scroller = range.view.scrollDOM;
        if (coords && scroller) {
          var scrollRect = scroller.getBoundingClientRect();
          var nextTop = scroller.scrollTop + (coords.top - scrollRect.top) - (scroller.clientHeight / 2);
          scroller.scrollTo({ top: Math.max(0, nextTop), behavior: 'smooth' });
        }
      } catch(e) {}
    }
    try { range.view.focus(); } catch(e) {}
    return true;
  }

  function _clearEditorSelection(range) {
    var sel = _getEditorSelection();
    var target = (sel && sel.view && sel.view.state) ? sel : range;
    if (!target || !target.view || !target.view.state) return false;
    var docLen = target.view.state.doc.length;
    var pos = Math.max(0, Math.min(docLen, Number(target.to) || Number(target.from) || 0));
    target.view.dispatch({ selection: { anchor: pos, head: pos } });
    try { target.view.focus(); } catch(e) {}
    return true;
  }

  function _syncEditorAfterMutation() {
    try {
      if (cherryEditor && currentDocType === 'markdown') currentMarkdown = cherryEditor.getMarkdown();
      else if (htmlEditor && currentDocType === 'html') currentMarkdown = htmlEditor.getMarkdown();
      else if (richdocEditor && currentDocType === 'richdoc') currentMarkdown = richdocEditor.getContent();
    } catch(e) {}
    if (saveMgr) saveMgr.onContentChange();
  }

  function _replaceEditorRange(text, range) {
    text = String(text || '');
    if (mode === 'preview') {
      switchMode('edit');
      setTimeout(function() { _replaceEditorRange(text, range); }, 120);
      return;
    }
    if (currentDocType === 'richdoc' && richdocEditor) {
      richdocEditor.insertAIText(text, true, !!(range && range.full));
      _syncEditorAfterMutation();
      return true;
    }
    if (range && range.view && range.view.state) {
      var docLen = range.view.state.doc.length;
      var from = Math.max(0, Math.min(docLen, Number(range.from) || 0));
      var to = Math.max(from, Math.min(docLen, Number(range.to) || from));
      range.view.dispatch({
        changes: { from: from, to: to, insert: text },
        selection: { anchor: from + text.length }
      });
      try { range.view.focus(); } catch(e) {}
      _syncEditorAfterMutation();
      return true;
    }
    return false;
  }

  function _insertIntoEditorAtCursor(text) {
    text = String(text || '');
    if (currentDocType === 'richdoc' && richdocEditor) {
      richdocEditor.insertAIText(text, false);
      _syncEditorAfterMutation();
      return true;
    }
    var sel = _getEditorSelection();
    if (sel && sel.view && sel.view.state) {
      var pos = Math.max(0, Math.min(sel.view.state.doc.length, Number(sel.to) || 0));
      sel.view.dispatch({
        changes: { from: pos, to: pos, insert: text },
        selection: { anchor: pos + text.length }
      });
      try { sel.view.focus(); } catch(e) {}
      _syncEditorAfterMutation();
      return true;
    }
    return false;
  }

  function _insertIntoEditor(text, insertMode) {
    // If we are in preview mode, the editor instances are destroyed.
    // Switch to edit mode first, then retry insertion once the editor mounts.
    if (mode === 'preview') {
      switchMode('edit');
      // Allow renderContent + cherry/html editor to mount.
      var attempts = 0;
      var retry = function() {
        attempts++;
        var ready = (currentDocType === 'html' && htmlEditor)
          || (currentDocType !== 'html' && cherryEditor);
        if (ready) { _insertIntoEditor(text, insertMode); return; }
        if (attempts < 30) setTimeout(retry, 100);
      };
      setTimeout(retry, 100);
      return;
    }
    if (cherryEditor && currentDocType === 'markdown') {
      var sel = _getEditorSelection();
      if (sel && sel.view) {
        if (insertMode === 'append') {
          _insertIntoEditorAtCursor(text);
        } else {
          _replaceEditorRange(text, sel);
        }
        return;
      }
      // Fallback: append to end via cherry API
      var v = cherryEditor.getValue();
      cherryEditor.setValue(insertMode === 'replace' ? text : (v + (v && !v.endsWith('\n') ? '\n\n' : '') + text));
      currentMarkdown = cherryEditor.getMarkdown();
      if (saveMgr) saveMgr.onContentChange();
      return;
    }
    if (htmlEditor && currentDocType === 'html') {
      var hsel = _getEditorSelection();
      if (hsel && hsel.view) {
        if (insertMode === 'append') {
          _insertIntoEditorAtCursor(text);
        } else {
          _replaceEditorRange(text, hsel);
        }
        return;
      }
      // Fallback for html editor
      var hv = htmlEditor.getMarkdown();
      htmlEditor.setMarkdown(insertMode === 'replace' ? text : (hv + (hv && !hv.endsWith('\n') ? '\n\n' : '') + text));
      currentMarkdown = htmlEditor.getMarkdown();
      if (saveMgr) saveMgr.onContentChange();
    }
  }

  window.__insertEditorText = function(text) {
    if (!text) return;
    _insertIntoEditor(String(text), 'append');
  };

  // Read the current article (blog) context: title + active labels.
  // Returns null when not in a blog editor or title is missing.
  function _getArticleContext() {
    if (!window.BLOG_ID || !window.BLOG_TITLE) return null;
    var title = String(window.BLOG_TITLE || '').trim();
    if (!title) return null;
    var labels = [];
    var chips = document.querySelectorAll('#tagRow .tag-chip[data-tag]');
    for (var i = 0; i < chips.length; i++) {
      var t = chips[i].getAttribute('data-tag');
      if (t) labels.push(t);
    }
    return { title: title, labels: labels };
  }

  // Build a system prompt that bakes in surrounding context (book chapter
  // siblings or article title/tags), so AI continuations feel coherent.
  function _buildEditorSystemPrompt(docType) {
    if (typeof docType === 'boolean') docType = docType ? 'html' : 'markdown';
    docType = docType || currentDocType || 'markdown';
    // Admin-configured system prompt wins, then i18n string, then hard-coded default.
    var base;
    if (docType === 'html') {
      base = window.AI_SYSTEM_PROMPT_HTML || window.__('editor.ai.system.html') || '你是一个 HTML 文档协作助手。回复直接给出可粘贴的 HTML 片段，不要包含解释。';
    } else if (docType === 'drawing') {
      base = window.AI_SYSTEM_PROMPT_DRAWING || window.__('editor.ai.system.drawing') || '你是一个画板/白板协作助手。围绕当前画板内容提供结构、布局、流程图、草图和视觉表达建议。回复简洁、可直接执行。';
    } else {
      base = window.AI_SYSTEM_PROMPT_MD || window.__('editor.ai.system.md') || '你是一个 Markdown 文档协作助手。回复使用 Markdown，简洁、信息密度高，不要寒暄。';
    }
    var bookCtx = (typeof window.__bookGetEditorContext === 'function')
      ? window.__bookGetEditorContext() : null;
    if (bookCtx && bookCtx.chapterName) {
      var lines = ['', '【当前书籍上下文（请基于此保持风格连贯，不要在输出里复述上下文）】'];
      if (bookCtx.bookName) lines.push('书籍: ' + bookCtx.bookName);
      if (bookCtx.parentChain && bookCtx.parentChain.length) lines.push('章节路径: ' + bookCtx.parentChain.join(' › '));
      lines.push('当前章节: ' + bookCtx.chapterName);
      if (bookCtx.siblings && bookCtx.siblings.length) {
        var sibs = bookCtx.siblings.slice(0, 12);
        lines.push('同级其他章节: ' + sibs.join('、') + (bookCtx.siblings.length > 12 ? ' ...' : ''));
      }
      return base + '\n' + lines.join('\n');
    }
    var artCtx = _getArticleContext();
    if (artCtx) {
      var aLines = ['', '【当前文章上下文（请基于此保持风格连贯，不要在输出里复述上下文）】'];
      aLines.push('文章标题: ' + artCtx.title);
      if (artCtx.labels.length) aLines.push('标签: ' + artCtx.labels.join('、'));
      return base + '\n' + aLines.join('\n');
    }
    return base;
  }

  // Run a one-shot AI transform on the current selection. Used by the
  // Cherry bubble menu items so they can fire-and-forget without opening
  // the full AI dialog.
  window.__runEditorAIQuickAction = function(actionPrompt, optSelectionText) {
    if (typeof AIHelper === 'undefined') {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    var sel = _getEditorSelection();
    var text = (sel && sel.text) || (optSelectionText || '');
    if (!text) {
      if (window.BSDialog) BSDialog.toast(window.__('editor.ai.toast.no_selection') || '请先选中要处理的文本', 'warning');
      return;
    }
    var sysPrompt = _buildEditorSystemPrompt(currentDocType);
    var user = actionPrompt + '\n\n【选中文本】\n' + text;
    if (window.BSDialog) BSDialog.toast(window.__('editor.ai.toast.running') || 'AI 处理中…', 'info', 1500);

    // 流式增量插入：第一次 chunk 替换原选区，后续 chunk 追加到已插入文本末尾。
    // insertedLen 记录已插入到编辑器的累计长度，下一次 chunk 从 sel.from + insertedLen 处插入。
    var insertedLen = 0;
    var firstChunk = true;
    AIHelper.complete({
      messages: AIHelper.buildMessages(sysPrompt, user),
      scene: 'editor_inline',
      onChunk: function(chunk) {
        if (!chunk || !sel || !sel.view) return;
        try {
          if (firstChunk) {
            sel.view.dispatch({
              changes: { from: sel.from, to: sel.to, insert: chunk }
            });
            firstChunk = false;
          } else {
            var pos = sel.from + insertedLen;
            sel.view.dispatch({
              changes: { from: pos, to: pos, insert: chunk }
            });
          }
          insertedLen += chunk.length;
        } catch (e) {}
      },
      onDone: function(fullText) {
        if (firstChunk) {
          // 没收到任何 chunk
          if (window.BSDialog) BSDialog.toast(window.__('editor.ai.toast.empty') || 'AI 未返回内容', 'warning');
          return;
        }
        if (sel && sel.view) {
          try { sel.view.dispatch({ selection: { anchor: sel.from + insertedLen } }); } catch(e) {}
          try { sel.view.focus(); } catch(e) {}
          try { if (cherryEditor && cherryEditor.getMarkdown) currentMarkdown = cherryEditor.getMarkdown(); } catch(e) {}
          if (saveMgr) saveMgr.onContentChange();
          if (window.BSDialog) BSDialog.toast(window.__('editor.ai.toast.done') || '已替换', 'success');
        }
      },
      onError: function(msg) {
        // 流式过程中出错：保留已插入部分，但同步状态以便保存
        if (insertedLen > 0) {
          try { if (cherryEditor && cherryEditor.getMarkdown) currentMarkdown = cherryEditor.getMarkdown(); } catch(e) {}
          if (saveMgr) saveMgr.onContentChange();
        }
        if (window.BSDialog) BSDialog.toast(msg || (window.__('note.ai.toast.error') || 'AI 调用失败'), 'error');
      }
    });
  };

  function _extractDrawingSkeletonJSON(text) {
    var source = String(text || '').trim();
    source = source.replace(/^```(?:json|javascript|js)?\s*/i, '').replace(/\s*```$/i, '').trim();
    var start = source.indexOf('[');
    if (start < 0) throw new Error('AI 未返回 JSON 数组');
    var out = '';
    var stack = [];
    var inString = false;
    var escape = false;
    for (var i = start; i < source.length; i++) {
      var ch = source.charAt(i);
      out += ch;
      if (escape) { escape = false; continue; }
      if (ch === '\\') { escape = true; continue; }
      if (ch === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (ch === '[') stack.push(']');
      else if (ch === '{') stack.push('}');
      else if ((ch === ']' || ch === '}') && stack.length) {
        stack.pop();
        if (!stack.length) break;
      }
    }
    if (inString) out += '"';
    out = out.replace(/,\s*$/g, '');
    while (stack.length) out += stack.pop();
    return JSON.parse(out);
  }

  function _drawingAISystemPrompt() {
    var base = (window.AI_SYSTEM_PROMPT_DRAWING || window.__('editor.ai.system.drawing') || '你是一个画板/白板协作助手。围绕当前画板内容提供结构、布局、流程图、草图和视觉表达建议。回复简洁、可直接执行。').trim();
    var outputContract = [
      '【智能画图输出协议】',
      '直接输出 ExcalidrawElementSkeleton JSON 数组，不要解释，不要 Markdown，不要代码围栏。',
      '不要推理过程。第一个字符必须是 [，最后一个字符必须是 ]。',
      '元素只用 rectangle/ellipse/diamond/text/line/arrow/frame。',
      '形状字段：type,x,y,width,height,strokeColor,backgroundColor,label。',
      'label 示例：{"text":"节点","fontSize":18}。',
      '箭头字段：type:"arrow",x,y,width,height,start:{id:"a"},end:{id:"b"},endArrowhead:"arrow"。',
      '需要箭头连接的节点必须有 id。布局清晰，避免重叠。'
    ].join('\n');
    return base ? (base + '\n\n' + outputContract) : outputContract;
  }

  function _drawingAIUserPrompt(input, chartType, currentScene) {
    var chartText = chartType && chartType !== 'auto' ? ('图表类型：' + chartType + '\n') : '图表类型：自动选择\n';
    var sceneHint = '';
    try {
      var parsed = currentScene ? JSON.parse(currentScene) : null;
      var count = parsed && parsed.elements ? parsed.elements.length : 0;
      if (count > 0) {
        sceneHint = '\n当前画布已有 ' + count + ' 个元素。除非用户要求追加，否则生成一个完整可替换的新版图。';
      }
    } catch(e) {}
    return chartText + '用户需求：\n' + input + sceneHint;
  }

  function _applyDrawingAISkeletonPreview(skeleton, append, baseSceneContent) {
    if (!window.BookStarkExcalidraw || !window.BookStarkExcalidraw.convertSkeleton || !window.BookStarkExcalidraw.applyElements) {
      throw new Error('Excalidraw skeleton converter is not ready');
    }
    var converted = window.BookStarkExcalidraw.convertSkeleton(skeleton);
    var nextElements = converted;
    if (append) {
      var base = null;
      try { base = baseSceneContent ? JSON.parse(baseSceneContent) : null; } catch(e) {}
      var baseElements = base && Array.isArray(base.elements) ? base.elements : [];
      nextElements = baseElements.concat(converted);
    }
    window.BookStarkExcalidraw.applyElements(nextElements, { append: false });
    BookStarkEditor.setDrawingDirty(true);
    currentMarkdown = BookStarkEditor.getDrawingContent();
    updateDrawingCharCount();
    return currentMarkdown;
  }

  function _makeDrawingAIDraggable(root, handleSelector) {
    var header = root.querySelector(handleSelector || '.ai-dlg-header');
    if (!header) return;
    var startX = 0;
    var startY = 0;
    var startLeft = 0;
    var startTop = 0;
    var dragging = false;

    function clampPosition(left, top) {
      var rect = root.getBoundingClientRect();
      var maxLeft = Math.max(8, window.innerWidth - rect.width - 8);
      var maxTop = Math.max(8, window.innerHeight - rect.height - 8);
      return {
        left: Math.max(8, Math.min(maxLeft, left)),
        top: Math.max(8, Math.min(maxTop, top))
      };
    }

    header.addEventListener('pointerdown', function(e) {
      if (e.target && e.target.closest && e.target.closest('button,select,input,textarea')) return;
      dragging = true;
      var rect = root.getBoundingClientRect();
      startX = e.clientX;
      startY = e.clientY;
      startLeft = rect.left;
      startTop = rect.top;
      root.style.setProperty('width', rect.width + 'px', 'important');
      root.style.setProperty('height', rect.height + 'px', 'important');
      root.classList.add('drawing-ai-dragging');
      try { header.setPointerCapture(e.pointerId); } catch(err) {}
      e.preventDefault();
    });
    header.addEventListener('pointermove', function(e) {
      if (!dragging) return;
      var pos = clampPosition(startLeft + e.clientX - startX, startTop + e.clientY - startY);
      root.style.setProperty('left', pos.left + 'px', 'important');
      root.style.setProperty('top', pos.top + 'px', 'important');
      root.style.setProperty('right', 'auto', 'important');
      root.style.setProperty('bottom', 'auto', 'important');
      root.style.setProperty('transform', 'none', 'important');
    });
    function endDrag(e) {
      if (!dragging) return;
      dragging = false;
      root.classList.remove('drawing-ai-dragging');
      try { header.releasePointerCapture(e.pointerId); } catch(err) {}
    }
    header.addEventListener('pointerup', endDrag);
    header.addEventListener('pointercancel', endDrag);
    function onResize() {
      var rect = root.getBoundingClientRect();
      var pos = clampPosition(rect.left, rect.top);
      root.style.setProperty('left', pos.left + 'px', 'important');
      root.style.setProperty('top', pos.top + 'px', 'important');
      root.style.setProperty('right', 'auto', 'important');
      root.style.setProperty('bottom', 'auto', 'important');
      root.style.setProperty('transform', 'none', 'important');
    }
    window.addEventListener('resize', onResize);
    return function() {
      window.removeEventListener('resize', onResize);
    };
  }

  function _snapshotAIFloatStyle(root) {
    var props = ['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'];
    var snapshot = {};
    props.forEach(function(prop) {
      snapshot[prop] = {
        value: root.style.getPropertyValue(prop),
        priority: root.style.getPropertyPriority(prop)
      };
    });
    return snapshot;
  }

  function _applyAIFloatStyle(root, snapshot) {
    var props = ['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'];
    props.forEach(function(prop) {
      var item = snapshot && snapshot[prop];
      if (item && item.value) root.style.setProperty(prop, item.value, item.priority || '');
      else root.style.removeProperty(prop);
    });
  }

  function _clearAIFloatBoxStyle(root) {
    ['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'].forEach(function(prop) {
      root.style.removeProperty(prop);
    });
  }

  function _setAIFloatCollapsed(root, collapsed, toggleBtn) {
    if (!root) return;
    collapsed = !!collapsed;
    if (collapsed && !root.classList.contains('drawing-ai-collapsed')) {
      root._aiExpandedStyle = _snapshotAIFloatStyle(root);
      root.style.removeProperty('width');
      root.style.removeProperty('height');
    } else if (!collapsed && root._aiExpandedStyle) {
      _applyAIFloatStyle(root, root._aiExpandedStyle);
      root._aiExpandedStyle = null;
    }
    root.classList.toggle('drawing-ai-collapsed', collapsed);
    if (toggleBtn) {
      toggleBtn.setAttribute('aria-label', collapsed ? '展开' : '收起');
      toggleBtn.textContent = collapsed ? '□' : '_';
    }
  }

  function _setAIFloatMaximized(root, maximized, btn) {
    if (!root) return;
    maximized = !!maximized;
    if (maximized && !root.classList.contains('drawing-ai-maximized')) {
      root._aiCompactStyle = _snapshotAIFloatStyle(root);
      root.classList.remove('drawing-ai-collapsed');
      _clearAIFloatBoxStyle(root);
    } else if (!maximized && root._aiCompactStyle) {
      _applyAIFloatStyle(root, root._aiCompactStyle);
      root._aiCompactStyle = null;
    }
    root.classList.toggle('drawing-ai-maximized', maximized);
    if (btn) {
      btn.setAttribute('aria-pressed', maximized ? 'true' : 'false');
      btn.setAttribute('aria-label', maximized ? '还原' : '最大化');
      btn.setAttribute('title', maximized ? '还原' : '最大化');
      btn.innerHTML = '<i class="fa-solid ' + (maximized ? 'fa-compress' : 'fa-expand') + '"></i>';
    }
  }

  function openDrawingAI(opts) {
    opts = opts || {};
    if (typeof AIHelper === 'undefined') {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    if (!window.BookStarkExcalidraw || !BookStarkEditor._excalidrawRunning) {
      if (window.BSDialog) BSDialog.toast('画板尚未加载完成', 'warning');
      return;
    }

    var esc = function(s) { return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); };
    var wrap = document.createElement('div');
    wrap.innerHTML = '' +
      '<div class="ai-dlg-box drawing-ai-dlg drawing-ai-float" role="dialog" aria-modal="false">' +
          '<div class="ai-dlg-header">' +
            '<span class="ai-dlg-title"><i class="fa-solid fa-wand-magic-sparkles"></i> AI 生成画板</span>' +
            '<div class="drawing-ai-window-actions">' +
              '<button type="button" class="drawing-ai-maximize" aria-label="最大化" title="最大化" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
              '<button type="button" class="drawing-ai-toggle" aria-label="收起">_</button>' +
              '<button type="button" class="ai-dlg-close" aria-label="关闭">&times;</button>' +
            '</div>' +
          '</div>' +
          '<div class="ai-dlg-body">' +
            '<div class="drawing-ai-grid">' +
              '<label class="drawing-ai-field"><span>类型</span><select class="drawing-ai-chart">' +
                '<option value="auto">自动</option><option value="flowchart">流程图</option><option value="mindmap">思维导图</option>' +
                '<option value="architecture">架构图</option><option value="sequence">时序图</option><option value="timeline">时间线</option>' +
                '<option value="matrix">矩阵图</option><option value="swimlane">泳道图</option><option value="concept">概念图</option>' +
              '</select></label>' +
              '<label class="drawing-ai-field"><span>写入</span><select class="drawing-ai-mode">' +
                '<option value="replace">替换画布</option><option value="append">追加到画布</option>' +
              '</select></label>' +
            '</div>' +
            '<textarea class="ai-dlg-prompt" rows="4" placeholder="' + esc(opts.placeholder || '描述要生成的图，例如：画一个用户登录流程图，包含异常分支') + '"></textarea>' +
            '<div class="ai-dlg-quick-row">' +
              '<button type="button" class="ai-dlg-quick" data-prompt="画一个三层 Web 应用架构图，包含客户端、API 服务、数据库、缓存、对象存储和监控。">应用架构</button>' +
              '<button type="button" class="ai-dlg-quick" data-prompt="画一个产品需求从提出、评审、开发、测试到发布的泳道流程图。">泳道流程</button>' +
              '<button type="button" class="ai-dlg-quick" data-prompt="画一个项目里程碑时间线，包含规划、设计、开发、内测、上线。">时间线</button>' +
            '</div>' +
            '<div class="ai-dlg-output" aria-live="polite"></div>' +
          '</div>' +
          '<div class="ai-dlg-footer">' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-cancel">取消</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-stop" style="display:none;">停止</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-append drawing-ai-apply" style="display:none;">应用到画布</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-go">生成</button>' +
          '</div>' +
      '</div>';
    var root = wrap.firstChild;
    document.body.appendChild(root);
    var promptEl = root.querySelector('.ai-dlg-prompt');
    var outputEl = root.querySelector('.ai-dlg-output');
    var chartEl = root.querySelector('.drawing-ai-chart');
    var modeEl = root.querySelector('.drawing-ai-mode');
    var goBtn = root.querySelector('.ai-dlg-btn-go');
    var stopBtn = root.querySelector('.ai-dlg-btn-stop');
    var applyBtn = root.querySelector('.drawing-ai-apply');
    var toggleBtn = root.querySelector('.drawing-ai-toggle');
    var maxBtn = root.querySelector('.drawing-ai-maximize');
    var ctrl = null;
    var generated = '';
    var liveApplied = false;
    var lastPreviewKey = '';
    var lastPreviewAt = 0;
    var pendingPreviewTimer = null;
    var baseSceneContent = '';
    var cleanupDrag = null;

    function close() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} }
      if (pendingPreviewTimer) clearTimeout(pendingPreviewTimer);
      if (cleanupDrag) { try { cleanupDrag(); } catch(e) {} cleanupDrag = null; }
      try { document.body.removeChild(root); } catch(e) {}
    }
    function setRunning(on) {
      goBtn.style.display = on ? 'none' : '';
      stopBtn.style.display = on ? '' : 'none';
      promptEl.disabled = on;
      chartEl.disabled = on;
      modeEl.disabled = on;
    }
    function setCollapsed(on) {
      _setAIFloatCollapsed(root, on, toggleBtn);
    }
    function applyLivePreview(force) {
      if (!generated.trim()) return;
      var now = Date.now();
      if (!force && now - lastPreviewAt < 900) {
        if (!pendingPreviewTimer) {
          pendingPreviewTimer = setTimeout(function() {
            pendingPreviewTimer = null;
            applyLivePreview(true);
          }, 900 - (now - lastPreviewAt));
        }
        return;
      }
      lastPreviewAt = now;
      var skeleton;
      try { skeleton = _extractDrawingSkeletonJSON(generated); } catch(e) { return; }
      if (!Array.isArray(skeleton) || !skeleton.length) return;
      var key = skeleton.length + ':' + generated.length;
      if (key === lastPreviewKey) return;
      try {
        _applyDrawingAISkeletonPreview(skeleton, modeEl.value === 'append', baseSceneContent);
        lastPreviewKey = key;
        liveApplied = true;
        applyBtn.style.display = '';
        applyBtn.textContent = '完成';
        if (saveMgr && saveMgr.onContentChange) saveMgr.onContentChange();
      } catch(e) {}
    }
    function applyGenerated() {
      try {
        if (liveApplied && !ctrl) {
          if (window.BSDialog) BSDialog.toast('画板已更新', 'success');
          close();
          return;
        }
        if (!generated.trim()) return;
        var skeleton = _extractDrawingSkeletonJSON(generated);
        currentMarkdown = _applyDrawingAISkeletonPreview(skeleton, modeEl.value === 'append', baseSceneContent) || currentMarkdown;
        BookStarkEditor.setDrawingDirty(true);
        updateDrawingCharCount();
        if (saveMgr && saveMgr.onContentChange) saveMgr.onContentChange();
        if (window.BSDialog) BSDialog.toast('已应用到画板', 'success');
        close();
      } catch (e) {
        outputEl.textContent = '解析失败：' + (e && e.message ? e.message : e);
        outputEl.classList.add('ai-dlg-output-err');
      }
    }
    function generate() {
      var prompt = (promptEl.value || '').trim();
      if (!prompt) {
        if (window.BSDialog) BSDialog.toast('请输入画图需求', 'warning');
        promptEl.focus();
        return;
      }
      generated = '';
      liveApplied = false;
      lastPreviewKey = '';
      baseSceneContent = currentMarkdown || BookStarkEditor.getDrawingContent();
      outputEl.textContent = '模型思考中...';
      outputEl.classList.remove('ai-dlg-output-err');
      outputEl.classList.add('ai-dlg-output-active');
      applyBtn.style.display = 'none';
      applyBtn.textContent = '应用到画布';
      setRunning(true);
      ctrl = AIHelper.complete({
        messages: AIHelper.buildMessages(_drawingAISystemPrompt(), _drawingAIUserPrompt(prompt, chartEl.value, currentMarkdown)),
        scene: 'drawing',
        temperature: 0.3,
        maxTokens: 8192,
        onChunk: function(_chunk, full) {
          generated = full;
          outputEl.textContent = full || '模型思考中...';
          outputEl.scrollTop = outputEl.scrollHeight;
          applyLivePreview(false);
        },
        onDone: function(full) {
          generated = full || generated;
          ctrl = null;
          applyLivePreview(true);
          setRunning(false);
          if (generated.trim()) {
            applyBtn.style.display = '';
            if (liveApplied) applyBtn.textContent = '完成';
          }
        },
        onError: function(msg) {
          ctrl = null;
          setRunning(false);
          outputEl.textContent = msg || (window.__('note.ai.toast.error') || 'AI 调用失败');
          outputEl.classList.add('ai-dlg-output-err');
        }
      });
    }

    root.querySelector('.ai-dlg-close').addEventListener('click', close);
    root.querySelector('.ai-dlg-btn-cancel').addEventListener('click', close);
    maxBtn.addEventListener('click', function() {
      var nextMaximized = !root.classList.contains('drawing-ai-maximized');
      if (nextMaximized && root.classList.contains('drawing-ai-collapsed')) setCollapsed(false);
      _setAIFloatMaximized(root, nextMaximized, maxBtn);
    });
    toggleBtn.addEventListener('click', function() {
      var nextCollapsed = !root.classList.contains('drawing-ai-collapsed');
      if (nextCollapsed && root.classList.contains('drawing-ai-maximized')) _setAIFloatMaximized(root, false, maxBtn);
      setCollapsed(nextCollapsed);
    });
    stopBtn.addEventListener('click', function() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      applyLivePreview(true);
      setRunning(false);
      if (generated.trim()) applyBtn.style.display = '';
    });
    goBtn.addEventListener('click', generate);
    applyBtn.addEventListener('click', applyGenerated);
    Array.prototype.forEach.call(root.querySelectorAll('.ai-dlg-quick'), function(btn) {
      btn.addEventListener('click', function() {
        promptEl.value = btn.getAttribute('data-prompt') || '';
        promptEl.focus();
      });
    });
    cleanupDrag = _makeDrawingAIDraggable(root);
    setTimeout(function() { promptEl.focus(); }, 30);
  }

  window.openDrawingAI = openDrawingAI;

  function openMarkdownFloatingAI(opts) {
    opts = opts || {};
    if (typeof AIHelper === 'undefined') {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    var esc = function(s) { return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); };
    var wrap = document.createElement('div');
    wrap.innerHTML = '' +
      '<div class="ai-dlg-box drawing-ai-dlg drawing-ai-float markdown-ai-float" role="dialog" aria-modal="false">' +
        '<div class="ai-dlg-header">' +
          '<span class="ai-dlg-title"><i class="fa-solid fa-wand-magic-sparkles"></i> ' + esc(opts.title || (window.__('editor.ai.dialog.title') || 'AI 助手')) + '</span>' +
          '<div class="drawing-ai-window-actions">' +
            '<button type="button" class="drawing-ai-maximize" aria-label="最大化" title="最大化" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
            '<button type="button" class="drawing-ai-toggle" aria-label="收起">_</button>' +
            '<button type="button" class="ai-dlg-close" aria-label="关闭">&times;</button>' +
          '</div>' +
        '</div>' +
        '<div class="ai-dlg-body">' +
          '<div class="markdown-ai-context-bar">' +
            '<div class="markdown-ai-context-actions">' +
              '<button type="button" class="ai-dlg-quick markdown-ai-use-all">全文</button>' +
              '<button type="button" class="ai-dlg-quick markdown-ai-clear-context">清空</button>' +
            '</div>' +
            '<span class="markdown-ai-context-status">未选择上下文</span>' +
          '</div>' +
          '<textarea class="ai-dlg-prompt" rows="3" placeholder="' + esc(opts.placeholder || '告诉 AI 你想写什么，或先选中后方文字再点“选区”') + '"></textarea>' +
          '<div class="ai-dlg-quick-row markdown-ai-quick-row"></div>' +
        '</div>' +
        '<div class="ai-dlg-footer">' +
          '<button type="button" class="ai-dlg-btn ai-dlg-btn-stop" style="display:none;">停止</button>' +
          '<button type="button" class="ai-dlg-btn ai-dlg-btn-replace markdown-ai-replace-selection" style="display:none;">替换选区</button>' +
          '<button type="button" class="ai-dlg-btn ai-dlg-btn-append markdown-ai-insert">光标处插入</button>' +
        '</div>' +
      '</div>';
    var root = wrap.firstChild;
    document.body.appendChild(root);

    var promptEl = root.querySelector('.ai-dlg-prompt');
    var stopBtn = root.querySelector('.ai-dlg-btn-stop');
    var replaceBtn = root.querySelector('.markdown-ai-replace-selection');
    var insertBtn = root.querySelector('.markdown-ai-insert');
    var toggleBtn = root.querySelector('.drawing-ai-toggle');
    var maxBtn = root.querySelector('.drawing-ai-maximize');
    var ctxStatus = root.querySelector('.markdown-ai-context-status');
    var quickRow = root.querySelector('.markdown-ai-quick-row');
    var ctrl = null;
    var generated = '';
    var contextText = '';
    var replaceTarget = null;
    var currentSelectionText = '';
    var currentSelectionRange = null;
    var cleanupDrag = null;
    var cleanupSelectionSync = null;
    var selectionSyncTimer = null;
    var liveApplyTarget = null;
    var liveApplyMode = '';
    var liveApplyPos = 0;
    var liveAppliedLen = 0;
    var liveStarted = false;
    var defaultActions = opts.defaultActions || opts.extraActions || [];
    var selectionActions = opts.selectionActions || opts.extraActions || [];

    function setReplaceAvailable(on) {
      replaceBtn.style.display = on ? '' : 'none';
    }
    function renderQuickActions(actions) {
      actions = actions || [];
      if (!actions.length) {
        quickRow.style.display = 'none';
        quickRow.innerHTML = '';
        return;
      }
      quickRow.style.display = '';
      quickRow.innerHTML = actions.map(function(a, i) {
        return '<button type="button" class="ai-dlg-quick" data-idx="' + i + '">' + esc(a.label) + '</button>';
      }).join('');
      Array.prototype.forEach.call(quickRow.querySelectorAll('.ai-dlg-quick'), function(btn) {
        btn.addEventListener('click', function(e) {
          var idx = parseInt(btn.getAttribute('data-idx'), 10);
          var act = actions[idx];
          if (!act || !act.prompt) return;
          promptEl.value = act.prompt;
          promptEl.focus();
          var len = promptEl.value.length;
          try { promptEl.setSelectionRange(len, len); } catch(_) {}
          if (e && (e.ctrlKey || e.metaKey)) generateAndApply('insert', act.prompt);
        });
      });
    }
    function refreshQuickActions() {
      renderQuickActions(contextText ? selectionActions : defaultActions);
    }
    function setPendingSelection(sel) {
      currentSelectionText = sel && sel.text ? String(sel.text) : '';
      currentSelectionRange = currentSelectionText ? sel : null;
      if (!contextText) {
        if (currentSelectionText) ctxStatus.textContent = '当前选区 · ' + currentSelectionText.length + ' 字';
        else ctxStatus.textContent = '未选择上下文';
      }
    }
    function setContext(label, text, target) {
      contextText = String(text || '');
      replaceTarget = (target && target.text && target.view && target.view.state) ? target : null;
      if (contextText) {
        if (label === '选区' && replaceTarget) {
          ctxStatus.innerHTML = '<button type="button" class="markdown-ai-context-locator" title="定位到选区">选区</button> · ' + contextText.length + ' 字';
        } else {
          ctxStatus.textContent = (label || '上下文') + ' · ' + contextText.length + ' 字';
        }
      } else {
        ctxStatus.textContent = '未选择上下文';
      }
      setReplaceAvailable(!!replaceTarget);
      refreshQuickActions();
    }
    function selectionLabel(sel) {
      if (!sel || !sel.view || !sel.view.state || !sel.view.state.doc) return '选区';
      return sel.from === 0 && sel.to === sel.view.state.doc.length ? '全文' : '选区';
    }
    function syncSelectionContext() {
      if (ctrl || !document.body.contains(root)) return;
      var active = document.activeElement;
      if (active && root.contains(active)) return;
      var sel = _getEditorSelection();
      if (sel && sel.text) {
        setPendingSelection(sel);
        setContext(selectionLabel(sel), sel.text, sel);
      } else {
        setPendingSelection(null);
      }
    }
    function scheduleSelectionSync() {
      if (selectionSyncTimer) clearTimeout(selectionSyncTimer);
      selectionSyncTimer = setTimeout(syncSelectionContext, 60);
    }
    function bindSelectionSync() {
      document.addEventListener('selectionchange', scheduleSelectionSync);
      document.addEventListener('mouseup', scheduleSelectionSync, true);
      document.addEventListener('keyup', scheduleSelectionSync, true);
      return function() {
        if (selectionSyncTimer) clearTimeout(selectionSyncTimer);
        document.removeEventListener('selectionchange', scheduleSelectionSync);
        document.removeEventListener('mouseup', scheduleSelectionSync, true);
        document.removeEventListener('keyup', scheduleSelectionSync, true);
      };
    }
    function captureSelection(showToast) {
      var sel = _getEditorSelection();
      if (!(sel && sel.text) && currentSelectionRange && currentSelectionText) sel = currentSelectionRange;
      if (sel && sel.text) {
        setContext(selectionLabel(sel), sel.text, sel);
        return true;
      }
      if (showToast && window.BSDialog) BSDialog.toast('请先在后方编辑器里选中文字', 'warning');
      return false;
    }
    function captureAll() {
      var all = _getEditorFullRange();
      if (all && all.text) {
        _selectEditorRange(all);
        setPendingSelection(all);
        setContext('全文', all.text, all);
        return true;
      }
      if (window.BSDialog) BSDialog.toast('当前文档没有内容', 'warning');
      return false;
    }
    function setRunning(on) {
      stopBtn.style.display = on ? '' : 'none';
      insertBtn.style.display = on ? 'none' : '';
      if (on) replaceBtn.style.display = 'none';
      else setReplaceAvailable(!!replaceTarget);
      promptEl.disabled = on;
      Array.prototype.forEach.call(root.querySelectorAll('.markdown-ai-context-actions button,.ai-dlg-quick'), function(btn) {
        btn.disabled = on;
      });
    }
    function setCollapsed(on) {
      _setAIFloatCollapsed(root, on, toggleBtn);
    }
    function close() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      if (cleanupDrag) { try { cleanupDrag(); } catch(e) {} cleanupDrag = null; }
      if (cleanupSelectionSync) { try { cleanupSelectionSync(); } catch(e) {} cleanupSelectionSync = null; }
      try { document.body.removeChild(root); } catch(e) {}
    }
    function buildUserPrompt(prompt) {
      if (!contextText) captureSelection(false);
      if (contextText) return '【上下文】\n' + contextText + '\n\n【指令】\n' + prompt;
      return prompt;
    }
    function prepareLiveApply(mode) {
      liveApplyMode = mode;
      liveApplyTarget = null;
      liveApplyPos = 0;
      liveAppliedLen = 0;
      liveStarted = false;
      if (mode === 'replace') {
        if (!replaceTarget && !captureSelection(true)) return false;
        liveApplyTarget = replaceTarget;
      } else {
        liveApplyTarget = readCurrentInsertTarget();
      }
      if (liveApplyTarget && liveApplyTarget.view && liveApplyTarget.view.state) {
        var docLen = liveApplyTarget.view.state.doc.length;
        liveApplyTarget.from = Math.max(0, Math.min(docLen, Number(liveApplyTarget.from) || 0));
        liveApplyTarget.to = Math.max(liveApplyTarget.from, Math.min(docLen, Number(liveApplyTarget.to) || liveApplyTarget.from));
        liveApplyPos = liveApplyTarget.from;
      }
      return true;
    }
    function readCurrentInsertTarget() {
      var sel = _getEditorSelection();
      if (sel && sel.view && sel.view.state) {
        return { view: sel.view, from: sel.to, to: sel.to, text: '' };
      }
      return null;
    }
    function applyLiveDelta(delta) {
      delta = String(delta || '');
      if (!delta) return;
      if (!liveApplyTarget || !liveApplyTarget.view || !liveApplyTarget.view.state) return;
      var view = liveApplyTarget.view;
      var from = liveStarted ? liveApplyPos : liveApplyTarget.from;
      var to = liveStarted ? liveApplyPos : liveApplyTarget.to;
      var docLen = view.state.doc.length;
      from = Math.max(0, Math.min(docLen, from));
      to = Math.max(from, Math.min(docLen, to));
      view.dispatch({
        changes: { from: from, to: to, insert: delta },
        selection: { anchor: from + delta.length }
      });
      liveApplyPos = from + delta.length;
      liveStarted = true;
      try { view.focus(); } catch(e) {}
      _syncEditorAfterMutation();
    }
    function applyLiveFull(full) {
      full = String(full || '');
      if (full.length <= liveAppliedLen) return;
      var delta = full.slice(liveAppliedLen);
      liveAppliedLen = full.length;
      applyLiveDelta(delta);
    }
    function generateAndApply(applyMode, promptOverride) {
      var prompt = (promptOverride != null ? promptOverride : promptEl.value || '').trim();
      if (!prompt) {
        if (window.BSDialog) BSDialog.toast('请输入指令', 'warning');
        promptEl.focus();
        return;
      }
      if (!prepareLiveApply(applyMode)) return;
      generated = '';
      ctxStatus.textContent = '模型生成中...';
      setRunning(true);
      ctrl = AIHelper.complete({
        messages: AIHelper.buildMessages(opts.systemPrompt, buildUserPrompt(prompt)),
        scene: 'editor',
        onChunk: function(_chunk, full) {
          generated = full || '';
          applyLiveFull(generated);
          ctxStatus.textContent = generated ? ('模型生成中 · ' + generated.length + ' 字') : '模型生成中...';
        },
        onDone: function(full) {
          generated = full || generated;
          applyLiveFull(generated);
          ctrl = null;
          setRunning(false);
          if (!generated.trim()) {
            ctxStatus.textContent = '没有生成内容';
            return;
          }
          if (!liveStarted) {
            if (applyMode === 'insert') {
              if (!_insertIntoEditorAtCursor(generated)) _insertIntoEditor(generated, 'append');
              ctxStatus.textContent = '已插入 · ' + generated.length + ' 字';
            }
            return;
          }
          ctxStatus.textContent = (applyMode === 'replace' ? '已替换' : '已插入') + ' · ' + generated.length + ' 字';
        },
        onError: function(msg) {
          ctrl = null;
          setRunning(false);
          ctxStatus.textContent = msg || (window.__('note.ai.toast.error') || 'AI 调用失败');
        }
      });
    }

    if (opts.contextText) setContext('选区', opts.contextText, _getEditorSelection());
    root.querySelector('.markdown-ai-use-all').addEventListener('click', captureAll);
    root.querySelector('.markdown-ai-clear-context').addEventListener('click', function() {
      _clearEditorSelection(replaceTarget || currentSelectionRange);
      setPendingSelection(null);
      setContext('', '', null);
    });
    ctxStatus.addEventListener('click', function(e) {
      if (!e.target || !e.target.closest || !e.target.closest('.markdown-ai-context-locator')) return;
      if (replaceTarget) _selectEditorRange(replaceTarget, true);
    });
    root.querySelector('.ai-dlg-close').addEventListener('click', close);
    maxBtn.addEventListener('click', function() {
      var nextMaximized = !root.classList.contains('drawing-ai-maximized');
      if (nextMaximized && root.classList.contains('drawing-ai-collapsed')) setCollapsed(false);
      _setAIFloatMaximized(root, nextMaximized, maxBtn);
    });
    toggleBtn.addEventListener('click', function() {
      var nextCollapsed = !root.classList.contains('drawing-ai-collapsed');
      if (nextCollapsed && root.classList.contains('drawing-ai-maximized')) _setAIFloatMaximized(root, false, maxBtn);
      setCollapsed(nextCollapsed);
    });
    insertBtn.addEventListener('click', function() { generateAndApply('insert'); });
    stopBtn.addEventListener('click', function() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      setRunning(false);
      ctxStatus.textContent = generated.trim() ? ('已停止 · ' + generated.length + ' 字') : '已停止';
    });
    replaceBtn.addEventListener('click', function() {
      generateAndApply('replace');
    });
    refreshQuickActions();
    cleanupDrag = _makeDrawingAIDraggable(root);
    cleanupSelectionSync = bindSelectionSync();
    scheduleSelectionSync();
    setTimeout(function() { promptEl.focus(); }, 30);
  }

  window.openEditorAI = function(opts) {
    opts = opts || {};
    if (mode === 'preview' && currentDocType === 'markdown') {
      openMarkdownPreviewAI(opts);
      return;
    }
    if (currentDocType === 'drawing') {
      openDrawingAI(opts);
      return;
    }
    if (typeof AIHelper === 'undefined' || (currentDocType !== 'markdown' && typeof AIComposeDialog === 'undefined')) {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    var sel = _getEditorSelection();
    var ctx = sel && sel.text ? sel.text : '';
    var isHtml = currentDocType === 'html';
    var sysPrompt = _buildEditorSystemPrompt(currentDocType);
    var bookCtx = (typeof window.__bookGetEditorContext === 'function')
      ? window.__bookGetEditorContext() : null;
    var hasBookCtx = !!(bookCtx && bookCtx.chapterName);
    var artCtx = hasBookCtx ? null : _getArticleContext();
    var hasArtCtx = !!artCtx;

    // 优先用 admin 配置的 ai_actions_<scene>（每行 label | prompt），无配置时 fallback 到默认。
    function _pickActions(sceneKey, defaults, vars) {
      var raw = window.AI_QUICK_RAW && window.AI_QUICK_RAW[sceneKey];
      if (raw && window.AIHelper && AIHelper.parseActions) {
        var parsed = AIHelper.parseActions(raw, vars);
        if (parsed && parsed.length) return parsed;
      }
      return defaults;
    }

    var selectionActions = _pickActions('selection', [
      { label: window.__('editor.ai.action.rewrite')   || '改写',     prompt: '请改写以下选中的文本，保持原意但更通顺、更专业。直接给改写后的版本。' },
      { label: window.__('editor.ai.action.expand')    || '扩写',     prompt: '请把选中文本扩写得更详细、更有信息量，保留原结构。直接给扩写后的版本。' },
      { label: window.__('editor.ai.action.shorten')   || '缩写',     prompt: '请把选中文本压缩到原长度的 1/3 左右，保留核心信息。' },
      { label: window.__('editor.ai.action.translate') || '翻译为英文', prompt: '请把选中文本翻译为流畅自然的英文。' },
      { label: window.__('editor.ai.action.continue')  || '续写',     prompt: '请基于选中文本的语气和上下文，续写一段（约 2-3 句话）。' }
    ]);

    var defaultActions;
    if (isHtml) {
      var htmlSubject = hasBookCtx ? '当前章节' : (hasArtCtx ? '当前文章' : '主题');
      defaultActions = _pickActions('html', [
        { label: window.__('editor.ai.action.html_page')    || '写整页 HTML',    prompt: '请基于' + htmlSubject + '主题，输出一段可直接粘贴的完整 HTML 片段（含 <h1>/<p>/<ul> 等结构，不要 <html>/<body>/<head>），不要包含解释。' },
        { label: window.__('editor.ai.action.html_section') || '写一段 HTML',    prompt: '请输出一段 HTML 片段，主题：' },
        { label: window.__('editor.ai.action.html_table')   || '插入示例表格',  prompt: '请输出一个 <table> HTML 片段（含 thead/tbody，3 列 4 行示例数据），不要解释。' },
        { label: window.__('editor.ai.action.html_card')    || '插入卡片块',    prompt: '请输出一个语义化的 <section class="card"> HTML 片段，包含标题、描述和操作按钮，主题：' },
        { label: window.__('editor.ai.action.html_form')    || '插入表单',      prompt: '请输出一个简单的 HTML <form> 片段，含 label/input/button，不要 <script>。' }
      ], { subject: htmlSubject });
    } else if (hasBookCtx) {
      defaultActions = _pickActions('book', [
        { label: window.__('editor.ai.action.draft_chapter') || '写本章初稿', prompt: '请基于当前章节标题与所在书籍的上下文，写一篇约 800 字的章节初稿，使用 markdown，有合理的二级/三级小标题，不要重复章节标题。' },
        { label: window.__('editor.ai.action.intro')         || '写本章引言', prompt: '请为当前章节写一段 150-200 字的引言段落，引出本章核心问题，语气与同级章节保持一致。' },
        { label: window.__('editor.ai.action.summary')       || '写本章小结', prompt: '请为当前章节写一段 150 字左右的小结段落，提炼 3-5 个要点，使用列表形式。' },
        { label: window.__('editor.ai.action.outline')       || '生成大纲', prompt: '为当前章节生成一个 markdown 标题大纲，3-5 个二级标题，每个二级下再带 1-2 个三级，不要正文。' },
        { label: window.__('editor.ai.action.draft')         || '写一段', prompt: '基于当前章节主题，写一段 markdown 段落：' }
      ]);
    } else if (hasArtCtx) {
      defaultActions = _pickActions('article', [
        { label: window.__('editor.ai.action.draft_article') || '写整篇文章', prompt: '请基于文章标题与标签，写一篇约 1000 字的完整文章，使用 markdown，有合理的二级/三级小标题，不要重复文章标题。' },
        { label: window.__('editor.ai.action.intro_article') || '写引言',     prompt: '请为这篇文章写一段 150-200 字的开篇引言，吸引读者并引出主题。' },
        { label: window.__('editor.ai.action.conclusion')    || '写结论',     prompt: '请为这篇文章写一段 150 字左右的结论段落，总结要点并给出行动建议。' },
        { label: window.__('editor.ai.action.outline')       || '生成大纲',   prompt: '为这篇文章生成一个 markdown 标题大纲，3-5 个二级标题，每个二级下再带 1-2 个三级，不要正文。' },
        { label: window.__('editor.ai.action.key_points')    || '提炼要点',   prompt: '请基于标题与标签，列出本主题最值得讨论的 5-8 个核心要点，使用 markdown 列表。' }
      ]);
    } else {
      defaultActions = _pickActions('empty', [
        { label: window.__('editor.ai.action.outline')   || '生成大纲', prompt: '为我即将写的内容生成一个 markdown 标题大纲，3-5 级，覆盖以下主题：' },
        { label: window.__('editor.ai.action.draft')     || '写一段', prompt: '写一段 markdown 段落，主题：' }
      ]);
    }
    var actions = ctx ? selectionActions : defaultActions;

    var defaultPlaceholder;
    if (ctx) {
      defaultPlaceholder = window.__('editor.ai.dialog.with_ctx') || '描述你想对选中文本做什么，或选下方快捷动作';
    } else if (isHtml) {
      defaultPlaceholder = window.__('editor.ai.dialog.with_html') || '选下方快捷动作，或自由描述要生成什么 HTML 片段';
    } else if (hasBookCtx) {
      defaultPlaceholder = window.__('editor.ai.dialog.with_book') || '选下方快捷动作，或自由描述本章你想生成什么';
    } else if (hasArtCtx) {
      defaultPlaceholder = window.__('editor.ai.dialog.with_article') || '选下方快捷动作，或自由描述这篇文章你想生成什么';
    } else {
      defaultPlaceholder = window.__('editor.ai.dialog.no_ctx') || '描述你想生成什么内容（先选中文本可解锁改写/扩写等动作）';
    }

    var hint = null;
    if (!ctx) {
      hint = window.__('editor.ai.hint.no_selection') || '先选中一段文字再点击 ✨，可解锁改写 / 扩写 / 缩写 / 翻译 / 续写。';
    }

    var dialogOptions = {
      title: opts.title || (window.__('editor.ai.dialog.title') || 'AI 助手'),
      placeholder: opts.placeholder || defaultPlaceholder,
      systemPrompt: sysPrompt,
      contextText: ctx || null,
      hint: hint,
      extraActions: actions,
      defaultActions: defaultActions,
      selectionActions: selectionActions,
      scene: 'editor',
      onInsert: function(text, mode) {
        _insertIntoEditor(text, mode);
      }
    };
    if (currentDocType === 'markdown') {
      openMarkdownFloatingAI(dialogOptions);
      return;
    }
    AIComposeDialog.open(dialogOptions);
  };

  // ======== Book-Only: AI outline ========
  function _escAttr(s) { return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }
  function _escHtml(s) { return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  function _bookAIDialogHTML(t, parentInfo) {
    var canSub = !!parentInfo;
    var rootLabel = t('book.ai.dialog.scope.root', '根目录');
    var subLabel = canSub
      ? t('book.ai.dialog.scope.sub', '子目录') + ': ' + _escHtml(parentInfo.name)
      : t('book.ai.dialog.scope.sub.disabled', '子目录（先在左侧选中一篇章节）');
    var subDisabled = canSub ? '' : ' disabled';
    return '' +
      '<div class="ai-dlg-overlay" role="dialog" aria-modal="true">' +
        '<div class="ai-dlg-box">' +
          '<div class="ai-dlg-header">' +
            '<span class="ai-dlg-title" id="_bkAITitle"><i class="fa-solid fa-wand-magic-sparkles"></i> </span>' +
            '<button type="button" class="ai-dlg-close" aria-label="close">&times;</button>' +
          '</div>' +
          '<div class="ai-dlg-body">' +
            '<div class="bk-ai-scope" role="tablist" aria-label="' + _escAttr(t('book.ai.dialog.scope.aria','生成范围')) + '">' +
              '<button type="button" class="bk-ai-scope-btn" data-scope="root" role="tab" aria-selected="false">' + _escHtml(rootLabel) + '</button>' +
              '<button type="button" class="bk-ai-scope-btn" data-scope="sub" role="tab" aria-selected="false"' + subDisabled + '>' + _escHtml(subLabel) + '</button>' +
            '</div>' +
            '<div class="bk-ai-parent-banner" id="_bkAIBanner" style="display:none"><i class="fa-solid fa-folder-tree"></i> <span></span></div>' +
            '<div class="bk-ai-row"><label class="bk-ai-label" id="_bkAITopicLabel"></label>' +
              '<input type="text" class="bk-ai-input" id="_bkAITopic" placeholder=""></div>' +
            '<div class="bk-ai-row bk-ai-row-inline">' +
              '<label class="bk-ai-label">' + t('book.ai.dialog.count_label','章节数') + '</label>' +
              '<input type="number" class="bk-ai-input bk-ai-input-sm" id="_bkAICount" value="8" min="2" max="30">' +
              '<label class="bk-ai-label" style="margin-left:12px">' + t('book.ai.dialog.style_label','风格 (可选)') + '</label>' +
              '<input type="text" class="bk-ai-input" id="_bkAIStyle" placeholder="' + _escAttr(t('book.ai.dialog.style_placeholder','')) + '">' +
            '</div>' +
            '<div class="bk-ai-row"><label class="bk-ai-label">' + t('book.ai.dialog.preview_label','目录预览（可编辑，每行一章）') + '</label>' +
              '<textarea class="bk-ai-preview" id="_bkAIPreview" rows="10" placeholder="..."></textarea></div>' +
          '</div>' +
          '<div class="ai-dlg-footer">' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-cancel" id="_bkAICancel">' + t('book.ai.dialog.cancel','取消') + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-stop" id="_bkAIStop" style="display:none;">' + (window.__('note.ai.dialog.stop')||'停止') + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-go" id="_bkAIGen"></button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-append" id="_bkAICreate" style="display:none;"></button>' +
          '</div>' +
        '</div>' +
      '</div>';
  }

  function openBookAIOutline() {
    if (typeof AIHelper === 'undefined') {
      if (window.BSDialog) BSDialog.toast(window.__('note.ai.toast.disabled') || 'AI 未启用', 'warning');
      return;
    }
    var t = function(k, fb) { return (window.__ ? window.__(k) : null) || fb; };
    var parentInfo = (typeof window.__bookGetCurrentDocInfo === 'function')
      ? window.__bookGetCurrentDocInfo() : null;

    var wrap = document.createElement('div');
    wrap.innerHTML = _bookAIDialogHTML(t, parentInfo);
    var root = wrap.firstChild;
    document.body.appendChild(root);
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('book-ai-outline');
    var prevFocus = document.activeElement;

    var titleEl = root.querySelector('#_bkAITitle');
    var bannerEl = root.querySelector('#_bkAIBanner');
    var bannerSpan = bannerEl.querySelector('span');
    var topicLabel = root.querySelector('#_bkAITopicLabel');
    var topicEl = root.querySelector('#_bkAITopic');
    var countEl = root.querySelector('#_bkAICount');
    var styleEl = root.querySelector('#_bkAIStyle');
    var preview = root.querySelector('#_bkAIPreview');
    var genBtn = root.querySelector('#_bkAIGen');
    var stopBtn = root.querySelector('#_bkAIStop');
    var createBtn = root.querySelector('#_bkAICreate');
    var cancelBtn = root.querySelector('#_bkAICancel');
    var closeBtn = root.querySelector('.ai-dlg-close');
    var scopeBtns = root.querySelectorAll('.bk-ai-scope-btn');

    var currentMode = parentInfo ? 'sub' : 'root';

    function applyMode(mode) {
      if (mode === 'sub' && !parentInfo) return;
      currentMode = mode;
      Array.prototype.forEach.call(scopeBtns, function(b) {
        var on = b.getAttribute('data-scope') === mode;
        b.classList.toggle('active', on);
        b.setAttribute('aria-selected', on ? 'true' : 'false');
      });
      var inSub = mode === 'sub';
      // Title
      titleEl.innerHTML = '<i class="fa-solid fa-wand-magic-sparkles"></i> ' +
        (inSub
          ? _escHtml(t('book.ai.dialog.title.sub','AI 起草子目录') + ' — ' + parentInfo.name)
          : _escHtml(t('book.ai.dialog.title','AI 起草章节目录')));
      // Banner
      if (inSub) {
        bannerEl.style.display = '';
        bannerSpan.textContent = (t('book.ai.dialog.parent_banner','正在为「{name}」生成子目录'))
          .replace('{name}', parentInfo.name);
      } else {
        bannerEl.style.display = 'none';
      }
      // Topic label / placeholder / default value
      topicLabel.textContent = inSub
        ? t('book.ai.dialog.topic_label.sub','子主题（默认沿用父章节标题）')
        : t('book.ai.dialog.topic_label','书籍主题');
      topicEl.placeholder = inSub
        ? t('book.ai.dialog.topic_placeholder.sub','例如：自注意力机制 / 训练技巧')
        : t('book.ai.dialog.topic_placeholder','例如：从零理解 Transformer');
      // Only auto-overwrite topic when it's empty or matches the previous mode's auto value.
      var autoFill = inSub ? parentInfo.name : '';
      if (!topicEl.value || topicEl.value === topicEl._autoFill) {
        topicEl.value = autoFill;
      }
      topicEl._autoFill = autoFill;
      // Count default
      if (!countEl._userTouched) countEl.value = inSub ? '5' : '8';
      // Buttons
      genBtn.textContent = inSub
        ? t('book.ai.dialog.generate.sub','生成子目录')
        : t('book.ai.dialog.generate','生成目录');
      createBtn.textContent = inSub
        ? t('book.ai.dialog.create_all.sub','创建为子文档')
        : t('book.ai.dialog.create_all','创建为文档');
    }

    countEl.addEventListener('input', function() { countEl._userTouched = true; });
    Array.prototype.forEach.call(scopeBtns, function(b) {
      b.addEventListener('click', function() {
        if (b.disabled) return;
        applyMode(b.getAttribute('data-scope'));
      });
    });

    applyMode(currentMode);

    var ctrl = null;
    function close() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      try { document.body.removeChild(root); } catch(e) {}
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('book-ai-outline');
      if (prevFocus && typeof prevFocus.focus === 'function') { try { prevFocus.focus(); } catch(e) {} }
    }
    function setRunning(on) {
      genBtn.style.display = on ? 'none' : '';
      stopBtn.style.display = on ? '' : 'none';
      topicEl.disabled = on; countEl.disabled = on; styleEl.disabled = on;
      Array.prototype.forEach.call(scopeBtns, function(b) {
        if (!b.disabled || on) b.disabled = on || (b.getAttribute('data-scope') === 'sub' && !parentInfo);
      });
    }

    function generate() {
      var topic = (topicEl.value || '').trim();
      var inSub = currentMode === 'sub' && !!parentInfo;
      if (!topic) {
        if (window.BSDialog) BSDialog.toast(t('book.ai.toast.empty','请输入主题'), 'warning');
        topicEl.focus();
        return;
      }
      var n = Math.max(2, Math.min(30, parseInt(countEl.value, 10) || (inSub ? 5 : 8)));
      var style = (styleEl.value || '').trim();
      preview.value = '';
      createBtn.style.display = 'none';
      setRunning(true);
      var sys = t('book.ai.system', '你是一个图书章节策划助手...');
      var userParts = [];
      if (inSub) {
        userParts.push('父章节标题: ' + parentInfo.name);
        userParts.push('当前任务: 为父章节「' + parentInfo.name + '」生成 ' + n + ' 个子小节标题，每个标题应当作为父章节的下一级子主题，与父章节主题紧密相关，覆盖该章节内不同的子方向，不要重复父章节本身。');
        if (topic && topic !== parentInfo.name) userParts.push('细化方向/补充说明: ' + topic);
      } else {
        userParts.push('主题: ' + topic);
        userParts.push('章节数: ' + n);
      }
      if (style) userParts.push('风格: ' + style);
      userParts.push('请输出 ' + n + ' 个标题，每行一个。');
      var user = userParts.join('\n');
      ctrl = AIHelper.complete({
        messages: AIHelper.buildMessages(sys, user),
        scene: inSub ? 'book_sub_outline' : 'book_outline',
        onChunk: function(_chunk, full) { preview.value = full; preview.scrollTop = preview.scrollHeight; },
        onDone: function() { setRunning(false); if ((preview.value||'').trim()) createBtn.style.display = ''; },
        onError: function(msg) { setRunning(false); preview.value = msg || (t('note.ai.toast.error', 'AI 调用失败')); }
      });
    }

    function parseLines() {
      return (preview.value || '').split('\n')
        .map(function(s) { return s.replace(/^\s*[-*•·]\s+/, '').replace(/^\s*\d+[\.\)、]\s*/, '').trim(); })
        .filter(function(s) { return s && s.length <= 100; });
    }

    async function createAll() {
      var titles = parseLines();
      if (!titles.length) return;
      createBtn.disabled = true;
      cancelBtn.disabled = true;
      var parentId = (currentMode === 'sub' && parentInfo) ? parentInfo.id : 0;
      try {
        if (window.BSDialog) BSDialog.toast(t('book.ai.toast.creating','正在创建章节...'), 'info');
        for (var i = 0; i < titles.length; i++) {
          await csrfFetch('/api/books/' + bookId + '/docs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ parent_id: parentId, doc_type: 'markdown', document_name: titles[i] })
          });
        }
        if (typeof window.__bookReloadDocTree === 'function') {
          try { await window.__bookReloadDocTree(); } catch(e) {}
        }
        if (window.BSDialog) BSDialog.toast((t('book.ai.toast.created','已创建 {n} 个章节')).replace('{n}', titles.length), 'success');
        close();
      } catch (e) {
        if (window.BSDialog) BSDialog.toast(String(e && e.message || e), 'error');
      } finally {
        createBtn.disabled = false;
        cancelBtn.disabled = false;
      }
    }

    genBtn.addEventListener('click', generate);
    stopBtn.addEventListener('click', function() { if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; } setRunning(false); if ((preview.value||'').trim()) createBtn.style.display = ''; });
    createBtn.addEventListener('click', createAll);
    cancelBtn.addEventListener('click', close);
    closeBtn.addEventListener('click', close);
    root.addEventListener('click', function(e) { if (e.target === root) close(); });
    document.addEventListener('keydown', function esc(e) { if (e.key === 'Escape') { close(); document.removeEventListener('keydown', esc); } });
    setTimeout(function() {
      if (!topicEl.value) topicEl.focus(); else countEl.focus();
    }, 30);
  }
  window.openBookAIOutline = openBookAIOutline;

  // ======== Shared: Outline ========
  var _outlineTimer = null;
  function debouncedOutlineUpdate() {
    clearTimeout(_outlineTimer);
    _outlineTimer = setTimeout(function() {
      if (currentDocType === 'html' || currentDocType === 'richdoc') {
        renderOutline([]);
        var outlineEl = document.getElementById('outline-list');
        if (outlineEl) outlineEl.innerHTML = '<div style="padding:12px 16px;color:var(--color-text-secondary);font-size:12px;">此文档类型使用编辑器内置目录</div>';
      } else {
        renderOutline(extractHeadings(currentMarkdown));
      }
    }, 500);
  }

  function extractHeadings(markdown) {
    var cherryHeadings = extractCherryHeadings();
    if (cherryHeadings) {
      var fallbackHeadings = extractMarkdownHeadings(markdown);
      cherryHeadings.forEach(function(heading, index) {
        if ((heading.line === null || heading.line === undefined) && fallbackHeadings[index]) {
          heading.line = fallbackHeadings[index].line;
        }
      });
      return cherryHeadings;
    }
    return extractMarkdownHeadings(markdown);
  }

  function extractCherryHeadings() {
    var instance = cherryEditor || cherryPreview;
    if (!instance || typeof instance.getHtml !== 'function' || typeof DOMParser === 'undefined') return null;
    try {
      var html = instance.getHtml();
      var doc = new DOMParser().parseFromString(html || '', 'text/html');
      var nodes = doc.querySelectorAll('h1, h2, h3, h4, h5, h6');
      return Array.prototype.map.call(nodes, function(node, index) {
        return {
          level: Math.min(parseInt(node.tagName.slice(1), 10) || 1, 4),
          text: (node.textContent || '').trim(),
          index: index,
          line: null,
        };
      }).filter(function(heading) {
        return heading.text;
      });
    } catch (e) {
      return null;
    }
  }

  function extractMarkdownHeadings(markdown) {
    if (!markdown) return [];
    var headings = [];
    var lines = markdown.split('\n');
    var activeFence = null;
    function getFenceMarker(line) {
      var m = line.match(/^\s{0,3}(`{3,}|~{3,})/);
      return m ? m[1] : null;
    }
    for (var i = 0; i < lines.length; i++) {
      var fence = getFenceMarker(lines[i]);
      if (activeFence) {
        if (fence && fence.charAt(0) === activeFence.charAt(0) && fence.length >= activeFence.length) {
          activeFence = null;
        }
        continue;
      }
      if (fence) {
        activeFence = fence;
        continue;
      }
      var m = lines[i].match(/^\s{0,3}(#{1,6})[ \t]+(.+)$/);
      if (m) {
        var level = m[1].length;
        var text = m[2].trim().replace(/[ \t]+#+[ \t]*$/, '').trim();
        text = text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
        text = text.replace(/`([^`]+)`/g, '$1');
        text = text.replace(/[*_~]+/g, '');
        headings.push({ level: Math.min(level, 4), text: text, index: headings.length, line: i });
      }
    }
    return headings;
  }

  function renderOutline(headings) {
    var container = document.getElementById('outline-content');
    if (!container) return;
    container.innerHTML = '';
    if (headings.length === 0) {
      container.innerHTML = '<div class="outline-empty"><i class="fa-solid fa-list-ul"></i><p>当前文档无标题</p></div>';
      return;
    }
    headings.forEach(function(h, idx) {
      var item = document.createElement('div');
      item.className = 'outline-item outline-h' + h.level;
      item.setAttribute('tabindex', '0');
      item.setAttribute('role', 'link');
      item.setAttribute('aria-label', '跳转到 ' + h.text);
      item.title = h.text;
      item.innerHTML = '<span class="outline-item-text">' + escHtml(h.text) + '</span><span class="outline-item-badge">H' + h.level + '</span>';
      item.dataset.index = idx;
      item.onclick = function() { scrollToHeading(idx); };
      item.onkeydown = function(e) { if (e.key === 'Enter') scrollToHeading(idx); };
      container.appendChild(item);
    });
  }

  function scrollToHeading(index) {
    if (mode === 'preview' || (isMobile() && currentPagerPage === 'preview')) {
      // On mobile, switch to preview page first if in edit mode
      if (isMobile() && currentPagerPage === 'edit') {
        switchPagerPage('preview');
        // Wait for preview to render before scrolling
        setTimeout(function() {
          var previewArea = document.getElementById('preview-area');
          if (!previewArea) return;
          var headingEls = previewArea.querySelectorAll('h1, h2, h3, h4, h5, h6');
          if (headingEls[index]) {
            headingEls[index].scrollIntoView({ behavior: 'smooth', block: 'start' });
          }
        }, 400);
        return;
      }
      var previewArea = document.getElementById('preview-area');
      if (!previewArea) return;
      var headingEls = previewArea.querySelectorAll('h1, h2, h3, h4, h5, h6');
      if (headingEls[index]) {
        headingEls[index].scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    } else if (cherryEditor) {
      try {
        var cmView = cherryEditor.getCodeMirror();
        if (cmView) {
          var heading = extractHeadings(currentMarkdown)[index];
          var targetLine = heading ? heading.line : -1;
          if (targetLine >= 0) {
            var lineInfo = cmView.state.doc.line(targetLine + 1);
            cmView.dispatch({
              selection: { anchor: lineInfo.from },
              scrollIntoView: true,
            });
            cmView.focus();
          }
        }
      } catch (e) {}
    }
    setActiveOutlineItem(index);
  }

  function setActiveOutlineItem(index) {
    var items = document.querySelectorAll('.outline-item');
    items.forEach(function(el) { el.classList.remove('active'); });
    var target = document.querySelector('.outline-item[data-index="' + index + '"]');
    if (target) target.classList.add('active');
  }

  function expandOutlineAll() {
    var items = document.querySelectorAll('.outline-item');
    items.forEach(function(el) { el.style.display = ''; });
  }
  window.expandOutlineAll = expandOutlineAll;

  function collapseOutlineAll() {
    var items = document.querySelectorAll('.outline-item');
    items.forEach(function(el) {
      if (el.classList.contains('outline-h2') || el.classList.contains('outline-h3') || el.classList.contains('outline-h4')) {
        el.style.display = 'none';
      }
    });
  }
  window.collapseOutlineAll = collapseOutlineAll;

  // ======== Shared: Sidebar Toggle ========
  function isMobile() {
    return window.innerWidth <= 768;
  }

  function toggleSidebar() {
    if (isMobile()) {
      var sb = document.getElementById('sidebar');
      if (sb.classList.contains('drawer-open')) {
        closeDrawer();
      } else {
        openDrawer();
      }
      return;
    }
    var sb = document.getElementById('sidebar');
    var collapseBtn = document.getElementById('collapseBtn');
    var isCollapsed = sb.classList.contains('collapsed');
    if (isCollapsed) {
      sb.classList.remove('collapsed');
      if (collapseBtn) collapseBtn.classList.remove('visible');
    } else {
      sb.classList.add('collapsed');
      if (collapseBtn) collapseBtn.classList.add('visible');
    }
  }
  window.toggleSidebar = toggleSidebar;

  function openDrawer() {
    var sb = document.getElementById('sidebar');
    var overlay = document.getElementById('drawerOverlay');
    sb.classList.add('drawer-open');
    sb.classList.remove('collapsed');
    overlay.classList.add('active');
  }
  window.openDrawer = openDrawer;

  function closeDrawer() {
    var sb = document.getElementById('sidebar');
    var overlay = document.getElementById('drawerOverlay');
    sb.classList.remove('drawer-open');
    overlay.classList.remove('active');
  }
  window.closeDrawer = closeDrawer;

  // ======== Shared: Sidebar Tabs ========
  function initSidebarTabs() {
    switchSidebarTab(activeSidebarTab);
  }

  function switchSidebarTab(tab) {
    activeSidebarTab = tab;
    localStorage.setItem('bookstark_sidebar_tab', tab);

    var tabTree = document.getElementById('tab-tree');
    var tabOutline = document.getElementById('tab-outline');
    var panelTree = document.getElementById('panel-tree');
    var panelOutline = document.getElementById('panel-outline');

    if (tab === 'tree' && tabTree && panelTree) {
      tabTree.classList.add('active');
      tabTree.setAttribute('aria-selected', 'true');
      tabOutline.classList.remove('active');
      tabOutline.setAttribute('aria-selected', 'false');
      panelTree.classList.add('active');
      panelOutline.classList.remove('active');
    } else {
      tabOutline.classList.add('active');
      tabOutline.setAttribute('aria-selected', 'true');
      if (tabTree) {
        tabTree.classList.remove('active');
        tabTree.setAttribute('aria-selected', 'false');
      }
      if (panelTree) panelTree.classList.remove('active');
      panelOutline.classList.add('active');
      renderOutline(extractHeadings(currentMarkdown));
    }
  }
  window.switchSidebarTab = switchSidebarTab;

  // ======== Shared: Event Listeners ========
  var overlay = document.getElementById('drawerOverlay');
  if (overlay) overlay.addEventListener('click', closeDrawer);

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && isMobile()) closeDrawer();
  });

  var _prevMobile = isMobile();
  window.addEventListener('resize', function() {
    var nowMobile = isMobile();
    if (_prevMobile && !nowMobile) {
      closeDrawer();
      var sb = document.getElementById('sidebar');
      if (sb && IS_BOOK) sb.classList.remove('collapsed');
      // Reset pager for desktop
      var track = document.getElementById('pagerTrack');
      if (track) track.classList.remove('show-preview');
      renderContent();
    }
    if (!_prevMobile && nowMobile) {
      var sb2 = document.getElementById('sidebar');
      if (sb2) sb2.classList.remove('collapsed');
      // Initialize pager for mobile
      renderContent();
    }
    _prevMobile = nowMobile;
  });
  // iOS Safari: visualViewport fallback for soft keyboard
  if (window.visualViewport) {
    var _kbBody = document.body;
    function _handleVVResize() {
      var vv = window.visualViewport;
      var diff = window.innerHeight - vv.height;
      if (diff > 100) {
        _kbBody.style.height = vv.height + 'px';
      } else {
        _kbBody.style.height = '';
      }
    }
    window.visualViewport.addEventListener('resize', _handleVVResize);
  }
  // ======== Book-Only: Document Tree ========
  if (IS_BOOK) {

    async function loadDocTree() {
      var res = await fetch('/api/books/' + bookId + '/docs/tree');
      var data = await res.json();
      docTree = data.data || [];
      loadCollapsedState();
      renderTree(docTree);
      if (currentDocId) updateStatusbarDocTitleFromTree();
    }
    window.__bookReloadDocTree = loadDocTree;
    // Expose current selection info for AI outline dialog
    window.__bookGetCurrentDocInfo = function() {
      if (!currentDocId) return null;
      var node = findNodeById(docTree, currentDocId);
      if (!node) return null;
      return { id: node.document_id, name: node.document_name || '' };
    };
    // Rich context for the in-editor AI assistant: book title, ancestors,
    // current chapter, and sibling titles. The AI can use this to make
    // continuations / drafts feel coherent with the rest of the book.
    window.__bookGetEditorContext = function() {
      if (!currentDocId) return null;
      var ancestors = getAncestors(docTree, currentDocId) || [];
      var current = ancestors.length ? ancestors[ancestors.length - 1] : null;
      var parents = ancestors.slice(0, -1).map(function(a) { return a.name; }).filter(Boolean);
      var sib = getSiblingInfo(docTree, currentDocId);
      var siblingNames = sib ? sib.siblings
        .filter(function(n) { return n.document_id !== currentDocId; })
        .map(function(n) { return n.document_name; })
        .filter(Boolean) : [];
      return {
        bookName: bookName || '',
        chapterName: current ? current.name : '',
        parentChain: parents,
        siblings: siblingNames
      };
    };

    function isCurrentDoc(docId) {
      return currentDocId !== null && String(currentDocId) === String(docId);
    }

    function renderTree(nodes, container) {
      var el = container || document.getElementById('doc-tree');
      if (!container) el.innerHTML = '';
      nodes.forEach(function(n) {
        // 正在 inline 编辑的节点跳过，保留其 DOM
        if (_inlineEditingDocId && n.document_id === _inlineEditingDocId) {
          var existing = el.querySelector('.tree-node[data-id="' + n.document_id + '"]');
          if (existing) { el.appendChild(existing); return; }
        }
        var div = document.createElement('div');
        div.dataset.id = n.document_id;
        var hasChildren = n.children && n.children.length > 0;
        var isActive = n.document_id === currentDocId;

        var isCollapsed = collapsedIds.has(n.document_id);
        div.className = 'tree-node' + (isActive ? ' active' : '');
        div.title = n.document_name;
        div.innerHTML =
          '<span class="tree-toggle">' + (hasChildren ? '<span class="toggle-icon">' + (isCollapsed ? '<i class="fa-solid fa-caret-right"></i>' : '<i class="fa-solid fa-caret-down"></i>') + '</span>' : '<span class="toggle-icon-space"></span>') + '</span>' +
          '<span class="tree-icon">' + (hasChildren ? (isCollapsed ? '<i class="fa-solid fa-folder"></i>' : '<i class="fa-solid fa-folder-open"></i>') : (n.doc_type === 'html' ? '<i class="fa-solid fa-code"></i>' : n.doc_type === 'richdoc' ? '<i class="fa-solid fa-file-word"></i>' : n.doc_type === 'spreadsheet' ? '<i class="fa-solid fa-table"></i>' : n.doc_type === 'presentation' ? '<i class="fa-solid fa-display"></i>' : n.doc_type === 'drawing' ? '<i class="fa-solid fa-pen-fancy"></i>' : n.doc_type === 'mindmap' ? '<i class="fa-solid fa-diagram-project"></i>' : '<i class="fa-solid fa-file-lines"></i>')) + '</span>' +
          '<span class="doc-name">' + escHtml(n.document_name) + '</span>';
        div.onclick = function(e) {
          if (hasChildren) {
            toggleExpand(div);
            if (isCurrentDoc(n.document_id) && !docLoadPending) return;
            loadDoc(n.document_id, n.doc_type);
          } else {
            if (isCurrentDoc(n.document_id) && !docLoadPending) return;
            loadDoc(n.document_id, n.doc_type);
          }
        };
        div.draggable = true;
        div.ondragstart = function(e) { e.dataTransfer.setData('text/plain', String(n.document_id)); div.classList.add('dragging'); };
        div.ondragend = function() { div.classList.remove('dragging'); };
        div.ondragover = function(e) { e.preventDefault(); showDropIndicator(e, div); };
        div.ondragleave = function() { clearDropIndicator(div); };
        div.ondrop = function(e) { e.preventDefault(); clearDropIndicator(div); handleDrop(e, n.document_id, div); };

        el.appendChild(div);
        if (hasChildren) {
          var childDiv = document.createElement('div');
          childDiv.className = 'tree-children';
          if (isCollapsed) childDiv.style.display = 'none';
          renderTree(n.children, childDiv);
          el.appendChild(childDiv);
        }
      });
    }

    function toggleExpand(nodeEl) {
      var childDiv = nodeEl.nextElementSibling;
      if (!childDiv || !childDiv.classList.contains('tree-children')) return;
      var docId = parseInt(nodeEl.dataset.id);
      var icon = nodeEl.querySelector('.toggle-icon');
      var isCollapsed = collapsedIds.has(docId);
      if (isCollapsed) {
        childDiv.style.display = '';
        var h = childDiv.scrollHeight;
        childDiv.style.transition = 'none';
        childDiv.style.maxHeight = '0px';
        childDiv.style.opacity = '0';
        childDiv.offsetHeight;
        childDiv.style.transition = 'max-height 0.25s ease-out, opacity 0.2s ease-out';
        childDiv.style.maxHeight = h + 'px';
        childDiv.style.opacity = '1';
        if (icon) icon.innerHTML = '<i class="fa-solid fa-caret-down"></i>';
        nodeEl.querySelector('.tree-icon').innerHTML = '<i class="fa-solid fa-folder-open"></i>';
        collapsedIds.delete(docId);
        saveCollapsedState();
        var onEnd = function() {
          childDiv.style.maxHeight = '';
          childDiv.style.opacity = '';
          childDiv.style.transition = '';
          childDiv.removeEventListener('transitionend', onEnd);
        };
        childDiv.addEventListener('transitionend', onEnd);
      } else {
        var h = childDiv.scrollHeight;
        childDiv.style.transition = 'none';
        childDiv.style.maxHeight = h + 'px';
        childDiv.style.opacity = '1';
        childDiv.offsetHeight;
        childDiv.style.transition = 'max-height 0.2s ease-in, opacity 0.15s ease-in';
        childDiv.style.maxHeight = '0px';
        childDiv.style.opacity = '0';
        if (icon) icon.innerHTML = '<i class="fa-solid fa-caret-right"></i>';
        nodeEl.querySelector('.tree-icon').innerHTML = '<i class="fa-solid fa-folder"></i>';
        collapsedIds.add(docId);
        saveCollapsedState();
        var onEnd2 = function() {
          if (collapsedIds.has(docId)) childDiv.style.display = 'none';
          childDiv.style.maxHeight = '';
          childDiv.style.opacity = '';
          childDiv.style.transition = '';
          childDiv.removeEventListener('transitionend', onEnd2);
        };
        childDiv.addEventListener('transitionend', onEnd2);
      }
    }

    function findFirstLeaf(nodes) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].children && nodes[i].children.length > 0) {
          var leaf = findFirstLeaf(nodes[i].children);
          if (leaf) return leaf;
        }
        return nodes[i];
      }
      return null;
    }

    function flattenTree(nodes, result) {
      result = result || [];
      nodes.forEach(function(n) {
        result.push(n);
        if (n.children) flattenTree(n.children, result);
      });
      return result;
    }

    function findNodeById(nodes, id) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].document_id === id) return nodes[i];
        if (nodes[i].children) {
          var found = findNodeById(nodes[i].children, id);
          if (found) return found;
        }
      }
      return null;
    }

    function getAncestors(tree, docId) {
      function find(nodes, path) {
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          var newPath = path.concat([{id: n.document_id, name: n.document_name}]);
          if (n.document_id === docId) return newPath;
          if (n.children && n.children.length) {
            var found = find(n.children, newPath);
            if (found) return found;
          }
        }
        return null;
      }
      return find(tree, []) || [{id: docId, name: ''}];
    }

    function getSiblingInfo(tree, docId) {
      function find(nodes, parentId) {
        for (var i = 0; i < nodes.length; i++) {
          if (nodes[i].document_id === docId) {
            return { siblings: nodes, index: i, parentId: parentId };
          }
          if (nodes[i].children && nodes[i].children.length) {
            var found = find(nodes[i].children, nodes[i].document_id);
            if (found) return found;
          }
        }
        return null;
      }
      return find(tree, 0);
    }

    // ======== Book-Only: Doc Footer ========
    function updateDocFooter() {
      var footer = document.getElementById('doc-footer');
      var tbNewChild = document.getElementById('tb-new-child');
      var tbRename = document.getElementById('tb-rename');
      var tbDelete = document.getElementById('tb-delete');
      if (!footer) return;
      if (currentDocId) {
        footer.style.display = '';
        if (tbNewChild) tbNewChild.style.display = '';
        if (tbRename) tbRename.style.display = '';
        if (tbDelete) tbDelete.style.display = '';
        var node = findNodeById(docTree, currentDocId);
        var hasChildren = node && node.children && node.children.length > 0;
        if (tbDelete) {
          if (hasChildren) {
            tbDelete.classList.add('opacity-30', 'cursor-not-allowed');
            tbDelete.disabled = true;
          } else {
            tbDelete.classList.remove('opacity-30', 'cursor-not-allowed');
            tbDelete.disabled = false;
          }
        }
        // Move button states
        var info = getSiblingInfo(docTree, currentDocId);
        var btnUp = document.getElementById('btn-move-up');
        var btnDown = document.getElementById('btn-move-down');
        var btnIndent = document.getElementById('btn-indent');
        var btnOutdent = document.getElementById('btn-outdent');
        if (info) {
          if (btnUp) btnUp.disabled = info.index === 0;
          if (btnDown) btnDown.disabled = info.index === info.siblings.length - 1;
          if (btnIndent) btnIndent.disabled = info.index === 0;
          if (btnOutdent) btnOutdent.disabled = info.parentId === 0;
        } else {
          if (btnUp) btnUp.disabled = true;
          if (btnDown) btnDown.disabled = true;
          if (btnIndent) btnIndent.disabled = true;
          if (btnOutdent) btnOutdent.disabled = true;
        }
      } else {
        footer.style.display = 'none';
        if (tbNewChild) tbNewChild.style.display = '';
        if (tbRename) tbRename.style.display = 'none';
        if (tbDelete) tbDelete.style.display = 'none';
      }
    }

    function updateStatusbarDocTitleFromTree() {
      var ancestors = getAncestors(docTree, currentDocId) || [];
      var current = ancestors.length ? ancestors[ancestors.length - 1] : null;
      var pathItems = [{ id: 0, name: bookName || '' }].concat(ancestors);
      setStatusbarDocTitle(current ? current.name : bookName, pathItems);
    }

    function addDocFromToolbar() {
      addDoc(currentDocId || 0, { allowRootChoice: !!currentDocId });
    }
    window.addDocFromToolbar = addDocFromToolbar;

    function renameCurrentDoc() {
      if (!currentDocId) return;
      var el = document.querySelector('.tree-node[data-id="' + currentDocId + '"]');
      if (el) startRename(currentDocId, el);
    }
    window.renameCurrentDoc = renameCurrentDoc;

    function deleteCurrentDoc() {
      if (!currentDocId) return;
      deleteDoc(currentDocId);
    }
    window.deleteCurrentDoc = deleteCurrentDoc;

    // ======== Book-Only: Document Operations ========
    async function loadDoc(docId, hintDocType) {
      if (isCurrentDoc(docId) && !docLoadPending) return;

      var loadSequence = ++docLoadSequence;
      docLoadPending = true;
      if (docLoadController) {
        docLoadController.abort();
        docLoadController = null;
      }

      function finishDocLoad() {
        if (loadSequence !== docLoadSequence) return;
        docLoadPending = false;
        docLoadController = null;
      }

      if (currentDocId && saveMgr && (saveMgr.getSaveStatus() === 'unsaved' || saveMgr.getSaveStatus() === 'saving')) {
        try {
          await saveMgr.manualSave();
        } catch (error) {
          BookStarkEditor.toast('当前文档保存失败，请检查网络后重试', 'error');
          finishDocLoad();
          return;
        }
      }
      if (loadSequence !== docLoadSequence) return;
      if (saveMgr && saveMgr.destroy) saveMgr.destroy();

      // Special editors render their own loading state.
      var previewArea = document.getElementById('preview-area');
      var editorArea = document.getElementById('editor-area');
      var editorPage = document.getElementById('editor-page');
      var previewPage = document.getElementById('preview-page');
      if (previewArea && hintDocType !== 'spreadsheet' && hintDocType !== 'drawing' && hintDocType !== 'mindmap' && hintDocType !== 'presentation') {
        BookStarkEditor.showLoading(previewArea);
      }
      if (isMobile()) {
        // Mobile: keep current pager page matching current mode
        switchPagerPage(mode === 'preview' ? 'preview' : 'edit');
      } else {
        if (mode === 'preview') {
          if (previewPage) previewPage.classList.add('active-desktop');
          if (editorPage) editorPage.classList.remove('active-desktop');
        } else {
          if (editorPage) editorPage.classList.add('active-desktop');
          if (previewPage) previewPage.classList.remove('active-desktop');
        }
      }

      // Destroy existing Cherry instance on doc switch
      if (cherryEditor) {
        try { cherryEditor.destroy(); } catch(e) {}
        cherryEditor = null;
        window._cherryEditor = null;
      }
      if (htmlEditor) {
        try { htmlEditor.destroy(); } catch(e) {}
        htmlEditor = null;
      }
      if (richdocEditor) {
        try { richdocEditor.destroy(); } catch(e) {}
        richdocEditor = null;
        window._richdocEditor = null;
      }
      if (currentDocType === 'presentation' && window.BookStarkPPTist) {
        BookStarkPPTist.destroy();
        var presentationEditorPage = document.getElementById('editor-page');
        if (presentationEditorPage) {
          presentationEditorPage.style.overflow = '';
          presentationEditorPage.classList.remove('spreadsheet-mobile-full');
        }
        var presentationContainer = document.getElementById('presentation-container');
        if (presentationContainer) {
          presentationContainer.classList.add('hidden');
          presentationContainer.classList.remove('presentation-fullwidth');
        }
        var presentationEditorArea = document.getElementById('editor-area');
        if (presentationEditorArea) presentationEditorArea.style.display = '';
        var presentationPreviewArea = document.getElementById('preview-area');
        if (presentationPreviewArea) presentationPreviewArea.style.display = '';
        var presentationModeToggle = document.getElementById('mode-toggle');
        if (presentationModeToggle) presentationModeToggle.style.display = '';
        var presentationPagerTabs = document.querySelector('.pager-tabs');
        if (presentationPagerTabs) presentationPagerTabs.style.display = '';
        var presentationCharCount = document.getElementById('char-count');
        if (presentationCharCount) presentationCharCount.style.display = '';
      }
      // Destroy Univer
      if (currentDocType === 'spreadsheet') {
        BookStarkEditor.destroyUniver();
        BookStarkEditor._loadAborted = true;
        var ep = document.getElementById('editor-page');
        if (ep) ep.style.overflow = '';
        var lc = document.getElementById('univer-container');
        if (lc) {
          lc.classList.add('hidden');
          lc.classList.remove('spreadsheet-fullwidth');
          lc.style.height = '';
        }
        var notice = lc ? lc.querySelector('.spreadsheet-mobile-notice') : null;
        if (notice) notice.remove();
        var ea = document.getElementById('editor-area');
        if (ea) ea.style.display = '';
        var pa = document.getElementById('preview-area');
        if (pa) pa.style.display = '';
        var mt = document.getElementById('mode-toggle');
        if (mt) {
          mt.style.display = '';
          mt.disabled = false;
          mt.classList.remove('opacity-40', 'cursor-not-allowed');
        }
        var cc = document.getElementById('char-count');
        if (cc) cc.style.display = '';
      }
      if (currentDocType === 'drawing') {
        BookStarkEditor.destroyExcalidraw();
        BookStarkEditor._loadAborted = true;
        var ep2 = document.getElementById('editor-page');
        if (ep2) ep2.style.overflow = '';
        var ec = document.getElementById('excalidraw-container');
        if (ec) {
          ec.classList.add('hidden');
          ec.classList.remove('spreadsheet-fullwidth');
          ec.style.height = '';
        }
        var ea2 = document.getElementById('editor-area');
        if (ea2) ea2.style.display = '';
        var pa2 = document.getElementById('preview-area');
        if (pa2) pa2.style.display = '';
        var mt2 = document.getElementById('mode-toggle');
        if (mt2) {
          mt2.style.display = '';
          mt2.disabled = false;
          mt2.classList.remove('opacity-40', 'cursor-not-allowed');
        }
        var cc2 = document.getElementById('char-count');
        if (cc2) cc2.style.display = '';
      }
      if (currentDocType === 'mindmap') {
        BookStarkEditor.destroyMindElixir();
        BookStarkEditor._loadAborted = true;
        var ep3 = document.getElementById('editor-page');
        if (ep3) ep3.classList.remove('spreadsheet-mobile-full');
        var mc = document.getElementById('mindmap-container');
        if (mc) {
          mc.classList.add('hidden');
          mc.classList.remove('spreadsheet-fullwidth');
        }
        var ea3 = document.getElementById('editor-area');
        if (ea3) ea3.style.display = '';
        var pa3 = document.getElementById('preview-area');
        if (pa3) pa3.style.display = '';
        var mt3 = document.getElementById('mode-toggle');
        if (mt3) mt3.style.display = '';
        var cc3 = document.getElementById('char-count');
        if (cc3) cc3.style.display = '';
        var pagerTabs2 = document.querySelector('.pager-tabs');
        if (pagerTabs2) pagerTabs2.style.display = '';
      }
      cherryContainerReady = false;

      docLoadController = new AbortController();
      var res;
      try {
        res = await fetch('/api/docs/' + docId, { cache: 'no-store', signal: docLoadController.signal });
      } catch (error) {
        if (error && error.name === 'AbortError') return;
        BookStarkEditor.toast('文档加载失败，请检查网络后重试', 'error');
        finishDocLoad();
        return;
      }
      if (loadSequence !== docLoadSequence) return;
      if (!res.ok) {
        BookStarkEditor.toast('文档加载失败，请稍后重试', 'error');
        finishDocLoad();
        return;
      }
      var data = await res.json();
      if (loadSequence !== docLoadSequence) return;
      var doc = data.data;

      currentDocId = docId;
      currentDocType = doc.doc_type || 'markdown';
      prevDocId = doc.prev_id || 0;
      nextDocId = doc.next_id || 0;

      // Respect current toolbar mode for all doc types

      // Pager tabs managed by render functions for spreadsheet/drawing
      var pagerTabs = document.querySelector('.pager-tabs');
      if (pagerTabs) {
        pagerTabs.style.display = '';
      }

      updateStatusbarModifyTime(doc.modify_time);

      // Notify tag editor of document switch
      if (typeof editorTagsSwitchDoc === 'function') editorTagsSwitchDoc(docId);

      saveMgr = BookStarkEditor.setupAutoSave({
        getContent: function() {
          if (currentDocType === 'richdoc') {
            if (!richdocEditor) return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            try { return richdocEditor.getContent(); } catch (e) { BookStarkEditor.toast(e.message, 'error'); return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown; }
          }
          if (currentDocType === 'spreadsheet') {
            var content = BookStarkEditor.getSpreadsheetContent();
            if (!content) {
              // Spreadsheet content unavailable (e.g. during init/destroy).
              // Return lastSaved to avoid overwriting server data with stale content.
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            if (content.length > 5 * 1024 * 1024) {
              BookStarkEditor.toast('数据量较大，保存可能较慢', 'warning');
            }
            return content;
          }
          if (currentDocType === 'drawing') {
            var drawingContent = BookStarkEditor.getDrawingContent();
            if (!drawingContent) {
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            if (drawingContent.length > 5 * 1024 * 1024) {
              BookStarkEditor.toast(window.__('editor.drawing.data_too_large'), 'warning');
            }
            return drawingContent;
          }
          if (currentDocType === 'mindmap') {
            var mindmapContent = BookStarkEditor.getMindElixirData();
            if (!mindmapContent) {
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            if (mindmapContent.length > 5 * 1024 * 1024) {
              BookStarkEditor.toast(window.__('editor.mindmap.data_too_large'), 'warning');
            }
            return mindmapContent;
          }
          if (currentDocType === 'presentation') {
            return BookStarkPPTist.getContent() || (saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown);
          }
          return currentMarkdown;
        },
        saveFn: function(content) {
          return csrfFetch('/api/docs/' + docId, {
            method: 'PUT',
            offlinePolicy: 'reject',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ markdown: content })
          }).then(function(r) {
            if (!r.ok || r.headers.get('X-Offline-Queued') === 'true') throw new Error('save failed');
            var now = new Date();
            var mm = String(now.getMonth() + 1).padStart(2, '0');
            var dd = String(now.getDate()).padStart(2, '0');
            var hh = String(now.getHours()).padStart(2, '0');
            var mi = String(now.getMinutes()).padStart(2, '0');
            var timeStr = now.getFullYear() + '-' + mm + '-' + dd + ' ' + hh + ':' + mi;
            updateStatusbarModifyTime(timeStr);
          });
        },
        draftKey: 'bookstark_draft_' + docId,
        onStatusChange: BookStarkEditor.updateSaveStatus,
      });

      var serverContent = doc.markdown || '';
      if ((currentDocType === 'html' || currentDocType === 'richdoc') && doc.content_url) {
        try {
          serverContent = await fetchRawHTMLContent(doc.content_url, { cache: 'no-store', signal: docLoadController.signal });
        } catch (error) {
          if (error && error.name === 'AbortError') return;
          BookStarkEditor.toast(error && error.message || 'HTML 内容加载失败', 'error');
          finishDocLoad();
          return;
        }
      }
      if (loadSequence !== docLoadSequence) return;
      docLoadController = null;
      var draftResult = await saveMgr.loadDraft(serverContent);
      if (loadSequence !== docLoadSequence) return;
      currentMarkdown = draftResult.content;
      saveMgr.setLastSaved(serverContent);
      if (draftResult.hasDraft) {
        showDraftBanner(draftResult.serverContent, draftResult.draftContent);
      } else {
        hideDraftBanner();
      }

      // Spreadsheet dirty check polling
      if (spreadsheetCheckInterval) {
        clearInterval(spreadsheetCheckInterval);
        spreadsheetCheckInterval = null;
      }
      if (currentDocType === 'spreadsheet' && saveMgr) {
        spreadsheetCheckInterval = setInterval(function() {
          if (currentDocType !== 'spreadsheet') {
            clearInterval(spreadsheetCheckInterval);
            spreadsheetCheckInterval = null;
            return;
          }
          if (BookStarkEditor.isSpreadsheetDirty()) {
            BookStarkEditor.setSpreadsheetDirty(false);
            // Only trigger save in edit mode; preview mode is read-only.
            if (mode !== 'preview' && saveMgr && saveMgr.onContentChange) {
              saveMgr.onContentChange();
            }
            BookStarkEditor.updateCharCount();
          }
        }, 2000);
      }

      // Update breadcrumb
      var ancestors = getAncestors(docTree, docId);
      var bcEl = document.getElementById('breadcrumb');
      if (bcEl) {
        var bcHtml = '<span class="breadcrumb-item" onclick="goDoc(0)">' + escHtml(bookName) + '</span>';
        for (var i = 0; i < ancestors.length; i++) {
          bcHtml += '<i class="fa-solid fa-chevron-right breadcrumb-sep"></i>';
          if (i < ancestors.length - 1) {
            bcHtml += '<span class="breadcrumb-item" onclick="goDoc(' + ancestors[i].id + ')">' + escHtml(ancestors[i].name) + '</span>';
          } else {
            bcHtml += '<span class="breadcrumb-item breadcrumb-current">' + escHtml(ancestors[i].name) + '</span>';
          }
        }
        bcEl.innerHTML = bcHtml;
      }
      updateStatusbarDocTitleFromTree();

      // Update prev/next buttons
      var prevBtn = document.getElementById('btn-prev-doc');
      var nextBtn = document.getElementById('btn-next-doc');
      if (prevBtn) prevBtn.disabled = !prevDocId;
      if (nextBtn) nextBtn.disabled = !nextDocId;

      renderTree(docTree);
      // Update URL with current doc ID
      if (window.history.replaceState) {
        var url = new URL(window.location);
        url.searchParams.set('doc', currentDocId);
        window.history.replaceState(null, '', url.toString());
      }
      updateDocFooter();
      if (activeSidebarTab === 'outline') {
        if (currentDocType === 'html') {
          renderOutline([]);
          var outlineEl = document.getElementById('outline-list');
          if (outlineEl) outlineEl.innerHTML = '<div style="padding:12px 16px;color:var(--color-text-secondary);font-size:12px;">HTML 文档不支持大纲</div>';
        } else {
          renderOutline(extractHeadings(currentMarkdown));
        }
      }
      renderContent();
      finishDocLoad();
    }

    function goDoc(id) { if (id) loadDoc(id); }
    window.goDoc = goDoc;

    function exportMindmapPng() {
      var docNameEl = document.querySelector('.breadcrumb-current');
      var filename = docNameEl ? docNameEl.textContent.trim() : window.__('editor.create_doc.type.mindmap');
    }
    window.exportMindmapPng = exportMindmapPng;

    function exportMindmapSvg() {
      var docNameEl = document.querySelector('.breadcrumb-current');
      var filename = docNameEl ? docNameEl.textContent.trim() : window.__('editor.create_doc.type.mindmap');
    }
    window.exportMindmapSvg = exportMindmapSvg;

    function goPrevDoc() { if (prevDocId) loadDoc(prevDocId); }
    window.goPrevDoc = goPrevDoc;

    function goNextDoc() { if (nextDocId) loadDoc(nextDocId); }
    window.goNextDoc = goNextDoc;

    // ======== Book-Only: Doc CRUD ========
    async function addDoc(defaultParentId, opts) {
      var parentId = defaultParentId || 0;
      var choice = await showCreateDocDialog(opts || {});
      if (!choice) return;
      if (choice.createAtRoot) parentId = 0;
      if (parentId) collapsedIds.delete(parentId);
      var res = await csrfFetch('/api/books/' + bookId + '/docs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parent_id: parentId, doc_type: choice.docType, document_name: choice.name })
      });
      if (res.ok) {
        await loadDocTree();
        var d = await res.json();
        loadDoc(d.data.document_id);
        BookStarkEditor.toast('文档已创建', 'success');
      } else {
        var d = await res.json();
        BookStarkEditor.alert2(d.message || '创建失败');
      }
    }

    function showCreateDocDialog(opts) {
      opts = opts || {};
      return new Promise(function(resolve) {
        var overlay = document.createElement('div');
        overlay.className = 'bs-dialog-overlay active';
        var box = document.createElement('div');
        box.className = 'bs-dialog-box';
        box.setAttribute('role', 'dialog');
        box.setAttribute('aria-modal', 'true');
        box.setAttribute('aria-label', '新建文档');
        box.innerHTML =
          '<div class="create-doc-mobile-handle"></div>' +
          '<div class="bs-dialog-title">' + window.__('editor.create_doc.title') + '</div>' +
          '<div class="create-doc-type-grid">' +
            '<button class="create-doc-type-btn active" data-type="markdown" type="button">' +
              '<span class="create-doc-type-icon type-icon-md"><i class="fa-solid fa-file-lines"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.markdown') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.markdown_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="html" type="button">' +
              '<span class="create-doc-type-icon type-icon-html"><i class="fa-solid fa-code"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.html') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.html_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="richdoc" type="button">' +
              '<span class="create-doc-type-icon type-icon-rich"><i class="fa-solid fa-file-word"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.richdoc') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.richdoc_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="spreadsheet" type="button">' +
              '<span class="create-doc-type-icon type-icon-tbl"><i class="fa-solid fa-table"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.spreadsheet') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.spreadsheet_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="presentation" type="button">' +
              '<span class="create-doc-type-icon type-icon-presentation"><i class="fa-solid fa-display"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.presentation') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.presentation_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="drawing" type="button">' +
              '<span class="create-doc-type-icon type-icon-draw"><i class="fa-solid fa-pen-fancy"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.drawing') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.drawing_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
            '<button class="create-doc-type-btn" data-type="mindmap" type="button">' +
              '<span class="create-doc-type-icon type-icon-mind"><i class="fa-solid fa-diagram-project"></i></span>' +
              '<span class="create-doc-type-label">' + window.__('editor.create_doc.type.mindmap') + '</span>' +
              '<span class="create-doc-type-desc">' + window.__('editor.create_doc.type.mindmap_desc') + '</span>' +
              '<span class="create-doc-check-badge"><i class="fa-solid fa-check"></i></span>' +
            '</button>' +
          '</div>' +
          '<div class="bs-dialog-input-wrap">' +
            '<input id="create-doc-name" class="bs-dialog-input dialog-input" placeholder="' + window.__('editor.create_doc.name_placeholder') + '" value="">' +
          '</div>' +
          (opts.allowRootChoice ? '<label class="create-doc-root-option"><input id="create-doc-root" type="checkbox"><span>' + window.__('editor.create_doc.root') + '</span></label>' : '') +
          '<div class="bs-dialog-actions">' +
            '<button class="bs-btn bs-btn-cancel" id="create-doc-cancel" type="button">' + window.__('editor.create_doc.cancel') + '</button>' +
            '<button class="bs-btn bs-btn-primary" id="create-doc-ok" type="button">' + window.__('editor.create_doc.create') + '</button>' +
          '</div>';
        overlay.appendChild(box);
        document.body.appendChild(overlay);
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('create-doc-dialog');

        var selectedType = 'markdown';
        box.querySelectorAll('.create-doc-type-btn').forEach(function(btn) {
          btn.onclick = function() {
            box.querySelectorAll('.create-doc-type-btn').forEach(function(b) { b.classList.remove('active'); });
            btn.classList.add('active');
            selectedType = btn.getAttribute('data-type');
          };
        });

        var nameInput = document.getElementById('create-doc-name');
        var rootInput = document.getElementById('create-doc-root');
        if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') window.BookStarkFormGuards.markNonCredentialInput(nameInput);
        setTimeout(function() { nameInput.focus(); }, 50);

        function close(val) {
          if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
          if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('create-doc-dialog');
          resolve(val);
        }

        document.getElementById('create-doc-ok').onclick = function() {
          var name = nameInput.value.trim();
          if (!name) name = '未命名文档';
          close({ docType: selectedType, name: name, createAtRoot: !!(rootInput && rootInput.checked) });
        };
        document.getElementById('create-doc-cancel').onclick = function() { close(null); };
        nameInput.onkeydown = function(e) {
          if (e.key === 'Enter') {
            var name = nameInput.value.trim();
            if (!name) name = '未命名文档';
            close({ docType: selectedType, name: name, createAtRoot: !!(rootInput && rootInput.checked) });
          }
          if (e.key === 'Escape') { close(null); }
        };
        overlay.onclick = function(e) { if (e.target === overlay) close(null); };
      });
    }

    var _inlineEditingDocId = 0;

    function _inlineRenameNewDoc(docId) {
      _inlineEditingDocId = docId;
      var el = document.querySelector('.tree-node[data-id="' + docId + '"]');
      if (!el) return;
      var nameSpan = el.querySelector('.doc-name');
      if (!nameSpan) return;
      var input = document.createElement('input');
      input.className = 'rename-input';
      input.value = '';
      if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') window.BookStarkFormGuards.markNonCredentialInput(input);
      nameSpan.replaceWith(input);
      input.focus();
      var finished = false;
      var finish = async function() {
        if (finished) return;
        finished = true;
        _inlineEditingDocId = 0;
        var newName = input.value.trim();
        if (!newName) {
          // 名称为空，删除刚创建的文档
          await csrfFetch('/api/docs/' + docId, { method: 'DELETE' });
          await loadDocTree();
          return;
        }
        var r = await csrfFetch('/api/docs/' + docId, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ document_name: newName }) });
        if (r.ok) {
          await loadDocTree();
          loadDoc(docId);
          BookStarkEditor.toast('文档已创建', 'success');
        } else {
          var d = await r.json();
          BookStarkEditor.alert2(d.message || '重命名失败');
          await loadDocTree();
        }
      };
      input.onblur = finish;
      input.onkeydown = function(e) {
        if (e.key === 'Enter') input.blur();
        if (e.key === 'Escape') { input.value = ''; input.blur(); }
      };
    }

    function startRename(docId, el) {
      var nameSpan = el.querySelector('.doc-name');
      if (!nameSpan) return;
      var oldName = nameSpan.textContent;
      var input = document.createElement('input');
      input.className = 'rename-input';
      input.value = oldName;
      if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') window.BookStarkFormGuards.markNonCredentialInput(input);
      nameSpan.replaceWith(input);
      input.focus();
      input.select();
      var finish = async function() {
        var newName = input.value.trim() || oldName;
        var r = await csrfFetch('/api/docs/' + docId, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ document_name: newName }) });
        if (r.ok) {
          await loadDocTree();
          if (newName !== oldName) BookStarkEditor.toast('已重命名', 'success');
        } else {
          var d = await r.json();
          BookStarkEditor.alert2(d.message || '重命名失败');
          await loadDocTree();
        }
      };
      input.onblur = finish;
      input.onkeydown = function(e) { if (e.key === 'Enter') input.blur(); if (e.key === 'Escape') { input.value = oldName; input.blur(); } };
    }

    async function deleteDoc(docId) {
      var ok = await BookStarkEditor.confirm2('确定删除此文档？');
      if (!ok) return;
      var res = await csrfFetch('/api/docs/' + docId, { method: 'DELETE' });
      if (res.ok) {
        await loadDocTree();
        if (currentDocId === docId) {
          currentDocId = null;
          var pa = document.getElementById('preview-area');
          if (pa) pa.innerHTML = '<p class="text-slate-400 text-center mt-16">请选择一篇文档</p>';
          var ep = document.getElementById('editor-page');
          var pp = document.getElementById('preview-page');
          if (isMobile()) {
            switchPagerPage('preview');
          } else {
            if (pp) pp.classList.add('active-desktop');
            if (ep) ep.classList.remove('active-desktop');
          }
        }
        updateDocFooter();
        BookStarkEditor.toast('文档已删除', 'success');
      } else {
        var d = await res.json();
        BookStarkEditor.alert2(d.message || '删除失败');
      }
    }

    // ======== Book-Only: Search ========
    function searchDocs(query) {
      var container = document.getElementById('doc-tree');
      if (!query) {
        renderTree(docTree);
        return;
      }
      var flat = flattenTree(docTree);
      var filtered = flat.filter(function(n) { return n.document_name.toLowerCase().includes(query.toLowerCase()); });
      container.innerHTML = '';
      filtered.forEach(function(n) {
        var div = document.createElement('div');
        div.className = 'tree-node';
        div.title = n.document_name;
        div.innerHTML = '<span class="tree-icon"><i class="fa-solid ' + (n.doc_type === 'html' ? 'fa-code' : n.doc_type === 'richdoc' ? 'fa-file-word' : n.doc_type === 'spreadsheet' ? 'fa-table' : n.doc_type === 'presentation' ? 'fa-display' : n.doc_type === 'drawing' ? 'fa-pen-fancy' : n.doc_type === 'mindmap' ? 'fa-diagram-project' : 'fa-file-lines') + '"></i></span><span class="doc-name">' + escHtml(n.document_name) + '</span>';
        div.onclick = function() {
          if (isCurrentDoc(n.document_id) && !docLoadPending) return;
          searchDocs('');
          document.getElementById('doc-search').value = '';
          loadDoc(n.document_id, n.doc_type);
        };
        container.appendChild(div);
      });
    }
    window.searchDocs = searchDocs;

    // ======== Book-Only: Expand/Collapse All ========
    var allExpanded = true;

    function toggleExpandAll() {
      allExpanded = !allExpanded;
      var btn = document.getElementById('btn-expand-all');
      var children = document.querySelectorAll('.tree-children');
      children.forEach(function(el) {
        var nodeEl = el.previousElementSibling;
        if (!nodeEl) return;
        var docId = parseInt(nodeEl.dataset.id);
        var icon = nodeEl.querySelector('.toggle-icon');
        var treeIcon = nodeEl.querySelector('.tree-icon');
        if (allExpanded) {
          el.style.display = '';
          var h = el.scrollHeight;
          el.style.transition = 'none';
          el.style.maxHeight = '0px';
          el.style.opacity = '0';
          el.offsetHeight;
          el.style.transition = 'max-height 0.25s ease-out, opacity 0.2s ease-out';
          el.style.maxHeight = h + 'px';
          el.style.opacity = '1';
          if (icon) icon.innerHTML = '<i class="fa-solid fa-caret-down"></i>';
          if (treeIcon) treeIcon.innerHTML = '<i class="fa-solid fa-folder-open"></i>';
          collapsedIds.delete(docId);
          var onEnd = function() {
            el.style.maxHeight = '';
            el.style.opacity = '';
            el.style.transition = '';
            el.removeEventListener('transitionend', onEnd);
          };
          el.addEventListener('transitionend', onEnd);
        } else {
          var h = el.scrollHeight;
          el.style.transition = 'none';
          el.style.maxHeight = h + 'px';
          el.style.opacity = '1';
          el.offsetHeight;
          el.style.transition = 'max-height 0.2s ease-in, opacity 0.15s ease-in';
          el.style.maxHeight = '0px';
          el.style.opacity = '0';
          if (icon) icon.innerHTML = '<i class="fa-solid fa-caret-right"></i>';
          if (treeIcon) treeIcon.innerHTML = '<i class="fa-solid fa-folder"></i>';
          collapsedIds.add(docId);
          var onEnd2 = function() {
            if (collapsedIds.has(docId)) el.style.display = 'none';
            el.style.maxHeight = '';
            el.style.opacity = '';
            el.style.transition = '';
            el.removeEventListener('transitionend', onEnd2);
          };
          el.addEventListener('transitionend', onEnd2);
        }
      });
      if (btn) {
        btn.innerHTML = allExpanded ? '<i class="fa-solid fa-compress"></i>' : '<i class="fa-solid fa-expand"></i>';
        btn.title = allExpanded ? '折叠全部' : '展开全部';
      }
      saveCollapsedState();
    }
    window.toggleExpandAll = toggleExpandAll;

    // ======== Book-Only: Drag & Drop ========
    function showDropIndicator(e, el) {
      var rect = el.getBoundingClientRect();
      var y = e.clientY - rect.top;
      var h = rect.height;
      clearDropIndicator(el);
      if (y < h * 0.25) el.classList.add('drop-before');
      else if (y > h * 0.75) el.classList.add('drop-after');
      else el.classList.add('drop-inside');
    }

    function clearDropIndicator(el) {
      el.classList.remove('drop-before', 'drop-inside', 'drop-after');
    }

    async function handleDrop(e, targetId, el) {
      var srcId = parseInt(e.dataTransfer.getData('text/plain'));
      if (srcId === targetId) return;
      var targetNode = findNodeById(docTree, targetId);
      if (!targetNode) return;
      var rect = el.getBoundingClientRect();
      var y = e.clientY - rect.top;
      var h = rect.height;
      var parentId, orderSort;
      if (y < h * 0.25) {
        parentId = targetNode.parent_id;
        orderSort = targetNode.order_sort > 0 ? targetNode.order_sort - 1 : 0;
      } else if (y > h * 0.75) {
        parentId = targetNode.parent_id;
        orderSort = targetNode.order_sort + 1;
      } else {
        parentId = targetId;
        orderSort = 9999;
      }
      var r = await csrfFetch('/api/docs/' + srcId + '/move', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ parent_id: parentId, order_sort: orderSort }) });
      if (r.ok) {
        await loadDocTree();
      } else {
        var d = await r.json();
        BookStarkEditor.toast(d.message || '移动失败', 'error');
        await loadDocTree();
      }
    }

    // ======== Book-Only: Reorder (Move Up/Down/Indent/Outdent) ========
    async function reorderDoc(direction, successMsg) {
      if (!currentDocId) return;
      var info = getSiblingInfo(docTree, currentDocId);
      var r = await csrfFetch('/api/docs/' + currentDocId + '/reorder', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ direction: direction })
      });
      if (r.ok) {
        if (direction === 'indent' && info && info.index > 0) {
          var newParentId = info.siblings[info.index - 1].document_id;
          collapsedIds.delete(newParentId);
        }
        await loadDocTree();
        updateDocFooter();
        BookStarkEditor.toast(successMsg, 'success');
      } else {
        var d = await r.json();
        BookStarkEditor.toast(d.message || '移动失败', 'error');
      }
    }

    function moveDocUp() { reorderDoc('up', '已上移'); }
    window.moveDocUp = moveDocUp;

    function moveDocDown() { reorderDoc('down', '已下移'); }
    window.moveDocDown = moveDocDown;

    function indentDoc() { reorderDoc('indent', '已降级'); }
    window.indentDoc = indentDoc;

    function outdentDoc() { reorderDoc('outdent', '已升级'); }
    window.outdentDoc = outdentDoc;

    // ======== Book Initialization ========
    async function initBook() {
      initSidebarTabs();
      await loadDocTree();
      if (docTree.length > 0) {
        var params = new URLSearchParams(window.location.search);
        var docParam = params.get('doc');
        var targetDocId = docParam ? parseInt(docParam, 10) : 0;
        if (targetDocId && findNodeById(docTree, targetDocId)) {
          await loadDoc(targetDocId);
        } else {
          var firstLeaf = findFirstLeaf(docTree);
          if (firstLeaf) await loadDoc(firstLeaf.document_id);
        }
      }
    }
    initBook();
  } // end IS_BOOK

  // ======== Initialization ========
  if (!IS_BOOK) {
    var blogPassword = '';
    var BLOG_PWD_MEMORY_PREFIX = 'bookstark:blog-password:v1:';

    function getBlogPasswordMemoryKey() {
      return BLOG_PWD_MEMORY_PREFIX + String(blogId || '');
    }

    function getRememberedBlogPassword() {
      try {
        return window.localStorage ? (localStorage.getItem(getBlogPasswordMemoryKey()) || '') : '';
      } catch(e) {
        return '';
      }
    }

    function rememberBlogPassword(pwd) {
      if (!pwd) return;
      try {
        if (window.localStorage) localStorage.setItem(getBlogPasswordMemoryKey(), pwd);
      } catch(e) {}
    }

    function forgetRememberedBlogPassword(pwd) {
      try {
        if (!window.localStorage) return;
        var remembered = localStorage.getItem(getBlogPasswordMemoryKey()) || '';
        if (!pwd || remembered === pwd) localStorage.removeItem(getBlogPasswordMemoryKey());
      } catch(e) {}
    }

    function showBlogPasswordDialog(errorMsg) {
      return new Promise(function(resolve) {
        var rememberedPwd = errorMsg ? '' : getRememberedBlogPassword();
        var overlay = document.createElement('div');
        overlay.className = 'bs-dialog-overlay active';
        var box = document.createElement('div');
        box.className = 'bs-dialog-box';
        var errorHtml = errorMsg ? '<p class="blog-pwd-error">' + escHtml(errorMsg) + '</p>' : '';
        box.innerHTML = '<h3 class="blog-pwd-title">该博客已加密</h3>' +
          '<p class="blog-pwd-desc">请输入密码以查看和编辑内容</p>' +
          errorHtml +
          '<div class="blog-pwd-input-wrap">' +
          '<input id="blog-pwd-input" class="bs-dialog-input dialog-input" type="password" autocomplete="off" data-lpignore="true" data-1p-ignore="true" placeholder="输入密码" autofocus>' +
          '<button id="blog-pwd-toggle" class="blog-pwd-toggle" type="button" aria-label="显示密码"><i class="fa-solid fa-eye"></i></button>' +
          '</div>' +
          '<div class="blog-pwd-actions">' +
          '<button id="blog-pwd-cancel" class="blog-pwd-btn blog-pwd-btn-cancel">取消</button>' +
          '<button id="blog-pwd-ok" class="blog-pwd-btn blog-pwd-btn-ok">确认</button>' +
          '</div>';
        overlay.appendChild(box);
        document.body.appendChild(overlay);
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('blog-password-dialog');
        var inp = document.getElementById('blog-pwd-input');
        inp.value = rememberedPwd;
        inp.focus();
        if (rememberedPwd) inp.select();
        function close(val) {
          document.body.removeChild(overlay);
          if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('blog-password-dialog');
          resolve(val);
        }
        document.getElementById('blog-pwd-ok').onclick = function() { close(inp.value); };
        document.getElementById('blog-pwd-cancel').onclick = function() { close(null); };
        document.getElementById('blog-pwd-toggle').onclick = function() {
          var visible = inp.type === 'password';
          inp.type = visible ? 'text' : 'password';
          this.setAttribute('aria-label', visible ? '隐藏密码' : '显示密码');
          this.innerHTML = '<i class="fa-solid ' + (visible ? 'fa-eye-slash' : 'fa-eye') + '"></i>';
          inp.focus();
        };
        inp.onkeydown = function(e) { if (e.key === 'Enter') close(inp.value); if (e.key === 'Escape') close(null); };
      });
    }

    function verifyBlogPassword(pwd) {
      var headers = { 'Content-Type': 'application/json' };
      var token = document.querySelector('meta[name="csrf-token"]');
      if (token) headers['X-CSRF-Token'] = token.getAttribute('content');

      if (currentDocType === 'html' || currentDocType === 'richdoc') {
        return fetchRawHTMLContent('/api/blogs/' + blogId + '/verify-password/raw', {
          method: 'POST',
          headers: headers,
          body: JSON.stringify({ password: pwd })
        }).then(function(content) {
          OfflineBlogVault.save(blogId, pwd, content);
          rememberBlogPassword(pwd);
          return content;
        }).catch(function(err) {
          if (err && err.isAuthError) {
            forgetRememberedBlogPassword(pwd);
            throw err;
          }
          forgetRememberedBlogPassword(pwd);
          return OfflineBlogVault.load(blogId, pwd).then(function(content) {
            BookStarkEditor.toast('已从本地加密缓存打开', 'info');
            rememberBlogPassword(pwd);
            return content;
          }).catch(function(localErr) {
            throw new Error((localErr && localErr.message) || (err && err.message) || '离线打开失败');
          });
        });
      }

      return fetch('/api/blogs/' + blogId + '/verify-password', {
        method: 'POST',
        headers: headers,
        body: JSON.stringify({ password: pwd })
      }).then(function(r) {
        return r.json().then(function(d) {
          if (!r.ok || d.code !== 0) {
            var err = new Error(d.message || '密码不正确');
            err.isAuthError = true;
            throw err;
          }
          return d;
        });
      }).then(function(d) {
        if (!d.data || !d.data.blog_content && d.data.blog_content !== '') {
          var err = new Error(d.message || '密码不正确');
          err.isAuthError = true;
          throw err;
        }
        var content = d.data.blog_content || '';
        OfflineBlogVault.save(blogId, pwd, content);
        rememberBlogPassword(pwd);
        return content;
      }).catch(function(err) {
        if (err && err.isAuthError) {
          forgetRememberedBlogPassword(pwd);
          throw err;
        }
        return OfflineBlogVault.load(blogId, pwd).then(function(content) {
          BookStarkEditor.toast('已从本地加密缓存打开', 'info');
          rememberBlogPassword(pwd);
          return content;
        }).catch(function(localErr) {
          throw new Error((localErr && localErr.message) || '离线打开失败');
        });
      });
    }

    function promptBlogPassword(errorMsg) {
      return showBlogPasswordDialog(errorMsg).then(function(pwd) {
        if (!pwd) {
          window.location.href = (function(){ var fp = new URLSearchParams(window.location.search).get('from'); return (fp && fp.charAt(0) === '/') ? fp : '/notes'; })();
          return Promise.reject('cancelled');
        }
        return verifyBlogPassword(pwd).then(function(content) {
          blogPassword = pwd;
          return content;
        }).catch(function(err) {
          if (err === 'cancelled') return Promise.reject(err);
          var msg = typeof err === 'string' ? err : ((err && err.message) || '密码不正确');
          return promptBlogPassword(msg);
        });
      });
    }

    function initBlog() {
      // Setup save function (password-aware)
      var saveFn = function(content) {
        var body = { blog_content: content };
        if (blogPassword) body.password = blogPassword;
        return csrfFetch('/api/blogs/' + blogId, {
          method: 'PUT',
          offlinePolicy: 'reject',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        }).then(function(r) {
          if (!r.ok || r.headers.get('X-Offline-Queued') === 'true') throw new Error('save failed');
          if (blogPassword) OfflineBlogVault.save(blogId, blogPassword, content);
          // Update modify time in status bar
          var now = new Date();
          var mm = String(now.getMonth() + 1).padStart(2, '0');
          var dd = String(now.getDate()).padStart(2, '0');
          var hh = String(now.getHours()).padStart(2, '0');
          var mi = String(now.getMinutes()).padStart(2, '0');
          var timeStr = now.getFullYear() + '-' + mm + '-' + dd + ' ' + hh + ':' + mi;
          updateStatusbarModifyTime(timeStr);
        });
      };

      saveMgr = BookStarkEditor.setupAutoSave({
        getContent: function() {
          if (currentDocType === 'richdoc') {
            if (!richdocEditor) return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            try { return richdocEditor.getContent(); } catch (e) { BookStarkEditor.toast(e.message, 'error'); return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown; }
          }
          if (currentDocType === 'spreadsheet') {
            var content = BookStarkEditor.getSpreadsheetContent();
            if (!content) {
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            return content;
          }
          if (currentDocType === 'drawing') {
            var drawingContent = BookStarkEditor.getDrawingContent();
            if (!drawingContent) {
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            return drawingContent;
          }
          if (currentDocType === 'mindmap') {
            var mindmapContent = BookStarkEditor.getMindElixirData();
            if (!mindmapContent) {
              return saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown;
            }
            return mindmapContent;
          }
          if (currentDocType === 'presentation') {
            return BookStarkPPTist.getContent() || (saveMgr ? saveMgr._lastSaved || currentMarkdown : currentMarkdown);
          }
          return currentMarkdown;
        },
        saveFn: saveFn,
        draftKey: 'bookstark_draft_blog_' + blogId,
        onStatusChange: BookStarkEditor.updateSaveStatus,
      });

      // If blog has password, prompt for it
      if (window.BLOG_HAS_PASSWORD) {
        promptBlogPassword().then(function(content) {
          currentMarkdown = content;
          saveMgr.setLastSaved(currentMarkdown);
          renderContent();
        }).catch(function() {
          // cancelled by user, already redirected
        });
      } else {
        var initialContentPromise = ((currentDocType === 'html' || currentDocType === 'richdoc') && window.BLOG_CONTENT_URL)
          ? fetchRawHTMLContent(window.BLOG_CONTENT_URL)
          : Promise.resolve(currentMarkdown);
        initialContentPromise.then(function(serverContent) {
          currentMarkdown = serverContent || '';
          saveMgr.setLastSaved(currentMarkdown);
          return saveMgr.loadDraft(currentMarkdown).then(function(draftResult) {
            currentMarkdown = draftResult.content;
            if (draftResult.hasDraft) {
              showDraftBanner(draftResult.serverContent, draftResult.draftContent);
            }
            renderContent();
          });
        }).catch(function() {
          BookStarkEditor.toast('HTML 内容加载失败', 'error');
          saveMgr.setLastSaved('');
          currentMarkdown = '';
          renderContent();
        });
      }

      // Set initial modify time from server
      updateStatusbarModifyTime(window.BLOG_MODIFY_TIME);

      // Spreadsheet dirty check polling for blog mode
      if (currentDocType === 'spreadsheet' && saveMgr) {
        if (spreadsheetCheckInterval) {
          clearInterval(spreadsheetCheckInterval);
          spreadsheetCheckInterval = null;
        }
        spreadsheetCheckInterval = setInterval(function() {
          if (currentDocType !== 'spreadsheet') {
            clearInterval(spreadsheetCheckInterval);
            spreadsheetCheckInterval = null;
            return;
          }
          if (BookStarkEditor.isSpreadsheetDirty()) {
            BookStarkEditor.setSpreadsheetDirty(false);
            if (saveMgr && saveMgr.onContentChange) {
              saveMgr.onContentChange();
            }
            BookStarkEditor.updateCharCount();
          }
        }, 2000);
      }

      initSidebarTabs();
    }
    initBlog();
  }

  // ======== Shared: Setup ========
  setupEditorBackConfirm();
  BookStarkEditor.setupKeyboardShortcuts(function() { manualSave(); });
  BookStarkEditor.setupUnloadWarning(function() { return saveMgr && (saveMgr.getSaveStatus() === 'unsaved' || saveMgr.getSaveStatus() === 'saving'); });
  setupPagerSwipe();

  // ======== Share Dialog ========
  var _shareDialogType = '';
  var _shareDialogTargetId = 0;
  var _shareDialogIdentify = '';
  var _shareDialogEditToken = '';

  function runShareLocked(key, control, task) {
    if (window.BookStarkRequestLock) return BookStarkRequestLock.run(key, task, control);
    if (control && control.disabled) return null;
    if (control) {
      control.disabled = true;
      control.classList.add('is-submitting');
      control.setAttribute('aria-busy', 'true');
    }
    return Promise.resolve().then(task).then(function(value) {
      if (control) {
        control.disabled = false;
        control.classList.remove('is-submitting');
        control.setAttribute('aria-busy', 'false');
      }
      return value;
    }, function(err) {
      if (control) {
        control.disabled = false;
        control.classList.remove('is-submitting');
        control.setAttribute('aria-busy', 'false');
      }
      throw err;
    });
  }

  window.openEditorShare = function() {
    var shareType = IS_BOOK ? 'document' : 'blog';
    var targetId = IS_BOOK ? currentDocId : blogId;
    if (!targetId) return;
    var request = runShareLocked('editor:share:publish:' + shareType + ':' + targetId, document.querySelector('[onclick="openEditorShare()"]'), function() {
      return csrfFetch('/api/shares', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ share_type: shareType, target_id: targetId }),
      });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.code === 0 && data.data) {
        _openShareDialog(shareType, targetId, data.data.share_identify, data.data.edit_token || '');
      } else {
        BSDialog.toast(data.message || window.__('share.toast.publish_failed'), 'error');
      }
    });
  };

  function _openShareDialog(shareType, targetId, shareIdentify, editToken) {
    _shareDialogType = shareType;
    _shareDialogTargetId = targetId;
    _shareDialogIdentify = shareIdentify;
    _shareDialogEditToken = editToken || '';

    document.getElementById('shareViewUrl').value = window.location.origin + '/shares/' + shareIdentify;

    var toggle = document.getElementById('shareEditToggle');
    var urlSection = document.getElementById('shareEditUrlSection');
    var offHint = document.getElementById('shareEditOffHint');
    var badge = document.getElementById('shareEditBadge');
    var icon = document.getElementById('shareEditIcon');
    var label = document.getElementById('shareEditLabel');

    if (editToken) {
      toggle.checked = true;
      urlSection.style.display = '';
      offHint.style.display = 'none';
      badge.textContent = window.__('share.dialog.editable');
      badge.style.background = '#fef3c7';
      badge.style.color = '#b45309';
      icon.style.color = 'var(--color-warning)';
      label.style.color = 'var(--color-text)';
      document.getElementById('shareEditUrl').value = window.location.origin + '/shares/' + shareIdentify + '?token=' + editToken;
    } else {
      toggle.checked = false;
      urlSection.style.display = 'none';
      offHint.style.display = '';
      badge.textContent = '';
      badge.style.background = '';
      badge.style.color = '';
      icon.style.color = 'var(--color-text-muted)';
      label.style.color = 'var(--color-text-muted)';
    }
    document.getElementById('sharePopoverOverlay').classList.add('active');
    document.getElementById('shareSettingOverlay').classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('editor-share-dialog');
  }

  window.toggleShareEdit = function() {
    var toggle = document.getElementById('shareEditToggle');
    var action = toggle.checked ? 'enable' : 'disable';
    var request = runShareLocked('editor:share:edit-token:' + _shareDialogType + ':' + _shareDialogTargetId, toggle, function() {
      return csrfFetch('/api/shares/' + _shareDialogType + '/' + _shareDialogTargetId + '/edit-token', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: action }),
      });
    });
    if (!request) {
      toggle.checked = !toggle.checked;
      return;
    }
    request.then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.code === 0) {
        _shareDialogEditToken = data.data.edit_token;
        _openShareDialog(_shareDialogType, _shareDialogTargetId, _shareDialogIdentify, data.data.edit_token);
        BSDialog.toast(toggle.checked ? window.__('share.toast.edit_enabled') : window.__('share.toast.edit_disabled'), 'success');
      } else {
        toggle.checked = !toggle.checked;
        BSDialog.toast(data.message || window.__('share.toast.op_failed'), 'error');
      }
    })
    .catch(function() {
      toggle.checked = !toggle.checked;
      BSDialog.toast(window.__('share.toast.network_error'), 'error');
    });
  };

  window.resetEditToken = function() {
    var request = runShareLocked('editor:share:reset-token:' + _shareDialogType + ':' + _shareDialogTargetId, null, function() {
      return BSDialog.confirm2(window.__('share.toast.reset_confirm')).then(function(ok) {
        if (!ok) return null;
        return csrfFetch('/api/shares/' + _shareDialogType + '/' + _shareDialogTargetId + '/edit-token', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'reset' }),
        });
      });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; })
      .then(function(data) {
        if (!data) return;
        if (data.code === 0) {
          _shareDialogEditToken = data.data.edit_token;
          _openShareDialog(_shareDialogType, _shareDialogTargetId, _shareDialogIdentify, data.data.edit_token);
          BSDialog.toast(window.__('share.toast.reset_success'), 'success');
        } else {
          BSDialog.toast(data.message || window.__('share.toast.reset_failed'), 'error');
        }
      });
  };

  window.copyShareUrl = function(inputId) {
    var input = document.getElementById(inputId);
    navigator.clipboard.writeText(input.value).then(function() {
      BSDialog.toast(window.__('share.toast.link_copied'), 'success');
    });
  };

  window.closeShareDialog = function() {
    document.getElementById('sharePopoverOverlay').classList.remove('active');
    document.getElementById('shareSettingOverlay').classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('editor-share-dialog');
  };

  window.unpublishFromDialog = function() {
    var request = runShareLocked('editor:share:unpublish:' + _shareDialogType + ':' + _shareDialogTargetId, document.querySelector('#shareSettingOverlay .share-cancel-btn'), function() {
      return BSDialog.confirm2(window.__('share.toast.unpublish_confirm')).then(function(ok) {
        if (!ok) return null;
        return csrfFetch('/api/shares/' + _shareDialogType + '/' + _shareDialogTargetId, {
        method: 'DELETE',
        });
      });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; })
      .then(function(data) {
        if (!data) return;
        if (data.code === 0) {
          closeShareDialog();
          BSDialog.toast(window.__('share.toast.unpublished'), 'success');
        } else {
          BSDialog.toast(data.message || window.__('share.toast.op_failed'), 'error');
        }
      });
  };
})();
