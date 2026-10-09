/* NotesApp — notes + articles timeline interaction */
function NotesApp(opts) {
    this.csrf = opts.csrfToken || '';
    this.memberID = opts.memberID || 0;
    this.shareDialogType = '';
    this.shareDialogTargetId = 0;
    this.shareDialogIdentify = '';
    this.shareDialogEditToken = '';
    this.calYear = opts.calYear || new Date().getFullYear();
    this.calMonth = opts.calMonth || (new Date().getMonth() + 1);
    this.dailyCounts = opts.dailyCounts || [];
    this.taskDailyCounts = opts.taskDailyCounts || [];
    this.page = opts.page || 1;
    this.pageSize = opts.pageSize || 20;
    this.total = opts.total || 0;
    this.blogType = opts.blogType || '';
    this.composeVisibility = 0;
    this.composeLocation = null;
    this.filterPinned = null; // null | 'pinned' | 'unpinned'
    this.filterVis = null; // null | 'public' | 'private'
    this.filterCode = false;
    this.selectedDate = null;
    this.activeTab = 'notes';
    this._notesLoaded = false;
    this.articlePage = 1;
    this.articleTotal = 0;
    this.articleFilterPinned = null; // null | 'pinned' | 'unpinned'
    this.articleFilterEncrypted = null; // null | 'encrypted' | 'plain'
    this.articleFilterVis = null; // null | 'public' | 'private'
    this.articleFilterType = null; // null | 'markdown' | 'html' | 'richdoc' | 'spreadsheet' | 'drawing' | 'mindmap'
    this.articleKeyword = '';
    this.articleShareStatus = {};
    this.noteLabels = opts.noteLabels || [];
    this.articleLabels = opts.articleLabels || [];
    this.labels = this.noteLabels;
    this.filterLabel = null;
    this.tagSearchQuery = '';
    this._letterExpanded = this._loadTagGroupState('notes');
    this._tagSearchLetterExpanded = {};
    this.tagColors = ['#2563eb','#22c55e','#f59e0b','#8b5cf6','#ec4899','#14b8a6','#f97316','#06b6d4'];
    this._selectedEditorType = 'markdown';
    this._aiFloating = null;
    this._aiActiveComposer = null;
    this._aiActiveRange = null;
    this._aiStreamCtrl = null;
    this._aiViewportHandler = null;
    this._noteDraftKey = 'bookstark:notes:new-note-draft:v1:' + (this.memberID || 'anonymous');
    this.init();
    if (typeof marked !== 'undefined') {
        marked.setOptions({ breaks: true, gfm: true });
        var _noteRenderer = new marked.Renderer();
        _noteRenderer.code = function(obj) {
            var text = (typeof obj === 'object' && obj !== null) ? obj.text : obj;
            var lang = (typeof obj === 'object' && obj !== null) ? obj.lang : arguments[1];
            var escaped = (typeof escHtml === 'function' ? escHtml(text) : String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'));
            if (lang) {
                var escapedLang = typeof escAttr === 'function' ? escAttr(lang) : lang.replace(/"/g, '&quot;');
                return '<div class="code-block" data-lang="' + escapedLang + '">' +
                    '<div class="code-block-header">' +
                    '<span class="code-block-dots"><i></i><i></i><i></i></span>' +
                    '<span class="code-block-lang">' + (typeof escHtml === 'function' ? escHtml(lang) : lang) + '</span>' +
                    '<button type="button" class="code-copy-btn" title="' + window.__('note.code_copy_title') + '" aria-label="' + window.__('note.code_copy_aria') + '"><i class="fa-regular fa-copy"></i></button>' +
                    '</div>' +
                    '<pre><code>' + escaped + '</code></pre>' +
                    '</div>';
            }
            return '<pre><code>' + escaped + '</code></pre>';
        };
        marked.setOptions({ renderer: _noteRenderer });
    }
}

NotesApp.pinIconHtml = function(pinned, small) {
    var sizeAttr = small ? ' style="font-size:10px;"' : '';
    if (pinned) {
        return '<i class="fa-solid fa-thumbtack"' + sizeAttr + '></i>';
    }
    return '<span class="pin-state-icon"' + sizeAttr + '><i class="fa-solid fa-thumbtack"></i><i class="fa-solid fa-slash pin-state-slash"></i></span>';
};

NotesApp.pinnedTitleBadgeHtml = function() {
    return '<span class="topic-card-pin-badge note-title-pin-badge"><i class="fa-solid fa-thumbtack" aria-hidden="true"></i>' + window.__('note.badge.pinned') + '</span>';
};

NotesApp.noteStatePinnedBadgeHtml = function() {
    return '<span class="vis-badge pin-badge note-state-pin-badge">📌 ' + window.__('note.badge.pinned') + '</span>';
};

NotesApp.injectPinnedBadgeIntoMarkup = function(renderedHtml, pinned) {
    if (!pinned) return renderedHtml || '';
    var badge = NotesApp.pinnedTitleBadgeHtml();
    var html = renderedHtml || '';
    if (!html) return badge;
    var injected = false;
    html = html.replace(/<(p|h[1-6]|li|blockquote)(\s[^>]*)?>/i, function(match) {
        injected = true;
        return match + badge;
    });
    return injected ? html : badge + html;
};

NotesApp._syncPinnedTextBadge = function(container, pinned) {
    if (!container) return;
    var oldBadge = container.querySelector('.topic-card-pin-badge, .pin-badge');
    if (pinned && !oldBadge) {
        var firstTextBlock = container.querySelector('p, h1, h2, h3, h4, h5, h6, li, blockquote');
        (firstTextBlock || container).insertAdjacentHTML('afterbegin', NotesApp.pinnedTitleBadgeHtml());
    } else if (!pinned && oldBadge) {
        oldBadge.remove();
    }
};

NotesApp._syncNoteStatePinBadge = function(header, pinned) {
    if (!header) return;
    var oldBadge = header.querySelector('.note-state-pin-badge');
    if (pinned && !oldBadge) {
        header.insertAdjacentHTML('afterbegin', NotesApp.noteStatePinnedBadgeHtml());
    } else if (!pinned && oldBadge) {
        oldBadge.remove();
    }
};

NotesApp.prototype._runSubmitRequest = function(key, button, task) {
    if (window.BookStarkRequestLock) return BookStarkRequestLock.run(key, task, button);
    if (button && button.disabled) return null;
    if (button) {
        button.disabled = true;
        button.classList.add('is-submitting');
        button.setAttribute('aria-busy', 'true');
    }
    return Promise.resolve().then(task).then(function(value) {
        if (button) {
            button.disabled = false;
            button.classList.remove('is-submitting');
            button.setAttribute('aria-busy', 'false');
        }
        return value;
    }, function(err) {
        if (button) {
            button.disabled = false;
            button.classList.remove('is-submitting');
            button.setAttribute('aria-busy', 'false');
        }
        throw err;
    });
};

NotesApp.prototype._getCardActionButton = function(cardSelector, actionSelector) {
    var card = document.querySelector(cardSelector);
    return card ? card.querySelector(actionSelector) : null;
};

NotesApp.prototype.init = function() {
    var initialTab = window.BookStarkTabURL ? window.BookStarkTabURL.get('tab', ['notes', 'articles', 'tasks'], 'notes') : 'notes';
    this.renderCalendar();
    this.renderSidebarStats();
    this.renderMobileStrip();
    this.renderLabels();
    this.renderMobileTags();
    this._initTagInputs();
    this.bindEvents();
    if (initialTab !== this.activeTab) {
        this.switchTab(initialTab, { updateUrl: false });
    }
    this._handleUrlId();
};

NotesApp.prototype.bindEvents = function() {
    var self = this;
    // Notes search
    var searchInput = document.getElementById('noteSearchInput');
    if (searchInput) {
        this._installSearchAutofillShield(searchInput);
        searchInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') { e.preventDefault(); self.doNoteSearch(); }
        });
    }
    // Article search
    var articleSearchInput = document.getElementById('articleSearchInput');
    if (articleSearchInput) {
        articleSearchInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') { e.preventDefault(); self.doArticleSearch(); }
        });
    }
    // Compose visibility button
    var composeVisBtn = document.getElementById('composeVisBtn');
    if (composeVisBtn) {
        composeVisBtn.addEventListener('click', function() {
            self.composeVisibility = self.composeVisibility === 0 ? 1 : 0;
            composeVisBtn.innerHTML = '<i class="fa-solid ' + (self.composeVisibility === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i>';
            composeVisBtn.title = self.composeVisibility === 1 ? window.__('note.vis.public') : window.__('note.vis.private');
        });
    }
    var editorVisBtn = document.getElementById('editorVisBtn');
    if (editorVisBtn) {
        editorVisBtn.addEventListener('click', function() {
            self.composeVisibility = self.composeVisibility === 0 ? 1 : 0;
            editorVisBtn.innerHTML = '<i class="fa-solid ' + (self.composeVisibility === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i>';
            editorVisBtn.title = self.composeVisibility === 1 ? window.__('note.vis.public') : window.__('note.vis.private');
        });
    }
    var composeLocationBtn = document.getElementById('composeLocationBtn');
    if (composeLocationBtn) {
        composeLocationBtn.addEventListener('click', function() { self.captureComposeLocation(composeLocationBtn); });
    }
    var editorLocationBtn = document.getElementById('editorLocationBtn');
    if (editorLocationBtn) {
        editorLocationBtn.addEventListener('click', function() { self.captureComposeLocation(editorLocationBtn); });
    }
    // Init markdown composers (CodeMirror 6 with markdown highlight + autocomplete)
    var composeHost = document.getElementById('composeText');
    if (composeHost && window.MarkdownComposer) {
        this.composeComposer = window.MarkdownComposer.create(composeHost, {
            placeholder: composeHost.getAttribute('data-placeholder') || '',
            ariaLabel: composeHost.getAttribute('data-placeholder') || '',
            minHeight: 96,
            maxHeight: 240,
            submitOnCtrlEnter: true,
            onChange: function() { self.updateComposePreview(); self._saveComposeDraftFrom(self.composeComposer); },
            onPasteFile: function(file) { self.uploadImageFile(file, self.composeComposer); },
            onSubmit: function() { self.submitCompose(); }
        });
    }
    var editorHost = document.getElementById('editorModalText');
    if (editorHost && window.MarkdownComposer) {
        var isMobileEditor = window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
        this.editorComposer = window.MarkdownComposer.create(editorHost, {
            placeholder: editorHost.getAttribute('data-placeholder') || '',
            ariaLabel: editorHost.getAttribute('data-placeholder') || '',
            minHeight: isMobileEditor ? 270 : 320,
            maxHeight: 9999,
            onChange: function() { self.updateEditorPreview(); if (!self._editNoteId) self._saveComposeDraftFrom(self.editorComposer); },
            onPasteFile: function(file) { self.uploadImageFile(file, self.editorComposer); }
        });
    }
    this._restoreComposeDraft();
    this._initFloatingAI();
    this._bindEmojiButtons();
    // Image upload buttons
    var composeImageBtn = document.getElementById('composeImageBtn');
    var composeFileInput = document.getElementById('composeFileInput');
    if (composeImageBtn && composeFileInput) {
        composeImageBtn.addEventListener('click', function() { composeFileInput.click(); });
        composeFileInput.addEventListener('change', function(e) {
            if (e.target.files && e.target.files.length > 0) {
                self.uploadImageFile(e.target.files[0], self.composeComposer);
                e.target.value = '';
            }
        });
    }
    var editorImageBtn = document.getElementById('editorImageBtn');
    var editorFileInput = document.getElementById('editorFileInput');
    if (editorImageBtn && editorFileInput) {
        editorImageBtn.addEventListener('click', function() { editorFileInput.click(); });
        editorFileInput.addEventListener('change', function(e) {
            if (e.target.files && e.target.files.length > 0) {
                self.uploadImageFile(e.target.files[0], self.editorComposer);
                e.target.value = '';
            }
        });
    }
    // Drag-and-drop image upload
    var composeCard = document.getElementById('composeCard');
    if (composeCard) { self._setupDropZone(composeCard, function() { return self.composeComposer; }); }
    var editorBody = document.querySelector('#editorOverlay .asset-modal-body');
    if (editorBody) { self._setupDropZone(editorBody, function() { return self.editorComposer; }); }
    // Code block scroll: let vertical wheel pass through to page, prevent horizontal touch swipe from bubbling
    var notesMain = document.querySelector('.notes-main') || document.querySelector('.notes-layout');
    if (notesMain) {
        // Wheel: when cursor is on a code pre that has horizontal overflow,
        // vertical delta should scroll the page instead of being swallowed by the pre.
        // Horizontal delta is left to the browser to scroll the pre natively.
        notesMain.addEventListener('wheel', function(e) {
            var pre = e.target.closest('.note-content pre');
            if (!pre) return;
            // Only intervene if the pre has horizontal overflow and user is scrolling vertically
            if (pre.scrollWidth > pre.clientWidth && Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
                e.preventDefault();
                window.scrollBy(0, e.deltaY);
            }
        }, { passive: false });
        // Touch: prevent horizontal swipe in code blocks from triggering browser back/forward
        notesMain.addEventListener('touchstart', function(e) {
            var pre = e.target.closest('.note-content pre');
            if (pre) {
                pre._touchStartX = e.touches[0].clientX;
                pre._touchStartY = e.touches[0].clientY;
            }
        }, { passive: true });
        notesMain.addEventListener('touchmove', function(e) {
            var pre = e.target.closest('.note-content pre');
            if (!pre) return;
            var dx = e.touches[0].clientX - (pre._touchStartX || 0);
            var dy = e.touches[0].clientY - (pre._touchStartY || 0);
            if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 5) {
                e.stopPropagation();
            }
        }, { passive: true });
    }
    // Code block copy button delegation
    document.addEventListener('click', function(e) {
        var btn = e.target.closest('.code-copy-btn');
        if (!btn) return;
        e.preventDefault();
        e.stopPropagation();
        var codeBlock = btn.closest('.code-block');
        if (!codeBlock) return;
        var code = codeBlock.querySelector('code');
        if (!code) return;
        var text = code.textContent;
        var done = function() {
            BSDialog.toast(window.__('note.code_copied'), 'success');
            btn.innerHTML = '<i class="fa-solid fa-check"></i>';
            setTimeout(function() { btn.innerHTML = '<i class="fa-regular fa-copy"></i>'; }, 1500);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done).catch(function() {
                var ta = document.createElement('textarea');
                ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
                document.body.appendChild(ta); ta.select();
                try { document.execCommand('copy'); done(); } catch(ex) { BSDialog.toast(window.__('note.code_copy_failed'), 'error'); }
                document.body.removeChild(ta);
            });
        } else {
            var ta = document.createElement('textarea');
            ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
            document.body.appendChild(ta); ta.select();
            try { document.execCommand('copy'); done(); } catch(ex) { BSDialog.toast(window.__('note.code_copy_failed'), 'error'); }
            document.body.removeChild(ta);
        }
    });
};

NotesApp.prototype._installSearchAutofillShield = function(input) {
    if (!input || input.__bookstarkAutofillShield) return;
    input.__bookstarkAutofillShield = true;
    input.setAttribute('readonly', 'readonly');
    input.setAttribute('data-autofill-shield', 'true');

    var unlock = function() {
        input.removeAttribute('readonly');
    };
    var relock = function() {
        input.setAttribute('readonly', 'readonly');
    };
    var relockWhenOutside = function(e) {
        if (e && e.target === input) return;
        relock();
    };

    input.addEventListener('pointerdown', unlock, true);
    input.addEventListener('touchstart', unlock, { capture: true, passive: true });
    input.addEventListener('focus', function() {
        setTimeout(function() {
            if (document.activeElement === input) unlock();
        }, 0);
    });
    input.addEventListener('blur', relock);
    input.addEventListener('focusout', relock);
    document.addEventListener('focusin', relockWhenOutside, true);
    document.addEventListener('pointerdown', relockWhenOutside, true);
};

NotesApp.prototype._bindEmojiButtons = function() {
    var self = this;
    var composeBtn = document.getElementById('composeEmojiBtn');
    var editorBtn = document.getElementById('editorEmojiBtn');
    if (composeBtn) {
        composeBtn.addEventListener('click', function(e) {
            e.preventDefault();
            self._toggleEmojiPicker(composeBtn, self.composeComposer, 'compose');
        });
    }
    if (editorBtn) {
        editorBtn.addEventListener('click', function(e) {
            e.preventDefault();
            self._toggleEmojiPicker(editorBtn, self.editorComposer, 'editor');
        });
    }
};

NotesApp.prototype._emojiCategories = function() {
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
};

NotesApp.prototype._hideEmojiPicker = function() {
    if (this._emojiPicker) {
        this._emojiPicker.remove();
        this._emojiPicker = null;
    }
    if (this._emojiOutsideHandler) {
        document.removeEventListener('click', this._emojiOutsideHandler, true);
        this._emojiOutsideHandler = null;
    }
    document.querySelectorAll('#composeEmojiBtn.active, #editorEmojiBtn.active, #taskQuickEmojiBtn.active, #taskModalEmojiBtn.active').forEach(function(btn) {
        btn.classList.remove('active');
        btn.setAttribute('aria-expanded', 'false');
    });
};

