// AIHelper — thin wrapper around /api/ai/complete (SSE).
// Usage:
//   const ctrl = AIHelper.complete({
//     messages: [{role:'system',content:'...'},{role:'user',content:'...'}],
//     onChunk: (text) => { ... },
//     onDone: (fullText) => { ... },
//     onError: (msg) => { ... },
//   });
//   ctrl.abort();   // cancel mid-stream
(function(global) {
  function _readCSRFToken() {
    var m = document.cookie.match(/(?:^|; )csrf_token=([^;]+)/);
    return m ? decodeURIComponent(m[1]) : '';
  }

  function _parseSSEChunk(buf, onChunk) {
    var idx;
    var emitted = '';
    while ((idx = buf.indexOf('\n')) !== -1) {
      var line = buf.slice(0, idx).replace(/\r$/, '');
      buf = buf.slice(idx + 1);
      if (!line.startsWith('data: ')) continue;
      var data = line.slice(6).trim();
      if (data === '[DONE]') { return { buf: buf, done: true, emitted: emitted }; }
      try {
        var obj = JSON.parse(data);
        var delta = obj && obj.choices && obj.choices[0] && obj.choices[0].delta;
        var t = delta && delta.content;
        if (t) { emitted += t; if (onChunk) onChunk(t); }
      } catch (e) { /* ignore malformed lines */ }
    }
    return { buf: buf, done: false, emitted: emitted };
  }

  function complete(opts) {
    opts = opts || {};
    var messages = opts.messages || [];
    var ctrl = new AbortController();
    var fullText = '';

    fetchWithCurrentCSRF('/api/ai/complete', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': _readCSRFToken(),
        'Accept': 'text/event-stream'
      },
      body: JSON.stringify({
        messages: messages,
        scene: opts.scene || 'general',
        temperature: opts.temperature,
        max_tokens: opts.maxTokens
      }),
      signal: ctrl.signal
    }).then(function(resp) {
      if (!resp.ok) {
        return resp.json().then(function(j) {
          throw new Error((j && j.message) || ('HTTP ' + resp.status));
        }, function() { throw new Error('HTTP ' + resp.status); });
      }
      var reader = resp.body.getReader();
      var dec = new TextDecoder();
      var buf = '';
      function pump() {
        return reader.read().then(function(r) {
          if (r.done) {
            if (opts.onDone) opts.onDone(fullText);
            return;
          }
          buf += dec.decode(r.value, { stream: true });
          var out = _parseSSEChunk(buf, function(t) {
            fullText += t;
            if (opts.onChunk) opts.onChunk(t, fullText);
          });
          buf = out.buf;
          if (out.done) {
            if (opts.onDone) opts.onDone(fullText);
            try { reader.cancel(); } catch(e) {}
            return;
          }
          return pump();
        });
      }
      return pump();
    }).catch(function(err) {
      if (err && err.name === 'AbortError') return;
      if (opts.onError) opts.onError(String(err && err.message || err));
    });

    return {
      abort: function() { try { ctrl.abort(); } catch(e) {} },
      getText: function() { return fullText; }
    };
  }

  // Build messages with a system prompt + user instruction.
  function buildMessages(systemPrompt, userText) {
    var arr = [];
    if (systemPrompt) arr.push({ role: 'system', content: systemPrompt });
    arr.push({ role: 'user', content: userText });
    return arr;
  }

  // 解析 admin 配置的多行快捷动作字符串。
  // 每行 "label | prompt"；# 开头注释、空行跳过。
  // vars 用于替换 prompt 里的 {key} 占位符（如 {subject}）。
  // 返回 [{label, prompt}]，若 raw 为空或解析后为空数组返回 null。
  function parseActions(raw, vars) {
    if (!raw || typeof raw !== 'string') return null;
    var lines = raw.split(/\r?\n/);
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line || line.charAt(0) === '#') continue;
      var idx = line.indexOf('|');
      if (idx <= 0) continue;
      var label = line.slice(0, idx).trim();
      var prompt = line.slice(idx + 1).trim();
      if (!label || !prompt) continue;
      if (vars) {
        prompt = prompt.replace(/\{(\w+)\}/g, function(m, k) {
          return Object.prototype.hasOwnProperty.call(vars, k) ? String(vars[k]) : m;
        });
      }
      out.push({ label: label, prompt: prompt });
    }
    return out.length ? out : null;
  }

  global.AIHelper = { complete: complete, buildMessages: buildMessages, parseActions: parseActions };

  // ──────────────────────────────────────────────────────────────────────
  // AIComposeDialog: a reusable modal for "tell AI what to write, see the
  // streamed reply, then insert/replace into the host editor".
  //
  // Usage:
  //   AIComposeDialog.open({
  //     title, placeholder, systemPrompt,
  //     contextText,             // optional pre-existing text shown read-only
  //     extraActions,            // [{label, prompt}] quick-action buttons
  //     onInsert: (text, mode)   // mode = 'append' | 'replace'
  //   });
  function _esc(s) { return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  function _buildDialogHTML(opts) {
    var t = function(k, fb) { return (window.__ ? window.__(k) : null) || fb; };
    var title = _esc(opts.title || t('note.ai.dialog.title', 'AI 助手'));
    var placeholder = _esc(opts.placeholder || t('note.ai.dialog.placeholder', '告诉 AI 你想要什么'));
    var ctxBlock = '';
    if (opts.contextText) {
      ctxBlock = '<div class="ai-dlg-ctx-label">' + _esc(t('note.ai.dialog.context_label', '上下文')) + '</div>'
        + '<pre class="ai-dlg-ctx">' + _esc(opts.contextText) + '</pre>';
    }
    var hintBlock = '';
    if (opts.hint) {
      hintBlock = '<div class="ai-dlg-hint">💡 ' + _esc(opts.hint) + '</div>';
    }
    var quick = '';
    if (opts.extraActions && opts.extraActions.length) {
      var btns = opts.extraActions.map(function(a, i) {
        return '<button type="button" class="ai-dlg-quick" data-idx="' + i + '">' + _esc(a.label) + '</button>';
      }).join('');
      quick = '<div class="ai-dlg-quick-row">' + btns + '</div>';
    }
    return '' +
      '<div class="ai-dlg-overlay" role="dialog" aria-modal="true" aria-labelledby="ai-dlg-title">' +
        '<div class="ai-dlg-box">' +
          '<div class="ai-dlg-header">' +
            '<span class="ai-dlg-title" id="ai-dlg-title"><i class="fa-solid fa-wand-magic-sparkles"></i> ' + title + '</span>' +
            '<button type="button" class="ai-dlg-close" aria-label="' + _esc(t('note.ai.dialog.cancel', '关闭')) + '">&times;</button>' +
          '</div>' +
          '<div class="ai-dlg-body">' +
            hintBlock +
            ctxBlock +
            '<textarea class="ai-dlg-prompt" placeholder="' + placeholder + '" rows="3"></textarea>' +
            quick +
            '<div class="ai-dlg-output" aria-live="polite"></div>' +
          '</div>' +
          '<div class="ai-dlg-footer">' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-cancel">' + _esc(t('note.ai.dialog.cancel', '取消')) + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-stop" style="display:none;">' + _esc(t('note.ai.dialog.stop', '停止')) + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-replace" style="display:none;">' + _esc(t('note.ai.dialog.replace', '替换')) + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-append" style="display:none;">' + _esc(t('note.ai.dialog.append', '追加')) + '</button>' +
            '<button type="button" class="ai-dlg-btn ai-dlg-btn-go">' + _esc(t('note.ai.dialog.generate', '生成')) + '</button>' +
          '</div>' +
        '</div>' +
      '</div>';
  }

  function openDialog(opts) {
    opts = opts || {};
    var t = function(k, fb) { return (window.__ ? window.__(k) : null) || fb; };
    var wrap = document.createElement('div');
    wrap.innerHTML = _buildDialogHTML(opts);
    var root = wrap.firstChild;
    document.body.appendChild(root);
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('ai-compose-dialog');
    var prevFocus = document.activeElement;

    var promptEl = root.querySelector('.ai-dlg-prompt');
    var outputEl = root.querySelector('.ai-dlg-output');
    var goBtn = root.querySelector('.ai-dlg-btn-go');
    var stopBtn = root.querySelector('.ai-dlg-btn-stop');
    var replaceBtn = root.querySelector('.ai-dlg-btn-replace');
    var appendBtn = root.querySelector('.ai-dlg-btn-append');
    var cancelBtn = root.querySelector('.ai-dlg-btn-cancel');
    var closeBtn = root.querySelector('.ai-dlg-close');

    var ctrl = null;
    var generated = '';

    function setRunning(on) {
      goBtn.style.display = on ? 'none' : '';
      stopBtn.style.display = on ? '' : 'none';
      promptEl.disabled = on;
    }
    function setHasResult(on) {
      replaceBtn.style.display = on ? '' : 'none';
      appendBtn.style.display = on ? '' : 'none';
    }
    function close() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      try { document.body.removeChild(root); } catch(e) {}
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('ai-compose-dialog');
      if (prevFocus && typeof prevFocus.focus === 'function') { try { prevFocus.focus(); } catch(e) {} }
    }
    function generate(promptOverride) {
      var prompt = (promptOverride != null ? promptOverride : promptEl.value || '').trim();
      if (!prompt) {
        if (window.BSDialog) BSDialog.toast(t('note.ai.toast.empty', '请输入指令'), 'warning');
        promptEl.focus();
        return;
      }
      generated = '';
      outputEl.textContent = '';
      outputEl.classList.add('ai-dlg-output-active');
      setHasResult(false);
      setRunning(true);
      var userMsg = prompt;
      if (opts.contextText) {
        userMsg = '【上下文】\n' + opts.contextText + '\n\n【指令】\n' + prompt;
      }
      ctrl = AIHelper.complete({
        messages: AIHelper.buildMessages(opts.systemPrompt, userMsg),
        scene: opts.scene || 'note',
        onChunk: function(_chunk, full) {
          generated = full;
          outputEl.textContent = full;
          outputEl.scrollTop = outputEl.scrollHeight;
        },
        onDone: function(full) {
          generated = full;
          setRunning(false);
          if (generated.trim()) setHasResult(true);
        },
        onError: function(msg) {
          setRunning(false);
          outputEl.textContent = msg || t('note.ai.toast.error', 'AI 调用失败');
          outputEl.classList.add('ai-dlg-output-err');
        }
      });
    }

    goBtn.addEventListener('click', function() { generate(); });
    stopBtn.addEventListener('click', function() {
      if (ctrl) { try { ctrl.abort(); } catch(e) {} ctrl = null; }
      setRunning(false);
      if (generated.trim()) setHasResult(true);
    });
    replaceBtn.addEventListener('click', function() {
      if (opts.onInsert) opts.onInsert(generated, 'replace');
      close();
    });
    appendBtn.addEventListener('click', function() {
      if (opts.onInsert) opts.onInsert(generated, 'append');
      close();
    });
    cancelBtn.addEventListener('click', close);
    closeBtn.addEventListener('click', close);
    root.addEventListener('click', function(e) { if (e.target === root) close(); });
    document.addEventListener('keydown', function escHandler(e) {
      if (e.key === 'Escape') { close(); document.removeEventListener('keydown', escHandler); }
    });

    // Quick actions: fill the prompt textarea so the user can refine it,
    // then explicitly press "Generate". Holding Ctrl/Cmd while clicking
    // sends the prompt immediately for power users.
    if (opts.extraActions) {
      Array.prototype.forEach.call(root.querySelectorAll('.ai-dlg-quick'), function(b) {
        b.addEventListener('click', function(e) {
          var idx = parseInt(b.getAttribute('data-idx'), 10);
          var act = opts.extraActions[idx];
          if (!act || !act.prompt) return;
          promptEl.value = act.prompt;
          // Move caret to end so the user can keep typing right away.
          promptEl.focus();
          var len = promptEl.value.length;
          try { promptEl.setSelectionRange(len, len); } catch(_) {}
          if (e && (e.ctrlKey || e.metaKey)) {
            generate(act.prompt);
          }
        });
      });
    }

    setTimeout(function() { promptEl.focus(); }, 30);
  }

  global.AIComposeDialog = { open: openDialog };
})(window);
