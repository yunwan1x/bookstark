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
    try { var saved = JSON.parse(localStorage.getItem(key)); if (Array.isArray(saved)) hidden = saved; } catch (_) {}
    var now = new Date();
    document.getElementById('homeToday').textContent = now.toLocaleDateString('zh-CN', {year:'numeric', month:'long', day:'numeric', weekday:'long'});
    function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; }
    function render() {
        grid.replaceChildren();
        sections.forEach(function (s) {
            var m = modules[s.key];
            if (!m || hidden.includes(s.key)) return;
            var card = el('section', 'home-card'); card.dataset.section = s.key; card.style.setProperty('--home-accent', m[2]);
            var head = el('div', 'home-card-head');
            var icon = el('span', 'home-card-icon'); var glyph = el('i', 'fa-solid fa-' + m[1]); glyph.setAttribute('aria-hidden','true'); icon.append(glyph);
            var label = el('div'); var title = el('h2', '', m[0]); title.id = 'home-title-' + s.key; card.setAttribute('aria-labelledby', title.id);
            label.append(title, el('div', 'home-card-subtitle', '最新 ' + s.items.length + ' 条 / 共 ' + s.total + ' 条'));
            var all = el('a', 'home-card-all', '查看全部 →'); all.href = m[3]; all.setAttribute('aria-label','查看全部' + m[0]); head.append(icon,label,all); card.append(head);
            var list = el('ul', 'home-list'); list.id = 'home-list-' + s.key;
            s.items.forEach(function (item) {
                var li = el('li'); var a = el('a', 'home-row');
                // Only server-generated local routes are accepted, never raw resource URLs.
                if (typeof item.url !== 'string' || !item.url.startsWith('/') || item.url.startsWith('//')) return;
                a.href = item.url; a.title = item.title || '未命名'; a.append(el('span','home-row-title',item.title || '未命名'));
                if (item.badge) a.append(el('span','home-badge',({markdown:'MD',html:'HTML',blog:'文章 / 笔记',book:'书籍',online:'在线',offline:'离线'})[item.badge] || item.badge));
                var date = el('time','',item.date ? item.date.slice(5) : ''); date.dateTime = item.date; date.title = item.date; a.append(date); li.append(a); list.append(li);
            });
            card.append(list);
            if (!s.items.length) card.append(el('p','home-empty','还没有' + m[0] + '记录'));
            if (s.items.length > 3) {
                var expand = el('button','home-expand','展开最近 ' + s.items.length + ' 条 ↓'); expand.setAttribute('aria-expanded','false'); expand.setAttribute('aria-controls',list.id);
                expand.onclick = function () { var open = list.classList.toggle('expanded'); expand.setAttribute('aria-expanded',String(open)); expand.textContent = open ? '收起 ↑' : '展开最近 ' + s.items.length + ' 条 ↓'; };
                card.append(expand);
            }
            grid.append(card);
        });
        status.hidden = grid.childElementCount > 0;
        if (!grid.childElementCount) status.textContent = '所有板块已隐藏，可在“自定义板块”中重新开启。';
    }
    function preferences() {
        var box = document.getElementById('homePreferences'); box.replaceChildren();
        sections.forEach(function (s) {
            var label = el('label'); var input = el('input'); input.type = 'checkbox'; input.checked = !hidden.includes(s.key);
            input.onchange = function () {
                hidden = hidden.filter(function (k) { return k !== s.key; }); if (!input.checked) hidden.push(s.key);
                try { localStorage.setItem(key,JSON.stringify(hidden)); } catch (_) {}
                render();
            };
            label.append(input,el('span','',modules[s.key][0])); box.append(label);
        });
        if (!sections.length) box.append(el('p','','请先加载首页数据。'));
    }
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
                status.textContent = '网络较慢，正在重试加载…';
            } finally { clearTimeout(timeout); }
        }
    }
    async function load() {
        var ticket = ++sequence;
        if (activeRequest) activeRequest.abort();
        status.hidden = false; status.textContent = '正在加载最近的记录…'; retry.hidden = true; grid.setAttribute('aria-busy','true');
        // Remove previous user's/stale records if authentication or loading fails.
        grid.replaceChildren();
        try {
            var result = await requestSummary(ticket);
            var response = result.response, data = result.data;
            if (ticket !== sequence) return;
            if (response.status === 401) { window.location.replace('/login'); return; }
            if (!response.ok || data.code !== 0 || !Array.isArray(data.sections)) throw new Error(data.message || data.error || '首页加载失败');
            sections = data.sections; render(); preferences();
        } catch (err) {
            if (ticket !== sequence) return;
            sections = []; preferences(); status.hidden = false; status.textContent = '加载失败：' + (err.name === 'AbortError' ? '请求超时，请重试' : err.message || '请检查网络'); retry.hidden = false;
        } finally { if (ticket === sequence) grid.setAttribute('aria-busy','false'); }
    }
    document.querySelectorAll('[data-home-sort]').forEach(function (button) { button.onclick = function () {
        sort = button.dataset.homeSort;
        document.querySelectorAll('[data-home-sort]').forEach(function (b) { b.setAttribute('aria-pressed',String(b === button)); }); load();
    }; });
    document.querySelectorAll('[data-home-dialog]').forEach(function (b) { b.onclick = function () { document.getElementById(b.dataset.homeDialog).showModal(); }; });
    document.querySelectorAll('[data-home-close]').forEach(function (b) { b.onclick = function () { b.closest('dialog').close(); }; });
    document.querySelectorAll('.home-dialog').forEach(function (d) { d.addEventListener('click',function(e) { if (e.target === d) { var r=d.getBoundingClientRect(); if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)d.close(); } }); });
    retry.onclick = load;
    window.addEventListener('pageshow',function(e) { if(e.persisted) load(); });
    load();
})();