NotesApp.prototype._toggleEmojiPicker = function(button, composer, source) {
    if (!button || !composer) return;
    if (this._emojiPicker && this._emojiPicker._source === source) {
        this._hideEmojiPicker();
        return;
    }
    this._hideEmojiPicker();

    var self = this;
    var picker = document.createElement('div');
    picker.className = 'note-emoji-picker';
    picker.setAttribute('role', 'menu');
    picker.setAttribute('aria-label', window.__('note.compose.emoji'));
    picker._source = source;

    var tabBar = document.createElement('div');
    tabBar.className = 'note-emoji-tab-bar';
    var grid = document.createElement('div');
    grid.className = 'note-emoji-grid';
    var categories = this._emojiCategories();

    function renderCategory(index) {
        tabBar.querySelectorAll('.note-emoji-tab').forEach(function(tab, i) {
            tab.classList.toggle('active', i === index);
        });
        grid.innerHTML = '';
        categories[index].icons.forEach(function(emoji) {
            var item = document.createElement('button');
            item.type = 'button';
            item.className = 'note-emoji-item';
            item.textContent = emoji;
            item.title = emoji;
            item.setAttribute('role', 'menuitem');
            item.setAttribute('aria-label', emoji);
            item.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                if (source === 'compose') {
                    var composePreview = document.getElementById('composePreview');
                    if (composePreview && composePreview.style.display === 'block') self.toggleComposePreview();
                } else {
                    var editorPreview = document.getElementById('editorPreview');
                    if (editorPreview && editorPreview.style.display === 'block') self.toggleEditorPreview();
                }
                composer.insertAtCursor(emoji);
                self._hideEmojiPicker();
            });
            grid.appendChild(item);
        });
    }

    categories.forEach(function(cat, idx) {
        if (idx > 0) {
            var sep = document.createElement('span');
            sep.className = 'note-emoji-tab-sep';
            tabBar.appendChild(sep);
        }
        var tab = document.createElement('button');
        tab.type = 'button';
        tab.className = 'note-emoji-tab';
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
    var pickerRect = picker.getBoundingClientRect();
    var left = Math.max(8, Math.min(window.innerWidth - pickerRect.width - 8, rect.left));
    var top = rect.bottom + 8;
    if (top + pickerRect.height > window.innerHeight - 8) {
        top = Math.max(8, rect.top - pickerRect.height - 8);
    }
    picker.style.left = left + 'px';
    picker.style.top = top + 'px';

    button.classList.add('active');
    button.setAttribute('aria-expanded', 'true');
    renderCategory(0);
    this._emojiPicker = picker;
    this._emojiOutsideHandler = function(e) {
        if (picker.contains(e.target) || button.contains(e.target)) return;
        self._hideEmojiPicker();
    };
    setTimeout(function() {
        document.addEventListener('click', self._emojiOutsideHandler, true);
    }, 0);
};

// ── Compose preview ──

NotesApp.prototype.toggleComposePreview = function() {
    var preview = document.getElementById('composePreview');
    var host = document.getElementById('composeText');
    var btn = document.getElementById('composePreviewBtn');
    if (!preview || !host || !btn) return;
    var isPreviewing = preview.style.display === 'block';
    if (isPreviewing) {
        preview.style.display = 'none';
        host.style.display = '';
        btn.innerHTML = '<i class="fa-solid fa-file-lines"></i>';
        btn.classList.remove('active');
    } else {
        var text = (this.composeComposer ? this.composeComposer.getValue() : '').trim();
        preview.innerHTML = text ? (typeof marked !== 'undefined' ? marked.parse(text) : escHtml(text)) : '';
        preview.style.display = 'block';
        host.style.display = 'none';
        btn.innerHTML = '<i class="fa-solid fa-pen"></i>';
        btn.classList.add('active');
    }
};

NotesApp.prototype.captureComposeLocation = function(btn) {
    if (!navigator.geolocation) {
        BSDialog.toast(window.__('note.location.unsupported'), 'warning');
        return;
    }
    var self = this;
    var targetBtn = btn || document.getElementById('composeLocationBtn');
    if (targetBtn && targetBtn.classList.contains('active')) {
        this.clearComposeLocation();
        BSDialog.toast(window.__('note.location.cleared'), 'success');
        return;
    }
    if (targetBtn) {
        targetBtn.disabled = true;
        targetBtn.classList.add('is-loading');
    }
    navigator.geolocation.getCurrentPosition(function(pos) {
        var c = pos.coords;
        self.composeLocation = {
            location_name: c.latitude.toFixed(5) + ', ' + c.longitude.toFixed(5),
            latitude: c.latitude,
            longitude: c.longitude,
            location_accuracy: c.accuracy
        };
        self._syncLocationButtons();
        BSDialog.toast(window.__('note.location.captured'), 'success');
    }, function() {
        BSDialog.toast(window.__('note.location.failed'), 'error');
        self._syncLocationButtons();
    }, { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 });
};

NotesApp.prototype._syncLocationButtons = function() {
    var active = !!this.composeLocation;
    ['composeLocationBtn', 'editorLocationBtn'].forEach(function(id) {
        var btn = document.getElementById(id);
        if (!btn) return;
        btn.disabled = false;
        btn.classList.remove('is-loading');
        btn.classList.toggle('active', active);
        btn.title = active ? window.__('note.location.remove') : window.__('note.compose.location');
    });
};

NotesApp.prototype.clearComposeLocation = function() {
    this.composeLocation = null;
    this._syncLocationButtons();
};

NotesApp.prototype._appendLocationPayload = function(body) {
    if (!this.composeLocation) return body;
    body.location_name = this.composeLocation.location_name || '';
    body.latitude = this.composeLocation.latitude;
    body.longitude = this.composeLocation.longitude;
    body.location_accuracy = this.composeLocation.location_accuracy;
    return body;
};

NotesApp.prototype.updateComposePreview = function() {
    var preview = document.getElementById('composePreview');
    if (!preview || !this.composeComposer || preview.style.display !== 'block') return;
    var text = this.composeComposer.getValue().trim();
    preview.innerHTML = text ? (typeof marked !== 'undefined' ? marked.parse(text) : escHtml(text)) : '';
};

NotesApp.prototype.toggleEditorPreview = function() {
    var preview = document.getElementById('editorPreview');
    var host = document.getElementById('editorModalText');
    var btn = document.getElementById('editorPreviewBtn');
    if (!preview || !host || !btn) return;
    var isPreviewing = preview.style.display === 'block';
    if (isPreviewing) {
        preview.style.display = 'none';
        host.style.display = '';
        btn.innerHTML = '<i class="fa-solid fa-file-lines"></i>';
        btn.classList.remove('active');
    } else {
        var text = (this.editorComposer ? this.editorComposer.getValue() : '').trim();
        preview.innerHTML = text ? (typeof marked !== 'undefined' ? marked.parse(text) : escHtml(text)) : '';
        preview.style.display = 'block';
        host.style.display = 'none';
        btn.innerHTML = '<i class="fa-solid fa-pen"></i>';
        btn.classList.add('active');
    }
};

NotesApp.prototype.updateEditorPreview = function() {
    var preview = document.getElementById('editorPreview');
    if (!preview || !this.editorComposer || preview.style.display !== 'block') return;
    var text = this.editorComposer.getValue().trim();
    preview.innerHTML = text ? (typeof marked !== 'undefined' ? marked.parse(text) : escHtml(text)) : '';
};

// ── Tab switching ──

NotesApp.prototype.switchTab = function(tab, opts) {
    opts = opts || {};
    if (this.activeTab === tab) {
        if (opts.updateUrl !== false && window.BookStarkTabURL) window.BookStarkTabURL.set('tab', tab);
        return;
    }
    this.activeTab = tab;
    if (opts.updateUrl !== false && window.BookStarkTabURL) window.BookStarkTabURL.set('tab', tab);
    // Update tab buttons
    document.querySelectorAll('#mainTabs .main-tab').forEach(function(t) {
        t.classList.toggle('active', t.dataset.tab === tab);
    });
    // Toggle tab content
    document.querySelectorAll('.tab-content').forEach(function(el) {
        el.classList.toggle('active', el.dataset.tab === tab);
    });
    // Toggle tab search areas
    document.querySelectorAll('.tab-search').forEach(function(el) {
        el.style.display = el.dataset.tab === tab ? '' : 'none';
    });
    var isTasksTab = tab === 'tasks';
    var notesSidebarPanel = document.getElementById('notesSidebarPanel');
    if (notesSidebarPanel) notesSidebarPanel.style.display = '';
    var sidebarTags = document.getElementById('sidebarTags');
    if (sidebarTags) sidebarTags.style.display = isTasksTab ? 'none' : '';
    var mobileFilterBtn = document.getElementById('mobileFilterBtn');
    if (mobileFilterBtn) mobileFilterBtn.style.display = '';
    var noteFab = document.querySelector('.mobile-fab');
    if (noteFab) noteFab.style.display = isTasksTab ? 'none' : '';
    var taskFabActions = document.getElementById('tasksFabActions');
    if (taskFabActions) taskFabActions.style.display = isTasksTab ? '' : 'none';
    if (!isTasksTab) {
        // Switch labels by tab
        this.labels = tab === 'notes' ? this.noteLabels : this.articleLabels;
        this.filterLabel = null;
        this.tagSearchQuery = '';
        this._letterExpanded = this._loadTagGroupState(tab);
        this._tagSearchLetterExpanded = {};
        document.querySelectorAll('[data-note-tag-search]').forEach(function(input) {
            input.value = '';
        });
        this.renderLabels();
        this.renderMobileTags();
        this.updateLabelUI();
        this.updateMobileFilterBtn();
    }
    // Update total count label
    var countEl = document.getElementById('totalCount');
    if (countEl) {
        countEl.style.display = '';
        if (isTasksTab) {
            if (window.BookStarkTasks && typeof window.BookStarkTasks.updateCountLabel === 'function') {
                window.BookStarkTasks.updateCountLabel();
            } else {
                countEl.textContent = '共 0 个';
            }
        } else {
            countEl.textContent = window.__('note.total_count').replace('{n}', tab === 'notes' ? this.total : this.articleTotal);
        }
    }
    if (tab === 'articles' && !this._articlesLoaded) {
        this._articlesLoaded = true;
        this.loadArticles();
    } else if (tab === 'notes' && !this._notesLoaded) {
        this.loadNotes();
    } else if (isTasksTab && window.BookStarkTasks && typeof window.BookStarkTasks.setDate === 'function') {
        window.BookStarkTasks.setDate(this.selectedDate, { reload: true });
        if (typeof window.BookStarkTasks.updateFilterButton === 'function') {
            window.BookStarkTasks.updateFilterButton();
        }
    }
};

// ── Notes filters ──

NotesApp.prototype.clearFilters = function() {
    this.filterPinned = null;
    this.filterVis = null;
    this.filterCode = false;
    this.filterLabel = null;
    this.selectedDate = null;
    this.page = 1;
    this.renderCalendar();
    this.renderMobileStrip();
    this._updateDateChip();
    this.updateFilterUI();
    this.updateLabelUI();
    this.loadNotes();
};

NotesApp.prototype.togglePinnedFilter = function() {
    // null → pinned → unpinned → null
    if (this.filterPinned === null) this.filterPinned = 'pinned';
    else if (this.filterPinned === 'pinned') this.filterPinned = 'unpinned';
    else this.filterPinned = null;
    this.page = 1;
    this.updateFilterUI();
    this.loadNotes();
};

NotesApp.prototype.toggleVisFilter = function() {
    // null → public → private → null
    if (this.filterVis === null) this.filterVis = 'public';
    else if (this.filterVis === 'public') this.filterVis = 'private';
    else this.filterVis = null;
    this.page = 1;
    this.updateFilterUI();
    this.loadNotes();
};

NotesApp.prototype.toggleCodeFilter = function() {
    this.filterCode = !this.filterCode;
    this.page = 1;
    this.updateFilterUI();
    this.loadNotes();
};

NotesApp.prototype.updateFilterUI = function() {
    var chipAll = document.getElementById('chipAll');
    var chipPinned = document.getElementById('chipPinned');
    var chipVis = document.getElementById('chipVis');
    var chipCode = document.getElementById('chipCode');
    var hasFilter = this.filterPinned !== null || this.filterVis !== null || this.filterCode || this.filterLabel !== null || this.selectedDate !== null;
    if (chipAll) chipAll.classList.toggle('active', !hasFilter);
    if (chipPinned) {
        var isPinnedActive = this.filterPinned !== null;
        chipPinned.classList.toggle('active', isPinnedActive);
        if (this.filterPinned === 'pinned') {
            chipPinned.innerHTML = NotesApp.pinIconHtml(true, true) + ' ' + window.__('note.filter.pinned');
        } else if (this.filterPinned === 'unpinned') {
            chipPinned.innerHTML = NotesApp.pinIconHtml(false, true) + ' ' + window.__('note.filter.unpinned');
        } else {
            chipPinned.innerHTML = NotesApp.pinIconHtml(true, true) + ' ' + window.__('note.filter.pinned');
        }
    }
    if (chipVis) {
        var isVisActive = this.filterVis !== null;
        chipVis.classList.toggle('active', isVisActive);
        if (this.filterVis === 'public') {
            chipVis.innerHTML = '<i class="fa-solid fa-eye" style="font-size:10px;"></i> ' + window.__('note.filter.public');
        } else if (this.filterVis === 'private') {
            chipVis.innerHTML = '<i class="fa-solid fa-eye-slash" style="font-size:10px;"></i> ' + window.__('note.filter.private');
        } else {
            chipVis.innerHTML = '<i class="fa-solid fa-eye" style="font-size:10px;"></i> ' + window.__('note.filter.public');
        }
    }
    if (chipCode) {
        chipCode.classList.toggle('active', !!this.filterCode);
        chipCode.innerHTML = '<i class="fa-solid fa-code" style="font-size:10px;"></i> ' + window.__('note.filter.code');
    }
};

// ── Article filters ──

NotesApp.prototype.clearArticleFilters = function() {
    this.articleFilterPinned = null;
    this.articleFilterEncrypted = null;
    this.articleFilterVis = null;
    this.articleFilterType = null;
    this.articlePage = 1;
    this.updateArticleFilterUI();
    this.loadArticles();
};

NotesApp.prototype.toggleArticlePinnedFilter = function() {
    // null → pinned → unpinned → null
    if (this.articleFilterPinned === null) this.articleFilterPinned = 'pinned';
    else if (this.articleFilterPinned === 'pinned') this.articleFilterPinned = 'unpinned';
    else this.articleFilterPinned = null;
    this.articlePage = 1;
    this.updateArticleFilterUI();
    this.loadArticles();
};

NotesApp.prototype.toggleEncryptedFilter = function() {
    // null → encrypted → plain → null
    if (this.articleFilterEncrypted === null) this.articleFilterEncrypted = 'encrypted';
    else if (this.articleFilterEncrypted === 'encrypted') this.articleFilterEncrypted = 'plain';
    else this.articleFilterEncrypted = null;
    this.articlePage = 1;
    this.updateArticleFilterUI();
    this.loadArticles();
};

NotesApp.prototype.toggleArticleVisFilter = function() {
    if (this.articleFilterVis === null) this.articleFilterVis = 'public';
    else if (this.articleFilterVis === 'public') this.articleFilterVis = 'private';
    else this.articleFilterVis = null;
    this.articlePage = 1;
    this.updateArticleFilterUI();
    this.loadArticles();
};

NotesApp.prototype._editorTypes = ['markdown', 'html', 'richdoc', 'spreadsheet', 'presentation', 'drawing', 'mindmap'];
NotesApp.prototype._editorTypeLabels = {markdown:'Markdown',html:'HTML',richdoc:window.__('note.article.type.richdoc.label'),spreadsheet:window.__('note.type.spreadsheet'),presentation:window.__('note.type.presentation'),drawing:window.__('note.type.drawing'),mindmap:window.__('note.type.mindmap')};
NotesApp.prototype._editorTypeIcons = {markdown:'fa-file-lines',html:'fa-code',richdoc:'fa-file-word',spreadsheet:'fa-table',presentation:'fa-display',drawing:'fa-pen-fancy',mindmap:'fa-diagram-project'};

NotesApp.prototype.toggleArticleTypeFilter = function() {
    var types = this._editorTypes;
    if (this.articleFilterType === null) {
        this.articleFilterType = types[0];
    } else {
        var idx = types.indexOf(this.articleFilterType);
        this.articleFilterType = idx < types.length - 1 ? types[idx + 1] : null;
    }
    this.articlePage = 1;
    this.updateArticleFilterUI();
    this.loadArticles();
};

NotesApp.prototype.hasArticleFilter = function() {
    return this.articleFilterPinned !== null || this.articleFilterEncrypted !== null || this.articleFilterVis !== null || this.articleFilterType !== null;
};

NotesApp.prototype.updateArticleFilterUI = function() {
    var chipAll = document.getElementById('articleChipAll');
    var chipPinned = document.getElementById('articleChipPinned');
    var chipEncrypted = document.getElementById('articleChipEncrypted');
    var chipVis = document.getElementById('articleChipVis');
    var chipType = document.getElementById('articleChipType');
    var hasFilter = this.hasArticleFilter();
    if (chipAll) chipAll.classList.toggle('active', !hasFilter);
    if (chipPinned) {
        chipPinned.classList.toggle('active', this.articleFilterPinned !== null);
        if (this.articleFilterPinned === 'pinned') {
            chipPinned.innerHTML = NotesApp.pinIconHtml(true, true) + ' ' + window.__('note.filter.pinned');
        } else if (this.articleFilterPinned === 'unpinned') {
            chipPinned.innerHTML = NotesApp.pinIconHtml(false, true) + ' ' + window.__('note.filter.unpinned');
        } else {
            chipPinned.innerHTML = NotesApp.pinIconHtml(true, true) + ' ' + window.__('note.filter.pinned');
        }
    }
    if (chipEncrypted) {
        chipEncrypted.classList.toggle('active', this.articleFilterEncrypted !== null);
        if (this.articleFilterEncrypted === 'encrypted') {
            chipEncrypted.innerHTML = '<i class="fa-solid fa-lock" style="font-size:10px;"></i> ' + window.__('note.filter.encrypted');
        } else if (this.articleFilterEncrypted === 'plain') {
            chipEncrypted.innerHTML = '<i class="fa-solid fa-lock-open" style="font-size:10px;"></i> ' + window.__('note.filter.unencrypted');
        } else {
            chipEncrypted.innerHTML = '<i class="fa-solid fa-lock" style="font-size:10px;"></i> ' + window.__('note.filter.encrypted');
        }
    }
    if (chipVis) {
        chipVis.classList.toggle('active', this.articleFilterVis !== null);
        if (this.articleFilterVis === 'public') {
            chipVis.innerHTML = '<i class="fa-solid fa-eye" style="font-size:10px;"></i> ' + window.__('note.filter.public');
        } else if (this.articleFilterVis === 'private') {
            chipVis.innerHTML = '<i class="fa-solid fa-eye-slash" style="font-size:10px;"></i> ' + window.__('note.filter.private');
        } else {
            chipVis.innerHTML = '<i class="fa-solid fa-eye" style="font-size:10px;"></i> ' + window.__('note.filter.public');
        }
    }
    if (chipType) {
        chipType.classList.toggle('active', this.articleFilterType !== null);
        if (this.articleFilterType) {
            var icon = this._editorTypeIcons[this.articleFilterType] || 'fa-file';
            var label = this._editorTypeLabels[this.articleFilterType] || this.articleFilterType;
            chipType.innerHTML = '<i class="fa-solid ' + icon + '" style="font-size:10px;"></i> ' + label;
        } else {
            chipType.innerHTML = '<i class="fa-solid fa-file" style="font-size:10px;"></i> ' + window.__('note.filter.type');
        }
    }
};

// ── Notes loading ──

NotesApp.prototype.doNoteSearch = function() {
    this.page = 1;
    this.loadNotes();
};

NotesApp.prototype.doArticleSearch = function() {
    var input = document.getElementById('articleSearchInput');
    this.articleKeyword = input ? input.value.trim() : '';
    this.articlePage = 1;
    this.loadArticles();
};

NotesApp.prototype.loadNotes = function(callback) {
    var self = this;
    var params = new URLSearchParams();
    params.set('page', this.page);
    params.set('page_size', this.pageSize);
    params.set('type', 'note');
    var noteSearchInput = document.getElementById('noteSearchInput');
    var keyword = noteSearchInput ? noteSearchInput.value.trim() : '';
    if (keyword) params.set('keyword', keyword);
    if (this.selectedDate) params.set('date', this.selectedDate);
    if (this.filterLabel) params.set('label', this.filterLabel);
    if (this.filterPinned === 'pinned') params.set('pinned', '1');
    else if (this.filterPinned === 'unpinned') params.set('pinned', '0');
    if (this.filterVis === 'public') params.set('visibility', '1');
    else if (this.filterVis === 'private') params.set('visibility', '0');
    if (this.filterCode) params.set('has_code', '1');

    this._showNotesSkeleton();
    if (window.BookStarkState) {
        BookStarkState.loadingTimeout('notes:list', document.getElementById('notesTimeline'), {
            type: 'error',
            title: '加载超时',
            message: '笔记列表暂时没有响应',
            actionText: '重试',
            onAction: function() { self.loadNotes(callback); }
        });
    }
    fetchWithCurrentCSRF('/api/blogs?' + params.toString(), {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); }).then(function(data) {
        if (window.BookStarkState) BookStarkState.clear('notes:list');
        if (data.code === 0) {
            var list = (data.data && Array.isArray(data.data)) ? data.data : (data.data && data.data.list ? data.data.list : []);
            self._notesLoaded = true;
            self.renderTimeline(list);
            self.total = data.total || 0;
            var countEl = document.getElementById('totalCount');
            if (countEl && self.activeTab === 'notes') countEl.textContent = window.__('note.total_count').replace('{n}', self.total);
            var tp = Math.ceil(self.total / self.pageSize);
            if (typeof renderPagination === 'function') renderPagination('notesPagination', self.page, tp, function(p) { notesApp.page = p; notesApp.loadNotes(); });
        } else {
            self._renderNotesLoadError(data && data.message);
        }
        if (callback) callback();
    }).catch(function(err) {
        if (window.BookStarkState) BookStarkState.clear('notes:list');
        console.error('loadNotes failed:', err);
        self._renderNotesLoadError();
        if (callback) callback();
    });
};

NotesApp.prototype._renderNotesLoadError = function(message) {
    var container = document.getElementById('notesTimeline');
    if (!container) return;
    if (window.BookStarkState) {
        var self = this;
        BookStarkState.render(container, {
            type: 'error',
            title: '笔记加载失败',
            message: message || '请检查网络后重试',
            actionText: '重试',
            onAction: function() { self.loadNotes(); }
        });
        return;
    }
    container.innerHTML = '<div style="text-align:center;padding:60px 20px;color:var(--color-gray-400);"><div style="font-size:42px;margin-bottom:16px;"><i class="fa-solid fa-triangle-exclamation"></i></div><div>' + escHtml(message || '加载失败，请稍后重试') + '</div></div>';
};

