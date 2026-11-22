/* TagInput — shared tag input component with search/autocomplete
   Usage:
     var ti = new TagInput(document.getElementById('myContainer'), {
       placeholder: '搜索或新建标签...',
       existingTags: ['go', 'sqlite'],  // pre-filled tags
       pageSize: 10,
       sortBy: 'recent'                 // default sort when input is empty
     });
     ti.getTags()   // => 'go,sqlite'
     ti.setTags(['go','sqlite'])
     ti.clear()
*/
function TagInput(container, opts) {
    if (!container) return;
    this.container = container;
    this.placeholder = (opts && opts.placeholder) || '搜索或新建标签...';
    this.pageSize = (opts && opts.pageSize) || 10;
    this.sortBy = (opts && opts.sortBy) || 'recent';
    this.useSheet = !!(opts && opts.useSheet);
    this.tags = (opts && opts.existingTags) ? opts.existingTags.slice() : [];
    this.summaryLimit = (opts && opts.summaryLimit) || 4;
    this._tagsExpanded = false;
    this._searchTimer = null;
    this._searchVersion = 0;
    this._uid = 'ti_' + (++TagInput._counter);
    this._scrollHandler = null;
    this._outsideClickHandler = null;
    this._containerClickHandler = null;
    this._sheet = null;
    this._pendingDropdownFocus = null;
    this._activeDropdownIndex = -1;
    this.render();
    this.bindEvents();
}

TagInput._counter = 0;
TagInput._activeSheet = null;

TagInput.prototype._t = function(key, fallback) {
    if (typeof window.__ !== 'function') return fallback;
    var text = window.__(key);
    return text && text !== key ? text : fallback;
};

TagInput.prototype._isMobile = function() {
    return this.useSheet && window.innerWidth <= 640;
};

TagInput.prototype._markInputAsNonCredential = function(input) {
    if (!input) return;
    input.setAttribute('autocomplete', 'off');
    input.setAttribute('autocapitalize', 'off');
    input.setAttribute('spellcheck', 'false');
    input.setAttribute('data-form-type', 'other');
    input.setAttribute('data-lpignore', 'true');
    input.setAttribute('data-1p-ignore', 'true');
    input.setAttribute('data-bwignore', 'true');
    input.setAttribute('data-dashlane-disabled', 'true');
    input.setAttribute('data-protonpass-ignore', 'true');
    input.setAttribute('data-keeper-ignore', 'true');
    if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') {
        window.BookStarkFormGuards.markNonCredentialInput(input);
    }
};

TagInput.prototype._markEditableAsNonCredential = function(field) {
    if (!field) return;
    field.setAttribute('role', 'textbox');
    field.setAttribute('aria-multiline', 'false');
    field.setAttribute('tabindex', '0');
    field.setAttribute('autocapitalize', 'off');
    field.setAttribute('spellcheck', 'false');
    field.setAttribute('data-form-type', 'other');
    field.setAttribute('data-lpignore', 'true');
    field.setAttribute('data-1p-ignore', 'true');
    field.setAttribute('data-bwignore', 'true');
    field.setAttribute('data-dashlane-disabled', 'true');
    field.setAttribute('data-protonpass-ignore', 'true');
    field.setAttribute('data-keeper-ignore', 'true');
    field.setAttribute('data-empty', 'true');
};

TagInput.prototype._setEditableEnabled = function(field, enabled) {
    if (!field) return;
    if (enabled) {
        field.setAttribute('contenteditable', 'plaintext-only');
    } else {
        field.setAttribute('contenteditable', 'false');
    }
};

TagInput.prototype._getFieldValue = function(field) {
    if (!field) return '';
    if ('value' in field) return field.value || '';
    return (field.textContent || '').replace(/\u00a0/g, ' ');
};

TagInput.prototype._setFieldValue = function(field, value) {
    if (!field) return;
    if ('value' in field) field.value = value || '';
    else field.textContent = value || '';
    this._syncFieldEmpty(field);
};

