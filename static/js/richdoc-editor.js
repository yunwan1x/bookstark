/**
 * BookStark adapter for @hufe921/canvas-editor 0.9.137.
 * The upstream package provides the canvas core; this file provides the
 * BookStark toolbar, persistence envelope, upload bridge and lifecycle.
 */
(function(global) {
  'use strict';

  var SCRIPT_URL = '/static/js/canvas-editor/canvas-editor.umd.js?v=0.9.137';
  var FONT_PREFERENCES_KEY = 'bookstark:richdoc:font-preferences:v1';
  var FONT_CATALOG = [
    { family: 'Microsoft YaHei', label: '微软雅黑' },
    { family: '华文宋体', label: '华文宋体' },
    { family: '华文黑体', label: '华文黑体' },
    { family: '华文仿宋', label: '华文仿宋' },
    { family: '华文楷体', label: '华文楷体' },
    { family: '华文琥珀', label: '华文琥珀' },
    { family: '华文隶书', label: '华文隶书' },
    { family: '华文新魏', label: '华文新魏' },
    { family: '华文行楷', label: '华文行楷' },
    { family: '华文中宋', label: '华文中宋' },
    { family: '华文彩云', label: '华文彩云' },
    { family: 'Arial', label: 'Arial' },
    { family: 'Segoe UI', label: 'Segoe UI' },
    { family: 'Ink Free', label: 'Ink Free' },
    { family: 'Fantasy', label: 'Fantasy' }
  ];
  var FONT_PREFERRED_ORDER = ['Microsoft YaHei', '微软雅黑', 'PingFang SC', '苹方-简', '华文宋体', '华文黑体', 'Arial'];
  var loadPromise = null;
  var active = null;

  function toast(message, type) {
    if (global.BSDialog && BSDialog.toast) BSDialog.toast(message, type || 'info');
    else if (global.BookStarkEditor && BookStarkEditor.toast) BookStarkEditor.toast(message, type || 'info');
  }

  function load() {
    if (global['canvas-editor'] && global['canvas-editor'].default) return Promise.resolve(global['canvas-editor']);
    if (loadPromise) return loadPromise;
    loadPromise = new Promise(function(resolve, reject) {
      var script = document.createElement('script');
      script.src = SCRIPT_URL;
      script.async = true;
      script.dataset.richdoc = 'core';
      script.onload = function() {
        var lib = global['canvas-editor'];
        if (lib && lib.default) resolve(lib);
        else reject(new Error('canvas-editor 未正确加载'));
      };
      script.onerror = function() { reject(new Error('canvas-editor 加载失败')); };
      document.head.appendChild(script);
    });
    return loadPromise;
  }

  function defaultEnvelope() {
    return {
      schema: 'bookstark-richdoc',
      schema_version: 1,
      editor_version: '0.9.137',
      data: { header: [], main: [{ value: '' }], footer: [], graffiti: [] },
      options: {},
      comments: []
    };
  }

  function parseEnvelope(raw) {
    if (!raw) return defaultEnvelope();
    try {
      var parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (parsed && parsed.schema === 'bookstark-richdoc' && parsed.schema_version === 1 && parsed.data && Array.isArray(parsed.data.main)) {
        parsed.options = parsed.options || {};
        parsed.comments = Array.isArray(parsed.comments) ? parsed.comments : [];
        return parsed;
      }
    } catch (e) {}
    throw new Error('富文档数据格式错误');
  }

  function button(command, icon, title, label) {
    return '<button type="button" class="richdoc-tool" data-command="' + command + '" title="' + title + '" aria-label="' + title + '">' +
      '<i class="fa-solid ' + icon + '"></i>' + (label ? '<span>' + label + '</span>' : '') + '</button>';
  }

  function splitButton(command, menuCommand, icon, title) {
    return '<span class="richdoc-split-tool">' + button(command, icon, title) +
      '<button type="button" class="richdoc-tool richdoc-split-arrow" data-command="' + menuCommand + '" title="选择' + title + '样式" aria-label="选择' + title + '样式"><i class="fa-solid fa-chevron-down"></i></button></span>';
  }

  function fontPickerHTML() {
    return '<button type="button" class="richdoc-select richdoc-font-picker" data-command="fontMenu" title="字体" aria-label="选择字体" aria-haspopup="menu" aria-expanded="false">' +
      '<span class="richdoc-font-label">微软雅黑</span><i class="fa-solid fa-chevron-down" aria-hidden="true"></i></button>';
  }

  function escapeHTML(value) {
    return String(value || '').replace(/[&<>"]/g, function(char) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[char];
    });
  }

  function cloneValue(value) {
    if (value === undefined) return {};
    return JSON.parse(JSON.stringify(value));
  }

  function uniqueFontFamilies(fonts) {
    var unique = {};
    return (fonts || []).map(function(value) { return String(value || '').trim(); }).filter(function(family) {
      var key = family.toLocaleLowerCase();
      if (!family || unique[key]) return false;
      unique[key] = true;
      return true;
    });
  }

  function sortFontFamilies(fonts) {
    function rank(family) {
      var lower = family.toLocaleLowerCase();
      var index = FONT_PREFERRED_ORDER.findIndex(function(item) { return item.toLocaleLowerCase() === lower; });
      return index < 0 ? FONT_PREFERRED_ORDER.length : index;
    }
    return uniqueFontFamilies(fonts).sort(function(left, right) {
      return rank(left) - rank(right) || left.localeCompare(right, 'zh-CN', { sensitivity: 'base' });
    });
  }

  function fontDisplayName(family) {
    var item = FONT_CATALOG.find(function(candidate) { return candidate.family === family; });
    return item ? item.label : family === 'system-ui' ? '系统默认' : family;
  }

  function getPathValue(source, path) {
    return String(path).split('.').reduce(function(value, key) { return value == null ? undefined : value[key]; }, source);
  }

  function setPathValue(target, path, value) {
    var keys = String(path).split('.');
    var cursor = target;
    keys.forEach(function(key, index) {
      if (index === keys.length - 1) { cursor[key] = value; return; }
      var nextKey = keys[index + 1];
      if (!cursor[key] || typeof cursor[key] !== 'object') cursor[key] = /^\d+$/.test(nextKey) ? [] : {};
      cursor = cursor[key];
    });
    return target;
  }

  function mergeSettings(base, updates, path) {
    if (!updates || typeof updates !== 'object' || Array.isArray(updates)) return cloneValue(updates);
    var target = base && typeof base === 'object' && !Array.isArray(base) ? cloneValue(base) : {};
    Object.keys(updates).forEach(function(key) {
      if (key === '__proto__' || key === 'prototype' || key === 'constructor') throw new Error((path || '配置') + ' 包含不允许的字段：' + key);
      var value = updates[key];
      target[key] = value && typeof value === 'object' && !Array.isArray(value) ? mergeSettings(target[key], value, (path || '配置') + '.' + key) : cloneValue(value);
    });
    return target;
  }

  function assertSafeSettings(options) {
    var forbidden = { '__proto__': true, prototype: true, constructor: true };
    function visit(value, path) {
      if (!value || typeof value !== 'object') return;
      Object.keys(value).forEach(function(key) {
        if (forbidden[key]) throw new Error((path || '配置') + ' 包含不允许的字段：' + key);
        visit(value[key], (path || '配置') + '.' + key);
      });
    }
    function finite(path, min, max) {
      var value = getPathValue(options, path);
      if (!Number.isFinite(value) || value < min || value > max) throw new Error(path + ' 必须在 ' + min + '–' + max + ' 之间');
    }
    visit(options, '配置');
    finite('width', 200, 5000); finite('height', 200, 5000); finite('scale', 0.5, 3);
    finite('defaultSize', 1, 500); finite('minSize', 1, 500); finite('maxSize', 1, 500);
    finite('printPixelRatio', 1, 6); finite('column.count', 1, 5); finite('column.gap', 0, 300); finite('watermark.opacity', 0, 1);
    finite('pageBorder.lineWidth', 0.5, 20); finite('defaultRowMargin', 0.5, 5); finite('defaultBasicRowMarginHeight', 0, 100); finite('defaultTabWidth', 1, 500);
    ['defaultFirstSize','defaultSecondSize','defaultThirdSize','defaultFourthSize'].forEach(function(key) { finite('title.' + key, 1, 500); });
    finite('header.top', 0, 1000); finite('footer.bottom', 0, 1000); finite('pageNumber.bottom', 0, 1000); finite('pageNumber.size', 1, 500);
    finite('pageNumber.startPageNo', 0, 1000000); finite('pageNumber.fromPageNo', 0, 1000000); finite('watermark.size', 1, 1000);
    if (options.minSize > options.defaultSize || options.defaultSize > options.maxSize) throw new Error('字号必须满足：最小字号 ≤ 默认字号 ≤ 最大字号');
    if (!Array.isArray(options.margins) || options.margins.length !== 4 || options.margins.some(function(value) { return !Number.isFinite(value) || value < 0 || value > 1000; })) throw new Error('页边距必须是 4 个 0–1000 的数字');
    if (options.margins[1] + options.margins[3] >= options.width || options.margins[0] + options.margins[2] >= options.height) throw new Error('页边距之和必须小于纸张宽高');
    if (options.background && /^(?:data:image\/|blob:)/i.test(String(options.background.image || '').trim())) throw new Error('背景图片必须使用已上传的 URL，不能嵌入 Data URL 或 Blob URL');
    if (options.watermark && options.watermark.type === 'image' && /^(?:data:image\/|blob:)/i.test(String(options.watermark.data || '').trim())) throw new Error('图片水印必须使用已上传的 URL，不能嵌入 Data URL 或 Blob URL');
    return options;
  }

  function toolbarHTML() {
    return '<div class="richdoc-toolbar" editor-component="menu">' +
      '<div class="richdoc-tool-group">' + button('undo','fa-rotate-left','撤销') + button('redo','fa-rotate-right','重做') + '</div>' +
      '<div class="richdoc-tool-group richdoc-select-group">' +
        fontPickerHTML() +
        '<select class="richdoc-select richdoc-size" data-command="size" aria-label="字号"><option value="56">初号</option><option value="48">小初</option><option value="34">一号</option><option value="32">小一</option><option value="29">二号</option><option value="24">小二</option><option value="21">三号</option><option value="20">小三</option><option value="18">四号</option><option value="16" selected>小四</option><option value="14">五号</option><option value="12">小五</option><option value="10">六号</option><option value="8">小六</option><option value="7">七号</option><option value="6">八号</option></select>' +
        button('bold','fa-bold','加粗') + button('italic','fa-italic','斜体') + splitButton('underline','underlineStyle','fa-underline','下划线') + button('colorMenu','fa-palette','文字颜色和高亮') + button('textMore','fa-ellipsis','更多文字工具') +
      '</div>' +
      '<div class="richdoc-tool-group">' +
        '<select class="richdoc-select richdoc-title-select" data-command="title" aria-label="标题"><option value="">正文</option><option value="first">标题 1</option><option value="second">标题 2</option><option value="third">标题 3</option><option value="fourth">标题 4</option><option value="fifth">标题 5</option><option value="sixth">标题 6</option></select>' +
        button('alignmentMenu','fa-align-left','对齐方式') + button('list','fa-list-ul','列表样式') + button('rowMargin','fa-arrows-up-down','行间距') + '</div>' +
      '<div class="richdoc-tool-group richdoc-insert-group">' + button('table','fa-table','插入表格') + button('image','fa-image','上传图片') + button('link','fa-link','插入链接') + button('insertMenu','fa-plus','更多插入') + '</div>' +
      '<div class="richdoc-tool-group richdoc-tool-group-last">' + button('comment','fa-comment-dots','批注') + button('search','fa-magnifying-glass','查找替换') + button('moreMenu','fa-ellipsis','更多工具') + '</div>' +
      '<input type="file" class="richdoc-image-input" accept="image/jpeg,image/png,image/gif,image/webp,image/svg+xml" hidden>' +
    '</div>';
  }

  function footerHTML(readonly) {
    return '<footer class="richdoc-footer" editor-component="footer">' +
      '<div class="richdoc-footer-section richdoc-footer-left">' +
        button('catalog','fa-list','目录') + button('pageMode','fa-scroll','分页/连续') +
        '<span class="richdoc-visible-pages">可见页码：1</span><span class="richdoc-page-info">页面：1 / 1</span><span class="richdoc-word-count">字数：0</span><span class="richdoc-position">行：0　列：0</span><span class="richdoc-upload-state"></span>' +
      '</div>' +
      '<div class="richdoc-footer-mode">' + (readonly ? '<span>只读模式</span>' : '<select class="richdoc-mode" aria-label="编辑模式"><option value="edit">编辑模式</option><option value="clean">清洁模式</option><option value="readonly">只读模式</option><option value="form">表单模式</option><option value="print">打印模式</option><option value="design">设计模式</option><option value="graffiti">涂鸦模式</option><option value="trace">留痕模式</option></select><label class="richdoc-trace-toggle"><input type="checkbox">记录留痕</label>') + '</div>' +
      '<div class="richdoc-footer-section richdoc-footer-right">' +
        button('zoomOut','fa-minus','缩小') + '<button type="button" class="richdoc-scale" data-command="zoomReset" title="重置缩放">100%</button>' + button('zoomIn','fa-plus','放大') +
        button('pageSetup','fa-file','纸张大小') + button('paperDirection','fa-arrows-left-right-to-line','纸张方向') + button('margins','fa-border-all','页边距') + button('columns','fa-table-columns','分栏') + button('fullscreen','fa-expand','全屏') + button('settings','fa-gear','编辑器设置') +
      '</div>' +
    '</footer>';
  }

  function shellHTML(readonly, compactLayout) {
    return '<div class="richdoc-shell' + (readonly ? ' is-readonly' : '') + '">' +
      toolbarHTML() +
      '<div class="richdoc-workspace">' +
        '<aside class="richdoc-catalog"' + ((readonly || compactLayout) ? ' hidden' : '') + '><div class="richdoc-panel-head"><strong>目录</strong><button type="button" data-panel-close="catalog">×</button></div><div class="richdoc-catalog-list"></div></aside>' +
        '<div class="richdoc-canvas"></div>' +
        '<aside class="richdoc-comments" hidden><div class="richdoc-panel-head"><strong>批注</strong><button type="button" data-panel-close="comments">×</button></div><div class="richdoc-comment-list"></div></aside>' +
      '</div>' +
      footerHTML(readonly) +
      '<div class="richdoc-popover" editor-component="menu" role="menu" hidden></div>' +
      '<div class="richdoc-modal-layer" editor-component="menu" hidden>' +
        '<button type="button" class="richdoc-overlay-backdrop" data-richdoc-close="modal" aria-label="关闭弹窗"></button>' +
        '<section class="richdoc-modal" role="dialog" aria-modal="true" aria-labelledby="richdoc-modal-title">' +
          '<header class="richdoc-modal-head"><strong id="richdoc-modal-title"></strong><button type="button" data-richdoc-close="modal" aria-label="关闭">×</button></header>' +
          '<form class="richdoc-modal-form"><div class="richdoc-modal-fields"></div><footer class="richdoc-modal-actions"><button type="button" class="richdoc-button richdoc-button-secondary" data-richdoc-close="modal">取消</button><button type="submit" class="richdoc-button richdoc-button-primary">确定</button></footer></form>' +
        '</section>' +
      '</div>' +
      '<div class="richdoc-settings-layer" editor-component="menu" hidden>' +
        '<button type="button" class="richdoc-overlay-backdrop" data-richdoc-close="settings" aria-label="关闭设置"></button>' +
        '<aside class="richdoc-settings-panel" role="dialog" aria-modal="true" aria-labelledby="richdoc-settings-title"></aside>' +
      '</div>' +
    '</div>';
  }

  function hashAndUpload(file, options) {
    var endpoint = options.uploadURL || '/api/uploads';
    function post() {
      var body = new FormData();
      body.append('file', file);
      body.append('category', 'editor');
      if (options.uploadPassword) body.append('password', options.uploadPassword);
      var fetcher = global.csrfFetch || global.fetch.bind(global);
      return fetcher(endpoint, { method: 'POST', body: body }).then(function(r) { return r.json(); }).then(function(payload) {
        if (payload.code === 0 && payload.data && payload.data.url) return payload.data;
        throw new Error(payload.message || '图片上传失败');
      });
    }
    if (typeof global.computeFileHash !== 'function' || typeof global.checkUploadByHash !== 'function' || options.uploadURL) return post();
    return global.computeFileHash(file).then(global.checkUploadByHash).then(function(existing) {
      return existing && existing.url ? existing : post();
    }).catch(post);
  }

  function dataURLToFile(value, name) {
    var comma = value.indexOf(',');
    var meta = comma >= 0 ? value.slice(0, comma) : value;
    var payload = comma >= 0 ? value.slice(comma + 1) : '';
    var mime = (meta.match(/data:([^;]+)/) || [])[1] || 'image/png';
    var isBase64 = /;base64/i.test(meta);
    var bytes = isBase64 ? atob(payload) : decodeURIComponent(payload);
    if (!isBase64) return new File([bytes], name || 'pasted-image.png', { type: mime });
    var array = new Uint8Array(bytes.length);
    for (var i = 0; i < bytes.length; i++) array[i] = bytes.charCodeAt(i);
    return new File([array], name || 'pasted-image.png', { type: mime });
  }

  function hasEmbeddedImage(value) {
    if (Array.isArray(value)) return value.some(hasEmbeddedImage);
    if (value && typeof value === 'object') {
      var imageElement = value.type === 'image';
      return Object.keys(value).some(function(key) {
        var child = value[key];
        if (typeof child === 'string' && ((imageElement && (key === 'value' || key === 'data')) || key === 'image' || key === 'src' || key === 'url')) {
          var lower = child.trim().toLowerCase();
          if (lower.indexOf('data:image/') === 0 || lower.indexOf('blob:') === 0) return true;
        }
        return hasEmbeddedImage(child);
      });
    }
    return false;
  }

  function cloneMacroArgument(value) {
    if (value === undefined) return null;
    try { return JSON.parse(JSON.stringify(value)); } catch (e) { return null; }
  }

  function RichDocMacro(editor) {
    this.editor = editor;
    this.macros = [];
    this.recording = null;
    this.playing = false;
    this.bindCommands();
  }

  RichDocMacro.prototype.bindCommands = function() {
    var self = this;
    var command = this.editor.instance && this.editor.instance.command;
    if (!command) return;
    Object.keys(command).forEach(function(name) {
      if (name.indexOf('execute') !== 0 || typeof command[name] !== 'function') return;
      var original = command[name];
      command[name] = function() {
        var args = Array.prototype.slice.call(arguments);
        if (self.recording && !self.playing) self.recording.push({ command: name, args: cloneMacroArgument(args) || [] });
        return original.apply(command, args);
      };
    });
  };

  RichDocMacro.prototype.isRecording = function() { return this.recording !== null; };
  RichDocMacro.prototype.startRecording = function() {
    if (this.playing || this.recording) return false;
    this.recording = [];
    toast('已开始录制宏', 'success');
    return true;
  };
  RichDocMacro.prototype.stopRecording = function(name) {
    if (!this.recording) return null;
    var macro = { id: 'macro-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8), name: name, type: '命令', steps: this.recording };
    this.recording = null;
    this.macros.push(macro);
    return macro;
  };
  RichDocMacro.prototype.cancelRecording = function() { this.recording = null; };
  RichDocMacro.prototype.getMacros = function() { return this.macros.slice(); };
  RichDocMacro.prototype.removeMacro = function(id) {
    var before = this.macros.length;
    this.macros = this.macros.filter(function(macro) { return macro.id !== id; });
    return this.macros.length !== before;
  };
  RichDocMacro.prototype.exportMacros = function() { return JSON.stringify(this.macros); };
  RichDocMacro.prototype.importMacros = function(raw) {
    try {
      var value = typeof raw === 'string' ? JSON.parse(raw) : raw;
      this.macros = Array.isArray(value) ? value.filter(function(macro) {
        return macro && macro.id && Array.isArray(macro.steps) && macro.steps.every(function(step) {
          return step && /^execute[A-Z]/.test(step.command) && Array.isArray(step.args);
        });
      }) : [];
    } catch (e) { this.macros = []; }
  };
  RichDocMacro.prototype.play = function(id) {
    var self = this;
    var macro = this.macros.find(function(item) { return item.id === id; });
    if (!macro || this.recording || this.playing) return Promise.resolve(false);
    this.playing = true;
    return macro.steps.reduce(function(task, step) {
      return task.then(function() {
        var fn = self.editor.instance.command[step.command];
        if (typeof fn !== 'function') return;
        return Promise.resolve(fn.apply(self.editor.instance.command, step.args || []));
      });
    }, Promise.resolve()).then(function() {
      toast('宏“' + macro.name + '”回放完成', 'success');
      return true;
    }).finally(function() { self.playing = false; });
  };

  function RichDoc(container, raw, options, lib) {
    this.container = container;
    this.options = options || {};
    this.lib = lib;
    this.envelope = parseEnvelope(raw);
    this.comments = this.envelope.comments.slice();
    this.pendingUploads = 0;
    this.pageCount = 1;
    this.uploadPromise = Promise.resolve();
    this.currentMode = this.options.readonly ? 'readonly' : 'edit';
    this.searchOptions = { reg: true, case: true, selection: false };
    this.destroyed = false;
    container.innerHTML = shellHTML(!!this.options.readonly, container.clientWidth < 1100);
    this.root = container.querySelector('.richdoc-shell');
    var editorOptions = Object.assign({}, this.envelope.options || {});
    editorOptions.locale = (global.__currentLang || 'zh-CN').toLowerCase().indexOf('zh') === 0 ? 'zhCN' : 'en';
    editorOptions.mode = this.options.readonly ? lib.EditorMode.READONLY : lib.EditorMode.EDIT;
    editorOptions.scrollContainerSelector = '.richdoc-canvas';
    this.instance = new lib.default(container.querySelector('.richdoc-canvas'), this.envelope.data, editorOptions);
    this.initializeFonts();
    this.macro = new RichDocMacro(this);
    this.restoreMacros();
    this.registerContextMenus();
    this.pageCount = container.querySelectorAll('.ce-page-container canvas').length || 1;
    this.bind();
    this.refreshCatalog();
    this.refreshComments();
    this.refreshStatus();
  }

  RichDoc.prototype.command = function(name) {
    var fn = this.instance && this.instance.command && this.instance.command[name];
    if (typeof fn !== 'function') return;
    return fn.apply(this.instance.command, Array.prototype.slice.call(arguments, 1));
  };

  RichDoc.prototype.focusCommand = function(name) {
    return this.command.apply(this, [name].concat(Array.prototype.slice.call(arguments, 1)));
  };

  RichDoc.prototype.readFontPreferences = function() {
    try {
      var value = JSON.parse(localStorage.getItem(FONT_PREFERENCES_KEY) || '{}');
      return { localFontsEnabled: value.localFontsEnabled === true, recentFonts: Array.isArray(value.recentFonts) ? uniqueFontFamilies(value.recentFonts).slice(0, 5) : [] };
    } catch (e) { return { localFontsEnabled: false, recentFonts: [] }; }
  };

  RichDoc.prototype.writeFontPreferences = function(updates) {
    this.fontPreferences = Object.assign({}, this.fontPreferences || this.readFontPreferences(), updates || {});
    try { localStorage.setItem(FONT_PREFERENCES_KEY, JSON.stringify(this.fontPreferences)); } catch (e) {}
  };

  RichDoc.prototype.detectCompatibleFonts = function() {
    var canvas = document.createElement('canvas');
    var context = canvas.getContext('2d');
    if (!context) return ['system-ui'];
    var sample = 'mmmmmmmmmmlliWw汉字國語0123456789';
    var bases = ['monospace', 'serif', 'sans-serif'];
    var widths = {};
    bases.forEach(function(base) { context.font = '72px ' + base; widths[base] = context.measureText(sample).width; });
    var fonts = FONT_CATALOG.map(function(item) { return item.family; }).filter(function(family) {
      return bases.some(function(base) {
        context.font = '72px "' + family.replace(/"/g, '\\"') + '", ' + base;
        return Math.abs(context.measureText(sample).width - widths[base]) > 0.01;
      });
    });
    return sortFontFamilies(fonts.length ? fonts : ['system-ui']);
  };

  RichDoc.prototype.initializeFonts = function() {
    this.fontPreferences = this.readFontPreferences();
    this.availableFonts = this.detectCompatibleFonts();
    this.fontSource = 'compatibility';
    this.fontLoadState = typeof global.queryLocalFonts === 'function' ? 'compatibility' : 'unsupported';
    this.localFontCount = 0;
    var configured = (this.command('getOptions') || {}).defaultFont;
    this.syncFontPicker(configured || this.availableFonts[0] || 'system-ui');
    this.restoreLocalFonts();
  };

  RichDoc.prototype.syncFontPicker = function(family) {
    if (!family) return;
    this.currentFont = family;
    var picker = this.root.querySelector('.richdoc-font-picker');
    if (!picker) return;
    picker.querySelector('.richdoc-font-label').textContent = fontDisplayName(family);
    picker.querySelector('.richdoc-font-label').style.fontFamily = family;
    picker.title = '字体：' + family;
  };

  RichDoc.prototype.rememberRecentFont = function(family) {
    this.writeFontPreferences({ recentFonts: uniqueFontFamilies([family].concat(this.fontPreferences.recentFonts || [])).slice(0, 5) });
  };

  RichDoc.prototype.refreshFontPopover = function() {
    var popover = this.root.querySelector('.richdoc-popover');
    if (!popover || popover.hidden || !this.popoverAnchor || this.popoverAnchor.dataset.command !== 'fontMenu') return;
    this.renderFontPopover(popover, this.closePopover.bind(this));
  };

  RichDoc.prototype.loadLocalFonts = function(automatic) {
    var self = this;
    if (typeof global.queryLocalFonts !== 'function') {
      this.fontLoadState = 'unsupported';
      this.refreshFontPopover();
      if (!automatic) toast('当前浏览器不支持读取本机字体，请使用桌面版 Chromium', 'warning');
      return Promise.resolve(false);
    }
    this.fontLoadState = 'loading';
    this.refreshFontPopover();
    return global.queryLocalFonts().then(function(fontData) {
      var families = sortFontFamilies(Array.prototype.map.call(fontData || [], function(font) { return font.family; }));
      if (!families.length) throw new Error('浏览器没有返回可用字体');
      self.availableFonts = families;
      self.localFontCount = families.length;
      self.fontSource = 'local';
      self.fontLoadState = 'local';
      self.writeFontPreferences({ localFontsEnabled: true });
      self.refreshFontPopover();
      if (!automatic) toast('已读取 ' + families.length + ' 个本机字体', 'success');
      return true;
    }).catch(function(error) {
      var denied = error && (error.name === 'NotAllowedError' || error.name === 'SecurityError');
      self.fontLoadState = 'error';
      if (denied) self.writeFontPreferences({ localFontsEnabled: false });
      self.refreshFontPopover();
      if (!automatic) toast(denied ? '未授权读取本机字体，已保留兼容字体' : (error.message || '读取本机字体失败'), 'warning');
      return false;
    });
  };

  RichDoc.prototype.restoreLocalFonts = function() {
    var self = this;
    if (!this.fontPreferences.localFontsEnabled || typeof global.queryLocalFonts !== 'function' || !navigator.permissions || !navigator.permissions.query) return;
    navigator.permissions.query({ name: 'local-fonts' }).then(function(permission) {
      if (permission.state === 'granted') self.loadLocalFonts(true);
    }).catch(function() {});
  };

  RichDoc.prototype.getSettingsFontFamilies = function(currentFont) {
    var fonts = (this.availableFonts || []).slice();
    if (currentFont && fonts.indexOf(currentFont) < 0) fonts.unshift(currentFont);
    return uniqueFontFamilies(fonts.length ? fonts : ['system-ui']);
  };

  RichDoc.prototype.renderFontPopover = function(popover, close) {
    var self = this;
    var current = this.currentFont || (this.command('getOptions') || {}).defaultFont || 'system-ui';
    var fonts = sortFontFamilies(this.availableFonts || []);
    var recent = (this.fontPreferences.recentFonts || []).filter(function(font) { return fonts.indexOf(font) >= 0; });
    var recentSet = {};
    recent.forEach(function(font) { recentSet[font] = true; });
    popover.innerHTML = '';
    var tools = document.createElement('div');
    tools.className = 'richdoc-font-tools';
    tools.innerHTML = '<label class="richdoc-font-search"><i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i><input type="search" autocomplete="off" spellcheck="false" placeholder="搜索字体" aria-label="搜索字体"></label>' +
      '<button type="button" class="richdoc-font-load"><i class="fa-solid fa-rotate" aria-hidden="true"></i><span><strong></strong><small></small></span></button>';
    var loadButton = tools.querySelector('.richdoc-font-load');
    var status = {
      compatibility: ['读取本机字体', '点击授权，仅读取字体名称'],
      local: ['本机字体 · ' + this.localFontCount, '已授权，点击可重新读取'],
      loading: ['正在读取本机字体', '请完成浏览器权限操作'],
      error: ['未获得字体权限', '仍保留兼容字体，点击重试'],
      unsupported: ['当前浏览器不支持', '请使用桌面版 Chromium']
    }[this.fontLoadState] || ['读取本机字体', '点击授权，仅读取字体名称'];
    loadButton.querySelector('strong').textContent = status[0];
    loadButton.querySelector('small').textContent = status[1];
    loadButton.disabled = this.fontLoadState === 'loading' || this.fontLoadState === 'unsupported';
    loadButton.addEventListener('click', function() { self.loadLocalFonts(false); });
    popover.appendChild(tools);
    var list = document.createElement('div');
    list.className = 'richdoc-font-list';
    function appendGroup(label, families, section) {
      if (!families.length) return;
      var heading = document.createElement('div');
      heading.className = 'richdoc-font-group';
      heading.textContent = label;
      heading.dataset.fontGroup = section;
      list.appendChild(heading);
      families.forEach(function(family) {
        var item = document.createElement('button');
        item.type = 'button';
        item.className = 'richdoc-font-option';
        item.dataset.family = family;
        item.dataset.fontSection = section;
        item.style.fontFamily = family;
        item.title = family + ' · ' + (self.fontSource === 'local' ? '本机字体' : '兼容检测可用');
        item.textContent = fontDisplayName(family);
        if (family === current) item.classList.add('is-selected');
        item.addEventListener('click', function() {
          self.command('executeFont', family);
          self.rememberRecentFont(family);
          self.syncFontPicker(family);
          close();
        });
        list.appendChild(item);
      });
    }
    if (current && fonts.indexOf(current) < 0) appendGroup('当前文档字体 · 本机未检测到', [current], 'document');
    appendGroup('最近使用', recent, 'recent');
    appendGroup(this.fontSource === 'local' ? '本机字体 · ' + this.localFontCount : '兼容字体 · ' + fonts.length, fonts.filter(function(font) { return !recentSet[font]; }), 'available');
    var empty = document.createElement('div');
    empty.className = 'richdoc-font-empty';
    empty.textContent = '没有匹配的字体';
    empty.hidden = true;
    list.appendChild(empty);
    popover.appendChild(list);
    var search = tools.querySelector('input');
    search.addEventListener('input', function() {
      var term = search.value.trim().toLocaleLowerCase();
      var visible = 0;
      list.querySelectorAll('.richdoc-font-option').forEach(function(item) {
        var match = !term || (item.dataset.family + ' ' + item.textContent).toLocaleLowerCase().indexOf(term) >= 0;
        item.hidden = !match;
        if (match) visible++;
      });
      list.querySelectorAll('.richdoc-font-group').forEach(function(group) {
        group.hidden = !Array.prototype.some.call(list.querySelectorAll('[data-font-section="' + group.dataset.fontGroup + '"]'), function(item) { return !item.hidden; });
      });
      empty.hidden = visible > 0;
    });
    setTimeout(function() { search.focus(); }, 0);
  };

  RichDoc.prototype.openFontPopover = function() {
    var self = this;
    return this.openPopover(this.commandButton('fontMenu'), 'richdoc-font-popover', function(popover, close) { self.renderFontPopover(popover, close); });
  };

  RichDoc.prototype.restoreMacros = function() {
    try { this.macro.importMacros(localStorage.getItem('bookstark:richdoc:macros:v1') || '[]'); } catch (e) {}
  };

  RichDoc.prototype.persistMacros = function() {
    try { localStorage.setItem('bookstark:richdoc:macros:v1', this.macro.exportMacros()); } catch (e) {}
  };

  RichDoc.prototype.openImageCaptionModal = function(command, element, isEditing) {
    var caption = element && element.imgCaption ? cloneValue(element.imgCaption) : {};
    this.openModal({
      title: isEditing ? '修改题注' : '新增题注',
      confirmText: isEditing ? '保存修改' : '新增题注',
      fields: [{ name: 'value', label: '题注内容', value: caption.value || '', required: true, wide: true, placeholder: '请输入题注内容，使用 {imageNo} 表示图片序号' }],
      onConfirm: function(values) {
        command.executeSetImageCaption(Object.assign({}, caption, { value: String(values.value || '').trim() }));
      }
    });
  };

  RichDoc.prototype.openSignatureModal = function() {
    var self = this;
    var strokes = [];
    var activeStroke = null;
    this.openModal({
      title: '签名',
      confirmText: '插入签名',
      fields: [],
      onConfirm: function() {
        if (!strokes.length) return toast('请先绘制签名', 'warning');
        canvas.toBlob(function(blob) {
          if (!blob) return toast('签名图片生成失败', 'error');
          self.insertImageFile(new File([blob], 'signature-' + Date.now() + '.png', { type: 'image/png' }));
        }, 'image/png');
      }
    });
    var fields = this.root.querySelector('.richdoc-modal-fields');
    fields.classList.add('richdoc-signature-fields');
    var operations = document.createElement('div');
    operations.className = 'richdoc-signature-operations';
    operations.innerHTML = '<span>在下方区域手写签名</span><span><button type="button" data-signature-action="undo"><i class="fa-solid fa-rotate-left"></i> 撤销</button><button type="button" data-signature-action="clear"><i class="fa-solid fa-trash-can"></i> 清空</button></span>';
    var canvas = document.createElement('canvas');
    canvas.className = 'richdoc-signature-canvas';
    canvas.width = 1120;
    canvas.height = 400;
    fields.appendChild(operations);
    fields.appendChild(canvas);
    var context = canvas.getContext('2d');
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.strokeStyle = '#172033';
    context.lineWidth = 4;
    function point(event) {
      var rect = canvas.getBoundingClientRect();
      return { x: (event.clientX - rect.left) * canvas.width / rect.width, y: (event.clientY - rect.top) * canvas.height / rect.height };
    }
    function redraw() {
      context.clearRect(0, 0, canvas.width, canvas.height);
      strokes.forEach(function(stroke) {
        if (!stroke.length) return;
        context.beginPath();
        context.moveTo(stroke[0].x, stroke[0].y);
        stroke.slice(1).forEach(function(item) { context.lineTo(item.x, item.y); });
        if (stroke.length === 1) context.lineTo(stroke[0].x + 0.1, stroke[0].y + 0.1);
        context.stroke();
      });
    }
    canvas.addEventListener('pointerdown', function(event) {
      event.preventDefault();
      canvas.setPointerCapture(event.pointerId);
      activeStroke = [point(event)];
      strokes.push(activeStroke);
      redraw();
    });
    canvas.addEventListener('pointermove', function(event) {
      if (!activeStroke) return;
      activeStroke.push(point(event));
      redraw();
    });
    function finishStroke() { activeStroke = null; }
    canvas.addEventListener('pointerup', finishStroke);
    canvas.addEventListener('pointercancel', finishStroke);
    operations.addEventListener('click', function(event) {
      var button = event.target.closest('[data-signature-action]');
      if (!button) return;
      if (button.dataset.signatureAction === 'undo') strokes.pop();
      else strokes = [];
      activeStroke = null;
      redraw();
    });
  };

  RichDoc.prototype.openStopMacroModal = function() {
    var self = this;
    this.openModal({
      title: '保存宏',
      confirmText: '保存宏',
      fields: [{ name: 'name', label: '宏名称', required: true, wide: true, placeholder: '请输入宏名称' }],
      onConfirm: function(values) {
        var macro = self.macro.stopRecording(String(values.name || '').trim());
        if (!macro) return;
        self.persistMacros();
        toast('宏“' + macro.name + '”已保存', 'success');
      },
      onCancel: function() { self.macro.cancelRecording(); }
    });
  };

  RichDoc.prototype.openPlayMacroModal = function() {
    var self = this;
    var macros = this.macro.getMacros();
    this.openModal({
      title: '回放宏',
      confirmText: '开始回放',
      fields: [{ name: 'macroId', label: '选择宏', type: 'select', required: true, wide: true, options: macros.map(function(macro) { return { label: macro.name + ' (' + macro.type + ')', value: macro.id }; }) }],
      onConfirm: function(values) {
        self.macro.play(values.macroId).catch(function(error) { toast(error.message || '宏回放失败', 'error'); });
      }
    });
  };

  RichDoc.prototype.openManageMacroModal = function() {
    var self = this;
    var macros = this.macro.getMacros();
    this.openModal({
      title: '管理宏',
      confirmText: '删除宏',
      fields: [{ name: 'macroId', label: '选择要删除的宏', type: 'select', required: true, wide: true, options: macros.map(function(macro) { return { label: macro.name + ' (' + macro.type + ')', value: macro.id }; }) }],
      onConfirm: function(values) {
        if (!self.macro.removeMacro(values.macroId)) return;
        self.persistMacros();
        toast('宏已删除', 'success');
      }
    });
  };

  RichDoc.prototype.registerContextMenus = function() {
    var self = this;
    var register = this.instance && this.instance.register;
    var zone = this.lib.EditorZone;
    var imageType = this.lib.ElementType.IMAGE;
    var graffitiMode = this.lib.EditorMode.GRAFFITI;
    if (!register || typeof register.contextMenuList !== 'function') return;
    register.contextMenuList([
      {
        name: '批注', icon: 'comment',
        when: function(context) { return !context.isReadonly && context.editorHasSelection && context.zone === zone.MAIN; },
        callback: function() { self.addComment(); }
      },
      {
        name: '新增题注', icon: 'caption',
        when: function(context) { return !context.isReadonly && context.startElement && context.startElement.type === imageType && !context.startElement.imgCaption; },
        callback: function(command, context) { self.openImageCaptionModal(command, context.startElement, false); }
      },
      {
        name: '修改题注', icon: 'caption',
        when: function(context) { return !context.isReadonly && context.startElement && context.startElement.type === imageType && !!context.startElement.imgCaption; },
        callback: function(command, context) { self.openImageCaptionModal(command, context.startElement, true); }
      },
      {
        name: '签名', icon: 'signature',
        when: function(context) { return !context.isReadonly && context.editorTextFocus; },
        callback: function() { self.openSignatureModal(); }
      },
      {
        name: '格式整理', icon: 'word-tool',
        when: function(context) { return !context.isReadonly; },
        callback: function(command) { command.executeWordTool(); }
      },
      {
        name: '清空涂鸦信息',
        when: function(context) { return context.options.mode === graffitiMode; },
        callback: function(command) { command.executeClearGraffiti(); }
      },
      {
        name: '宏',
        when: function(context) { return !context.isReadonly; },
        childMenus: [
          { name: '录制宏', icon: 'record', when: function() { return !self.macro.isRecording(); }, callback: function() { self.macro.startRecording(); } },
          { name: '停止录制宏', icon: 'stop', when: function() { return self.macro.isRecording(); }, callback: function() { self.openStopMacroModal(); } },
          { name: '回放宏', when: function() { return !self.macro.isRecording() && self.macro.getMacros().length > 0; }, callback: function() { self.openPlayMacroModal(); } },
          { name: '管理宏', when: function() { return !self.macro.isRecording() && self.macro.getMacros().length > 0; }, callback: function() { self.openManageMacroModal(); } }
        ]
      }
    ]);
  };

  RichDoc.prototype.closePopover = function() {
    var popover = this.root.querySelector('.richdoc-popover');
    if (!popover) return;
    popover.hidden = true;
    popover.innerHTML = '';
    if (this.popoverAnchor) this.popoverAnchor.setAttribute('aria-expanded', 'false');
    this.popoverAnchor = null;
    var cleanup = this.popoverCleanup;
    this.popoverCleanup = null;
    if (cleanup) cleanup();
  };

  RichDoc.prototype.openPopover = function(anchor, className, render) {
    var self = this;
    var popover = this.root.querySelector('.richdoc-popover');
    if (!popover || !anchor) return;
    if (this.popoverAnchor === anchor && !popover.hidden) {
      this.closePopover();
      return false;
    }
    this.closePopover();
    this.popoverAnchor = anchor;
    anchor.setAttribute('aria-expanded', 'true');
    popover.className = 'richdoc-popover ' + (className || '');
    render(popover, function() { self.closePopover(); });
    popover.hidden = false;
    var rootRect = this.root.getBoundingClientRect();
    var anchorRect = anchor.getBoundingClientRect();
    var left = Math.max(8, Math.min(anchorRect.left - rootRect.left, rootRect.width - popover.offsetWidth - 8));
    var top = anchorRect.bottom - rootRect.top + 6;
    if (top + popover.offsetHeight > rootRect.height - 8) top = anchorRect.top - rootRect.top - popover.offsetHeight - 6;
    popover.style.left = left + 'px';
    popover.style.top = Math.max(8, top) + 'px';
    return true;
  };

  RichDoc.prototype.createField = function(config) {
    var wrapper = document.createElement('label');
    wrapper.className = 'richdoc-field' + (config.wide ? ' richdoc-field-wide' : '');
    if (config.label) {
      var label = document.createElement('span');
      label.className = 'richdoc-field-label';
      label.textContent = config.label;
      if (config.required) label.classList.add('is-required');
      wrapper.appendChild(label);
    }
    var input;
    if (config.type === 'textarea') {
      input = document.createElement('textarea');
      input.rows = config.rows || 6;
    } else if (config.type === 'select') {
      input = document.createElement('select');
      (config.options || []).forEach(function(option) {
        var item = document.createElement('option');
        item.value = option.value;
        item.textContent = option.label;
        input.appendChild(item);
      });
    } else if (config.type === 'checkbox') {
      wrapper.classList.add('richdoc-field-checkbox');
      input = document.createElement('input');
      input.type = 'checkbox';
    } else {
      input = document.createElement('input');
      input.type = config.type || 'text';
    }
    input.name = config.name;
    if (config.placeholder) input.placeholder = config.placeholder;
    if (config.required) input.required = true;
    if (config.readonly) input.readOnly = true;
    if (config.min !== undefined) input.min = config.min;
    if (config.max !== undefined) input.max = config.max;
    if (config.step !== undefined) input.step = config.step;
    if (config.type === 'checkbox') input.checked = !!config.value;
    else if (config.value !== undefined && config.value !== null) input.value = String(config.value);
    wrapper.appendChild(input);
    if (config.help) {
      var help = document.createElement('small');
      help.textContent = config.help;
      wrapper.appendChild(help);
    }
    return wrapper;
  };

  RichDoc.prototype.closeModal = function(cancelled) {
    var layer = this.root.querySelector('.richdoc-modal-layer');
    if (!layer || layer.hidden) return;
    var cancel = this.modalCancel;
    layer.hidden = true;
    this.modalSubmit = null;
    this.modalCancel = null;
    if (this.modalAnchor && this.modalAnchor.focus) this.modalAnchor.focus();
    this.modalAnchor = null;
    if (cancelled && cancel) cancel();
  };

  RichDoc.prototype.openModal = function(config) {
    this.closePopover();
    this.closeSettings();
    var layer = this.root.querySelector('.richdoc-modal-layer');
    var form = layer.querySelector('.richdoc-modal-form');
    var fields = layer.querySelector('.richdoc-modal-fields');
    layer.querySelector('#richdoc-modal-title').textContent = config.title;
    layer.querySelector('.richdoc-button-primary').textContent = config.confirmText || '确定';
    fields.className = 'richdoc-modal-fields';
    fields.innerHTML = '';
    (config.fields || []).forEach(function(field) { fields.appendChild(this.createField(field)); }, this);
    this.modalAnchor = document.activeElement;
    this.modalSubmit = config.onConfirm;
    this.modalCancel = config.onCancel;
    form.onsubmit = function(event) {
      event.preventDefault();
      if (!form.reportValidity()) return;
      var values = {};
      Array.prototype.forEach.call(form.elements, function(input) {
        if (!input.name) return;
        values[input.name] = input.type === 'checkbox' ? input.checked : input.value;
      });
      var callback = this.modalSubmit;
      this.closeModal(false);
      if (callback) callback(values);
    }.bind(this);
    layer.hidden = false;
    var first = fields.querySelector('input:not([type="hidden"]), textarea, select');
    if (first) setTimeout(function() { first.focus(); if (first.select && first.tagName !== 'SELECT') first.select(); }, 0);
  };

  RichDoc.prototype.closeSettings = function() {
    var layer = this.root.querySelector('.richdoc-settings-layer');
    if (!layer || layer.hidden) return;
    layer.hidden = true;
    if (this.settingsAnchor && this.settingsAnchor.focus) this.settingsAnchor.focus();
    this.settingsAnchor = null;
  };

  RichDoc.prototype.openSettings = function(section) {
    this.closePopover();
    this.closeModal();
    var self = this;
    var layer = this.root.querySelector('.richdoc-settings-layer');
    var panel = layer.querySelector('.richdoc-settings-panel');
    var currentOptions = cloneValue(this.command('getOptions') || {});
    var defaults = {
      width: 794, height: 1123, paperDirection: 'vertical', pageMode: 'paging', margins: [60, 60, 60, 60],
      column: { count: 1, gap: 20, separator: false }, pageBorder: { disabled: false, color: '#d8dde8', lineWidth: 1 },
      defaultFont: 'Microsoft YaHei', defaultSize: 16, minSize: 1, maxSize: 500, defaultColor: '#1f2937', defaultHyperlinkColor: '#2563eb',
      defaultRowMargin: 1.5, defaultBasicRowMarginHeight: 8, defaultTabWidth: 32, wordBreak: 'break-word',
      title: { defaultFirstSize: 34, defaultSecondSize: 29, defaultThirdSize: 24, defaultFourthSize: 21 },
      header: { disabled: false, top: 30, editable: true }, footer: { disabled: false, bottom: 30, editable: true },
      pageNumber: { disabled: false, format: '第{pageNo}页 / 共{pageCount}页', rowFlex: 'center', bottom: 20, size: 12, color: '#6b7280', startPageNo: 1, fromPageNo: 0 },
      watermark: { data: '', type: 'text', color: '#aeb6c5', opacity: 0.2, size: 120, layer: 'bottom', repeat: true },
      background: { color: '#ffffff', image: '', size: 'cover', repeat: 'no-repeat' },
      scale: 1, renderMode: 'speed', printPixelRatio: 2,
      lineNumber: { disabled: true }, lineBreak: { disabled: true }, whiteSpace: { disabled: true }, magnifier: { disabled: true }, accessibility: { disabled: false }
    };
    var draft = mergeSettings(defaults, currentOptions);
    draft.width = Number(draft.width || draft.paperWidth || 794);
    draft.height = Number(draft.height || draft.paperHeight || 1123);
    draft.margins = cloneValue(this.command('getPaperMargin') || draft.margins || defaults.margins);
    var currentColumns = this.command('getColumns');
    if (currentColumns) draft.column = Object.assign({}, draft.column, currentColumns);

    function input(path, label, type, attributes) {
      return '<label class="richdoc-settings-field"><span>' + label + '</span><input data-setting-path="' + path + '"' + (type ? ' data-setting-type="' + type + '"' : '') + ' type="' + (type === 'number' ? 'number' : 'text') + '" ' + (attributes || '') + '></label>';
    }
    function color(path, label) { return '<label class="richdoc-settings-field"><span>' + label + '</span><input data-setting-path="' + path + '" type="color"></label>'; }
    function select(path, label, options, type) {
      return '<label class="richdoc-settings-field"><span>' + label + '</span><select data-setting-path="' + path + '"' + (type ? ' data-setting-type="' + type + '"' : '') + '>' + options + '</select></label>';
    }
    function check(path, label, invert) { return '<label class="richdoc-settings-check"><input data-setting-path="' + path + '" data-setting-type="boolean"' + (invert ? ' data-setting-invert="true"' : '') + ' type="checkbox"><span>' + label + '</span></label>'; }
    function pane(name, content, activePane) { return '<div class="richdoc-settings-pane' + (activePane ? ' is-active' : '') + '" data-settings-pane="' + name + '">' + content + '</div>'; }
    function sectionBlock(title, content) { return '<section class="richdoc-settings-section"><h3>' + title + '</h3>' + content + '</section>'; }
    var numberOptions = '<option value="1">1（关闭）</option><option value="2">2</option><option value="3">3</option><option value="4">4</option><option value="5">5</option>';
    var fontList = this.getSettingsFontFamilies(draft.defaultFont);
    var fontOptions = fontList.map(function(font) { return '<option value="' + escapeHTML(font) + '">' + escapeHTML(fontDisplayName(font)) + '</option>'; }).join('');
    var pagePane = sectionBlock('纸张', '<div class="richdoc-settings-grid">' + input('width','纸张宽度（px）','number','min="200" max="5000"') + input('height','纸张高度（px）','number','min="200" max="5000"') + select('paperDirection','纸张方向','<option value="vertical">纵向</option><option value="horizontal">横向</option>') + select('pageMode','页面模式','<option value="paging">分页</option><option value="continuity">连页</option>') + '</div>') +
      sectionBlock('页边距', '<div class="richdoc-settings-grid richdoc-settings-grid-four">' + input('margins.0','上','number','min="0" max="1000"') + input('margins.1','右','number','min="0" max="1000"') + input('margins.2','下','number','min="0" max="1000"') + input('margins.3','左','number','min="0" max="1000"') + '</div>') +
      sectionBlock('分栏与边框', '<div class="richdoc-settings-grid">' + select('column.count','栏数',numberOptions,'number') + input('column.gap','栏间距','number','min="0" max="300"') + check('column.separator','显示栏间分隔线') + check('pageBorder.disabled','显示页面边框',true) + color('pageBorder.color','边框颜色') + input('pageBorder.lineWidth','边框宽度','number','min="0.5" max="20" step="0.5"') + '</div>');
    var textPane = sectionBlock('默认字体', '<div class="richdoc-settings-grid">' + select('defaultFont','字体',fontOptions) + input('defaultSize','默认字号','number','min="1" max="500"') + input('minSize','最小字号','number','min="1" max="500"') + input('maxSize','最大字号','number','min="1" max="500"') + color('defaultColor','默认文字颜色') + color('defaultHyperlinkColor','超链接颜色') + '</div>') +
      sectionBlock('段落与换行', '<div class="richdoc-settings-grid">' + input('defaultRowMargin','默认行间距','number','min="0.5" max="5" step="0.05"') + input('defaultBasicRowMarginHeight','基础行高','number','min="0" max="100"') + input('defaultTabWidth','Tab 宽度','number','min="1" max="500"') + select('wordBreak','断行规则','<option value="break-word">中文标点与单词优化</option><option value="break-all">按字符宽度折行</option>') + '</div>') +
      sectionBlock('标题字号', '<div class="richdoc-settings-grid richdoc-settings-grid-four">' + input('title.defaultFirstSize','一级','number','min="5"') + input('title.defaultSecondSize','二级','number','min="5"') + input('title.defaultThirdSize','三级','number','min="5"') + input('title.defaultFourthSize','四级','number','min="5"') + '</div>');
    var headerPane = sectionBlock('页眉与页脚', '<div class="richdoc-settings-grid">' + check('header.disabled','启用页眉',true) + input('header.top','页眉距顶部','number','min="0"') + check('header.editable','允许编辑页眉') + check('footer.disabled','启用页脚',true) + input('footer.bottom','页脚距底部','number','min="0"') + check('footer.editable','允许编辑页脚') + '</div>') +
      sectionBlock('页码', '<div class="richdoc-settings-grid">' + check('pageNumber.disabled','显示页码',true) + input('pageNumber.format','格式','','placeholder="第{pageNo}页 / 共{pageCount}页"') + select('pageNumber.rowFlex','位置','<option value="left">左侧</option><option value="center">居中</option><option value="right">右侧</option>') + input('pageNumber.bottom','距底部','number','min="0"') + input('pageNumber.size','字号','number','min="5"') + color('pageNumber.color','字体颜色') + input('pageNumber.startPageNo','起始页码','number','min="0"') + input('pageNumber.fromPageNo','从第几页显示（0 开始）','number','min="0"') + '</div>');
    var watermarkPane = sectionBlock('水印', '<div class="richdoc-settings-grid">' + input('watermark.data','内容（留空表示关闭）') + select('watermark.type','类型','<option value="text">文字</option><option value="image">图片 URL</option>') + color('watermark.color','颜色') + input('watermark.opacity','透明度','number','min="0" max="1" step="0.05"') + input('watermark.size','字号','number','min="5" max="500"') + select('watermark.layer','层级','<option value="bottom">内容下方</option><option value="top">内容上方</option>') + check('watermark.repeat','重复铺满页面') + '</div>') +
      sectionBlock('页面背景', '<p class="richdoc-settings-tip">背景图片只接受系统上传后的 URL，不会把图片嵌入文档。</p><div class="richdoc-settings-grid">' + color('background.color','背景颜色') + input('background.image','背景图片 URL','','placeholder="/uploads/... 或 https://..."') + select('background.size','尺寸','<option value="cover">覆盖</option><option value="contain">完整显示</option><option value="auto">原始尺寸</option>') + select('background.repeat','重复','<option value="no-repeat">不重复</option><option value="repeat">重复</option><option value="repeat-x">水平重复</option><option value="repeat-y">垂直重复</option>') + '</div>');
    var displayPane = '<p class="richdoc-settings-tip">缩放、渲染和辅助显示是当前编辑器的显示配置。</p>' + sectionBlock('显示与打印', '<div class="richdoc-settings-grid">' + input('scale','页面缩放','number','min="0.5" max="3" step="0.1"') + select('renderMode','渲染模式','<option value="speed">极速</option><option value="compatibility">兼容</option>') + input('printPixelRatio','打印像素比','number','min="1" max="6" step="0.5"') + '</div>') + sectionBlock('辅助显示', '<div class="richdoc-settings-grid">' + check('lineNumber.disabled','显示行号',true) + check('lineBreak.disabled','显示换行符',true) + check('whiteSpace.disabled','显示空格符',true) + check('magnifier.disabled','启用放大镜',true) + check('accessibility.disabled','启用无障碍支持',true) + '</div>');
    panel.innerHTML = '<header class="richdoc-settings-head"><div><span>EDITOR SETTINGS</span><strong id="richdoc-settings-title">文档与编辑器设置</strong><small>排版配置随文档保存；应用前会校验关键参数。</small></div><button type="button" data-richdoc-close="settings" aria-label="关闭设置">×</button></header>' +
      '<form class="richdoc-settings-form"><div class="richdoc-settings-main"><nav class="richdoc-settings-nav" aria-label="设置分类">' +
      [['page','页面布局'],['text','默认文字'],['header','页眉页脚'],['watermark','水印与背景'],['display','显示与打印'],['advanced','高级 JSON']].map(function(item, index) { return '<button type="button" data-settings-tab="' + item[0] + '" class="' + (index ? '' : 'is-active') + '">' + item[1] + '</button>'; }).join('') +
      '</nav><div class="richdoc-settings-content">' + pane('page',pagePane,true) + pane('text',textPane) + pane('header',headerPane) + pane('watermark',watermarkPane) + pane('display',displayPane) + pane('advanced','<p class="richdoc-settings-tip">这里包含全部配置。危险键、异常数值及内嵌图片会被拒绝。</p><textarea class="richdoc-settings-json" spellcheck="false" aria-label="完整编辑器 JSON 配置"></textarea>') + '</div></div>' +
      '<footer class="richdoc-settings-actions"><button type="button" class="richdoc-button richdoc-button-secondary richdoc-settings-reset">恢复默认配置</button><span class="richdoc-settings-error" role="alert"></span><button type="button" class="richdoc-button richdoc-button-secondary" data-richdoc-close="settings">取消</button><button type="submit" class="richdoc-button richdoc-button-primary">应用设置</button></footer></form>';
    var form = panel.querySelector('form');
    var errorBox = panel.querySelector('.richdoc-settings-error');
    var jsonField = panel.querySelector('.richdoc-settings-json');
    var advancedDirty = false;
    function populate(value) {
      panel.querySelectorAll('[data-setting-path]').forEach(function(field) {
        var fieldValue = getPathValue(value, field.dataset.settingPath);
        var invert = field.dataset.settingInvert === 'true';
        if (field.dataset.settingType === 'boolean') field.checked = invert ? !Boolean(fieldValue) : Boolean(fieldValue);
        else field.value = fieldValue === undefined || fieldValue === null ? '' : String(fieldValue);
      });
      jsonField.value = JSON.stringify(value, null, 2);
    }
    function readForm() {
      var next = cloneValue(draft);
      panel.querySelectorAll('[data-setting-path]').forEach(function(field) {
        var invert = field.dataset.settingInvert === 'true';
        var value = field.dataset.settingType === 'boolean' ? (invert ? !field.checked : field.checked) : field.dataset.settingType === 'number' ? Number(field.value) : field.value;
        setPathValue(next, field.dataset.settingPath, value);
      });
      return next;
    }
    function parseAdvanced() {
      var value;
      try { value = JSON.parse(jsonField.value); }
      catch (error) { throw new Error('JSON 格式错误：' + error.message); }
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('配置顶层必须是 JSON 对象');
      return assertSafeSettings(mergeSettings(draft, value));
    }
    function setError(message, isInfo) { errorBox.textContent = message || ''; errorBox.classList.toggle('is-info', !!isInfo); }
    function switchTab(tab) {
      var current = panel.querySelector('[data-settings-tab].is-active');
      if (current && current.dataset.settingsTab === 'advanced' && advancedDirty && tab !== 'advanced') {
        try { draft = parseAdvanced(); populate(draft); advancedDirty = false; }
        catch (error) { setError(error.message); return false; }
      } else if (tab === 'advanced') {
        draft = readForm(); jsonField.value = JSON.stringify(draft, null, 2); advancedDirty = false;
      }
      panel.querySelectorAll('[data-settings-tab]').forEach(function(button) { button.classList.toggle('is-active', button.dataset.settingsTab === tab); });
      panel.querySelectorAll('[data-settings-pane]').forEach(function(currentPane) { currentPane.classList.toggle('is-active', currentPane.dataset.settingsPane === tab); });
      setError('');
      return true;
    }
    populate(draft);
    panel.querySelectorAll('[data-settings-tab]').forEach(function(button) { button.addEventListener('click', function() { switchTab(button.dataset.settingsTab); }); });
    jsonField.addEventListener('input', function() { advancedDirty = true; setError(''); });
    panel.querySelector('.richdoc-settings-reset').addEventListener('click', function() {
      Object.keys(defaults).forEach(function(path) { draft[path] = cloneValue(defaults[path]); });
      populate(draft);
      advancedDirty = false;
      setError('已载入默认配置，点击“应用设置”后生效', true);
    });
    form.onsubmit = function(event) {
      event.preventDefault();
      if (!form.reportValidity()) return;
      try {
        var activeTab = panel.querySelector('[data-settings-tab].is-active').dataset.settingsTab;
        draft = activeTab === 'advanced' ? parseAdvanced() : assertSafeSettings(readForm());
        self.command('executeUpdateOptions', draft);
        self.closeSettings();
        toast('编辑器设置已应用', 'success');
      } catch (error) { setError(error.message || '设置无法应用'); }
    };
    this.settingsAnchor = document.activeElement;
    layer.hidden = false;
    var initialTab = section === 'text' || section === 'header' || section === 'watermark' || section === 'display' || section === 'advanced' ? section : 'page';
    switchTab(initialTab);
    setTimeout(function() { var target = panel.querySelector('[data-settings-pane="' + initialTab + '"] input, [data-settings-pane="' + initialTab + '"] select, [data-settings-pane="' + initialTab + '"] textarea'); if (target) target.focus(); }, 0);
  };

  RichDoc.prototype.invoke = function(name) {
    var result;
    try {
      result = this.run(name);
    } catch (error) {
      console.error('[richdoc] command failed:', name, error);
      toast((error && error.message) || '操作失败，请重试', 'error');
      return;
    }
    if (result && typeof result.catch === 'function') {
      result.catch(function(error) {
        console.error('[richdoc] async command failed:', name, error);
        toast((error && error.message) || '操作失败，请重试', 'error');
      });
    }
    return result;
  };

  RichDoc.prototype.refreshRangeStyle = function(context) {
    if (!context) return;
    this.rangeContext = context;
    var root = this.root;
    var element = context.startElement || {};
    var activeCommands = {
      bold: !!element.bold,
      italic: !!element.italic,
      underline: !!element.underline,
      strikeout: !!element.strikeout,
      superscript: !!element.superscript || element.type === this.lib.ElementType.SUPERSCRIPT,
      subscript: !!element.subscript || element.type === this.lib.ElementType.SUBSCRIPT,
      left: element.rowFlex === this.lib.RowFlex.LEFT,
      center: element.rowFlex === this.lib.RowFlex.CENTER,
      right: element.rowFlex === this.lib.RowFlex.RIGHT,
      alignment: element.rowFlex === this.lib.RowFlex.ALIGNMENT,
      justify: element.rowFlex === this.lib.RowFlex.JUSTIFY
    };
    Object.keys(activeCommands).forEach(function(command) {
      root.querySelectorAll('button[data-command="' + command + '"]').forEach(function(button) {
        button.classList.toggle('is-active', activeCommands[command]);
        button.setAttribute('aria-pressed', activeCommands[command] ? 'true' : 'false');
      });
    });
    this.syncAlignmentPicker(element.rowFlex || this.lib.RowFlex.LEFT);
    var size = root.querySelector('select[data-command="size"]');
    var title = root.querySelector('select[data-command="title"]');
    if (element.font) this.syncFontPicker(element.font);
    if (size && element.size && Array.prototype.some.call(size.options, function(option) { return option.value === String(element.size); })) size.value = String(element.size);
    if (title) title.value = element.level || '';
  };

  RichDoc.prototype.syncCommandAvailability = function(controlState) {
    var readonlyMode = this.options.readonly || this.currentMode === 'readonly' || this.currentMode === 'trace' || this.currentMode === 'print';
    var controlActive = controlState === true || String(controlState || '').toLowerCase() === 'active';
    var allowedReadonly = { search: true, print: true, moreMenu: true, catalog: true, fullscreen: true, zoomOut: true, zoomReset: true, zoomIn: true };
    var blockedInControl = { table: true, link: true, separator: true, pageBreak: true, control: true };
    this.controlActive = controlActive;
    this.root.querySelectorAll('[data-command]').forEach(function(element) {
      var command = element.dataset.command;
      var disabled = (readonlyMode && !allowedReadonly[command]) || (controlActive && blockedInControl[command]);
      element.disabled = disabled;
      element.setAttribute('aria-disabled', disabled ? 'true' : 'false');
    });
    var traceToggle = this.root.querySelector('.richdoc-trace-toggle input');
    if (traceToggle) traceToggle.disabled = this.options.readonly || this.currentMode === 'trace';
  };

  RichDoc.prototype.bind = function() {
    var self = this;
    var lib = this.lib;
    var toolbar = this.root.querySelector('.richdoc-toolbar');
    this.root.addEventListener('click', function(event) {
      var close = event.target.closest('[data-richdoc-close]');
      if (close) {
        if (close.dataset.richdocClose === 'modal') self.closeModal(true);
        else self.closeSettings();
        return;
      }
      var btn = event.target.closest('[data-command]');
      if (!btn || btn.tagName === 'SELECT' || btn.tagName === 'INPUT') return;
      if (btn.disabled || btn.getAttribute('aria-disabled') === 'true') return;
      if (btn.dataset.command === 'painter') {
        clearTimeout(self.painterTimer);
        self.painterTimer = setTimeout(function() { self.invoke('painter'); }, 200);
        return;
      }
      self.invoke(btn.dataset.command);
    });
    this.root.addEventListener('dblclick', function(event) {
      var painter = event.target.closest('button[data-command="painter"]');
      if (!painter) return;
      clearTimeout(self.painterTimer);
      self.command('executePainter', { isDblclick: true });
    });
    this.outsidePointerHandler = function(event) {
      var popover = self.root.querySelector('.richdoc-popover');
      if (!popover || popover.hidden) return;
      if (!popover.contains(event.target) && event.target !== self.popoverAnchor && !self.popoverAnchor.contains(event.target)) self.closePopover();
    };
    this.escapeHandler = function(event) {
      if (event.key !== 'Escape') return;
      var modal = self.root.querySelector('.richdoc-modal-layer');
      var settings = self.root.querySelector('.richdoc-settings-layer');
      if (modal && !modal.hidden) self.closeModal(true);
      else if (settings && !settings.hidden) self.closeSettings();
      else self.closePopover();
    };
    this.shortcutHandler = function(event) {
      if (!(event.ctrlKey || event.metaKey) || String(event.key).toLowerCase() !== 'f') return;
      if (active !== self || self.options.readonly && !self.commandButton('search')) return;
      var modal = self.root.querySelector('.richdoc-modal-layer');
      var settings = self.root.querySelector('.richdoc-settings-layer');
      var target = event.target;
      if ((modal && !modal.hidden) || (settings && !settings.hidden) || target && (target.matches('input, textarea, select') || target.isContentEditable)) return;
      event.preventDefault();
      event.stopPropagation();
      self.openSearchPopover(self.command('getRangeText') || '');
    };
    document.addEventListener('pointerdown', this.outsidePointerHandler);
    document.addEventListener('keydown', this.escapeHandler);
    document.addEventListener('keydown', this.shortcutHandler, true);
    if (toolbar) {
      toolbar.addEventListener('change', function(event) {
        var target = event.target;
        var cmd = target.dataset && target.dataset.command;
        if (!cmd) return;
        if (cmd === 'font') self.command('executeFont', target.value);
        else if (cmd === 'size') self.command('executeSize', Number(target.value));
        else if (cmd === 'title') self.command('executeTitle', target.value || null);
      });
      var input = toolbar.querySelector('.richdoc-image-input');
      input.addEventListener('change', function() {
        if (input.files && input.files[0]) self.insertImageFile(input.files[0]);
        input.value = '';
      });
    }
    this.root.querySelectorAll('[data-panel-close]').forEach(function(btn) {
      btn.addEventListener('click', function() { btn.closest('aside').hidden = true; });
    });
    var mode = this.root.querySelector('.richdoc-mode');
    if (mode) mode.addEventListener('change', function() {
      var value = mode.value;
      var mapped = lib.EditorMode[String(value).toUpperCase()] || value;
      self.command('executeMode', mapped);
      self.currentMode = value;
      self.syncCommandAvailability(self.controlActive);
    });
    var traceToggle = this.root.querySelector('.richdoc-trace-toggle input');
    if (traceToggle) traceToggle.addEventListener('change', function() { self.command('executeToggleTrace', traceToggle.checked); });
    // canvas-editor's default paste-image path uses FileReader.readAsDataURL.
    // Override it so every local/pasted/dropped image is uploaded first.
    this.instance.override.pasteImage = function(file) {
      self.insertImageFile(file);
      return { preventDefault: true };
    };
    this.instance.override.paste = function(event) {
      var html = event && event.clipboardData ? (event.clipboardData.getData('text/html') || '') : '';
      var matches = html.match(/data:image\/[^"']+/gi) || [];
      if (!matches.length) return { preventDefault: false };
      matches.forEach(function(value, index) {
        self.insertImageFile(dataURLToFile(value, 'pasted-image-' + (index + 1) + '.png'));
      });
      return { preventDefault: true };
    };
    this.instance.override.drop = function(event) {
      var files = event && event.dataTransfer && event.dataTransfer.files;
      var images = files ? Array.prototype.filter.call(files, function(file) { return file.type.indexOf('image/') === 0; }) : [];
      if (!images.length) return { preventDefault: false };
      event.preventDefault();
      images.forEach(function(file) { self.insertImageFile(file); });
      return { preventDefault: true };
    };
    this.instance.listener.contentChange = function() {
      self.refreshStatus();
      self.refreshCatalog();
      if (self.options.onChange) self.options.onChange();
    };
    this.instance.listener.pageSizeChange = function(pageCount) { self.pageCount = pageCount || 1; self.refreshStatus(); };
    this.instance.listener.visiblePageNoListChange = function(pageList) {
      var visible = self.root.querySelector('.richdoc-visible-pages');
      if (visible) visible.textContent = '可见页码：' + (pageList || [0]).map(function(page) { return page + 1; }).join('、');
    };
    this.instance.listener.intersectionPageNoChange = function(page) {
      self.currentPage = Number(page || 0) + 1;
      self.refreshStatus();
    };
    this.instance.listener.pageScaleChange = function(scale) {
      var percentage = self.root.querySelector('.richdoc-scale');
      if (percentage) percentage.textContent = Math.round(Number(scale || 1) * 100) + '%';
    };
    this.instance.listener.rangeStyleChange = function() {
      var context = self.command('getRangeContext');
      var position = self.root.querySelector('.richdoc-position');
      if (context && position) position.textContent = '行：' + (Number(context.startRowNo || 0) + 1) + '　列：' + (Number(context.startColNo || 0) + 1);
      self.refreshRangeStyle(context);
    };
    this.instance.listener.controlChange = function(context) { self.syncCommandAvailability(context && context.state); };
    this.instance.listener.saved = function() { if (self.options.onChange) self.options.onChange(); };
    this.syncCommandAvailability(false);
  };

  RichDoc.prototype.commandButton = function(name) {
    var buttons = this.root.querySelectorAll('button[data-command="' + name + '"]');
    return Array.prototype.find.call(buttons, function(button) { return !button.closest('[hidden]'); }) || buttons[0];
  };

  RichDoc.prototype.openChoicePopover = function(name, title, choices, onSelect) {
    this.openPopover(this.groupActionAnchor || this.commandButton(name), 'richdoc-choice-popover', function(popover, close) {
      var heading = document.createElement('strong');
      heading.className = 'richdoc-popover-title';
      heading.textContent = title;
      popover.appendChild(heading);
      var list = document.createElement('div');
      list.className = 'richdoc-choice-list';
      list.setAttribute('role', 'listbox');
      choices.forEach(function(choice) {
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'richdoc-choice';
        button.setAttribute('role', 'option');
        if (choice.active) button.classList.add('is-selected');
        button.setAttribute('aria-selected', choice.active ? 'true' : 'false');
        button.innerHTML = choice.icon ? '<i class="' + choice.icon + '"></i><span></span>' : '<span></span>';
        button.querySelector('span').textContent = choice.label;
        button.addEventListener('click', function() { close(); onSelect(choice.value); });
        list.appendChild(button);
      });
      popover.appendChild(list);
    });
  };

  RichDoc.prototype.isGroupedCommandDisabled = function(name) {
    var readonlyMode = this.options.readonly || this.currentMode === 'readonly' || this.currentMode === 'trace' || this.currentMode === 'print';
    if (readonlyMode) return name !== 'print';
    return !!(this.controlActive && { table: true, link: true, separator: true, pageBreak: true, control: true }[name]);
  };

  RichDoc.prototype.invokeGrouped = function(name, anchorName) {
    var anchor = this.commandButton(anchorName);
    this.closePopover();
    this.groupActionAnchor = anchor;
    try { return this.invoke(name); }
    finally { this.groupActionAnchor = null; }
  };

  RichDoc.prototype.openGroupedPopover = function(anchorName, title, sections) {
    var self = this;
    return this.openPopover(this.commandButton(anchorName), 'richdoc-grouped-popover', function(popover, close) {
      var heading = document.createElement('strong');
      heading.className = 'richdoc-popover-title richdoc-grouped-title';
      heading.textContent = title;
      popover.appendChild(heading);
      sections.forEach(function(section) {
        var block = document.createElement('section');
        block.className = 'richdoc-command-section';
        var label = document.createElement('span');
        label.className = 'richdoc-command-section-label';
        label.textContent = section.label;
        block.appendChild(label);
        var grid = document.createElement('div');
        grid.className = 'richdoc-command-grid';
        section.items.forEach(function(item) {
          var action = document.createElement('button');
          action.type = 'button';
          action.className = 'richdoc-command-item';
          action.dataset.groupedCommand = item.command;
          action.disabled = self.isGroupedCommandDisabled(item.command);
          action.innerHTML = '<i class="fa-solid ' + item.icon + '" aria-hidden="true"></i><span></span>';
          action.querySelector('span').textContent = item.label;
          if (item.command === 'painter') {
            action.title = '双击可连续使用';
            action.addEventListener('click', function() {
              clearTimeout(self.groupPainterTimer);
              self.groupPainterTimer = setTimeout(function() { close(); self.invokeGrouped('painter', anchorName); }, 200);
            });
            action.addEventListener('dblclick', function() {
              clearTimeout(self.groupPainterTimer);
              close();
              self.command('executePainter', { isDblclick: true });
            });
          } else {
            action.addEventListener('click', function() { close(); self.invokeGrouped(item.command, anchorName); });
          }
          grid.appendChild(action);
        });
        block.appendChild(grid);
        popover.appendChild(block);
      });
    });
  };

  RichDoc.prototype.openTextMorePopover = function() {
    return this.openGroupedPopover('textMore', '更多文字工具', [{ label: '文字与格式', items: [
      { command: 'painter', icon: 'fa-paintbrush', label: '格式刷' },
      { command: 'format', icon: 'fa-eraser', label: '清除格式' },
      { command: 'sizeAdd', icon: 'fa-plus', label: '增大字号' },
      { command: 'sizeMinus', icon: 'fa-minus', label: '减小字号' },
      { command: 'strikeout', icon: 'fa-strikethrough', label: '删除线' },
      { command: 'superscript', icon: 'fa-superscript', label: '上标' },
      { command: 'subscript', icon: 'fa-subscript', label: '下标' }
    ] }]);
  };

  RichDoc.prototype.openAlignmentPopover = function() {
    var self = this;
    var lib = this.lib;
    var active = this.rangeContext && this.rangeContext.startElement && this.rangeContext.startElement.rowFlex || lib.RowFlex.LEFT;
    return this.openChoicePopover('alignmentMenu', '对齐方式', [
      { label: '左对齐', value: lib.RowFlex.LEFT, icon: 'fa-solid fa-align-left' },
      { label: '居中', value: lib.RowFlex.CENTER, icon: 'fa-solid fa-align-center' },
      { label: '右对齐', value: lib.RowFlex.RIGHT, icon: 'fa-solid fa-align-right' },
      { label: '分散对齐', value: lib.RowFlex.ALIGNMENT, icon: 'fa-solid fa-arrows-left-right' },
      { label: '两端对齐', value: lib.RowFlex.JUSTIFY, icon: 'fa-solid fa-align-justify' }
    ].map(function(choice) { choice.active = choice.value === active; return choice; }), function(value) {
      self.command('executeRowFlex', value);
      self.syncAlignmentPicker(value);
    });
  };

  RichDoc.prototype.syncAlignmentPicker = function(value) {
    var button = this.commandButton('alignmentMenu');
    if (!button) return;
    var map = {};
    map[this.lib.RowFlex.LEFT] = ['fa-align-left', '左对齐'];
    map[this.lib.RowFlex.CENTER] = ['fa-align-center', '居中'];
    map[this.lib.RowFlex.RIGHT] = ['fa-align-right', '右对齐'];
    map[this.lib.RowFlex.ALIGNMENT] = ['fa-arrows-left-right', '分散对齐'];
    map[this.lib.RowFlex.JUSTIFY] = ['fa-align-justify', '两端对齐'];
    var state = map[value] || map[this.lib.RowFlex.LEFT];
    button.querySelector('i').className = 'fa-solid ' + state[0];
    button.title = '对齐方式：' + state[1];
    button.setAttribute('aria-label', button.title);
  };

  RichDoc.prototype.openInsertPopover = function() {
    return this.openGroupedPopover('insertMenu', '插入', [
      { label: '常用', items: [
        { command: 'table', icon: 'fa-table', label: '表格' },
        { command: 'image', icon: 'fa-image', label: '图片' },
        { command: 'link', icon: 'fa-link', label: '链接' }
      ] },
      { label: '内容', items: [
        { command: 'separator', icon: 'fa-minus', label: '分隔线' },
        { command: 'pageBreak', icon: 'fa-file-arrow-down', label: '分页符' },
        { command: 'date', icon: 'fa-calendar-days', label: '日期' }
      ] },
      { label: '高级内容', items: [
        { command: 'code', icon: 'fa-code', label: '代码块' },
        { command: 'latex', icon: 'fa-square-root-variable', label: '公式' },
        { command: 'block', icon: 'fa-window-maximize', label: '内容块' }
      ] },
      { label: '表单控件', items: [
        { command: 'control', icon: 'fa-rectangle-list', label: '通用控件' },
        { command: 'checkbox', icon: 'fa-square-check', label: '复选框' },
        { command: 'radio', icon: 'fa-circle-dot', label: '单选框' }
      ] }
    ]);
  };

  RichDoc.prototype.openMoreToolsPopover = function() {
    return this.openGroupedPopover('moreMenu', '更多工具', [{ label: '文档', items: [
      { command: 'watermark', icon: 'fa-stamp', label: '水印' },
      { command: 'print', icon: 'fa-print', label: '打印' }
    ] }]);
  };

  RichDoc.prototype.openColorPopover = function() {
    var self = this;
    return this.openPopover(this.commandButton('colorMenu'), 'richdoc-color-popover', function(popover) {
      popover.innerHTML = '<strong class="richdoc-popover-title">文字颜色与高亮</strong>' +
        '<div class="richdoc-color-row"><span><i class="fa-solid fa-font"></i>文字颜色</span><input type="color" data-richdoc-color="text" value="#1f2937" aria-label="文字颜色"><button type="button" data-richdoc-color-clear="text">清除</button></div>' +
        '<div class="richdoc-color-presets" data-richdoc-color-presets="text"></div>' +
        '<div class="richdoc-color-row"><span><i class="fa-solid fa-highlighter"></i>高亮颜色</span><input type="color" data-richdoc-color="highlight" value="#fff59d" aria-label="高亮颜色"><button type="button" data-richdoc-color-clear="highlight">清除</button></div>' +
        '<div class="richdoc-color-presets" data-richdoc-color-presets="highlight"></div>';
      var palettes = {
        text: ['#1f2937','#dc2626','#ea580c','#ca8a04','#16a34a','#2563eb','#7c3aed','#db2777'],
        highlight: ['#fff59d','#fde68a','#fecaca','#fed7aa','#bbf7d0','#bfdbfe','#ddd6fe','#fbcfe8']
      };
      Object.keys(palettes).forEach(function(type) {
        var command = type === 'text' ? 'executeColor' : 'executeHighlight';
        var input = popover.querySelector('[data-richdoc-color="' + type + '"]');
        input.addEventListener('input', function() { self.command(command, input.value); });
        popover.querySelector('[data-richdoc-color-clear="' + type + '"]').addEventListener('click', function() { self.command(command, null); });
        var presets = popover.querySelector('[data-richdoc-color-presets="' + type + '"]');
        palettes[type].forEach(function(color) {
          var swatch = document.createElement('button');
          swatch.type = 'button';
          swatch.title = color;
          swatch.style.backgroundColor = color;
          swatch.addEventListener('click', function() { input.value = color; self.command(command, color); });
          presets.appendChild(swatch);
        });
      });
    });
  };

  RichDoc.prototype.openTablePopover = function() {
    var self = this;
    this.openPopover(this.groupActionAnchor || this.commandButton('table'), 'richdoc-table-popover', function(popover, close) {
      var header = document.createElement('div');
      header.className = 'richdoc-table-popover-head';
      var title = document.createElement('strong');
      title.className = 'richdoc-popover-title';
      title.textContent = '插入表格 · 1 × 1';
      var closeButton = document.createElement('button');
      closeButton.type = 'button';
      closeButton.className = 'richdoc-table-close';
      closeButton.setAttribute('aria-label', '关闭表格选择');
      closeButton.textContent = '×';
      closeButton.addEventListener('click', close);
      header.appendChild(title);
      header.appendChild(closeButton);
      popover.appendChild(header);
      var grid = document.createElement('div');
      grid.className = 'richdoc-table-grid';
      grid.setAttribute('role', 'grid');
      function highlight(rows, columns) {
        title.textContent = '插入表格 · ' + rows + ' × ' + columns;
        grid.querySelectorAll('button').forEach(function(cell) {
          cell.classList.toggle('is-active', Number(cell.dataset.row) <= rows && Number(cell.dataset.column) <= columns);
        });
      }
      for (var row = 1; row <= 10; row++) {
        for (var column = 1; column <= 10; column++) {
          var cell = document.createElement('button');
          cell.type = 'button';
          cell.dataset.row = row;
          cell.dataset.column = column;
          cell.setAttribute('aria-label', row + ' 行 ' + column + ' 列');
          cell.addEventListener('pointerenter', function() { highlight(Number(this.dataset.row), Number(this.dataset.column)); });
          cell.addEventListener('focus', function() { highlight(Number(this.dataset.row), Number(this.dataset.column)); });
          cell.addEventListener('click', function() {
            var selectedRow = Number(this.dataset.row);
            var selectedColumn = Number(this.dataset.column);
            close();
            self.focusCommand('executeInsertTable', selectedRow, selectedColumn);
          });
          grid.appendChild(cell);
        }
      }
      popover.appendChild(grid);
      highlight(1, 1);
    });
  };

  RichDoc.prototype.openWatermarkModal = function() {
    var self = this;
    this.openModal({
      title: '添加水印',
      fields: [
        { name: 'data', label: '水印内容', required: true, placeholder: '请输入水印文字', value: 'BookStark', wide: true },
        { name: 'color', label: '颜色', type: 'color', value: '#AEB5C0' },
        { name: 'size', label: '字号', type: 'number', min: 12, max: 240, value: 120 },
        { name: 'opacity', label: '透明度', type: 'number', min: 0.05, max: 1, step: 0.05, value: 0.3 },
        { name: 'repeat', label: '重复方式', type: 'select', value: '0', options: [{ label: '不重复', value: '0' }, { label: '重复', value: '1' }] },
        { name: 'horizontalGap', label: '水平间隔', type: 'number', min: 0, value: 10 },
        { name: 'verticalGap', label: '垂直间隔', type: 'number', min: 0, value: 10 }
      ],
      onConfirm: function(values) {
        var repeat = values.repeat === '1';
        self.focusCommand('executeAddWatermark', { data: values.data, color: values.color, size: Number(values.size), opacity: Number(values.opacity), repeat: repeat, gap: repeat ? [Number(values.horizontalGap), Number(values.verticalGap)] : undefined });
      }
    });
  };

  RichDoc.prototype.openControlModal = function(type) {
    var self = this;
    var lib = this.lib;
    var controlType = lib.ControlType[String(type).toUpperCase()];
    var valueSetsExample = '[\n  { "value": "是", "code": "yes" },\n  { "value": "否", "code": "no" }\n]';
    var configurations = {
      text: {
        title: '文本控件',
        fields: [
          { name: 'placeholder', label: '占位符', required: true, placeholder: '请输入占位符', wide: true },
          { name: 'value', label: '默认值', placeholder: '请输入默认值', wide: true }
        ]
      },
      number: {
        title: '数值控件',
        fields: [
          { name: 'placeholder', label: '占位符', required: true, placeholder: '请输入占位符', wide: true },
          { name: 'value', label: '默认值', type: 'number', placeholder: '请输入默认值', wide: true }
        ]
      },
      select: {
        title: '列举控件',
        fields: [
          { name: 'placeholder', label: '占位符', required: true, placeholder: '请输入占位符', wide: true },
          { name: 'code', label: '默认值编码', placeholder: '请输入默认值编码', wide: true },
          { name: 'valueSets', label: '值集 JSON', type: 'textarea', rows: 6, required: true, value: valueSetsExample, wide: true }
        ]
      },
      checkbox: {
        title: '复选框控件',
        fields: [
          { name: 'code', label: '默认值编码', placeholder: '多个值用英文逗号分隔', wide: true },
          { name: 'valueSets', label: '值集 JSON', type: 'textarea', rows: 6, required: true, value: valueSetsExample, wide: true }
        ]
      },
      radio: {
        title: '单选框控件',
        fields: [
          { name: 'code', label: '默认值编码', placeholder: '请输入默认值编码', wide: true },
          { name: 'valueSets', label: '值集 JSON', type: 'textarea', rows: 6, required: true, value: valueSetsExample, wide: true }
        ]
      },
      date: {
        title: '日期控件',
        fields: [
          { name: 'placeholder', label: '占位符', required: true, placeholder: '请输入占位符', wide: true },
          { name: 'value', label: '默认值', placeholder: '请输入默认值', wide: true },
          { name: 'dateFormat', label: '日期格式', type: 'select', value: 'yyyy-MM-dd hh:mm:ss', options: [{ label: 'yyyy-MM-dd hh:mm:ss', value: 'yyyy-MM-dd hh:mm:ss' }, { label: 'yyyy-MM-dd', value: 'yyyy-MM-dd' }] }
        ]
      }
    };
    var config = configurations[type];
    if (!config || !controlType) return toast('当前控件类型不可用', 'warning');
    this.openModal({
      title: config.title,
      fields: config.fields,
      onConfirm: function(values) {
        var control = { type: controlType, value: values.value ? [{ value: values.value }] : null };
        if (values.placeholder !== undefined) control.placeholder = values.placeholder;
        if (values.code !== undefined) control.code = values.code;
        if (values.dateFormat) control.dateFormat = values.dateFormat;
        if (values.valueSets) {
          try { control.valueSets = JSON.parse(values.valueSets); }
          catch (error) { toast('值集 JSON 格式错误', 'error'); return; }
        }
        self.focusCommand('executeInsertControl', { type: lib.ElementType.CONTROL, value: '', control: control });
      }
    });
  };

  RichDoc.prototype.refreshSearchResult = function(popover) {
    var result = popover && popover.querySelector('.richdoc-search-result');
    if (!result) return;
    var info = this.command('getSearchNavigateInfo');
    result.textContent = info && info.count ? info.index + '/' + info.count : '';
  };

  RichDoc.prototype.openSearchPopover = function(initialValue) {
    var self = this;
    var opened = this.openPopover(this.commandButton('search'), 'richdoc-search-popover', function(popover, close) {
      popover.innerHTML = '<div class="richdoc-search-row"><input type="text" class="richdoc-search-input" aria-label="查找内容" placeholder="查找内容"><span class="richdoc-search-result"></span><button type="button" class="richdoc-search-nav" data-search-nav="prev" title="上一个" aria-label="上一个"><i class="fa-solid fa-chevron-up"></i></button><button type="button" class="richdoc-search-nav" data-search-nav="next" title="下一个" aria-label="下一个"><i class="fa-solid fa-chevron-down"></i></button><button type="button" class="richdoc-search-close" title="关闭" aria-label="关闭">×</button></div>' +
        '<div class="richdoc-search-row"><input type="text" class="richdoc-replace-input" aria-label="替换为" placeholder="替换为"><button type="button" class="richdoc-search-replace">替换</button></div>' +
        '<div class="richdoc-search-options"><label><input type="checkbox" data-search-option="reg">正则</label><label><input type="checkbox" data-search-option="case">忽略大小写</label><label><input type="checkbox" data-search-option="selection">选定内容内查找</label></div>';
      var searchInput = popover.querySelector('.richdoc-search-input');
      var replaceInput = popover.querySelector('.richdoc-replace-input');
      searchInput.value = initialValue || '';
      Object.keys(self.searchOptions).forEach(function(name) { popover.querySelector('[data-search-option="' + name + '"]').checked = self.searchOptions[name]; });
      function search() {
        var keyword = searchInput.value || null;
        self.searchOptions.reg = popover.querySelector('[data-search-option="reg"]').checked;
        self.searchOptions.case = popover.querySelector('[data-search-option="case"]').checked;
        self.searchOptions.selection = popover.querySelector('[data-search-option="selection"]').checked;
        var options = { isRegEnable: self.searchOptions.reg, isIgnoreCase: self.searchOptions.case, isLimitSelection: self.searchOptions.selection };
        try { self.command('executeSearch', keyword, options); self.refreshSearchResult(popover); popover.classList.remove('has-error'); }
        catch (error) { popover.classList.add('has-error'); }
      }
      searchInput.addEventListener('input', search);
      searchInput.addEventListener('keydown', function(event) { if (event.key === 'Enter') search(); });
      popover.querySelectorAll('[data-search-option]').forEach(function(input) { input.addEventListener('change', search); });
      popover.querySelector('[data-search-nav="prev"]').addEventListener('click', function() { self.command('executeSearchNavigatePre'); self.refreshSearchResult(popover); });
      popover.querySelector('[data-search-nav="next"]').addEventListener('click', function() { self.command('executeSearchNavigateNext'); self.refreshSearchResult(popover); });
      popover.querySelector('.richdoc-search-replace').addEventListener('click', function() {
        if (searchInput.value && searchInput.value !== replaceInput.value) {
          self.command('executeReplace', replaceInput.value);
          self.refreshSearchResult(popover);
        }
      });
      popover.querySelector('.richdoc-search-close').addEventListener('click', close);
      if (searchInput.value) search();
      setTimeout(function() { searchInput.focus(); searchInput.select(); }, 0);
    });
    if (opened) this.popoverCleanup = function() { self.command('executeSearch', null); };
  };

  RichDoc.prototype.run = function(name) {
    var lib = this.lib;
    var self = this;
    var map = {
      undo: ['executeUndo'], redo: ['executeRedo'], painter: ['executePainter', { isDblclick: false }], format: ['executeFormat'], bold: ['executeBold'], italic: ['executeItalic'], underline: ['executeUnderline'], strikeout: ['executeStrikeout'], superscript: ['executeSuperscript'], subscript: ['executeSubscript'],
      sizeAdd: ['executeSizeAdd'], sizeMinus: ['executeSizeMinus'],
      left: ['executeRowFlex', lib.RowFlex.LEFT], center: ['executeRowFlex', lib.RowFlex.CENTER], right: ['executeRowFlex', lib.RowFlex.RIGHT], alignment: ['executeRowFlex', lib.RowFlex.ALIGNMENT], justify: ['executeRowFlex', lib.RowFlex.JUSTIFY],
      pageBreak: ['executePageBreak'], checkbox: ['executeInsertElementList', [{ type: lib.ElementType.CHECKBOX, value: '', checkbox: { value: false } }]], radio: ['executeInsertElementList', [{ type: lib.ElementType.RADIO, value: '', radio: { value: false } }]],
      zoomOut: ['executePageScaleMinus'], zoomReset: ['executePageScaleRecovery'], zoomIn: ['executePageScaleAdd'], print: ['executePrint']
    };
    if (map[name]) {
      return this.command.apply(this, map[name]);
    }
    if (name === 'save') {
      if (typeof global.manualSave === 'function') global.manualSave();
      return;
    }
    if (name === 'share') {
      if (typeof global.openEditorShare === 'function') global.openEditorShare();
      return;
    }
    if (name === 'image') return this.root.querySelector('.richdoc-image-input').click();
    if (name === 'fontMenu') return this.openFontPopover();
    if (name === 'colorMenu') return this.openColorPopover();
    if (name === 'textMore') return this.openTextMorePopover();
    if (name === 'alignmentMenu') return this.openAlignmentPopover();
    if (name === 'insertMenu') return this.openInsertPopover();
    if (name === 'moreMenu') return this.openMoreToolsPopover();
    if (name === 'underlineStyle') {
      var underlineValue = this.rangeContext && this.rangeContext.startElement && this.rangeContext.startElement.underline;
      var activeUnderlineStyle = underlineValue && typeof underlineValue === 'object' ? underlineValue.style : underlineValue ? 'solid' : '';
      return this.openChoicePopover(name, '下划线样式', [
        { label: '单实线', value: 'solid', icon: 'richdoc-underline-preview is-solid' },
        { label: '双实线', value: 'double', icon: 'richdoc-underline-preview is-double' },
        { label: '虚线', value: 'dashed', icon: 'richdoc-underline-preview is-dashed' },
        { label: '点线', value: 'dotted', icon: 'richdoc-underline-preview is-dotted' },
        { label: '波浪线', value: 'wavy', icon: 'richdoc-underline-preview is-wavy' }
      ].map(function(choice) { choice.active = choice.value === activeUnderlineStyle; return choice; }), function(value) { self.focusCommand('executeUnderline', { style: value }); });
    }
    if (name === 'rowMargin') {
      var activeRowMargin = this.rangeContext && this.rangeContext.startElement && this.rangeContext.startElement.rowMargin;
      return this.openChoicePopover(name, '行间距', [1, 1.25, 1.5, 1.75, 2, 2.5, 3].map(function(value) { return { label: value + ' 倍', value: value, active: Number(activeRowMargin) === value }; }), function(value) { self.focusCommand('executeRowMargin', value); });
    }
    if (name === 'list') {
      var listElement = this.rangeContext && this.rangeContext.startElement || {};
      return this.openChoicePopover(name, '列表样式', [
        { label: '取消列表', value: { type: null, style: undefined }, icon: 'fa-solid fa-ban' },
        { label: '有序列表', value: { type: lib.ListType.OL, style: lib.ListStyle.DECIMAL }, icon: 'fa-solid fa-list-ol' },
        { label: '复选框列表', value: { type: lib.ListType.UL, style: lib.ListStyle.CHECKBOX }, icon: 'fa-solid fa-list-check' },
        { label: '实心圆点列表', value: { type: lib.ListType.UL, style: lib.ListStyle.DISC }, icon: 'fa-solid fa-circle' },
        { label: '空心圆点列表', value: { type: lib.ListType.UL, style: lib.ListStyle.CIRCLE }, icon: 'fa-regular fa-circle' },
        { label: '空心方块列表', value: { type: lib.ListType.UL, style: lib.ListStyle.SQUARE }, icon: 'fa-regular fa-square' }
      ].map(function(choice) { choice.active = choice.value.type === (listElement.listType || null) && choice.value.style === listElement.listStyle; return choice; }), function(value) { self.focusCommand('executeList', value.type, value.style); });
    }
    if (name === 'separator') {
      return this.openChoicePopover(name, '分隔线样式', [
        { label: '实线', value: [], icon: 'richdoc-line-preview is-solid' },
        { label: '点线', value: [1, 1], icon: 'richdoc-line-preview is-dotted' },
        { label: '短虚线', value: [3, 1], icon: 'richdoc-line-preview is-dashed' },
        { label: '方形虚线', value: [4, 4], icon: 'richdoc-line-preview is-square-dashed' },
        { label: '点划线', value: [7, 3, 3, 3], icon: 'richdoc-line-preview is-long-dashed' },
        { label: '双点划线', value: [6, 2, 2, 2, 2, 2], icon: 'richdoc-line-preview is-double-dashed' }
      ], function(value) { self.focusCommand('executeSeparator', value); });
    }
    if (name === 'watermark') {
      return this.openChoicePopover(name, '水印', [
        { label: '添加水印', value: 'add', icon: 'fa-solid fa-plus' },
        { label: '删除水印', value: 'delete', icon: 'fa-solid fa-trash' }
      ], function(value) {
        if (value === 'add') self.openWatermarkModal();
        else self.focusCommand('executeDeleteWatermark');
      });
    }
    if (name === 'table') {
      return this.openTablePopover();
    }
    if (name === 'link') {
      var selectedText = this.command('getRangeText') || '';
      return this.openModal({
        title: '插入超链接',
        fields: [
          { name: 'text', label: '显示文本', required: true, value: selectedText, placeholder: '请输入显示文本', wide: true },
          { name: 'url', label: '链接地址', required: true, value: '', placeholder: 'https://example.com', wide: true }
        ],
        onConfirm: function(values) {
          self.focusCommand('executeHyperlink', { type: lib.ElementType.HYPERLINK, value: '', url: values.url, valueList: self.lib.splitText(values.text).map(function(value) { return { value: value }; }) });
        }
      });
    }
    if (name === 'code') {
      return this.openModal({
        title: '插入代码块',
        fields: [{ name: 'code', label: '代码', type: 'textarea', rows: 12, required: true, placeholder: '请输入代码', wide: true }],
        onConfirm: function(values) { self.focusCommand('executeInsertElementList', self.lib.splitText('\n' + values.code).map(function(value) { return { value: value, font: 'monospace', highlight: '#f3f4f6' }; })); }
      });
    }
    if (name === 'latex') {
      return this.openModal({
        title: '插入 LaTeX 公式',
        fields: [{ name: 'latex', label: '公式', type: 'textarea', rows: 4, required: true, value: 'E=mc^2', placeholder: '例如：\\frac{a}{b}', wide: true }],
        onConfirm: function(values) { self.focusCommand('executeInsertElementList', [{ type: lib.ElementType.LATEX, value: values.latex }]); }
      });
    }
    if (name === 'block') {
      return this.openModal({
        title: '插入内容块',
        fields: [
          { name: 'type', label: '类型', type: 'select', value: 'iframe', options: [{ label: '网址', value: 'iframe' }, { label: '视频', value: 'video' }] },
          { name: 'width', label: '宽度（px）', type: 'number', min: 120, max: 2400, placeholder: '默认使用页面内宽度' },
          { name: 'height', label: '高度（px）', type: 'number', required: true, min: 120, max: 1600, value: 360 },
          { name: 'src', label: '地址', placeholder: '请输入网址或视频地址', wide: true },
          { name: 'srcdoc', label: 'HTML', type: 'textarea', rows: 5, placeholder: '请输入 HTML 代码（仅网址类型有效）', wide: true }
        ],
        onConfirm: function(values) {
          var block = { type: values.type };
          if (values.type === 'iframe') {
            if (!values.src && !values.srcdoc) return toast('网址和 HTML 至少填写一项', 'warning');
            block.iframeBlock = { src: values.src, srcdoc: values.srcdoc };
          } else {
            if (!values.src) return toast('请输入视频地址', 'warning');
            block.videoBlock = { src: values.src };
          }
          var element = { type: lib.ElementType.BLOCK, value: '', height: Number(values.height), block: block };
          if (values.width) element.width = Number(values.width);
          self.focusCommand('executeInsertElementList', [element]);
        }
      });
    }
    if (name === 'control') {
      return this.openChoicePopover(name, '控件类型', [
        { label: '文本', value: 'text', icon: 'fa-solid fa-font' },
        { label: '数值', value: 'number', icon: 'fa-solid fa-hashtag' },
        { label: '列举', value: 'select', icon: 'fa-solid fa-list' },
        { label: '日期', value: 'date', icon: 'fa-solid fa-calendar-days' },
        { label: '复选框', value: 'checkbox', icon: 'fa-solid fa-square-check' },
        { label: '单选框', value: 'radio', icon: 'fa-solid fa-circle-dot' }
      ], function(value) { self.openControlModal(value); });
    }
    if (name === 'search') {
      return this.openSearchPopover(this.command('getRangeText') || '');
    }
    if (name === 'comment') return this.addComment();
    if (name === 'catalog') return this.togglePanel('catalog');
    if (name === 'pageSetup') {
      var paperOptions = this.command('getOptions') || {};
      var paperWidth = Number(paperOptions.width || paperOptions.paperWidth || 0);
      var paperHeight = Number(paperOptions.height || paperOptions.paperHeight || 0);
      return this.openChoicePopover(name, '纸张类型', [
        { label: 'A4', value: [794, 1123] }, { label: 'A2', value: [1593, 2251] }, { label: 'A3', value: [1125, 1593] }, { label: 'A5', value: [565, 796] },
        { label: '5号信封', value: [412, 488] }, { label: '6号信封', value: [450, 866] }, { label: '7号信封', value: [609, 862] }, { label: '9号信封', value: [862, 1221] },
        { label: '法律用纸', value: [813, 1266] }, { label: '信纸', value: [813, 1054] }
      ].map(function(choice) { choice.active = choice.value[0] === paperWidth && choice.value[1] === paperHeight; return choice; }), function(value) { self.command('executePaperSize', value[0], value[1]); });
    }
    if (name === 'paperDirection') {
      var activeDirection = (this.command('getOptions') || {}).paperDirection;
      return this.openChoicePopover(name, '纸张方向', [{ label: '纵向', value: lib.PaperDirection.VERTICAL, active: activeDirection === lib.PaperDirection.VERTICAL }, { label: '横向', value: lib.PaperDirection.HORIZONTAL, active: activeDirection === lib.PaperDirection.HORIZONTAL }], function(value) { self.command('executePaperDirection', value); });
    }
    if (name === 'margins') {
      var currentMargins = this.command('getPaperMargin') || [100, 120, 100, 120];
      return this.openModal({
        title: '页边距',
        fields: [
          { name: 'top', label: '上边距', type: 'number', min: 0, required: true, value: currentMargins[0] },
          { name: 'right', label: '右边距', type: 'number', min: 0, required: true, value: currentMargins[1] },
          { name: 'bottom', label: '下边距', type: 'number', min: 0, required: true, value: currentMargins[2] },
          { name: 'left', label: '左边距', type: 'number', min: 0, required: true, value: currentMargins[3] }
        ],
        onConfirm: function(values) { self.command('executeSetPaperMargin', [Number(values.top), Number(values.right), Number(values.bottom), Number(values.left)]); }
      });
    }
    if (name === 'columns') {
      var currentColumns = this.command('getColumns') || { count: 1, gap: 20, separator: false };
      return this.openModal({
        title: '分栏',
        fields: [
          { name: 'count', label: '栏数', type: 'select', value: String(currentColumns.count || 1), options: [{ label: '1（关闭）', value: '1' }, { label: '2', value: '2' }, { label: '3', value: '3' }, { label: '4', value: '4' }, { label: '5', value: '5' }] },
          { name: 'gap', label: '栏间距（px）', type: 'number', min: 0, required: true, value: currentColumns.gap || 20 },
          { name: 'separator', label: '分隔线', type: 'select', value: currentColumns.separator ? 'true' : 'false', options: [{ label: '不显示', value: 'false' }, { label: '显示', value: 'true' }] }
        ],
        onConfirm: function(values) { self.command('executeSetColumns', { count: Number(values.count), gap: Number(values.gap), separator: values.separator === 'true' }); }
      });
    }
    if (name === 'settings') {
      return this.openSettings('page');
    }
    if (name === 'date') {
      var now = new Date();
      var pad = function(value) { return String(value).padStart(2, '0'); };
      var dateValue = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
      var datetimeValue = dateValue + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds());
      return this.openChoicePopover(name, '插入日期', [{ label: dateValue, value: { text: dateValue, format: 'yyyy-MM-dd' } }, { label: datetimeValue, value: { text: datetimeValue, format: 'yyyy-MM-dd hh:mm:ss' } }], function(value) {
        self.focusCommand('executeInsertElementList', [{ type: lib.ElementType.DATE, value: '', dateFormat: value.format, valueList: [{ value: value.text }] }]);
      });
    }
    if (name === 'pageMode') {
      var activePageMode = (this.command('getOptions') || {}).pageMode;
      return this.openChoicePopover(name, '页面模式', [{ label: '分页', value: lib.PageMode.PAGING, active: activePageMode === lib.PageMode.PAGING }, { label: '连页', value: lib.PageMode.CONTINUITY, active: activePageMode === lib.PageMode.CONTINUITY }], function(value) { self.command('executePageMode', value); });
    }
    if (name === 'fullscreen') {
      if (document.fullscreenElement) document.exitFullscreen();
      else this.root.requestFullscreen();
    }
  };

  RichDoc.prototype.insertImageFile = function(file) {
    var self = this;
    if (!file || file.type.indexOf('image/') !== 0) return Promise.reject(new Error('请选择图片文件'));
    this.pendingUploads++;
    this.refreshUploadState();
    var task = hashAndUpload(file, this.options).then(function(data) {
      return new Promise(function(resolve) {
        var image = new Image();
        image.onload = function() {
          var width = data.width || image.naturalWidth || 480;
          var height = data.height || image.naturalHeight || 320;
          if (width > 720) { height = Math.round(height * 720 / width); width = 720; }
          self.command('executeImage', { value: data.url, width: width, height: height });
          resolve(data.url);
        };
        image.onerror = function() {
          self.command('executeImage', { value: data.url, width: data.width || 480, height: data.height || 320 });
          resolve(data.url);
        };
        image.src = data.url;
      });
    }).catch(function(error) {
      toast(error.message || '图片上传失败', 'error');
      return null;
    }).finally(function() {
      self.pendingUploads--;
      self.refreshUploadState();
    });
    this.uploadPromise = Promise.allSettled([this.uploadPromise, task]).then(function() {});
    return task;
  };

  RichDoc.prototype.refreshUploadState = function() {
    var el = this.root.querySelector('.richdoc-upload-state');
    if (el) el.textContent = this.pendingUploads ? '图片上传中…' : '';
  };

  RichDoc.prototype.flushUploads = function() {
    return this.uploadPromise;
  };

  RichDoc.prototype.getContent = function() {
    var result = this.instance.command.getValue();
    var options = result.options || {};
    options.mode = 'edit';
    var payload = {
      schema: 'bookstark-richdoc', schema_version: 1,
      editor_version: result.version || '0.9.137', data: result.data,
      options: options, comments: this.comments
    };
    if (hasEmbeddedImage(payload)) throw new Error('图片尚未上传完成，不能保存内嵌图片');
    return JSON.stringify(payload);
  };

  RichDoc.prototype.setReadonly = function(readonly) {
    readonly = !!readonly;
    this.command('executeMode', readonly ? this.lib.EditorMode.READONLY : this.lib.EditorMode.EDIT);
    this.options.readonly = readonly;
    this.currentMode = readonly ? 'readonly' : 'edit';
    this.root.classList.toggle('is-readonly', readonly);
    var mode = this.root.querySelector('.richdoc-mode');
    if (mode) mode.value = this.currentMode;
    this.syncCommandAvailability(this.controlActive);
  };

  RichDoc.prototype.addComment = function() {
    var self = this;
    var text = this.command('getRangeText');
    if (!text) return toast('请先选择要批注的文字', 'warning');
    this.openModal({
      title: '添加批注',
      confirmText: '添加批注',
      fields: [
        { name: 'selection', label: '所选文字', value: text, readonly: true, wide: true, help: '批注会关联到当前选中的文字。' },
        { name: 'content', label: '批注内容', type: 'textarea', rows: 5, required: true, placeholder: '请输入批注内容', wide: true }
      ],
      onConfirm: function(values) {
        var id = self.focusCommand('executeSetGroup');
        if (!id) return;
        self.comments.push({ id: id, content: values.content, author: self.options.author || '共享编辑者', range_text: text, created_at: new Date().toISOString() });
        self.refreshComments();
        if (self.options.onChange) self.options.onChange();
        self.togglePanel('comments');
      }
    });
  };

  RichDoc.prototype.refreshComments = function() {
    var self = this;
    var list = this.root.querySelector('.richdoc-comment-list');
    if (!list) return;
    list.innerHTML = '';
    this.comments.forEach(function(comment) {
      var item = document.createElement('button');
      item.type = 'button';
      item.className = 'richdoc-comment-item';
      item.textContent = comment.range_text + ' — ' + comment.content + ' · ' + comment.author;
      item.addEventListener('click', function() { self.command('executeLocationGroup', comment.id); });
      list.appendChild(item);
    });
  };

  RichDoc.prototype.refreshCatalog = function() {
    var self = this;
    var list = this.root.querySelector('.richdoc-catalog-list');
    if (!list || !this.instance.command.getCatalog) return;
    Promise.resolve(this.instance.command.getCatalog()).then(function(items) {
      list.innerHTML = '';
      function append(entries, depth) {
        (entries || []).forEach(function(entry) {
          var btn = document.createElement('button');
          btn.type = 'button'; btn.className = 'richdoc-catalog-item'; btn.textContent = entry.name;
          btn.style.paddingLeft = (8 + depth * 12) + 'px';
          btn.onclick = function() { self.command('executeLocationCatalog', entry.id); };
          list.appendChild(btn);
          append(entry.subCatalog, depth + 1);
        });
      }
      append(items, 0);
    });
  };

  RichDoc.prototype.togglePanel = function(name) {
    var panel = this.root.querySelector(name === 'catalog' ? '.richdoc-catalog' : '.richdoc-comments');
    if (panel) panel.hidden = !panel.hidden;
    if (name === 'catalog') this.refreshCatalog(); else this.refreshComments();
  };

  RichDoc.prototype.refreshStatus = function() {
    var self = this;
    if (!this.instance) return;
    var count = this.root.querySelector('.richdoc-word-count');
    Promise.resolve(this.instance.command.getWordCount()).then(function(value) { if (count) count.textContent = '字数：' + (value || 0); });
    var info = this.root.querySelector('.richdoc-page-info');
    if (info) info.textContent = '页面：' + (this.currentPage || 1) + ' / ' + (this.pageCount || 1);
  };

  RichDoc.prototype.insertAIText = function(text, replaceSelection, selectAll) {
    if (!text) return;
    if (selectAll) this.command('executeSelectAll');
    var elements = this.lib.splitText(text).map(function(value) { return { value: value }; });
    this.command('executeInsertElementList', elements, { isReplace: replaceSelection !== false });
  };

  RichDoc.prototype.getSelectionText = function() { return this.command('getRangeText') || ''; };
  RichDoc.prototype.getText = function() {
    var value = this.command('getText') || {};
    return [value.header, value.main, value.footer].filter(Boolean).join('\n');
  };

  RichDoc.prototype.destroy = function() {
    this.destroyed = true;
    clearTimeout(this.painterTimer);
    clearTimeout(this.groupPainterTimer);
    if (this.outsidePointerHandler) document.removeEventListener('pointerdown', this.outsidePointerHandler);
    if (this.escapeHandler) document.removeEventListener('keydown', this.escapeHandler);
    if (this.shortcutHandler) document.removeEventListener('keydown', this.shortcutHandler, true);
    if (this.instance && this.instance.destroy) this.instance.destroy();
    this.container.innerHTML = '';
    if (active === this) active = null;
  };

  function mount(containerId, raw, options) {
    var container = typeof containerId === 'string' ? document.getElementById(containerId) : containerId;
    if (!container) return Promise.reject(new Error('富文档容器不存在'));
    if (active) active.destroy();
    container.innerHTML = '<div class="richdoc-loading"><i class="fa-solid fa-spinner fa-spin"></i> 正在加载富文档…</div>';
    return load().then(function(lib) {
      active = new RichDoc(container, raw, options || {}, lib);
      return active;
    }).catch(function(error) {
      container.innerHTML = '<div class="richdoc-load-error">' + error.message + '</div>';
      throw error;
    });
  }

  global.BookStarkRichDoc = {
    VERSION: '0.9.137', load: load, mount: mount,
    defaultContent: function() { return JSON.stringify(defaultEnvelope()); },
    parse: parseEnvelope,
    get active() { return active; },
    destroy: function() { if (active) active.destroy(); }
  };
})(window);
