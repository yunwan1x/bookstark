(function(global) {
  'use strict';

  var instance = null;
  var scrollLockKey = 'code-editor-modal';

  function t(key, fallback) {
    var value = typeof global.__ === 'function' ? global.__(key) : '';
    return value && value !== key ? value : fallback;
  }

  function escapeHTML(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(char) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char];
    });
  }

  function button(command, icon, key, fallback, keepOnMobile) {
    var label = t(key, fallback);
    return '<button class="code-editor-action" type="button" data-code-editor-command="' + command + '"' +
      (keepOnMobile ? ' data-mobile-editor-tool="keep"' : '') +
      ' aria-label="' + escapeHTML(label) + '" title="' + escapeHTML(label) + '">' +
      '<i class="fa-solid ' + icon + '"></i></button>';
  }

  function ensureModal() {
    var modal = document.getElementById('sharedCodeEditorModal');
    if (modal) return modal;
    modal = document.createElement('div');
    modal.id = 'sharedCodeEditorModal';
    modal.className = 'asset-modal-backdrop code-editor-backdrop';
    modal.setAttribute('aria-hidden', 'true');
    modal.innerHTML =
      '<section class="code-editor-window" role="dialog" aria-modal="true" aria-labelledby="sharedCodeEditorTitle">' +
        '<header class="code-editor-head">' +
          '<div class="code-editor-window-controls">' +
            '<button type="button" class="code-editor-window-dot red" data-code-editor-close aria-label="' + escapeHTML(t('asset.files.editor.close', '关闭')) + '"></button>' +
            '<span class="code-editor-window-dot yellow" aria-hidden="true"></span>' +
            '<button type="button" class="code-editor-window-dot green" data-code-editor-maximize aria-label="' + escapeHTML(t('asset.files.editor.maximize', '最大化')) + '"></button>' +
          '</div>' +
          '<div class="code-editor-titlebar">' +
            '<strong id="sharedCodeEditorTitle"></strong>' +
            '<span id="sharedCodeEditorSubtitle"></span>' +
          '</div>' +
          '<div class="code-editor-actions">' +
            button('undo', 'fa-rotate-left', 'asset.files.editor.undo', '撤销', true) +
            button('redo', 'fa-rotate-right', 'asset.files.editor.redo', '重做', true) +
            button('search', 'fa-magnifying-glass', 'asset.files.editor.search', '搜索', true) +
            button('replace', 'fa-magnifying-glass-arrow-right', 'asset.files.editor.replace', '替换') +
            button('prev', 'fa-arrow-up', 'asset.files.editor.prev', '上一个') +
            button('next', 'fa-arrow-down', 'asset.files.editor.next', '下一个') +
            button('select-matches', 'fa-object-group', 'asset.files.editor.select_matches', '选择全部匹配项') +
            button('goto-line', 'fa-arrow-right-to-bracket', 'asset.files.editor.goto_line', '跳转到行') +
            button('outdent', 'fa-outdent', 'asset.files.editor.outdent', '减少缩进') +
            button('indent', 'fa-indent', 'asset.files.editor.indent', '增加缩进') +
            button('fold', 'fa-compress', 'asset.files.editor.fold', '折叠代码') +
            button('unfold', 'fa-expand', 'asset.files.editor.unfold', '展开代码') +
            button('comment', 'fa-comment-slash', 'asset.files.editor.comment', '切换注释') +
            '<button class="code-editor-action" type="button" data-code-editor-save data-mobile-editor-tool="keep" aria-label="' +
              escapeHTML(t('asset.action.save', '保存')) + '" title="' + escapeHTML(t('asset.action.save', '保存')) + '"><i class="fa-solid fa-floppy-disk"></i></button>' +
            '<button class="code-editor-action" type="button" data-code-editor-maximize aria-label="' +
              escapeHTML(t('asset.files.editor.maximize', '最大化')) + '" title="' + escapeHTML(t('asset.files.editor.maximize', '最大化')) + '"><i class="fa-solid fa-up-right-and-down-left-from-center"></i></button>' +
            '<button class="code-editor-action" type="button" data-code-editor-close aria-label="' +
              escapeHTML(t('asset.files.editor.close', '关闭')) + '" title="' + escapeHTML(t('asset.files.editor.close', '关闭')) + '"><i class="fa-solid fa-xmark"></i></button>' +
          '</div>' +
        '</header>' +
        '<div class="code-editor-body" id="sharedCodeEditorPane"></div>' +
      '</section>';
    document.body.appendChild(modal);
    modal.addEventListener('click', function(event) {
      var commandButton = event.target.closest('[data-code-editor-command]');
      if (commandButton) return runCommand(commandButton.dataset.codeEditorCommand);
      if (event.target.closest('[data-code-editor-retry]')) return retryLoad();
      if (event.target.closest('[data-code-editor-state-close]')) return close();
      if (event.target.closest('[data-code-editor-save]')) return save();
      if (event.target.closest('[data-code-editor-maximize]')) return toggleMaximized();
      if (event.target.closest('[data-code-editor-close]')) close();
    });
    return modal;
  }

  function editorLanguage(CM, fileName) {
    var ext = String(fileName || '').split('.').pop().toLowerCase();
    if (['html', 'htm', 'xml', 'svg'].indexOf(ext) >= 0 && CM.html) {
      return CM.html({ autoCloseTags: true, matchClosingTags: true, selfClosingTags: true });
    }
    if (['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'json'].indexOf(ext) >= 0 && CM.javascript) return CM.javascript();
    if (['css', 'scss', 'less'].indexOf(ext) >= 0 && CM.css) return CM.css();
    if (['md', 'markdown'].indexOf(ext) >= 0 && CM.markdown) return CM.markdown();
    return CM.markdown ? CM.markdown() : [];
  }

  function createEditor(content, fileName) {
    var pane = document.getElementById('sharedCodeEditorPane');
    if (!global.CMHtml) {
      pane.innerHTML = '<textarea class="code-editor-textarea" spellcheck="false"></textarea>';
      instance.textarea = pane.querySelector('textarea');
      instance.textarea.value = content || '';
      instance.textarea.focus();
      return;
    }
    pane.innerHTML = '';
    var CM = global.CMHtml;
    var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    var theme = CM.EditorView.theme({
      '&': { height: '100%', fontSize: '13px', backgroundColor: 'var(--color-bg-card)', color: 'var(--color-text)' },
      '.cm-scroller': { fontFamily: "'SF Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.55', overflow: 'auto' },
      '.cm-content': { padding: '14px 0' },
      '.cm-gutters': { backgroundColor: 'transparent', color: 'var(--color-gray-400)', border: 'none' },
      '.cm-activeLine': { backgroundColor: 'rgba(37,99,235,0.06)' },
      '.cm-activeLineGutter': { backgroundColor: 'transparent' },
      '&.cm-focused': { outline: 'none' }
    }, { dark: isDark });
    var saveBinding = {
      key: 'Mod-s',
      preventDefault: true,
      run: function() {
        save();
        return true;
      }
    };
    var extensions = [
      CM.lineNumbers(),
      CM.highlightActiveLineGutter(),
      CM.highlightSpecialChars(),
      CM.history(),
      CM.foldGutter(),
      CM.drawSelection(),
      CM.dropCursor(),
      CM.EditorState.allowMultipleSelections.of(true),
      CM.indentOnInput(),
      CM.syntaxHighlighting(CM.defaultHighlightStyle, { fallback: true }),
      CM.bracketMatching(),
      CM.closeBrackets(),
      CM.autocompletion(),
      CM.rectangularSelection(),
      CM.crosshairCursor(),
      CM.highlightActiveLine(),
      CM.highlightSelectionMatches(),
      editorLanguage(CM, fileName),
      CM.keymap.of([].concat(
        [saveBinding],
        CM.closeBracketsKeymap,
        CM.defaultKeymap,
        CM.searchKeymap,
        CM.historyKeymap,
        CM.foldKeymap,
        CM.completionKeymap,
        [CM.indentWithTab]
      )),
      CM.EditorView.lineWrapping,
      theme
    ];
    var state = CM.EditorState.create({ doc: content || '', extensions: extensions });
    instance.view = new CM.EditorView({ state: state, parent: pane });
    instance.view.focus();
  }

  function destroyEditor() {
    if (!instance) return;
    if (instance.view) {
      try { instance.view.destroy(); } catch (error) {}
    }
    instance.view = null;
    instance.textarea = null;
    var pane = document.getElementById('sharedCodeEditorPane');
    if (pane) pane.innerHTML = '';
  }

  function getValue() {
    if (!instance) return '';
    if (instance.view) return instance.view.state.doc.toString();
    if (instance.textarea) return instance.textarea.value;
    return '';
  }

  function setSubtitle(value) {
    var subtitle = document.getElementById('sharedCodeEditorSubtitle');
    if (subtitle) subtitle.textContent = value || '';
  }

  function setBusy(busy) {
    if (!instance) return;
    instance.saving = busy;
    syncActionAvailability();
  }

  function syncActionAvailability() {
    if (!instance) return;
    var unavailable = instance.saving || instance.loading || instance.loadError;
    ensureModal().querySelectorAll('[data-code-editor-command], [data-code-editor-save]').forEach(function(button) {
      button.disabled = unavailable;
    });
  }

  function renderLoading(message) {
    var pane = document.getElementById('sharedCodeEditorPane');
    if (!pane) return;
    pane.innerHTML =
      '<div class="code-editor-state code-editor-loading" role="status" aria-live="polite">' +
        '<span class="code-editor-spinner" aria-hidden="true"></span>' +
        '<strong>' + escapeHTML(message || t('asset.files.editor.loading', '加载中')) + '</strong>' +
      '</div>';
  }

  function setLoading(loading, message) {
    if (!instance) return api;
    instance.loading = !!loading;
    instance.loadError = false;
    instance.retryLoad = null;
    if (loading) {
      destroyEditor();
      renderLoading(message || instance.options.loadingText);
    }
    syncActionAvailability();
    return api;
  }

  function setContent(content, fileName) {
    if (!instance) return api;
    instance.loading = false;
    instance.loadError = false;
    instance.retryLoad = null;
    destroyEditor();
    setSubtitle(instance.options.subtitle || '');
    createEditor(content || '', fileName || instance.options.fileName || instance.options.title || '');
    syncActionAvailability();
    return api;
  }

  function showLoadError(error, retry) {
    if (!instance) return api;
    instance.loading = false;
    instance.loadError = true;
    instance.retryLoad = typeof retry === 'function' ? retry : null;
    destroyEditor();
    var pane = document.getElementById('sharedCodeEditorPane');
    var message = error && error.message ? error.message : String(error || '');
    pane.innerHTML =
      '<div class="code-editor-state code-editor-load-error" role="alert">' +
        '<span class="code-editor-state-icon" aria-hidden="true"><i class="fa-solid fa-triangle-exclamation"></i></span>' +
        '<strong>' + escapeHTML(t('asset.files.editor.load_error', '文件读取失败')) + '</strong>' +
        (message ? '<p>' + escapeHTML(message) + '</p>' : '') +
        '<div class="code-editor-state-actions">' +
          (instance.retryLoad ? '<button type="button" class="bs-btn bs-btn-primary" data-code-editor-retry><i class="fa-solid fa-rotate-right"></i><span>' +
            escapeHTML(t('asset.files.editor.retry', '重试')) + '</span></button>' : '') +
          '<button type="button" class="bs-btn bs-btn-cancel" data-code-editor-state-close>' +
            escapeHTML(t('common.close', '关闭')) + '</button>' +
        '</div>' +
      '</div>';
    syncActionAvailability();
    return api;
  }

  function retryLoad() {
    if (!instance || typeof instance.retryLoad !== 'function') return;
    var retry = instance.retryLoad;
    retry();
  }

  function notifyUnavailable() {
    if (instance && typeof instance.options.onCommandUnavailable === 'function') {
      instance.options.onCommandUnavailable();
    }
  }

  function save() {
    if (!instance || instance.saving || instance.loading || instance.loadError || typeof instance.options.onSave !== 'function') return;
    var active = instance;
    setBusy(true);
    if (active.options.savingSubtitle) setSubtitle(active.options.savingSubtitle);
    var saveResult;
    try {
      saveResult = active.options.onSave(getValue(), api);
    } catch (error) {
      saveResult = Promise.reject(error);
    }
    Promise.resolve(saveResult).then(function() {
      if (instance !== active) return;
      if (typeof active.options.onSaved === 'function') active.options.onSaved();
      if (active.options.closeOnSave) close();
      else setSubtitle(active.options.subtitle || '');
    }).catch(function(error) {
      if (instance !== active) return;
      setSubtitle(active.options.errorSubtitle || active.options.subtitle || '');
      if (typeof active.options.onError === 'function') active.options.onError(error);
    }).finally(function() {
      if (instance === active) setBusy(false);
    });
  }

  function runCommand(command) {
    if (!instance || instance.loading || instance.loadError) return;
    if (instance.view) {
      if (!runCMCommand(command)) notifyUnavailable();
      return;
    }
    var textarea = instance.textarea;
    if (!textarea) return;
    textarea.focus();
    if (command === 'undo' || command === 'redo') {
      try { document.execCommand(command); } catch (error) {}
      return;
    }
    if (command === 'indent') {
      var start = textarea.selectionStart || 0;
      var end = textarea.selectionEnd || 0;
      textarea.value = textarea.value.slice(0, start) + '  ' + textarea.value.slice(end);
      textarea.selectionStart = textarea.selectionEnd = start + 2;
      return;
    }
    notifyUnavailable();
  }

  function runCMCommand(command) {
    var CM = global.CMHtml;
    var view = instance && instance.view;
    if (!CM || !view) return false;
    view.focus();
    if (command === 'replace') {
      var opened = runCMKey(CM.searchKeymap, 'Mod-f', false, view);
      global.setTimeout(function() {
        var replace = document.querySelector('#sharedCodeEditorPane .cm-search input[name="replace"]');
        if (replace) {
          replace.focus();
          replace.select();
        }
      }, 30);
      return opened;
    }
    var commandMap = {
      undo: [CM.historyKeymap, 'Mod-z', false],
      redo: [CM.historyKeymap, 'Mod-y', false],
      search: [CM.searchKeymap, 'Mod-f', false],
      next: [CM.searchKeymap, 'Mod-g', false],
      prev: [CM.searchKeymap, 'Mod-g', true],
      'select-matches': [CM.searchKeymap, 'Mod-Shift-l', false],
      'goto-line': [CM.searchKeymap, 'Mod-Alt-g', false],
      outdent: [CM.defaultKeymap, 'Mod-[', false],
      indent: [CM.defaultKeymap, 'Mod-]', false],
      fold: [CM.foldKeymap, 'Ctrl-Shift-[', false],
      unfold: [CM.foldKeymap, 'Ctrl-Shift-]', false],
      comment: [CM.defaultKeymap, 'Mod-/', false]
    };
    var spec = commandMap[command];
    return !!(spec && runCMKey(spec[0], spec[1], spec[2], view));
  }

  function runCMKey(keymap, key, shift, view) {
    if (!Array.isArray(keymap)) return false;
    for (var i = 0; i < keymap.length; i++) {
      var binding = keymap[i];
      if (binding.key !== key && binding.mac !== key && binding.linux !== key) continue;
      var fn = shift && binding.shift ? binding.shift : binding.run;
      if (typeof fn === 'function') return !!fn(view);
    }
    return false;
  }

  function toggleMaximized() {
    if (!instance) return;
    instance.maximized = !instance.maximized;
    ensureModal().querySelector('.code-editor-window').classList.toggle('maximized', instance.maximized);
    if (instance.view) global.requestAnimationFrame(function() { instance.view.requestMeasure(); });
  }

  function open(options) {
    close();
    options = options || {};
    var modal = ensureModal();
    instance = {
      options: options,
      returnFocus: document.activeElement,
      view: null,
      textarea: null,
      saving: false,
      loading: !!options.loading,
      loadError: false,
      retryLoad: null,
      maximized: false
    };
    document.getElementById('sharedCodeEditorTitle').textContent = options.title || t('asset.files.editor.title', '文本编辑');
    setSubtitle(options.subtitle || '');
    modal.classList.add('open');
    modal.setAttribute('aria-hidden', 'false');
    if (global.BookStarkScrollLock) global.BookStarkScrollLock.lock(scrollLockKey);
    else document.body.style.overflow = 'hidden';
    if (instance.loading) {
      renderLoading(options.loadingText);
      syncActionAvailability();
    } else {
      createEditor(options.content || '', options.fileName || options.title || '');
    }
    return api;
  }

  function close() {
    if (!instance) return;
    var active = instance;
    instance = null;
    if (active.view) {
      try { active.view.destroy(); } catch (error) {}
    }
    var pane = document.getElementById('sharedCodeEditorPane');
    if (pane) pane.innerHTML = '';
    var modal = document.getElementById('sharedCodeEditorModal');
    if (modal) {
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden', 'true');
      var win = modal.querySelector('.code-editor-window');
      if (win) win.classList.remove('maximized');
    }
    if (global.BookStarkScrollLock) global.BookStarkScrollLock.unlock(scrollLockKey);
    else document.body.style.overflow = '';
    if (typeof active.options.onClose === 'function') active.options.onClose();
    if (active.returnFocus && active.returnFocus.isConnected) active.returnFocus.focus();
  }

  document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && instance) {
      event.preventDefault();
      close();
    }
  });

  var api = {
    open: open,
    close: close,
    save: save,
    getValue: getValue,
    setSubtitle: setSubtitle,
    setLoading: setLoading,
    setContent: setContent,
    showLoadError: showLoadError,
    isOpen: function() { return !!instance; }
  };
  global.BookStarkCodeEditorModal = api;
})(window);