TagInput.prototype._syncFieldEmpty = function(field) {
    if (!field || 'value' in field) return;
    field.setAttribute('data-empty', this._getFieldValue(field).trim() ? 'false' : 'true');
};

TagInput.prototype._insertPlainText = function(text) {
    if (!text) return;
    if (document.queryCommandSupported && document.queryCommandSupported('insertText')) {
        document.execCommand('insertText', false, text);
        return;
    }
    var sel = window.getSelection && window.getSelection();
    if (!sel || !sel.rangeCount) return;
    var range = sel.getRangeAt(0);
    range.deleteContents();
    range.insertNode(document.createTextNode(text));
    range.collapse(false);
    sel.removeAllRanges();
    sel.addRange(range);
};

TagInput.prototype._splitTagText = function(text) {
    return String(text || '').split(/[,，;\n\r]+/).map(function(name) {
        return name.trim();
    }).filter(function(name) {
        return !!name;
    });
};

TagInput.prototype._commitInputValue = function() {
    var input = this._isSheetOpen()
        ? this._sheet.root.querySelector('.tag-input-sheet-field')
        : this.container.querySelector('.tag-input-field');
    if (!input) return;
    var values = this._splitTagText(this._getFieldValue(input));
    if (!values.length) return;
    this._setFieldValue(input, '');
    for (var i = 0; i < values.length; i++) this.addTag(values[i]);
};

TagInput.prototype.render = function() {
    this._cancelPendingSearch();
    var c = this.container;
    c.classList.add('tag-input-container');
    c.innerHTML = '';
    // Remove old dropdown from body if re-rendering
    var oldDD = this.getDropdown();
    if (oldDD) oldDD.remove();
    var self = this;
    var selected = document.createElement('div');
    selected.className = 'tag-input-selected';
    selected.setAttribute('aria-live', 'polite');
    c.appendChild(selected);
    // Input
    var inputRow = document.createElement('div');
    inputRow.className = 'tag-input-search-row';
    var input = document.createElement('div');
    input.className = 'tag-input-field';
    input.id = this._uid + '_field';
    input.setAttribute('data-placeholder', this.placeholder);
    input.setAttribute('aria-label', this.placeholder);
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-controls', this._uid + '_dropdown');
    this._markEditableAsNonCredential(input);
    this._setEditableEnabled(input, !this._isMobile());
    inputRow.appendChild(input);
    selected.appendChild(inputRow);
    this._renderSelectedTags();
    // Dropdown — appended to body to escape overflow clipping
    var dd = document.createElement('div');
    dd.className = 'tag-input-dropdown hidden';
    dd.id = this._uid + '_dropdown';
    dd.setAttribute('data-ti-uid', this._uid);
    dd.setAttribute('role', 'listbox');
    dd.addEventListener('keydown', function(e) {
        self._handleDropdownKey(e);
    });
    document.body.appendChild(dd);
};

TagInput.prototype._createChip = function(name) {
    var self = this;
    var s = document.createElement('span');
    s.className = 'tag-input-chip';
    s.setAttribute('data-tag', name);
    s.innerHTML = '<span class="tag-input-chip-label">' + (typeof escHtml === 'function' ? escHtml(name) : name) + '</span><span class="tag-input-remove">&times;</span>';
    s.querySelector('.tag-input-remove').addEventListener('click', function(e) {
        e.stopPropagation();
        self.removeTag(name);
    });
    return s;
};

