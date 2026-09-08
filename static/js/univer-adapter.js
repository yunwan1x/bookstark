(function() {
  'use strict';

  var loaded = false;
  var loading = false;
  var callbacks = [];
  var univer = null;
  var univerAPI = null;
  var workbook = null;
  var themeObserver = null;
  var renderReadyTimer = null;
  var running = false;
  var dirty = false;
  var baseline = '';
  var lastContainerId = '';
  var lastReadonly = false;

  function showUploadError(error) {
    var fallback = (typeof window.__ === 'function' && window.__('editor.upload_failed')) || 'Upload failed';
    var message = error && error.message && !/^HTTP \d+$/.test(error.message) ? error.message : fallback;
    if (window.BookStarkErrors && typeof window.BookStarkErrors.toast === 'function') {
      window.BookStarkErrors.toast(message, 'error', fallback);
    } else if (window.BSDialog && typeof window.BSDialog.toast === 'function') {
      window.BSDialog.toast(message, 'error');
    } else {
      console.error(message);
    }
  }

  function uploadImageFile(file) {
    function postUpload() {
      var formData = new FormData();
      formData.append('file', file);
      formData.append('category', 'spreadsheet');
      var fetcher = typeof window.csrfFetch === 'function' ? window.csrfFetch : window.fetch.bind(window);
      return fetcher('/api/uploads', { method: 'POST', body: formData }).then(function(response) {
        return response.json().catch(function() { return null; }).then(function(payload) {
          if (!response.ok || !payload || payload.code !== 0 || !payload.data || !payload.data.url) {
            throw new Error((payload && payload.message) || 'HTTP ' + response.status);
          }
          return payload.data;
        });
      });
    }

    var findExisting = Promise.resolve(null);
    if (typeof window.computeFileHash === 'function' && typeof window.checkUploadByHash === 'function') {
      findExisting = window.computeFileHash(file).then(function(hash) {
        return window.checkUploadByHash(hash);
      }).catch(function() { return null; });
    }
    return findExisting.then(function(existing) {
      if (existing && existing.url) return existing;
      return postUpload();
    }).catch(function(error) {
      showUploadError(error);
      throw error;
    });
  }

  window.BookStarkUniverUploadImage = uploadImageFile;

  function versionedAsset(path, version) {
    return version ? path + '?v=' + encodeURIComponent(version) : path;
  }

  function loadingElement() {
    return document.getElementById('univer-loading');
  }

  function revealWhenRendered(container) {
    var loadingEl = loadingElement();
    var attempts = 0;
    if (renderReadyTimer) clearInterval(renderReadyTimer);
    renderReadyTimer = setInterval(function() {
      attempts += 1;
      var canvases = container.querySelectorAll('canvas');
      var rendered = Array.prototype.some.call(canvases, function(canvas) {
        var rect = canvas.getBoundingClientRect();
        return rect.width > 50 && rect.height > 50;
      });
      if (!rendered && attempts < 60) return;
      clearInterval(renderReadyTimer);
      renderReadyTimer = null;
      container.style.visibility = '';
      if (loadingEl) loadingEl.style.display = 'none';
      window.dispatchEvent(new CustomEvent('bookstark:univer-ready'));
    }, 50);
  }

  function showLoadError(kind) {
    var el = loadingElement();
    if (!el) return;
    var key = kind === 'timeout' ? 'editor.univer.load_timeout' : 'editor.univer.load_failed';
    var icon = kind === 'timeout' ? 'fa-clock text-amber-500' : 'fa-circle-exclamation text-red-500';
    el.style.display = 'flex';
    el.innerHTML = '<div class="text-center"><i class="fa-solid ' + icon + ' text-2xl mb-2"></i><p class="text-sm text-slate-500">' + window.__(key) + '</p><button type="button" onclick="BookStarkEditor.retryLoadUniver()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
  }

  function flushCallbacks() {
    var queued = callbacks.slice();
    callbacks.length = 0;
    queued.forEach(function(callback) {
      try { callback(); } catch (error) { console.error(error); }
    });
  }

  function loadAssets(callback) {
    if (loaded && window.UniverBookStark) {
      if (callback) callback();
      return;
    }
    if (callback) callbacks.push(callback);
    if (loading) return;
    loading = true;

    var css = document.createElement('link');
    css.rel = 'stylesheet';
    css.href = versionedAsset('/static/js/univer/univer.css', window.__univerCssVer__);
    css.setAttribute('data-univer', 'css');
    document.head.appendChild(css);

    var settled = false;
    var timeout = setTimeout(function() {
      if (settled) return;
      loading = false;
      showLoadError('timeout');
    }, 20000);
    var script = document.createElement('script');
    script.src = versionedAsset('/static/js/univer/univer.js', window.__univerJsVer__);
    script.setAttribute('data-univer', 'js');
    script.onload = function() {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      loaded = !!window.UniverBookStark;
      loading = false;
      if (loaded) flushCallbacks();
      else showLoadError('failed');
    };
    script.onerror = function() {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      loading = false;
      showLoadError('failed');
    };
    document.head.appendChild(script);
  }

  function createEmptyWorksheet(sheetId, name) {
    return {
      id: sheetId,
      name: name || 'Sheet1',
      tabColor: '',
      hidden: 0,
      rowCount: 1000,
      columnCount: 26,
      zoomRatio: 1,
      freeze: { startRow: -1, startColumn: -1, ySplit: 0, xSplit: 0 },
      scrollTop: 0,
      scrollLeft: 0,
      defaultColumnWidth: 73,
      defaultRowHeight: 23,
      mergeData: [],
      cellData: {},
      rowData: {},
      columnData: {},
      showGridlines: 1,
      rightToLeft: 0
    };
  }

  function createEmptyWorkbook() {
    var id = 'bookstark-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
    var sheetId = id + '-sheet-01';
    var sheets = {};
    sheets[sheetId] = createEmptyWorksheet(sheetId, 'Sheet1');
    return {
      id: id,
      name: '',
      appVersion: '0.25.1',
      locale: document.documentElement.lang === 'en' ? 'enUS' : 'zhCN',
      styles: {},
      sheetOrder: [sheetId],
      sheets: sheets
    };
  }

  function normalizeData(data) {
    var parsed = data;
    if (typeof parsed === 'string') {
      try { parsed = JSON.parse(parsed); } catch (error) { parsed = null; }
    }
    if (parsed && Array.isArray(parsed.sheetOrder) && parsed.sheets && typeof parsed.sheets === 'object') {
      return parsed;
    }
    return createEmptyWorkbook();
  }

  function stableSnapshot(snapshot) {
    if (!snapshot) return '';
    var clone = JSON.parse(JSON.stringify(snapshot));
    Object.keys(clone.sheets || {}).forEach(function(id) {
      var sheet = clone.sheets[id];
      delete sheet.scrollLeft;
      delete sheet.scrollTop;
    });
    return JSON.stringify(clone);
  }

  function getSnapshot() {
    if (!workbook || !workbook.save) return null;
    try { return workbook.save(); } catch (error) {
      console.warn('Unable to save Univer workbook:', error);
      return null;
    }
  }

  function dispose() {
    if (renderReadyTimer) clearInterval(renderReadyTimer);
    renderReadyTimer = null;
    if (themeObserver) themeObserver.disconnect();
    themeObserver = null;
    if (univer && univer.dispose) {
      try { univer.dispose(); } catch (error) { console.warn(error); }
    }
    univer = null;
    univerAPI = null;
    workbook = null;
    running = false;
    dirty = false;
    baseline = '';
    var container = lastContainerId && document.getElementById(lastContainerId);
    if (container) container.innerHTML = '';
  }

  function init(containerId, data, options) {
    var sdk = window.UniverBookStark;
    var container = document.getElementById(containerId);
    if (!sdk || !container) return null;
    dispose();
    lastContainerId = containerId;
    lastReadonly = !!(options && options.readonly);
    var preserveDirty = !!(options && options.preserveDirty);
    container.innerHTML = '';
    container.style.visibility = 'hidden';

    var english = document.documentElement.lang === 'en';
    var locale = english ? sdk.LocaleType.EN_US : sdk.LocaleType.ZH_CN;
    var coreLocale = english ? sdk.sheetsCoreEnUS : sdk.sheetsCoreZhCN;
    var conditionalFormattingLocale = english ? sdk.sheetsConditionalFormattingEnUS : sdk.sheetsConditionalFormattingZhCN;
    var dataValidationLocale = english ? sdk.sheetsDataValidationEnUS : sdk.sheetsDataValidationZhCN;
    var drawingLocale = english ? sdk.sheetsDrawingEnUS : sdk.sheetsDrawingZhCN;
    var filterLocale = english ? sdk.sheetsFilterEnUS : sdk.sheetsFilterZhCN;
    var findReplaceLocale = english ? sdk.sheetsFindReplaceEnUS : sdk.sheetsFindReplaceZhCN;
    var hyperLinkLocale = english ? sdk.sheetsHyperLinkEnUS : sdk.sheetsHyperLinkZhCN;
    var noteLocale = english ? sdk.sheetsNoteEnUS : sdk.sheetsNoteZhCN;
    var sortLocale = english ? sdk.sheetsSortEnUS : sdk.sheetsSortZhCN;
    var tableLocale = english ? sdk.sheetsTableEnUS : sdk.sheetsTableZhCN;
    var locales = {};
    locales[locale] = sdk.mergeLocales(
      coreLocale,
      conditionalFormattingLocale,
      dataValidationLocale,
      drawingLocale,
      filterLocale,
      findReplaceLocale,
      hyperLinkLocale,
      noteLocale,
      sortLocale,
      tableLocale
    );
    var result = sdk.createUniver({
      locale: locale,
      locales: locales,
      darkMode: document.documentElement.getAttribute('data-theme') === 'dark',
      presets: [
        sdk.UniverSheetsCorePreset({
          container: containerId,
          header: !lastReadonly,
          toolbar: !lastReadonly,
          formulaBar: !lastReadonly,
          footer: true,
          contextMenu: !lastReadonly,
          disableAutoFocus: true
        }),
        sdk.UniverSheetsConditionalFormattingPreset(),
        sdk.UniverSheetsDataValidationPreset({
          showEditOnDropdown: true,
          showSearchOnDropdown: true
        }),
        sdk.UniverSheetsFilterPreset(),
        sdk.UniverSheetsFindReplacePreset(),
        sdk.UniverSheetsHyperLinkPreset(),
        sdk.UniverSheetsNotePreset(),
        sdk.UniverSheetsSortPreset(),
        sdk.UniverSheetsTablePreset(),
        sdk.BookStarkSheetsDrawingPreset({ allowImageSize: 5 * 1024 * 1024 })
      ]
    });
    univer = result.univer;
    univerAPI = result.univerAPI;
    var normalized = normalizeData(data);
    workbook = univerAPI.createWorkbook(normalized);
    if (workbook && workbook.setEditable) workbook.setEditable(!lastReadonly);
    baseline = stableSnapshot(getSnapshot());
    dirty = preserveDirty;
    running = true;

    themeObserver = new MutationObserver(function(records) {
      var changed = records.some(function(record) { return record.attributeName === 'data-theme'; });
      if (!changed || !running) return;
      var snapshot = getSnapshot();
      var wasDirty = isDirty();
      init(containerId, snapshot, { readonly: lastReadonly, preserveDirty: wasDirty });
    });
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    revealWhenRendered(container);
    return workbook;
  }

  function applyReadonly(readonly) {
    if (!running || lastReadonly === !!readonly) return;
    var snapshot = getSnapshot();
    var wasDirty = isDirty();
    init(lastContainerId, snapshot, { readonly: !!readonly, preserveDirty: wasDirty });
  }

  function getContent() {
    var snapshot = getSnapshot();
    return snapshot ? JSON.stringify(snapshot) : null;
  }

  function isDirty() {
    if (!running) return dirty;
    return dirty || stableSnapshot(getSnapshot()) !== baseline;
  }

  function setDirty(value) {
    dirty = !!value;
    if (!dirty) baseline = stableSnapshot(getSnapshot());
  }

  function loadData(data, options) {
    loadAssets(function() {
      if (window.BookStarkEditor && BookStarkEditor._loadAborted) {
        BookStarkEditor._loadAborted = false;
        return;
      }
      init('univer-sheet', data, options || {});
    });
  }

  function retry() {
    loaded = false;
    loading = false;
    document.querySelectorAll('[data-univer]').forEach(function(element) { element.remove(); });
    var el = loadingElement();
    if (el) {
      el.style.display = 'flex';
      el.innerHTML = '<span class="text-slate-500" style="font-size:14px;">' + window.__('editor.univer.loading') + '</span>';
    }
    loadAssets();
  }

  window.BookStarkUniverAdapter = {
    loadAssets: loadAssets,
    init: init,
    destroy: dispose,
    applyReadonly: applyReadonly,
    getContent: getContent,
    isDirty: isDirty,
    setDirty: setDirty,
    loadData: loadData,
    retry: retry,
    normalizeData: normalizeData,
    get running() { return running; }
  };
})();
