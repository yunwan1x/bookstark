(function() {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function toast(message, type) {
    if (window.BSDialog && BSDialog.toast) BSDialog.toast(message, type || 'info');
  }

  function renderMarkdown(el, text) {
    if (!el) return;
    el.classList.add('note-content');
    if (typeof marked !== 'undefined' && marked.parse) {
      el.innerHTML = marked.parse(String(text || ''));
    } else {
      el.textContent = String(text || '');
    }
  }

  function snapshotFloatStyle(root) {
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

  function applyFloatStyle(root, snapshot) {
    var props = ['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'];
    props.forEach(function(prop) {
      var item = snapshot && snapshot[prop];
      if (item && item.value) root.style.setProperty(prop, item.value, item.priority || '');
      else root.style.removeProperty(prop);
    });
  }

  function clearFloatBoxStyle(root) {
    ['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'].forEach(function(prop) {
      root.style.removeProperty(prop);
    });
  }

  function makeDraggable(root, handleSelector) {
    var header = root.querySelector(handleSelector || '.preview-ai-header');
    if (!header) return null;
    var startX = 0;
    var startY = 0;
    var startLeft = 0;
    var startTop = 0;
    var dragging = false;

    function isMobile() {
      return window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
    }

    function clampPosition(left, top) {
      var rect = root.getBoundingClientRect();
      var maxLeft = Math.max(8, window.innerWidth - rect.width - 8);
      var maxTop = Math.max(8, window.innerHeight - rect.height - 8);
      return {
        left: Math.max(8, Math.min(maxLeft, left)),
        top: Math.max(8, Math.min(maxTop, top))
      };
    }

    function onPointerDown(e) {
      if (isMobile()) return;
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
    }

    function onPointerMove(e) {
      if (!dragging) return;
      var pos = clampPosition(startLeft + e.clientX - startX, startTop + e.clientY - startY);
      root.style.setProperty('left', pos.left + 'px', 'important');
      root.style.setProperty('top', pos.top + 'px', 'important');
      root.style.setProperty('right', 'auto', 'important');
      root.style.setProperty('bottom', 'auto', 'important');
      root.style.setProperty('transform', 'none', 'important');
    }

    function endDrag(e) {
      if (!dragging) return;
      dragging = false;
      root.classList.remove('drawing-ai-dragging');
      try { header.releasePointerCapture(e.pointerId); } catch(err) {}
    }

    function onResize() {
      if (isMobile()) return;
      var rect = root.getBoundingClientRect();
      var pos = clampPosition(rect.left, rect.top);
      root.style.setProperty('left', pos.left + 'px', 'important');
      root.style.setProperty('top', pos.top + 'px', 'important');
      root.style.setProperty('right', 'auto', 'important');
      root.style.setProperty('bottom', 'auto', 'important');
      root.style.setProperty('transform', 'none', 'important');
    }

    header.addEventListener('pointerdown', onPointerDown);
    header.addEventListener('pointermove', onPointerMove);
    header.addEventListener('pointerup', endDrag);
    header.addEventListener('pointercancel', endDrag);
    window.addEventListener('resize', onResize);

    return function() {
      header.removeEventListener('pointerdown', onPointerDown);
      header.removeEventListener('pointermove', onPointerMove);
      header.removeEventListener('pointerup', endDrag);
      header.removeEventListener('pointercancel', endDrag);
      window.removeEventListener('resize', onResize);
    };
  }

  function copyMessage(btn) {
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

  function create(config) {
    config = config || {};
    var state = {
      panel: null,
      ctrl: null,
      contextText: '',
      contextKind: '',
      contextRange: null,
      cleanupDrag: null,
      cleanupSelection: null,
      cleanupViewport: null
    };

    function isMobile() {
      return window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
    }

    function syncViewportHeight() {
      var panel = state.panel;
      if (!panel || !document.body.contains(panel)) return;
      var vv = window.visualViewport;
      var height = vv && vv.height ? vv.height : (window.innerHeight || document.documentElement.clientHeight || 0);
      if (height > 0) panel.style.setProperty('--preview-ai-viewport-height', Math.round(height) + 'px');
      if (isMobile()) {
        panel.style.left = '';
        panel.style.right = '';
        panel.style.top = '';
        panel.style.bottom = '';
      }
    }

    function bindViewportSync() {
      syncViewportHeight();
      var visualViewport = window.visualViewport;
      if (visualViewport && visualViewport.addEventListener) {
        visualViewport.addEventListener('resize', syncViewportHeight);
        visualViewport.addEventListener('scroll', syncViewportHeight);
      }
      window.addEventListener('resize', syncViewportHeight);
      return function() {
        if (visualViewport && visualViewport.removeEventListener) {
          visualViewport.removeEventListener('resize', syncViewportHeight);
          visualViewport.removeEventListener('scroll', syncViewportHeight);
        }
        window.removeEventListener('resize', syncViewportHeight);
      };
    }

    function buildPrompt(userPrompt) {
      var label = config.contextLabel || '阅读上下文';
      var ctx = state.contextText || '';
      if (ctx) return '【' + label + '】\n' + ctx + '\n\n【问题】\n' + userPrompt;
      return userPrompt;
    }

    function actions() {
      if (typeof config.getActions === 'function') {
        return config.getActions({
          kind: state.contextKind,
          text: state.contextText,
          range: state.contextRange
        }) || [];
      }
      return [
        { label: '总结全文', prompt: '请总结全文，先给一句话结论，再列出 5 个核心要点。' },
        { label: '找漏洞', prompt: '请检查全文的逻辑漏洞、证据不足和表达含混之处。' },
        { label: '提问题', prompt: '请基于全文提出 8 个可以继续研究或写作的问题。' },
        { label: '给结论', prompt: '请提炼全文可以直接采用的结论和行动建议。' }
      ];
    }

    function renderSuggestions() {
      var panel = state.panel;
      if (!panel) return;
      var row = panel.querySelector('.preview-ai-suggestion-row');
      var list = actions();
      row.innerHTML = list.map(function(a, i) {
        return '<button type="button" class="preview-ai-suggestion" data-idx="' + i + '">' + esc(a.label) + '</button>';
      }).join('');
      Array.prototype.forEach.call(row.querySelectorAll('.preview-ai-suggestion'), function(btn) {
        btn.addEventListener('click', function() {
          var action = list[parseInt(btn.getAttribute('data-idx'), 10)];
          if (!action) return;
          var input = panel.querySelector('.preview-ai-input');
          input.value = action.prompt || '';
          input.focus();
        });
      });
    }

    function setContext(kind, text, range) {
      var panel = state.panel;
      if (!panel) return;
      text = String(text || '').trim();
      state.contextKind = text ? kind : '';
      state.contextText = text;
      state.contextRange = (kind === 'selection' && range) ? range : null;
      if (typeof config.onContextChange === 'function') {
        config.onContextChange({
          kind: state.contextKind,
          text: state.contextText,
          range: state.contextRange
        });
      }
      var badge = panel.querySelector('.preview-ai-context-badge');
      if (text) {
        if (kind === 'selection') {
          badge.innerHTML = '<button type="button" class="preview-ai-context-locator" title="定位到选区">选区</button> · ' + text.length + ' 字';
        } else {
          badge.textContent = (config.fullContextLabel || '全文') + ' · ' + text.length + ' 字';
        }
      } else {
        badge.textContent = config.emptyContextText || '未选择上下文';
      }
      renderSuggestions();
    }

    function setMaximized(panel, maximized, btn) {
      if (!panel) return;
      maximized = !!maximized;
      var toggleBtn = panel.querySelector('.preview-ai-toggle');
      if (maximized && panel.classList.contains('drawing-ai-collapsed')) setCollapsed(panel, false, toggleBtn);
      if (maximized && !panel.classList.contains('preview-ai-maximized')) {
        panel._previewAICompactStyle = snapshotFloatStyle(panel);
        clearFloatBoxStyle(panel);
      } else if (!maximized && panel._previewAICompactStyle) {
        applyFloatStyle(panel, panel._previewAICompactStyle);
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

    function setCollapsed(panel, collapsed, toggleBtn) {
      if (!panel) return;
      collapsed = !!collapsed;
      var maxBtn = panel.querySelector('.preview-ai-maximize');
      if (collapsed && panel.classList.contains('preview-ai-maximized')) setMaximized(panel, false, maxBtn);
      if (collapsed && !panel.classList.contains('drawing-ai-collapsed')) {
        panel._aiExpandedStyle = snapshotFloatStyle(panel);
        panel.style.removeProperty('width');
        panel.style.removeProperty('height');
      } else if (!collapsed && panel._aiExpandedStyle) {
        applyFloatStyle(panel, panel._aiExpandedStyle);
        panel._aiExpandedStyle = null;
      }
      panel.classList.toggle('drawing-ai-collapsed', collapsed);
      if (toggleBtn) {
        toggleBtn.setAttribute('aria-label', collapsed ? '展开' : '收起');
        toggleBtn.setAttribute('title', collapsed ? '展开' : '收起');
        toggleBtn.textContent = collapsed ? '□' : '_';
      }
    }

    function setRunning(on) {
      var panel = state.panel;
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

    function appendMessage(role, text) {
      var panel = state.panel;
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
        renderMarkdown(content, text || '');
      } else {
        msg.textContent = text || '';
      }
      list.appendChild(msg);
      list.scrollTop = list.scrollHeight;
      return msg;
    }

    function closeContextEditor(modal) {
      modal = modal || document.getElementById('previewAIContextEditorModal');
      if (modal && modal.parentNode) modal.parentNode.removeChild(modal);
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('preview-ai-context-editor');
    }

    function openContextEditor() {
      if (!config.openContextEditorOnFullClick && !config.allowContextEdit) return;
      var currentText = String(state.contextText || '').trim();
      if (!currentText) {
        toast(config.emptyFullContextToast || '当前没有可用内容', 'warning');
        return;
      }
      closeContextEditor();
      var modal = document.createElement('div');
      modal.id = 'previewAIContextEditorModal';
      modal.className = 'asset-modal-backdrop preview-ai-context-editor active';
      modal.setAttribute('role', 'dialog');
      modal.setAttribute('aria-modal', 'true');
      modal.setAttribute('aria-hidden', 'false');
      modal.style.zIndex = '10050';
      modal.innerHTML =
        '<div class="asset-modal asset-modal-wide preview-ai-context-editor-box" role="document">' +
          '<div class="asset-modal-head">' +
            '<h2 class="asset-modal-title">' + esc(config.contextEditorTitle || '编辑上下文') + '</h2>' +
            '<button type="button" class="asset-modal-close preview-ai-context-editor-close" aria-label="关闭" title="关闭"><i class="fa-solid fa-xmark"></i></button>' +
          '</div>' +
          '<div class="asset-modal-body">' +
            '<textarea class="dialog-input preview-ai-context-editor-textarea" rows="14" spellcheck="false"></textarea>' +
          '</div>' +
          '<div class="asset-modal-foot">' +
            '<button type="button" class="bs-btn bs-btn-primary preview-ai-context-editor-save">保存上下文</button>' +
          '</div>' +
        '</div>';
      document.body.appendChild(modal);
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('preview-ai-context-editor');
      var textarea = modal.querySelector('.preview-ai-context-editor-textarea');
      textarea.value = currentText;
      modal.addEventListener('click', function(e) {
        if (e.target === modal) closeContextEditor(modal);
      });
      modal.querySelector('.preview-ai-context-editor-close').addEventListener('click', function() {
        closeContextEditor(modal);
      });
      modal.querySelector('.preview-ai-context-editor-save').addEventListener('click', function() {
        var next = String(textarea.value || '').trim();
        if (!next) {
          toast('上下文不能为空', 'warning');
          textarea.focus();
          return;
        }
        setContext(state.contextKind || 'full', next, state.contextRange);
        closeContextEditor(modal);
      });
      setTimeout(function() {
        textarea.focus();
        textarea.setSelectionRange(textarea.value.length, textarea.value.length);
      }, 30);
    }

    function updateMessage(el, text) {
      if (!el) return;
      el.setAttribute('data-raw', text || '');
      var content = el.querySelector('.preview-ai-message-content') || el;
      renderMarkdown(content, text || '');
    }

    function send() {
      var panel = state.panel;
      if (!panel || typeof AIHelper === 'undefined') return;
      var input = panel.querySelector('.preview-ai-input');
      var prompt = String(input.value || '').trim();
      if (!prompt) {
        input.focus();
        return;
      }
      if (!state.contextText && typeof config.getSelection === 'function') {
        var sel = config.getSelection();
        if (sel) setContext(sel.kind || 'selection', sel.text, sel.range);
      }
      appendMessage('user', prompt);
      input.value = '';
      var aiMsg = appendMessage('ai', '思考中...');
      var systemPrompt = typeof config.getSystemPrompt === 'function'
        ? config.getSystemPrompt()
        : (config.systemPrompt || '');
      setRunning(true);
      var generated = '';
      state.ctrl = AIHelper.complete({
        messages: AIHelper.buildMessages(systemPrompt, buildPrompt(prompt)),
        scene: config.scene || 'reading_assistant',
        onChunk: function(_chunk, full) {
          generated = full || generated;
          updateMessage(aiMsg, generated || '思考中...');
          var list = panel.querySelector('.preview-ai-conversation');
          if (list) list.scrollTop = list.scrollHeight;
        },
        onDone: function(full) {
          state.ctrl = null;
          generated = full || generated;
          updateMessage(aiMsg, generated.trim() || '没有生成内容');
          setRunning(false);
        },
        onError: function(msg) {
          state.ctrl = null;
          aiMsg.textContent = msg || (window.__ ? window.__('note.ai.toast.error') : 'AI 调用失败') || 'AI 调用失败';
          aiMsg.classList.add('is-error');
          setRunning(false);
        }
      });
    }

    function bindSelectionSync() {
      if (typeof config.getSelection !== 'function') return null;
      var timer = null;
      function schedule() {
        if (timer) clearTimeout(timer);
        timer = setTimeout(function() {
          var panel = state.panel;
          if (!panel || !document.body.contains(panel)) return;
          var active = document.activeElement;
          if (active && panel.contains(active)) return;
          var sel = config.getSelection();
          if (sel) setContext(sel.kind || 'selection', sel.text, sel.range);
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

    function ensurePanel() {
      if (state.panel && document.body.contains(state.panel)) return state.panel;
      var title = config.title || '阅读助手';
      var panel = document.createElement('section');
      panel.className = 'preview-ai-panel';
      if (config.panelId) panel.id = config.panelId;
      panel.setAttribute('role', 'dialog');
      panel.setAttribute('aria-modal', 'false');
      panel.setAttribute('aria-label', title);
      panel.innerHTML =
        '<div class="preview-ai-header">' +
          '<div class="preview-ai-title"><i class="fa-solid fa-wand-magic-sparkles"></i><span>' + esc(title) + '</span></div>' +
          '<div class="preview-ai-window-actions">' +
            '<button type="button" class="preview-ai-maximize" aria-label="最大化" title="最大化" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
            '<button type="button" class="preview-ai-toggle" aria-label="收起" title="收起">_</button>' +
            '<button type="button" class="preview-ai-close" aria-label="关闭" title="关闭"><i class="fa-solid fa-xmark"></i></button>' +
          '</div>' +
        '</div>' +
        '<div class="preview-ai-context-strip">' +
          '<div class="preview-ai-context-actions">' +
            '<button type="button" class="preview-ai-chip" data-context="full">' + esc(config.fullButtonLabel || '全文') + '</button>' +
            '<button type="button" class="preview-ai-chip" data-context="clear">清空</button>' +
          '</div>' +
          '<span class="preview-ai-context-badge">' + esc(config.emptyContextText || '未选择上下文') + '</span>' +
        '</div>' +
        '<div class="preview-ai-conversation" aria-live="polite"></div>' +
        '<form class="preview-ai-composer">' +
          '<textarea class="preview-ai-input" rows="3" placeholder="' + esc(config.placeholder || '问一个和当前内容有关的问题...') + '"></textarea>' +
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
      panel.querySelector('.preview-ai-close').addEventListener('click', close);
      maxBtn.addEventListener('click', function() {
        setMaximized(panel, !panel.classList.contains('preview-ai-maximized'), maxBtn);
      });
      toggleBtn.addEventListener('click', function() {
        setCollapsed(panel, !panel.classList.contains('drawing-ai-collapsed'), toggleBtn);
      });
      panel.querySelector('[data-context="full"]').addEventListener('click', function() {
        var text = typeof config.getFullContext === 'function' ? config.getFullContext() : '';
        if (!String(text || '').trim()) {
          toast(config.emptyFullContextToast || '当前没有可用内容', 'warning');
          return;
        }
        setContext('full', text, null);
        if (config.openContextEditorOnFullClick) openContextEditor();
      });
      panel.querySelector('[data-context="clear"]').addEventListener('click', function() {
        if (typeof config.clearSelection === 'function') config.clearSelection();
        setContext('', '', null);
      });
      panel.querySelector('.preview-ai-context-badge').addEventListener('click', function(e) {
        if (e.target && e.target.closest && e.target.closest('.preview-ai-context-locator')) {
          if (typeof config.locateSelection === 'function') config.locateSelection(state.contextRange);
          return;
        }
        if (config.allowContextEdit || config.openContextEditorOnFullClick) openContextEditor();
      });
      panel.querySelector('.preview-ai-conversation').addEventListener('click', function(e) {
        var btn = e.target && e.target.closest ? e.target.closest('.preview-ai-copy') : null;
        if (btn) copyMessage(btn);
      });
      panel.querySelector('.preview-ai-composer').addEventListener('submit', function(e) {
        e.preventDefault();
        send();
      });
      panel.querySelector('.preview-ai-input').addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
          e.preventDefault();
          send();
        }
      });
      panel.querySelector('.preview-ai-stop').addEventListener('click', function() {
        if (state.ctrl) {
          try { state.ctrl.abort(); } catch(e) {}
          state.ctrl = null;
        }
        setRunning(false);
      });

      state.panel = panel;
      state.cleanupDrag = makeDraggable(panel, '.preview-ai-header');
      state.cleanupSelection = bindSelectionSync();
      state.cleanupViewport = bindViewportSync();
      return panel;
    }

    function open() {
      if (!window.AI_ENABLED && config.requireAIEnabled !== false) {
        toast(config.disabledToast || 'AI 功能未启用', 'warning');
        return null;
      }
      if (typeof AIHelper === 'undefined') {
        toast(config.disabledToast || 'AI 功能未启用', 'warning');
        return null;
      }
      if (typeof config.beforeOpen === 'function' && config.beforeOpen() === false) return null;
      var panel = ensurePanel();
      syncViewportHeight();
      panel.classList.add('open');
      syncViewportHeight();
      var initial = typeof config.getInitialContext === 'function' ? config.getInitialContext() : null;
      if (initial && String(initial.text || '').trim()) {
        setContext(initial.kind || 'full', initial.text, initial.range || null);
      } else if (!state.contextText && typeof config.getSelection === 'function') {
        var selected = config.getSelection();
        if (selected) setContext(selected.kind || 'selection', selected.text, selected.range);
        else setContext('', '', null);
      } else if (state.contextText) {
        setContext(state.contextKind, state.contextText, state.contextRange);
      } else {
        setContext('', '', null);
      }
      var input = panel.querySelector('.preview-ai-input');
      setTimeout(function() { if (input) input.focus(); }, 30);
      return panel;
    }

    function close() {
      if (state.ctrl) {
        try { state.ctrl.abort(); } catch(e) {}
        state.ctrl = null;
      }
      if (state.cleanupDrag) {
        try { state.cleanupDrag(); } catch(e) {}
        state.cleanupDrag = null;
      }
      if (state.cleanupSelection) {
        try { state.cleanupSelection(); } catch(e) {}
        state.cleanupSelection = null;
      }
      if (state.cleanupViewport) {
        try { state.cleanupViewport(); } catch(e) {}
        state.cleanupViewport = null;
      }
      if (typeof config.clearSelection === 'function') config.clearSelection();
      if (state.panel && state.panel.parentNode) state.panel.parentNode.removeChild(state.panel);
      closeContextEditor();
      state.panel = null;
      state.contextText = '';
      state.contextKind = '';
      state.contextRange = null;
    }

    return {
      open: open,
      close: close,
      setContext: setContext,
      getContextText: function() { return state.contextText; },
      getPanel: function() { return state.panel; }
    };
  }

  window.AIReadingAssistant = { create: create };
})();