TagInput.prototype._renderSelectedTags = function() {
    var selected = this.container.querySelector('.tag-input-selected');
    if (!selected) return;
    var self = this;
    var inputRow = selected.querySelector('.tag-input-search-row');
    selected.innerHTML = '';
    selected.classList.toggle('expanded', this._tagsExpanded);
    selected.classList.toggle('empty', !this.tags.length);
    if (!this.tags.length) {
        if (inputRow) selected.appendChild(inputRow);
        return;
    }

    var visibleTags = this._tagsExpanded ? this.tags : this.tags.slice(0, this.summaryLimit);
    visibleTags.forEach(function(name) {
        selected.appendChild(self._createChip(name));
    });
    var hiddenCount = this.tags.length - visibleTags.length;
    if (hiddenCount > 0 || this._tagsExpanded) {
        var more = document.createElement('button');
        more.type = 'button';
        more.className = 'tag-input-more';
        more.textContent = this._tagsExpanded ? this._t('tag_input.collapse', '收起') : '+' + hiddenCount;
        more.setAttribute('aria-expanded', this._tagsExpanded ? 'true' : 'false');
        more.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            self._tagsExpanded = !self._tagsExpanded;
            self._renderSelectedTags();
        });
        selected.appendChild(more);
    }
    if (inputRow) selected.appendChild(inputRow);
};

TagInput.prototype.getDropdown = function() {
    return document.querySelector('.tag-input-dropdown[data-ti-uid="' + this._uid + '"]');
};

TagInput.prototype._positionDropdown = function() {
    var dd = this.getDropdown();
    if (!dd || dd.classList.contains('hidden')) return;
    if (this._isMobile()) {
        this.hideDropdown();
        return;
    }
    var rect = this.container.getBoundingClientRect();
    dd.style.left = rect.left + 'px';
    dd.style.width = rect.width + 'px';
    dd.style.top = (rect.bottom + 4) + 'px';
    dd.style.bottom = 'auto';
};

TagInput.prototype.bindEvents = function() {
    var self = this;
    // Unbind previous global listeners if any
    if (this._scrollHandler) {
        window.removeEventListener('resize', this._scrollHandler);
        window.removeEventListener('scroll', this._scrollHandler, true);
    }
    if (this._outsideClickHandler) {
        document.removeEventListener('click', this._outsideClickHandler);
    }
    if (this._containerClickHandler) {
        this.container.removeEventListener('click', this._containerClickHandler);
    }
    var input = this.container.querySelector('.tag-input-field');
    if (!input) return;
    this._containerClickHandler = function() {
        if (self._isMobile()) self.openMobileSheet();
        else input.focus();
    };
    this.container.addEventListener('click', this._containerClickHandler);
    input.addEventListener('input', function() {
        self._syncFieldEmpty(input);
        if (!self._isMobile()) self.search();
    });
    input.addEventListener('paste', function(e) {
        var text = e.clipboardData && e.clipboardData.getData('text');
        e.preventDefault();
        if (!text) return;
        if (/[,，;\n\r]/.test(text)) {
            self._splitTagText(text).forEach(function(name) { self.addTag(name); });
        } else {
            self._insertPlainText(text);
            self._syncFieldEmpty(input);
            if (!self._isMobile()) self.search();
        }
    });
    input.addEventListener('keydown', function(e) {
        if (self._isMobile()) {
            if (e.key === 'Enter' || e.key === ',' || e.key === ' ') {
                e.preventDefault();
                self.openMobileSheet();
            }
            return;
        }
        if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault();
            if (e.key === 'Enter' && self._isDropdownOpen() && self._clickActiveDropdownItem()) return;
            var v = self._getFieldValue(input).trim().replace(/[,，;]$/, '');
            if (v) self.addTag(v);
            else self.hideDropdown();
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            if (self._isDropdownOpen() && self._dropdownItems().length) {
                self._moveDropdownFocus(e.key === 'ArrowDown' ? 1 : -1);
            } else {
                self._pendingDropdownFocus = e.key === 'ArrowDown' ? 0 : -1;
                self.search();
            }
        }
        if (e.key === 'Escape') {
            e.preventDefault();
            self.hideDropdown();
            input.focus();
        }
        // Backspace on empty input removes last tag
        if (e.key === 'Backspace' && !self._getFieldValue(input)) {
            var last = self.tags[self.tags.length - 1];
            if (last) self.removeTag(last);
        }
    });
    input.addEventListener('focus', function() {
        if (self._isMobile()) {
            self.openMobileSheet();
            input.blur();
        } else {
            self.search();
        }
    });
    // Reposition on scroll/resize
    this._scrollHandler = function() {
        var field = self.container.querySelector('.tag-input-field');
        if (field) self._setEditableEnabled(field, !self._isMobile());
        self._positionDropdown();
    };
    window.addEventListener('resize', this._scrollHandler);
    window.addEventListener('scroll', this._scrollHandler, true);
    // Close dropdown on outside click
    this._outsideClickHandler = function(e) {
        var dd = self.getDropdown();
        if (!self.container.contains(e.target) && (!dd || !dd.contains(e.target))) {
            self.hideDropdown();
        }
    };
    document.addEventListener('click', this._outsideClickHandler);
};

