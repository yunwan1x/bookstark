(function () {
    'use strict';
    var modules = {
        notes: ['笔记', 'note-sticky', '#2563eb', '/notes'],
        articles: ['文章', 'file-lines', '#0caa8b', '/notes?tab=articles'],
        tasks: ['待办', 'list-check', '#ed8a19', '/notes?tab=tasks'],
        books: ['书籍', 'book-open', '#8758eb', '/books'],
        bookmarks: ['书签', 'link', '#168ef0', '/bookmarks'],
        topics: ['专题', 'layer-group', '#198ae8', '/topics'],
        nav: ['导航', 'compass', '#3468e8', '/nav'],
        shares: ['分享', 'share-nodes', '#10a880', '/shares'],
        assets: ['资产', 'server', '#d99b19', '/admin/assets']
    };
    var grid = document.getElementById('homeGrid');
    var status = document.getElementById('homeStatus');
    var retry = document.getElementById('homeRetry');
    var key = 'bookstark-home:' + document.body.dataset.homeMember;
    var hidden = [], sections = [], sort = 'updated', sequence = 0, activeRequest;
    var layout = [], draft = [], saving = false, dragging = null;
    var layoutDialog = document.getElementById('homeCustomize');
    var layoutStatus = document.getElementById('homeLayoutStatus');
    var english = document.documentElement.lang.indexOf('en') === 0;
    function lt(zh, en) { return english ? en : zh; }
    var moduleEnglish = {notes:'Notes',articles:'Articles',tasks:'Tasks',books:'Books',bookmarks:'Bookmarks',topics:'Topics',nav:'Navigation',shares:'Shares',assets:'Assets'};
    function moduleName(key) { return english ? moduleEnglish[key] : modules[key][0]; }
    function defaultLayout() { return Object.keys(modules).map(function(k) {return {key:k,width:1,hidden:false};}); }
    function available(item) { return sections.some(function(s) {return s.key === item.key;}); }
    try { var saved = JSON.parse(localStorage.getItem(key)); if (Array.isArray(saved)) hidden = saved; } catch (_) {}
    var now = new Date();
    document.getElementById('homeToday').textContent = now.toLocaleDateString(english ? 'en-US' : 'zh-CN', {year:'numeric', month:'long', day:'numeric', weekday:'long'});
    function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; }
    function render() {
        grid.replaceChildren();
        layout.forEach(function (item) {
            var s = sections.find(function(s) {return s.key === item.key;});
            if (!s || item.hidden) return;
            var m = modules[s.key];
            if (!m) return;
            var card = el('section', 'home-card'); card.dataset.section = s.key; card.style.setProperty('--home-accent', m[2]);
            card.dataset.width = String(item.width);
            var head = el('div', 'home-card-head');
            var icon = el('span', 'home-card-icon'); var glyph = el('i', 'fa-solid fa-' + m[1]); glyph.setAttribute('aria-hidden','true'); icon.append(glyph);
            var label = el('div'); var title = el('h2', '', moduleName(s.key)); title.id = 'home-title-' + s.key; card.setAttribute('aria-labelledby', title.id);
            label.append(title, el('div', 'home-card-subtitle', lt('最新 ' + s.items.length + ' 条 / 共 ' + s.total + ' 条', 'Latest ' + s.items.length + ' / ' + s.total + ' total')));
            var all = el('a', 'home-card-all', lt('查看全部 →','View all →')); all.href = m[3]; all.setAttribute('aria-label',lt('查看全部','View all ') + moduleName(s.key)); head.append(icon,label,all); card.append(head);
            var list = el('ul', 'home-list'); list.id = 'home-list-' + s.key;
            s.items.forEach(function (item) {
                var li = el('li'); var a = el('a', 'home-row');
                if (typeof item.url !== 'string') return;
                if (s.key === 'bookmarks') {
                    // Bookmark destinations are external; reject executable URL schemes.
                    try {
                        var destination = new URL(item.url);
                        if (destination.protocol !== 'http:' && destination.protocol !== 'https:') return;
                    } catch (_) { return; }
                    a.target = '_blank'; a.rel = 'noopener noreferrer';
                } else if (!item.url.startsWith('/') || item.url.startsWith('//')) return;
                a.href = item.url; a.title = item.title || lt('未命名','Untitled'); a.append(el('span','home-row-title',a.title));
                if (item.badge) a.append(el('span','home-badge',({markdown:'MD',html:'HTML',blog:lt('文章 / 笔记','Article / Note'),book:lt('书籍','Book'),online:lt('在线','Online'),offline:lt('离线','Offline'),ssh:lt('SSH 主机','SSH host'),webdav:'WebDAV','加密':lt('加密','Protected'),'已完成':lt('已完成','Completed'),'待处理':lt('待处理','Pending')})[item.badge] || item.badge));
                var date = el('time','',item.date ? item.date.slice(5) : ''); date.dateTime = item.date; date.title = item.date; a.append(date); li.append(a); list.append(li);
            });
            card.append(list);
            if (!s.items.length) card.append(el('p','home-empty',lt('还没有' + m[0] + '记录','No records yet')));
            if (s.items.length > 3) {
                var expandText = lt('展开最近 ' + s.items.length + ' 条 ↓','Show latest ' + s.items.length + ' ↓');
                var expand = el('button','home-expand',expandText); expand.setAttribute('aria-expanded','false'); expand.setAttribute('aria-controls',list.id);
                expand.onclick = function () { var open = list.classList.toggle('expanded'); expand.setAttribute('aria-expanded',String(open)); expand.textContent = open ? lt('收起 ↑','Collapse ↑') : expandText; };
                card.append(expand);
            }
            grid.append(card);
        });
        status.hidden = grid.childElementCount > 0;
        if (!grid.childElementCount) status.textContent = lt('所有板块已隐藏，可在“自定义板块”中重新开启。','All sections are hidden. Enable them in Customize sections.');
    }
    function preferences() {
        var box = document.getElementById('homePreferences'); box.replaceChildren();
        sections.forEach(function (s) {
            var item = draft.find(function(item) {return item.key === s.key;});
            var label = el('label'); var input = el('input'); input.type = 'checkbox'; input.checked = !item.hidden;
            input.id = 'home-layout-visible-' + s.key; label.htmlFor = input.id;
            input.onchange = function () {
                item.hidden = !input.checked;
                preview();
            };
            label.append(input,el('span','',moduleName(s.key))); box.append(label);
        });
        if (!sections.length) box.append(el('p','',lt('请先加载首页数据。','Load the home page first.')));
        document.getElementById('homeLayoutSave').disabled = !sections.length;
        document.getElementById('homeLayoutReset').disabled = !sections.length;
        preview();
    }
    function move(key, target) {
        var from = draft.findIndex(function(i) {return i.key === key;});
        var to = draft.findIndex(function(i) {return i.key === target;});
        if (from < 0 || to < 0 || from === to) return;
        draft.splice(to, 0, draft.splice(from, 1)[0]);
        preview();
        layoutStatus.textContent = lt('已调整位置：','Position updated: ') + moduleName(key);
        var handle = document.getElementById('home-layout-drag-' + key); if (handle) handle.focus();
    }
    function preview() {
        var box = document.getElementById('homeLayoutPreview'); box.replaceChildren();
        var visible = draft.filter(function(i) {return available(i) && !i.hidden;});
        visible.forEach(function(item, index) {
            var card = el('div','home-layout-card'); card.dataset.width = String(item.width); card.dataset.key = item.key;
            var head = el('div','home-layout-card-head');
            var handle = el('button','home-button','⠿'); handle.type = 'button'; handle.draggable = true;
            handle.id = 'home-layout-drag-' + item.key;
            handle.setAttribute('aria-label',lt('拖动排序：','Drag to reorder: ') + moduleName(item.key));
            handle.ondragstart = function(e) {dragging = item.key; e.dataTransfer.setData('text/plain',item.key); e.dataTransfer.effectAllowed = 'move';};
            handle.ondragend = function() {dragging = null; box.querySelectorAll('.is-drop-target').forEach(function(c) {c.classList.remove('is-drop-target');});};
            head.append(handle,el('span','',moduleName(item.key))); card.append(head);
            var label = el('label','home-layout-width',lt('宽度','Width')); var select = el('select','dialog-input');
            select.id = 'home-layout-width-' + item.key; label.htmlFor = select.id;
            [lt('1格','1 column'),lt('2格','2 columns'),lt('整行','Full row')].forEach(function(text,i) {var option = el('option','',text); option.value = String(i+1); select.append(option);});
            select.value = String(item.width);
            select.onchange = function() {item.width = Number(select.value); card.dataset.width = select.value;};
            label.append(select); card.append(label);
            var actions = el('div','home-layout-move');
            [-1,1].forEach(function(delta) {
                var text = delta < 0 ? lt('上移','Move up') : lt('下移','Move down');
                var button = el('button','home-button',delta < 0 ? '↑' : '↓'); button.type = 'button';
                button.title = text; button.setAttribute('aria-label',text + ' ' + moduleName(item.key));
                button.disabled = !visible[index + delta];
                button.onclick = function() {move(item.key,visible[index + delta].key);}; actions.append(button);
            }); card.append(actions);
            card.ondragover = function(e) {if (dragging && dragging !== item.key) {e.preventDefault(); card.classList.add('is-drop-target');}};
            card.ondragleave = function() {card.classList.remove('is-drop-target');};
            card.ondrop = function(e) {e.preventDefault(); card.classList.remove('is-drop-target'); if (dragging) move(dragging,item.key); dragging = null;};
            box.append(card);
        });
        if (!visible.length) box.append(el('p','',lt('请选择要显示的板块。','Select sections to display.')));
    }
    document.getElementById('homeLayoutReset').onclick = function() {
        draft = defaultLayout(); preferences(); layoutStatus.textContent = lt('已恢复默认，保存后生效。','Defaults restored. Save to apply.');
    };
    layoutDialog.addEventListener('cancel',function(e) {if (saving) e.preventDefault();});
    document.getElementById('homeLayoutSave').onclick = async function() {
        if (saving || !sections.length) return;
        saving = true;
        layoutDialog.querySelectorAll('button,input,select').forEach(function(n) {n.disabled = true;});
        layoutStatus.textContent = lt('正在保存…','Saving…');
        try {
            var response = await csrfFetch('/api/home/layout',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({layout:draft})});
            var data = await response.json();
            if (!response.ok || data.code !== 0 || !Array.isArray(data.layout)) throw new Error('save failed');
            layout = data.layout; render();
            try {localStorage.removeItem(key);} catch (_) {}
            layoutDialog.close();
        } catch (_) {
            layoutStatus.textContent = lt('保存失败，请检查网络或登录状态后重试。','Could not save. Check your connection or sign-in status and retry.');
        } finally {
            saving = false;
            layoutDialog.querySelectorAll('button,input,select').forEach(function(n) {n.disabled = false;});
            preferences();
        }
    };
    async function requestSummary(ticket) {
        for (var attempt = 0; attempt < 2; attempt++) {
            var controller = new AbortController(); activeRequest = controller;
            // A cold browser may queue this behind fonts/common assets on slow links.
            var timeout = setTimeout(function () { controller.abort(); }, 60000);
            try {
                var response = await fetch('/api/home?order=' + sort, {credentials:'same-origin',cache:'no-store',signal:controller.signal});
                var data = await response.json();
                return {response:response,data:data};
            } catch (err) {
                // Only retry this read-only GET, once; never retry HTTP/business errors.
                if (ticket !== sequence || attempt || (err.name !== 'AbortError' && err.name !== 'TypeError')) throw err;
                status.textContent = lt('网络较慢，正在重试加载…','Slow connection. Retrying…');
            } finally { clearTimeout(timeout); }
        }
    }
    async function load() {
        var ticket = ++sequence;
        if (activeRequest) activeRequest.abort();
        status.hidden = false; status.textContent = lt('正在加载最近的记录…','Loading recent records…'); retry.hidden = true; grid.setAttribute('aria-busy','true');
        // Remove previous user's/stale records if authentication or loading fails.
        grid.replaceChildren();
        try {
            var result = await requestSummary(ticket);
            var response = result.response, data = result.data;
            if (ticket !== sequence) return;
            if (response.status === 401) { window.location.replace('/login'); return; }
            if (!response.ok || data.code !== 0 || !Array.isArray(data.sections)) throw new Error('home request failed');
            sections = data.sections;
            layout = Array.isArray(data.layout) ? data.layout : defaultLayout().map(function(item) {item.hidden = hidden.includes(item.key); return item;});
            render();
            if (!layoutDialog.open) {draft = layout.map(function(i) {return Object.assign({},i);}); preferences();}
        } catch (err) {
            if (ticket !== sequence) return;
            console.warn('Home load failed:',err);
            sections = []; preferences(); status.hidden = false; status.textContent = err.name === 'AbortError' ? lt('请求超时，请重试','Request timed out. Please retry.') : lt('首页加载失败，请检查网络后重试。','Could not load your home page. Check your connection and retry.'); retry.hidden = false;
        } finally { if (ticket === sequence) grid.setAttribute('aria-busy','false'); }
    }
    document.querySelectorAll('[data-home-sort]').forEach(function (button) { button.onclick = function () {
        sort = button.dataset.homeSort;
        document.querySelectorAll('[data-home-sort]').forEach(function (b) { b.setAttribute('aria-pressed',String(b === button)); }); load();
    }; });
    document.querySelectorAll('[data-home-dialog]').forEach(function (b) { b.onclick = function () {
        if (b.dataset.homeDialog === 'homeCustomize') {draft = layout.map(function(i) {return Object.assign({},i);}); layoutStatus.textContent = ''; preferences();}
        document.getElementById(b.dataset.homeDialog).showModal();
    }; });
    document.querySelectorAll('[data-home-close]').forEach(function (b) { b.onclick = function () { if (!saving) b.closest('dialog').close(); }; });
    document.querySelectorAll('.home-dialog').forEach(function (d) { d.addEventListener('click',function(e) { if (!saving && e.target === d) { var r=d.getBoundingClientRect(); if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)d.close(); } }); });
    retry.onclick = load;
    window.addEventListener('pageshow',function(e) { if(e.persisted) load(); });
    window.addEventListener('bookstark:assistant-created',load);
    load();
})();
