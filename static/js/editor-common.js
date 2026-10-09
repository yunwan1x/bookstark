/**
 * BookStark Editor Common Module
 * Shared logic for book and blog editors
 */

// Prevent MathJax "Cannot set property Package" error on re-initialization.
// tex-svg.js sets read-only properties on MathJax; loading it twice causes TypeError.
// Cherry's YW() checks document.getElementById("mathjax-js") before loading,
// but doesn't set id on the script it creates. We patch it after each Cherry init.
function tagMathJaxScript() {
  var scripts = document.querySelectorAll('script[src*="tex-svg"]');
  for (var i = 0; i < scripts.length; i++) {
    if (!scripts[i].id) scripts[i].id = 'mathjax-js';
  }
}

const BookStarkEditor = (function() {
  function isMobile() { return window.innerWidth <= 768; }

  var DRAFT_DB_NAME = 'bookstark-editor-drafts';
  var DRAFT_DB_VERSION = 1;
  var DRAFT_STORE_NAME = 'drafts';
  var LOCAL_DRAFT_LIMIT = 512 * 1024;

  function openDraftDB() {
    if (!window.indexedDB) return Promise.reject(new Error('IndexedDB unavailable'));
    return new Promise(function(resolve, reject) {
      var request = indexedDB.open(DRAFT_DB_NAME, DRAFT_DB_VERSION);
      request.onupgradeneeded = function(event) {
        var db = event.target.result;
        if (!db.objectStoreNames.contains(DRAFT_STORE_NAME)) {
          db.createObjectStore(DRAFT_STORE_NAME, { keyPath: 'key' });
        }
      };
      request.onsuccess = function(event) { resolve(event.target.result); };
      request.onerror = function() { reject(request.error || new Error('Draft database unavailable')); };
    });
  }

  function readIndexedDraft(key) {
    return openDraftDB().then(function(db) {
      return new Promise(function(resolve, reject) {
        var request = db.transaction(DRAFT_STORE_NAME, 'readonly').objectStore(DRAFT_STORE_NAME).get(key);
        request.onsuccess = function() { resolve(request.result ? request.result.content : null); };
        request.onerror = function() { reject(request.error); };
      });
    }).catch(function() { return null; });
  }

  function writeIndexedDraft(key, content) {
    return openDraftDB().then(function(db) {
      return new Promise(function(resolve, reject) {
        var tx = db.transaction(DRAFT_STORE_NAME, 'readwrite');
        tx.objectStore(DRAFT_STORE_NAME).put({ key: key, content: content, updatedAt: Date.now() });
        tx.oncomplete = function() { resolve(); };
        tx.onerror = function() { reject(tx.error); };
      });
    });
  }

  function deleteIndexedDraft(key) {
    return openDraftDB().then(function(db) {
      return new Promise(function(resolve, reject) {
        var tx = db.transaction(DRAFT_STORE_NAME, 'readwrite');
        tx.objectStore(DRAFT_STORE_NAME).delete(key);
        tx.oncomplete = function() { resolve(); };
        tx.onerror = function() { reject(tx.error); };
      });
    }).catch(function() {});
  }

  function readStoredDraft(key) {
    var localDraft = null;
    try { localDraft = localStorage.getItem(key); } catch (e) {}
    if (localDraft !== null) return Promise.resolve(localDraft);
    return readIndexedDraft(key);
  }

  function writeStoredDraft(key, content) {
    if (content.length <= LOCAL_DRAFT_LIMIT) {
      try {
        localStorage.setItem(key, content);
        return deleteIndexedDraft(key);
      } catch (e) {}
    }
    try { localStorage.removeItem(key); } catch (e) {}
    return writeIndexedDraft(key, content);
  }

  function deleteStoredDraft(key) {
    try { localStorage.removeItem(key); } catch (e) {}
    return deleteIndexedDraft(key);
  }

  // Registry for Cherry instances (used by theme.js to switch code block themes)
  var cherryInstances = [];
  function registerCherry(instance) {
    if (instance && cherryInstances.indexOf(instance) === -1) {
      cherryInstances.push(instance);
    }
  }
  function getCherryInstances() { return cherryInstances; }

  // Cherry Markdown base config
  function getCherryConfig(overrides) {
    var toolbarItems = isMobile()
      ? ['list', 'header','color','size','panel', {insert: ['link','image', 'code', 'table',"detail"]}, 'undo', 'redo','search']
      : [
          'bold', 'italic', 'strikethrough','link', '|',
          'color', 'header','|',
          'list', 'justify','panel', ,'detail', '|','export',
          {
            insert: [  'hr', 'code', 'formula', 'toc', 'table','image'],
          },
          'graph', '|','search',
          'togglePreview', 'fullScreen', 'theme','redo','undo'
        ];

    var editorModel = isMobile() ? 'editOnly' : 'edit&preview';

    var savedTheme = getSavedTheme();
    var cherryMainTheme = savedTheme;

    // Cherry custom AI menus for the bubble (selection) toolbar.
    // Each item delegates to window.__runEditorAIQuickAction (defined in editor.js).
    // 优先用 admin 在 settings 里配置的 ai_actions_selection（每行 label | prompt），
    // 解析失败/未配置时 fallback 到下面这套硬编码默认动作（保留 i18n 多语言）。
    var defaultAiActions = [
      { label: (window.__ && window.__('editor.ai.action.rewrite'))   || '改写',     icon: '✨', prompt: '请改写以下选中的文本，保持原意但更通顺、更专业。直接给改写后的版本。' },
      { label: (window.__ && window.__('editor.ai.action.expand'))    || '扩写',     icon: '➕', prompt: '请把选中文本扩写得更详细、更有信息量，保留原结构。直接给扩写后的版本。' },
      { label: (window.__ && window.__('editor.ai.action.shorten'))   || '缩写',     icon: '➖', prompt: '请把选中文本压缩到原长度的 1/3 左右，保留核心信息。' },
      { label: (window.__ && window.__('editor.ai.action.translate')) || '翻译为英文', icon: '🌐', prompt: '请把选中文本翻译为流畅自然的英文。' },
      { label: (window.__ && window.__('editor.ai.action.continue'))  || '续写',     icon: '↪',  prompt: '请基于选中文本的语气和上下文，续写一段（约 2-3 句话）。' }
    ];
    var aiActions = defaultAiActions;
    var rawSel = window.AI_QUICK_RAW && window.AI_QUICK_RAW.selection;
    if (rawSel && window.AIHelper && AIHelper.parseActions) {
      var parsed = AIHelper.parseActions(rawSel);
      if (parsed && parsed.length) {
        aiActions = parsed.map(function(a) { return { label: a.label, icon: '✨', prompt: a.prompt }; });
      }
    }
    // 给每项分配稳定的 menu name（cherry 需要唯一 name 来注册菜单项）
    aiActions = aiActions.map(function(a, i) { return Object.assign({ name: 'aiAct' + i }, a); });

    var customMenu = {};
    if (window.Cherry && typeof window.Cherry.createMenuHook === 'function') {
      aiActions.forEach(function(a) {
        customMenu[a.name] = window.Cherry.createMenuHook(a.label, {
          iconName: '',
          icon: '<span class="cherry-ai-icon" aria-hidden="true">' + a.icon + '</span>',
          onClick: function(selection) {
            // Cherry passes the selection text. Delegate to the editor-side
            // helper which streams the AI response and replaces the selection
            // via CodeMirror dispatch (which preserves undo history).
            if (typeof window.__runEditorAIQuickAction === 'function') {
              window.__runEditorAIQuickAction(a.prompt, selection);
            }
            // Returning undefined keeps the selection as-is until the async
            // replacement lands.
            return undefined;
          }
        });
      });
    }

    var bubbleAI = aiActions.map(function(a) { return a.name; });
    var bubbleItems = ['bold', 'italic', 'underline', 'quote', '|'].concat(bubbleAI);

    return Object.assign({
      id: 'cherry-container',
      value: '',
      isPreviewOnly: false,
      editor: {
        defaultModel: editorModel,
        showFullWidth: true,
        placeholder: '开始编写文档内容...',
      },
      toolbars: {
        toolbar: toolbarItems,
        bubble: bubbleItems,
        float: !isMobile()?['h1', 'h2', 'h3', 'link', 'ol', 'ul', 'detail', 'panel', 'quote', 'table', 'code']:['bold','link', 'ol', 'ul', 'detail','quote', 'code'],
        customMenu: customMenu,
      },
      engine: {
        global: {
          classicBr: false
        },
        syntax: {
          autoLink: {
            enableShortLink: true,
            shortLinkLength: 20
          },
          table: {
            enableChart: false
          },
          codeBlock: {
            wrap: true,
            lineNumber: true,
            copyCode: true,
            editCode: true,
            changeLang: true,
          },

          mathBlock: {
            engine: 'MathJax',
            src: (window.MathJax && typeof window.MathJax.tex2svgPromise === 'function') ? undefined : '/static/js/mathjax/tex-svg.js',
            plugins: true,
          },
          inlineMath: {
            engine: 'MathJax',
          },
          mermaid: {
            distPath: '/static/js/mermaid.min.js'
          },
         
          header: {
            anchorStyle: 'none',
            strict: false
          } 
        },
      },
      fileUpload: function(file, callback) {
        // Try hash pre-check first to avoid re-uploading duplicates
        var doUpload = function() {
          var formData = new FormData();
          formData.append('file', file);
          csrfFetch('/api/uploads', {
            method: 'POST',
            body: formData
          })
          .then(function(r) {
            if (!r.ok) throw new Error('HTTP ' + r.status);
            return r.json();
          })
          .then(function(res) {
            if (res.code === 0 && res.data && res.data.url) {
              callback(res.data.url);
            } else {
              BSDialog.toast((res && res.message) || '上传失败', 'error');
            }
          })
          .catch(function(err) { BSDialog.toast('上传失败', 'error'); });
        };
        computeFileHash(file).then(function(hash) {
          return checkUploadByHash(hash);
        }).then(function(existing) {
          if (existing && existing.url) {
            callback(existing.url);
          } else {
            doUpload();
          }
        }).catch(function() {
          doUpload();
        });
      },
      themeSettings: {
        themeList: [
          { className: 'github', label: 'GitHub' },
          { className: 'vue', label: 'Vue' },
          { className: 'dark', label: '暗色' },
        ],
        mainTheme: cherryMainTheme,
        codeBlockTheme: cherryMainTheme === 'dark' ? 'one-dark' : 'one-light',
        inlineCodeTheme: cherryMainTheme,
      },
     
    }, overrides);
  }

  // Determine initial theme based on saved preference
  function getSavedTheme() {
    // If page is in dark mode, use dark theme
    var pageTheme = document.documentElement.getAttribute('data-theme');
    if (pageTheme === 'dark') return 'dark';
    // In light mode, only use github or vue (dark is driven by page theme)
    var saved = localStorage.getItem('cherry-theme');
    if (saved === 'vue') return 'vue';
    return 'github';
  }

  // Sync Cherry theme preference to localStorage (only store non-dark preferences)
  function syncPageTheme() {
    var cherry = document.querySelector('.cherry');
    if (!cherry) return;
    var isVue = cherry.classList.contains('theme__vue');
    var isDark = cherry.classList.contains('theme__dark');
    // Only persist non-dark preferences; dark is driven by page theme, not cherry-theme
    if (isDark) {
      // Don't overwrite the saved light-mode preference
    } else if (isVue) {
      localStorage.setItem('cherry-theme', 'vue');
    } else {
      localStorage.setItem('cherry-theme', 'github');
    }
  }

  // Apply initial theme — Cherry may have restored its own theme from cherry-theme localStorage
  function applyInitialTheme() {
    // Sync page theme icon and Cherry theme with stored preference
    if (window.BookStarkTheme) {
      window.BookStarkTheme.apply(window.BookStarkTheme.get());
    }
    var cherry = document.querySelector('.cherry');
    if (!cherry) return;
    // If Cherry didn't apply any custom theme, apply based on saved preference
    if (cherry.classList.contains('theme__default')) {
      var saved = getSavedTheme();
      cherry.classList.remove('theme__default');
      cherry.classList.add('theme__' + saved);
      // Also set code block theme attribute
      var codeTheme = saved === 'dark' ? 'one-dark' : 'one-light';
      cherry.setAttribute('data-code-block-theme', codeTheme);
    }
    syncPageTheme();
  }

  // Watch Cherry theme class changes
  function setupThemeSync() {
    var observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(m) {
        if (m.attributeName === 'class') syncPageTheme();
      });
    });

    function startObserving() {
      var cherry = document.querySelector('.cherry');
      if (cherry) {
        observer.observe(cherry, { attributes: true, attributeFilter: ['class'] });
        syncPageTheme();
      } else {
        setTimeout(startObserving, 200);
      }
    }
    startObserving();
  }

  // Intercept image file drops on the Cherry editor area.
  // CodeMirror's default drop handler reads all files as text (readAsText),
  // which corrupts image files. We intercept the drop event first and route
  // image files through the fileUpload callback, then insert the markdown
  // directly into the editor.
  function setupEditorImageDrop(containerId, fileUploadFn, cherryInstance) {
    if (typeof fileUploadFn !== 'function') return;
    var container = document.getElementById(containerId);
    if (!container) return;
    container.addEventListener('drop', function(e) {
      var files = e.dataTransfer && e.dataTransfer.files;
      if (!files || files.length === 0) return;
      var hasImage = false;
      for (var i = 0; i < files.length; i++) {
        if (files[i].type && files[i].type.indexOf('image/') === 0) {
          hasImage = true;
          break;
        }
      }
      if (!hasImage) return;
      e.preventDefault();
      e.stopPropagation();
      var editor = cherryInstance && cherryInstance.editor && cherryInstance.editor.editor;
      for (var j = 0; j < files.length; j++) {
        if (files[j].type && files[j].type.indexOf('image/') === 0) {
          (function(file) {
            fileUploadFn(file, function(url) {
              if (typeof url === 'string' && url && editor && typeof editor.replaceSelection === 'function') {
                var name = file.name ? file.name.replace(/\.[^.]+$/, '') : '';
                var md = '![' + name + '](' + url + ')';
                editor.replaceSelection(md);
              }
            });
          })(files[j]);
        }
      }
    }, true); // capture phase: runs before CodeMirror's handler
  }

  function getEditorEmojiCategories() {
    return [
      { key:'common', i18n:'editor.mindmap.icon.common', icons:['⭐','📌','🔥','💡','✅','❌','⚠️','🎯','📎','🔗','💎','🏷️','📦','🔧','📊','🎨','🚀','💬','📝','🔔','❤️','👍','🎉','⏰','📚','🔍','💰','🌟','🎵','🌈','☁️','⚡'] },
      { key:'face', i18n:'editor.mindmap.icon.face', icons:['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','😉','😊','😇','🥰','😍','🤩','😘','😋','😛','😜','🤪','🤗','🤭','🤫','🤔','😐','😑','😶','😏','🙄','😬','😌','😔','😪','🤤','😴','🥳','😎','🤓','🧐','😟','😕','😮','😳','🥺','😢','😭','😱','😤','😡','🤬','🤯','🤖','👻','💀','💩'] },
      { key:'gesture', i18n:'editor.mindmap.icon.gesture', icons:['👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','💪'] },
      { key:'people', i18n:'editor.mindmap.icon.people', icons:['👶','👧','🧒','👦','👩','🧑','👨','👵','🧓','👴','👮','🕵️','👷','🤴','👸','👳','🧕','🤵','👰','🤰','🤱','👼','🎅','🤶','🦸','🦹','🧙','🧚','🧛','🧜','🧝','🧟','💃','🕺','🏃','🚶','🏊','🚴'] },
      { key:'animal', i18n:'editor.mindmap.icon.animal', icons:['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔','🐧','🐦','🦆','🦅','🦉','🦇','🐺','🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🕷️','🐢','🐍','🐙','🦑','🦀','🐠','🐬','🐳','🦈','🐘','🦒','🐕','🐈'] },
      { key:'food', i18n:'editor.mindmap.icon.food', icons:['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🌽','🥕','🥔','🍠','🥐','🥖','🍞','🧀','🥚','🍳','🥞','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🥪','🌮','🌯','🥗','🍝','🍜','🍣','🍱','🍰','🎂','🍫','🍿','☕','🍵','🍺'] },
      { key:'travel', i18n:'editor.mindmap.icon.travel', icons:['🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🚚','🚛','🚜','🏍️','🛵','🚲','🚇','🚄','🚅','🚂','✈️','🛫','🛬','🚀','🛸','🚁','⛵','🚢','⚓','🏠','🏡','🏢','🏥','🏦','🏨','🏫','⛪','🕌','🗼','🗽','🗻','🏕️','🏖️','⛰️','🌋'] },
      { key:'object', i18n:'editor.mindmap.icon.object', icons:['⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','💽','💾','💿','📷','📸','📹','🎥','📞','☎️','📺','📻','🎙️','🧭','⏱️','⏰','⌛','📡','🔋','🔌','💡','🔦','🗑️','💸','💵','💰','💳','💎','⚖️','🧰','🔧','🔨','⚙️','🧲','🛡️','🔮','🔭','🔬','💊','💉','🧬','🔑','🚪','🧸','🎁','🎈','🎊','🎉','✉️','📧','📦','✏️','🖊️','📝','📁','📅','📈','📊','📌','📍','📎','✂️'] },
      { key:'symbol', i18n:'editor.mindmap.icon.symbol', icons:['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','💕','💞','💓','💗','💖','💘','☮️','☯️','♈','♉','♊','♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','❗','❓','‼️','⁉️','⚠️','♻️','✅','❎','🌐','💤','🆗','🆕','🆓','0️⃣','1️⃣','2️⃣','3️⃣','4️⃣','5️⃣','6️⃣','7️⃣','8️⃣','9️⃣','▶️','⏸️','⏹️','➡️','⬅️','⬆️','⬇️','↗️','↘️','↙️','↖️','➕','➖','➗','✖️','✔️','☑️','🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','⬛','⬜','🔔','📣'] },
      { key:'flag', i18n:'editor.mindmap.icon.flag', icons:['🏁','🚩','🎌','🏴','🏳️','🏳️‍🌈','🏳️‍⚧️','🏴‍☠️','🇨🇳','🇺🇸','🇬🇧','🇯🇵','🇰🇷','🇫🇷','🇩🇪','🇮🇹','🇪🇸','🇷🇺','🇧🇷','🇮🇳','🇦🇺','🇨🇦','🇲🇽','🇸🇬','🇹🇭','🇻🇳','🇲🇾','🇮🇩','🇵🇭','🇳🇿','🇿🇦','🇦🇪','🇹🇷','🇪🇬','🇭🇰','🇲🇴','🇹🇼','🇺🇳'] }
    ];
  }

  function closeEditorEmojiPicker() {
    var old = document.querySelector('.editor-emoji-picker');
    if (old) old.remove();
    document.querySelectorAll('.editor-emoji-toolbar-btn.active').forEach(function(btn) {
      btn.classList.remove('active');
      btn.setAttribute('aria-expanded', 'false');
    });
    if (window.__editorEmojiOutsideHandler) {
      document.removeEventListener('click', window.__editorEmojiOutsideHandler, true);
      window.__editorEmojiOutsideHandler = null;
    }
  }

  function toggleEditorEmojiPicker(button) {
    var existing = document.querySelector('.editor-emoji-picker');
    if (existing) {
      closeEditorEmojiPicker();
      return;
    }
    var picker = document.createElement('div');
    picker.className = 'editor-emoji-picker';
    picker.setAttribute('role', 'menu');
    picker.setAttribute('aria-label', window.__('note.compose.emoji') || '插入表情');

    var tabBar = document.createElement('div');
    tabBar.className = 'editor-emoji-tab-bar';
    var grid = document.createElement('div');
    grid.className = 'editor-emoji-grid';
    var categories = getEditorEmojiCategories();

    function renderCategory(index) {
      tabBar.querySelectorAll('.editor-emoji-tab').forEach(function(tab, i) {
        tab.classList.toggle('active', i === index);
      });
      grid.innerHTML = '';
      categories[index].icons.forEach(function(icon) {
        var item = document.createElement('button');
        item.type = 'button';
        item.className = 'editor-emoji-item';
        item.textContent = icon;
        item.title = icon;
        item.setAttribute('role', 'menuitem');
        item.setAttribute('aria-label', icon);
        item.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          if (typeof window.__insertEditorText === 'function') window.__insertEditorText(icon);
          closeEditorEmojiPicker();
        });
        grid.appendChild(item);
      });
    }

    categories.forEach(function(cat, idx) {
      if (idx > 0) {
        var sep = document.createElement('span');
        sep.className = 'editor-emoji-tab-sep';
        tabBar.appendChild(sep);
      }
      var tab = document.createElement('button');
      tab.type = 'button';
      tab.className = 'editor-emoji-tab';
      tab.textContent = window.__(cat.i18n);
      tab.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        renderCategory(idx);
      });
      tabBar.appendChild(tab);
    });

    picker.appendChild(tabBar);
    picker.appendChild(grid);
    picker.addEventListener('wheel', function(e) { e.stopPropagation(); }, { passive: false });
    picker.addEventListener('touchmove', function(e) { e.stopPropagation(); }, { passive: false });
    document.body.appendChild(picker);

    var rect = button.getBoundingClientRect();
    var pr = picker.getBoundingClientRect();
    var left = Math.max(8, Math.min(window.innerWidth - pr.width - 8, rect.left));
    var top = rect.bottom + 8;
    if (top + pr.height > window.innerHeight - 8) top = Math.max(8, rect.top - pr.height - 8);
    picker.style.left = left + 'px';
    picker.style.top = top + 'px';
    button.classList.add('active');
    button.setAttribute('aria-expanded', 'true');
    renderCategory(0);
    window.__editorEmojiOutsideHandler = function(e) {
      if (picker.contains(e.target) || button.contains(e.target)) return;
      closeEditorEmojiPicker();
    };
    setTimeout(function() {
      document.addEventListener('click', window.__editorEmojiOutsideHandler, true);
    }, 0);
  }

  function installEditorEmojiToolbar(containerId) {
    if (containerId !== 'cherry-container') return;
    setTimeout(function() {
      var container = document.getElementById(containerId);
      if (!container || container.querySelector('.editor-emoji-toolbar-btn')) return;
      var toolbar = container.querySelector('.cherry-toolbar');
      if (!toolbar) return;
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'cherry-toolbar-button editor-emoji-toolbar-btn';
      btn.title = window.__('note.compose.emoji') || '插入表情';
      btn.setAttribute('aria-label', btn.title);
      btn.setAttribute('aria-haspopup', 'menu');
      btn.setAttribute('aria-expanded', 'false');
      btn.innerHTML = '<span class="editor-emoji-toolbar-icon" aria-hidden="true">😀</span>';
      btn.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        toggleEditorEmojiPicker(btn);
      });
      toolbar.appendChild(btn);
    }, 0);
  }

  function getCherryEditorView(instance) {
    if (!instance) return null;
    try {
      if (instance.editor && instance.editor.editor && instance.editor.editor.view) {
        return instance.editor.editor.view;
      }
    } catch(e) {}
    try {
      var root = instance.wrapperDom || instance.cherryDom || document.getElementById('cherry-container');
      var cmRoot = root && root.querySelector ? root.querySelector('.cm-editor') : document.querySelector('.cm-editor');
      return cmRoot && cmRoot.cmView && cmRoot.cmView.view;
    } catch(e2) {}
    return null;
  }

  function runCherryHistoryCommand(instance, action) {
    var view = getCherryEditorView(instance);
    if (!view) return false;
    var keymap = (instance.editor && instance.editor.defaultKeymap) || [];
    var key = action === 'redo' ? 'Mod-y' : 'Mod-z';
    for (var i = 0; i < keymap.length; i++) {
      var item = keymap[i];
      if (!item || item.key !== key || typeof item.run !== 'function') continue;
      try {
        var result = item.run(view);
        try { view.focus(); } catch(e) {}
        return result !== false;
      } catch(e2) {
        return false;
      }
    }
    return false;
  }

  function installCherryHistoryToolbarFallback(instance) {
    if (!instance || instance.__bsHistoryToolbarFallbackInstalled) return;
    instance.__bsHistoryToolbarFallbackInstalled = true;
    function bind() {
      var root = instance.wrapperDom || instance.cherryDom || document;
      if (!root || !root.querySelectorAll) root = document;
      var buttons = root.querySelectorAll('.cherry-toolbar-undo, .cherry-toolbar-redo');
      for (var i = 0; i < buttons.length; i++) {
        var btn = buttons[i];
        if (btn.__bsHistoryFallbackBound) continue;
        btn.__bsHistoryFallbackBound = true;
        btn.addEventListener('click', function(e) {
          var action = this.classList.contains('cherry-toolbar-redo') ? 'redo' : 'undo';
          if (runCherryHistoryCommand(instance, action)) {
            e.preventDefault();
            e.stopPropagation();
            if (typeof BookStarkEditor.updateCharCount === 'function') {
              setTimeout(BookStarkEditor.updateCharCount, 0);
            }
          }
        }, true);
      }
    }
    setTimeout(bind, 0);
    setTimeout(bind, 300);
  }