TagInput.prototype.search = function() {
    var self = this;
    clearTimeout(this._searchTimer);
    var searchVersion = ++this._searchVersion;
    this._searchTimer = setTimeout(function() {
        self._searchTimer = null;
        var q = self._getSearchValue();
        self._fetchLabels(q).then(function(labels) {
            if (searchVersion !== self._searchVersion) return;
            if (self._isSheetOpen()) {
                self._renderSheetResults(labels, q);
                return;
            }
            var input = self.container.querySelector('.tag-input-field');
            if (!input || document.activeElement !== input) return;
            self._renderDropdown(labels, q);
            if (self._pendingDropdownFocus !== null) {
                self._focusDropdownItem(self._pendingDropdownFocus);
                self._pendingDropdownFocus = null;
            }
        }).catch(function() {
            if (searchVersion !== self._searchVersion) return;
            if (self._isSheetOpen()) self._renderSheetError();
        });
    }, 300);
};

TagInput.prototype._renderDropdown = function(labels, q) {
    var self = this;
    var dd = this.getDropdown();
    if (!dd) return;
    q = (q || '').trim();
    var items = (labels || []).filter(function(l) {
        return l && l.label_name && self.tags.indexOf(l.label_name) < 0;
    });
    var exact = q && (this.tags.indexOf(q) >= 0 || items.some(function(l) { return l.label_name === q; }));
    var html = '';
    if (q && !exact) {
        html += '<div class="tag-input-dd-item tag-input-dd-create" tabindex="-1" role="option" aria-selected="false" data-create="' + (typeof escAttr === 'function' ? escAttr(q) : q) + '"><span>创建「' + (typeof escHtml === 'function' ? escHtml(q) : q) + '」</span><span class="tag-input-dd-count">Enter</span></div>';
    }
    html += items.map(function(l) {
        return '<div class="tag-input-dd-item" tabindex="-1" role="option" aria-selected="false" data-label="' + (typeof escAttr === 'function' ? escAttr(l.label_name) : l.label_name) + '"><span>' + (typeof escHtml === 'function' ? escHtml(l.label_name) : l.label_name) + '</span><span class="tag-input-dd-count">' + (l.bookmark_count || 0) + '签</span></div>';
    }).join('');
    dd.innerHTML = html;
    this._activeDropdownIndex = -1;
    if (!html) {
        this.hideDropdown();
        return;
    }
    dd.classList.remove('hidden');
    dd.querySelectorAll('.tag-input-dd-item[data-label], .tag-input-dd-item[data-create]').forEach(function(el) {
        el.addEventListener('mousedown', function(e) { e.preventDefault(); });
        el.addEventListener('click', function() {
            self.addTag(el.getAttribute('data-label') || el.getAttribute('data-create'));
        });
    });
    this._positionDropdown();
};