// ── Articles loading ──

NotesApp.prototype.loadArticles = function(callback) {
    var self = this;
    var params = new URLSearchParams();
    params.set('page', this.articlePage);
    params.set('page_size', this.pageSize);
    params.set('type', 'article');
    if (this.articleKeyword) params.set('keyword', this.articleKeyword);
    if (this.selectedDate) params.set('date', this.selectedDate);
    if (this.filterLabel) params.set('label', this.filterLabel);
    if (this.articleFilterPinned === 'pinned') params.set('pinned', '1');
    else if (this.articleFilterPinned === 'unpinned') params.set('pinned', '0');
    if (this.articleFilterEncrypted === 'encrypted') params.set('encrypted', '1');
    else if (this.articleFilterEncrypted === 'plain') params.set('encrypted', '0');
    if (this.articleFilterVis === 'public') params.set('visibility', '1');
    else if (this.articleFilterVis === 'private') params.set('visibility', '0');
    if (this.articleFilterType) params.set('editor_type', this.articleFilterType);

    this._showArticlesSkeleton();
    if (window.BookStarkState) {
        BookStarkState.loadingTimeout('notes:articles', document.getElementById('articlesList'), {
            type: 'error',
            title: '加载超时',
            message: '文章列表暂时没有响应',
            actionText: '重试',
            onAction: function() { self.loadArticles(callback); }
        });
    }
    fetchWithCurrentCSRF('/api/blogs?' + params.toString(), {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); }).then(function(data) {
        if (window.BookStarkState) BookStarkState.clear('notes:articles');
        if (data.code === 0) {
            var list = (data.data && Array.isArray(data.data)) ? data.data : (data.data && data.data.list ? data.data.list : []);
            self.loadArticleShareStatus(list).then(function() {
                self.articleTotal = data.total || 0;
                var countEl = document.getElementById('totalCount');
                if (countEl && self.activeTab === 'articles') countEl.textContent = window.__('note.total_count').replace('{n}', self.articleTotal);
                self.renderArticlesList(list);
                var atp = Math.ceil(self.articleTotal / self.pageSize);
                if (typeof renderPagination === 'function') renderPagination('articlesPagination', self.articlePage, atp, function(p) { notesApp.articlePage = p; notesApp.loadArticles(); });
                if (callback) callback();
            });
        } else {
            self._renderArticlesLoadError(data && data.message);
            if (callback) callback();
        }
    }).catch(function(err) {
        if (window.BookStarkState) BookStarkState.clear('notes:articles');
        console.error('loadArticles failed:', err);
        self._renderArticlesLoadError();
        if (callback) callback();
    });
};

NotesApp.prototype._renderArticlesLoadError = function(message) {
    var container = document.getElementById('articlesList');
    if (!container) return;
    if (window.BookStarkState) {
        var self = this;
        BookStarkState.render(container, {
            type: 'error',
            title: '文章加载失败',
            message: message || '请检查网络后重试',
            actionText: '重试',
            onAction: function() { self.loadArticles(); }
        });
        return;
    }
    container.innerHTML = '<div style="text-align:center;padding:60px 20px;color:var(--color-gray-400);"><div style="font-size:42px;margin-bottom:16px;"><i class="fa-solid fa-triangle-exclamation"></i></div><div>' + escHtml(message || '加载失败，请稍后重试') + '</div></div>';
};

NotesApp.prototype.loadArticleShareStatus = function(items) {
    var ids = items.map(function(b) { return b.blog_id; });
    if (!ids.length) { this.articleShareStatus = {}; return Promise.resolve(); }
    var self = this;
    return fetchWithCurrentCSRF('/api/shares/status?type=blog&ids=' + ids.join(',')).then(function(r) { return r.json(); }).then(function(d) {
        self.articleShareStatus = d.data || {};
    }).catch(function() { self.articleShareStatus = {}; });
};

// ── Note card rendering ──

NotesApp.renderNoteCard = function(b, showActions) {
    var card = document.createElement('div');
    card.className = 'note-card' + (b.is_pinned ? ' pinned' : '');
    card.dataset.id = b.blog_id;
    var isInteractive = showActions !== false;

    var visText = b.visibility === 1 ? window.__('note.badge.public') : window.__('note.badge.private');
    var locationHtml = NotesApp._buildLocationHtml(b);
    var pinnedBadge = b.is_pinned ? NotesApp.noteStatePinnedBadgeHtml() : '';
    var header = '<div class="note-header">' + pinnedBadge +
        '<span class="vis-badge vis-state">' + visText + '</span>' +
        locationHtml + (isInteractive ?
        '<button class="note-copy-btn" title="' + window.__('note.action.copy') + '" aria-label="' + window.__('note.action.copy') + '" onclick="event.stopPropagation();notesApp.copyNoteContent(' + b.blog_id + ')"><i class="fa-regular fa-copy"></i></button>' +
        '<button class="note-fullscreen-btn" title="' + window.__('note.action.fullscreen') + '" aria-label="' + window.__('note.action.fullscreen') + '" onclick="event.stopPropagation();notesApp.openNoteViewer(' + b.blog_id + ')"><i class="fa-solid fa-expand"></i></button>' : '') +
        '</div>';

    var text = b.content_preview || b.blog_title || '';
    var html = typeof marked !== 'undefined'
        ? sanitizeRenderedHTML(marked.parse(text))
        : escHtml(text);
    var content = '<div class="note-content">' + html + '</div>';

    var tags = '';
    if (b.labels && b.labels.length) {
        tags = '<div class="note-tags">' + (isInteractive
            ? NotesApp._buildTagBadgesHtml(b.blog_id, b.labels)
            : NotesApp._buildReadonlyTagBadgesHtml(b.labels)) + '</div>';
    }

    var dateStr = b.create_time ? b.create_time.substring(0, 10) : '';
    var actions = '';
    if (showActions !== false) {
        var pinLabel = b.is_pinned ? window.__('note.action.unpin') : window.__('note.action.pin');
        actions = '<div class="note-actions">' +
            '<button class="row-action" title="' + window.__('note.action.edit') + '" aria-label="' + window.__('note.action.edit') + '" onclick="notesApp.editNote(' + b.blog_id + ')"><i class="fa-solid fa-pen"></i></button>' +
            '<button class="row-action note-pin-action pin-action' + (b.is_pinned ? ' is-pinned' : '') + '" title="' + pinLabel + '" aria-label="' + pinLabel + '" aria-pressed="' + (b.is_pinned ? 'true' : 'false') + '" onclick="notesApp.togglePin(' + b.blog_id + ')">' + NotesApp.pinIconHtml(!!b.is_pinned) + '</button>' +
            '<button class="row-action vis-toggle" title="' + (b.visibility === 1 ? window.__('note.action.set_private') : window.__('note.action.set_public')) + '" aria-label="' + window.__('note.action.visibility') + '" onclick="notesApp.toggleVisibility(' + b.blog_id + ')"><i class="fa-solid ' + (b.visibility === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i></button>' +
            '<button class="row-action del" title="' + window.__('note.action.delete') + '" aria-label="' + window.__('note.action.delete') + '" onclick="notesApp.deleteNote(' + b.blog_id + ')"><i class="fa-solid fa-trash-can"></i></button>' +
            '</div>';
    }

    card.innerHTML = header + content + tags +
        '<div class="note-footer">' + actions + '<span class="note-time"><i class="fa-regular fa-clock" style="font-size:11px;margin-right:3px;"></i>' + dateStr + '</span></div>';
    if (window.notesApp && typeof window.notesApp.prepareNoteCardImages === 'function') {
        window.notesApp.prepareNoteCardImages(card);
    }
    return card;
};

NotesApp.renderShareCommentsBlock = function(identify, extraClass) {
    var safeKey = String(identify || '').replace(/[^a-zA-Z0-9_-]/g, '-');
    var rootID = 'note-comments-' + safeKey;
    var disclosure = document.createElement('div');
    disclosure.className = 'note-comments-disclosure';
    disclosure.innerHTML =
        '<button type="button" class="note-comments-toggle" data-share-comments-toggle aria-controls="' + rootID + '" aria-expanded="false">' +
            '<i class="fa-regular fa-comments"></i><span>' + window.__('share_comments.title') + '</span>' +
        '</button>';
    var section = document.createElement('section');
    section.id = rootID;
    section.className = 'share-comments note-inline-comments' + (extraClass ? ' ' + extraClass : '');
    section.setAttribute('data-share-identify', identify || '');
    section.setAttribute('data-comments-lazy', '1');
    section.setAttribute('data-comments-hydrated', '0');
    section.setAttribute('aria-label', window.__('share_comments.title'));
    section.hidden = true;
    disclosure.appendChild(section);
    return disclosure;
};

NotesApp.prototype.prepareNoteCardImages = function(card) {
    if (!card) return;
    var images = card.querySelectorAll('.note-content img');
    Array.prototype.forEach.call(images, function(img) {
        img.classList.add('note-image-lightbox-trigger');
        img.setAttribute('tabindex', '0');
        img.setAttribute('role', 'button');
        img.setAttribute('aria-label', window.__('note.compose.image') || '查看图片');
        img.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            if (window.notesApp) window.notesApp.openImageLightbox(img);
        });
        img.addEventListener('keydown', function(e) {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            e.preventDefault();
            e.stopPropagation();
            if (window.notesApp) window.notesApp.openImageLightbox(img);
        });
    });
};

NotesApp._buildLocationHtml = function(b) {
    if (!b || b.latitude === undefined || b.latitude === null || b.longitude === undefined || b.longitude === null) return '';
    var lat = Number(b.latitude);
    var lng = Number(b.longitude);
    if (!isFinite(lat) || !isFinite(lng)) return '';
    var name = b.location_name || (lat.toFixed(5) + ', ' + lng.toFixed(5));
    var href = 'https://www.openstreetmap.org/?mlat=' + encodeURIComponent(lat) + '&mlon=' + encodeURIComponent(lng) + '#map=15/' + encodeURIComponent(lat) + '/' + encodeURIComponent(lng);
    return '<a class="note-location" href="' + href + '" target="_blank" rel="noopener" title="' + escAttr(name) + '" onclick="event.stopPropagation();"><i class="fa-solid fa-location-dot"></i>' + escHtml(name) + '</a>';
};

NotesApp.prototype.renderTimeline = function(blogs) {
    var container = document.getElementById('notesTimeline');
    if (!container) return;
    container.innerHTML = '';
    if (!blogs || blogs.length === 0) {
        if (window.BookStarkState) {
            BookStarkState.render(container, { type: 'empty', icon: 'fa-note-sticky', title: window.__('note.empty.notes') });
            return;
        }
        container.innerHTML = '<div style="text-align:center;padding:60px 20px;color:var(--color-gray-400);"><div style="font-size:42px;margin-bottom:16px;"><i class="fa-solid fa-note-sticky"></i></div><div>' + window.__('note.empty.notes') + '</div></div>';
        return;
    }
    blogs.forEach(function(b) {
        container.appendChild(NotesApp.renderNoteCard(b));
    });
};

// ── Article card rendering ──

NotesApp.prototype.renderArticleCard = function(b) {
    var card = document.createElement('div');
    card.className = 'article-card';
    card.dataset.id = b.blog_id;

    var isShared = !!this.articleShareStatus[b.blog_id];
    var time = b.modify_time && b.modify_time.indexOf('0001') < 0 ? b.modify_time.substring(0, 16).replace('T', ' ') : (b.create_time ? b.create_time.substring(0, 16).replace('T', ' ') : '');

    var header = '<div class="article-card-header">' +
        '<div class="article-title-line">' +
        (b.is_pinned ? NotesApp.pinnedTitleBadgeHtml() : '') +
        '<a href="javascript:void(0)" class="article-title" onclick="notesApp.goArticleEdit(\'' + escAttr(b.blog_identify || '') + '\',' + b.blog_id + ')">' + escHtml(b.blog_title || window.__('note.article.no_title')) + '</a>' +
        '</div>' +
        '</div>';

    var metaItems = '<span class="article-meta-item"><i class="fa-regular fa-clock"></i> ' + time + '</span>';

    var tags = NotesApp._buildArticleStatusBadgesHtml({
        pinned: !!b.is_pinned,
        visibilityText: b.visibility === 1 ? window.__('note.badge.public') : window.__('note.badge.private'),
        hasPassword: !!b.has_password,
        editorTypeLabel: b.editor_type ? ({markdown:'Markdown',richdoc:window.__('note.article.type.richdoc.label'),spreadsheet:window.__('note.article.type.spreadsheet.label'),presentation:window.__('note.article.type.presentation.label'),drawing:window.__('note.article.type.drawing.label'),html:'HTML',mindmap:window.__('note.article.type.mindmap.label')}[b.editor_type] || b.editor_type) : ''
    });
    if (b.labels && b.labels.length) {
        tags += NotesApp._buildTagBadgesHtml(b.blog_id, b.labels);
    }

    var actions = '<div class="article-actions">' +
        '<button class="row-action article-pin-action pin-action' + (b.is_pinned ? ' is-pinned' : '') + '" title="' + (b.is_pinned ? window.__('note.action.unpin') : window.__('note.action.pin')) + '" aria-label="' + (b.is_pinned ? window.__('note.action.unpin') : window.__('note.action.pin')) + '" aria-pressed="' + (b.is_pinned ? 'true' : 'false') + '" onclick="notesApp.toggleArticlePin(' + b.blog_id + ')">' + NotesApp.pinIconHtml(!!b.is_pinned) + '</button>' +
        '<button class="row-action vis-toggle" title="' + (b.visibility === 1 ? window.__('note.action.set_private') : window.__('note.action.set_public')) + '" aria-label="' + window.__('note.action.visibility') + '" onclick="notesApp.toggleArticleVisibility(' + b.blog_id + ')"><i class="fa-solid ' + (b.visibility === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i></button>' +
        '<button class="row-action" title="' + window.__('note.action.settings') + '" aria-label="' + window.__('note.action.settings') + '" onclick="notesApp.openArticleSettingModal(' + b.blog_id + ')"><i class="fa-solid fa-gear"></i></button>' +
        '<button class="row-action del" title="' + window.__('note.action.delete') + '" aria-label="' + window.__('note.action.delete') + '" onclick="notesApp.deleteArticle(' + b.blog_id + ')"><i class="fa-solid fa-trash-can"></i></button>' +
        '</div>';
    var excerpt = b.has_password ? window.__('note.article.encrypted_desc') : (b.content_preview || '');
    card.dataset.desc = b.blog_desc || '';

    card.innerHTML =
        header +
        '<div class="article-excerpt">' + escHtml(excerpt) + '</div>' +
        '<div class="article-footer">' + actions + metaItems + '</div>' +
        '<div class="article-tags">' + tags + '</div>';

    return card;
};

NotesApp._buildArticleStatusBadgesHtml = function(opts) {
    opts = opts || {};
    return '<span class="vis-badge vis-state article-state-badge">' + escHtml(opts.visibilityText || window.__('note.badge.private')) + '</span>' +
        (opts.hasPassword ? '<span class="vis-badge article-state-badge"><i class="fa-solid fa-lock" style="font-size:10px;"></i> ' + window.__('note.badge.encrypted') + '</span>' : '') +
        (opts.editorTypeLabel ? '<span class="vis-badge editor-type-chip article-state-badge">' + escHtml(opts.editorTypeLabel) + '</span>' : '');
};

NotesApp._ensureArticleTagsRow = function(card) {
    var row = card ? card.querySelector('.article-tags') : null;
    if (!card || row) return row;
    row = document.createElement('div');
    row.className = 'article-tags';
    var footer = card.querySelector('.article-footer');
    if (footer && footer.nextSibling) {
        card.insertBefore(row, footer.nextSibling);
    } else {
        card.appendChild(row);
    }
    return row;
};

// ── Skeleton helpers ──

NotesApp.prototype._notesSkeletonHtml = '';
NotesApp.prototype._articlesSkeletonHtml = '';

NotesApp.prototype._showNotesSkeleton = function() {
    var container = document.getElementById('notesTimeline');
    if (!container) return;
    if (!this._notesSkeletonHtml) {
        this._notesSkeletonHtml = container.innerHTML;
    }
    container.innerHTML = this._notesSkeletonHtml;
};

NotesApp.prototype._showArticlesSkeleton = function() {
    var loading = document.getElementById('articlesLoading');
    var list = document.getElementById('articlesList');
    if (loading && list) {
        if (!this._articlesSkeletonHtml) {
            this._articlesSkeletonHtml = loading.innerHTML;
        }
        list.innerHTML = this._articlesSkeletonHtml;
    }
};

NotesApp.prototype.renderArticlesList = function(blogs) {
    var container = document.getElementById('articlesList');
    if (!container) return;
    container.innerHTML = '';
    if (!blogs || blogs.length === 0) {
        if (window.BookStarkState) {
            BookStarkState.render(container, { type: 'empty', icon: 'fa-file-lines', title: window.__('note.empty.articles') });
            return;
        }
        container.innerHTML = '<div style="text-align:center;padding:60px 20px;color:var(--color-gray-400);"><div style="font-size:42px;margin-bottom:16px;"><i class="fa-regular fa-file-lines"></i></div><div>' + window.__('note.empty.articles') + '</div></div>';
        return;
    }
    var self = this;
    blogs.forEach(function(b) {
        container.appendChild(self.renderArticleCard(b));
    });
    if (this._pendingHighlightSelector) {
        var sel = this._pendingHighlightSelector;
        this._pendingHighlightSelector = null;
        setTimeout(function() {
            var card = document.querySelector(sel);
            if (card) {
                card.scrollIntoView({ behavior: 'smooth', block: 'center' });
                card.classList.add('search-highlight');
                setTimeout(function() { card.classList.remove('search-highlight'); }, 5000);
            }
        }, 150);
    }
};

// ── Compose / submit ──

NotesApp.prototype._readComposeDraft = function() {
    try { return window.localStorage ? (localStorage.getItem(this._noteDraftKey) || '') : ''; }
    catch (e) { return ''; }
};

NotesApp.prototype._writeComposeDraft = function(text) {
    try {
        if (!window.localStorage) return;
        var value = text == null ? '' : String(text);
        if (value.trim()) localStorage.setItem(this._noteDraftKey, value);
        else localStorage.removeItem(this._noteDraftKey);
    } catch (e) {}
};

NotesApp.prototype._saveComposeDraftFrom = function(composer) {
    if (!composer || !composer.getValue) return;
    this._writeComposeDraft(composer.getValue());
};

NotesApp.prototype._clearComposeDraftStorage = function() {
    try { if (window.localStorage) localStorage.removeItem(this._noteDraftKey); } catch (e) {}
};

NotesApp.prototype._restoreComposeDraft = function() {
    var draft = this._readComposeDraft();
    if (!draft) return;
    if (this.composeComposer && !this.composeComposer.getValue()) {
        this.composeComposer.setValue(draft);
        this.updateComposePreview();
    }
    if (this.editorComposer && !this.editorComposer.getValue()) {
        this.editorComposer.setValue(draft);
        this.updateEditorPreview();
    }
};

NotesApp.prototype._syncNewNoteDraftToEditor = function() {
    if (!this.editorComposer) return;
    var text = '';
    if (this.composeComposer) text = this.composeComposer.getValue() || '';
    if (!text) text = this._readComposeDraft();
    this.editorComposer.setValue(text);
    this.updateEditorPreview();
    this._writeComposeDraft(text);
};

NotesApp.prototype._syncNewNoteDraftToCompose = function() {
    if (!this.composeComposer || !this.editorComposer) return;
    if (this._editNoteId) return;
    var text = this.editorComposer.getValue() || '';
    this.composeComposer.setValue(text);
    this.updateComposePreview();
    this._writeComposeDraft(text);
};

NotesApp.prototype.clearComposeDraft = function() {
    var self = this;
    var composeText = this.composeComposer ? this.composeComposer.getValue() : '';
    var editorText = this.editorComposer ? this.editorComposer.getValue() : '';
    if (!composeText.trim() && !editorText.trim() && !this._readComposeDraft()) return;
    BSDialog.confirm2(window.__('note.confirm.clear_draft')).then(function(ok) {
        if (!ok) return;
        if (self.composeComposer) self.composeComposer.clear();
        if (self.editorComposer && !self._editNoteId) self.editorComposer.clear();
        self._clearComposeDraftStorage();
        self.updateComposePreview();
        self.updateEditorPreview();
        BSDialog.toast(window.__('note.toast.draft_cleared'), 'success');
    });
};

NotesApp.prototype.submitCompose = function() {
    var text = (this.composeComposer ? this.composeComposer.getValue() : '').trim();
    if (!text) return;
    var labels = this.composeTagInput ? this.composeTagInput.getTags() : '';
    var title = text.substring(0, 50).replace(/[#*`\n]/g, '').trim() || 'note-' + Date.now();
    var self = this;
    var body = {
        blog_title: title,
        blog_type: 'note',
        blog_content: text,
        visibility: this.composeVisibility,
        labels: labels
    };
    this._appendLocationPayload(body);
    var request = this._runSubmitRequest('notes:compose:create', document.querySelector('#composeCard .compose-submit'), function() {
        return fetchWithCurrentCSRF('/api/blogs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
            body: JSON.stringify(body)
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            if (self.composeComposer) self.composeComposer.clear();
            if (self.editorComposer) self.editorComposer.clear();
            if (self.composeTagInput) self.composeTagInput.clear();
            self.clearComposeLocation();
            self._clearComposeDraftStorage();
            self.page = 1;
            self.loadNotes();
            BSDialog.toast(window.__('note.toast.publish_success'), 'success');
        } else {
            BSDialog.toast(data.message || window.__('note.toast.publish_failed'), 'error');
        }
    }).catch(function() {
        BSDialog.toast(window.__('note.toast.publish_failed'), 'error');
    });
};

NotesApp.prototype.openFullEditor = function() {
    this._editorPrevFocus = document.activeElement;
    this.setFullEditorMaximized(false);
    if (!this._editNoteId) this._syncNewNoteDraftToEditor();
    var clearBtn = document.getElementById('editorClearBtn');
    if (clearBtn) clearBtn.style.display = '';
    document.getElementById('editorOverlay').classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-editor-modal');
    if (this.editorComposer) this.editorComposer.focus();
    this._trapEditor(true);
};

NotesApp.prototype.openComposeAI = function() {
    this._openInlineAIPrompt(this.composeComposer);
};

NotesApp.prototype.openEditorModalAI = function() {
    this._openInlineAIPrompt(this.editorComposer);
};

NotesApp.prototype._openAIDialog = function(composer) {
    if (typeof AIHelper === 'undefined' || typeof AIComposeDialog === 'undefined') {
        BSDialog.toast(window.__('note.ai.toast.disabled'), 'warning');
        return;
    }
    if (!composer) return;
    AIComposeDialog.open({
        title: window.__('note.ai.dialog.title'),
        placeholder: window.__('note.ai.dialog.placeholder'),
        systemPrompt: window.AI_SYSTEM_PROMPT_MD || window.__('note.ai.dialog.system'),
        onInsert: function(text, mode) {
            if (mode === 'replace') composer.setValue(text);
            else composer.insertAtCursor(text);
        }
    });
};

NotesApp.prototype._getAIStreamStatusEl = function(composer) {
    if (composer && composer === this.composeComposer) return document.getElementById('composeAIStreamStatus');
    if (composer && composer === this.editorComposer) return document.getElementById('editorAIStreamStatus');
    return null;
};

NotesApp.prototype._formatAIStreamText = function(count) {
    var template = window.__ ? window.__('note.ai.streaming_count') : 'AI 正在生成，已输出 {count} 字';
    if (!template || template === 'note.ai.streaming_count') template = 'AI 正在生成，已输出 {count} 字';
    return template.replace('{count}', String(Math.max(0, count || 0)));
};

NotesApp.prototype._setAIStreamStatus = function(composer, state, count, message) {
    var el = this._getAIStreamStatusEl(composer);
    if (!el) return;
    if (!state || state === 'idle') {
        el.classList.remove('is-visible', 'is-error');
        el.setAttribute('aria-hidden', 'true');
        el.innerHTML = '';
        return;
    }
    el.classList.toggle('is-error', state === 'error');
    el.classList.add('is-visible');
    el.setAttribute('aria-hidden', 'false');
    if (state === 'error') {
        el.textContent = message || (window.__ ? window.__('note.ai.toast.error') : 'AI 调用失败');
        return;
    }
    el.innerHTML = '<span class="ai-inline-generation-spinner" aria-hidden="true"></span><span>' + this._escapeNoteAIHTML(message || this._formatAIStreamText(count)) + '</span>';
};

NotesApp.prototype._hideAIStreamStatus = function(composer) {
    this._setAIStreamStatus(composer, 'idle');
};

NotesApp.prototype._escapeNoteAIHTML = function(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(ch) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch];
    });
};

