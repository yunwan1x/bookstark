(function (global) {
  'use strict';

  var frame = null;
  var host = null;
  var currentContent = '';
  var currentOptions = {};
  var ready = false;
  var syncTimer = 0;
  var activeUploads = 0;

  function translatedText(key, fallback) {
    if (typeof global.__ !== 'function') return fallback;
    var value = global.__(key);
    return value && value !== key ? value : fallback;
  }

  function setUploadState(uploading) {
    if (!host) return;
    var status = host.querySelector('.pptist-upload-status');
    if (uploading && !status) {
      status = document.createElement('div');
      status.className = 'pptist-upload-status';
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      status.innerHTML =
        '<span class="pptist-upload-spinner" aria-hidden="true"></span>' +
        '<span class="pptist-upload-text"></span>';
      host.appendChild(status);
    }
    if (!status) return;
    var text = status.querySelector('.pptist-upload-text');
    if (text) {
      text.textContent = currentOptions.uploadingText ||
        translatedText('editor.presentation.uploading_image', '图片上传中...');
    }
    status.hidden = !uploading;
    host.classList.toggle('is-uploading', uploading);
  }

  function showUploadError(error) {
    var fallback = currentOptions.uploadErrorText ||
      translatedText('editor.presentation.upload_image_failed', '图片上传失败');
    var message = error && error.message && !/^HTTP \d+$/.test(error.message)
      ? error.message
      : fallback;
    if (global.BookStarkErrors && typeof global.BookStarkErrors.toast === 'function') {
      global.BookStarkErrors.toast(message, 'error', fallback);
    } else if (global.BSDialog && typeof global.BSDialog.toast === 'function') {
      global.BSDialog.toast(message, 'error');
    } else {
      console.error(message);
    }
  }

  function uploadImageFile(file) {
    if (!file || !/^image\//i.test(file.type || '')) {
      return Promise.reject(new Error(
        translatedText('note.upload.not_image', '请选择图片文件')
      ));
    }
    if (currentOptions.readonly) {
      return Promise.reject(new Error(
        translatedText('editor.presentation.upload_readonly', '只读模式不能上传图片')
      ));
    }

    activeUploads += 1;
    setUploadState(true);

    var uploadURL = currentOptions.uploadURL || '/api/uploads';
    var isAuthenticatedUpload = uploadURL === '/api/uploads';

    function postUpload() {
      var formData = new FormData();
      formData.append('file', file);
      formData.append('category', 'editor');
      if (currentOptions.uploadPassword) {
        formData.append('password', currentOptions.uploadPassword);
      }
      var fetcher = isAuthenticatedUpload && typeof global.csrfFetch === 'function'
        ? global.csrfFetch
        : global.fetch.bind(global);
      return fetcher(uploadURL, { method: 'POST', body: formData }).then(function(response) {
        return response.json().catch(function() { return null; }).then(function(payload) {
          if (!response.ok || !payload || payload.code !== 0 || !payload.data || !payload.data.url) {
            throw new Error((payload && payload.message) || 'HTTP ' + response.status);
          }
          return payload.data;
        });
      });
    }

    var findExisting = Promise.resolve(null);
    if (
      isAuthenticatedUpload &&
      typeof global.computeFileHash === 'function' &&
      typeof global.checkUploadByHash === 'function'
    ) {
      findExisting = global.computeFileHash(file).then(function(hash) {
        return global.checkUploadByHash(hash);
      }).catch(function() { return null; });
    }

    return findExisting
      .then(function(existing) {
        return existing && existing.url ? existing : postUpload();
      })
      .catch(function(error) {
        showUploadError(error);
        throw error;
      })
      .finally(function() {
        activeUploads = Math.max(0, activeUploads - 1);
        setUploadState(activeUploads > 0);
      });
  }

  function defaultPresentation(title) {
    return {
      title: title || '未命名演示文稿',
      width: 1000,
      height: 562.5,
      theme: {
        themeColors: ['#5b9bd5', '#ed7d31', '#a5a5a5', '#ffc000', '#4472c4', '#70ad47'],
        fontColor: '#333',
        fontName: '',
        backgroundColor: '#fff',
        shadow: { h: 3, v: 3, blur: 2, color: '#808080' },
        outline: { width: 2, color: '#525252', style: 'solid' }
      },
      slides: [{ id: 'slide-1', elements: [] }]
    };
  }

  function parseContent(content, title) {
    try {
      var parsed = typeof content === 'string' ? JSON.parse(content) : content;
      if (!parsed || !Array.isArray(parsed.slides) || !parsed.slides.length) {
        return defaultPresentation(title);
      }
      if (!parsed.title && title) parsed.title = title;
      return parsed;
    } catch (e) {
      return defaultPresentation(title);
    }
  }

  function sendInit() {
    if (!frame || !frame.contentWindow || !ready) return;
    var payload = parseContent(currentContent, currentOptions.title);
    frame.contentWindow.postMessage({
      source: 'bookstark',
      type: 'init',
      payload: payload,
      readonly: Boolean(currentOptions.readonly)
    }, global.location.origin);
  }

  function readFrameContent() {
    try {
      var bridge = frame && frame.contentWindow && frame.contentWindow.BookStarkPPTistBridge;
      if (!bridge || typeof bridge.getPresentation !== 'function') return currentContent;
      return JSON.stringify(bridge.getPresentation());
    } catch (e) {
      return currentContent;
    }
  }

  function syncFromFrame() {
    if (currentOptions.readonly) return;
    global.clearTimeout(syncTimer);
    syncTimer = global.setTimeout(function () {
      var nextContent = readFrameContent();
      if (!nextContent || nextContent === currentContent) return;
      currentContent = nextContent;
      if (typeof currentOptions.onChange === 'function') currentOptions.onChange(currentContent);
    }, 400);
  }

  function installEmbedUI() {
    if (!frame || !frame.contentDocument) return;
    var doc = frame.contentDocument;
    if (doc.getElementById('bookstark-pptist-styles')) return;
    var style = doc.createElement('style');
    style.id = 'bookstark-pptist-styles';
    style.textContent =
      '@media(max-width:768px){' +
        '.layout-content-left,.layout-content-right{display:none!important}' +
        '.layout-content-center{width:100%!important;min-width:0!important;flex:1!important}' +
        '.editor-header{overflow-x:auto!important;scrollbar-width:none!important}' +
        '.editor-header::-webkit-scrollbar{display:none!important}' +
        '.bookstark-mobile-left-open .layout-content-left,' +
        '.bookstark-mobile-right-open .layout-content-right{' +
          'display:flex!important;position:fixed!important;top:40px!important;bottom:0!important;' +
          'z-index:1200!important;width:min(86vw,320px)!important;height:auto!important;' +
          'background:#fff!important;box-shadow:0 12px 32px rgba(15,23,42,.22)!important' +
        '}' +
        '.bookstark-mobile-left-open .layout-content-left{left:0!important}' +
        '.bookstark-mobile-right-open .layout-content-right{right:0!important;left:auto!important}' +
        '.bookstark-pptist-mobile-backdrop{' +
          'position:fixed;inset:40px 0 0;z-index:1190;background:rgba(15,23,42,.24);' +
          'padding:0;border:0;appearance:none;backdrop-filter:blur(1px);cursor:default' +
        '}' +
        '.bookstark-pptist-mobile-backdrop[hidden]{display:none!important}' +
        '.bookstark-pptist-mobile-nav{' +
          'position:fixed;right:12px;bottom:12px;z-index:1300;display:flex;gap:6px;' +
          'padding:5px;background:rgba(255,255,255,.94);border:1px solid #dbe2ea;' +
          'border-radius:6px;box-shadow:0 6px 20px rgba(15,23,42,.16)' +
        '}' +
        '.bookstark-pptist-mobile-nav button{' +
          'height:34px;padding:0 10px;border:0;border-radius:4px;background:transparent;' +
          'color:#475569;font-size:13px;font-weight:600' +
        '}' +
        '.bookstark-pptist-mobile-nav button.active{background:#2563eb;color:#fff}' +
      '}' +
      '@media(min-width:769px){.bookstark-pptist-mobile-nav{display:none!important}}';
    doc.head.appendChild(style);

    if (currentOptions.readonly) return;
    doc.addEventListener('input', syncFromFrame, true);
    doc.addEventListener('change', syncFromFrame, true);
    doc.addEventListener('pointerup', syncFromFrame, true);
    doc.addEventListener('keyup', syncFromFrame, true);
    var root = doc.querySelector('.pptist-editor');
    if (!root) return;
    var nav = doc.createElement('div');
    nav.className = 'bookstark-pptist-mobile-nav';
    nav.innerHTML =
      '<button type="button" data-panel="left" aria-expanded="false"></button>' +
      '<button type="button" data-panel="right" aria-expanded="false"></button>';
    nav.querySelector('[data-panel="left"]').textContent =
      translatedText('editor.presentation.mobile.slides', '幻灯片');
    nav.querySelector('[data-panel="right"]').textContent =
      translatedText('editor.presentation.mobile.design', '设计');
    var backdrop = doc.createElement('button');
    backdrop.type = 'button';
    backdrop.className = 'bookstark-pptist-mobile-backdrop';
    backdrop.setAttribute(
      'aria-label',
      translatedText('editor.presentation.mobile.close_panel', '关闭面板')
    );
    backdrop.hidden = true;

    function closeMobilePanels() {
      root.classList.remove('bookstark-mobile-left-open', 'bookstark-mobile-right-open');
      nav.querySelectorAll('button').forEach(function(item) {
        item.classList.remove('active');
        item.setAttribute('aria-expanded', 'false');
      });
      backdrop.hidden = true;
    }

    nav.addEventListener('click', function(event) {
      var button = event.target.closest('button[data-panel]');
      if (!button) return;
      var panel = button.getAttribute('data-panel');
      var className = panel === 'left' ? 'bookstark-mobile-left-open' : 'bookstark-mobile-right-open';
      var otherClass = panel === 'left' ? 'bookstark-mobile-right-open' : 'bookstark-mobile-left-open';
      var opening = !root.classList.contains(className);
      closeMobilePanels();
      if (opening) {
        root.classList.add(className);
        button.classList.add('active');
        button.setAttribute('aria-expanded', 'true');
        backdrop.hidden = false;
      }
    });
    backdrop.addEventListener('click', closeMobilePanels);
    doc.addEventListener('keydown', function(event) {
      if (event.key === 'Escape') closeMobilePanels();
    });
    doc.body.appendChild(backdrop);
    doc.body.appendChild(nav);
  }

  function handleMessage(event) {
    if (!frame || event.origin !== global.location.origin || event.source !== frame.contentWindow) return;
    var message = event.data;
    if (!message || message.source !== 'bookstark-pptist') return;
    if (message.type === 'ready') {
      ready = true;
      sendInit();
      return;
    }
    if (message.type === 'initialized') {
      installEmbedUI();
      if (host) host.classList.add('is-ready');
      if (typeof currentOptions.onReady === 'function') currentOptions.onReady();
      return;
    }
    if (message.type === 'change' && !currentOptions.readonly) {
      currentContent = JSON.stringify(message.payload || defaultPresentation(currentOptions.title));
      if (typeof currentOptions.onChange === 'function') currentOptions.onChange(currentContent);
    }
  }

  function destroy() {
    global.removeEventListener('message', handleMessage);
    global.clearTimeout(syncTimer);
    if (frame && frame.parentNode) frame.parentNode.removeChild(frame);
    if (host) {
      host.classList.remove('is-ready');
      host.innerHTML = '';
    }
    frame = null;
    host = null;
    ready = false;
    syncTimer = 0;
    activeUploads = 0;
    currentOptions = {};
  }

  function mount(containerId, content, options) {
    destroy();
    host = document.getElementById(containerId);
    if (!host) throw new Error('Presentation container not found: ' + containerId);
    currentOptions = options || {};
    currentContent = typeof content === 'string'
      ? content
      : JSON.stringify(content || defaultPresentation(currentOptions.title));
    host.classList.add('pptist-host');
    host.innerHTML =
      '<div class="pptist-loading" role="status">' +
        '<span class="pptist-loading-spinner" aria-hidden="true"></span>' +
        '<span>' + (currentOptions.loadingText || '演示文稿加载中...') + '</span>' +
      '</div>';

    frame = document.createElement('iframe');
    frame.className = 'pptist-frame';
    frame.title = currentOptions.title || '演示文稿';
    frame.allow = 'clipboard-read; clipboard-write';
    frame.setAttribute('allowfullscreen', '');
    // Go's static server canonicalizes index.html to its directory URL.
    frame.src = '/static/pptist/app.html?bookstark=1';
    host.appendChild(frame);
    global.addEventListener('message', handleMessage);
    return frame;
  }

  function setContent(content, title) {
    currentContent = typeof content === 'string'
      ? content
      : JSON.stringify(content || defaultPresentation(title || currentOptions.title));
    if (title) currentOptions.title = title;
    sendInit();
  }

  global.BookStarkPPTist = {
    mount: mount,
    destroy: destroy,
    setContent: setContent,
    getContent: function () {
      var nextContent = readFrameContent();
      if (nextContent) currentContent = nextContent;
      return currentContent;
    },
    defaultContent: function (title) { return JSON.stringify(defaultPresentation(title)); }
  };
  global.BookStarkPPTistUploadImage = uploadImageFile;
})(window);