TagInput.prototype._getSearchValue = function() {
    if (this._isSheetOpen()) {
        var sheetInput = this._sheet.root.querySelector('.tag-input-sheet-field');
        return sheetInput ? this._getFieldValue(sheetInput).trim() : '';
    }
    var input = this.container.querySelector('.tag-input-field');
    return input ? this._getFieldValue(input).trim() : '';
};

TagInput.prototype._fetchLabels = function(q) {
    var params = 'page_size=' + this.pageSize;
    var url = '/api/labels?';
    if (!q) {
        url = '/api/labels/recommendations?';
    } else {
        params += '&sort_by=bookmark&sort_order=desc&keyword=' + encodeURIComponent(q);
    }
    return fetch(url + params).then(function(r) { return r.json(); }).then(function(d) {
        return d.data || [];
    });
};

TagInput.prototype._ensureSheet = function() {
    if (this._sheet) return this._sheet;
    var self = this;
    var root = document.createElement('div');
    root.className = 'tag-input-sheet-root hidden';
    root.setAttribute('data-ti-uid', this._uid);
    root.innerHTML =
        '<div class="tag-input-sheet-backdrop tag-popover-overlay"></div>' +
        '<div class="tag-input-sheet tag-popover" role="dialog" aria-modal="true" data-mobile-sheet data-mobile-sheet-panel="self">' +
        '  <div class="tag-input-sheet-header tag-popover-header">' +
        '    <div class="tag-input-sheet-title tag-popover-title">' + (typeof escHtml === 'function' ? escHtml(this._t('tag_input.sheet.title', '标签')) : '标签') + '</div>' +
        '    <button type="button" class="tag-input-sheet-done tag-popover-close" aria-label="' + (typeof escAttr === 'function' ? escAttr(this._t('tag_input.sheet.done', '完成')) : '完成') + '">&times;</button>' +
        '  </div>' +
        '  <div class="tag-popover-body">' +
        '    <div class="tag-input-sheet-selected tag-popover-chips"></div>' +
        '    <div class="tag-input-sheet-search tag-input-wrap">' +
        '      <i class="fa-solid fa-magnifying-glass tag-input-icon"></i>' +
        '      <div class="tag-input-sheet-field tag-input" id="' + this._uid + '_sheet_field" data-placeholder="' + (typeof escAttr === 'function' ? escAttr(this.placeholder) : this.placeholder) + '" aria-label="' + (typeof escAttr === 'function' ? escAttr(this.placeholder) : this.placeholder) + '"></div>' +
        '    </div>' +
        '  </div>' +
        '  <div class="tag-input-sheet-results tag-popover-dropdown"></div>' +
        '</div>';
    document.body.appendChild(root);
    if (window.BookStarkMobileUI && typeof window.BookStarkMobileUI.enhanceSheet === 'function') {
        window.BookStarkMobileUI.enhanceSheet(root, {
            panelSelector: '.tag-popover',
            close: function() { self.closeMobileSheet(); }
        });
    }
    var field = root.querySelector('.tag-input-sheet-field');
    this._markEditableAsNonCredential(field);
    this._setEditableEnabled(field, true);
    root.querySelector('.tag-input-sheet-backdrop').addEventListener('click', function() { self.closeMobileSheet(); });
    root.querySelector('.tag-input-sheet-done').addEventListener('click', function() { self.closeMobileSheet(); });
    root.querySelector('.tag-input-sheet').addEventListener('click', function(e) { e.stopPropagation(); });
    field.addEventListener('input', function() {
        self._syncFieldEmpty(field);
        self.search();
    });
    field.addEventListener('paste', function(e) {
        var text = e.clipboardData && e.clipboardData.getData('text');
        e.preventDefault();
        if (!text) return;
        if (/[,，;\n\r]/.test(text)) {
            self._splitTagText(text).forEach(function(name) { self.addTag(name); });
        } else {
            self._insertPlainText(text);
            self._syncFieldEmpty(field);
            self.search();
        }
    });
    field.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            self.closeMobileSheet();
            return;
        }
        if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault();
            var v = self._getFieldValue(field).trim().replace(/[,，;]$/, '');
            if (v) self.addTag(v);
        }
    });
    this._sheet = { root: root };
    return this._sheet;
};