NotesApp.prototype._parseNoteAIActions = function(raw) {
    raw = typeof raw === 'string' ? raw : '';
    return raw.split(/\r?\n/).map(function(line) {
        line = line.trim();
        if (!line || line.charAt(0) === '#') return null;
        var idx = line.indexOf('|');
        if (idx < 0) return null;
        var label = line.slice(0, idx).trim();
        var prompt = line.slice(idx + 1).trim();
        if (!label || !prompt) return null;
        return { label: label, prompt: prompt };
    }).filter(Boolean);
};

NotesApp.prototype._getNoteAIActions = function() {
    var actions = this._parseNoteAIActions(window.NOTE_AI_ACTIONS_RAW || '');
    if (actions.length) return actions;
    return [
        { label: '美化格式', prompt: '美化这段笔记的 Markdown 格式：保留原意，整理标题、列表、引用、代码块和段落层级，让结构更清晰。只返回处理后的 Markdown。' },
        { label: '润色', prompt: '润色这段笔记：保留事实和语气，改得更通顺、更简洁、更适合长期保存。只返回处理后的 Markdown。' },
        { label: '清单', prompt: '把这段笔记整理成清晰的 checklist，保留必要背景和行动项。只返回 Markdown。' },
        { label: '摘要', prompt: '提炼这段笔记的核心要点，按层级输出摘要和重点。只返回 Markdown。' },
        { label: '续写', prompt: '基于这段笔记继续补写一小段，延续原来的语气和上下文。只返回要写入的 Markdown。' },
        { label: '翻译英文', prompt: '把这段笔记翻译成自然流畅的英文，保留 Markdown 结构。只返回翻译后的 Markdown。' }
    ];
};

NotesApp.prototype._renderNoteAIActionButtons = function(actions) {
    var self = this;
    actions = actions || this._getNoteAIActions();
    return actions.map(function(action, idx) {
        return '<button type="button" data-note-ai-action="' + idx + '" title="' + self._escapeNoteAIHTML(action.prompt) + '">' + self._escapeNoteAIHTML(action.label) + '</button>';
    }).join('');
};

NotesApp.prototype._setInlineAIQuickActions = function(actions) {
    if (!this._aiFloating) return;
    var self = this;
    actions = actions && actions.length ? actions : this._getNoteAIActions();
    var group = this._aiFloating.quickActions;
    if (!group) return;
    group.innerHTML = this._renderNoteAIActionButtons(actions);
    Array.prototype.forEach.call(group.querySelectorAll('[data-note-ai-action]'), function(btn) {
        btn.addEventListener('click', function() {
            if (!self._aiFloating) return;
            var idx = parseInt(btn.getAttribute('data-note-ai-action'), 10);
            var action = actions[idx];
            self._aiFloating.prompt.value = action ? action.prompt : '';
            self._aiFloating.prompt.focus();
            self._aiFloating.prompt.select();
        });
    });
};

NotesApp.prototype._initFloatingAI = function() {
    if (this._aiFloating || !window.AI_ENABLED) return;
    var self = this;
    var wrap = document.createElement('div');
    wrap.innerHTML = '' +
        '<div class="note-ai-popover" role="dialog" aria-modal="false" aria-label="AI 写入当前位置">' +
          '<div class="note-ai-popover-head">' +
            '<div class="note-ai-popover-title"><i class="fa-solid fa-wand-magic-sparkles"></i><span>AI 写入当前位置</span></div>' +
            '<div class="note-ai-popover-actions">' +
              '<button class="note-ai-popover-expand" type="button" aria-label="放大 AI 输入框" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
              '<button class="note-ai-popover-close" type="button" aria-label="关闭">&times;</button>' +
            '</div>' +
          '</div>' +
          '<div class="note-ai-context"></div>' +
          '<div class="note-ai-input-row">' +
            '<textarea class="note-ai-prompt" rows="1" autocomplete="off" placeholder="告诉 AI 你想怎么改..."></textarea>' +
            '<button class="note-ai-go note-ai-go-inline" type="button">确定</button>' +
          '</div>' +
          '<div class="note-ai-quick-actions" role="group" aria-label="AI 快捷操作">' +
            this._renderNoteAIActionButtons() +
          '</div>' +
          '<div class="note-ai-footer">' +
            '<button class="note-ai-cancel ai-dlg-btn ai-dlg-btn-cancel" type="button">取消</button>' +
            '<button class="note-ai-go note-ai-go-footer ai-dlg-btn ai-dlg-btn-go" type="button">生成</button>' +
          '</div>' +
          '<div class="note-ai-status" aria-live="polite"></div>' +
        '</div>';
    document.body.appendChild(wrap);
    var popover = wrap.querySelector('.note-ai-popover');
    var promptEl = wrap.querySelector('.note-ai-prompt');
    var ctxEl = wrap.querySelector('.note-ai-context');
    var statusEl = wrap.querySelector('.note-ai-status');
    var expandBtn = wrap.querySelector('.note-ai-popover-expand');
    var quickActionsEl = wrap.querySelector('.note-ai-quick-actions');
    this._aiFloating = { root: wrap, popover: popover, prompt: promptEl, context: ctxEl, status: statusEl, expandBtn: expandBtn, quickActions: quickActionsEl, cleanupDrag: null };

    popover.addEventListener('mousedown', function(e) { e.stopPropagation(); });
    popover.addEventListener('touchstart', function(e) { e.stopPropagation(); });
    this._setInlineAIQuickActions(this._getNoteAIActions());
    wrap.querySelector('.note-ai-popover-close').addEventListener('click', function() { self._hideInlineAI(); });
    wrap.querySelector('.note-ai-cancel').addEventListener('click', function() { self._hideInlineAI(); });
    expandBtn.addEventListener('click', function() { self._toggleInlineAIExpanded(); });
    Array.prototype.forEach.call(wrap.querySelectorAll('.note-ai-go'), function(btn) {
        btn.addEventListener('click', function() { self._runInlineAI(); });
    });
    promptEl.addEventListener('keydown', function(e) {
        var expanded = self._aiFloating && self._aiFloating.popover.classList.contains('is-expanded');
        if (e.key === 'Enter' && (!expanded || e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            self._runInlineAI();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            self._hideInlineAI();
            if (self._aiActiveComposer) self._aiActiveComposer.focus();
        }
    });
    document.addEventListener('mousedown', function(e) {
        if (!self._aiFloating) return;
        if (self._aiFloating.root.contains(e.target)) return;
        self._hideInlineAI();
    });
    document.addEventListener('touchstart', function(e) {
        if (!self._aiFloating) return;
        if (self._aiFloating.root.contains(e.target)) return;
        self._hideInlineAI();
    });
    this._aiViewportHandler = function() {
        if (self._isSmallAIViewport()) self._syncAIMobileViewport();
        else self._hideInlineAI();
    };
    window.addEventListener('resize', this._aiViewportHandler, { passive: true });
    window.addEventListener('orientationchange', this._aiViewportHandler, { passive: true });
    if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', this._aiViewportHandler, { passive: true });
        window.visualViewport.addEventListener('scroll', this._aiViewportHandler, { passive: true });
    }
    this._aiFloating.cleanupDrag = this._makeInlineAIDraggable(popover);
    this._bindComposerFloatingAI(this.composeComposer);
    this._bindComposerFloatingAI(this.editorComposer);
};

NotesApp.prototype._isSmallAIViewport = function() {
    return window.matchMedia ? window.matchMedia('(max-width: 640px)').matches : window.innerWidth <= 640;
};

NotesApp.prototype._syncAIMobileViewport = function() {
    if (!this._aiFloating || !this._isSmallAIViewport()) {
        document.documentElement.style.removeProperty('--note-ai-vv-top');
        document.body.classList.remove('note-ai-mobile-open');
        return;
    }
    var vv = window.visualViewport;
    var top = vv ? Math.max(0, vv.offsetTop) : 0;
    document.documentElement.style.setProperty('--note-ai-vv-top', Math.round(top) + 'px');
};

NotesApp.prototype._lockInlineAIScroll = function() {
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-inline-ai');
};

NotesApp.prototype._unlockInlineAIScroll = function() {
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-inline-ai');
};

NotesApp.prototype._makeInlineAIDraggable = function(popover) {
    if (!popover) return null;
    var header = popover.querySelector('.note-ai-popover-head');
    if (!header) return null;
    var self = this;
    var startX = 0;
    var startY = 0;
    var startLeft = 0;
    var startTop = 0;
    var dragging = false;

    function clampPosition(left, top) {
        var rect = popover.getBoundingClientRect();
        var maxLeft = Math.max(8, window.innerWidth - rect.width - 8);
        var maxTop = Math.max(8, window.innerHeight - rect.height - 8);
        return {
            left: Math.max(8, Math.min(maxLeft, left)),
            top: Math.max(8, Math.min(maxTop, top))
        };
    }

    function begin(e) {
        if (self._isSmallAIViewport()) return;
        if (e.target && e.target.closest && e.target.closest('button,input,textarea,select,a')) return;
        var rect = popover.getBoundingClientRect();
        dragging = true;
        startX = e.clientX;
        startY = e.clientY;
        startLeft = rect.left;
        startTop = rect.top;
        popover.classList.add('note-ai-popover-dragging');
        try { header.setPointerCapture(e.pointerId); } catch(err) {}
        e.preventDefault();
    }

    function move(e) {
        if (!dragging) return;
        var pos = clampPosition(startLeft + e.clientX - startX, startTop + e.clientY - startY);
        popover.classList.add('is-dragged');
        popover.style.setProperty('left', pos.left + 'px', 'important');
        popover.style.setProperty('top', pos.top + 'px', 'important');
        popover.style.setProperty('right', 'auto', 'important');
        popover.style.setProperty('bottom', 'auto', 'important');
        popover.style.setProperty('transform', 'none', 'important');
    }

    function end(e) {
        if (!dragging) return;
        dragging = false;
        popover.classList.remove('note-ai-popover-dragging');
        try { header.releasePointerCapture(e.pointerId); } catch(err) {}
    }

    function onResize() {
        if (!popover.classList.contains('is-open') || self._isSmallAIViewport()) return;
        if (!popover.classList.contains('is-dragged')) return;
        var rect = popover.getBoundingClientRect();
        var pos = clampPosition(rect.left, rect.top);
        popover.style.setProperty('left', pos.left + 'px', 'important');
        popover.style.setProperty('top', pos.top + 'px', 'important');
        popover.style.setProperty('right', 'auto', 'important');
        popover.style.setProperty('bottom', 'auto', 'important');
    }

    header.addEventListener('pointerdown', begin);
    header.addEventListener('pointermove', move);
    header.addEventListener('pointerup', end);
    header.addEventListener('pointercancel', end);
    window.addEventListener('resize', onResize);
    return function() {
        header.removeEventListener('pointerdown', begin);
        header.removeEventListener('pointermove', move);
        header.removeEventListener('pointerup', end);
        header.removeEventListener('pointercancel', end);
        window.removeEventListener('resize', onResize);
    };
};

NotesApp.prototype._resetInlineAIPosition = function() {
    if (!this._aiFloating) return;
    var popover = this._aiFloating.popover;
    popover.classList.remove('is-dragged', 'note-ai-popover-dragging');
    popover.style.left = '';
    popover.style.top = '';
    popover.style.right = '';
    popover.style.bottom = '';
    popover.style.transform = '';
    popover._noteAICompactStyle = null;
};

NotesApp.prototype._bindComposerFloatingAI = function(composer) {
    if (!composer || composer._noteAIBound || !composer.getEl) return;
    composer._noteAIBound = true;
    var self = this;
    var el = composer.getEl();
    if (!el) return;
    el.addEventListener('keyup', function(e) {
        if (e.key === 'Escape') self._hideInlineAI();
    });
    el.addEventListener('focusin', function() { self._aiActiveComposer = composer; });
    el.addEventListener('scroll', function() { self._hideInlineAI(); }, true);
};

NotesApp.prototype._setInlineAIExpanded = function(expanded) {
    if (!this._aiFloating) return;
    var popover = this._aiFloating.popover;
    var prompt = this._aiFloating.prompt;
    var btn = this._aiFloating.expandBtn;
    expanded = !!expanded;
    if (expanded && !popover.classList.contains('is-expanded')) {
        popover._noteAICompactStyle = {
            left: popover.style.left,
            top: popover.style.top,
            right: popover.style.right,
            bottom: popover.style.bottom,
            transform: popover.style.transform
        };
        popover.classList.remove('is-dragged');
        popover.style.transform = '';
    } else if (!expanded && popover._noteAICompactStyle) {
        popover.style.left = popover._noteAICompactStyle.left || '';
        popover.style.top = popover._noteAICompactStyle.top || '';
        popover.style.right = popover._noteAICompactStyle.right || '';
        popover.style.bottom = popover._noteAICompactStyle.bottom || '';
        popover.style.transform = popover._noteAICompactStyle.transform || '';
        popover._noteAICompactStyle = null;
        popover.classList.remove('is-dragged');
    }
    popover.classList.toggle('is-expanded', expanded);
    popover.setAttribute('aria-modal', expanded ? 'true' : 'false');
    prompt.setAttribute('rows', expanded ? '6' : '1');
    if (btn) {
        btn.setAttribute('aria-pressed', expanded ? 'true' : 'false');
        btn.setAttribute('aria-label', expanded ? '还原 AI 输入框' : '放大 AI 输入框');
        btn.innerHTML = '<i class="fa-solid ' + (expanded ? 'fa-compress' : 'fa-expand') + '"></i>';
    }
};

NotesApp.prototype._toggleInlineAIExpanded = function() {
    if (!this._aiFloating) return;
    var expanded = !this._aiFloating.popover.classList.contains('is-expanded');
    this._setInlineAIExpanded(expanded);
    this._aiFloating.prompt.focus();
};

NotesApp.prototype._hideInlineAI = function() {
    if (!this._aiFloating) return;
    this._aiFloating.popover.classList.remove('is-open');
    this._setInlineAIExpanded(false);
    this._resetInlineAIPosition();
    this._aiFloating.status.classList.remove('is-streaming');
    this._aiFloating.status.textContent = '';
    document.body.classList.remove('note-ai-mobile-open');
    this._unlockInlineAIScroll();
};

NotesApp.prototype._positionAIFloat = function(el, rect, opts) {
    opts = opts || {};
    if (this._isSmallAIViewport()) {
        this._syncAIMobileViewport();
        el.style.left = '';
        el.style.top = '';
        el.style.transform = '';
        return;
    }
    var width = opts.width || 220;
    var x = rect.left || 0;
    var y = opts.below ? (rect.bottom + 8) : (rect.top - 10);
    x = Math.max(12 + width / 2, Math.min(window.innerWidth - 12 - width / 2, x));
    if (opts.below) {
        y = Math.min(window.innerHeight - 190, Math.max(48, y));
        el.style.transform = 'translateX(-50%)';
    } else {
        y = Math.max(54, y);
        el.style.transform = 'translate(-50%, -100%)';
    }
    el.style.left = x + 'px';
    el.style.top = y + 'px';
};

NotesApp.prototype._showAISelectionMenu = function(composer) {
    this._aiActiveComposer = composer;
};

