/* ===== BookStark Command Palette ===== */
(function() {
  'use strict';

  var state = {
    open: false,
    active: 0,
    query: '',
    items: [],
    searchTimer: null,
    abort: null
  };

  function t(key, fallback) {
    if (typeof window.__ !== 'function') return fallback;
    var v = window.__(key);
    return v && v !== key ? v : fallback;
  }

  function isAuthed() {
    return !!document.getElementById('searchTrigger');
  }

  function isAdmin() {
    return !!document.querySelector('a[href="/admin/system"], a[href="/admin/assets"], a[href="/admin/dashboard"]');
  }

  function icon(name) {
    return '<i class="fa-solid ' + name + '"></i>';
  }

  function command(title, subtitle, type, iconName, href, run, keywords) {
    return {
      kind: 'command',
      title: title,
      subtitle: subtitle || '',
      type: type || '页面',
      icon: iconName || 'fa-circle',
      href: href || '',
      run: run,
      keywords: keywords || ''
    };
  }

  function baseCommands() {
    var commands = [
      command('导航页', '/nav', '页面', 'fa-compass', '/nav', null, 'home nav'),
      command('书签', '/bookmarks', '页面', 'fa-bookmark', '/bookmarks', null, 'bookmark'),
      command('分享', '/shares', '页面', 'fa-share-nodes', '/shares', null, 'share public'),
      command('切换主题', '浅色 / 暗色', '操作', 'fa-moon', '', function() { if (window.BookStarkTheme) BookStarkTheme.toggle(); }, 'theme dark light')
    ];
    if (isAuthed()) {
      commands.unshift(
        command('搜索全站', '输入关键词后回车搜索全部内容', '搜索', 'fa-magnifying-glass', '', runGlobalSearch, 'search'),
        command('笔记', '/notes', '页面', 'fa-note-sticky', '/notes', null, 'note'),
        command('待办', '/notes?tab=tasks', '页面', 'fa-list-check', '/notes?tab=tasks', null, 'todo task'),
        command('文章', '/notes?tab=articles', '页面', 'fa-pen-nib', '/notes?tab=articles', null, 'article'),
        command('专题', '/topics', '页面', 'fa-box-archive', '/topics', null, 'topic project collection'),
        command('书籍', '/books', '页面', 'fa-book', '/books', null, 'book'),
        command('全局搜索', '/search', '页面', 'fa-magnifying-glass', '/search', null, 'search'),
        command('个人信息', '/profile', '页面', 'fa-user', '/profile', null, 'profile account'),
        command('回收站', '/trash', '页面', 'fa-trash-can', '/trash', null, 'trash')
      );
      commands.push(
        command('新建笔记', '/notes?command=new-note', '新建', 'fa-note-sticky', '/notes?command=new-note', newNote, 'create note'),
        command('新建待办', '/notes?tab=tasks&command=new-task', '新建', 'fa-list-check', '/notes?tab=tasks&command=new-task', null, 'create todo task'),
        command('新建文章', '/notes?command=new-article', '新建', 'fa-pen-nib', '/notes?command=new-article', null, 'create article'),
        command('新建专题', '/topics?command=new-topic', '新建', 'fa-box-archive', '/topics?command=new-topic', null, 'create topic'),
        command('新建书籍', '/books?command=new-book', '新建', 'fa-book', '/books?command=new-book', null, 'create book'),
        command('新建书签', '/bookmarks?command=new-bookmark', '新建', 'fa-bookmark', '/bookmarks?command=new-bookmark', null, 'create bookmark')
      );
      if (isAdmin()) {
        commands.push(
          command('图片管理', '/images', '管理', 'fa-image', '/images', null, 'image'),
          command('标签', '/labels', '管理', 'fa-tags', '/labels', null, 'label tag'),
          command('主机', '/admin/assets', '管理', 'fa-server', '/admin/assets', null, 'asset ssh webdav docker host'),
          command('系统设置', '/admin/system', '管理', 'fa-gear', '/admin/system', null, 'system settings'),
          command('访问统计', '/admin/dashboard', '管理', 'fa-chart-line', '/admin/dashboard', null, 'dashboard stats')
        );
      }
    } else {
      commands.push(
        command('登录', '/login', '页面', 'fa-right-to-bracket', '/login', null, 'login'),
        command('注册', '/register', '页面', 'fa-user-plus', '/register', null, 'register')
      );
    }
    return commands;
  }

  function ensureDOM() {
    var overlay = document.getElementById('cmdkOverlay');
    if (overlay) return overlay;
    overlay = document.createElement('div');
    overlay.id = 'cmdkOverlay';
    overlay.className = 'cmdk-overlay';
    overlay.innerHTML =
      '<div class="cmdk-panel" role="dialog" aria-modal="true" aria-label="Command palette">' +
      '  <div class="cmdk-search">' +
      '    <i class="fa-solid fa-magnifying-glass"></i>' +
      '    <input id="cmdkInput" class="cmdk-input" type="search" autocomplete="off" placeholder="搜索或输入命令">' +
      '    <span class="cmdk-kbd">Esc</span>' +
      '  </div>' +
      '  <div id="cmdkResults" class="cmdk-results" role="listbox"></div>' +
      '</div>';
    document.body.appendChild(overlay);
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) close();
    });
    var input = overlay.querySelector('#cmdkInput');
    input.addEventListener('input', function() {
      state.query = input.value.trim();
      state.active = 0;
      renderLocal();
      scheduleRemoteSearch();
    });
    input.addEventListener('keydown', onKeydown);
    return overlay;
  }

  function open(seed) {
    var overlay = ensureDOM();
    state.open = true;
    state.query = seed || '';
    state.active = 0;
    overlay.classList.add('active');
    document.body.classList.add('cmdk-open');
    var input = overlay.querySelector('#cmdkInput');
    input.value = state.query;
    renderLocal();
    scheduleRemoteSearch();
    setTimeout(function() {
      input.focus();
      input.select();
    }, 0);
  }

  function close() {
    var overlay = document.getElementById('cmdkOverlay');
    if (!overlay) return;
    overlay.classList.remove('active');
    document.body.classList.remove('cmdk-open');
    state.open = false;
    clearTimeout(state.searchTimer);
    if (state.abort) state.abort.abort();
  }

  function onKeydown(e) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      move(1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      move(-1);
    } else if (e.key === 'Home') {
      e.preventDefault();
      setActive(0);
    } else if (e.key === 'End') {
      e.preventDefault();
      setActive(state.items.length - 1);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      runActive();
    }
  }

  function move(delta) {
    if (!state.items.length) return;
    setActive((state.active + delta + state.items.length) % state.items.length);
  }

  function setActive(index) {
    if (!state.items.length) return;
    state.active = Math.max(0, Math.min(index, state.items.length - 1));
    syncActiveItem();
  }

  function syncActiveItem() {
    var box = document.getElementById('cmdkResults');
    if (!box) return;
    box.querySelectorAll('.cmdk-item').forEach(function(btn) {
      var idx = parseInt(btn.getAttribute('data-idx'), 10) || 0;
      var active = idx === state.active;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    var activeEl = box.querySelector('.cmdk-item.active');
    if (activeEl) activeEl.scrollIntoView({ block: 'nearest' });
  }

  function renderLocal(extraItems) {
    var q = state.query.toLowerCase();
    var commands = baseCommands().filter(function(item) {
      if (!q) return true;
      return (item.title + ' ' + item.subtitle + ' ' + item.type + ' ' + (item.keywords || '')).toLowerCase().indexOf(q) >= 0;
    });
    state.items = commands.concat(extraItems || []);
    renderItems();
  }

  function renderItems() {
    var box = document.getElementById('cmdkResults');
    if (!box) return;
    if (!state.items.length) {
      box.innerHTML = '<div class="cmdk-empty">没有匹配结果</div>';
      return;
    }
    var html = '';
    var lastKind = '';
    state.items.forEach(function(item, idx) {
      if (item.kind !== lastKind) {
        lastKind = item.kind;
        html += '<div class="cmdk-section">' + (item.kind === 'result' ? '内容' : '命令') + '</div>';
      }
      html += '<button type="button" class="cmdk-item' + (idx === state.active ? ' active' : '') + '" data-idx="' + idx + '" role="option" aria-selected="' + (idx === state.active ? 'true' : 'false') + '">' +
        '<span class="cmdk-icon">' + icon(item.icon || 'fa-circle') + '</span>' +
        '<span><span class="cmdk-title">' + escHtml(item.title || '') + '</span><span class="cmdk-subtitle">' + escHtml(item.subtitle || '') + '</span></span>' +
        '<span class="cmdk-type">' + escHtml(item.type || '') + '</span>' +
      '</button>';
    });
    box.innerHTML = html;
    box.querySelectorAll('.cmdk-item').forEach(function(btn) {
      btn.addEventListener('mouseenter', function() {
        state.active = parseInt(btn.getAttribute('data-idx'), 10) || 0;
        syncActiveItem();
      });
      btn.addEventListener('click', function() {
        state.active = parseInt(btn.getAttribute('data-idx'), 10) || 0;
        runActive();
      });
    });
    syncActiveItem();
  }

  function scheduleRemoteSearch() {
    clearTimeout(state.searchTimer);
    if (!isAuthed() || state.query.length < 2) return;
    state.searchTimer = setTimeout(fetchRemoteResults, 220);
  }

  function fetchRemoteResults() {
    if (state.abort) state.abort.abort();
    state.abort = new AbortController();
    fetch('/api/search?q=' + encodeURIComponent(state.query), {
      credentials: 'same-origin',
      signal: state.abort.signal
    }).then(function(res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    }).then(function(json) {
      var data = json.data || json;
      renderLocal(searchDataToItems(data).slice(0, 10));
    }).catch(function(err) {
      if (err.name !== 'AbortError') renderLocal();
    });
  }

  function searchDataToItems(data) {
    var items = [];
    (data.blogs || []).forEach(function(b) {
      var note = b.blog_type === 'note';
      var id = b.id || b.blog_id;
      items.push({ kind: 'result', title: b.title || b.blog_title || '未命名', subtitle: b.snippet || '', type: note ? '笔记' : '文章', icon: note ? 'fa-note-sticky' : 'fa-pen-nib', href: note ? ('/notes?id=' + id) : ('/notes?id=' + id + '&tab=articles') });
    });
    (data.documents || []).forEach(function(d) {
      items.push({ kind: 'result', title: d.name || '', subtitle: d.book_name || d.snippet || '', type: '文档', icon: 'fa-file-lines', href: '/books/' + d.book_identify + '/edit?doc=' + d.id });
    });
    (data.books || []).forEach(function(b) {
      items.push({ kind: 'result', title: b.name || b.book_name || '', subtitle: b.description || '', type: '书籍', icon: 'fa-book', href: '/books/' + (b.identify || b.book_identify || '') + '/edit' });
    });
    (data.bookmarks || []).forEach(function(b) {
      items.push({ kind: 'result', title: b.title || b.bookmark_title || b.url || '', subtitle: b.url || '', type: '书签', icon: 'fa-bookmark', href: '/bookmarks?id=' + (b.id || b.bookmark_id) });
    });
    (data.labels || []).forEach(function(l) {
      var labelName = l.name || l.label_name || '';
      items.push({ kind: 'result', title: labelName, subtitle: '标签', type: '标签', icon: 'fa-tags', href: '/labels?id=' + (l.id || l.label_id || '') });
    });
    (data.tasks || []).forEach(function(task) {
      var title = firstLine(task.content || task.title || '') || '未命名待办';
      var meta = [];
      if (task.due_date) meta.push('截止 ' + task.due_date);
      meta.push(task.done ? '已完成' : '未完成');
      items.push({ kind: 'result', title: title, subtitle: meta.join(' · ') || task.snippet || '', type: '待办', icon: 'fa-list-check', href: '/notes?tab=tasks&task_id=' + encodeURIComponent(task.id || task.task_id || '') });
    });
    (data.topics || []).forEach(function(topic) {
      var id = topic.id || topic.topic_id || '';
      var title = topic.title || '未命名专题';
      var count = Number(topic.item_count || 0);
      var meta = count > 0 ? count + ' 项资料' : '专题';
      items.push({ kind: 'result', title: title, subtitle: topic.snippet || topic.question || meta, type: '专题', icon: 'fa-box-archive', href: '/topics?id=' + encodeURIComponent(id) });
    });
    return items;
  }

  function runActive() {
    var item = state.items[state.active];
    if (!item) {
      runGlobalSearch();
      return;
    }
    close();
    if (typeof item.run === 'function') {
      item.run();
    } else if (item.href) {
      window.location.href = item.href;
    }
  }

  function runGlobalSearch() {
    var q = state.query || '';
    if (!q) return;
    window.location.href = '/search?q=' + encodeURIComponent(q);
  }

  function newNote() {
    if (window.notesApp && typeof window.notesApp.handleFab === 'function') {
      window.notesApp.activeTab = 'notes';
      window.notesApp.handleFab();
      return;
    }
    window.location.href = '/notes?command=new-note';
  }

  function firstLine(text) {
    return String(text || '').split(/\r?\n/).filter(function(line) { return line.trim(); })[0] || '';
  }

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      open();
    }
  });

  window.BookStarkCommandPalette = { open: open, close: close };
})();