TagInput.prototype._isSheetOpen = function() {
    return !!(this._sheet && !this._sheet.root.classList.contains('hidden'));
};

TagInput.prototype.openMobileSheet = function() {
    if (!this._isMobile()) return;
    if (TagInput._activeSheet && TagInput._activeSheet !== this) {
        TagInput._activeSheet.closeMobileSheet();
    }
    TagInput._activeSheet = this;
    this.hideDropdown();
    var sheet = this._ensureSheet();
    sheet.root.classList.remove('hidden');
    sheet.root.querySelector('.tag-input-sheet-backdrop').classList.add('active');
    sheet.root.querySelector('.tag-input-sheet').classList.add('active');
    document.body.classList.add('tag-input-sheet-open');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('tag-input-sheet');
    this._renderSheetSelected();
    var field = sheet.root.querySelector('.tag-input-sheet-field');
    if (field) this._setFieldValue(field, '');
    this.search();
    setTimeout(function() { if (field) field.focus(); }, 40);
};

TagInput.prototype.closeMobileSheet = function() {
    if (!this._sheet) return;
    this._sheet.root.classList.add('hidden');
    this._sheet.root.querySelector('.tag-input-sheet-backdrop').classList.remove('active');
    this._sheet.root.querySelector('.tag-input-sheet').classList.remove('active');
    if (TagInput._activeSheet === this) TagInput._activeSheet = null;
    document.body.classList.remove('tag-input-sheet-open');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('tag-input-sheet');
    var field = this._sheet.root.querySelector('.tag-input-sheet-field');
    if (field) this._setFieldValue(field, '');
};

TagInput.prototype._renderSheetSelected = function() {
    if (!this._sheet) return;
    var self = this;
    var selected = this._sheet.root.querySelector('.tag-input-sheet-selected');
    if (!selected) return;
    if (!this.tags.length) {
        selected.innerHTML = '';
        return;
    }
    selected.innerHTML = '';
    this.tags.forEach(function(name) {
        var chip = document.createElement('span');
        chip.className = 'tag-chip';
        chip.setAttribute('data-tag', name);
        chip.innerHTML = (typeof escHtml === 'function' ? escHtml(name) : name) + ' <span class="tag-remove" title="' + (typeof escAttr === 'function' ? escAttr(self._t('tag_input.remove', '移除')) : '移除') + '" aria-label="' + (typeof escAttr === 'function' ? escAttr(self._t('tag_input.remove', '移除') + ' ' + name) : '移除 ' + name) + '">&times;</span>';
        var remove = chip.querySelector('.tag-remove');
        if (remove) {
            remove.addEventListener('click', function(e) {
                e.stopPropagation();
                self.removeTag(name);
            });
        }
        selected.appendChild(chip);
    });
};