NotesApp.prototype._openInlineAIPrompt = function(composer, seed, opts) {
    opts = opts || {};
    if (!composer || !this._aiFloating) return;
    if (typeof AIHelper === 'undefined') {
        BSDialog.toast(window.__('note.ai.toast.disabled'), 'warning');
        return;
    }
    this._aiActiveComposer = composer;
    var range = composer.getSelectionRange ? composer.getSelectionRange() : { from: 0, to: 0 };
    var value = composer.getValue ? composer.getValue() : '';
    if ((!range || range.from === range.to) && value) {
        range = { from: 0, to: value.length };
        if (typeof composer.selectRange === 'function') composer.selectRange(range.from, range.to);
    }
    this._aiActiveRange = { from: range.from, to: range.to };
    this._aiActiveOptions = {
        contextPrefix: opts.contextPrefix || '',
        emptyText: opts.emptyText || '',
        scene: opts.scene || 'note',
        systemPrompt: opts.systemPrompt || '',
        quickActions: opts.quickActions || null
    };
    var selected = value.substring(range.from, range.to);
    var contextText = selected ? selected : (opts.emptyText || '空笔记，将在当前光标位置插入。');
    if (opts.contextPrefix) contextText = opts.contextPrefix + '\n\n' + contextText;
    this._aiFloating.context.textContent = contextText;
    this._aiFloating.prompt.value = seed || '';
    this._aiFloating.status.classList.remove('is-streaming');
    this._aiFloating.status.textContent = '';
    this._setInlineAIQuickActions(this._aiActiveOptions.quickActions);
    this._resetInlineAIPosition();
    this._setInlineAIExpanded(false);
    var rect = composer.getRangeRect ? composer.getRangeRect(range.from, range.to) : { left: window.innerWidth / 2, bottom: 80, top: 60 };
    this._positionAIFloat(this._aiFloating.popover, rect, { width: 360, below: true });
    if (this._isSmallAIViewport()) document.body.classList.add('note-ai-mobile-open');
    this._aiFloating.popover.classList.add('is-open');
    this._lockInlineAIScroll();
    var promptEl = this._aiFloating.prompt;
    window.setTimeout(function() { promptEl.focus(); promptEl.select(); }, 0);
};

NotesApp.prototype._runInlineAI = function() {
    var composer = this._aiActiveComposer;
    if (!composer || !this._aiFloating || !this._aiActiveRange) return;
    var instruction = (this._aiFloating.prompt.value || '').trim();
    if (!instruction) {
        this._aiFloating.prompt.focus();
        return;
    }
    if (this._aiStreamCtrl) {
        try { this._aiStreamCtrl.abort(); } catch(e) {}
        this._aiStreamCtrl = null;
    }
    var self = this;
    var range = { from: this._aiActiveRange.from, to: this._aiActiveRange.to };
    var aiOpts = this._aiActiveOptions || {};
    var value = composer.getValue ? composer.getValue() : '';
    var selected = value.substring(range.from, range.to);
    var prefix = aiOpts.contextPrefix ? '【额外上下文】\n' + aiOpts.contextPrefix + '\n\n' : '';
    var userMsg = selected
        ? prefix + '【选中的 Markdown】\n' + selected + '\n\n【指令】\n' + instruction + '\n\n请只返回要写入编辑器的 Markdown 内容，不要解释。'
        : prefix + '【指令】\n' + instruction + '\n\n请只返回要插入编辑器的 Markdown 内容，不要解释。';
    var insertedEnd = range.from;
    var started = false;
    var writtenChars = 0;
    this._aiFloating.status.classList.add('is-streaming');
    this._aiFloating.status.textContent = '正在流式写入...';
    this._aiFloating.popover.classList.remove('is-open');
    this._unlockInlineAIScroll();
    this._hideAIStreamStatus(composer);
    this._setAIStreamStatus(composer, 'streaming', 0);
    this._aiStreamCtrl = AIHelper.complete({
        messages: AIHelper.buildMessages(aiOpts.systemPrompt || window.AI_SYSTEM_PROMPT_MD || window.__('note.ai.dialog.system'), userMsg),
        scene: aiOpts.scene || 'note',
        onChunk: function(chunk) {
            if (!started) {
                insertedEnd = composer.replaceRange(range.from, range.to, '');
                started = true;
            }
            insertedEnd = composer.replaceRange(insertedEnd, insertedEnd, chunk);
            writtenChars += chunk.length;
            self._setAIStreamStatus(composer, 'streaming', writtenChars);
        },
        onDone: function() {
            self._aiStreamCtrl = null;
            if (self._aiFloating) {
                self._aiFloating.status.classList.remove('is-streaming');
                self._aiFloating.status.textContent = '已写入';
            }
            self._hideAIStreamStatus(composer);
        },
        onError: function(msg) {
            self._aiStreamCtrl = null;
            if (self._aiFloating) self._aiFloating.status.classList.remove('is-streaming');
            self._setAIStreamStatus(composer, 'error', 0, msg || window.__('note.ai.toast.error'));
            BSDialog.toast(msg || window.__('note.ai.toast.error'), 'error');
        }
    });
};

NotesApp.prototype.closeFullEditor = function() {
    this._syncNewNoteDraftToCompose();
    this.setFullEditorMaximized(false);
    document.getElementById('editorOverlay').classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-editor-modal');
    // Restore submit button for new note
    var modal = document.querySelector('#editorOverlay .asset-modal');
    var submitBtn = modal.querySelector('.compose-submit');
    submitBtn.textContent = window.__('note.full_editor.submit.publish');
    submitBtn.setAttribute('onclick', 'notesApp.submitFullEditor()');
    document.getElementById('editorModalTitle').textContent = window.__('note.full_editor.title.new');
    var clearBtn = document.getElementById('editorClearBtn');
    if (clearBtn) clearBtn.style.display = '';
    var tagRow = document.getElementById('editorTagContainer');
    var tagToggle = document.getElementById('editorTagToggle');
    if (tagRow) tagRow.classList.add('hidden');
    if (tagToggle) tagToggle.classList.remove('active');
    this._editNoteId = null;
    this._trapEditor(false);
};

NotesApp.prototype.setFullEditorMaximized = function(maximized) {
    var modal = document.querySelector('#editorOverlay .asset-modal');
    var btn = document.getElementById('editorMaximizeBtn');
    if (!modal || !btn) return;
    modal.classList.toggle('is-maximized', !!maximized);
    btn.setAttribute('aria-pressed', maximized ? 'true' : 'false');
    btn.setAttribute('aria-label', window.__(maximized ? 'note.editor.restore' : 'note.editor.maximize'));
    btn.setAttribute('title', window.__(maximized ? 'note.editor.restore' : 'note.editor.maximize'));
    btn.innerHTML = '<i class="fa-solid ' + (maximized ? 'fa-compress' : 'fa-expand') + '"></i>';
    var view = this.editorComposer && this.editorComposer.getView ? this.editorComposer.getView() : null;
    if (view && typeof view.requestMeasure === 'function') {
        window.requestAnimationFrame(function() { view.requestMeasure(); });
    }
};

NotesApp.prototype.toggleFullEditorMaximized = function() {
    var modal = document.querySelector('#editorOverlay .asset-modal');
    if (!modal) return;
    this.setFullEditorMaximized(!modal.classList.contains('is-maximized'));
    if (this.editorComposer) this.editorComposer.focus();
};

var _focusableSel = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
NotesApp.prototype._trapEditor = function(on) {
    var self = this;
    if (on) {
        this._editorTrapHandler = function(e) {
            if (e.key === 'Escape') { e.preventDefault(); self.closeFullEditor(); return; }
            if (e.key !== 'Tab') return;
            var box = document.querySelector('#editorOverlay .asset-modal');
            if (!box) return;
            var focusable = Array.prototype.slice.call(box.querySelectorAll(_focusableSel)).filter(function(el) { return el.offsetParent !== null; });
            if (!focusable.length) return;
            var first = focusable[0], last = focusable[focusable.length - 1];
            if (e.shiftKey) { if (document.activeElement === first) { e.preventDefault(); last.focus(); } }
            else { if (document.activeElement === last) { e.preventDefault(); first.focus(); } }
        };
        document.addEventListener('keydown', this._editorTrapHandler);
    } else {
        if (this._editorTrapHandler) { document.removeEventListener('keydown', this._editorTrapHandler); this._editorTrapHandler = null; }
        if (this._editorPrevFocus && typeof this._editorPrevFocus.focus === 'function') { try { this._editorPrevFocus.focus(); } catch(e) {} this._editorPrevFocus = null; }
    }
};

NotesApp.prototype.submitFullEditor = function() {
    var text = (this.editorComposer ? this.editorComposer.getValue() : '').trim();
    if (!text) return;
    var labels = this.editorTagInput ? this.editorTagInput.getTags() : '';
    var title = text.substring(0, 50).replace(/[#*`\n]/g, '').trim() || 'note-' + Date.now();
    var self = this;
    var body = { blog_title: title, blog_type: 'note', blog_content: text, visibility: this.composeVisibility, labels: labels };
    this._appendLocationPayload(body);
    var request = this._runSubmitRequest('notes:editor:create', document.querySelector('#editorOverlay .editor-toolbar-submit'), function() {
        return fetchWithCurrentCSRF('/api/blogs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
            body: JSON.stringify(body)
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            if (self.editorComposer) self.editorComposer.clear();
            if (self.composeComposer) self.composeComposer.clear();
            if (self.editorTagInput) self.editorTagInput.clear();
            if (self.composeTagInput) self.composeTagInput.clear();
            self.clearComposeLocation();
            self._clearComposeDraftStorage();
            self.closeFullEditor();
            self.page = 1;
            self.loadNotes();
            BSDialog.toast(window.__('note.toast.publish_success'), 'success');
        } else { BSDialog.toast(data.message || window.__('note.toast.publish_failed'), 'error'); }
    }).catch(function() {
        BSDialog.toast(window.__('note.toast.publish_failed'), 'error');
    });
};

NotesApp.prototype.saveEditNoteFromModal = function() {
    var id = this._editNoteId;
    if (!id) return;
    var text = (this.editorComposer ? this.editorComposer.getValue() : '').trim();
    if (!text) return;
    var labels = this.editorTagInput ? this.editorTagInput.getTags() : '';
    var self = this;
    var request = this._runSubmitRequest('notes:editor:update:' + id, document.querySelector('#editorOverlay .editor-toolbar-submit'), function() {
        return fetchWithCurrentCSRF('/api/blogs/' + id, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
            body: JSON.stringify({ blog_content: text, labels: labels })
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            self.closeFullEditor();
            self._updateNoteCard(id, text, self.editorTagInput ? self.editorTagInput.getTagList() : []);
            BSDialog.toast(window.__('note.toast.save_success'), 'success');
        } else { BSDialog.toast(data.message || window.__('note.toast.save_failed'), 'error'); }
    }).catch(function() { BSDialog.toast(window.__('note.toast.save_failed'), 'error'); });
};

NotesApp.prototype.createArticle = function() {
    this.openArticleSettingModal(null);
};

NotesApp.prototype.selectArticleType = function(btn) {
    var grid = document.querySelector('.article-type-grid');
    if (!grid) return;
    grid.querySelectorAll('.create-doc-type-btn').forEach(function(b) { b.classList.remove('active'); });
    btn.classList.add('active');
    this._selectedEditorType = btn.getAttribute('data-editor-type') || 'markdown';
};

NotesApp.prototype.toggleArticlePasswordVisible = function(inputId, btn) {
    var input = document.getElementById(inputId);
    if (!input || !btn) return;
    var visible = input.type === 'password';
    input.type = visible ? 'text' : 'password';
    btn.setAttribute('aria-label', visible ? window.__('asset.password.hide') : window.__('asset.password.show'));
    btn.innerHTML = '<i class="fa-solid ' + (visible ? 'fa-eye-slash' : 'fa-eye') + '"></i>';
    input.focus();
};

NotesApp.prototype._resetArticlePasswordVisibility = function() {
    ['articleCurrentPwd', 'articleNewPwd'].forEach(function(inputId) {
        var input = document.getElementById(inputId);
        if (!input) return;
        input.type = 'password';
        var wrap = input.closest('.article-pwd-input-wrap');
        var btn = wrap ? wrap.querySelector('.article-pwd-toggle') : null;
        if (btn) {
            btn.setAttribute('aria-label', window.__('asset.password.show'));
            btn.innerHTML = '<i class="fa-solid fa-eye"></i>';
        }
    });
};

NotesApp.prototype.openArticleSettingModal = function(id) {
    this._articlePrevFocus = document.activeElement;
    var isNew = !id;
    document.getElementById('_articleId').value = id || '';
    document.getElementById('articleSettingTitle').textContent = isNew ? window.__('note.article.modal.title.new') : window.__('note.action.settings');
    document.getElementById('articleSettingSaveBtn').textContent = isNew ? window.__('note.article.btn.new') : window.__('note.article.btn.edit');
    document.getElementById('articleSettingError').style.display = 'none';
    document.getElementById('articleTitleInput').value = '';
    var descInput = document.getElementById('articleDescInput');
    if (descInput) descInput.value = '';
    // Show/hide type selector
    var typeSection = document.getElementById('articleTypeSection');
    if (typeSection) typeSection.style.display = isNew ? '' : 'none';
    // Reset type selection
    if (isNew) {
        this._selectedEditorType = 'markdown';
        var grid = document.querySelector('.article-type-grid');
        if (grid) {
            grid.querySelectorAll('.create-doc-type-btn').forEach(function(b) { b.classList.remove('active'); });
            var first = grid.querySelector('[data-editor-type="markdown"]');
            if (first) first.classList.add('active');
        }
    }
    // Clear tags
    if (this.articleTagInput) this.articleTagInput.clear();
    // Reset password
    document.getElementById('articleCurrentPwd').value = '';
    document.getElementById('articleNewPwd').value = '';
    this._resetArticlePasswordVisibility();
    document.getElementById('articleCurrentPwdRow').style.display = 'none';
    document.getElementById('articlePwdHint').textContent = window.__('note.article.pwd.hint');

    var self = this;
    if (!isNew) {
        var artCard = document.querySelector('.article-card[data-id="' + id + '"]');
        if (self.articleTagInput) {
            self.articleTagInput.setTags(NotesApp._extractTagsFromCard(artCard));
        }
        var titleEl = artCard ? artCard.querySelector('.article-title') : null;
        document.getElementById('articleTitleInput').value = titleEl ? titleEl.textContent : '';
        if (descInput) descInput.value = artCard ? (artCard.dataset.desc || '') : '';
        var currentHasPwd = artCard ? !!artCard.querySelector('.vis-badge .fa-lock') : false;
        if (currentHasPwd) {
            document.getElementById('articleCurrentPwdRow').style.display = '';
            document.getElementById('articlePwdHint').textContent = window.__('note.article.pwd.hint_existing');
        }
    }
    document.getElementById('articleSettingOverlay').classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-article-modal');
    setTimeout(function() { document.getElementById('articleTitleInput').focus(); }, 100);
    this._trapArticleSetting(true);
};

NotesApp.prototype.closeArticleSettingModal = function() {
    document.getElementById('articleSettingOverlay').classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-article-modal');
    if (this.articleTagInput) this.articleTagInput.hideDropdown();
    this._trapArticleSetting(false);
};

NotesApp.prototype._trapArticleSetting = function(on) {
    var self = this;
    if (on) {
        this._articleTrapHandler = function(e) {
            if (e.key === 'Escape') { e.preventDefault(); self.closeArticleSettingModal(); return; }
            if (e.key !== 'Tab') return;
            var box = document.querySelector('#articleSettingOverlay .asset-modal');
            if (!box) return;
            var focusable = Array.prototype.slice.call(box.querySelectorAll(_focusableSel)).filter(function(el) { return el.offsetParent !== null; });
            if (!focusable.length) return;
            var first = focusable[0], last = focusable[focusable.length - 1];
            if (e.shiftKey) { if (document.activeElement === first) { e.preventDefault(); last.focus(); } }
            else { if (document.activeElement === last) { e.preventDefault(); first.focus(); } }
        };
        document.addEventListener('keydown', this._articleTrapHandler);
    } else {
        if (this._articleTrapHandler) { document.removeEventListener('keydown', this._articleTrapHandler); this._articleTrapHandler = null; }
        if (this._articlePrevFocus && typeof this._articlePrevFocus.focus === 'function') { try { this._articlePrevFocus.focus(); } catch(e) {} this._articlePrevFocus = null; }
    }
};

NotesApp.prototype.saveArticleSetting = function() {
    var id = document.getElementById('_articleId').value;
    var title = document.getElementById('articleTitleInput').value.trim();
    var descInput = document.getElementById('articleDescInput');
    var desc = descInput ? descInput.value.trim() : '';
    var errEl = document.getElementById('articleSettingError');
    if (!title) { errEl.textContent = window.__('note.article.error.no_title'); errEl.style.display = ''; return; }
    if (desc.length > 500) { errEl.textContent = window.__('note.article.error.desc_too_long'); errEl.style.display = ''; return; }
    var labels = this._getArticleTags();
    var body = { blog_title: title, blog_desc: desc, labels: labels };
    // Password
    var newPwd = document.getElementById('articleNewPwd').value;
    if (id) {
        var currentPwd = document.getElementById('articleCurrentPwd').value;
        if (newPwd) body.new_password = newPwd;
        if (currentPwd) body.current_password = currentPwd;
        if (currentPwd && !newPwd) body.new_password = '';
    }
    var self = this;
    if (!id) {
        // Create new article
        body.blog_type = 'article';
        body.blog_content = '';
        body.editor_type = this._selectedEditorType || 'markdown';
        if (newPwd) body.new_password = newPwd;
        var createRequest = this._runSubmitRequest('notes:article:create', document.getElementById('articleSettingSaveBtn'), function() {
            return fetchWithCurrentCSRF('/api/blogs', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
                body: JSON.stringify(body)
            });
        });
        if (!createRequest) return;
        createRequest.then(function(r) { return r.json(); }).then(function(data) {
            if (data.code === 0 && data.data && data.data.blog_identify) {
                var newId = data.data.blog_id || data.data.id;
                var returnUrl = '/notes?id=' + newId + '&tab=' + self.activeTab;
                window.location.href = '/blogs/' + data.data.blog_identify + '/edit?mode=edit&from=' + encodeURIComponent(returnUrl);
            } else {
                errEl.textContent = data.message || window.__('note.article.error.create_failed'); errEl.style.display = '';
            }
        }).catch(function() { errEl.textContent = window.__('note.article.error.create_failed'); errEl.style.display = ''; });
    } else {
        // Update existing article
        var updateRequest = this._runSubmitRequest('notes:article:update:' + id, document.getElementById('articleSettingSaveBtn'), function() {
            return fetchWithCurrentCSRF('/api/blogs/' + id, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
                body: JSON.stringify(body)
            });
        });
        if (!updateRequest) return;
        updateRequest.then(function(r) { return r.json(); }).then(function(data) {
            if (data.code === 0) {
                var inputNewPwd = document.getElementById('articleNewPwd').value;
                var inputCurrentPwd = document.getElementById('articleCurrentPwd').value;
                self.closeArticleSettingModal();
                var artCard = document.querySelector('.article-card[data-id="' + id + '"]');
                var currentHasPwd = artCard ? !!artCard.querySelector('.vis-badge .fa-lock') : false;
                var newHasPwd;
                if (inputNewPwd) { newHasPwd = true; }
                else if (inputCurrentPwd) { newHasPwd = false; }
                else { newHasPwd = currentHasPwd; }
                self._updateArticleCard(id, title, desc, self.articleTagInput ? self.articleTagInput.getTagList() : [], newHasPwd);
                BSDialog.toast(window.__('note.toast.saved'), 'success');
            } else {
                errEl.textContent = data.message || window.__('note.article.error.save_failed'); errEl.style.display = '';
            }
        }).catch(function() { errEl.textContent = window.__('note.article.error.save_failed'); errEl.style.display = ''; });
    }
};

// ── Tag input components ──

