// Markdown composer — wraps CodeMirror 6 with a textarea-like API.
// Depends on global window.CMHtml (provided by static/js/codemirror-html.min.js).
// Falls back to a plain <textarea> when CMHtml is not loaded.
(function(global) {
  function create(host, options) {
    if (!host) return null;
    options = options || {};
    var _value = options.value || '';
    var _onChange = options.onChange;
    var _onPasteFile = options.onPasteFile;
    var _onSubmit = options.onSubmit;
    var _placeholderText = options.placeholder || '';

    function _handleClipboardImage(items) {
      if (!_onPasteFile || !items) return false;
      for (var i = 0; i < items.length; i++) {
        if (items[i].type && items[i].type.indexOf('image/') === 0) {
          var f = items[i].getAsFile();
          if (f) { _onPasteFile(f); return true; }
        }
      }
      return false;
    }

    function _textareaCaretRect(textarea, pos) {
      var div = document.createElement('div');
      var style = getComputedStyle(textarea);
      var props = [
        'boxSizing', 'width', 'height', 'overflowX', 'overflowY', 'borderTopWidth',
        'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'paddingTop',
        'paddingRight', 'paddingBottom', 'paddingLeft', 'fontStyle', 'fontVariant',
        'fontWeight', 'fontStretch', 'fontSize', 'fontSizeAdjust', 'lineHeight',
        'fontFamily', 'textAlign', 'textTransform', 'textIndent', 'textDecoration',
        'letterSpacing', 'wordSpacing', 'tabSize', 'MozTabSize'
      ];
      div.style.position = 'absolute';
      div.style.visibility = 'hidden';
      div.style.whiteSpace = 'pre-wrap';
      div.style.wordWrap = 'break-word';
      div.style.top = '0';
      div.style.left = '-9999px';
      props.forEach(function(p) { div.style[p] = style[p]; });
      div.textContent = textarea.value.substring(0, pos);
      var span = document.createElement('span');
      span.textContent = textarea.value.substring(pos) || '.';
      div.appendChild(span);
      document.body.appendChild(div);
      var taRect = textarea.getBoundingClientRect();
      var spanRect = span.getBoundingClientRect();
      var divRect = div.getBoundingClientRect();
      var rect = {
        left: taRect.left + (spanRect.left - divRect.left) - textarea.scrollLeft,
        right: taRect.left + (spanRect.left - divRect.left) - textarea.scrollLeft,
        top: taRect.top + (spanRect.top - divRect.top) - textarea.scrollTop,
        bottom: taRect.top + (spanRect.top - divRect.top) - textarea.scrollTop + (parseFloat(style.lineHeight) || 22),
        height: parseFloat(style.lineHeight) || 22
      };
      document.body.removeChild(div);
      return rect;
    }

    if (typeof global.CMHtml === 'undefined') {
      host.innerHTML = '';
      var ta = document.createElement('textarea');
      ta.className = 'md-composer-fallback';
      ta.placeholder = _placeholderText;
      ta.value = _value;
      if (options.ariaLabel) ta.setAttribute('aria-label', options.ariaLabel);
      if (options.minHeight) ta.style.minHeight = options.minHeight + 'px';
      host.appendChild(ta);
      ta.addEventListener('input', function() {
        _value = ta.value;
        if (_onChange) _onChange(_value);
      });
      ta.addEventListener('paste', function(e) {
        var items = (e.clipboardData || {}).items;
        if (_handleClipboardImage(items)) e.preventDefault();
      });
      ta.addEventListener('keydown', function(e) {
        if (e.key === 'Tab') {
          e.preventDefault();
          var s = ta.selectionStart, en = ta.selectionEnd;
          ta.value = ta.value.substring(0, s) + '\t' + ta.value.substring(en);
          ta.selectionStart = ta.selectionEnd = s + 1;
        }
        if (options.submitOnCtrlEnter && (e.ctrlKey || e.metaKey) && e.key === 'Enter') {
          e.preventDefault();
          if (_onSubmit) _onSubmit();
        }
      });
      return {
        isCM: false,
        getValue: function() { return ta.value; },
        setValue: function(v) {
          var s = v == null ? '' : String(v);
          ta.value = s; _value = s;
        },
        insertAtCursor: function(text) {
          var s = ta.selectionStart, en = ta.selectionEnd, val = ta.value;
          ta.value = val.substring(0, s) + text + val.substring(en);
          ta.selectionStart = ta.selectionEnd = s + text.length;
          ta.focus();
          ta.dispatchEvent(new Event('input', { bubbles: true }));
        },
        getSelectionRange: function() {
          return { from: ta.selectionStart || 0, to: ta.selectionEnd || 0 };
        },
        getSelectedText: function() {
          var s = ta.selectionStart || 0, en = ta.selectionEnd || 0;
          return ta.value.substring(s, en);
        },
        selectRange: function(from, to) {
          from = Math.max(0, Math.min(ta.value.length, from || 0));
          to = Math.max(from, Math.min(ta.value.length, to == null ? from : to));
          ta.selectionStart = from;
          ta.selectionEnd = to;
          ta.focus();
        },
        replaceRange: function(from, to, text) {
          var insert = text == null ? '' : String(text);
          from = Math.max(0, Math.min(ta.value.length, from || 0));
          to = Math.max(from, Math.min(ta.value.length, to == null ? from : to));
          ta.value = ta.value.substring(0, from) + insert + ta.value.substring(to);
          var pos = from + insert.length;
          ta.selectionStart = ta.selectionEnd = pos;
          _value = ta.value;
          ta.focus();
          ta.dispatchEvent(new Event('input', { bubbles: true }));
          return pos;
        },
        getRangeRect: function(from, to) {
          from = from == null ? (ta.selectionStart || 0) : from;
          to = to == null ? (ta.selectionEnd || from) : to;
          var a = _textareaCaretRect(ta, from);
          var b = _textareaCaretRect(ta, to);
          return {
            left: (a.left + b.left) / 2,
            right: (a.right + b.right) / 2,
            top: Math.min(a.top, b.top),
            bottom: Math.max(a.bottom, b.bottom),
            height: Math.max(a.height, b.height)
          };
        },
        focus: function() { ta.focus(); },
        clear: function() { ta.value = ''; _value = ''; if (_onChange) _onChange(''); },
        getEl: function() { return ta; },
        destroy: function() { host.innerHTML = ''; }
      };
    }

    var CM = global.CMHtml;
    var _isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    host.innerHTML = '';
    var wrap = document.createElement('div');
    wrap.className = 'md-composer-cm';
    if (options.ariaLabel) wrap.setAttribute('aria-label', options.ariaLabel);
    host.appendChild(wrap);

    var minH = options.minHeight || 80;
    var maxH = options.maxHeight || 400;

    var theme = CM.EditorView.theme({
      '&': { fontSize: '14px', backgroundColor: 'transparent', color: 'var(--color-text)' },
      '.cm-editor': { backgroundColor: 'transparent' },
      '.cm-scroller': {
        fontFamily: "'PingFang SC','Helvetica Neue',Arial,'Microsoft YaHei','SF Mono','Fira Code',Consolas,monospace",
        lineHeight: '1.6',
        minHeight: minH + 'px',
        maxHeight: maxH + 'px',
        overflow: 'auto'
      },
      '.cm-content': { padding: '8px 0', caretColor: 'var(--color-text)' },
      '.cm-line': { padding: '0 12px' },
      '.cm-activeLine': { backgroundColor: 'transparent' },
      '.cm-focused .cm-activeLine': { backgroundColor: 'rgba(37,99,235,0.04)' },
      '.cm-cursor': { borderLeftColor: 'var(--color-text)' },
      '.cm-placeholder': { color: 'var(--color-gray-400)', fontStyle: 'normal' },
      '&.cm-focused': { outline: 'none' }
    }, { dark: _isDark });

    var changeListener = CM.EditorView.updateListener.of(function(u) {
      if (u.docChanged) {
        _value = u.state.doc.toString();
        if (_onChange) _onChange(_value);
      }
    });

    var domHandlers = CM.EditorView.domEventHandlers({
      paste: function(event) {
        var items = (event.clipboardData || {}).items;
        if (_handleClipboardImage(items)) {
          event.preventDefault();
          return true;
        }
        return false;
      }
    });

    var extensions = [
      CM.history(),
      CM.drawSelection(),
      CM.dropCursor(),
      CM.EditorState.allowMultipleSelections.of(true),
      CM.indentOnInput(),
      CM.syntaxHighlighting(CM.defaultHighlightStyle, { fallback: true }),
      CM.syntaxHighlighting(CM.mdHighlight),
      CM.bracketMatching(),
      CM.closeBrackets(),
      CM.autocompletion({ activateOnTyping: true }),
      CM.highlightSelectionMatches(),
      CM.markdown({ base: CM.markdownLanguage, addKeymap: false }),
      CM.placeholder(_placeholderText),
      CM.keymap.of([].concat(
        CM.closeBracketsKeymap,
        CM.defaultKeymap,
        CM.searchKeymap,
        CM.historyKeymap,
        CM.completionKeymap,
        [CM.indentWithTab]
      )),
      CM.EditorView.lineWrapping,
      theme,
      changeListener,
      domHandlers
    ];
    if (options.submitOnCtrlEnter) {
      extensions.push(CM.keymap.of([{
        key: 'Mod-Enter',
        run: function() { if (_onSubmit) { _onSubmit(); return true; } return false; }
      }]));
    }

    var state = CM.EditorState.create({ doc: _value, extensions: extensions });
    var view = new CM.EditorView({ state: state, parent: wrap });

    function _setValue(v) {
      var s = v == null ? '' : String(v);
      if (s === _value) return;
      _value = s;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: s } });
    }

    return {
      isCM: true,
      getValue: function() { return _value; },
      setValue: _setValue,
      insertAtCursor: function(text) {
        var sel = view.state.selection.main;
        view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: text },
          selection: { anchor: sel.from + text.length }
        });
        view.focus();
      },
      getSelectionRange: function() {
        var sel = view.state.selection.main;
        return { from: sel.from, to: sel.to };
      },
      getSelectedText: function() {
        var sel = view.state.selection.main;
        return view.state.doc.sliceString(sel.from, sel.to);
      },
      selectRange: function(from, to) {
        from = Math.max(0, Math.min(view.state.doc.length, from || 0));
        to = Math.max(from, Math.min(view.state.doc.length, to == null ? from : to));
        view.dispatch({ selection: { anchor: from, head: to } });
        view.focus();
      },
      replaceRange: function(from, to, text) {
        var insert = text == null ? '' : String(text);
        from = Math.max(0, Math.min(view.state.doc.length, from || 0));
        to = Math.max(from, Math.min(view.state.doc.length, to == null ? from : to));
        var pos = from + insert.length;
        view.dispatch({
          changes: { from: from, to: to, insert: insert },
          selection: { anchor: pos }
        });
        view.focus();
        return pos;
      },
      getRangeRect: function(from, to) {
        var sel = view.state.selection.main;
        from = from == null ? sel.from : from;
        to = to == null ? sel.to : to;
        var a = view.coordsAtPos(from);
        var b = view.coordsAtPos(to);
        if (!a && !b) {
          var wrapRect = wrap.getBoundingClientRect();
          return { left: wrapRect.left + 24, right: wrapRect.left + 24, top: wrapRect.top + 24, bottom: wrapRect.top + 46, height: 22 };
        }
        if (!a) a = b;
        if (!b) b = a;
        return {
          left: (a.left + b.left) / 2,
          right: (a.right + b.right) / 2,
          top: Math.min(a.top, b.top),
          bottom: Math.max(a.bottom, b.bottom),
          height: Math.max(a.bottom - a.top, b.bottom - b.top, 22)
        };
      },
      focus: function() { view.focus(); },
      clear: function() { _setValue(''); },
      getEl: function() { return wrap; },
      getView: function() { return view; },
      destroy: function() { try { view.destroy(); } catch(e) {} host.innerHTML = ''; }
    };
  }

  global.MarkdownComposer = { create: create };
})(window);