// Initialize Cherry editor instance
  function initCherry(containerId, markdown, onChange) {
    const config = getCherryConfig({
      id: containerId,
      value: markdown || '',
      isPreviewOnly: false,
    });
    if (typeof onChange === 'function') {
      config.callback = config.callback || {};
      config.callback.afterChange = function(text) { onChange(text); };
    }
    config.callback = config.callback || {};
    config.callback.afterInit = function() {
      applyInitialTheme();
      setupThemeSync();
      if (window.BookStarkTheme) window.BookStarkTheme.observeCherry();
      installEditorEmojiToolbar(containerId);
    };
    var instance = new Cherry(config);
    registerCherry(instance);
    installCherryHistoryToolbarFallback(instance);
    tagMathJaxScript();
    // Intercept drop events on the editor area so image files are uploaded
    // instead of being inserted as text by CodeMirror's default drop handler.
    setupEditorImageDrop(containerId, config.fileUpload, instance);
    return instance;
  }

  // Initialize preview-only instance
  function initPreview(containerId, markdown, opts) {
    opts = opts || {};
    const config = getCherryConfig({
      id: containerId,
      value: markdown || '',
      isPreviewOnly: true,
      editor: { defaultModel: 'previewOnly' },
    });
    config.callback = config.callback || {};
    config.callback.afterInit = function() {
      applyInitialTheme(); setupThemeSync();
      if (window.BookStarkTheme) window.BookStarkTheme.observeCherry();
      if (opts.afterInit) opts.afterInit();
    };
    var instance = new Cherry(config);
    registerCherry(instance);
    tagMathJaxScript();
    return instance;
  }

  // Unified content renderer for share view.
  // containerId: ID of the DOM element to render into
  // content: raw content string
  // docType: 'spreadsheet' | 'presentation' | 'drawing' | 'mindmap' | 'html' | '' (markdown default)
  // opts: { onTocReady: fn, onFullpage: fn }
  // Returns Cherry instance for markdown, null for other types.
  function renderContent(containerId, content, docType, opts) {
    opts = opts || {};
    var container = document.getElementById(containerId);
    if (!container) return null;
    if (docType !== 'richdoc' && window.BookStarkRichDoc && BookStarkRichDoc.active) {
      BookStarkRichDoc.destroy();
    }

    // Destroy any active viewer before switching content type
    if (univerRunning) destroyUniver();
    if (excalidrawRunning) destroyExcalidraw(false);
    if (mindElixirInstance) destroyMindElixir();
    if (window.BookStarkPPTist) BookStarkPPTist.destroy();

    // Clear previous content (loading spinner, welcome, or previous doc)
    container.innerHTML = '';
    container.style.display = 'flex';
    container.style.flexDirection = 'column';

    if (docType === 'presentation') {
      var presentationScroll = document.getElementById('content-scroll');
      if (presentationScroll) presentationScroll.classList.add('presentation-mode');
      var presentationHeight = (presentationScroll ? presentationScroll.clientHeight : 0) || (window.innerHeight - 40);
      var presentationContainer = document.createElement('div');
      presentationContainer.id = containerId + '-presentation';
      presentationContainer.style.cssText = 'width:100%;height:' + presentationHeight + 'px;min-height:0;';
      container.appendChild(presentationContainer);
      BookStarkPPTist.mount(presentationContainer.id, content, {
        title: opts.title || window.__('editor.presentation.default_name'),
        readonly: true,
        loadingText: window.__('editor.presentation.loading'),
        onReady: function() {
          if (opts.onFullpage) opts.onFullpage();
        }
      });

    } else if (docType === 'spreadsheet') {
      var scrollEl = document.getElementById('content-scroll');
      var sheetHeight = (scrollEl ? scrollEl.clientHeight : 0) || (window.innerHeight - 40);
      var sheetContainer = document.createElement('div');
      sheetContainer.id = 'univer-container';
      sheetContainer.style.cssText = 'width:100%;height:' + sheetHeight + 'px;position:relative;';
      var sheetLoading = document.createElement('div');
      sheetLoading.id = 'univer-loading';
      sheetLoading.style.cssText = 'display:flex;align-items:center;justify-content:center;height:100%;';
      sheetLoading.innerHTML = '<span class="text-slate-500" style="font-size:14px;">' + window.__('editor.univer.loading') + '</span>';
      var sheetDiv = document.createElement('div');
      sheetDiv.id = 'univer-sheet';
      sheetDiv.style.cssText = 'width:100%;height:100%;visibility:hidden;';
      sheetContainer.appendChild(sheetLoading);
      sheetContainer.appendChild(sheetDiv);
      container.appendChild(sheetContainer);
      // Lock outer scroll to avoid double scrollbars
      if (scrollEl) scrollEl.classList.add('spreadsheet-mode');
      loadUniverAssets(function() {
        initUniver('univer-sheet', content, { readonly: true });
        if (opts.onFullpage) opts.onFullpage();
      });

    } else if (docType === 'drawing') {
      var excLoading = document.createElement('div');
      excLoading.id = 'excalidraw-loading';
      excLoading.style.cssText = 'display:flex;align-items:center;justify-content:center;min-height:600px;flex:1;';
      excLoading.innerHTML = '<span class="text-slate-500" style="font-size:14px;">' + window.__('editor.excalidraw.loading') + '</span>';
      var excCanvas = document.createElement('div');
      excCanvas.id = 'excalidraw-canvas';
      excCanvas.style.cssText = 'width:100%;min-height:600px;flex:1;display:none;';
      container.appendChild(excLoading);
      container.appendChild(excCanvas);
      var scrollEl2 = document.getElementById('content-scroll');
      if (scrollEl2) scrollEl2.classList.add('drawing-mode');
      loadExcalidrawAssets(function() {
        if (window.BookStarkExcalidraw) {
          window.BookStarkExcalidraw.initExcalidrawPreview('excalidraw-canvas', content);
          excalidrawRunning = true;
        }
        excCanvas.style.display = '';
        excLoading.style.display = 'none';
        if (opts.onFullpage) opts.onFullpage();
      });

    } else if (docType === 'mindmap') {
      var mindContainer = document.createElement('div');
      mindContainer.style.cssText = 'width:100%;flex:1;position:relative;min-height:0;';
      var mindLoading = document.createElement('div');
      mindLoading.id = 'mindmap-loading';
      mindLoading.style.cssText = 'display:flex;align-items:center;justify-content:center;height:100%;';
      mindLoading.innerHTML = '<span class="text-slate-500" style="font-size:14px;">' + window.__('editor.mindmap.loading') + '</span>';
      var mindEl = document.createElement('div');
      mindEl.id = 'mindmap-el';
      mindEl.style.cssText = 'width:100%;height:100%;visibility:hidden;';
      mindContainer.appendChild(mindLoading);
      mindContainer.appendChild(mindEl);
      container.appendChild(mindContainer);
      var scrollEl3 = document.getElementById('content-scroll');
      if (scrollEl3) scrollEl3.classList.add('mindmap-mode');
      loadMindElixirAssets(function() {
        var mind = initMindElixir(content, { readonly: true, toolBar: true });
        if (mind) {
          window._shareMindElixir = mind;
          mindEl.style.visibility = '';
          mindLoading.style.display = 'none';
          var exportBtns = document.getElementById('share-mindmap-export');
          if (exportBtns) exportBtns.style.display = 'flex';
        }
        if (opts.onFullpage) opts.onFullpage();
      });

    } else if (docType === 'richdoc') {
      var scrollElRich = document.getElementById('content-scroll');
      if (scrollElRich) scrollElRich.classList.add('richdoc-mode');
      container.innerHTML = '<div id="' + containerId + '-richdoc" class="richdoc-container"></div>';
      BookStarkRichDoc.mount(containerId + '-richdoc', content || BookStarkRichDoc.defaultContent(), {
        readonly: true,
        author: '共享编辑者'
      }).then(function() {
        if (opts.onTocReady) opts.onTocReady();
        if (opts.onFullpage) opts.onFullpage();
      }).catch(function(error) {
        container.innerHTML = '<div class="richdoc-load-error">' + error.message + '</div>';
      });

    } else if (docType === 'html') {
      var scrollElHtml = document.getElementById('content-scroll');
      if (scrollElHtml) scrollElHtml.classList.add('html-mode');
      initHtmlPreview(containerId, content);
      if (opts.onFullpage) opts.onFullpage();

    } else {
      // Markdown (default): Cherry renders DOM asynchronously after afterInit fires,
      // so TOC building needs setTimeout(100) to wait for the previewer to populate headings.
      var scrollEl4 = document.getElementById('content-scroll');
      if (scrollEl4) {
        scrollEl4.classList.remove('spreadsheet-mode', 'presentation-mode', 'drawing-mode', 'mindmap-mode', 'html-mode', 'richdoc-mode');
        scrollEl4.classList.add('markdown-mode');
      }
      return initPreview(containerId, content, {
        afterInit: function() {
          if (opts.onTocReady) setTimeout(opts.onTocReady, 100);
        }
      });
    }

    return null;
  }

  // Auto-save manager
  var SAVE_INTERVAL = (window.__SAVE_INTERVAL__ || 30) * 1000;

  function setupAutoSave(opts) {
    // opts: { getContent, saveFn, draftKey, onStatusChange }
    let saveTimer = null;
    let lastSaved = '';
    let status = 'saved';
    let lastSaveError = null;
    let inFlight = null;
    let draftWrite = Promise.resolve();
    let disposed = false;

    function queueDraftWrite(content) {
      draftWrite = draftWrite.catch(function() {}).then(function() {
        return writeStoredDraft(opts.draftKey, content);
      }).catch(function() {
        // Draft persistence is best effort. It must never stop server saving.
      });
      return draftWrite;
    }

    function queueDraftDelete() {
      draftWrite = draftWrite.catch(function() {}).then(function() {
        return deleteStoredDraft(opts.draftKey);
      }).catch(function() {});
      return draftWrite;
    }

    function setSaveStatus(s, error) {
      status = s;
      if (error) lastSaveError = error;
      if (s === 'saved') lastSaveError = null;
      // Editor change callbacks can arrive after a failed save. Keep its reason
      // visible until saving succeeds instead of replacing it with "unsaved".
      if (opts.onStatusChange) opts.onStatusChange(s, s === 'unsaved' ? lastSaveError || undefined : undefined);
    }

    function getSaveStatus() { return status; }

    function setLastSaved(content) { lastSaved = content; }

    function onContentChange() {
      const content = opts.getContent();
      queueDraftWrite(content);
      if (content !== lastSaved) {
        setSaveStatus('unsaved');
        // Only start timer if not already running — don't reset on new changes
        if (!saveTimer) {
          saveTimer = setTimeout(function() {
            saveTimer = null;
            autoSave().catch(function() {});
          }, SAVE_INTERVAL);
        }
      } else {
        setSaveStatus('saved');
        clearTimeout(saveTimer);
        saveTimer = null;
        queueDraftDelete();
      }
    }

    function scheduleRetry() {
      if (disposed) return;
      clearTimeout(saveTimer);
      saveTimer = setTimeout(function() {
        saveTimer = null;
        autoSave().catch(function() {});
      }, SAVE_INTERVAL);
    }

    function saveLatest() {
      if (disposed) return Promise.resolve({ skipped: true });
      const content = opts.getContent();
      if (content === lastSaved) {
        setSaveStatus('saved');
        return Promise.resolve({ skipped: true });
      }

      // Keep one write in flight. Callers that arrive while saving wait for it,
      // then persist the latest editor state instead of racing an older request.
      if (inFlight) {
        return inFlight.catch(function() {}).then(function() {
          return saveLatest();
        });
      }

      setSaveStatus('saving');
      inFlight = Promise.resolve().then(function() {
        return opts.saveFn(content);
      }).then(function(result) {
        lastSaved = content;
        return draftWrite.catch(function() {}).then(function() {
          const current = opts.getContent();
          if (current !== lastSaved) {
            // A newer edit arrived while this request was in flight. Keep that
            // exact revision recoverable until the follow-up save succeeds.
            queueDraftWrite(current);
            setSaveStatus('unsaved');
            scheduleRetry();
            return result;
          }
          return queueDraftDelete().then(function() {
            const latest = opts.getContent();
            if (latest !== lastSaved) {
              queueDraftWrite(latest);
              setSaveStatus('unsaved');
              scheduleRetry();
            } else {
              setSaveStatus('saved');
            }
            return result;
          });
        });
      }).catch(function(error) {
        setSaveStatus('unsaved', error);
        scheduleRetry();
        throw error;
      }).then(function(result) {
        inFlight = null;
        return result;
      }, function(error) {
        inFlight = null;
        throw error;
      });
      return inFlight;
    }

    function autoSave() {
      clearTimeout(saveTimer);
      saveTimer = null;
      return saveLatest();
    }

    function manualSave() {
      clearTimeout(saveTimer);
      saveTimer = null;
      return saveLatest();
    }

    function loadDraft(serverContent) {
      return draftWrite.catch(function() {}).then(function() {
        return readStoredDraft(opts.draftKey);
      }).then(function(draft) {
        if (draft !== null && draft !== serverContent) {
          // Render the current server content first. The draft is only applied
          // after the user explicitly chooses "restore" in the recovery banner.
          return { content: serverContent, draftContent: draft, hasDraft: true, serverContent: serverContent };
        }
        return { content: serverContent, draftContent: draft, hasDraft: false, serverContent: serverContent };
      });
    }

    function discardDraft() {
      setSaveStatus('saved');
      return queueDraftDelete();
    }

    function clearDraft() {
      return queueDraftDelete();
    }

    function destroy() {
      disposed = true;
      clearTimeout(saveTimer);
      saveTimer = null;
    }

    return { onContentChange, manualSave, autoSave, loadDraft, discardDraft, clearDraft, destroy, getSaveStatus, setLastSaved, setSaveStatus, get _lastSaved() { return lastSaved; } };
  }

  // Keyboard shortcuts
  function setupKeyboardShortcuts(saveFn) {
    document.addEventListener('keydown', function(e) {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        saveFn();
      }
    });
  }

  // Unload warning
  function setupUnloadWarning(isUnsavedFn) {
    window.addEventListener('beforeunload', function(e) {
      if (isUnsavedFn()) {
        e.preventDefault();
        e.returnValue = '';
      }
    });
  }

  // Update save status UI
  function updateSaveStatus(status, error) {
    const el = document.getElementById('save-status');
    if (!el) return;
    const labels = { saving: '● 保存中…', unsaved: '● 未保存', saved: '● 已保存' };
    const colors = { saving: 'text-blue-600', unsaved: 'text-amber-600', saved: 'text-green-600' };
    el.textContent = labels[status] || '';
    var reason = error ? BookStarkErrors.message(error, '保存失败，请重试') : '';
    if (reason) el.textContent += '：' + reason;
    el.title = reason;
    el.className = 'ml-auto ' + (colors[status] || '');
    const saveBtn = document.getElementById('save-btn');
    if (saveBtn) {
      if (status === 'saved') {
        saveBtn.classList.add('saved');
      } else {
        saveBtn.classList.remove('saved');
      }
    }
    updateCharCount();
  }

  // Show loading skeleton in a container
  function showLoading(container) {
    if (!container) return;
    container.innerHTML =
      '<div class="editor-loading">' +
        '<div class="editor-loading-line" style="width:40%"></div>' +
        '<div class="editor-loading-line" style="width:75%"></div>' +
        '<div class="editor-loading-line" style="width:60%"></div>' +
        '<div class="editor-loading-line" style="width:85%"></div>' +
        '<div class="editor-loading-line" style="width:50%"></div>' +
        '<div class="editor-loading-line" style="width:70%"></div>' +
        '<div class="editor-loading-line" style="width:45%"></div>' +
      '</div>';
  }

  // Update character count in statusbar
  function updateCharCount() {
    var cc = document.getElementById('char-count');
    if (!cc) return;
    // Spreadsheet: count characters in non-empty cells from currentMarkdown
    // (consistent across edit/preview modes and independent of spreadsheet runtime state)
    var md = typeof window._getCurrentMarkdown === 'function' ? window._getCurrentMarkdown() : '';
    if (md && md.charAt(0) === '{') {
      try {
        var data = JSON.parse(md);
        // Drawing: count elements
        if (data.elements) {
          var label = cc.querySelector('.statusbar-text-label');
          cc.innerHTML = (label ? label.outerHTML : '') + data.elements.length + ' 个元素';
          return;
        }
        // Spreadsheet: count characters in non-empty cells across all sheets.
        var count = 0;
        if (data.sheets) {
          Object.keys(data.sheets).forEach(function(sheetId) {
            var rows = data.sheets[sheetId] && data.sheets[sheetId].cellData;
            Object.keys(rows || {}).forEach(function(rowIndex) {
              Object.keys(rows[rowIndex] || {}).forEach(function(columnIndex) {
                var value = rows[rowIndex][columnIndex] && rows[rowIndex][columnIndex].v;
                if (value !== null && value !== undefined && value !== '') count += String(value).length;
              });
            });
          });
        } else if (data.celldata) {
          for (var i = 0; i < data.celldata.length; i++) {
            var v = data.celldata[i].v;
            if (v && v.v !== null && v.v !== undefined && v.v !== '') {
              count += String(v.v).length;
            }
          }
        } else {
          throw new Error('Not a spreadsheet snapshot');
        }
        var label = cc.querySelector('.statusbar-text-label');
        if (!label) {
          cc.innerHTML = '<i class="fa-solid fa-font" style="font-size:9px;margin-right:2px;"></i><span class="statusbar-text-label">字符数:</span> ' + count;
        } else {
          cc.lastChild.textContent = ' ' + count;
        }
        return;
      } catch(e) {}
    }
    // Markdown / HTML: count raw content length
    if (!md) {
      if (window._cherryEditor && typeof window._cherryEditor.getMarkdown === 'function') {
        md = window._cherryEditor.getMarkdown() || '';
      }
    }
    var label = cc.querySelector('.statusbar-text-label');
    if (!label) {
      cc.innerHTML = '<i class="fa-solid fa-font" style="font-size:9px;margin-right:2px;"></i><span class="statusbar-text-label">字符数:</span> ' + md.length;
    } else {
      cc.lastChild.textContent = ' ' + md.length;
    }
  }

  // ======== Custom Dialogs (delegate to BSDialog from base.html) ========
  function confirm2(message) { return BSDialog.confirm2(message); }
  function prompt2(message, defaultValue) { return BSDialog.prompt2(message, defaultValue); }
  function alert2(message) { return BSDialog.alert2(message); }
  function toast(message, type, duration) { return BSDialog.toast(message, type, duration); }

  // ======== HTML Editor ========
  var _htmlBaseCss =
    'body{font-family:system-ui,-apple-system,sans-serif;line-height:1.6;padding:24px}' +
    'img,svg,video,canvas{max-width:100%;height:auto}';

  function _isFullHtmlDocument(html) {
    if (!html) return false;
    var trimmed = html.trimLeft();
    return trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');
  }

  function _buildHtmlDocument(html, bare) {
    // 完整的 HTML 文档（含 <!DOCTYPE> 或 <html> 标签）直接加载，不注入外部样式
    if (_isFullHtmlDocument(html)) {
      return html;
    }
    var head = '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">';
    if (!bare) {
      head += '<link rel="stylesheet" href="/static/css/modern-normalize.css"><style>' + _htmlBaseCss + '</style>';
    }
    return '<!DOCTYPE html><html><head>' + head + '</head><body>' + (html || '') + '</body></html>';
  }

  function _escapeHtmlForTextarea(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function initHtmlEditor(containerId, htmlContent, onChange) {
    var container = document.getElementById(containerId);
    if (!container) return null;

    var _content = htmlContent || '';

    // 优雅降级：CM6 bundle 未加载时回退到 textarea
    if (typeof window.CMHtml === 'undefined') {
      container.innerHTML =
        '<div class="html-editor-wrap">' +
          '<textarea class="html-editor-textarea" spellcheck="false" aria-label="HTML 编辑器" placeholder="开始编写 HTML 内容..."></textarea>' +
        '</div>';
      var textarea = container.querySelector('.html-editor-textarea');
      textarea.value = _content;
      var _t = null;
      textarea.addEventListener('input', function() {
        _content = textarea.value;
        if (onChange) { clearTimeout(_t); _t = setTimeout(function() { onChange(_content); }, 300); }
      });
      return {
        getMarkdown: function() { return _content; },
        setMarkdown: function(c) { _content = c || ''; textarea.value = _content; },
        destroy: function() { container.innerHTML = ''; }
      };
    }

    container.innerHTML = '<div class="html-editor-wrap"><div class="html-editor-cm" aria-label="HTML 编辑器"></div></div>';
    var host = container.querySelector('.html-editor-cm');
    var CM = window.CMHtml;
    var _debounceTimer = null;
    var _isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    var updateListener = CM.EditorView.updateListener.of(function(u) {
      if (u.docChanged) {
        _content = u.state.doc.toString();
        if (onChange) {
          clearTimeout(_debounceTimer);
          _debounceTimer = setTimeout(function() { onChange(_content); }, 300);
        }
      }
    });

    var theme = CM.EditorView.theme({
      '&': { height: '100%', fontSize: '13px', backgroundColor: 'var(--color-bg-card)', color: 'var(--color-text)' },
      '.cm-scroller': { fontFamily: "'SF Mono','Fira Code','Cascadia Code',Consolas,monospace", lineHeight: '1.6', overflow: 'auto' },
      '.cm-content': { padding: '16px 0' },
      '.cm-gutters': { backgroundColor: 'transparent', color: 'var(--color-gray-400)', border: 'none' },
      '.cm-activeLine': { backgroundColor: 'rgba(37,99,235,0.06)' },
      '.cm-activeLineGutter': { backgroundColor: 'transparent' },
      '&.cm-focused': { outline: 'none' }
    }, { dark: _isDark });

    var state = CM.EditorState.create({
      doc: _content,
      extensions: [
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
        CM.html({ autoCloseTags: true, matchClosingTags: true, selfClosingTags: true }),
        CM.keymap.of([].concat(
          CM.closeBracketsKeymap,
          CM.defaultKeymap,
          CM.searchKeymap,
          CM.historyKeymap,
          CM.foldKeymap,
          CM.completionKeymap,
          [CM.indentWithTab]
        )),
        CM.EditorView.lineWrapping,
        theme,
        updateListener
      ]
    });

    var view = new CM.EditorView({ state: state, parent: host });

    return {
      getMarkdown: function() { return _content; },
      setMarkdown: function(content) {
        var c = content || '';
        if (c === _content) return;
        _content = c;
        view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: c } });
      },
      destroy: function() {
        try { view.destroy(); } catch(e) {}
        container.innerHTML = '';
      }
    };
  }

  function initHtmlPreview(containerId, htmlContent, options) {
    var container = document.getElementById(containerId);
    if (!container) return;
    var bare = options && options.bare;
    var doc = _buildHtmlDocument(htmlContent, bare);

    // 复用已有 iframe，避免每次销毁重建
    var iframe = container.querySelector('iframe.html-preview-iframe');
    if (iframe && iframe._previewSrcdoc !== undefined) {
      // 内容未变则跳过
      if (iframe._previewSrcdoc === doc) return;
      iframe.srcdoc = doc;
      iframe._previewSrcdoc = doc;
      return;
    }

    container.innerHTML = '<iframe class="html-editor-iframe html-preview-iframe" sandbox="allow-scripts allow-same-origin allow-downloads allow-popups allow-popups-to-escape-sandbox allow-modals" allow="camera *; microphone *; display-capture *; fullscreen; autoplay; clipboard-write"></iframe>';
    iframe = container.querySelector('iframe');
    iframe.srcdoc = doc;
    iframe._previewSrcdoc = doc;

    // Auto-resize iframe to fit content (skip when parent uses html-fullwidth — iframe scrolls internally)
    var isFullwidth = iframe.closest('.html-fullwidth');
    if (!isFullwidth) {
      function resizeIframe() {
        try {
          var doc = iframe.contentDocument || iframe.contentWindow.document;
          if (doc && doc.body) {
            iframe.style.height = doc.body.scrollHeight + 'px';
          }
        } catch(e) {}
      }
      iframe.addEventListener('load', resizeIframe);
      if (window.ResizeObserver) {
        var ro = new ResizeObserver(resizeIframe);
        ro.observe(iframe);
      }
    }
  }

  // ===== Univer Spreadsheet Support =====
  function waitForStylesheets(links, callback) {
    var pending = links.length;
    if (!pending) {
      if (callback) callback();
      return;
    }
    links.forEach(function(link) {
      var settled = false;
      function done() {
        if (settled) return;
        settled = true;
        pending--;
        if (!pending && callback) callback();
      }
      try {
        if (link.sheet) {
          done();
          return;
        }
      } catch (error) {}
      link.addEventListener('load', done, { once: true });
      link.addEventListener('error', done, { once: true });
      setTimeout(done, 3000);
    });
  }

  var univerRunning = false;

  function loadUniverAssets(callback) {
    window.BookStarkUniverAdapter.loadAssets(callback);
  }

  function initUniver(containerId, data, options) {
    var instance = window.BookStarkUniverAdapter.init(containerId, data, options || {});
    univerRunning = window.BookStarkUniverAdapter.running;
    return instance;
  }

  function destroyUniver() {
    window.BookStarkUniverAdapter.destroy();
    univerRunning = false;
  }

  function applyUniverReadonly(readonly) {
    window.BookStarkUniverAdapter.applyReadonly(!!readonly);
    univerRunning = window.BookStarkUniverAdapter.running;
  }

  // ===== Excalidraw Drawing Support =====

  var excalidrawLoaded = false;
  var excalidrawLoading = false;
  var excalidrawRunning = false;
  var drawingDirty = false;

  var mindElixirLoaded = false;
  var mindElixirLoading = false;
  var mindElixirInstance = null;
  var _meExportMenuCloseHandler = null;
  var _meStyleDropdownCloseHandler = null;
  var _meStyleDropdownResizeHandler = null;
  var _mindElixirThemeObserver = null;

  function getMindElixirAppTheme() {
    var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    var base = isDark
      ? (window.MindElixir && window.MindElixir.DARK_THEME)
      : (window.MindElixir && window.MindElixir.THEME);
    base = base || { palette: [], cssVar: {} };
    var cssVar = Object.assign({}, base.cssVar || {});
    if (isDark) {
      Object.assign(cssVar, {
        '--root-color': '#eff6ff',
        '--root-bgcolor': '#1d4ed8',
        '--root-border-color': '#60a5fa',
        '--main-color': '#93c5fd',
        '--main-bgcolor': '#172554',
        '--main-bgcolor-transparent': 'rgba(59, 130, 246, 0.16)',
        '--color': '#e2e8f0',
        '--bgcolor': '#0f172a',
        '--panel-color': '#e2e8f0',
        '--panel-bgcolor': '#1e293b',
        '--panel-border-color': '#334155',
        '--selected': '#60a5fa'
      });
    }
    return {
      name: isDark ? 'BookStark Dark' : 'BookStark Light',
      type: isDark ? 'dark' : 'light',
      palette: isDark
        ? ['#60a5fa', '#818cf8', '#22c55e', '#f59e0b', '#f472b6', '#38bdf8', '#a78bfa']
        : (base.palette || []).slice(),
      cssVar: cssVar
    };
  }

  function applyMindElixirAppTheme(mind) {
    if (!mind || !window.MindElixir || typeof mind.changeTheme !== 'function') return;
    try {
      mind.changeTheme(getMindElixirAppTheme());
      refreshMindElixirLayout(mind);
    } catch(e) {}
  }

  function refreshMindElixirLayout(mind, opts) {
    if (!mind) return;
    opts = opts || {};
    var shouldCenter = !!opts.center;
    function run(center) {
      try { if (typeof mind.linkDiv === 'function') mind.linkDiv(); } catch(e) {}
      if (center) {
        try { if (typeof mind.toCenter === 'function') mind.toCenter(); } catch(e) {}
      }
    }
    function schedule(fn) {
      if (window.requestAnimationFrame) window.requestAnimationFrame(fn);
      else window.setTimeout(fn, 0);
    }
    schedule(function() {
      run(shouldCenter);
      window.setTimeout(function() { run(false); }, 80);
    });
  }

  function observeMindElixirAppTheme(mind) {
    if (_mindElixirThemeObserver) _mindElixirThemeObserver.disconnect();
    _mindElixirThemeObserver = new MutationObserver(function() {
      applyMindElixirAppTheme(mind);
    });
    _mindElixirThemeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });
  }

  function addMindElixirToolbarExtras(isReadonly) {
    if (isReadonly) {
      var ltToolbar = document.querySelector('#mindmap-el .mind-elixir-toolbar.lt');
      if (ltToolbar) ltToolbar.style.display = 'none';
    }

    var rbToolbar = document.querySelector('#mindmap-el .mind-elixir-toolbar.rb');
    if (!rbToolbar || rbToolbar.querySelector('.me-export-wrap')) return;

    if (typeof window.exportMindmapPng === 'function' || typeof window.exportMindmapSvg === 'function') {
      var exportWrapper = document.createElement('span');
      exportWrapper.className = 'me-export-wrap';
      exportWrapper.style.cssText = 'position:relative;display:inline-flex;align-items:center;justify-content:center;';

      var exportBtn = document.createElement('span');
      exportBtn.title = window.__('editor.mindmap.export_btn');
      exportBtn.innerHTML = '<i class="fa-solid fa-download" style="font-size:13px;"></i>';
      exportBtn.style.cssText = 'cursor:pointer;display:inline-flex;align-items:center;justify-content:center;opacity:0.6;padding:2px;border-radius:3px;';
      exportBtn.onmouseenter = function() { exportBtn.style.opacity = '1'; };
      exportBtn.onmouseleave = function() { exportBtn.style.opacity = '0.6'; };

      var exportMenu = document.createElement('div');
      exportMenu.style.cssText = 'display:none;position:absolute;bottom:calc(100% + 6px);right:-4px;background:#fff;border:1px solid #e2e8f0;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,0.12);z-index:1000;min-width:90px;overflow:hidden;';

      function makeMenuItem(label, fn) {
        var item = document.createElement('div');
        item.textContent = label;
        item.style.cssText = 'padding:8px 14px;font-size:13px;cursor:pointer;color:#334155;white-space:nowrap;';
        item.onmouseenter = function() { item.style.background = '#f1f5f9'; };
        item.onmouseleave = function() { item.style.background = ''; };
        item.onclick = function(e) { e.stopPropagation(); exportMenu.style.display = 'none'; fn(); };
        return item;
      }

      if (typeof window.exportMindmapPng === 'function') exportMenu.appendChild(makeMenuItem('导出 PNG', window.exportMindmapPng));
      if (typeof window.exportMindmapSvg === 'function') exportMenu.appendChild(makeMenuItem('导出 SVG', window.exportMindmapSvg));

      exportBtn.onclick = function(e) {
        e.stopPropagation();
        exportMenu.style.display = exportMenu.style.display === 'none' ? 'block' : 'none';
      };

      if (_meExportMenuCloseHandler) document.removeEventListener('click', _meExportMenuCloseHandler);
      _meExportMenuCloseHandler = function(e) {
        if (!exportWrapper.contains(e.target)) exportMenu.style.display = 'none';
      };
      document.addEventListener('click', _meExportMenuCloseHandler);

      exportWrapper.appendChild(exportBtn);
      exportWrapper.appendChild(exportMenu);
      rbToolbar.insertBefore(exportWrapper, rbToolbar.firstChild);
    }
  }

  function loadMindElixirAssets(callback) {
    if (mindElixirLoaded) { callback && callback(); return; }
    if (mindElixirLoading) {
      var ci = setInterval(function() { if (mindElixirLoaded) { clearInterval(ci); callback && callback(); } }, 100);
      return;
    }
    mindElixirLoading = true;

    var loadTimeout = setTimeout(function() {
      if (!mindElixirLoaded) {
        mindElixirLoading = false;
        var loading = document.getElementById('mindmap-loading');
        if (loading) loading.innerHTML = '<div class="text-center"><i class="fa-solid fa-clock text-2xl text-amber-500 mb-2"></i><p class="text-sm text-slate-500">' + window.__('editor.mindmap.load_timeout') + '</p><button onclick="BookStarkEditor.retryLoadMindElixir()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
      }
    }, 10000);

    var cssLinks = [];
    function versionedAsset(path, version) {
      var v = version || window.__assetVer__;
      return path + (v ? '?v=' + encodeURIComponent(v) : '');
    }
    var mindCssHref = versionedAsset('/static/js/mind-elixir/mind-elixir.css', window.__mindElixirCssVer__);
    var mindResetHref = versionedAsset('/static/css/mindmap-reset.css', window.__mindmapResetCssVer__);
    var mindScriptSrc = versionedAsset('/static/js/mind-elixir/mind-elixir.umd.js', window.__mindElixirJsVer__);
    var markedScriptSrc = versionedAsset('/static/js/marked.min.js', window.__markedJsVer__);
    var cssLink = document.getElementById('me-core-css');
    if (!cssLink) {
      cssLink = document.createElement('link');
      cssLink.id = 'me-core-css';
      cssLink.rel = 'stylesheet';
      document.head.appendChild(cssLink);
    }
    if (cssLink.getAttribute('href') !== mindCssHref) cssLink.href = mindCssHref;
    cssLinks.push(cssLink);

    var meReset = document.getElementById('me-reset-css');
    if (!meReset) {
      meReset = document.createElement('link');
      meReset.id = 'me-reset-css';
      meReset.rel = 'stylesheet';
      document.head.appendChild(meReset);
    }
    if (meReset.getAttribute('href') !== mindResetHref) meReset.href = mindResetHref;
    cssLinks.push(meReset);

    var cssReady = false;
    var jsReady = false;
    function maybeReady() {
      if (!cssReady || !jsReady) return;
      clearTimeout(loadTimeout);
      mindElixirLoaded = true;
      mindElixirLoading = false;
      callback && callback();
    }
    waitForStylesheets(cssLinks, function() {
      cssReady = true;
      maybeReady();
    });

    function doLoadJS() {
      var script = document.createElement('script');
      script.src = mindScriptSrc;
      script.onload = function() {
        if (window.MindElixir && window.MindElixir.default) window.MindElixir = window.MindElixir.default;
        jsReady = true;
        maybeReady();
      };
      script.onerror = function() {
        clearTimeout(loadTimeout);
        mindElixirLoading = false;
        var loading = document.getElementById('mindmap-loading');
        if (loading) loading.innerHTML = '<div class="text-center"><i class="fa-solid fa-circle-exclamation text-2xl text-red-500 mb-2"></i><p class="text-sm text-slate-500">' + window.__('editor.mindmap.load_failed') + '</p><button onclick="BookStarkEditor.retryLoadMindElixir()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
      };
      document.head.appendChild(script);
    }

    if (window.marked) { doLoadJS(); }
    else {
      var ms = document.createElement('script');
      ms.src = markedScriptSrc;
      ms.onload = doLoadJS;
      ms.onerror = doLoadJS;
      document.head.appendChild(ms);
    }
  }

  function retryLoadMindElixir() {
    mindElixirLoading = false;
    var loading = document.getElementById('mindmap-loading');
    if (loading) loading.innerHTML = '';
    loadMindElixirAssets(function() {
      if (typeof renderMindmapContent === 'function') renderMindmapContent();
    });
  }

  function addMindElixirStyleToolbar(mind) {
    var container = mind.container || document.getElementById('mindmap-el');
    if (!container || container.querySelector('.me-style-toolbar')) return;
    var dropdowns = [];
    var openDropdownAnchor = null;
    var lastSelectedTpc = null;

    var COLORS = [
      {c:'#334155',n:'黑'},{c:'#ef4444',n:'红'},{c:'#f97316',n:'橙'},
      {c:'#eab308',n:'黄'},{c:'#22c55e',n:'绿'},{c:'#3b82f6',n:'蓝'},
      {c:'#8b5cf6',n:'紫'},{c:'#ec4899',n:'粉'},{c:'#64748b',n:'灰'},
      {c:'#ffffff',n:'白'}
    ];
    var SIZES = [12,14,16,18,20,24,28];
    var ICON_CATEGORIES = [
      { key:'common', i18n:'editor.mindmap.icon.common', icons:['⭐','📌','🔥','💡','✅','❌','⚠️','🎯','📎','🔗','💎','🏷️','📦','🔧','📊','🎨','🚀','💬','📝','🔔','❤️','👍','🎉','⏰','📚','🔍','💰','🌟','🎵','🌈','☁️','⚡'] },
      { key:'face', i18n:'editor.mindmap.icon.face', icons:['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','😉','😊','😇','🥰','😍','🤩','😘','😗','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','😐','😑','😶','😏','😒','🙄','😬','😮‍💨','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🥵','🥶','🥴','😵','🤯','🤠','🥳','🥸','😎','🤓','🧐','😟','😕','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱','😤','😡','😠','🤬','👿','💀','☠️','💩','🤡','👻','👽','🤖','😺','😸','😹','😻','😼','😽','🙀','😿','😾'] },
      { key:'gesture', i18n:'editor.mindmap.icon.gesture', icons:['👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','💪','🦾','🖖'] },
      { key:'people', i18n:'editor.mindmap.icon.people', icons:['👶','👧','🧒','👦','👩','🧑','👨','👩‍🦱','🧑‍🦱','👨‍🦱','👩‍🦰','🧑‍🦰','👨‍🦰','👱‍♀️','👱','👱‍♂️','👩‍🦳','🧑‍🦳','👨‍🦳','👩‍🦲','🧑‍🦲','👨‍🦲','🧔‍♀️','🧔','🧔‍♂️','👵','🧓','👴','👮','🕵️','💂','🥷','👷','🤴','👸','👳','🧕','🤵','👰','🤰','🫄','🤱','👼','🎅','🤶','🦸','🦹','🧙','🧚','🧛','🧜','🧝','🧞','🧟','💆','💇','🚶','🧍','🧎','🏃','💃','🕺','👯','🧖','🧗','🤸','⛹️','🏋️','🚴','🚵','🤼','🤽','🤾','🤺','⛷️','🏂','🏌️','🏇','🏊','🤹'] },
      { key:'animal', i18n:'editor.mindmap.icon.animal', icons:['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐻‍❄️','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🐣','🐥','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🪱','🐛','🦋','🐌','🐞','🐜','🪰','🪲','🪳','🦟','🦗','🕷️','🦂','🐢','🐍','🦎','🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🦭','🐊','🐅','🐆','🦓','🦍','🦧','🐘','🦣','🦏','🦛','🐪','🐫','🦒','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🦙','🐐','🦌','🐕','🐩','🦮','🐈','🐈‍⬛','🪶','🐓','🦃','🦤','🦚','🦜','🦢','🦩','🕊️','🐇','🦝','🦨','🦡','🦫','🦦','🦥','🐁','🐀','🐿️','🦔'] },
      { key:'food', i18n:'editor.mindmap.icon.food', icons:['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🫑','🌽','🥕','🫒','🧄','🧅','🥔','🍠','🥐','🥖','🍞','🥨','🥯','🧀','🥚','🍳','🧈','🥞','🧇','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🫓','🥪','🥙','🧆','🌮','🌯','🫔','🥗','🥘','🫕','🍝','🍜','🍲','🍛','🍣','🍱','🥟','🦪','🍤','🍙','🍚','🍘','🍥','🥠','🥮','🍢','🍡','🍧','🍨','🍦','🥧','🧁','🍰','🎂','🍮','🍭','🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','🥛','🍼','🫖','☕','🍵','🧃','🥤','🧋','🍶','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧉','🍾','🧊'] },
      { key:'travel', i18n:'editor.mindmap.icon.travel', icons:['🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🏍️','🛵','🚲','🛴','🛺','🚔','🚍','🚘','🚖','🛞','🚡','🚠','🚟','🚃','🚋','🚞','🚝','🚄','🚅','🚈','🚂','🚆','🚇','🚊','🚉','✈️','🛫','🛬','💺','🚀','🛸','🚁','🛶','⛵','🚤','🛥️','🛳️','⛴️','🚢','⚓','🛟','🏠','🏡','🏘️','🏚️','🏗️','🏭','🏢','🏬','🏣','🏤','🏥','🏦','🏨','🏪','🏫','🏩','💒','🏛️','⛪','🕌','🕍','🛕','🕋','⛩️','🗼','🗽','🗻','🏕️','🏖️','🏜️','🏝️','⛰️','🌋'] },
      { key:'object', i18n:'editor.mindmap.icon.object', icons:['⌚','📱','📲','💻','⌨️','🖥️','🖨️','🖱️','🖲️','💽','💾','💿','📀','📷','📸','📹','🎥','📽️','🎞️','📞','☎️','📟','📠','📺','📻','🎙️','🎚️','🎛️','🧭','⏱️','⏲️','⏰','🕰️','⌛','⏳','📡','🔋','🔌','💡','🔦','🕯️','🧯','🗑️','🛢️','💸','💵','💴','💶','💷','🪙','💰','💳','💎','⚖️','🪜','🧰','🪛','🔧','🔨','⚒️','🛠️','⛏️','🪚','🔩','⚙️','🪤','🧱','⛓️','🧲','🔫','💣','🪓','🔪','🗡️','⚔️','🛡️','🚬','⚰️','🪦','⚱️','🏺','🔮','📿','🧿','💈','⚗️','🔭','🔬','🕳️','🩹','🩺','💊','💉','🩸','🧬','🦠','🧫','🧪','🌡️','🧹','🪠','🧺','🧻','🧼','🪥','🧽','🪣','🧴','🛎️','🔑','🗝️','🚪','🪑','🛋️','🛏️','🛌','🧸','🪆','🖼️','🪞','🪟','🛍️','🛒','🎁','🎈','🎏','🎀','🎊','🎉','🪄','🪅','🎎','🏮','🎐','🧧','✉️','📩','📨','📧','💌','📥','📤','📦','📪','📫','📬','📭','📮','🗳️','✏️','✒️','🖊️','🖋️','📝','💼','📁','📂','🗂️','📅','📆','🗒️','🗓️','📇','📈','📉','📊','📋','📌','📍','📎','🖇️','📏','📐','✂️','🗃️','🗄️','🗑️'] },
      { key:'symbol', i18n:'editor.mindmap.icon.symbol', icons:['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉️','☸️','✡️','🔯','🕎','☯️','☦️','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','🉑','☢️','☣️','📴','📳','🈶','🈚','🈸','🈺','🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🈹','🈲','🅰️','🅱️','🆎','🆑','🅾️','🆘','❗','❓','❕','❔','‼️','⁉️','🔅','🔆','〽️','⚠️','🚸','🔱','⚜️','🔰','♻️','✅','🈯','💹','❇️','✳️','❎','🌐','💠','Ⓜ️','🌀','💤','🏧','🚾','♿','🅿️','🛗','🈳','🈂️','🛂','🛃','🛄','🛅','🚹','🚺','🚻','🚼','🚮','🎦','📶','🈁','🔣','ℹ️','🔤','🔡','🔠','🆖','🆗','🆙','🆒','🆕','🆓','0️⃣','1️⃣','2️⃣','3️⃣','4️⃣','5️⃣','6️⃣','7️⃣','8️⃣','9️⃣','🔟','🔢','#️⃣','*️⃣','⏏️','▶️','⏸️','⏯️','⏹️','⏺️','⏭️','⏮️','⏩','⏪','⏫','⏬','◀️','🔼','🔽','➡️','⬅️','⬆️','⬇️','↗️','↘️','↙️','↖️','↕️','↔️','↪️','↩️','⤴️','⤵️','🔀','🔁','🔂','🔄','🔃','➕','➖','➗','✖️','♾️','💲','💱','™️','©️','®️','〰️','➰','➿','🔚','🔙','🔛','🔝','🔜','✔️','☑️','🔘','🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','🟤','🔺','🔻','🔸','🔹','🔶','🔷','🔳','🔲','▪️','▫️','◾','◽','◼️','◻️','🟥','🟧','🟨','🟩','🟦','🟪','⬛','⬜','🟫','🔈','🔇','🔉','🔊','🔔','🔕','📣','📢'] },
      { key:'flag', i18n:'editor.mindmap.icon.flag', icons:['🏁','🚩','🎌','🏴','🏳️','🏳️‍🌈','🏳️‍⚧️','🏴‍☠️','🇨🇳','🇺🇸','🇬🇧','🇯🇵','🇰🇷','🇫🇷','🇩🇪','🇮🇹','🇪🇸','🇷🇺','🇧🇷','🇮🇳','🇦🇺','🇨🇦','🇲🇽','🇸🇬','🇹🇭','🇻🇳','🇲🇾','🇮🇩','🇵🇭','🇳🇿','🇿🇦','🇦🇪','🇸🇦','🇹🇷','🇪🇬','🇳🇬','🇰🇪','🇦🇷','🇨🇱','🇨🇴','🇵🇪','🇵🇰','🇧🇩','🇱🇰','🇲🇲','🇰🇭','🇱🇦','🇳🇵','🇲🇳','🇰🇵','🇭🇰','🇲🇴','🇹🇼','🇺🇳'] }
    ];

    var toolbar = document.createElement('div');
    toolbar.className = 'me-style-toolbar';

    function makeBtn(html, title, onClick) {
      var btn = document.createElement('button');
      btn.className = 'tb-btn';
      btn.type = 'button';
      btn.innerHTML = html;
      btn.title = title;
      btn.setAttribute('aria-label', title);
      btn.addEventListener('click', function(e) {
        e.stopPropagation();
        e.preventDefault();
        rememberSelection();
        onClick(e);
      });
      return btn;
    }

    function makeSep() {
      var d = document.createElement('div');
      d.className = 'tb-sep';
      return d;
    }

    function makeDropdown() {
      var d = document.createElement('div');
      d.className = 'tb-dropdown me-style-popover';
      dropdowns.push(d);
      ['pointerdown', 'mousedown', 'touchstart', 'click'].forEach(function(evt) {
        d.addEventListener(evt, function(e) {
          e.stopPropagation();
        }, { passive: false });
      });
      return d;
    }

    function closeAllDropdowns() {
      dropdowns.forEach(function(dd) {
        dd.classList.remove('open');
        dd.style.left = '';
        dd.style.top = '';
      });
      openDropdownAnchor = null;
    }

    function positionDropdown(dd, anchor) {
      if (!dd || !anchor) return;
      var rect = anchor.getBoundingClientRect();
      dd.style.position = 'fixed';
      dd.style.left = '-9999px';
      dd.style.top = '-9999px';
      if (dd.parentNode !== document.body) document.body.appendChild(dd);
      dd.classList.add('open');
      var ddRect = dd.getBoundingClientRect();
      var margin = 8;
      var left = rect.left + rect.width / 2 - ddRect.width / 2;
      var top = rect.bottom + 6;
      left = Math.max(margin, Math.min(left, window.innerWidth - ddRect.width - margin));
      if (top + ddRect.height > window.innerHeight - margin) {
        top = Math.max(margin, rect.top - ddRect.height - 6);
      }
      dd.style.left = left + 'px';
      dd.style.top = top + 'px';
    }

    function toggleDropdown(dd, e) {
      var anchor = e && e.currentTarget ? e.currentTarget : null;
      var isOpen = dd.classList.contains('open');
      closeAllDropdowns();
      if (!isOpen) {
        openDropdownAnchor = anchor;
        positionDropdown(dd, anchor);
      }
      if (e) { e.stopPropagation(); e.preventDefault(); }
    }

    function rememberSelection() {
      var current = mind.currentNode || (mind.currentNodes && mind.currentNodes[mind.currentNodes.length - 1]);
      if (current && current.nodeObj) lastSelectedTpc = current;
    }

    function isLiveTpc(tpc) {
      return !!(tpc && tpc.nodeObj && tpc.isConnected);
    }

    function getSelectedTpc() {
      rememberSelection();
      if (isLiveTpc(mind.currentNode)) return mind.currentNode;
      if (isLiveTpc(lastSelectedTpc)) return lastSelectedTpc;
      return null;
    }

    function applyStyle(prop, val) {
      var tpc = getSelectedTpc();
      if (!tpc) return;
      var styleUpdate = {};
      styleUpdate[prop] = val;
      mind.reshapeNode(tpc, { style: styleUpdate });
    }

    function resetStyle() {
      var tpc = getSelectedTpc();
      if (!tpc) return;
      tpc.nodeObj.style = {};
      tpc.style.cssText = '';
      mind.reshapeNode(tpc, { style: {} });
      closeAllDropdowns();
    }

    function selectedEditableNodes() {
      return (mind.currentNodes || []).filter(function(node) {
        return node && node.nodeObj && node.nodeObj.parent;
      });
    }

    function updateNodeActionButtons() {
      var hasNode = !!getSelectedTpc();
      var hasEditableNode = selectedEditableNodes().length > 0;
      toolbar.querySelectorAll('[data-node-action="sibling"], [data-node-action="remove"]').forEach(function(btn) {
        btn.disabled = !hasEditableNode;
      });
      toolbar.querySelectorAll('[data-node-action="child"]').forEach(function(btn) {
        btn.disabled = !hasNode;
      });
    }

    function scheduleNodeActionUpdate() {
      window.setTimeout(updateNodeActionButtons, 80);
    }

    var childBtn = makeBtn('<i class="fa-solid fa-plus" style="font-size:13px;"></i>', '添加子节点', function() {
      if (!getSelectedTpc()) return;
      mind.addChild();
      scheduleNodeActionUpdate();
    });
    childBtn.dataset.nodeAction = 'child';
    toolbar.appendChild(childBtn);

    var siblingBtn = makeBtn('<i class="fa-solid fa-turn-down" style="font-size:13px;transform:rotate(270deg);"></i>', '添加同级节点', function() {
      if (!selectedEditableNodes().length) return;
      mind.insertSibling('after');
      scheduleNodeActionUpdate();
    });
    siblingBtn.dataset.nodeAction = 'sibling';
    toolbar.appendChild(siblingBtn);

    var removeBtn = makeBtn('<i class="fa-solid fa-trash-can" style="font-size:12px;"></i>', '删除节点', function() {
      var nodes = selectedEditableNodes();
      if (!nodes.length) return;
      mind.removeNodes(nodes);
      scheduleNodeActionUpdate();
    });
    removeBtn.dataset.nodeAction = 'remove';
    toolbar.appendChild(removeBtn);

    toolbar.appendChild(makeSep());

    // --- Color button ---
    var colorGroup = document.createElement('div');
    colorGroup.className = 'tb-group';
    var colorBtn = makeBtn('<i class="fa-solid fa-palette" style="font-size:14px;"></i>', '文字颜色', function(e) {
      toggleDropdown(colorDD, e);
    });
    var colorDD = makeDropdown();
    var colorGrid = document.createElement('div');
    colorGrid.className = 'color-grid';
    COLORS.forEach(function(item) {
      var swatch = document.createElement('div');
      swatch.className = 'color-swatch';
      swatch.style.backgroundColor = item.c;
      if (item.c === '#ffffff') swatch.style.border = '2px solid #e2e8f0';
      swatch.title = item.n;
      swatch.setAttribute('aria-label', '颜色: ' + item.n);
      swatch.addEventListener('click', function(e) {
        e.stopPropagation();
        e.preventDefault();
        applyStyle('color', item.c);
        colorGrid.querySelectorAll('.color-swatch').forEach(function(s) { s.classList.remove('selected'); });
        swatch.classList.add('selected');
        closeAllDropdowns();
      });
      colorGrid.appendChild(swatch);
    });
    colorDD.appendChild(colorGrid);
    colorGroup.appendChild(colorBtn);
    colorGroup.appendChild(colorDD);
    toolbar.appendChild(colorGroup);

    // --- Background color button ---
    var bgGroup = document.createElement('div');
    bgGroup.className = 'tb-group';
    var bgBtn = makeBtn('<i class="fa-solid fa-fill-drip" style="font-size:14px;"></i>', '背景颜色', function(e) {
      toggleDropdown(bgDD, e);
    });
    var bgDD = makeDropdown();
    var bgGrid = document.createElement('div');
    bgGrid.className = 'color-grid';
    var BG_COLORS = [
      {c:'transparent',n:'无'},{c:'#fef2f2',n:'浅红'},{c:'#fff7ed',n:'浅橙'},
      {c:'#fefce8',n:'浅黄'},{c:'#f0fdf4',n:'浅绿'},{c:'#eff6ff',n:'浅蓝'},
      {c:'#f5f3ff',n:'浅紫'},{c:'#fdf2f8',n:'浅粉'},{c:'#f8fafc',n:'浅灰'},
      {c:'#1e293b',n:'深色'}
    ];
    BG_COLORS.forEach(function(item) {
      var swatch = document.createElement('div');
      swatch.className = 'color-swatch';
      if (item.c === 'transparent') {
        swatch.style.background = 'linear-gradient(45deg, #ccc 25%, transparent 25%, transparent 75%, #ccc 75%), linear-gradient(45deg, #ccc 25%, transparent 25%, transparent 75%, #ccc 75%)';
        swatch.style.backgroundSize = '8px 8px';
        swatch.style.backgroundPosition = '0 0, 4px 4px';
      } else {
        swatch.style.backgroundColor = item.c;
      }
      swatch.style.border = '2px solid #e2e8f0';
      swatch.title = item.n;
      swatch.setAttribute('aria-label', '背景: ' + item.n);
      swatch.addEventListener('click', function(e) {
        e.stopPropagation();
        e.preventDefault();
        applyStyle('backgroundColor', item.c === 'transparent' ? '' : item.c);
        bgGrid.querySelectorAll('.color-swatch').forEach(function(s) { s.classList.remove('selected'); });
        swatch.classList.add('selected');
        closeAllDropdowns();
      });
      bgGrid.appendChild(swatch);
    });
    bgDD.appendChild(bgGrid);
    bgGroup.appendChild(bgBtn);
    bgGroup.appendChild(bgDD);
    toolbar.appendChild(bgGroup);

    toolbar.appendChild(makeSep());

    // --- Font size button ---
    var sizeGroup = document.createElement('div');
    sizeGroup.className = 'tb-group';
    var sizeBtn = makeBtn('<i class="fa-solid fa-text-height" style="font-size:14px;"></i>', '字体大小', function(e) {
      toggleDropdown(sizeDD, e);
    });
    var sizeDD = makeDropdown();
    var sizeList = document.createElement('div');
    sizeList.className = 'size-list';
    SIZES.forEach(function(sz) {
      var item = document.createElement('div');
      item.className = 'size-item';
      item.textContent = sz + 'px';
      item.addEventListener('click', function(e) {
        e.stopPropagation();
        e.preventDefault();
        applyStyle('fontSize', sz + 'px');
        sizeList.querySelectorAll('.size-item').forEach(function(s) { s.classList.remove('selected'); });
        item.classList.add('selected');
        closeAllDropdowns();
      });
      sizeList.appendChild(item);
    });
    sizeDD.appendChild(sizeList);
    sizeGroup.appendChild(sizeBtn);
    sizeGroup.appendChild(sizeDD);
    toolbar.appendChild(sizeGroup);

    // --- Bold button ---
    toolbar.appendChild(makeBtn('<b>B</b>', '加粗', function() {
      var tpc = getSelectedTpc();
      if (!tpc) return;
      var current = tpc.nodeObj.style && tpc.nodeObj.style.fontWeight;
      applyStyle('fontWeight', current === 'bold' ? '' : 'bold');
    }));

    toolbar.appendChild(makeSep());

    // --- Icon/emoji button ---
    var iconGroup = document.createElement('div');
    iconGroup.className = 'tb-group';
    var iconBtn = makeBtn('😀', '添加图标', function(e) {
      toggleDropdown(iconDD, e);
    });
    var iconDD = makeDropdown();
    iconDD.classList.add('icon-dropdown');

    // Tab bar
    var tabBar = document.createElement('div');
    tabBar.className = 'icon-tab-bar';
    var iconGrid = document.createElement('div');
    iconGrid.className = 'icon-grid';

    function renderIconCategory(catIdx) {
      tabBar.querySelectorAll('.icon-tab').forEach(function(t, i) {
        t.classList.toggle('active', i === catIdx);
      });
      iconGrid.innerHTML = '';
      ICON_CATEGORIES[catIdx].icons.forEach(function(icon) {
        var item = document.createElement('div');
        item.className = 'icon-item';
        item.textContent = icon;
        item.title = icon;
        item.addEventListener('click', function(e) {
          e.stopPropagation();
          e.preventDefault();
          var tpc = getSelectedTpc();
          if (!tpc) return;
          var nodeObj = tpc.nodeObj;
          if (!nodeObj.icons) nodeObj.icons = [];
          nodeObj.icons.push(icon);
          mind.reshapeNode(tpc, { icons: nodeObj.icons });
          closeAllDropdowns();
        });
        iconGrid.appendChild(item);
      });
    }

    ICON_CATEGORIES.forEach(function(cat, idx) {
      if (idx > 0) {
        var sep = document.createElement('span');
        sep.className = 'icon-tab-sep';
        tabBar.appendChild(sep);
      }
      var tab = document.createElement('button');
      tab.type = 'button';
      tab.className = 'icon-tab';
      tab.textContent = window.__(cat.i18n);
      tab.addEventListener('click', function(e) {
        e.stopPropagation();
        e.preventDefault();
        renderIconCategory(idx);
      });
      tabBar.appendChild(tab);
    });

    iconDD.appendChild(tabBar);
    iconDD.appendChild(iconGrid);

    // Stop wheel events from reaching MindElixir (which uses them for zoom)
    iconDD.addEventListener('wheel', function(e) { e.stopPropagation(); }, { passive: false });
    iconDD.addEventListener('touchmove', function(e) { e.stopPropagation(); }, { passive: false });

    // Clear icons button in dropdown
    var clearIconBtn = document.createElement('div');
    clearIconBtn.className = 'icon-clear-btn';
    clearIconBtn.textContent = window.__('editor.mindmap.style.clear_icon');
    clearIconBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      e.preventDefault();
      var tpc = getSelectedTpc();
      if (!tpc) return;
      tpc.nodeObj.icons = [];
      mind.reshapeNode(tpc, { icons: [] });
      closeAllDropdowns();
    });
    iconDD.appendChild(clearIconBtn);

    // Render first tab by default
    renderIconCategory(0);

    iconGroup.appendChild(iconBtn);
    iconGroup.appendChild(iconDD);
    toolbar.appendChild(iconGroup);

    toolbar.appendChild(makeSep());

    // --- Reset button ---
    toolbar.appendChild(makeBtn('<i class="fa-solid fa-rotate-left" style="font-size:12px;"></i>', '重置样式', function() {
      resetStyle();
    }));

    container.appendChild(toolbar);

    // Prevent toolbar clicks from bubbling to MindElixir container,
    // which would clear node selection and hide the toolbar.
    ['pointerdown', 'mousedown', 'touchstart', 'click'].forEach(function(evt) {
      toolbar.addEventListener(evt, function(e) {
        e.stopPropagation();
        rememberSelection();
      }, { passive: false });
    });

    // Show/hide based on node selection
    function showToolbar() { toolbar.classList.add('visible'); }
    function hideToolbar() { closeAllDropdowns(); toolbar.classList.remove('visible'); updateNodeActionButtons(); }

    mind.bus.addListener('selectNodes', function() {
      rememberSelection();
      showToolbar();
      updateNodeActionButtons();
    });
    mind.bus.addListener('selectNewNode', function() {
      rememberSelection();
      showToolbar();
      updateNodeActionButtons();
    });
    mind.bus.addListener('unselectNodes', function() {
      setTimeout(function() {
        if (!mind.currentNode && (!mind.currentNodes || mind.currentNodes.length === 0)) hideToolbar();
        else updateNodeActionButtons();
      }, 50);
    });
    updateNodeActionButtons();

    // Close dropdowns on outside click
    if (_meStyleDropdownCloseHandler) document.removeEventListener('click', _meStyleDropdownCloseHandler);
    _meStyleDropdownCloseHandler = function(e) {
      var inDropdown = dropdowns.some(function(dd) { return dd.contains(e.target); });
      if (!toolbar.contains(e.target) && !inDropdown) closeAllDropdowns();
    };
    document.addEventListener('click', _meStyleDropdownCloseHandler);

    if (_meStyleDropdownResizeHandler) window.removeEventListener('resize', _meStyleDropdownResizeHandler);
    _meStyleDropdownResizeHandler = function() {
      var open = dropdowns.find(function(dd) { return dd.classList.contains('open'); });
      if (open && openDropdownAnchor) positionDropdown(open, openDropdownAnchor);
    };
    window.addEventListener('resize', _meStyleDropdownResizeHandler);
  }

  function initMindElixir(jsonStr, opts) {
    if (!window.MindElixir) return;
    var el = document.getElementById('mindmap-el');
    if (!el) return;
    var isReadonly = opts && opts.readonly;
    var options = {
      el: '#mindmap-el',
      direction: window.MindElixir.SIDE,
      theme: getMindElixirAppTheme(),
      locale: 'zh',
      newTopicName: '新节点',
      editable: !isReadonly,
      draggable: true,
      toolBar: opts && opts.toolBar !== undefined ? opts.toolBar : true,
      contextMenu: !isReadonly,
      keypress: !isReadonly,
    };
    if (window.marked) {
      options.markdown = function(text) { return window.marked.parse(text).trim(); };
    }
    var data;
    try { data = JSON.parse(jsonStr || '{}'); } catch(e) { data = window.MindElixir.new(window.__('editor.mindmap.new_name')); }
    if (!data || !data.nodeData) data = window.MindElixir.new(window.__('editor.mindmap.new_name'));
    var mind = new window.MindElixir(options);
    mind.init(data);
    mindElixirInstance = mind;
    applyMindElixirAppTheme(mind);
    refreshMindElixirLayout(mind, { center: true });
    observeMindElixirAppTheme(mind);
    addMindElixirToolbarExtras(isReadonly);
    if (!isReadonly) addMindElixirStyleToolbar(mind);
    return mind;
  }

  function getMindElixirData() {
    if (!mindElixirInstance) return null;
    try { return JSON.stringify(mindElixirInstance.getData()); } catch(e) { return null; }
  }

  function destroyMindElixir() {
    if (_meExportMenuCloseHandler) {
      document.removeEventListener('click', _meExportMenuCloseHandler);
      _meExportMenuCloseHandler = null;
    }
    if (_meStyleDropdownCloseHandler) {
      document.removeEventListener('click', _meStyleDropdownCloseHandler);
      _meStyleDropdownCloseHandler = null;
    }
    if (_meStyleDropdownResizeHandler) {
      window.removeEventListener('resize', _meStyleDropdownResizeHandler);
      _meStyleDropdownResizeHandler = null;
    }
    if (_mindElixirThemeObserver) {
      _mindElixirThemeObserver.disconnect();
      _mindElixirThemeObserver = null;
    }
    document.querySelectorAll('.me-style-popover').forEach(function(el) { el.remove(); });
    if (mindElixirInstance) {
      try { mindElixirInstance.destroy(); } catch(e) {}
      mindElixirInstance = null;
    }
  }

  function loadMindElixirData(data, options) {
    options = options || {};
    var readonly = !!options.readonly;
    var onChange = options && options.onChange;
    destroyMindElixir();
    var container = document.getElementById('mindmap-el');
    if (container) container.innerHTML = '';
    var loading = document.getElementById('mindmap-loading');
    if (loading) {
      loading.style.display = '';
      loading.innerHTML = '';
    }
    loadMindElixirAssets(function() {
      if (BookStarkEditor._loadAborted) {
        BookStarkEditor._loadAborted = false;
        return;
      }
      var mind = initMindElixir(data, { readonly: readonly });
      if (mind && !readonly && onChange) {
        mind.bus.addListener('operation', onChange);
      }
      if (loading) {
        loading.innerHTML = '';
        loading.style.display = 'none';
      }
    });
  }

  function exportMindElixirPng(filename) {
    if (!mindElixirInstance) return;
    mindElixirInstance.exportPng().then(function(blob) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = (filename || window.__('editor.create_doc.type.mindmap')) + '.png';
      a.click();
      setTimeout(function() { URL.revokeObjectURL(a.href); }, 1000);
    }).catch(function(e) {
      BookStarkEditor.toast('导出失败: ' + e.message, 'error');
    });
  }

  function exportMindElixirSvg(filename) {
    if (!mindElixirInstance) return;
    var blob = mindElixirInstance.exportSvg();
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = (filename || window.__('editor.create_doc.type.mindmap')) + '.svg';
    a.click();
    setTimeout(function() { URL.revokeObjectURL(a.href); }, 1000);
  }

  function loadExcalidrawAssets(callback) {
    if (excalidrawLoaded) {
      callback && callback();
      return;
    }
    if (excalidrawLoading) {
      var checkInterval = setInterval(function() {
        if (excalidrawLoaded) {
          clearInterval(checkInterval);
          callback && callback();
        }
      }, 100);
      return;
    }
    excalidrawLoading = true;

    // Load CSS
    var cssHref = '/static/css/excalidraw.css' + (window.__assetVer__ ? '?v=' + window.__assetVer__ : '');
    var cssLink = document.querySelector('link[data-excalidraw="css"]');
    if (!cssLink) {
      cssLink = document.createElement('link');
      cssLink.rel = 'stylesheet';
      cssLink.href = cssHref;
      cssLink.setAttribute('data-excalidraw', 'css');
      document.head.appendChild(cssLink);
    }

    var cssReady = false;
    var jsReady = false;
    function maybeReady() {
      if (!cssReady || !jsReady) return;
      clearTimeout(loadTimeout);
      excalidrawLoaded = true;
      excalidrawLoading = false;
      callback && callback();
    }
    waitForStylesheets([cssLink], function() {
      cssReady = true;
      maybeReady();
    });

    // Set asset path for fonts
    if (!window.EXCALIDRAW_ASSET_PATH) {
      window.EXCALIDRAW_ASSET_PATH = '/static/js/excalidraw/';
    }

    // Load main script with timeout
    var loadTimeout = setTimeout(function() {
      if (!excalidrawLoaded) {
        excalidrawLoading = false;
        var loading = document.getElementById('excalidraw-loading');
        if (loading) {
          loading.innerHTML = '<div class="text-center"><i class="fa-solid fa-clock text-2xl text-amber-500 mb-2"></i><p class="text-sm text-slate-500">' + window.__('editor.excalidraw.load_timeout') + '</p><button onclick="BookStarkEditor.retryLoadExcalidraw()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
        }
      }
    }, 10000);

    var script = document.createElement('script');
    script.type = 'module';
    script.src = '/static/js/excalidraw/excalidraw-entry.js' + (window.__assetVer__ ? '?v=' + window.__assetVer__ : '');
    script.setAttribute('data-excalidraw', 'js');
    script.onload = function() {
      var attempts = 0;
      function waitGlobal() {
        if (window.BookStarkExcalidraw) {
          jsReady = true;
          maybeReady();
          return;
        }
        attempts++;
        if (attempts > 100) {
          clearTimeout(loadTimeout);
          excalidrawLoading = false;
          var loading = document.getElementById('excalidraw-loading');
          if (loading) {
            loading.innerHTML = '<div class="text-center"><i class="fa-solid fa-circle-exclamation text-2xl text-red-500 mb-2"></i><p class="text-sm text-slate-500">' + window.__('editor.excalidraw.load_failed') + '</p><button onclick="BookStarkEditor.retryLoadExcalidraw()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
          }
          return;
        }
        setTimeout(waitGlobal, 50);
      }
      waitGlobal();
    };
    script.onerror = function() {
      clearTimeout(loadTimeout);
      excalidrawLoading = false;
      var loading = document.getElementById('excalidraw-loading');
      if (loading) {
        loading.innerHTML = '<div class="text-center"><i class="fa-solid fa-circle-exclamation text-2xl text-red-500 mb-2"></i><p class="text-sm text-slate-500">' + window.__('editor.excalidraw.load_failed') + '</p><button onclick="BookStarkEditor.retryLoadExcalidraw()" class="mt-2 px-3 py-1 text-sm bg-blue-600 text-white rounded-md hover:bg-blue-700">' + window.__('editor.asset.retry') + '</button></div>';
      }
    };
    document.head.appendChild(script);
  }

  function retryLoadExcalidraw() {
    excalidrawLoading = false;
    excalidrawLoaded = false;
    document.querySelectorAll('script[data-excalidraw="js"], link[data-excalidraw="css"]').forEach(function(el) { el.remove(); });
    var loading = document.getElementById('excalidraw-loading');
    if (loading) {
      loading.innerHTML = '';
    }
    loadExcalidrawAssets(function() {
      if (typeof renderDrawingContent === 'function') renderDrawingContent();
    });
  }

  function destroyExcalidraw(keepAssets) {
    if (window.BookStarkExcalidraw) {
      try { window.BookStarkExcalidraw.destroyExcalidraw(); } catch(e) {}
    }
    excalidrawRunning = false;
    drawingDirty = false;

    var container = document.getElementById('excalidraw-canvas');
    if (container) container.innerHTML = '';

    // Clean up mobile preview style
    var mp = document.getElementById('excalidraw-preview-mobile');
    if (mp) mp.remove();

    if (keepAssets === false) {
      // Remove all Excalidraw DOM artifacts (only on doc switch, not mode toggle)
      var cssLinks = document.querySelectorAll('link[data-excalidraw="css"]');
      cssLinks.forEach(function(el) { el.remove(); });
      var jsScripts = document.querySelectorAll('script[data-excalidraw="js"]');
      jsScripts.forEach(function(el) { el.remove(); });

      // Reset loaded state so it can be reloaded fresh
      excalidrawLoaded = false;
      excalidrawLoading = false;
    }

    var loading = document.getElementById('excalidraw-loading');
    if (loading) {
      loading.style.display = '';
      loading.innerHTML = '';
    }
  }

  function getDrawingContent() {
    if (window.BookStarkExcalidraw) {
      return window.BookStarkExcalidraw.getExcalidrawData();
    }
    return null;
  }

  function isDrawingDirty() {
    return drawingDirty;
  }

  function setDrawingDirty(val) {
    drawingDirty = val;
  }

  function loadDrawingData(data, options) {
    options = options || {};
    var readonly = !!options.readonly;
    var onChange = options && options.onChange;
    destroyExcalidraw(true);
    var container = document.getElementById('excalidraw-canvas');
    if (container) container.innerHTML = '';
    var loading = document.getElementById('excalidraw-loading');
    if (loading) {
      loading.style.display = '';
      loading.innerHTML = '<div class="text-sm text-slate-500">' + window.__('editor.excalidraw.loading') + '</div>';
    }
    function finishReload() {
      if (container) container.style.display = '';
      if (loading) {
        loading.innerHTML = '';
        loading.style.display = 'none';
      }
    }
    loadExcalidrawAssets(function() {
      if (BookStarkEditor._loadAborted) {
        BookStarkEditor._loadAborted = false;
        return;
      }
      if (!window.BookStarkExcalidraw) return;
      if (readonly) {
        window.BookStarkExcalidraw.initExcalidrawPreview('excalidraw-canvas', data);
        excalidrawRunning = true;
        finishReload();
        return;
      }
      var skipFirst = true;
      window.BookStarkExcalidraw.initExcalidraw('excalidraw-canvas', data, function() {
        if (skipFirst) {
          skipFirst = false;
          return;
        }
        if (onChange) onChange();
      });
      excalidrawRunning = true;
      finishReload();
    });
  }

  var excalidrawReadonlyActive = false;

  function applyExcalidrawReadonly(readonly) {
    // Kept as a no-op for API compatibility; Excalidraw now uses proper
    // initExcalidraw/initExcalidrawPreview for mode switching.
  }

  function getSpreadsheetContent() {
    return window.BookStarkUniverAdapter.getContent();
  }

  function isSpreadsheetDirty() {
    return window.BookStarkUniverAdapter.isDirty();
  }

  function setSpreadsheetDirty(dirty) {
    window.BookStarkUniverAdapter.setDirty(dirty);
  }

  function loadSpreadsheetData(data, options) {
    options = options || {};
    destroyUniver();
    var container = document.getElementById("univer-sheet");
    if (container) container.innerHTML = "";
    loadUniverAssets(function() {
      if (BookStarkEditor._loadAborted) {
        BookStarkEditor._loadAborted = false;
        return;
      }
      initUniver("univer-sheet", data, { readonly: !!options.readonly });
    });
  }

  function retryLoadUniver() {
    window.BookStarkUniverAdapter.retry();
  }

  return {
    isMobile,
    initCherry,
    initHtmlEditor,
    initHtmlPreview,
    initPreview,
    setupAutoSave,
    setupKeyboardShortcuts,
    setupUnloadWarning,
    updateSaveStatus,
    updateCharCount,
    getCherryConfig,
    showLoading,
    getCherryInstances,
    confirm2,
    prompt2,
    alert2,
    toast,
    initUniver,
    destroyUniver,
    applyUniverReadonly,
    loadUniverAssets,
    retryLoadUniver,
    getSpreadsheetContent,
    isSpreadsheetDirty,
    setSpreadsheetDirty,
    loadSpreadsheetData,
    get _univerRunning() { return univerRunning; },
    // Abort flag: set to true when navigating away during async spreadsheet load
    _loadAborted: false,
    initExcalidraw: function(containerId, elementsJson, onChange) {
      if (!window.BookStarkExcalidraw) return;
      window.BookStarkExcalidraw.initExcalidraw(containerId, elementsJson, onChange);
      excalidrawRunning = true;
    },
    initExcalidrawPreview: function(containerId, elementsJson) {
      if (!window.BookStarkExcalidraw) return;
      window.BookStarkExcalidraw.initExcalidrawPreview(containerId, elementsJson);
      excalidrawRunning = true;
    },
    applyExcalidrawReadonly: applyExcalidrawReadonly,
    destroyExcalidraw: destroyExcalidraw,
    loadExcalidrawAssets: loadExcalidrawAssets,
    retryLoadExcalidraw: retryLoadExcalidraw,
    getDrawingContent: getDrawingContent,
    isDrawingDirty: isDrawingDirty,
    setDrawingDirty: setDrawingDirty,
    loadDrawingData: loadDrawingData,
    applyExcalidrawSkeleton: function(elements, opts) {
      if (!window.BookStarkExcalidraw || !window.BookStarkExcalidraw.applySkeleton) {
        throw new Error('Excalidraw skeleton converter is not ready');
      }
      window.BookStarkExcalidraw.applySkeleton(elements, opts || {});
      drawingDirty = true;
      return getDrawingContent();
    },
    get _excalidrawRunning() { return excalidrawRunning; },
    loadMindElixirAssets: loadMindElixirAssets,
    retryLoadMindElixir: retryLoadMindElixir,
    initMindElixir: initMindElixir,
    getMindElixirData: getMindElixirData,
    destroyMindElixir: destroyMindElixir,
    loadMindElixirData: loadMindElixirData,
    exportMindElixirPng: exportMindElixirPng,
    exportMindElixirSvg: exportMindElixirSvg,
    get _mindElixirRunning() { return mindElixirInstance !== null; },
    renderContent: renderContent,
  };
})();