NotesApp.prototype._initTagInputs = function() {
    var self = this;
    // Compose tag input (lazy, toggled by button)
    var composeToggle = document.getElementById('composeTagToggle');
    if (composeToggle) {
        composeToggle.addEventListener('click', function() {
            var c = document.getElementById('composeTagContainer');
            if (!c) return;
            if (c.classList.contains('hidden')) {
                c.classList.remove('hidden');
                if (!self.composeTagInput) {
                    self.composeTagInput = new TagInput(c, { placeholder: window.__('note.tag.placeholder'), useSheet: true });
                }
                self.composeTagInput.focus();
            } else {
                c.classList.add('hidden');
            }
        });
    }
    // Full editor tag input
    var editorToggle = document.getElementById('editorTagToggle');
    var editorContainer = document.getElementById('editorTagContainer');
    if (editorContainer) {
        self.editorTagInput = new TagInput(editorContainer, { placeholder: window.__('note.tag.placeholder'), useSheet: true });
    }
    if (editorToggle && editorContainer) {
        editorToggle.addEventListener('click', function() {
            editorContainer.classList.toggle('hidden');
            editorToggle.classList.toggle('active', !editorContainer.classList.contains('hidden'));
            if (!editorContainer.classList.contains('hidden') && self.editorTagInput) self.editorTagInput.focus();
        });
    }
    // Article setting modal tag input
    var articleContainer = document.getElementById('articleTagContainer');
    if (articleContainer) {
        self.articleTagInput = new TagInput(articleContainer, { placeholder: window.__('note.tag.placeholder'), useSheet: true });
    }
};

NotesApp.prototype._getArticleTags = function() {
    return this.articleTagInput ? this.articleTagInput.getTags() : '';
};

NotesApp.prototype._addArticleTag = function(name) {
    if (this.articleTagInput) this.articleTagInput.addTag(name);
};

NotesApp.prototype._hideArticleTagDropdown = function() {
    if (this.articleTagInput) this.articleTagInput.hideDropdown();
};

// ── Note actions ──

NotesApp.prototype.togglePin = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:note:pin:' + id, this._getCardActionButton('.note-card[data-id="' + id + '"]', '.note-pin-action'), function() {
        return fetchWithCurrentCSRF('/api/blogs/' + id + '/pin', {
        method: 'PATCH',
        headers: { 'X-CSRF-Token': self.csrf }
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            var pinned = data.data.is_pinned;
            var card = document.querySelector('.note-card[data-id="' + id + '"]');
            if (card) {
                var btn = card.querySelector('.note-pin-action');
                if (btn) {
                    var label = pinned ? window.__('note.action.unpin') : window.__('note.action.pin');
                    btn.classList.toggle('is-pinned', pinned);
                    btn.title = label;
                    btn.setAttribute('aria-label', label);
                    btn.setAttribute('aria-pressed', pinned ? 'true' : 'false');
                    btn.innerHTML = NotesApp.pinIconHtml(pinned);
                }
                card.classList.toggle('pinned', pinned);
                NotesApp._syncNoteStatePinBadge(card.querySelector('.note-header'), pinned);
            }
            BSDialog.toast(pinned ? window.__('note.toast.pin') : window.__('note.toast.unpin'));
        }
    });
};

NotesApp.prototype.toggleVisibility = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:note:visibility:' + id, this._getCardActionButton('.note-card[data-id="' + id + '"]', '.vis-toggle'), function() {
        return fetchWithCurrentCSRF('/api/blogs/' + id + '/visibility', {
        method: 'PATCH',
        headers: { 'X-CSRF-Token': self.csrf }
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            var vis = data.data.visibility;
            var card = document.querySelector('.note-card[data-id="' + id + '"]');
            if (card) {
                var badge = card.querySelector('.vis-state');
                if (badge) {
                    badge.textContent = vis === 1 ? window.__('note.badge.public') : window.__('note.badge.private');
                }
                var btn = card.querySelector('.vis-toggle');
                if (btn) {
                    btn.title = vis === 1 ? window.__('note.action.set_private') : window.__('note.action.set_public');
                    btn.innerHTML = '<i class="fa-solid ' + (vis === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i>';
                }
            }
            BSDialog.toast(vis === 1 ? window.__('note.toast.vis_public') : window.__('note.toast.vis_private'), 'success');
        }
    });
};

NotesApp.prototype.removeBlogLabel = function(blogId, labelName) {
    var self = this;
    BSDialog.confirm2(window.__('note.confirm.delete_label').replace('{name}', labelName)).then(function(ok) {
        if (!ok) return;
        // Collect remaining labels (all except the one being removed)
        var remaining = [];
        var card = document.querySelector('.note-card[data-id="' + blogId + '"]') || document.querySelector('.article-card[data-id="' + blogId + '"]');
        if (card) {
            var badges = card.querySelectorAll('.tag-badge');
            badges.forEach(function(badge) {
                var name = badge.childNodes[0] ? badge.childNodes[0].textContent.trim() : '';
                if (name && name !== labelName) remaining.push(name);
            });
        }
        fetchWithCurrentCSRF('/api/labels/resource/blog/' + blogId, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': self.csrf },
            body: JSON.stringify({ labels: remaining.join(',') })
        }).then(function(r) { return r.json(); }).then(function(data) {
            if (data.code === 0) {
                self._refreshCardLabels(blogId, labelName);
                BSDialog.toast(window.__('note.toast.label_deleted'), 'success');
            }
        });
    });
};

NotesApp.prototype._refreshCardLabels = function(blogId, removedLabel) {
    var card = document.querySelector('.note-card[data-id="' + blogId + '"]') || document.querySelector('.article-card[data-id="' + blogId + '"]');
    if (!card) return;
    var badges = card.querySelectorAll('.tag-badge');
    badges.forEach(function(badge) {
        var text = badge.childNodes[0] ? badge.childNodes[0].textContent.trim() : '';
        if (text === removedLabel) {
            badge.style.transition = 'opacity 0.15s';
            badge.style.opacity = '0';
            setTimeout(function() { badge.remove(); }, 150);
        }
    });
    // Remove empty note-tags container
    var tagsContainer = card.querySelector('.note-tags');
    if (tagsContainer && !tagsContainer.querySelector('.tag-badge')) {
        tagsContainer.remove();
    }
    var articleTagsContainer = card.querySelector('.article-tags');
    if (articleTagsContainer && !articleTagsContainer.querySelector('.tag-badge') && !articleTagsContainer.querySelector('.article-state-badge')) {
        articleTagsContainer.remove();
    }
};

NotesApp._buildTagBadgesHtml = function(blogId, labels) {
    return labels.map(function(l) {
        var safeLabel = escAttr(l).replace(/'/g, "\\'");
        return '<span class="tag-badge tag-badge-clickable" data-label="' + escAttr(l) + '" onclick="event.stopPropagation();notesApp.selectLabel(\'' + safeLabel + '\')">' +
            escHtml(l) +
            '<button class="tag-badge-remove" title="' + window.__('note.tag.remove.title') + '" aria-label="' + window.__('note.tag.remove.aria') + '" onclick="event.stopPropagation();notesApp.removeBlogLabel(' + blogId + ',\'' + safeLabel + '\')"><i class="fa-solid fa-xmark"></i></button>' +
            '</span>';
    }).join('');
};

NotesApp._buildReadonlyTagBadgesHtml = function(labels) {
    return labels.map(function(label) {
        return '<span class="tag-badge">' + escHtml(label) + '</span>';
    }).join('');
};

NotesApp._extractTagsFromCard = function(cardEl) {
    var result = [];
    if (!cardEl) return result;
    cardEl.querySelectorAll('.tag-badge').forEach(function(badge) {
        var text = badge.childNodes[0] ? badge.childNodes[0].textContent.trim() : '';
        if (text) result.push(text);
    });
    return result;
};

NotesApp.prototype._updateNoteCard = function(blogId, content, labels) {
    var card = document.querySelector('.note-card[data-id="' + blogId + '"]');
    if (!card) return;
    var contentEl = card.querySelector('.note-content');
    if (contentEl) {
        var html = typeof marked !== 'undefined' ? marked.parse(content) : escHtml(content);
        contentEl.innerHTML = html;
    }
    var oldTags = card.querySelector('.note-tags');
    if (oldTags) oldTags.remove();
    if (labels && labels.length) {
        var tagsContainer = document.createElement('div');
        tagsContainer.className = 'note-tags';
        tagsContainer.innerHTML = NotesApp._buildTagBadgesHtml(blogId, labels);
        card.insertBefore(tagsContainer, card.querySelector('.note-footer'));
    }
};

NotesApp.prototype._updateArticleCard = function(blogId, title, desc, labels, hasPassword) {
    var card = document.querySelector('.article-card[data-id="' + blogId + '"]');
    if (!card) return;
    var titleEl = card.querySelector('.article-title');
    if (titleEl) titleEl.textContent = title || window.__('note.article.no_title');
    card.dataset.desc = desc || '';
    var excerptEl = card.querySelector('.article-excerpt');
    if (excerptEl) excerptEl.textContent = hasPassword ? window.__('note.article.encrypted_desc') : (desc || '');
    var pinned = !!card.querySelector('.topic-card-pin-badge, .pin-badge');
    var visBadge = card.querySelector('.vis-state');
    var editorTypeChip = card.querySelector('.editor-type-chip');
    var oldTags = card.querySelector('.article-tags');
    if (oldTags) oldTags.remove();
    var tagsContainer = document.createElement('div');
    tagsContainer.className = 'article-tags';
    tagsContainer.innerHTML = NotesApp._buildArticleStatusBadgesHtml({
        pinned: pinned,
        visibilityText: visBadge ? visBadge.textContent.trim() : window.__('note.badge.private'),
        hasPassword: !!hasPassword,
        editorTypeLabel: editorTypeChip ? editorTypeChip.textContent.trim() : ''
    }) + (labels && labels.length ? NotesApp._buildTagBadgesHtml(blogId, labels) : '');
    card.appendChild(tagsContainer);
};

NotesApp.prototype.deleteNote = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:note:delete:' + id, this._getCardActionButton('.note-card[data-id="' + id + '"]', '.del'), function() {
        return BSDialog.confirm2(window.__('note.confirm.delete')).then(function(ok) {
            if (!ok) return null;
            return fetchWithCurrentCSRF('/api/blogs/' + id, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': self.csrf }
            });
        });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; }).then(function(data) {
            if (!data) return;
            if (data.code === 0) {
                var card = document.querySelector('.note-card[data-id="' + id + '"]');
                if (card) {
                    card.style.transition = 'opacity 0.2s, transform 0.2s';
                    card.style.opacity = '0';
                    card.style.transform = 'translateX(-20px)';
                    setTimeout(function() { card.remove(); }, 200);
                }
                BSDialog.toast(window.__('note.toast.deleted'), 'success');
            }
    });
};

NotesApp.prototype.editNote = function(id) {
    var card = document.querySelector('.note-card[data-id="' + id + '"]');
    if (!card) return;
    var self = this;
    // Fetch full content
    fetchWithCurrentCSRF('/api/blogs/' + id, {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.code !== 0 || !data.data) { BSDialog.toast(window.__('note.toast.get_content_failed'), 'error'); return; }
        var blog = data.data;
        var content = blog.blog_content || '';
        self._editNoteId = id;
        var modal = document.querySelector('#editorOverlay .asset-modal');
        document.getElementById('editorModalTitle').textContent = window.__('note.full_editor.title.edit');
        if (self.editorComposer) self.editorComposer.setValue(content);
        // Set tags from card DOM
        if (self.editorTagInput) {
            self.editorTagInput.setTags(NotesApp._extractTagsFromCard(card));
        }
        // Change submit button to save edit
        var submitBtn = modal.querySelector('.compose-submit');
        submitBtn.textContent = window.__('note.full_editor.submit.save');
        submitBtn.setAttribute('onclick', 'notesApp.saveEditNoteFromModal()');
        var clearBtn = document.getElementById('editorClearBtn');
        if (clearBtn) clearBtn.style.display = 'none';
        self.setFullEditorMaximized(false);
        document.getElementById('editorOverlay').classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-editor-modal');
        if (self.editorComposer) self.editorComposer.focus();
    }).catch(function() { BSDialog.toast(window.__('note.toast.get_content_failed'), 'error'); });
};

NotesApp.prototype._getNoteImageLightboxItems = function() {
    var images = document.querySelectorAll('#notesTimeline .note-card .note-content img');
    return Array.prototype.slice.call(images).map(function(img, index) {
        return {
            img: img,
            src: img.currentSrc || img.src || img.getAttribute('src') || '',
            alt: img.getAttribute('alt') || '',
            title: img.getAttribute('title') || '',
            index: index
        };
    }).filter(function(item) {
        return !!item.src;
    });
};

NotesApp.prototype._setImageLightboxItem = function(index) {
    var items = this._getNoteImageLightboxItems();
    var overlayImg = document.getElementById('noteImageLightboxImg');
    var captionEl = document.getElementById('noteImageLightboxCaption');
    var counterEl = document.getElementById('noteImageLightboxCounter');
    var prevBtn = document.getElementById('noteImageLightboxPrevBtn');
    var nextBtn = document.getElementById('noteImageLightboxNextBtn');
    if (!items.length || !overlayImg) {
        this.closeImageLightbox();
        return;
    }
    var nextIndex = Math.max(0, Math.min(index, items.length - 1));
    var item = items[nextIndex];
    this._imageLightboxIndex = nextIndex;
    overlayImg.src = item.src;
    overlayImg.alt = item.alt || item.title || '';
    if (captionEl) captionEl.textContent = item.alt || item.title || '';
    if (counterEl) counterEl.textContent = (nextIndex + 1) + ' / ' + items.length;
    if (prevBtn) prevBtn.disabled = nextIndex <= 0;
    if (nextBtn) nextBtn.disabled = nextIndex >= items.length - 1;
};

NotesApp.prototype.openImageLightbox = function(targetImg) {
    var overlay = document.getElementById('noteImageLightboxOverlay');
    if (!overlay || !targetImg) return;
    var items = this._getNoteImageLightboxItems();
    var index = items.findIndex(function(item) {
        return item.img === targetImg;
    });
    if (index < 0) return;
    this._imageLightboxPrevFocus = document.activeElement;
    overlay.classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-image-lightbox');
    this._setImageLightboxItem(index);
    this._trapImageLightbox(true);
};

NotesApp.prototype.showAdjacentImageLightbox = function(delta) {
    var items = this._getNoteImageLightboxItems();
    if (!items.length) return;
    var current = typeof this._imageLightboxIndex === 'number' ? this._imageLightboxIndex : 0;
    this._setImageLightboxItem(current + delta);
};

NotesApp.prototype.closeImageLightbox = function() {
    var overlay = document.getElementById('noteImageLightboxOverlay');
    if (overlay) overlay.classList.remove('active');
    var overlayImg = document.getElementById('noteImageLightboxImg');
    if (overlayImg) {
        overlayImg.removeAttribute('src');
        overlayImg.alt = '';
    }
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-image-lightbox');
    this._trapImageLightbox(false);
    this._imageLightboxIndex = null;
};

NotesApp.prototype.copyNoteContent = function(id) {
    var btn = document.querySelector('.note-copy-btn');
    fetchWithCurrentCSRF('/api/blogs/' + id, {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.code !== 0 || !data.data) { BSDialog.toast(window.__('note.toast.get_content_failed'), 'error'); return; }
        var text = data.data.blog_content || '';
        var done = function() { BSDialog.toast(window.__('note.toast.copied'), 'success'); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done).catch(function() {
                var ta = document.createElement('textarea');
                ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
                document.body.appendChild(ta); ta.select();
                try { document.execCommand('copy'); done(); } catch(ex) { BSDialog.toast(window.__('note.code_copy_failed'), 'error'); }
                document.body.removeChild(ta);
            });
        } else {
            var ta = document.createElement('textarea');
            ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
            document.body.appendChild(ta); ta.select();
            try { document.execCommand('copy'); done(); } catch(ex) { BSDialog.toast(window.__('note.code_copy_failed'), 'error'); }
            document.body.removeChild(ta);
        }
    }).catch(function() { BSDialog.toast(window.__('note.toast.get_content_failed'), 'error'); });
};

NotesApp.prototype._getNoteViewerIds = function() {
    var cards = document.querySelectorAll('#notesTimeline .note-card[data-id]');
    if (!cards.length) cards = document.querySelectorAll('.note-card[data-id]');
    return Array.prototype.slice.call(cards)
        .map(function(card) { return parseInt(card.dataset.id, 10); })
        .filter(function(id) { return !isNaN(id); });
};

NotesApp.prototype._updateNoteViewerNav = function() {
    var ids = this._getNoteViewerIds();
    var idx = ids.indexOf(parseInt(this._noteViewerCurrentId, 10));
    var prevBtn = document.getElementById('noteViewerPrevBtn');
    var nextBtn = document.getElementById('noteViewerNextBtn');
    if (prevBtn) prevBtn.disabled = idx <= 0;
    if (nextBtn) nextBtn.disabled = idx < 0 || idx >= ids.length - 1;
};

NotesApp.prototype._renderNoteViewerMeta = function(note) {
    var metaEl = document.getElementById('noteViewerMeta');
    if (!metaEl) return;
    var parts = [];
    var time = note.update_time || note.create_time || '';
    if (time) parts.push(String(time).substring(0, 10));
    if (note.labels && note.labels.length) {
        parts.push(note.labels.map(function(label) {
            if (typeof label === 'string') return label;
            return label && (label.name || label.label_name || label.title || label.text) || '';
        }).filter(Boolean).join(' / '));
    }
    metaEl.textContent = parts.join(' · ');
};

NotesApp.prototype.showAdjacentNoteViewer = function(delta) {
    var ids = this._getNoteViewerIds();
    var idx = ids.indexOf(parseInt(this._noteViewerCurrentId, 10));
    var nextId = idx >= 0 ? ids[idx + delta] : null;
    if (nextId === null || typeof nextId === 'undefined') return;
    this.openNoteViewer(nextId, { preserveFocus: true });
};

NotesApp.prototype.openNoteViewer = function(id, options) {
    var self = this;
    options = options || {};
    var overlay = document.getElementById('noteViewerOverlay');
    var titleEl = document.getElementById('noteViewerTitle');
    var metaEl = document.getElementById('noteViewerMeta');
    var contentEl = document.getElementById('noteViewerContent');
    if (!overlay || !contentEl) return;
    this._noteViewerCurrentId = id;
    this._noteViewerRequestToken = (this._noteViewerRequestToken || 0) + 1;
    var token = this._noteViewerRequestToken;
    if (!options.preserveFocus) this._noteViewerPrevFocus = document.activeElement;
    if (titleEl) titleEl.textContent = window.__('note.viewer.title');
    if (metaEl) metaEl.textContent = '';
    this._updateNoteViewerNav();
    contentEl.innerHTML = '<div class="note-viewer-loading">' + escHtml(window.__('common.loading') || 'Loading...') + '</div>';
    overlay.classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-viewer-modal');
    this._trapNoteViewer(true);
    fetchWithCurrentCSRF('/api/blogs/' + id, {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); }).then(function(data) {
        if (token !== self._noteViewerRequestToken) return;
        if (data.code !== 0 || !data.data) { BSDialog.toast(window.__('note.toast.get_content_failed'), 'error'); self.closeNoteViewer(); return; }
        var note = data.data;
        var text = note.blog_content || note.content_preview || note.blog_title || '';
        if (titleEl) titleEl.textContent = note.blog_title || window.__('note.viewer.title');
        self._renderNoteViewerMeta(note);
        contentEl.innerHTML = typeof marked !== 'undefined' ? marked.parse(text) : escHtml(text);
        contentEl.scrollTop = 0;
    }).catch(function() {
        if (token !== self._noteViewerRequestToken) return;
        BSDialog.toast(window.__('note.toast.get_content_failed'), 'error');
        self.closeNoteViewer();
    });
};

NotesApp.prototype.closeNoteViewer = function() {
    var overlay = document.getElementById('noteViewerOverlay');
    if (overlay) overlay.classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-viewer-modal');
    this._trapNoteViewer(false);
    var contentEl = document.getElementById('noteViewerContent');
    if (contentEl) contentEl.innerHTML = '';
    this._noteViewerCurrentId = null;
    this._noteViewerRequestToken = (this._noteViewerRequestToken || 0) + 1;
    var metaEl = document.getElementById('noteViewerMeta');
    if (metaEl) metaEl.textContent = '';
};

