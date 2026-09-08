(function(global) {
  'use strict';

  var instanceID = 0;

  function esc(value) {
    var node = document.createElement('div');
    node.textContent = value == null ? '' : String(value);
    return node.innerHTML;
  }

  function debounce(fn, delay) {
    var timer = 0;
    return function() {
      var args = arguments;
      clearTimeout(timer);
      timer = setTimeout(function() { fn.apply(null, args); }, delay);
    };
  }

  function closestOption(target, root) {
    var option = target && target.closest ? target.closest('[data-bs-selection-value]') : null;
    return option && root.contains(option) ? option : null;
  }

  function SearchSelect(host, options) {
    this.host = host;
    this.options = options || {};
    this.value = '';
    this.selected = null;
    this.items = [];
    this.activeIndex = -1;
    this.loadSeq = 0;
    this.abortController = null;
    this.disabled = false;
    this.id = 'bs-search-select-' + (++instanceID);
    this.handleOutside = this.handleOutside.bind(this);
    this.render();
    this.bind();
    this.load('');
  }

  SearchSelect.prototype.render = function() {
    this.host.classList.add('bs-selection-control', 'bs-search-select');
    this.host.innerHTML =
      '<button class="bs-selection-trigger" type="button" role="combobox" aria-haspopup="listbox" aria-expanded="false" aria-controls="' + this.id + '-list">' +
        '<span class="bs-selection-trigger-icon"><i class="fa-solid ' + esc(this.options.icon || 'fa-book') + '"></i></span>' +
        '<span class="bs-selection-trigger-copy">' +
          '<span class="bs-selection-trigger-label is-placeholder">' + esc(this.options.placeholder || '请选择') + '</span>' +
          '<small class="bs-selection-trigger-meta" hidden></small>' +
        '</span>' +
        '<i class="fa-solid fa-chevron-down bs-selection-chevron" aria-hidden="true"></i>' +
      '</button>' +
      '<div class="bs-selection-popover" hidden>' +
        '<div class="bs-selection-search">' +
          '<i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>' +
          '<input class="bs-selection-search-input" type="search" autocomplete="off" placeholder="' + esc(this.options.searchPlaceholder || '搜索...') + '" aria-label="' + esc(this.options.searchPlaceholder || '搜索') + '">' +
          '<button class="bs-selection-search-clear" type="button" aria-label="' + esc(this.options.clearLabel || '清空搜索') + '" hidden><i class="fa-solid fa-xmark"></i></button>' +
        '</div>' +
        '<div class="bs-selection-list" id="' + this.id + '-list" role="listbox"></div>' +
      '</div>';
    this.trigger = this.host.querySelector('.bs-selection-trigger');
    this.label = this.host.querySelector('.bs-selection-trigger-label');
    this.meta = this.host.querySelector('.bs-selection-trigger-meta');
    this.popover = this.host.querySelector('.bs-selection-popover');
    this.search = this.host.querySelector('.bs-selection-search-input');
    this.clearButton = this.host.querySelector('.bs-selection-search-clear');
    this.list = this.host.querySelector('.bs-selection-list');
  };

  SearchSelect.prototype.bind = function() {
    var self = this;
    this.trigger.addEventListener('click', function() {
      if (!self.disabled) self.toggle();
    });
    this.trigger.addEventListener('keydown', function(event) {
      if (event.key === 'ArrowDown' || event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        if (!self.disabled) self.open();
      }
    });
    this.search.addEventListener('input', debounce(function() {
      self.clearButton.hidden = !self.search.value;
      self.load(self.search.value.trim());
    }, 180));
    this.search.addEventListener('keydown', function(event) { self.handleKeys(event); });
    this.clearButton.addEventListener('click', function() {
      self.search.value = '';
      self.clearButton.hidden = true;
      self.load('');
      self.search.focus();
    });
    this.list.addEventListener('mousemove', function(event) {
      var option = closestOption(event.target, self.list);
      if (!option) return;
      self.setActive(Number(option.getAttribute('data-bs-selection-index')));
    });
    this.list.addEventListener('click', function(event) {
      var option = closestOption(event.target, self.list);
      if (!option) return;
      self.choose(Number(option.getAttribute('data-bs-selection-index')));
    });
  };

  SearchSelect.prototype.handleOutside = function(event) {
    if (!this.host.contains(event.target)) this.close();
  };

  SearchSelect.prototype.toggle = function() {
    if (this.popover.hidden) this.open();
    else this.close();
  };

  SearchSelect.prototype.open = function() {
    if (this.disabled) return;
    this.popover.hidden = false;
    this.host.classList.add('is-open');
    this.trigger.setAttribute('aria-expanded', 'true');
    document.addEventListener('pointerdown', this.handleOutside);
    var self = this;
    setTimeout(function() { self.search.focus(); self.search.select(); }, 0);
  };

  SearchSelect.prototype.close = function() {
    this.popover.hidden = true;
    this.host.classList.remove('is-open');
    this.trigger.setAttribute('aria-expanded', 'false');
    document.removeEventListener('pointerdown', this.handleOutside);
    this.activeIndex = -1;
  };

  SearchSelect.prototype.handleKeys = function(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      this.close();
      this.trigger.focus();
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      var direction = event.key === 'ArrowDown' ? 1 : -1;
      var next = this.activeIndex + direction;
      if (next < 0) next = this.items.length - 1;
      if (next >= this.items.length) next = 0;
      this.setActive(next, true);
      return;
    }
    if (event.key === 'Enter' && this.activeIndex >= 0) {
      event.preventDefault();
      this.choose(this.activeIndex);
    }
  };

  SearchSelect.prototype.setActive = function(index, scroll) {
    this.activeIndex = index;
    var options = this.list.querySelectorAll('[data-bs-selection-index]');
    Array.prototype.forEach.call(options, function(option) {
      option.classList.toggle('is-active', Number(option.getAttribute('data-bs-selection-index')) === index);
    });
    if (scroll && options[index]) options[index].scrollIntoView({ block: 'nearest' });
  };

  SearchSelect.prototype.load = function(query) {
    var self = this;
    var seq = ++this.loadSeq;
    if (this.abortController) this.abortController.abort();
    this.abortController = typeof AbortController === 'function' ? new AbortController() : null;
    this.list.innerHTML = '<div class="bs-selection-status"><i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i><span>' + esc(this.options.loadingText || '正在加载...') + '</span></div>';
    var loader = this.options.load || function() { return []; };
    Promise.resolve(loader(query, this.abortController ? this.abortController.signal : null)).then(function(result) {
      if (seq !== self.loadSeq) return;
      self.items = Array.isArray(result) ? result : (result && Array.isArray(result.items) ? result.items : []);
      self.activeIndex = self.items.length ? 0 : -1;
      self.renderItems();
      if (!query && self.options.autoSelectSingle && self.items.length === 1 && !self.value) self.choose(0, true);
    }).catch(function(error) {
      if (seq !== self.loadSeq || error && error.name === 'AbortError') return;
      self.items = [];
      self.activeIndex = -1;
      self.list.innerHTML = '<div class="bs-selection-status">' + esc((error && error.message) || self.options.errorText || '加载失败') + '</div>';
    });
  };

  SearchSelect.prototype.renderItems = function() {
    var self = this;
    if (!this.items.length) {
      this.list.innerHTML = '<div class="bs-selection-status">' + esc(this.options.emptyText || '没有匹配结果') + '</div>';
      return;
    }
    this.list.innerHTML = this.items.map(function(item, index) {
      var value = String(self.options.getValue ? self.options.getValue(item) : item.value);
      var label = self.options.getLabel ? self.options.getLabel(item) : item.label;
      var meta = self.options.getMeta ? self.options.getMeta(item) : item.meta;
      var icon = self.options.getIcon ? self.options.getIcon(item) : (self.options.optionIcon || 'fa-book');
      var selected = String(self.value) === value;
      return '<button class="bs-selection-option' + (selected ? ' is-selected' : '') + (index === self.activeIndex ? ' is-active' : '') + '" type="button" role="option" aria-selected="' + (selected ? 'true' : 'false') + '" data-bs-selection-index="' + index + '" data-bs-selection-value="' + esc(value) + '">' +
        '<span class="bs-selection-option-icon"><i class="fa-solid ' + esc(icon) + '"></i></span>' +
        '<span class="bs-selection-option-copy"><span class="bs-selection-option-label">' + esc(label || '') + '</span>' +
        (meta ? '<small class="bs-selection-option-meta">' + esc(meta) + '</small>' : '') + '</span>' +
        '<i class="fa-solid fa-check bs-selection-option-check" aria-hidden="true"></i>' +
      '</button>';
    }).join('');
  };

  SearchSelect.prototype.choose = function(index, silent) {
    var item = this.items[index];
    if (!item) return;
    this.selected = item;
    this.value = String(this.options.getValue ? this.options.getValue(item) : item.value);
    var label = this.options.getLabel ? this.options.getLabel(item) : item.label;
    var meta = this.options.getMeta ? this.options.getMeta(item) : item.meta;
    this.label.textContent = label || '';
    this.label.classList.remove('is-placeholder');
    this.meta.textContent = meta || '';
    this.meta.hidden = !meta;
    this.setInvalid(false);
    this.renderItems();
    if (!silent) {
      this.close();
      this.trigger.focus();
    }
    if (typeof this.options.onChange === 'function') this.options.onChange(item, this.value);
  };

  SearchSelect.prototype.getValue = function() { return this.value; };
  SearchSelect.prototype.getSelected = function() { return this.selected; };
  SearchSelect.prototype.focus = function() { this.trigger.focus(); };
  SearchSelect.prototype.setInvalid = function(invalid) {
    this.host.classList.toggle('is-invalid', !!invalid);
    this.trigger.setAttribute('aria-invalid', invalid ? 'true' : 'false');
  };
  SearchSelect.prototype.setDisabled = function(disabled) {
    this.disabled = !!disabled;
    this.trigger.disabled = this.disabled;
    if (this.disabled) this.close();
  };
  SearchSelect.prototype.destroy = function() {
    this.loadSeq += 1;
    if (this.abortController) this.abortController.abort();
    document.removeEventListener('pointerdown', this.handleOutside);
    this.host.innerHTML = '';
    this.host.classList.remove('bs-selection-control', 'bs-search-select', 'is-open', 'is-invalid');
  };

  function TreePicker(host, options) {
    this.host = host;
    this.options = options || {};
    this.nodes = [];
    this.value = '0';
    this.selected = null;
    this.expanded = {};
    this.disabled = true;
    this.id = 'bs-tree-picker-' + (++instanceID);
    this.handleOutside = this.handleOutside.bind(this);
    this.render();
    this.bind();
    this.updateTrigger();
    this.renderTree();
  }

  TreePicker.prototype.render = function() {
    this.host.classList.add('bs-selection-control', 'bs-tree-picker');
    this.host.innerHTML =
      '<button class="bs-selection-trigger" type="button" role="combobox" aria-haspopup="tree" aria-expanded="false" aria-controls="' + this.id + '-tree" disabled>' +
        '<span class="bs-selection-trigger-icon"><i class="fa-solid fa-folder-tree"></i></span>' +
        '<span class="bs-selection-trigger-copy"><span class="bs-selection-trigger-label"></span><small class="bs-selection-trigger-meta" hidden></small></span>' +
        '<i class="fa-solid fa-chevron-down bs-selection-chevron" aria-hidden="true"></i>' +
      '</button>' +
      '<div class="bs-selection-popover" hidden>' +
        '<div class="bs-selection-search">' +
          '<i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>' +
          '<input class="bs-selection-search-input" type="search" autocomplete="off" placeholder="' + esc(this.options.searchPlaceholder || '搜索目录...') + '">' +
          '<button class="bs-selection-search-clear" type="button" aria-label="' + esc(this.options.clearLabel || '清空搜索') + '" hidden><i class="fa-solid fa-xmark"></i></button>' +
        '</div>' +
        '<div class="bs-selection-list bs-tree-picker-list" id="' + this.id + '-tree" role="tree"></div>' +
      '</div>';
    this.trigger = this.host.querySelector('.bs-selection-trigger');
    this.label = this.host.querySelector('.bs-selection-trigger-label');
    this.meta = this.host.querySelector('.bs-selection-trigger-meta');
    this.popover = this.host.querySelector('.bs-selection-popover');
    this.search = this.host.querySelector('.bs-selection-search-input');
    this.clearButton = this.host.querySelector('.bs-selection-search-clear');
    this.list = this.host.querySelector('.bs-tree-picker-list');
  };

  TreePicker.prototype.bind = function() {
    var self = this;
    this.trigger.addEventListener('click', function() {
      if (!self.disabled) self.toggle();
    });
    this.search.addEventListener('input', function() {
      self.clearButton.hidden = !self.search.value;
      self.renderTree();
    });
    this.search.addEventListener('keydown', function(event) {
      if (event.key === 'Escape') {
        event.preventDefault();
        self.close();
        self.trigger.focus();
      }
    });
    this.clearButton.addEventListener('click', function() {
      self.search.value = '';
      self.clearButton.hidden = true;
      self.renderTree();
      self.search.focus();
    });
    this.list.addEventListener('click', function(event) {
      var toggle = event.target.closest('[data-bs-tree-toggle]');
      if (toggle && self.list.contains(toggle)) {
        var toggleID = toggle.getAttribute('data-bs-tree-toggle');
        self.expanded[toggleID] = !self.expanded[toggleID];
        self.renderTree();
        return;
      }
      var option = closestOption(event.target, self.list);
      if (!option) return;
      self.choose(option.getAttribute('data-bs-selection-value'));
    });
  };

  TreePicker.prototype.handleOutside = function(event) {
    if (!this.host.contains(event.target)) this.close();
  };
  TreePicker.prototype.toggle = SearchSelect.prototype.toggle;
  TreePicker.prototype.open = function() {
    if (this.disabled) return;
    this.popover.hidden = false;
    this.host.classList.add('is-open');
    this.trigger.setAttribute('aria-expanded', 'true');
    document.addEventListener('pointerdown', this.handleOutside);
    var self = this;
    setTimeout(function() { self.search.focus(); self.search.select(); }, 0);
  };
  TreePicker.prototype.close = function() {
    this.popover.hidden = true;
    this.host.classList.remove('is-open');
    this.trigger.setAttribute('aria-expanded', 'false');
    document.removeEventListener('pointerdown', this.handleOutside);
  };

  TreePicker.prototype.nodeID = function(node) {
    return String(node.document_id != null ? node.document_id : node.id);
  };
  TreePicker.prototype.nodeName = function(node) {
    return String(node.document_name != null ? node.document_name : (node.name || ''));
  };
  TreePicker.prototype.nodeIcon = function(node) {
    if (node.children && node.children.length) return 'fa-folder';
    var icons = {
      html: 'fa-code',
      richdoc: 'fa-file-word',
      spreadsheet: 'fa-table',
      drawing: 'fa-pen-ruler',
      mindmap: 'fa-diagram-project',
      markdown: 'fa-file-lines'
    };
    return icons[node.doc_type || node.editor_type] || 'fa-file-lines';
  };

  TreePicker.prototype.findNode = function(nodes, value) {
    for (var i = 0; i < nodes.length; i += 1) {
      if (this.nodeID(nodes[i]) === String(value)) return nodes[i];
      var child = this.findNode(nodes[i].children || [], value);
      if (child) return child;
    }
    return null;
  };

  TreePicker.prototype.matches = function(node, query) {
    if (!query) return true;
    if (this.nodeName(node).toLowerCase().indexOf(query) >= 0) return true;
    var children = node.children || [];
    for (var i = 0; i < children.length; i += 1) {
      if (this.matches(children[i], query)) return true;
    }
    return false;
  };

  TreePicker.prototype.renderRows = function(nodes, depth, query) {
    var self = this;
    var html = '';
    (nodes || []).forEach(function(node) {
      if (!self.matches(node, query)) return;
      var id = self.nodeID(node);
      var children = node.children || [];
      var expanded = !!query || !!self.expanded[id];
      var selected = self.value === id;
      html += '<div class="bs-tree-picker-row' + (selected ? ' is-selected' : '') + '" style="--bs-tree-depth:' + depth + '" role="treeitem" aria-level="' + (depth + 1) + '"' +
        (children.length ? ' aria-expanded="' + (expanded ? 'true' : 'false') + '"' : '') + '>' +
        '<button class="bs-tree-picker-toggle' + (children.length ? (expanded ? ' is-expanded' : '') : ' is-empty') + '" type="button"' + (children.length ? ' data-bs-tree-toggle="' + esc(id) + '" aria-label="' + esc(expanded ? (self.options.collapseLabel || '收起') : (self.options.expandLabel || '展开')) + '"' : ' tabindex="-1"') + '><i class="fa-solid fa-chevron-right"></i></button>' +
        '<button class="bs-tree-picker-select" type="button" data-bs-selection-value="' + esc(id) + '">' +
          '<i class="fa-solid ' + self.nodeIcon(node) + '" aria-hidden="true"></i>' +
          '<span class="bs-tree-picker-name">' + esc(self.nodeName(node)) + '</span>' +
          '<i class="fa-solid fa-check bs-tree-picker-check" aria-hidden="true"></i>' +
        '</button></div>';
      if (children.length && expanded) html += self.renderRows(children, depth + 1, query);
    });
    return html;
  };

  TreePicker.prototype.renderTree = function() {
    var query = (this.search.value || '').trim().toLowerCase();
    var rootSelected = this.value === '0';
    var root =
      '<div class="bs-tree-picker-row' + (rootSelected ? ' is-selected' : '') + '" style="--bs-tree-depth:0" role="treeitem" aria-level="1">' +
        '<span class="bs-tree-picker-toggle is-empty"></span>' +
        '<button class="bs-tree-picker-select" type="button" data-bs-selection-value="0">' +
          '<i class="fa-solid fa-book-open" aria-hidden="true"></i><span class="bs-tree-picker-name">' + esc(this.options.rootLabel || '根目录') + '</span>' +
          '<i class="fa-solid fa-check bs-tree-picker-check" aria-hidden="true"></i>' +
        '</button></div>';
    var rows = this.renderRows(this.nodes, 0, query);
    if (query && !rows) {
      this.list.innerHTML = '<div class="bs-selection-status">' + esc(this.options.emptyText || '没有匹配目录') + '</div>';
      return;
    }
    this.list.innerHTML = root + rows;
  };

  TreePicker.prototype.choose = function(value, silent) {
    this.value = String(value == null ? '0' : value);
    this.selected = this.value === '0' ? null : this.findNode(this.nodes, this.value);
    this.updateTrigger();
    this.renderTree();
    this.setInvalid(false);
    if (!silent) {
      this.close();
      this.trigger.focus();
      if (typeof this.options.onChange === 'function') this.options.onChange(this.selected, this.value);
    }
  };

  TreePicker.prototype.updateTrigger = function() {
    var root = this.value === '0' || !this.selected;
    this.label.textContent = root ? (this.options.rootLabel || '根目录') : this.nodeName(this.selected);
    this.label.classList.remove('is-placeholder');
    this.meta.textContent = root ? (this.options.rootMeta || '') : (this.options.itemMeta || '');
    this.meta.hidden = !this.meta.textContent;
  };

  TreePicker.prototype.setTree = function(nodes) {
    this.nodes = Array.isArray(nodes) ? nodes : [];
    this.expanded = {};
    this.nodes.forEach(function(node) {
      if (node && node.children && node.children.length) this.expanded[this.nodeID(node)] = true;
    }, this);
    if (this.value !== '0') {
      this.selected = this.findNode(this.nodes, this.value);
      if (!this.selected) this.value = '0';
    }
    this.updateTrigger();
    this.renderTree();
  };
  TreePicker.prototype.setValue = function(value, silent) { this.choose(value, silent); };
  TreePicker.prototype.getValue = function() { return this.value; };
  TreePicker.prototype.focus = function() { this.trigger.focus(); };
  TreePicker.prototype.setInvalid = SearchSelect.prototype.setInvalid;
  TreePicker.prototype.setDisabled = SearchSelect.prototype.setDisabled;
  TreePicker.prototype.destroy = function() {
    document.removeEventListener('pointerdown', this.handleOutside);
    this.host.innerHTML = '';
    this.host.classList.remove('bs-selection-control', 'bs-tree-picker', 'is-open', 'is-invalid');
  };

  global.BookStarkSearchSelect = {
    create: function(host, options) { return new SearchSelect(host, options); }
  };
  global.BookStarkTreePicker = {
    create: function(host, options) { return new TreePicker(host, options); }
  };
})(window);
