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
        shares: ['广场', 'users', '#10a880', '/shares'],
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
    var moduleEnglish = {notes:'Notes',articles:'Articles',tasks:'Tasks',books:'Books',bookmarks:'Bookmarks',topics:'Topics',nav:'Navigation',shares:'Community',assets:'Assets'};
    function moduleName(key) { return english ? moduleEnglish[key] : modules[key][0]; }
    function defaultLayout() { return Object.keys(modules).map(function(k) {return {key:k,width:1,hidden:false};}); }
    function available(item) { return sections.some(function(s) {return s.key === item.key;}); }
    try { var saved = JSON.parse(localStorage.getItem(key)); if (Array.isArray(saved)) hidden = saved; } catch (_) {}
    var now = new Date();
    function dateKey(date) { return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0'); }
    function parseDate(value) { return new Date(value+'T12:00:00'); }
    var selected = '', rangeStart = '', rangeEnd = '', rangeMode = 'all', limit = 10;
    var calendarMonth = new Date(now.getFullYear(),now.getMonth(),1), activity = new Set();
    var activityCounts = {}, activityEnd = dateKey(now), activityReady = false;
    var firstActivityDay = new Date(now);firstActivityDay.setDate(firstActivityDay.getDate()-(firstActivityDay.getDay()+6)%7-77);
    var activityStart = dateKey(firstActivityDay);
    var startInput = document.getElementById('homeStart'), endInput = document.getElementById('homeEnd');
    function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; }
    function selectDay(value) {
        selected = value; rangeStart=value; rangeEnd=value; rangeMode='1';
        calendarMonth=new Date(parseDate(value).getFullYear(),parseDate(value).getMonth(),1);
        syncDates(); load();
    }
    function dateButton(date, other, strip) {
        var value=dateKey(date), button=el('button','calendar-day'+(other?' other-month':'')+(value===dateKey(new Date())?' today':'')+(value===selected?' selected':''));
        button.type='button';button.dataset.date=value;button.setAttribute('aria-pressed',String(value===selected));
        button.setAttribute('aria-label',date.toLocaleDateString(english?'en-US':'zh-CN',{year:'numeric',month:'long',day:'numeric',weekday:'long'}));
        if(value>=rangeStart&&value<=rangeEnd)button.classList.add('home-in-range');
        button.append(el('span','calendar-day-num',String(date.getDate())));
        if(strip)button.append(el('span','home-weekday',date.toLocaleDateString(english?'en-US':'zh-CN',{weekday:'short'})));
        if(activity.has(value)){var dot=el('span','heat-dot');dot.setAttribute('aria-hidden','true');button.append(dot);}
        button.onclick=function(){selectDay(value);};return button;
    }
    function renderCalendar() {
        document.getElementById('homeMonthTitle').textContent=calendarMonth.toLocaleDateString(english?'en-US':'zh-CN',{year:'numeric',month:'long'});
        var days=document.getElementById('homeCalendarDays');days.replaceChildren();
        var first=new Date(calendarMonth), offset=(first.getDay()+6)%7;first.setDate(1-offset);
        var cells=Math.ceil((offset+new Date(calendarMonth.getFullYear(),calendarMonth.getMonth()+1,0).getDate())/7)*7;
        for(var i=0;i<cells;i++){var d=new Date(first);d.setDate(first.getDate()+i);days.append(dateButton(d,d.getMonth()!==calendarMonth.getMonth(),false));}
        var strip=document.getElementById('homeWeekStrip');strip.replaceChildren();var monday=parseDate(selected || dateKey(now));monday.setDate(monday.getDate()-(monday.getDay()+6)%7);
        for(var j=0;j<7;j++){var day=new Date(monday);day.setDate(monday.getDate()+j);strip.append(dateButton(day,false,true));}
    }
    function renderActivity() {
        var heatmap=document.getElementById('homeHeatmap'),months=document.getElementById('homeActivityMonths'),weekdays=document.getElementById('homeActivityWeekdays');
        var focusDay=heatmap.contains(document.activeElement)?document.activeElement.dataset.heatDate:'';
        heatmap.replaceChildren();months.replaceChildren();weekdays.replaceChildren();
        var labels=english?['M','T','W','T','F','S','S']:['一','二','三','四','五','六','日'];
        labels.forEach(function(label){weekdays.append(el('span','',label));});
        var first=parseDate(activityStart),lastMonth=-1;
        for(var week=0;week<12;week++){
            var monday=new Date(first);monday.setDate(first.getDate()+week*7);
            months.append(el('span','',monday.getMonth()!==lastMonth?monday.toLocaleDateString(english?'en-US':'zh-CN',{month:'short'}):''));lastMonth=monday.getMonth();
            for(var day=0;day<7;day++){
                var date=new Date(monday);date.setDate(monday.getDate()+day);
                var value=dateKey(date),count=Number(activityCounts[value])||0,button=el('button','home-heat-cell');
                button.type='button';button.dataset.heatDate=value;button.dataset.level=String(count===0?0:count===1?1:count<=3?2:count<=7?3:4);
                button.disabled=!activityReady||value>activityEnd;
                var description=value+' · '+(activityReady?lt(count+' 条内容',''+count+' items'):lt('正在加载','Loading'));
                button.title=description;button.setAttribute('aria-label',description);button.setAttribute('aria-pressed',String(value===selected));
                if(rangeStart&&value>=rangeStart&&value<=rangeEnd)button.classList.add('is-in-range');
                button.onclick=function(){selectDay(this.dataset.heatDate);};heatmap.append(button);
            }
        }
        document.getElementById('homeActivity').setAttribute('aria-busy',String(!activityReady));
        document.getElementById('homeActivityHint').textContent=sort==='created'?lt('按内容创建日期统计 · 点击日期筛选','By creation date · Click a day to filter'):lt('按内容最近更新日期统计 · 点击日期筛选','By last update date · Click a day to filter');
        if(focusDay){var target=heatmap.querySelector('[data-heat-date="'+focusDay+'"]');if(target&&!target.disabled)target.focus();}
    }
    document.getElementById('homeHeatmap').addEventListener('keydown',function(e){
        var button=e.target.closest('[data-heat-date]'),offset={ArrowLeft:-7,ArrowRight:7,ArrowUp:-1,ArrowDown:1}[e.key];
        if(!button||!offset)return;
        e.preventDefault();var date=parseDate(button.dataset.heatDate);date.setDate(date.getDate()+offset);
        var target=this.querySelector('[data-heat-date="'+dateKey(date)+'"]');if(target&&!target.disabled)target.focus();
    });
    function syncDates() {
        startInput.value=rangeStart;endInput.value=rangeEnd;endInput.min=rangeStart;startInput.max=rangeEnd;
        document.getElementById('homeSelectedDate').textContent=rangeStart&&rangeStart!==rangeEnd ? rangeStart.replaceAll('-','/')+' – '+rangeEnd.replaceAll('-','/') : selected ? parseDate(selected).toLocaleDateString(english?'en-US':'zh-CN',{year:'numeric',month:'long',day:'numeric',weekday:'long'}) : lt('最近内容','Recent content');
        document.querySelector('.home-date-hint').textContent=rangeStart ? lt('所选日期内的内容，按时间倒序显示。','Content within the selected dates, newest first.') : lt('不限日期，按时间倒序显示最近内容。','Recent content across all dates, newest first.');
        document.querySelectorAll('[data-home-range]').forEach(function(b){var active=b.dataset.homeRange===rangeMode;b.classList.toggle('active',active);b.setAttribute('aria-pressed',String(active));});
        renderCalendar();
        renderActivity();
    }
    document.querySelectorAll('[data-home-range]').forEach(function(b){b.onclick=function(){
        if(b.dataset.homeRange==='custom'){
            startInput.value=rangeStart||dateKey(new Date());endInput.value=rangeEnd||startInput.value;
            startInput.max=endInput.value;endInput.min=startInput.value;
            document.getElementById('homeDateDialog').showModal();startInput.focus();return;
        }
        rangeMode=b.dataset.homeRange;
        if(rangeMode==='all'){selected='';rangeStart='';rangeEnd='';syncDates();load();return;}
        if(!selected)selected=dateKey(new Date());
        if(!rangeStart){rangeStart=selected;rangeEnd=selected;}
        var first=parseDate(selected);first.setDate(first.getDate()-Number(rangeMode)+1);rangeStart=dateKey(first);rangeEnd=selected;syncDates();load();
    };});
    document.querySelectorAll('[data-home-today]').forEach(function(b){b.onclick=function(){selectDay(dateKey(new Date()));};});
    document.getElementById('homeRangeForm').onsubmit=function(e){
        e.preventDefault();var from=parseDate(startInput.value),to=parseDate(endInput.value);
        if(!startInput.value||!endInput.value||!Number.isFinite(+from)||!Number.isFinite(+to)||from>to||to-from>366*86400000){BSDialog.toast(lt('请选择有效的日期范围，最多一年。','Choose a valid date range of up to one year.'),'error');return;}
        rangeStart=startInput.value;rangeEnd=endInput.value;selected=rangeEnd;rangeMode='custom';calendarMonth=new Date(to.getFullYear(),to.getMonth(),1);document.getElementById('homeDateDialog').close();syncDates();load();
    };
    startInput.oninput=function(){endInput.min=startInput.value;};endInput.oninput=function(){startInput.max=endInput.value;};
    document.getElementById('homeLimit').onchange=function(){limit=Number(this.value);load();};
    [-1,1].forEach(function(delta){document.getElementById(delta<0?'homePrevMonth':'homeNextMonth').onclick=function(){calendarMonth.setMonth(calendarMonth.getMonth()+delta);activity.clear();renderCalendar();load();};});
    document.getElementById('homeCalendarToggle').onclick=function(){
        var open=document.getElementById('homeCalendar').classList.toggle('is-open');this.setAttribute('aria-expanded',String(open));
    };
    document.getElementById('homeCalendar').addEventListener('keydown',function(e){
        if(e.key==='Escape'){this.classList.remove('is-open');document.getElementById('homeCalendarToggle').setAttribute('aria-expanded','false');document.getElementById('homeCalendarToggle').focus();}
        var button=e.target.closest('[data-date]');if(!button)return;
        var shift={ArrowLeft:-1,ArrowRight:1,ArrowUp:-7,ArrowDown:7}[e.key];
        if(shift){e.preventDefault();var next=parseDate(button.dataset.date);next.setDate(next.getDate()+shift);selectDay(dateKey(next));var target=this.querySelector('[data-date="'+dateKey(next)+'"]');if(target)target.focus();}
    });
    syncDates();
    function renderSkeleton() {
        grid.replaceChildren();
        var pending = layout;
        if (!pending.length) {
            try { pending = JSON.parse(localStorage.getItem(key + ':layout')) || []; } catch (_) {}
        }
        if (!Array.isArray(pending) || !pending.length) pending = defaultLayout().filter(function(item) { return !hidden.includes(item.key); });
        pending.forEach(function(item) {
            if (!item || !modules[item.key] || item.hidden) return;
            var card = el('section','home-card skeleton-card home-loading-card');
            card.setAttribute('aria-hidden','true');
            card.dataset.width = [1,2,3].includes(item.width) ? String(item.width) : '1';
            card.append(el('div','skeleton home-skeleton-heading'));
            for (var i = 0; i < 10; i++) card.append(el('div','skeleton home-skeleton-line'));
            grid.append(card);
        });
    }
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
            label.append(title);
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
            if (!s.items.length) card.append(el('p','home-empty',rangeStart ? lt('所选日期内没有记录','No records in the selected date range') : lt('暂无记录','No records yet')));
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
            try {localStorage.setItem(key + ':layout',JSON.stringify(layout));} catch (_) {}
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
                var query = new URLSearchParams({order:sort,start:rangeStart,end:rangeEnd,limit:String(limit),month:dateKey(calendarMonth).slice(0,7)});
                var response = await fetch('/api/home?' + query, {credentials:'same-origin',cache:'no-store',signal:controller.signal});
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
        renderSkeleton();
        try {
            var result = await requestSummary(ticket);
            var response = result.response, data = result.data;
            if (ticket !== sequence) return;
            if (response.status === 401) { window.location.replace('/login'); return; }
            if (!response.ok || data.code !== 0 || !Array.isArray(data.sections)) throw new Error('home request failed');
            sections = data.sections;
            activityCounts=data.activity||{};activityStart=data.activity_start||activityStart;activityEnd=data.activity_end||activityEnd;activityReady=true;renderActivity();
            activity = new Set(); sections.forEach(function(s){(s.dates||[]).forEach(function(day){activity.add(day);});});renderCalendar();
            layout = Array.isArray(data.layout) ? data.layout : defaultLayout().map(function(item) {item.hidden = hidden.includes(item.key); return item;});
            try { localStorage.setItem(key + ':layout',JSON.stringify(layout)); } catch (_) {}
            render();
            if (!layoutDialog.open) {draft = layout.map(function(i) {return Object.assign({},i);}); preferences();}
        } catch (err) {
            if (ticket !== sequence) return;
            console.warn('Home load failed:',err);
            grid.replaceChildren();
            activityCounts={};activityReady=false;renderActivity();
            activity.clear();renderCalendar();
            sections = []; preferences(); status.hidden = false; status.textContent = err.name === 'AbortError' ? lt('请求超时，请重试','Request timed out. Please retry.') : lt('首页加载失败，请检查网络后重试。','Could not load your home page. Check your connection and retry.'); retry.hidden = false;
        } finally { if (ticket === sequence) grid.setAttribute('aria-busy','false'); }
    }
    document.querySelectorAll('[data-home-sort]').forEach(function (button) { button.onclick = function () {
        if (sort === button.dataset.homeSort) return;
        sort = button.dataset.homeSort;
        document.querySelectorAll('[data-home-sort]').forEach(function (b) { b.setAttribute('aria-pressed',String(b === button)); b.classList.toggle('active',b === button); }); load();
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