NotesApp.prototype.copyNoteViewerContent = function() {
    if (!this._noteViewerCurrentId) return;
    this.copyNoteContent(this._noteViewerCurrentId);
};

NotesApp.prototype.editNoteFromViewer = function() {
    var id = this._noteViewerCurrentId;
    if (!id) return;
    this.closeNoteViewer();
    this.editNote(id);
};

NotesApp.prototype._trapImageLightbox = function(on) {
    var self = this;
    if (on) {
        if (this._imageLightboxTrapHandler) return;
        this._imageLightboxTrapHandler = function(e) {
            if (e.key === 'Escape') {
                e.preventDefault();
                self.closeImageLightbox();
                return;
            }
            if (e.key === 'ArrowLeft') {
                e.preventDefault();
                self.showAdjacentImageLightbox(-1);
                return;
            }
            if (e.key === 'ArrowRight') {
                e.preventDefault();
                self.showAdjacentImageLightbox(1);
                return;
            }
            if (e.key !== 'Tab') return;
            var box = document.querySelector('#noteImageLightboxOverlay .note-image-lightbox-shell');
            if (!box) return;
            var focusable = Array.prototype.slice.call(box.querySelectorAll(_focusableSel)).filter(function(el) {
                return el.offsetParent !== null && !el.disabled;
            });
            if (!focusable.length) return;
            var first = focusable[0], last = focusable[focusable.length - 1];
            if (e.shiftKey) {
                if (document.activeElement === first) {
                    e.preventDefault();
                    last.focus();
                }
            } else if (document.activeElement === last) {
                e.preventDefault();
                first.focus();
            }
        };
        document.addEventListener('keydown', this._imageLightboxTrapHandler);
        var closeBtn = document.getElementById('noteImageLightboxCloseBtn');
        if (closeBtn) closeBtn.focus();
    } else {
        if (this._imageLightboxTrapHandler) {
            document.removeEventListener('keydown', this._imageLightboxTrapHandler);
            this._imageLightboxTrapHandler = null;
        }
        if (this._imageLightboxPrevFocus && typeof this._imageLightboxPrevFocus.focus === 'function') {
            try { this._imageLightboxPrevFocus.focus(); } catch(e) {}
            this._imageLightboxPrevFocus = null;
        }
    }
};

NotesApp.prototype._trapNoteViewer = function(on) {
    var self = this;
    if (on) {
        if (this._noteViewerTrapHandler) return;
        this._noteViewerTrapHandler = function(e) {
            if (e.key === 'Escape') { e.preventDefault(); self.closeNoteViewer(); return; }
            if (e.key === 'ArrowLeft') { e.preventDefault(); self.showAdjacentNoteViewer(-1); return; }
            if (e.key === 'ArrowRight') { e.preventDefault(); self.showAdjacentNoteViewer(1); return; }
            if (e.key !== 'Tab') return;
            var box = document.querySelector('#noteViewerOverlay .note-viewer-shell');
            if (!box) return;
            var focusable = Array.prototype.slice.call(box.querySelectorAll(_focusableSel)).filter(function(el) { return el.offsetParent !== null; });
            if (!focusable.length) return;
            var first = focusable[0], last = focusable[focusable.length - 1];
            if (e.shiftKey) { if (document.activeElement === first) { e.preventDefault(); last.focus(); } }
            else { if (document.activeElement === last) { e.preventDefault(); first.focus(); } }
        };
        document.addEventListener('keydown', this._noteViewerTrapHandler);
        var closeBtn = document.querySelector('#noteViewerOverlay .note-viewer-close');
        if (closeBtn) closeBtn.focus();
    } else {
        if (this._noteViewerTrapHandler) { document.removeEventListener('keydown', this._noteViewerTrapHandler); this._noteViewerTrapHandler = null; }
        if (this._noteViewerPrevFocus && typeof this._noteViewerPrevFocus.focus === 'function') { try { this._noteViewerPrevFocus.focus(); } catch(e) {} this._noteViewerPrevFocus = null; }
    }
};

	// ── Article actions ──

NotesApp.prototype.goArticleEdit = function(identify, id) {
    try {
        sessionStorage.setItem('notes_return_state', JSON.stringify({
            tab: this.activeTab,
            articleId: id,
            scrollTop: document.documentElement.scrollTop || document.body.scrollTop
        }));
    } catch(e) {}
    var returnUrl = '/notes?id=' + id + '&tab=' + this.activeTab;
    window.location.href = '/blogs/' + identify + '/edit?mode=preview&from=' + encodeURIComponent(returnUrl);
};

NotesApp.prototype.publishArticle = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:article:publish:' + id, this._getCardActionButton('.article-card[data-id="' + id + '"]', '.article-share-action'), function() {
        return fetchWithCurrentCSRF('/api/shares', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': self.csrf,
        },
        body: JSON.stringify({ share_type: 'blog', target_id: id }),
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); })
    .then(function(data) {
        if (data.code === 0 && data.data) {
            self.articleShareStatus[id] = true;
            self.openShareDialog('blog', id, data.data.share_identify, data.data.edit_token || '');
        } else {
            BSDialog.toast(data.message || window.__('share.toast.publish_failed'), 'error');
        }
    });
};

NotesApp.prototype.openShareDialog = function(shareType, targetId, shareIdentify, editToken) {
    this.shareDialogType = shareType;
    this.shareDialogTargetId = targetId;
    this.shareDialogIdentify = shareIdentify;
    this.shareDialogEditToken = editToken || '';

    var viewUrl = window.location.origin + '/shares/' + shareIdentify;
    document.getElementById('shareViewUrl').value = viewUrl;

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
        document.getElementById('shareEditUrl').value = viewUrl + '?token=' + editToken;
    } else {
        toggle.checked = false;
        urlSection.style.display = 'none';
        offHint.style.display = '';
        badge.textContent = '已关闭';
        badge.style.background = 'var(--color-bg-hover)';
        badge.style.color = 'var(--color-text-muted)';
        icon.style.color = 'var(--color-text-muted)';
        label.style.color = 'var(--color-text-muted)';
    }

    document.getElementById('shareSettingOverlay').classList.add('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('notes-share-modal');
};

NotesApp.prototype.unpublishArticle = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:article:unpublish:' + id, this._getCardActionButton('.article-card[data-id="' + id + '"]', '.article-share-action'), function() {
        return BSDialog.confirm2(window.__('note.confirm.unpublish')).then(function(ok) {
            if (!ok) return null;
            return fetchWithCurrentCSRF('/api/shares/blog/' + id, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': self.csrf }
            });
        });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; }).then(function(data) {
            if (!data) return;
            if (data.code === 0) {
                self.loadArticles();
                BSDialog.toast(window.__('note.toast.unpublished'), 'success');
            } else {
                BSDialog.alert2(data.message || window.__('note.toast.unpublish_failed'));
            }
        }).catch(function() { BSDialog.toast(window.__('note.toast.unpublish_failed'), 'error'); });
};

NotesApp.prototype.deleteArticle = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:article:delete:' + id, this._getCardActionButton('.article-card[data-id="' + id + '"]', '.del'), function() {
        return BSDialog.confirm2(window.__('note.confirm.delete_article')).then(function(ok) {
            if (!ok) return null;
            return fetchWithCurrentCSRF('/api/blogs/' + id, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': self.csrf }
            });
        });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; }).then(function(data) {
            if (!data) return;
            if (data.code === 0) { self.loadArticles(); BSDialog.toast(window.__('note.toast.deleted'), 'success'); }
            else { BSDialog.alert2(data.message || window.__('note.toast.delete_failed')); }
        }).catch(function() { BSDialog.toast(window.__('note.toast.delete_failed'), 'error'); });
};

NotesApp.prototype.toggleArticlePin = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:article:pin:' + id, this._getCardActionButton('.article-card[data-id="' + id + '"]', '.article-pin-action'), function() {
        return fetchWithCurrentCSRF('/api/blogs/' + id + '/pin', {
        method: 'PATCH',
        headers: { 'X-CSRF-Token': self.csrf }
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            var pinned = data.data.is_pinned;
            var card = document.querySelector('.article-card[data-id="' + id + '"]');
            if (card) {
                var btn = card.querySelector('.article-pin-action');
                if (btn) {
                    var label = pinned ? window.__('note.action.unpin') : window.__('note.action.pin');
                    btn.classList.toggle('is-pinned', pinned);
                    btn.title = label;
                    btn.setAttribute('aria-label', label);
                    btn.setAttribute('aria-pressed', pinned ? 'true' : 'false');
                    btn.innerHTML = NotesApp.pinIconHtml(pinned);
                }
                NotesApp._syncPinnedTextBadge(card.querySelector('.article-title-line'), pinned);
            }
            BSDialog.toast(pinned ? window.__('note.toast.pin') : window.__('note.toast.unpin'));
        }
    });
};

NotesApp.prototype.toggleArticleVisibility = function(id) {
    var self = this;
    var request = this._runSubmitRequest('notes:article:visibility:' + id, this._getCardActionButton('.article-card[data-id="' + id + '"]', '.vis-toggle'), function() {
        return fetchWithCurrentCSRF('/api/blogs/' + id + '/visibility', {
        method: 'PATCH',
        headers: { 'X-CSRF-Token': self.csrf }
        });
    });
    if (!request) return;
    request.then(function(r) { return r.json(); }).then(function(data) {
        if (data.code === 0) {
            var vis = data.data.visibility;
            var card = document.querySelector('.article-card[data-id="' + id + '"]');
            if (card) {
                var badge = card.querySelector('.vis-state');
                if (badge) {
                    badge.textContent = vis === 1 ? window.__('note.badge.public') : window.__('note.badge.private');
                }
                var btn = card.querySelector('.vis-toggle');
                if (btn) {
                    btn.title = vis === 1 ? window.__('note.action.set_private') : window.__('note.action.set_public');
                    btn.innerHTML = '<i class="fa-solid ' + (vis === 1 ? 'fa-eye' : 'fa-eye-slash') + '"></i>';
                }
            }
            BSDialog.toast(vis === 1 ? window.__('note.toast.vis_public') : window.__('note.toast.vis_private'), 'success');
        }
    });
};

// ── FAB ──

NotesApp.prototype.handleFab = function() {
    if (this.activeTab === 'tasks') {
        if (window.BookStarkTasks && typeof window.BookStarkTasks.openTask === 'function') {
            window.BookStarkTasks.openTask(null);
        }
        return;
    }
    if (this.activeTab === 'articles') {
        this.createArticle();
    } else {
        this.openFullEditor();
    }
};

// ── Calendar ──

NotesApp.prototype.renderCalendar = function() {
    var container = document.getElementById('calDays');
    if (!container) return;
    container.innerHTML = '';
    var year = this.calYear, month = this.calMonth;
    document.getElementById('calTitle').textContent = window.__('note.calendar_title').replace('{year}', year).replace('{month}', month);

    var firstDay = new Date(year, month - 1, 1).getDay();
    var offset = firstDay === 0 ? 6 : firstDay - 1;
    var daysInMonth = new Date(year, month, 0).getDate();
    var prevDays = new Date(year, month - 1, 0).getDate();
    var today = new Date();
    var todayStr = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0') + '-' + String(today.getDate()).padStart(2, '0');

    var countsMap = this.getCombinedDailyCountsMap();

    // Previous month
    for (var i = offset - 1; i >= 0; i--) {
        var d = prevDays - i;
        container.innerHTML += '<div class="calendar-day other-month"><span class="calendar-day-num">' + d + '</span></div>';
    }
    // Current month
    for (var day = 1; day <= daysInMonth; day++) {
        var dateStr = year + '-' + String(month).padStart(2, '0') + '-' + String(day).padStart(2, '0');
        var dc = countsMap[dateStr];
        var heatClass = '';
        var dots = '';
        if (dc) {
            var total = dc.count || 0;
            if (total >= 5) heatClass = ' heat-4';
            else if (total >= 3) heatClass = ' heat-3';
            else if (total >= 2) heatClass = ' heat-2';
            else if (total >= 1) heatClass = ' heat-1';
            var dotArr = [];
            if (dc.note_count) dotArr.push('<span class="heat-dot"></span>');
            if (dc.article_count) dotArr.push('<span class="heat-dot article"></span>');
            if (dc.task_count) dotArr.push('<span class="heat-dot task"></span>');
            if (dotArr.length) dots = '<div class="calendar-day-dots">' + dotArr.join('') + '</div>';
        }
        var isToday = dateStr === todayStr ? ' today' : '';
        var isSelected = dateStr === this.selectedDate ? ' selected' : '';
        container.innerHTML += '<div class="calendar-day' + heatClass + isToday + isSelected + '" data-date="' + dateStr + '" onclick="notesApp.selectDate(\'' + dateStr + '\')"><span class="calendar-day-num">' + day + '</span>' + dots + '</div>';
    }
    // Next month
    var totalCells = offset + daysInMonth;
    var remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
    for (var r = 1; r <= remaining; r++) {
        container.innerHTML += '<div class="calendar-day other-month"><span class="calendar-day-num">' + r + '</span></div>';
    }
};

NotesApp.prototype.selectDate = function(dateStr) {
    if (this.selectedDate === dateStr) {
        this.selectedDate = null;
    } else {
        this.selectedDate = dateStr;
    }
    this.renderCalendar();
    this.renderMobileStrip();
    this._updateDateChip();
    this.updateMobileFilterBtn();
    this.page = 1;
    this.articlePage = 1;
    if (this.activeTab === 'notes') {
        this.loadNotes();
    } else if (this.activeTab === 'articles') {
        this.loadArticles();
    } else if (window.BookStarkTasks && typeof window.BookStarkTasks.setDate === 'function') {
        window.BookStarkTasks.setDate(this.selectedDate, { reload: true });
    }
};

NotesApp.prototype.clearDateFilter = function() {
    this.selectedDate = null;
    this.renderCalendar();
    this.renderMobileStrip();
    this._updateDateChip();
    this.updateMobileFilterBtn();
    this.page = 1;
    this.articlePage = 1;
    if (this.activeTab === 'notes') {
        this.loadNotes();
    } else if (this.activeTab === 'articles') {
        this.loadArticles();
    } else if (window.BookStarkTasks && typeof window.BookStarkTasks.setDate === 'function') {
        window.BookStarkTasks.setDate(null, { reload: true });
    }
};

NotesApp.prototype._updateDateChip = function() {
    var chip = document.getElementById('chipDate');
    var text = document.getElementById('chipDateText');
    if (!chip || !text) return;
    if (this.selectedDate) {
        var parts = this.selectedDate.split('-');
        text.textContent = parts[1] + '/' + parts[2];
        chip.style.display = '';
        chip.classList.add('active');
    } else {
        chip.style.display = 'none';
        chip.classList.remove('active');
    }
};

NotesApp.prototype.prevMonth = function() {
    this.calMonth--;
    if (this.calMonth < 1) { this.calMonth = 12; this.calYear--; }
    this.loadCalendarData();
};

NotesApp.prototype.nextMonth = function() {
    this.calMonth++;
    if (this.calMonth > 12) { this.calMonth = 1; this.calYear++; }
    this.loadCalendarData();
};

NotesApp.prototype.loadCalendarData = function() {
    var self = this;
    var headers = { 'X-CSRF-Token': this.csrf };
    var blogCounts = fetchWithCurrentCSRF('/api/blogs/daily-counts?year=' + this.calYear + '&month=' + this.calMonth, {
        headers: headers
    }).then(function(r) { return r.json(); });
    var taskCounts = fetchWithCurrentCSRF('/api/tasks/daily-counts?year=' + this.calYear + '&month=' + this.calMonth, {
        headers: { 'X-CSRF-Token': this.csrf }
    }).then(function(r) { return r.json(); });
    return Promise.all([blogCounts, taskCounts]).then(function(results) {
        if (results[0] && results[0].code === 0) { self.dailyCounts = results[0].data || []; }
        if (results[1] && results[1].code === 0) { self.taskDailyCounts = results[1].data || []; }
        self.renderCalendar();
        self.renderSidebarStats();
        self.renderMobileStrip();
    });
};

// ── Sidebar stats ──

NotesApp.prototype.getCombinedDailyCountsMap = function() {
    var countsMap = {};
    (this.dailyCounts || []).forEach(function(d) {
        countsMap[d.date] = {
            date: d.date,
            count: d.count || 0,
            note_count: d.note_count || 0,
            article_count: d.article_count || 0,
            task_count: 0,
            task_done_count: 0,
            task_active_count: 0
        };
    });
    (this.taskDailyCounts || []).forEach(function(d) {
        if (!countsMap[d.date]) {
            countsMap[d.date] = {
                date: d.date,
                count: 0,
                note_count: 0,
                article_count: 0,
                task_count: 0,
                task_done_count: 0,
                task_active_count: 0
            };
        }
        countsMap[d.date].task_count += d.count || 0;
        countsMap[d.date].task_done_count += d.done_count || 0;
        countsMap[d.date].task_active_count += d.active_count || 0;
        countsMap[d.date].count += d.count || 0;
    });
    return countsMap;
};

NotesApp.prototype.renderSidebarStats = function() {
    var container = document.getElementById('sidebarStatsContent');
    if (!container) return;
    var totalNotes = 0, totalArticles = 0, totalTasks = 0, activeDays = 0;
    var activeDateSet = {};
    var countsMap = this.getCombinedDailyCountsMap();
    Object.keys(countsMap).forEach(function(date) {
        var d = countsMap[date];
        totalNotes += d.note_count || 0;
        totalArticles += d.article_count || 0;
        totalTasks += d.task_count || 0;
        if (d.count > 0) { activeDays++; activeDateSet[d.date] = true; }
    });
    var daysInMonth = new Date(this.calYear, this.calMonth, 0).getDate();
    var longestStreak = 0, currentStreak = 0;
    for (var day = 1; day <= daysInMonth; day++) {
        var dateStr = this.calYear + '-' + String(this.calMonth).padStart(2, '0') + '-' + String(day).padStart(2, '0');
        if (activeDateSet[dateStr]) {
            currentStreak++;
            if (currentStreak > longestStreak) longestStreak = currentStreak;
        } else {
            currentStreak = 0;
        }
    }
    container.innerHTML =
        '<div class="stats-row"><span class="stats-label"><span class="legend-dot note"></span>' + window.__('note.stats.notes') + '</span><span class="stats-value">' + totalNotes + '</span></div>' +
        '<div class="stats-bar"><div class="stats-bar-fill" style="width:' + Math.min(totalNotes * 5, 100) + '%;background:var(--color-success,#22c55e);"></div></div>' +
        '<div class="stats-row" style="margin-top:8px;"><span class="stats-label"><span class="legend-dot article"></span>' + window.__('note.stats.articles') + '</span><span class="stats-value">' + totalArticles + '</span></div>' +
        '<div class="stats-bar"><div class="stats-bar-fill" style="width:' + Math.min(totalArticles * 10, 100) + '%;background:var(--color-primary,#2563eb);"></div></div>' +
        '<div class="stats-row" style="margin-top:8px;"><span class="stats-label"><span class="legend-dot task"></span>' + window.__('nav.todos') + '</span><span class="stats-value">' + totalTasks + '</span></div>' +
        '<div class="stats-bar"><div class="stats-bar-fill" style="width:' + Math.min(totalTasks * 5, 100) + '%;background:var(--color-warning,#f59e0b);"></div></div>' +
        '<div class="stats-row" style="margin-top:12px;padding-top:8px;border-top:1px solid var(--color-gray-100,#f1f5f9);"><span class="stats-label">' + window.__('note.stats.active_days') + '</span><span class="stats-value">' + activeDays + ' / ' + daysInMonth + '</span></div>' +
        '<div class="stats-row"><span class="stats-label">' + window.__('note.stats.longest_streak') + '</span><span class="stats-value">' + window.__('note.stats.streak_days').replace('{n}', longestStreak) + '</span></div>';
};

// ── Mobile strip ──