TagInput.prototype._renderSheetResults = function(labels, q) {
    if (!this._sheet) return;
    var self = this;
    var results = this._sheet.root.querySelector('.tag-input-sheet-results');
    if (!results) return;
    var exact = labels.some(function(l) { return l.label_name === q; });
    var html = labels.map(function(l) {
        var name = l.label_name || '';
        var selected = self.tags.indexOf(name) >= 0;
        return '<button type="button" class="tag-input-sheet-item tag-dropdown-item' + (selected ? ' selected' : '') + '" data-label="' + (typeof escAttr === 'function' ? escAttr(name) : name) + '">' +
            '<span class="tag-input-sheet-name tag-item-name">' + (typeof escHtml === 'function' ? escHtml(name) : name) + '</span>' +
            '<span class="tag-input-sheet-count tag-item-count">' + (l.bookmark_count || 0) + '签</span>' +
        '</button>';
    }).join('');
    if (q && !exact && self.tags.indexOf(q) < 0) {
        html += '<button type="button" class="tag-input-sheet-item tag-dropdown-item create" data-create="' + (typeof escAttr === 'function' ? escAttr(q) : q) + '">' +
            '<span class="tag-input-sheet-name tag-item-name">' + (typeof escHtml === 'function' ? escHtml(this._t('tag_input.sheet.create', '创建')) : '创建') + '「' + (typeof escHtml === 'function' ? escHtml(q) : q) + '」</span>' +
        '</button>';
    }
    if (!html) {
        html = '<div class="tag-input-sheet-empty">' + (typeof escHtml === 'function' ? escHtml(this._t('tag_input.sheet.empty', '暂无标签')) : '暂无标签') + '</div>';
    }
    results.innerHTML = html;
    results.querySelectorAll('.tag-input-sheet-item[data-label]').forEach(function(el) {
        el.addEventListener('click', function() {
            var name = el.getAttribute('data-label');
            if (self.tags.indexOf(name) >= 0) self.removeTag(name);
            else self.addTag(name);
        });
    });
    results.querySelectorAll('.tag-input-sheet-item[data-create]').forEach(function(el) {
        el.addEventListener('click', function() {
            self.addTag(el.getAttribute('data-create'));
        });
    });
};

TagInput.prototype._renderSheetError = function() {
    if (!this._sheet) return;
    var results = this._sheet.root.querySelector('.tag-input-sheet-results');
    if (results) {
        results.innerHTML = '<div class="tag-input-sheet-empty">' + (typeof escHtml === 'function' ? escHtml(this._t('tag_input.sheet.error', '加载失败')) : '加载失败') + '</div>';
    }
};

TagInput.prototype.addTag = function(name) {
    name = name.trim();
    if (!name || this.tags.indexOf(name) >= 0) return;
    this.tags.push(name);
    var input = this.container.querySelector('.tag-input-field');
    if (input) this._setFieldValue(input, '');
    this._renderSelectedTags();
    if (this._isSheetOpen()) {
        var sheetInput = this._sheet.root.querySelector('.tag-input-sheet-field');
        if (sheetInput) this._setFieldValue(sheetInput, '');
        this._renderSheetSelected();
        this.search();
    } else if (input) {
        if (this._isMobile()) {
            this.hideDropdown();
        } else {
            input.focus();
            this.hideDropdown();
        }
    }
    if (typeof this.onTagChange === 'function') this.onTagChange();
};

TagInput.prototype.removeTag = function(name) {
    var idx = this.tags.indexOf(name);
    if (idx < 0) return;
    this.tags.splice(idx, 1);
    if (this.tags.length <= this.summaryLimit) this._tagsExpanded = false;
    this._renderSelectedTags();
    if (this._isSheetOpen()) {
        this._renderSheetSelected();
        this.search();
    }
    if (typeof this.onTagChange === 'function') this.onTagChange();
};

TagInput.prototype.hideDropdown = function() {
    this._cancelPendingSearch();
    var dd = this.getDropdown();
    if (dd) dd.classList.add('hidden');
    this._pendingDropdownFocus = null;
    this._activeDropdownIndex = -1;
    var input = this.container.querySelector('.tag-input-field');
    if (input) input.removeAttribute('aria-activedescendant');
};

TagInput.prototype._cancelPendingSearch = function() {
    clearTimeout(this._searchTimer);
    this._searchTimer = null;
    this._searchVersion += 1;
};

TagInput.prototype._isDropdownOpen = function() {
    var dd = this.getDropdown();
    return !!(dd && !dd.classList.contains('hidden'));
};

TagInput.prototype._dropdownItems = function() {
    var dd = this.getDropdown();
    if (!dd) return [];
    return Array.prototype.slice.call(dd.querySelectorAll('.tag-input-dd-item')).filter(function(item) {
        return item.offsetParent !== null;
    });
};