NotesApp.prototype.renderMobileStrip = function() {
    var containers = ['mobileCalStrip', 'taskMobileCalStrip'].map(function(id) {
        return document.getElementById(id);
    }).filter(function(el) { return !!el; });
    if (!containers.length) return;
    var today = new Date();
    var countsMap = this.getCombinedDailyCountsMap();
    var weekdays = window.__('note.weekdays').split(',');
    var html = '';
    for (var i = 6; i >= 0; i--) {
        var d = new Date(today);
        d.setDate(d.getDate() - i);
        var dateStr = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
        var dc = countsMap[dateStr];
        var isToday = i === 0 ? ' today' : '';
        var isSelected = dateStr === this.selectedDate ? ' selected' : '';
        var dots = '';
        if (dc && dc.count > 0) {
            var dotArr = [];
            if (dc.note_count) dotArr.push('<span class="strip-dot"></span>');
            if (dc.article_count) dotArr.push('<span class="strip-dot article"></span>');
            if (dc.task_count) dotArr.push('<span class="strip-dot task"></span>');
            if (dotArr.length) dots = '<div class="strip-indicator">' + dotArr.join('') + '</div>';
        }
        html += '<div class="strip-day' + isToday + isSelected + '" data-date="' + dateStr + '" onclick="notesApp.selectDate(\'' + dateStr + '\')">' +
            '<span class="strip-label">' + weekdays[d.getDay()] + '</span>' +
            '<span class="strip-num">' + d.getDate() + '</span>' +
            dots + '</div>';
    }
    containers.forEach(function(container) { container.innerHTML = html; });
};

// ── Label filtering ──

var _pyBounds = '阿八嚓哒鹅发旮哈讥咔垃妈拿噢啪七日撒他挖希压匝';
var _pyInitials = 'ABCDEFGHJKLMNOPQRSTWXYZ';
function _getPinyinInitial(s) {
    if (!s) return '#';
    var ch = s.charAt(0);
    var code = ch.charCodeAt(0);
    if (code >= 65 && code <= 90) return ch;
    if (code >= 97 && code <= 122) return ch.toUpperCase();
    if (code < 0x4E00 || code > 0x9FFF) return '#';
    for (var i = _pyBounds.length - 1; i >= 0; i--) {
        if (ch.localeCompare(_pyBounds.charAt(i), 'zh-CN') >= 0) {
            return _pyInitials.charAt(i);
        }
    }
    return '#';
}

NotesApp.prototype.getTagColor = function(index) {
    return this.tagColors[index % this.tagColors.length];
};

NotesApp.prototype._tagGroupStorageKey = function(tab) {
    return 'bookstark:notes:tag-groups:' + (tab || this.activeTab || 'notes');
};

NotesApp.prototype._loadTagGroupState = function(tab) {
    try {
        var value = JSON.parse(localStorage.getItem(this._tagGroupStorageKey(tab)) || '{}');
        return value && typeof value === 'object' ? value : {};
    } catch (e) {
        return {};
    }
};

NotesApp.prototype._saveTagGroupState = function() {
    try {
        localStorage.setItem(this._tagGroupStorageKey(), JSON.stringify(this._letterExpanded || {}));
    } catch (e) {}
};

NotesApp.prototype._isTagGroupExpanded = function(letter) {
    if (this.tagSearchQuery) return this._tagSearchLetterExpanded[letter] !== false;
    return this._letterExpanded[letter] !== false;
};

NotesApp.prototype._filterTagLabels = function(labels) {
    var query = String(this.tagSearchQuery || '').trim().toLocaleLowerCase();
    if (!query) return labels.slice();
    return labels.filter(function(label) {
        return String(label.label_name || '').toLocaleLowerCase().indexOf(query) >= 0;
    });
};

NotesApp.prototype._groupTagLabels = function(labels) {
    var groups = {};
    var order = [];
    labels.forEach(function(label) {
        var letter = _getPinyinInitial(label.label_name);
        if (!groups[letter]) {
            groups[letter] = [];
            order.push(letter);
        }
        groups[letter].push(label);
    });
    order.sort(function(a, b) {
        if (a === '#') return 1;
        if (b === '#') return -1;
        return a.localeCompare(b, 'zh-CN');
    });
    order.forEach(function(letter) {
        groups[letter].sort(function(a, b) {
            return String(a.label_name || '').localeCompare(String(b.label_name || ''), 'zh-CN');
        });
    });
    return { groups: groups, order: order };
};

NotesApp.prototype._renderSelectedTag = function(container) {
    if (!container) return;
    if (!this.filterLabel) {
        container.innerHTML = '';
        container.hidden = true;
        return;
    }
    container.hidden = false;
    container.innerHTML =
        '<span class="sidebar-tags-selected-label">' + escHtml(window.__('note.tags.selected')) + '</span>' +
        '<button type="button" class="sidebar-tags-selected-chip" onclick="notesApp.clearLabelFilter()">' +
        '<span>' + escHtml(this.filterLabel) + '</span><i class="fa-solid fa-xmark" aria-hidden="true"></i>' +
        '<span class="sr-only">' + escHtml(window.__('note.tags.clear')) + '</span></button>';
};

NotesApp.prototype._renderTagBrowser = function(container, selectedContainer, labels) {
    if (!container) return;
    this._renderSelectedTag(selectedContainer);
    if (!labels.length) {
        container.innerHTML = '<div class="sidebar-tags-empty">' + window.__('note.tags.empty') + '</div>';
        return;
    }
    var filtered = this._filterTagLabels(labels);
    if (!filtered.length) {
        container.innerHTML = '<div class="sidebar-tags-empty">' + window.__('note.tags.no_match') + '</div>';
        return;
    }
    var self = this;
    var grouped = this._groupTagLabels(filtered);
    var chevronSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>';
    var html = '';
    grouped.order.forEach(function(letter) {
        var letterTags = grouped.groups[letter];
        var isExpanded = self._isTagGroupExpanded(letter);
        html += '<section class="tag-letter-group' + (isExpanded ? ' expanded' : '') + '">';
        html += '<button type="button" class="tag-letter-header" aria-expanded="' + (isExpanded ? 'true' : 'false') + '" onclick="notesApp.toggleLetterGroup(\'' + escAttr(letter) + '\')">';
        html += '<span class="tag-letter-chevron">' + chevronSvg + '</span>';
        html += '<span class="tag-letter-name">' + escHtml(letter) + '</span>';
        html += '<span class="tag-letter-count">' + letterTags.length + '</span>';
        html += '</button>';
        html += '<div class="tag-letter-body">';
        letterTags.forEach(function(label) {
            var name = label.label_name || '';
            var isActive = self.filterLabel === name;
            var count = label.blog_count || 0;
            html += '<button type="button" class="sidebar-tag-pill' + (isActive ? ' active' : '') + '" data-label="' + escAttr(name) + '" aria-pressed="' + (isActive ? 'true' : 'false') + '" onclick="notesApp.selectLabel(\'' + escAttr(escJs(name)) + '\')">';
            html += '<span class="sidebar-tag-name">' + escHtml(name) + '</span><span class="sidebar-tag-count">' + count + '</span></button>';
        });
        html += '</div></section>';
    });
    container.innerHTML = html;
};

NotesApp.prototype.renderLabels = function() {
    var container = document.getElementById('tagsBody');
    var countEl = document.getElementById('tagsCount');
    if (!container) return;
    var labels = this.labels || [];
    if (countEl) countEl.textContent = labels.length;
    this._renderTagBrowser(container, document.getElementById('tagsSelected'), labels);
};

NotesApp.prototype.toggleLetterGroup = function(letter) {
    if (this.tagSearchQuery) {
        this._tagSearchLetterExpanded[letter] = !this._isTagGroupExpanded(letter);
    } else {
        this._letterExpanded[letter] = !this._isTagGroupExpanded(letter);
        this._saveTagGroupState();
    }
    this.renderLabels();
    this.renderMobileTags();
};

NotesApp.prototype.setAllTagGroupsExpanded = function(expanded) {
    var grouped = this._groupTagLabels(this._filterTagLabels(this.labels || []));
    for (var i = 0; i < grouped.order.length; i++) {
        if (this.tagSearchQuery) this._tagSearchLetterExpanded[grouped.order[i]] = !!expanded;
        else this._letterExpanded[grouped.order[i]] = !!expanded;
    }
    if (!this.tagSearchQuery) this._saveTagGroupState();
    this.renderLabels();
    this.renderMobileTags();
};

NotesApp.prototype.setTagSearch = function(value) {
    var nextQuery = String(value || '').trim();
    if (nextQuery !== this.tagSearchQuery) this._tagSearchLetterExpanded = {};
    this.tagSearchQuery = nextQuery;
    var self = this;
    document.querySelectorAll('[data-note-tag-search]').forEach(function(input) {
        if (input.value !== self.tagSearchQuery) input.value = self.tagSearchQuery;
    });
    this.renderLabels();
    this.renderMobileTags();
};

NotesApp.prototype.renderMobileTags = function() {
    var container = document.getElementById('mobileTagsBar');
    if (!container) return;
    var labels = this.labels || [];
    var countEl = document.getElementById('mobileTagsCount');
    if (countEl) countEl.textContent = labels.length;
    this._renderTagBrowser(container, document.getElementById('mobileTagsSelected'), labels);
};

NotesApp.prototype.selectLabel = function(name) {
    if (this.filterLabel === name) {
        this.filterLabel = null;
    } else {
        this.filterLabel = name;
    }
    this.page = 1;
    this.articlePage = 1;
    this.renderLabels();
    this.renderMobileTags();
    this.updateFilterUI();
    this.updateMobileFilterBtn();
    if (this.activeTab === 'articles') {
        this.loadArticles();
    } else {
        this.loadNotes();
    }
};

NotesApp.prototype.clearLabelFilter = function() {
    if (!this.filterLabel) return;
    this.selectLabel(this.filterLabel);
};

NotesApp.prototype.updateLabelUI = function() {
    this.renderLabels();
    this.renderMobileTags();
};

NotesApp.prototype.updateMobileFilterBtn = function() {
    if (this.activeTab === 'tasks' && window.BookStarkTasks && typeof window.BookStarkTasks.updateFilterButton === 'function') {
        window.BookStarkTasks.updateFilterButton();
        return;
    }
    var btn = document.getElementById('mobileFilterBtn');
    if (!btn) return;
    var hasActive = this.filterLabel || this.selectedDate;
    btn.classList.toggle('has-active', !!hasActive);
};

NotesApp.prototype.toggleMobileDrawer = function() {
    if (this.activeTab === 'tasks' && window.BookStarkTasks && typeof window.BookStarkTasks.openMobileDrawer === 'function') {
        window.BookStarkTasks.openMobileDrawer();
        return;
    }
    var drawer = document.getElementById('mobileDrawer');
    var overlay = document.getElementById('mobileDrawerOverlay');
    if (!drawer) return;
    var isOpen = drawer.classList.contains('active');
    if (isOpen) {
        this.closeMobileDrawer();
    } else {
        drawer.classList.add('active');
        overlay.classList.add('active');
    }
};

NotesApp.prototype.closeMobileDrawer = function() {
    if (this.activeTab === 'tasks' && window.BookStarkTasks && typeof window.BookStarkTasks.closeMobileDrawer === 'function') {
        window.BookStarkTasks.closeMobileDrawer();
        return;
    }
    var drawer = document.getElementById('mobileDrawer');
    var overlay = document.getElementById('mobileDrawerOverlay');
    if (drawer) drawer.classList.remove('active');
    if (overlay) overlay.classList.remove('active');
};

// ── URL ID handling ──

NotesApp.prototype._handleUrlId = function() {
    var params = new URLSearchParams(window.location.search);
    var id = params.get('id') || params.get('highlight');
    if (!id) {
        var self = this;
        try {
            var saved = sessionStorage.getItem('notes_return_state');
            if (saved) {
                sessionStorage.removeItem('notes_return_state');
                var state = JSON.parse(saved);
                if (state.tab === 'articles') {
                    self._articlesLoaded = true;
                    self.switchTab('articles');
                    self.loadArticles(function() {
                        if (state.articleId) {
                            self._ensureHighlight('article-card', state.articleId, 'article');
                        } else if (state.scrollTop) {
                            window.scrollTo(0, state.scrollTop);
                        }
                    });
                    return;
                }
            }
        } catch(e) {}
        if (this.activeTab === 'articles') {
            if (!this._articlesLoaded) {
                this._articlesLoaded = true;
                this.loadArticles();
            }
        } else {
            this.loadNotes();
        }
        return;
    }
    var self = this;
    var tab = params.get('tab');
    try { sessionStorage.removeItem('notes_return_state'); } catch(e) {}
    // Clean URL
    if (window.history.replaceState) {
        var url = new URL(window.location);
        url.searchParams.delete('id');
        url.searchParams.delete('highlight');
        url.searchParams.delete('from');
        url.searchParams.delete('page');
        url.searchParams.delete('tab');
        window.history.replaceState(null, '', url.toString());
    }
    if (tab === 'articles') {
        self._articlesLoaded = true;
        self.switchTab('articles');
        self.loadArticles(function() {
            self._ensureHighlight('article-card', id, 'article');
        });
    } else if (tab === 'notes') {
        self.switchTab('notes');
        self.loadNotes(function() {
            self._ensureHighlight('note-card', id, 'note');
        });
    } else {
        // No tab param — fetch blog to determine type (backward compat)
        fetchWithCurrentCSRF('/api/blogs/' + id, { headers: { 'X-CSRF-Token': self.csrf } }).then(function(r) { return r.json(); }).then(function(data) {
            if (data.code !== 0 || !data.data) {
                self.loadNotes();
                return;
            }
            var blog = data.data;
            if (blog.blog_type === 'article') {
                self._articlesLoaded = true;
                self.switchTab('articles');
                self.loadArticles(function() {
                    self._ensureHighlight('article-card', id, 'article');
                });
            } else {
                self.loadNotes(function() {
                    self._ensureHighlight('note-card', id, 'note');
                });
            }
        }).catch(function() {
            self.loadNotes();
        });
    }
};

NotesApp.prototype._highlightItem = function(className, id) {
    var card = document.querySelector('.' + className + '[data-id="' + id + '"]');
    if (card) {
        card.scrollIntoView({ behavior: 'smooth', block: 'center' });
        card.classList.add('search-highlight');
        setTimeout(function() { card.classList.remove('search-highlight'); }, 5000);
        return true;
    }
    return false;
};

NotesApp.prototype._ensureHighlight = function(className, id, listType) {
    if (this._highlightItem(className, id)) return;
    // Not found on current page — fetch the blog and insert it at the top
    var self = this;
    fetchWithCurrentCSRF('/api/blogs/' + id, { headers: { 'X-CSRF-Token': self.csrf } }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.code !== 0 || !data.data) return;
        var blog = data.data;
        var container = listType === 'article' ? document.getElementById('articlesList') : document.getElementById('notesList');
        if (!container) return;
        var cardEl = listType === 'article' ? self.renderArticleCard(blog) : NotesApp.renderNoteCard(blog);
        container.insertBefore(cardEl, container.firstChild);
        self._highlightItem(className, id);
    });
};

// ── Image upload ──

NotesApp.prototype.uploadImageFile = function(file, composer) {
    if (!file || !file.type || file.type.indexOf('image/') !== 0) {
        BSDialog.toast(window.__('note.upload.not_image'), 'warning');
        return;
    }
    var self = this;

    function doUpload() {
        var formData = new FormData();
        formData.append('file', file);
        formData.append('category', 'note');
        csrfFetch('/api/uploads', {
            method: 'POST',
            body: formData
        }).then(function(r) {
            if (!r.ok) throw new Error('HTTP ' + r.status);
            return r.json();
        }).then(function(res) {
            if (res.code === 0 && res.data && res.data.url) {
                self.insertMarkdownImage(composer, file.name, res.data.url);
                BSDialog.toast(window.__('note.toast.image_upload_success'), 'success');
            } else {
                BSDialog.toast((res && res.message) || window.__('note.toast.image_upload_failed'), 'error');
            }
        }).catch(function() {
            BSDialog.toast(window.__('note.toast.image_upload_failed'), 'error');
        });
    }

    // Hash pre-check: skip upload if file already exists on server
    computeFileHash(file).then(function(hash) {
        return checkUploadByHash(hash);
    }).then(function(existing) {
        if (existing && existing.url) {
            self.insertMarkdownImage(composer, file.name, existing.url);
            BSDialog.toast(window.__('note.toast.image_reused'), 'success');
        } else {
            doUpload();
        }
    }).catch(function() {
        doUpload();
    });
};

NotesApp.prototype.insertMarkdownImage = function(composer, filename, url) {
    if (!composer) return;
    var name = filename.replace(/\.[^.]+$/, '');
    var md = '![' + name + '](' + url + ')';
    composer.insertAtCursor(md);
};

NotesApp.prototype._setupDropZone = function(zone, composerGetter) {
    var self = this;
    var dragCounter = 0;
    zone.addEventListener('dragenter', function(e) {
        e.preventDefault();
        dragCounter++;
        zone.classList.add('notes-drop-active');
    });
    zone.addEventListener('dragover', function(e) {
        e.preventDefault();
    });
    zone.addEventListener('dragleave', function(e) {
        e.preventDefault();
        dragCounter--;
        if (dragCounter <= 0) {
            dragCounter = 0;
            zone.classList.remove('notes-drop-active');
        }
    });
    zone.addEventListener('drop', function(e) {
        e.preventDefault();
        dragCounter = 0;
        zone.classList.remove('notes-drop-active');
        var composer = typeof composerGetter === 'function' ? composerGetter() : composerGetter;
        if (!composer) return;
        if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
            for (var i = 0; i < e.dataTransfer.files.length; i++) {
                var file = e.dataTransfer.files[i];
                if (file.type && file.type.indexOf('image/') === 0) {
                    self.uploadImageFile(file, composer);
                }
            }
        }
    });
};

// Use global escHtml/escAttr from utils.js; provide fallback only if not loaded
if (typeof escHtml !== 'function') { window.escHtml = function(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }; }
if (typeof escAttr !== 'function') { window.escAttr = function(s) { return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }; }

window.toggleShareEdit = function() {
    var app = window.notesApp;
    var toggle = document.getElementById('shareEditToggle');
    var action = toggle.checked ? 'enable' : 'disable';

    var request = app._runSubmitRequest('notes:share:edit-token:' + app.shareDialogType + ':' + app.shareDialogTargetId, toggle, function() {
        return fetchWithCurrentCSRF('/api/shares/' + app.shareDialogType + '/' + app.shareDialogTargetId + '/edit-token', {
        method: 'PATCH',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': app.csrf,
        },
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
            app.shareDialogEditToken = data.data.edit_token;
            app.openShareDialog(app.shareDialogType, app.shareDialogTargetId, app.shareDialogIdentify, data.data.edit_token);
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
    var app = window.notesApp;
    var request = app._runSubmitRequest('notes:share:reset-token:' + app.shareDialogType + ':' + app.shareDialogTargetId, null, function() {
        return BSDialog.confirm2(window.__('share.toast.reset_confirm')).then(function(ok) {
            if (!ok) return null;
            return fetchWithCurrentCSRF('/api/shares/' + app.shareDialogType + '/' + app.shareDialogTargetId + '/edit-token', {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': app.csrf,
            },
            body: JSON.stringify({ action: 'reset' }),
            });
        });
    });
    if (!request) return;
    request.then(function(r) { return r ? r.json() : null; })
        .then(function(data) {
            if (!data) return;
            if (data.code === 0) {
                app.shareDialogEditToken = data.data.edit_token;
                app.openShareDialog(app.shareDialogType, app.shareDialogTargetId, app.shareDialogIdentify, data.data.edit_token);
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
    document.getElementById('shareSettingOverlay').classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('notes-share-modal');
};

window.unpublishFromDialog = function() {
    var app = window.notesApp;
    var request = app._runSubmitRequest('notes:share:unpublish:' + app.shareDialogType + ':' + app.shareDialogTargetId, document.querySelector('#shareSettingOverlay .editor-modal-cancel'), function() {
        return BSDialog.confirm2(window.__('share.toast.unpublish_confirm')).then(function(ok) {
            if (!ok) return null;
            return fetchWithCurrentCSRF('/api/shares/' + app.shareDialogType + '/' + app.shareDialogTargetId, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': app.csrf },
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
                app.loadArticles();
            } else {
                BSDialog.toast(data.message || window.__('share.toast.op_failed'), 'error');
            }
        });
};