TagInput.prototype._setActiveDropdownItem = function(items, activeItem) {
    var input = this.container.querySelector('.tag-input-field');
    items.forEach(function(item) {
        var active = item === activeItem;
        item.classList.toggle('active', active);
        if (item.getAttribute('role') === 'option') {
            item.setAttribute('aria-selected', active ? 'true' : 'false');
        }
    });
    if (input) {
        if (activeItem && activeItem.id) input.setAttribute('aria-activedescendant', activeItem.id);
        else input.removeAttribute('aria-activedescendant');
    }
};

TagInput.prototype._focusDropdownItem = function(index) {
    var items = this._dropdownItems();
    if (!items.length) return null;
    var next = (index + items.length) % items.length;
    var item = items[next];
    if (!item.id) item.id = this._uid + '_option_' + next;
    this._activeDropdownIndex = next;
    this._setActiveDropdownItem(items, item);
    item.scrollIntoView({ block: 'nearest' });
    return item;
};

TagInput.prototype._moveDropdownFocus = function(direction) {
    var items = this._dropdownItems();
    if (!items.length) return null;
    var index = this._activeDropdownIndex;
    if (index < 0) index = items.findIndex(function(item) { return item.classList.contains('active'); });
    if (index < 0) index = direction > 0 ? -1 : 0;
    return this._focusDropdownItem(index + direction);
};

TagInput.prototype._clickActiveDropdownItem = function() {
    var items = this._dropdownItems();
    if (!items.length) return false;
    var item = items.indexOf(document.activeElement) >= 0
        ? document.activeElement
        : items.find(function(node) { return node.classList.contains('active'); });
    if (!item || (!item.getAttribute('data-label') && !item.getAttribute('data-create'))) return false;
    item.click();
    return true;
};

TagInput.prototype._handleDropdownKey = function(e) {
    var input = this.container.querySelector('.tag-input-field');
    if (e.key === 'ArrowDown') {
        e.preventDefault();
        this._moveDropdownFocus(1);
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        this._moveDropdownFocus(-1);
    } else if (e.key === 'Home') {
        e.preventDefault();
        this._focusDropdownItem(0);
    } else if (e.key === 'End') {
        e.preventDefault();
        this._focusDropdownItem(-1);
    } else if (e.key === 'Enter') {
        e.preventDefault();
        if (!this._clickActiveDropdownItem() && input && this._getFieldValue(input).trim()) this.addTag(this._getFieldValue(input).trim());
    } else if (e.key === 'Escape') {
        e.preventDefault();
        this.hideDropdown();
        if (input) input.focus();
    } else if (e.key === 'Tab') {
        this.hideDropdown();
    }
};

TagInput.prototype.getTags = function() {
    this._commitInputValue();
    return this.tags.join(',');
};

TagInput.prototype.getTagList = function() {
    this._commitInputValue();
    return this.tags.slice();
};

TagInput.prototype.setTags = function(tags) {
    var values;
    if (typeof tags === 'string') {
        values = tags ? tags.split(',') : [];
    } else {
        values = tags ? tags.slice() : [];
    }
    this.tags = [];
    values.forEach(function(tag) {
        var name = String(tag || '').trim();
        if (name && this.tags.indexOf(name) < 0) this.tags.push(name);
    }, this);
    this._tagsExpanded = false;
    this.render();
    this.bindEvents();
};

TagInput.prototype.clear = function() {
    this.tags = [];
    this._tagsExpanded = false;
    this.render();
    this.bindEvents();
    if (this._isSheetOpen()) this._renderSheetSelected();
};

TagInput.prototype.focus = function() {
    var input = this.container.querySelector('.tag-input-field');
    if (this._isMobile()) this.openMobileSheet();
    else if (input) input.focus();
};
