(function() {
    'use strict';

    var allLabels = window.BM_LABELS || [];
    var isLoggedIn = window.BM_IS_LOGGED_IN || false;
    var isAdmin = window.BM_IS_ADMIN || false;
    var scope = isLoggedIn ? 'mine' : 'public';

    // Batch mode state
    var selectedIds = {};
    var editMode = false;
    var selectAllMode = false;
    var selectAllTotal = 0;
    var rowActionLocks = {};

    var FAVICON_TIMEOUT = 5000;
    var _dialogFavicon = '';

	function faviconProxyUrl(faviconUrl) {
	    if (!faviconUrl) return '';
	    return '/api/favicon?url=' + encodeURIComponent(faviconUrl);
	}

    function activateOnKey(event, action, value) {
        if (!event || (event.key !== 'Enter' && event.key !== ' ')) return;
        event.preventDefault();
        event.stopPropagation();
        if (action === 'tree') toggleTreeNode(value);
        else if (action === 'label') toggleLabel(value);
        else if (action === 'parent') toggleParent(value);
        else if (action === 'flat') toggleFlatTags();
        else if (action === 'letter') toggleFlatLetter(value);
        else if (action === 'site') searchBySite(event.currentTarget);
        else if (action === 'searchLabel') searchByLabel(value);
    }

    function faviconFallback(title, url) {
        var ch = '?';
        var bg = '';
        var hostname = '';
        if (url) {
            try { hostname = new URL(url).hostname; } catch(e) {}
        }
        if (hostname) {
            ch = domainChar(hostname);
            bg = domainColor(hostname);
        } else {
            var t = title || '';
            if (t) {
                var first = t.charAt(0);
                var code = first.charCodeAt(0);
                ch = (code >= 0x4E00 && code <= 0x9FFF) ? first : first.toUpperCase();
            }
            bg = charColor(t || ch);
        }
        return '<span class="bm-row-favicon bm-favicon-fallback" style="background:' + bg + '">' + esc(ch) + '</span>';
    }

    function replaceFaviconWithFallback(img) {
        if (!img || !img.parentNode) return;
        var tmp = document.createElement('span');
        var url = img.getAttribute('data-url') || '';
        var title = img.getAttribute('data-title') || '';
        tmp.innerHTML = faviconFallback(title, url);
        var span = tmp.firstElementChild;
        // Preserve site-search attributes from the original img
        if (url) span.setAttribute('data-url', url);
        span.setAttribute('data-id', img.getAttribute('data-id') || '');
        span.setAttribute('data-title', title);
        span.classList.add('bm-site-icon');
        span.setAttribute('onclick', 'event.preventDefault();event.stopPropagation();BM.searchBySite(this)');
        span.setAttribute('onkeydown', 'BM.activateOnKey(event, \'site\', \'\')');
        span.setAttribute('tabindex', '0');
        span.setAttribute('role', 'button');
        span.setAttribute('aria-label', window.__('bookmark.favicon_search'));
        span.setAttribute('title', window.__('bookmark.favicon_search'));
        img.replaceWith(span);
    }

    function setupFaviconTimeouts() {
        var imgs = document.querySelectorAll('img.bm-row-favicon:not([data-ft])');
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            img.setAttribute('data-ft', '1');
            if (img.complete && img.naturalWidth > 0) continue;
            (function(el) {
                var timer = setTimeout(function() { replaceFaviconWithFallback(el); }, FAVICON_TIMEOUT);
                el.onload = function() { clearTimeout(timer); el.onload = null; el.onerror = null; };
                el.onerror = function() { clearTimeout(timer); replaceFaviconWithFallback(el); };
            })(img);
        }
    }

    // Lazy-refresh favicons that are empty or default /favicon.ico
    var _faviconRefreshQueue = [];
    var _faviconRefreshing = false;

    function needsFaviconRefresh(favicon) {
        if (!favicon) return true;
        // Default favicon.ico pattern from generateFaviconURL
        try { var u = new URL(favicon); return u.pathname === '/favicon.ico'; } catch(e) { return false; }
    }

    function queueFaviconRefresh(bookmarkId, url) {
        if (_faviconRefreshQueue.some(function(q) { return q.id === bookmarkId; })) return;
        _faviconRefreshQueue.push({ id: bookmarkId, url: url });
        processFaviconRefreshQueue();
    }

    function processFaviconRefreshQueue() {
        if (_faviconRefreshing || _faviconRefreshQueue.length === 0) return;
        _faviconRefreshing = true;
        var item = _faviconRefreshQueue.shift();
        csrfFetch('/api/bookmarks/' + item.id + '/favicon', { method: 'PATCH', headers: {'Content-Type': 'application/json'} })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            var data = res.data || res;
            if (data && data.updated && data.favicon) {
                // Update in-memory and DOM
                var bm = currentBookmarks.find(function(b) { return b.bookmark_id === item.id; });
                if (bm) bm.favicon = data.favicon;
                var img = document.querySelector('img.bm-row-favicon[data-id="' + item.id + '"]');
                if (img) {
                    img.src = faviconProxyUrl(data.favicon);
                } else {
                    // Fallback: re-render the row
                    var row = document.querySelector('.bm-row[data-id="' + item.id + '"]');
                    if (row && bm) {
                        var tmp = document.createElement('div');
                        tmp.innerHTML = renderSingleRow(bm);
                        row.replaceWith(tmp.firstElementChild);
                        setupFaviconTimeouts();
                    }
                }
            }
        })
        .catch(function() {})
        .finally(function() {
            _faviconRefreshing = false;
            // Small delay to avoid overwhelming the server
            setTimeout(processFaviconRefreshQueue, 200);
        });
    }

    var currentAction = null;
    var batchTags = [];

    // State
    var selectedLabels = [];
    var siteFilter = ''; // 站点域名筛选
    var drawerPreviousFocus = null;
    var currentBookmarks = [];
    var currentPage = 1;
    var totalBookmarks = 0;
    function updateBmCount() {
        var el = document.getElementById('bm-count');
        if (el) el.textContent = window.__('bookmark.total').replace('{n}', totalBookmarks);
    }
    var isLoading = false;
    var PAGE_SIZE = window.BM_PAGE_SIZE || 20;

    // Sidebar state
    var sidebarOpen = false;
    var sidebarFilter = '';

    // 标签树展开状态：默认全部展开；用户折叠后保存 false。
    var treeCollapsed = (function() {
        try {
            var v = JSON.parse(localStorage.getItem('bm_tree_expanded') || '{}');
            return typeof v === 'object' && v !== null ? v : {};
        } catch(e) { return {}; }
    })();
    function saveTreeCollapsed() {
        try { localStorage.setItem('bm_tree_expanded', JSON.stringify(treeCollapsed)); } catch(e) {}
    }
    function isTreeExpanded(prefix) {
        return treeCollapsed[prefix] !== false;
    }

    // 其他标签（flat）默认展开
    var flatTagsExpanded = (function() {
        try {
            var saved = localStorage.getItem('bm_flat_expanded');
            return saved === null ? true : saved === 'true';
        } catch(e) { return true; }
    })();
    function saveFlatTagsExpanded() {
        try { localStorage.setItem('bm_flat_expanded', flatTagsExpanded ? 'true' : 'false'); } catch(e) {}
    }

    // 其他标签字母分组默认全部展开；用户折叠后保存 false。
    var flatLetterExpanded = (function() {
        try {
            var v = JSON.parse(localStorage.getItem('bm_flat_letter_expanded') || '{}');
            return typeof v === 'object' && v !== null ? v : {};
        } catch(e) { return {}; }
    })();
    var flatLetterSearchExpanded = {};
    function saveFlatLetterExpanded() {
        try { localStorage.setItem('bm_flat_letter_expanded', JSON.stringify(flatLetterExpanded)); } catch(e) {}
    }
    function isFlatLetterExpanded(letter) {
        if (isDesktop() && sidebarFilter && Object.prototype.hasOwnProperty.call(flatLetterSearchExpanded, letter)) {
            return flatLetterSearchExpanded[letter];
        }
        return flatLetterExpanded[letter] !== false;
    }

    function getVisibleFlatLetters() {
        var labels = isDesktop() ? filterLabels(sidebarFilter) : allLabels;
        return groupFlatByLetter(buildLabelTree(labels).flat).order;
    }

    function setAllFlatLettersExpanded(expanded) {
        var letters = getVisibleFlatLetters();
        var isSearchView = isDesktop() && !!sidebarFilter;
        if (!isSearchView) {
            flatTagsExpanded = expanded;
            saveFlatTagsExpanded();
        }
        for (var i = 0; i < letters.length; i++) {
            if (isSearchView) flatLetterSearchExpanded[letters[i]] = expanded;
            else flatLetterExpanded[letters[i]] = expanded;
        }
        if (!isSearchView) saveFlatLetterExpanded();
        if (isDesktop()) renderSidebarTags();
        else renderDrawerTags();
    }

    function renderFlatTagsHeader(count) {
        var expandLabel = window.__('bookmark.sidebar.expand_all');
        var collapseLabel = window.__('bookmark.sidebar.collapse_all');
        var html = '<div class="bm-section-flat-header' + (flatTagsExpanded ? ' expanded' : '') + '">';
        html += '<button type="button" class="bm-section-flat-toggle" aria-expanded="' + (flatTagsExpanded ? 'true' : 'false') + '" onclick="BM.toggleFlatTags()">';
        html += '<span class="bm-section-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></span>';
        html += '<span class="bm-section-flat-title">' + window.__('bookmark.sidebar.other_tags') + '</span>';
        html += '<span class="bm-section-count">' + count + '</span>';
        html += '</button>';
        html += '<span class="bm-section-flat-actions">';
        html += '<button type="button" class="bm-flat-bulk-btn" aria-label="' + escAttr(expandLabel) + '" title="' + escAttr(expandLabel) + '" onclick="event.stopPropagation();BM.setAllFlatLettersExpanded(true)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="7 7 12 12 17 7"/><polyline points="7 13 12 18 17 13"/></svg></button>';
        html += '<button type="button" class="bm-flat-bulk-btn" aria-label="' + escAttr(collapseLabel) + '" title="' + escAttr(collapseLabel) + '" onclick="event.stopPropagation();BM.setAllFlatLettersExpanded(false)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="7 11 12 6 17 11"/><polyline points="7 17 12 12 17 17"/></svg></button>';
        html += '</span></div>';
        return html;
    }

    function groupFlatByLetter(flatTags) {
        var groups = {};
        var order = [];
        for (var i = 0; i < flatTags.length; i++) {
            var letter = getPinyinInitial(flatTags[i]);
            if (!groups[letter]) { groups[letter] = []; order.push(letter); }
            groups[letter].push(flatTags[i]);
        }
        order.sort(compareBookmarkLetters);
        for (var i = 0; i < order.length; i++) {
            groups[order[i]].sort(compareBookmarkLabels);
        }
        return { groups: groups, order: order };
    }

    // 解析标签列表为树形结构
    // 返回：{ parents: [{prefix, children:[{name}]}, ...], flat: [{name}] }
    // parents = 有 "/" 的父节点，flat = 没有 "/" 的普通标签
    function buildLabelTree(labels) {
        var parentMap = {}; // prefix -> [childName, ...]
        var parentOrder = [];
        var flat = [];
        for (var i = 0; i < labels.length; i++) {
            var name = labels[i];
            var slashIdx = name.indexOf('/');
            if (slashIdx > 0 && slashIdx < name.length - 1) {
                var prefix = name.substring(0, slashIdx);
                if (!parentMap[prefix]) { parentMap[prefix] = []; parentOrder.push(prefix); }
                parentMap[prefix].push(name);
            } else {
                flat.push(name);
            }
        }
        parentOrder.sort(compareBookmarkLabels);
        flat.sort(compareBookmarkLabels);
        var parents = [];
        for (var pi = 0; pi < parentOrder.length; pi++) {
            parentMap[parentOrder[pi]].sort(compareBookmarkLabels);
            parents.push({ prefix: parentOrder[pi], children: parentMap[parentOrder[pi]] });
        }
        return { parents: parents, flat: flat };
    }

    // 当前激活的父节点过滤（OR 逻辑），null 表示未激活
    var activeParentFilter = null; // { prefix, children }

    // 父节点点击：OR 筛选所有子标签（清空其他筛选）
    function toggleParent(prefix) {
        var tree = buildLabelTree(filterLabels(sidebarFilter));
        var parent = null;
        for (var i = 0; i < tree.parents.length; i++) {
            if (tree.parents[i].prefix === prefix) { parent = tree.parents[i]; break; }
        }
        if (!parent) return;
        if (activeParentFilter && activeParentFilter.prefix === prefix) {
            // 再次点击：取消
            activeParentFilter = null;
        } else {
            activeParentFilter = { prefix: prefix, children: parent.children.slice() };
            selectedLabels = []; // 父节点 OR 模式下清空单独标签选择
        }
        if (isDesktop()) { renderSidebarTags(); renderSidebarSelected(); }
        else { renderDrawerTags(); }
        renderSelectedTags();
        fetchBookmarks(false);
    }

    // 折叠/展开父节点（不触发筛选）
    function toggleTreeNode(prefix) {
        treeCollapsed[prefix] = !isTreeExpanded(prefix);
        saveTreeCollapsed();
        if (isDesktop()) renderSidebarTags();
        else renderDrawerTags();
    }

    function toggleFlatTags() {
        flatTagsExpanded = !flatTagsExpanded;
        saveFlatTagsExpanded();
        if (isDesktop()) renderSidebarTags();
        else renderDrawerTags();
    }

    function toggleFlatLetter(letter) {
        if (isDesktop() && sidebarFilter) {
            flatLetterSearchExpanded[letter] = !isFlatLetterExpanded(letter);
        } else {
            flatLetterExpanded[letter] = !isFlatLetterExpanded(letter);
            saveFlatLetterExpanded();
        }
        if (isDesktop()) renderSidebarTags();
        else renderDrawerTags();
    }

    // Advanced search state
    var advLabels = [];          // selected labels in adv panel
    var advLabelLogic = 'and';   // 'and' or 'or'
    var advTimeDays = 0;         // 0=不限, 1/7/30=preset, -1=custom
    var advTimeField = 'create'; // 'create' or 'modify'
    var advStartDate = '';       // custom start date YYYY-MM-DD
    var advEndDate = '';         // custom end date YYYY-MM-DD
    var advIsPublic = false;
    var advIsPinned = false;
    var advNavVisible = false;
    var advNoLabel = false;
    var advKeyword = '';         // content search: url, desc, title
    var advLabelsCache = [];     // labels with count from API

    // --- Search state persistence (localStorage) ---
    var SEARCH_STATE_KEY = 'bm_search_state_' + scope;

    function saveSearchState() {
        try {
            var state = {
                selectedLabels: selectedLabels,
                siteFilter: siteFilter,
                currentPage: currentPage,
                keyword: (document.getElementById('bm-search') || {}).value || '',
                activeParentFilter: activeParentFilter,
                advLabels: advLabels,
                advLabelLogic: advLabelLogic,
                advTimeDays: advTimeDays,
                advTimeField: advTimeField,
                advStartDate: advStartDate,
                advEndDate: advEndDate,
                advIsPublic: advIsPublic,
                advIsPinned: advIsPinned,
                advNavVisible: advNavVisible,
                advNoLabel: advNoLabel,
                advKeyword: advKeyword
            };
            localStorage.setItem(SEARCH_STATE_KEY, JSON.stringify(state));
        } catch(e) {}
    }

    function restoreSearchState() {
        try {
            var raw = localStorage.getItem(SEARCH_STATE_KEY);
            if (!raw) return false;
            var state = JSON.parse(raw);
            if (typeof state !== 'object' || !state) return false;

            var validLabels = window.BM_LABELS || [];
            var labelSet = {};
            validLabels.forEach(function(l) { labelSet[l] = true; });

            if (Array.isArray(state.selectedLabels)) {
                selectedLabels = state.selectedLabels.filter(function(l) { return labelSet[l]; });
            }
            if (state.siteFilter && typeof state.siteFilter === 'string') {
                siteFilter = state.siteFilter;
            }
            if (typeof state.currentPage === 'number' && state.currentPage > 0) {
                currentPage = state.currentPage;
            }
            if (typeof state.keyword === 'string') {
                var searchInput = document.getElementById('bm-search');
                if (searchInput) searchInput.value = state.keyword;
            }
            if (state.activeParentFilter && Array.isArray(state.activeParentFilter.children)) {
                var validChildren = state.activeParentFilter.children.filter(function(l) { return labelSet[l]; });
                if (validChildren.length > 0) {
                    activeParentFilter = { prefix: state.activeParentFilter.prefix, children: validChildren };
                }
            }
            if (Array.isArray(state.advLabels)) {
                advLabels = state.advLabels.filter(function(l) { return labelSet[l]; });
            }
            if (state.advLabelLogic === 'or' || state.advLabelLogic === 'and') {
                advLabelLogic = state.advLabelLogic;
            }
            if (typeof state.advTimeDays === 'number') advTimeDays = state.advTimeDays;
            if (state.advTimeField === 'create' || state.advTimeField === 'modify') advTimeField = state.advTimeField;
            if (typeof state.advStartDate === 'string') advStartDate = state.advStartDate;
            if (typeof state.advEndDate === 'string') advEndDate = state.advEndDate;
            if (typeof state.advIsPublic === 'boolean') advIsPublic = state.advIsPublic;
            if (typeof state.advIsPinned === 'boolean') advIsPinned = state.advIsPinned;
            if (typeof state.advNavVisible === 'boolean') advNavVisible = state.advNavVisible;
            if (typeof state.advNoLabel === 'boolean') advNoLabel = state.advNoLabel;
            if (typeof state.advKeyword === 'string') advKeyword = state.advKeyword;

            return true;
        } catch(e) {
            return false;
        }
    }

    function isDesktop() {
        return window.innerWidth > 768;
    }

    // --- Pinyin initial ---
    var _pyBounds = '阿八嚓哒鹅发旮哈讥咔垃妈拿噢啪七日撒他挖希压匝';
    var _pyInitials = 'ABCDEFGHJKLMNOPQRSTWXYZ';
    function getPinyinInitial(s) {
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
    function compareBookmarkLetters(a, b) {
        if (a === b) return 0;
        if (a === '#') return 1;
        if (b === '#') return -1;
        return String(a).localeCompare(String(b), 'en-US');
    }
    function compareBookmarkLabels(a, b) {
        var ia = getPinyinInitial(a);
        var ib = getPinyinInitial(b);
        var letterCmp = compareBookmarkLetters(ia, ib);
        if (letterCmp !== 0) return letterCmp;
        return String(a).localeCompare(String(b), 'zh-CN', { numeric: true, sensitivity: 'base' });
    }

    // --- Data ---
    var skeletonHtml = '';
    try { skeletonHtml = document.getElementById('bm-loading').innerHTML; } catch(e) {}

    function fetchBookmarks(append, page) {
        var desktop = isDesktop();
        // If a new search (not append) is requested while loading, cancel the old one
        if (isLoading && !append) {
            isLoading = false;
        }
        if (isLoading) return Promise.resolve();
        // Reset page to 1 for new searches/filters, unless explicit page given
        if (page) {
            currentPage = page;
        } else if (!append) {
            currentPage = 1;
        }
        if (!append) { currentBookmarks = []; selectAllMode = false; selectAllTotal = 0; }

        isLoading = true;
        if (!append && skeletonHtml) {
            document.getElementById('bm-list').innerHTML = skeletonHtml;
        }

        var params = [];
        params.push('page=' + currentPage);
        params.push('page_size=' + PAGE_SIZE);
        params.push('scope=' + scope);
        if (selectedLabels.length > 0) params.push('labels=' + encodeURIComponent(selectedLabels.join(',')));
        if (activeParentFilter) params.push('labels_or=' + encodeURIComponent(activeParentFilter.children.join(',')));
        var keyword = document.getElementById('bm-search').value.trim();
        if (keyword) params.push('keyword=' + encodeURIComponent(keyword));
        if (siteFilter) params.push('site=' + encodeURIComponent(siteFilter));
        // Advanced search params
        if (advKeyword && !keyword) params.push('keyword=' + encodeURIComponent(advKeyword));
        if (advIsPublic) params.push('is_public=1');
        if (advIsPinned) params.push('is_pinned=1');
        if (advNavVisible) params.push('nav_visible=1');
        if (advNoLabel) params.push('no_label=1');
        if (advLabels.length > 0 && advLabelLogic === 'or') {
            params.push('labels_or=' + encodeURIComponent(advLabels.join(',')));
        }
        if (advTimeDays > 0) {
            var days = advTimeDays;
            var st = new Date(Date.now() - days * 86400000);
            params.push('start_time=' + encodeURIComponent(st.toISOString().slice(0, 19)));
            params.push('time_field=' + advTimeField);
        } else if (advTimeDays === -1) {
            if (advStartDate) params.push('start_time=' + encodeURIComponent(advStartDate + 'T00:00:00'));
            if (advEndDate) params.push('end_time=' + encodeURIComponent(advEndDate + 'T23:59:59'));
            params.push('time_field=' + advTimeField);
        }

        return fetch('/api/bookmarks?' + params.join('&'))
            .then(function(r) { return r.json(); })
            .then(function(res) {
                var data = res.data || [];
                currentBookmarks = data;
                totalBookmarks = res.total || 0;
                updateBmCount();
                renderBookmarkList();
                isLoading = false;
                renderPagination();
                saveSearchState();
                // In selectAllMode, auto-select all rows on current page
                if (selectAllMode && editMode) {
                    selectedIds = {};
                    for (var i = 0; i < currentBookmarks.length; i++) {
                        selectedIds[currentBookmarks[i].bookmark_id] = true;
                    }
                    selectAllTotal = totalBookmarks;
                    updateBatchBar();
                    updateAllRowSelectUI();
                }
            })
            .catch(function() {
                isLoading = false;
            });
    }

    function fetchLabels() {
        fetch('/api/bookmark-labels?scope=' + scope)
            .then(function(r) { return r.json(); })
            .then(function(res) {
                allLabels = res.data || [];
            });
    }

    // --- Batch mode (select-to-activate) ---
    function toggleEditMode() {
        editMode = !editMode;
        if (!editMode) {
            selectedIds = {};
            selectAllMode = false;
            selectAllTotal = 0;
            currentAction = null;
            batchTags = [];
        }
        renderBookmarkList();
        updateBatchBar();
    }

    function updateEditModeUI() {
        var btn = document.getElementById('bm-edit-btn');
        if (btn) {
            if (editMode) {
                btn.classList.add('bm-edit-btn-active');
            } else {
                btn.classList.remove('bm-edit-btn-active');
            }
        }
        var list = document.getElementById('bm-list');
        if (!list) return;
        if (editMode) {
            list.classList.add('bm-editing');
        } else {
            list.classList.remove('bm-editing');
        }
    }

    function toggleBatch() {
        // Legacy: no longer a mode toggle. Clear selection instead.
        selectedIds = {};
        currentAction = null;
        batchTags = [];
        updateBatchBar();
        updateAllRowSelectUI();
    }

    function resetBatchBar() {
        currentAction = null;
        batchTags = [];
        document.getElementById('bm-batch-tag-row').style.display = 'none';
        clearBatchTagChips();
        // Remove active state from all batch buttons
        var btns = document.querySelectorAll('.bm-batch-btn, .bm-batch-menu-item');
        for (var i = 0; i < btns.length; i++) btns[i].classList.remove('bm-batch-btn-active');
    }

    function updateBatchBar() {
        var bar = document.getElementById('bm-batch-bar');
        var count = getSelectedCount();
        if (editMode && (count > 0 || selectAllMode)) {
            bar.style.display = '';
        } else {
            bar.style.display = 'none';
            resetBatchBar();
        }
        var countEl = document.getElementById('bm-batch-count');
        if (countEl) {
            var displayCount = selectAllMode ? selectAllTotal : count;
            countEl.textContent = window.__('bookmark.batch.count_n').replace('{n}', displayCount);
            countEl.classList.toggle('bm-batch-count-all', selectAllMode);
        }
        var sa = document.getElementById('bm-select-all');
        if (sa) sa.checked = selectAllMode || (currentBookmarks.length > 0 && count === currentBookmarks.length);
    }

    function toggleSelect(id) {
        if (!editMode) return;
        if (selectAllMode) {
            // Exit selectAllMode: keep only current page items, toggle the clicked one
            selectAllMode = false;
            selectAllTotal = 0;
            selectedIds = {};
            for (var i = 0; i < currentBookmarks.length; i++) {
                var bid = currentBookmarks[i].bookmark_id;
                if (bid !== id) selectedIds[bid] = true;
            }
            updateBatchBar();
            updateAllRowSelectUI();
            return;
        }
        if (selectedIds[id]) delete selectedIds[id];
        else selectedIds[id] = true;
        updateBatchBar();
        updateRowSelectUI(id);
    }

    function toggleSelectAll() {
        if (!editMode) return;
        var checked = document.getElementById('bm-select-all').checked;
        if (checked) {
            selectAllMode = true;
            selectAllTotal = totalBookmarks;
            for (var i = 0; i < currentBookmarks.length; i++) {
                selectedIds[currentBookmarks[i].bookmark_id] = true;
            }
        } else {
            selectAllMode = false;
            selectAllTotal = 0;
            selectedIds = {};
        }
        updateBatchBar();
        updateAllRowSelectUI();
    }

    function getSelectedCount() {
        return Object.keys(selectedIds).length;
    }

    // Click action button = execute immediately (except tag actions which need tag input)
    function batchAction(action) {
        var ids = Object.keys(selectedIds).map(Number);
        if (ids.length === 0) return;

        // Tag actions: show tag input row
        if (action === 'add-tag' || action === 'remove-tag') {
            currentAction = action;
            batchTags = [];
            clearBatchTagChips();
            // Highlight the clicked button (desktop or mobile)
            var btns = document.querySelectorAll('.bm-batch-btn, .bm-batch-menu-item');
            for (var i = 0; i < btns.length; i++) btns[i].classList.remove('bm-batch-btn-active');
            var clickedBtn = event && event.currentTarget;
            if (clickedBtn) clickedBtn.classList.add('bm-batch-btn-active');
            document.getElementById('bm-batch-tag-row').style.display = '';
            initBatchTagInput();
            if (batchTagInput) batchTagInput.focus();
            return;
        }

        // Non-tag actions: execute immediately
        currentAction = action;
        executeBatch();
    }

    // Confirm button for tag actions
    function confirmBatchTag() {
        var tags = batchTagInput ? batchTagInput.getTagList() : [];
        if (tags.length === 0) {
            BSDialog.toast(window.__('bookmark.batch.tag_error'), 'error');
            return;
        }
        batchTags = tags;
        executeBatch();
    }

    // --- Batch tag input ---
    var batchTagInput = null;

    function initBatchTagInput() {
        var container = document.getElementById('bm-batch-tag-container');
        if (!container) return;
        batchTagInput = new TagInput(container, { placeholder: window.__('bookmark.batch.tag_placeholder'), useSheet: true });
    }

    function addBatchTag(name) {
        if (!batchTagInput) return;
        batchTagInput.addTag(name);
        batchTags = batchTagInput.getTagList();
        updateExecuteBtn();
    }

    function removeBatchTag(name) {
        if (!batchTagInput) return;
        batchTagInput.removeTag(name);
        batchTags = batchTagInput.getTagList();
        updateExecuteBtn();
    }

    function clearBatchTagChips() {
        if (batchTagInput) batchTagInput.clear();
        batchTags = [];
    }

    function hideBatchTagDropdown() {
        if (batchTagInput) batchTagInput.hideDropdown();
    }


    // Build current search filter object for batch-by-filter API
    function getSearchFilter() {
        var f = {};
        f.scope = scope;
        var keyword = document.getElementById('bm-search').value.trim();
        if (keyword) f.keyword = keyword;
        if (selectedLabels.length > 0) f.labels = selectedLabels.join(',');
        if (activeParentFilter) f.labels_or = activeParentFilter.children.join(',');
        if (siteFilter) f.site = siteFilter;
        if (advKeyword && !keyword) f.keyword = advKeyword;
        if (advIsPublic) f.is_public = '1';
        if (advIsPinned) f.is_pinned = '1';
        if (advNavVisible) f.nav_visible = '1';
        if (advNoLabel) f.no_label = '1';
        if (advLabels.length > 0 && advLabelLogic === 'or') f.labels_or = advLabels.join(',');
        if (advTimeDays > 0) {
            var days = advTimeDays;
            var st = new Date(Date.now() - days * 86400000);
            f.start_time = st.toISOString().slice(0, 19);
            f.time_field = advTimeField;
        } else if (advTimeDays === -1) {
            if (advStartDate) f.start_time = advStartDate + 'T00:00:00';
            if (advEndDate) f.end_time = advEndDate + 'T23:59:59';
            f.time_field = advTimeField;
        }
        return f;
    }

    async function executeBatch() {
        if (!currentAction || (getSelectedCount() === 0 && !selectAllMode)) return;
        var ids = selectAllMode ? [] : Object.keys(selectedIds).map(Number);
        var filter = selectAllMode ? getSearchFilter() : null;
        var countText = selectAllMode ? selectAllTotal + '' : ids.length + '';

        // Build request payload: use filter in selectAllMode, ids otherwise
        function buildPayload(extra) {
            var p = selectAllMode ? {filter: filter} : {ids: ids};
            if (extra) { for (var k in extra) p[k] = extra[k]; }
            return JSON.stringify(p);
        }

        var url, body;
        if (currentAction === 'delete') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.delete_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-delete';
            body = buildPayload();
        } else if (currentAction === 'share') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.share_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-share';
            body = buildPayload();
        } else if (currentAction === 'unshare') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.unshare_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-unshare';
            body = buildPayload();
        } else if (currentAction === 'pin') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.pin_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-pin';
            body = buildPayload();
        } else if (currentAction === 'unpin') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.unpin_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-unpin';
            body = buildPayload();
        } else if (currentAction === 'show-nav') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.show_nav_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-show-nav';
            body = buildPayload();
        } else if (currentAction === 'hide-nav') {
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.hide_nav_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-hide-nav';
            body = buildPayload();
        } else if (currentAction === 'add-tag') {
            if (batchTags.length === 0) return;
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.add_tag_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-add-labels';
            body = buildPayload({tags: batchTags});
        } else if (currentAction === 'remove-tag') {
            if (batchTags.length === 0) return;
            if (!await BSDialog.confirm2(window.__('bookmark.confirm.remove_tag_count').replace('{n}', countText))) return;
            url = '/api/bookmarks/batch-remove-labels';
            body = buildPayload({tags: batchTags});
        } else {
            return;
        }

        var execBtn = document.getElementById('bm-batch-execute');
        var request = window.BookStarkRequestLock
            ? BookStarkRequestLock.run('bookmarks:batch:' + currentAction, function() {
                return csrfFetch(url, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: body
                });
            }, execBtn)
            : csrfFetch(url, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: body
            });
        if (!request) return;
        request.then(function(r) {
            if (!r.ok) return r.json().then(function(d) { throw new Error(d.message || window.__('bookmark.batch.op_failed')); });
            return r.json();
        }).then(function() {
            var actionMsgs = {
                'delete': window.__('bookmark.batch.result.deleted'), 'share': window.__('bookmark.batch.result.shared'), 'unshare': window.__('bookmark.batch.result.unshared'),
                'pin': window.__('bookmark.batch.result.pinned'), 'unpin': window.__('bookmark.batch.result.unpinned'),
                'show-nav': window.__('bookmark.batch.result.show_nav'), 'hide-nav': window.__('bookmark.batch.result.hide_nav'),
                'add-tag': window.__('bookmark.batch.result.add_tag'), 'remove-tag': window.__('bookmark.batch.result.remove_tag')
            };
            BSDialog.toast(actionMsgs[currentAction] || window.__('bookmark.batch.result.success'), 'success');
            if (selectAllMode) {
                // In selectAllMode, refresh data from server
                selectAllMode = false;
                selectAllTotal = 0;
                selectedIds = {};
                currentAction = null;
                batchTags = [];
                fetchBookmarks(false);
                return;
            }
            if (currentAction === 'delete') {
                currentBookmarks = currentBookmarks.filter(function(x) { return !selectedIds[x.bookmark_id]; });
                totalBookmarks -= ids.length;
                updateBmCount();
                ids.forEach(function(id) {
                    var row = document.querySelector('#bm-list .bm-row[data-id="' + id + '"]');
                    if (row) row.remove();
                });
                if (currentBookmarks.length === 0) renderBookmarkList();
                renderPagination();
            } else if (currentAction === 'share' || currentAction === 'unshare') {
                var isPublic = currentAction === 'share';
                ids.forEach(function(id) {
                    var b = currentBookmarks.find(function(x) { return x.bookmark_id === id; });
                    if (b) {
                        b.is_public = isPublic;
                        var row = document.querySelector('#bm-list .bm-row[data-id="' + id + '"]');
                        if (row) {
                            var tmp = document.createElement('div');
                            tmp.innerHTML = renderSingleRow(b);
                            row.replaceWith(tmp.firstElementChild);
                        }
                    }
                });
            } else if (currentAction === 'pin' || currentAction === 'unpin') {
                var pinned = currentAction === 'pin';
                ids.forEach(function(id) {
                    var b = currentBookmarks.find(function(x) { return x.bookmark_id === id; });
                    if (b) {
                        b.is_pinned = pinned;
                        var row = document.querySelector('#bm-list .bm-row[data-id="' + id + '"]');
                        if (row) {
                            var tmp = document.createElement('div');
                            tmp.innerHTML = renderSingleRow(b);
                            row.replaceWith(tmp.firstElementChild);
                        }
                    }
                });
            } else if (currentAction === 'show-nav' || currentAction === 'hide-nav') {
                var navVis = currentAction === 'show-nav';
                ids.forEach(function(id) {
                    var b = currentBookmarks.find(function(x) { return x.bookmark_id === id; });
                    if (b) {
                        b.nav_visible = navVis;
                        var row = document.querySelector('#bm-list .bm-row[data-id="' + id + '"]');
                        if (row) {
                            var tmp = document.createElement('div');
                            tmp.innerHTML = renderSingleRow(b);
                            row.replaceWith(tmp.firstElementChild);
                        }
                    }
                });
            } else {
                fetchBookmarks(false);
            }
            selectedIds = {};
            currentAction = null;
            batchTags = [];
            updateBatchBar();
            updateAllRowSelectUI();
        }).catch(function(e) {
            BSDialog.toast(e.message || window.__('bookmark.batch.op_failed'), 'error');
        });
    }

    // --- Tag drawer / sidebar ---
    function openTagDrawer() {
        if (isDesktop()) {
            openSidebar();
        } else {
            openMobileDrawer();
        }
    }

    function closeTagDrawer() {
        if (isDesktop()) {
            closeSidebar();
        } else {
            closeMobileDrawer();
        }
    }

    // Desktop sidebar
    function openSidebar() {
        sidebarOpen = true;
        sidebarFilter = '';
        var sidebar = document.getElementById('bm-sidebar');
        var searchInput = document.getElementById('bm-sidebar-search');
        sidebar.classList.add('open');
        if (searchInput) searchInput.value = '';
        renderSidebarTags();
        renderSidebarSelected();
        updateTagBtnState();
        loadAdvLabels();
    }

    function closeSidebar() {
        sidebarOpen = false;
        var sidebar = document.getElementById('bm-sidebar');
        sidebar.classList.remove('open');
        updateTagBtnState();
    }

    function updateTagBtnState() {
        var btn = document.getElementById('bm-tag-btn');
        if (!btn) return;
        if (sidebarOpen) {
            btn.classList.add('bm-tag-btn-active');
        } else {
            btn.classList.remove('bm-tag-btn-active');
        }
    }

    function renderSidebarTags() {
        var filtered = filterLabels(sidebarFilter);
        var tree = buildLabelTree(filtered);
        var html = '';

        if (filtered.length === 0) {
            html = '<div class="bm-sidebar-empty">' + window.__('bookmark.sidebar.no_match') + '</div>';
        } else {
            for (var pi = 0; pi < tree.parents.length; pi++) {
                var parent = tree.parents[pi];
                var prefix = parent.prefix;
                var children = parent.children;
                var expanded = isTreeExpanded(prefix);
                var parentActive = activeParentFilter && activeParentFilter.prefix === prefix;
                var allChildSelected = !parentActive && children.every(function(c) { return selectedLabels.indexOf(c) >= 0; });
                var someChildSelected = !parentActive && children.some(function(c) { return selectedLabels.indexOf(c) >= 0; });
                var groupCls = 'bm-section-group' + (expanded ? ' expanded' : '');
                if (parentActive || allChildSelected) groupCls += ' bm-section-group-selected';
                else if (someChildSelected) groupCls += ' bm-section-group-partial';
                html += '<div class="' + groupCls + '">';
	                html += '<div class="bm-section-header" tabindex="0" role="button" aria-expanded="' + expanded + '" onclick="BM.toggleTreeNode(\'' + escAttr(escJs(prefix)) + '\')" onkeydown="BM.activateOnKey(event, \'tree\', \'' + escAttr(escJs(prefix)) + '\')">';
                html += '<span class="bm-section-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></span>';
                html += '<span class="bm-section-name">' + esc(prefix) + '</span>';
	                html += '<span class="bm-section-select-all" role="button" tabindex="0" onclick="event.stopPropagation();BM.toggleParent(\'' + escAttr(escJs(prefix)) + '\')" onkeydown="BM.activateOnKey(event, \'parent\', \'' + escAttr(escJs(prefix)) + '\')">' + (parentActive || allChildSelected ? window.__('bookmark.sidebar.cancel') : window.__('bookmark.sidebar.select_all')) + '</span>';
                html += '<span class="bm-section-count">' + children.length + '</span>';
                html += '</div>';
                html += '<div class="bm-section-body"><div class="bm-section-children">';
                for (var ci = 0; ci < children.length; ci++) {
                    var child = children[ci];
                    var childLabel = child.substring(prefix.length + 1);
                    var selected = selectedLabels.indexOf(child) >= 0;
	                    html += '<div class="bm-section-child' + (selected ? ' selected' : '') + '" tabindex="0" role="button" aria-pressed="' + (selected ? 'true' : 'false') + '" onclick="BM.toggleLabel(\'' + escAttr(escJs(child)) + '\')" onkeydown="BM.activateOnKey(event, \'label\', \'' + escAttr(escJs(child)) + '\')">';
                    html += '<span class="bm-child-dot"></span>';
                    html += '<span class="bm-child-name">' + esc(childLabel) + '</span>';
                    html += '<span class="bm-child-check"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>';
                    html += '</div>';
                }
                html += '</div></div>';
                html += '</div>';
            }
            if (tree.flat.length > 0) {
                if (tree.parents.length > 0) {
                    html += '<div class="bm-section-flat-divider"></div>';
                }
                html += renderFlatTagsHeader(tree.flat.length);
                html += '<div class="bm-section-flat' + (flatTagsExpanded ? ' expanded' : '') + '">';
                var letterData = groupFlatByLetter(tree.flat);
                for (var li = 0; li < letterData.order.length; li++) {
                    var letter = letterData.order[li];
                    var letterTags = letterData.groups[letter];
                    var letterExp = isFlatLetterExpanded(letter);
                    html += '<div class="bm-letter-group' + (letterExp ? ' expanded' : '') + '">';
                    html += '<div class="bm-letter-header" tabindex="0" role="button" aria-expanded="' + (letterExp ? 'true' : 'false') + '" onclick="BM.toggleFlatLetter(\'' + escAttr(escJs(letter)) + '\')" onkeydown="BM.activateOnKey(event, \'letter\', \'' + escAttr(escJs(letter)) + '\')">';
                    html += '<span class="bm-letter-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></span>';
                    html += '<span class="bm-letter-name">' + esc(letter) + '</span>';
                    html += '<span class="bm-letter-count">' + letterTags.length + '</span>';
                    html += '</div>';
                    html += '<div class="bm-letter-body">';
                    for (var fi = 0; fi < letterTags.length; fi++) {
                        var ftag = letterTags[fi];
                        var fsel = selectedLabels.indexOf(ftag) >= 0;
                        html += '<span class="bm-sidebar-tag ' + (fsel ? 'bm-sidebar-tag-selected' : '') + '" tabindex="0" role="button" aria-pressed="' + (fsel ? 'true' : 'false') + '" onclick="BM.toggleLabel(\'' + escAttr(escJs(ftag)) + '\')" onkeydown="BM.activateOnKey(event, \'label\', \'' + escAttr(escJs(ftag)) + '\')">' + esc(ftag) + '</span>';
                    }
                    html += '</div></div>';
                }
                html += '</div>';
            }
        }
        document.getElementById('bm-sidebar-tags').innerHTML = html;
    }

    function renderSidebarSelected() {
        var el = document.getElementById('bm-sidebar-selected');
        if (selectedLabels.length === 0) {
            el.innerHTML = '<span style="font-size:11px;color:var(--color-gray-300)">' + window.__('bookmark.sidebar.no_selected') + '</span>';
            return;
        }
        var html = '';
        for (var i = 0; i < selectedLabels.length; i++) {
            html += '<span class="bm-chip" tabindex="0" role="button" onclick="BM.toggleLabel(\'' + escAttr(escJs(selectedLabels[i])) + '\')" onkeydown="BM.activateOnKey(event, \'label\', \'' + escAttr(escJs(selectedLabels[i])) + '\')">' + esc(selectedLabels[i]) + ' <span class="bm-chip-x">\u2715</span></span>';
        }
        el.innerHTML = html;
    }

    function filterSidebarTags() {
        var input = document.getElementById('bm-sidebar-search');
        var nextFilter = input ? input.value.trim() : '';
        if (nextFilter !== sidebarFilter) flatLetterSearchExpanded = {};
        sidebarFilter = nextFilter;
        renderSidebarTags();
    }

    function filterLabels(q) {
        if (!q) return allLabels;
        var lower = q.toLowerCase();
        return allLabels.filter(function(l) { return l.toLowerCase().indexOf(lower) >= 0; });
    }

    function clearLabelFilter() {
        selectedLabels = [];
        activeParentFilter = null;
        siteFilter = '';
        localStorage.removeItem(SEARCH_STATE_KEY);
        renderSidebarTags();
        renderSidebarSelected();
        renderSelectedTags();
        fetchBookmarks(false);
    }

    // --- Site search (click favicon to search same-site bookmarks) ---
    function searchByLabel(label) {
        selectedLabels = [label];
        activeParentFilter = null;
        currentPage = 1;
        var searchInput = document.getElementById('bm-search');
        if (searchInput) searchInput.value = '';
        if (isDesktop()) {
            renderSidebarTags();
            renderSidebarSelected();
        } else {
            renderDrawerTags();
        }
        renderSelectedTags();
        fetchBookmarks(false);
    }

    function searchBySite(el) {
        var url = el.getAttribute('data-url') || '';
        if (!url) return;
        try {
            var domain = new URL(url).hostname;
            if (!domain) return;
            siteFilter = domain;
            currentPage = 1;
            updateSearchPlaceholder();
            renderSelectedTags();
            fetchBookmarks(false);
        } catch(e) {}
    }

    function clearSiteFilter() {
        siteFilter = '';
        updateSearchPlaceholder();
        renderSelectedTags();
        fetchBookmarks(false);
    }

    function advTimeFilterActive() {
        return advTimeDays > 0 || (advTimeDays === -1 && (!!advStartDate || !!advEndDate));
    }

    function advTimeFieldLabel() {
        return advTimeField === 'modify' ? window.__('bookmark.adv.time_modify') : window.__('bookmark.adv.time_create');
    }

    function advTimeRangeLabel() {
        if (advTimeDays === 1) return window.__('bookmark.adv.time_1d');
        if (advTimeDays === 7) return window.__('bookmark.adv.time_7d');
        if (advTimeDays === 30) return window.__('bookmark.adv.time_30d');
        if (advTimeDays === -1) {
            if (advStartDate && advEndDate) return advStartDate + ' ~ ' + advEndDate;
            if (advStartDate) return advStartDate + ' ~';
            if (advEndDate) return '~ ' + advEndDate;
        }
        return '';
    }

    function clearAdvTimeFilter() {
        advTimeDays = 0;
        advStartDate = '';
        advEndDate = '';
        renderAdvPanel();
        renderSelectedTags();
        fetchBookmarks(false);
    }

    function updateSearchPlaceholder() {
        var input = document.getElementById('bm-search');
        if (!input) return;
        if (siteFilter) {
            input.placeholder = window.__('bookmark.search_in_site').replace('{domain}', siteFilter);
        } else {
            input.placeholder = window.__('bookmark.search.placeholder');
        }
    }

    // Mobile drawer
    function openMobileDrawer() {
        sidebarOpen = true;
        drawerPreviousFocus = document.activeElement;
        renderDrawerTags();
        var overlay = document.getElementById('bm-drawer-overlay');
        var drawer = document.getElementById('bm-drawer');
        overlay.style.display = '';
        drawer.classList.add('active');
        document.body.style.overflow = 'hidden';
        loadAdvLabels();
        updateTagBtnState();
        setTimeout(function() {
            var focusTarget = drawer.querySelector('.bm-sidebar-close, [tabindex="0"], button, input');
            if (focusTarget) focusTarget.focus();
        }, 50);
    }

    function closeMobileDrawer() {
        sidebarOpen = false;
        document.getElementById('bm-drawer-overlay').style.display = 'none';
        document.getElementById('bm-drawer').classList.remove('active');
        document.body.style.overflow = '';
        updateTagBtnState();
        if (drawerPreviousFocus && typeof drawerPreviousFocus.focus === 'function') {
            try { drawerPreviousFocus.focus(); } catch(e) {}
        }
        drawerPreviousFocus = null;
    }

    function renderDrawerTags() {
        var tree = buildLabelTree(allLabels);
        var html = '';

        for (var pi = 0; pi < tree.parents.length; pi++) {
            var parent = tree.parents[pi];
            var prefix = parent.prefix;
            var children = parent.children;
            var expanded = isTreeExpanded(prefix);
            var parentActive = activeParentFilter && activeParentFilter.prefix === prefix;
            var allChildSelected = !parentActive && children.every(function(c) { return selectedLabels.indexOf(c) >= 0; });
            var someChildSelected = !parentActive && children.some(function(c) { return selectedLabels.indexOf(c) >= 0; });
            var groupCls = 'bm-section-group' + (expanded ? ' expanded' : '');
            if (parentActive || allChildSelected) groupCls += ' bm-section-group-selected';
            else if (someChildSelected) groupCls += ' bm-section-group-partial';
            html += '<div class="' + groupCls + '">';
            html += '<div class="bm-section-header" tabindex="0" role="button" aria-expanded="' + expanded + '" onclick="BM.toggleTreeNode(\'' + escAttr(escJs(prefix)) + '\')" onkeydown="BM.activateOnKey(event, \'tree\', \'' + escAttr(escJs(prefix)) + '\')">';
            html += '<span class="bm-section-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></span>';
            html += '<span class="bm-section-name">' + esc(prefix) + '</span>';
            html += '<span class="bm-section-select-all" role="button" tabindex="0" onclick="event.stopPropagation();BM.toggleParent(\'' + escAttr(escJs(prefix)) + '\')" onkeydown="BM.activateOnKey(event, \'parent\', \'' + escAttr(escJs(prefix)) + '\')">' + (parentActive || allChildSelected ? window.__('bookmark.sidebar.cancel') : window.__('bookmark.sidebar.select_all')) + '</span>';
            html += '<span class="bm-section-count">' + children.length + '</span>';
            html += '</div>';
            html += '<div class="bm-section-body"><div class="bm-section-children">';
            for (var ci = 0; ci < children.length; ci++) {
                var child = children[ci];
                var childLabel = child.substring(prefix.length + 1);
                var selected = selectedLabels.indexOf(child) >= 0;
                html += '<div class="bm-section-child' + (selected ? ' selected' : '') + '" tabindex="0" role="button" aria-pressed="' + (selected ? 'true' : 'false') + '" onclick="BM.toggleLabel(\'' + escAttr(escJs(child)) + '\')" onkeydown="BM.activateOnKey(event, \'label\', \'' + escAttr(escJs(child)) + '\')">';
                html += '<span class="bm-child-dot"></span>';
                html += '<span class="bm-child-name">' + esc(childLabel) + '</span>';
                html += '<span class="bm-child-check"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>';
                html += '</div>';
            }
            html += '</div></div>';
            html += '</div>';
        }
        if (tree.flat.length > 0) {
            if (tree.parents.length > 0) {
                html += '<div class="bm-section-flat-divider"></div>';
            }
            html += renderFlatTagsHeader(tree.flat.length);
            html += '<div class="bm-section-flat' + (flatTagsExpanded ? ' expanded' : '') + '">';
            var letterData = groupFlatByLetter(tree.flat);
            for (var li = 0; li < letterData.order.length; li++) {
                var letter = letterData.order[li];
                var letterTags = letterData.groups[letter];
                var letterExp = isFlatLetterExpanded(letter);
                html += '<div class="bm-letter-group' + (letterExp ? ' expanded' : '') + '">';
                html += '<div class="bm-letter-header" tabindex="0" role="button" aria-expanded="' + (letterExp ? 'true' : 'false') + '" onclick="BM.toggleFlatLetter(\'' + escAttr(escJs(letter)) + '\')" onkeydown="BM.activateOnKey(event, \'letter\', \'' + escAttr(escJs(letter)) + '\')">';
                html += '<span class="bm-letter-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></span>';
                html += '<span class="bm-letter-name">' + esc(letter) + '</span>';
                html += '<span class="bm-letter-count">' + letterTags.length + '</span>';
                html += '</div>';
                html += '<div class="bm-letter-body">';
                for (var fi = 0; fi < letterTags.length; fi++) {
                    var ftag = letterTags[fi];
                    var fsel = selectedLabels.indexOf(ftag) >= 0;
                    html += '<div class="bm-drawer-tag ' + (fsel ? 'bm-drawer-tag-selected' : '') + '" tabindex="0" role="button" aria-pressed="' + (fsel ? 'true' : 'false') + '" onclick="BM.toggleLabel(\'' + escAttr(escJs(ftag)) + '\')" onkeydown="BM.activateOnKey(event, \'label\', \'' + escAttr(escJs(ftag)) + '\')">' + esc(ftag) + '</div>';
                }
                html += '</div></div>';
            }
            html += '</div>';
        }
        document.getElementById('bm-drawer-tags').innerHTML = html;
    }

    function toggleLabel(label) {
        activeParentFilter = null; // 切换单个标签时退出父节点 OR 模式
        var idx = selectedLabels.indexOf(label);
        if (idx >= 0) selectedLabels.splice(idx, 1);
        else selectedLabels.push(label);

        // Update all views
        if (isDesktop()) {
            renderSidebarTags();
            renderSidebarSelected();
        } else {
            renderDrawerTags();
        }
        renderSelectedTags();
        fetchBookmarks(false);
    }

    function removeLabel(label) {
        var idx = selectedLabels.indexOf(label);
        if (idx >= 0) selectedLabels.splice(idx, 1);
        renderSelectedTags();
        if (isDesktop()) {
            renderSidebarTags();
            renderSidebarSelected();
        }
        fetchBookmarks(false);
    }

    function renderSelectedTags() {
        var el = document.getElementById('bm-selected-tags');
        var hasParent = !!activeParentFilter;
        var hasSite = !!siteFilter;
        var hasAdvTime = advTimeFilterActive();
        if (selectedLabels.length === 0 && !hasParent && !hasSite && !hasAdvTime) {
            el.style.display = 'none';
            el.innerHTML = '';
            return;
        }
        el.style.display = '';
        var html = '';
        if (hasSite) {
            html += '<span class="bm-chip bm-chip-site" onclick="BM.clearSiteFilter()"><i class="fa-solid fa-globe" style="font-size:10px;margin-right:2px"></i>' + esc(siteFilter) + ' <span class="bm-chip-x">\u2715</span></span>';
        }
        if (hasParent) {
            html += '<span class="bm-chip bm-chip-parent" onclick="BM.toggleParent(\'' + escAttr(escJs(activeParentFilter.prefix)) + '\')">' + esc(activeParentFilter.prefix) + '/ <span class="bm-chip-x">\u2715</span></span>';
        }
        if (hasAdvTime) {
            html += '<span class="bm-chip bm-chip-time" onclick="BM.clearAdvTimeFilter()"><i class="fa-regular fa-clock" style="font-size:10px;margin-right:2px"></i>' + esc(advTimeFieldLabel() + ': ' + advTimeRangeLabel()) + ' <span class="bm-chip-x">\u2715</span></span>';
        }
        for (var i = 0; i < selectedLabels.length; i++) {
            html += '<span class="bm-chip" onclick="BM.removeLabel(\'' + escAttr(escJs(selectedLabels[i])) + '\')">' + esc(selectedLabels[i]) + ' <span class="bm-chip-x">\u2715</span></span>';
        }
        el.innerHTML = html;
    }

    function renderDrawerSelected() {
        var el = document.getElementById('bm-drawer-selected');
        if (selectedLabels.length === 0) { el.innerHTML = '<span class="text-slate-400 text-xs">' + window.__('bookmark.sidebar.no_selected') + '</span>'; return; }
        var html = '';
        for (var i = 0; i < selectedLabels.length; i++) {
            html += '<span class="bm-chip" onclick="BM.toggleLabel(\'' + escAttr(escJs(selectedLabels[i])) + '\')">' + esc(selectedLabels[i]) + ' \u2715</span>';
        }
        el.innerHTML = html;
    }

    function scrollToLetter(letter) {
        var el = document.getElementById('bm-letter-' + letter);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    // --- Panel tab switching ---
    function switchPanelTab(tab, opts) {
        opts = opts || {};
        if (opts.updateUrl !== false && window.BookStarkTabURL) window.BookStarkTabURL.set('panel', tab);
        document.querySelectorAll('.bm-panel-tab').forEach(function(t, i) {
            t.classList.toggle('active', (tab === 'tags' && i % 2 === 0) || (tab === 'adv' && i % 2 === 1));
        });
        var tagsPanel = document.getElementById('bm-panel-tags');
        var advPanel = document.getElementById('bm-panel-adv');
        if (tagsPanel) tagsPanel.classList.toggle('active', tab === 'tags');
        if (advPanel) advPanel.classList.toggle('active', tab === 'adv');
        var drawerTags = document.getElementById('bm-drawer-panel-tags');
        var drawerAdv = document.getElementById('bm-drawer-panel-adv');
        if (drawerTags) drawerTags.classList.toggle('active', tab === 'tags');
        if (drawerAdv) drawerAdv.classList.toggle('active', tab === 'adv');
        if (tab === 'adv') renderAdvPanel();
    }

    // --- Adv labels loading ---
    function loadAdvLabels() {
        fetch('/api/bookmark-labels?scope=' + scope)
            .then(function(r) { return r.json(); })
            .then(function(res) {
                advLabelsCache = (res.data || []).map(function(name) { return { name: name, count: 0 }; });
            });
    }

    // --- Advanced search: render panel HTML ---
    function advPanelHTML() {
        var isAnd = advLabelLogic === 'and';
        var timeBtns = [{d:1,l:window.__('bookmark.adv.time_1d')},{d:7,l:window.__('bookmark.adv.time_7d')},{d:30,l:window.__('bookmark.adv.time_30d')},{d:-1,l:window.__('bookmark.adv.time_custom')}];
        var timeHtml = '';
        for (var t = 0; t < timeBtns.length; t++) {
            timeHtml += '<span class="bm-adv-time-btn' + (advTimeDays === timeBtns[t].d ? ' active' : '') + '" onclick="BM.selectAdvTime(this,' + timeBtns[t].d + ')">' + timeBtns[t].l + '</span>';
        }
        return '<div class="bm-adv-body">'
            + '<div class="bm-adv-group"><div class="bm-adv-label"><i class="fa-solid fa-magnifying-glass"></i> ' + window.__('bookmark.adv.content_search') + '</div>'
            + '<input type="text" class="bm-adv-keyword-input" value="' + escAttr(advKeyword) + '" placeholder="' + window.__('bookmark.adv.content_placeholder') + '" oninput="BM.onAdvKeywordInput(this)"></div>'
            + '<div class="bm-adv-group"><div class="bm-adv-label"><i class="fa-solid fa-tags"></i> ' + window.__('bookmark.adv.tag_filter') + '</div>'
            + '<div class="bm-adv-logic-toggle"><span class="bm-adv-logic-btn' + (isAnd ? ' active' : '') + '" onclick="BM.setAdvLogic(\'and\')">AND</span><span class="bm-adv-logic-btn' + (!isAnd ? ' active' : '') + '" onclick="BM.setAdvLogic(\'or\')">OR</span></div>'
            + '<div class="bm-adv-tag-container"></div></div>'
            + '<div class="bm-adv-group"><div class="bm-adv-label"><i class="fa-regular fa-clock"></i> <span class="bm-adv-time-field-toggle"><span class="bm-adv-time-field-btn' + (advTimeField === 'create' ? ' active' : '') + '" onclick="BM.setAdvTimeField(\'create\')">' + window.__('bookmark.adv.time_create') + '</span><span class="bm-adv-time-field-btn' + (advTimeField === 'modify' ? ' active' : '') + '" onclick="BM.setAdvTimeField(\'modify\')">' + window.__('bookmark.adv.time_modify') + '</span></span></div>'
            + '<div class="bm-adv-time-presets">' + timeHtml + '</div>'
            + '<div class="bm-adv-time-custom' + (advTimeDays === -1 ? ' visible' : '') + '">'
            + '<div class="bm-adv-date-row"><span class="bm-adv-date-label">' + window.__('bookmark.adv.date_start') + '</span><input type="date" class="bm-adv-date-input" value="' + escAttr(advStartDate) + '" onchange="BM.onAdvStartDate(this)"></div>'
            + '<div class="bm-adv-date-row"><span class="bm-adv-date-label">' + window.__('bookmark.adv.date_end') + '</span><input type="date" class="bm-adv-date-input" value="' + escAttr(advEndDate) + '" onchange="BM.onAdvEndDate(this)"></div>'
            + '</div></div>'
            + '<div class="bm-adv-group"><div class="bm-adv-switches">'
            + '<div class="bm-adv-switch"><span class="bm-adv-switch-text">' + window.__('bookmark.adv.switch_pinned') + '</span><label class="bm-adv-toggle"><input type="checkbox"' + (advIsPinned ? ' checked' : '') + ' onchange="BM.onAdvPinnedToggle(this)"><div class="bm-adv-toggle-track"></div><div class="bm-adv-toggle-thumb"></div></label></div>'
            + '<div class="bm-adv-switch"><span class="bm-adv-switch-text">' + window.__('bookmark.adv.switch_nav') + '</span><label class="bm-adv-toggle"><input type="checkbox"' + (advNavVisible ? ' checked' : '') + ' onchange="BM.onAdvNavVisibleToggle(this)"><div class="bm-adv-toggle-track"></div><div class="bm-adv-toggle-thumb"></div></label></div>'
            + '<div class="bm-adv-switch"><span class="bm-adv-switch-text">' + window.__('bookmark.adv.switch_public') + '</span><label class="bm-adv-toggle"><input type="checkbox"' + (advIsPublic ? ' checked' : '') + ' onchange="BM.onAdvPublicToggle(this)"><div class="bm-adv-toggle-track"></div><div class="bm-adv-toggle-thumb"></div></label></div>'
            + '<div class="bm-adv-switch"><span class="bm-adv-switch-text">' + window.__('bookmark.adv.switch_no_label') + '</span><label class="bm-adv-toggle"><input type="checkbox"' + (advNoLabel ? ' checked' : '') + ' onchange="BM.onAdvNoLabelToggle(this)"><div class="bm-adv-toggle-track"></div><div class="bm-adv-toggle-thumb"></div></label></div>'
            + '</div></div>'
            + '<div class="bm-adv-actions"><button class="bm-adv-btn-search" onclick="BM.executeAdvSearch()"><i class="fa-solid fa-magnifying-glass"></i> ' + window.__('bookmark.adv.search') + '</button><button class="bm-adv-btn-reset" onclick="BM.resetAdvSearch()"><i class="fa-solid fa-rotate-left"></i> ' + window.__('bookmark.adv.reset') + '</button></div></div>';
    }

    function renderAdvPanel() {
        var html = advPanelHTML();
        [document.getElementById('bm-panel-adv'), document.getElementById('bm-drawer-panel-adv')].forEach(function(el) { if (el) el.innerHTML = html; });
        // Init TagInput for advanced search panels
        initAdvTagInputs();
    }

    var advTagInputs = [];
    function initAdvTagInputs() {
        advTagInputs = [];
        ['bm-panel-adv', 'bm-drawer-panel-adv'].forEach(function(panelId) {
            var panel = document.getElementById(panelId);
            if (!panel) return;
            var container = panel.querySelector('.bm-adv-tag-container');
            if (!container) return;
            var ti = new TagInput(container, { placeholder: window.__('bookmark.adv.tag_search'), useSheet: true });
            // Restore existing advLabels
            ti.setTags(advLabels);
            // Sync back on changes
            ti.onTagChange = function() {
                advLabels = ti.getTagList();
            };
            advTagInputs.push(ti);
        });
    }

    // --- Adv tag functions (delegated to TagInput) ---
    function addAdvLabel(name) {
        if (advLabels.indexOf(name) >= 0) return;
        advLabels.push(name);
        advTagInputs.forEach(function(ti) { ti.addTag(name); });
    }

    function removeAdvLabel(name) {
        var idx = advLabels.indexOf(name);
        if (idx >= 0) advLabels.splice(idx, 1);
        advTagInputs.forEach(function(ti) { ti.removeTag(name); });
    }

    function setAdvLogic(logic) {
        advLabelLogic = logic;
        // Update logic toggle buttons without full re-render
        document.querySelectorAll('.bm-adv-logic-btn').forEach(function(btn) {
            var isAndBtn = btn.textContent.trim() === 'AND';
            btn.classList.toggle('active', isAndBtn ? logic === 'and' : logic !== 'and');
        });
    }

    function onAdvKeywordInput(el) { advKeyword = el.value.trim(); }
    function onAdvPublicToggle(el) { advIsPublic = el.checked; applyAdvSearch(false); }
    function onAdvPinnedToggle(el) { advIsPinned = el.checked; applyAdvSearch(false); }
    function onAdvNavVisibleToggle(el) { advNavVisible = el.checked; applyAdvSearch(false); }
    function onAdvNoLabelToggle(el) { advNoLabel = el.checked; applyAdvSearch(false); }
    function onAdvStartDate(el) { advStartDate = el.value; applyAdvSearch(false); }
    function onAdvEndDate(el) { advEndDate = el.value; applyAdvSearch(false); }

    function selectAdvTime(el, days) {
        advTimeDays = days;
        // Update time button active states in the same panel as the clicked button
        var panel = el ? el.closest('.bm-adv-body') : null;
        if (panel) {
            panel.querySelectorAll('.bm-adv-time-btn').forEach(function(btn) {
                btn.classList.remove('active');
            });
            el.classList.add('active');
            var customEl = panel.querySelector('.bm-adv-time-custom');
            if (customEl) customEl.classList.toggle('visible', days === -1);
        }
        applyAdvSearch(false);
    }

    function setAdvTimeField(field) {
        advTimeField = field;
        // Update time field toggle buttons in all panels
        document.querySelectorAll('.bm-adv-time-field-btn').forEach(function(btn) {
            var isCreate = btn.textContent.trim() === window.__('bookmark.adv.time_create');
            btn.classList.toggle('active', isCreate ? field === 'create' : field === 'modify');
        });
        if (advTimeDays !== 0) applyAdvSearch(false);
    }

    // Apply adv search conditions and fetch bookmarks
    function applyAdvSearch(closeDrawer) {
        if (advLabelLogic === 'and') {
            selectedLabels = advLabels.slice();
        } else {
            selectedLabels = [];
        }
                renderSelectedTags();
        if (isDesktop()) { renderSidebarTags(); renderSidebarSelected(); }
        if (closeDrawer) closeTagDrawer();
        fetchBookmarks(false);
    }

    function executeAdvSearch() {
        var kwInput = document.querySelector('.bm-adv-keyword-input');
        if (kwInput) advKeyword = kwInput.value.trim();
        applyAdvSearch(false);
    }

    function resetAdvSearch() {
        advLabels = [];
        advLabelLogic = 'and';
        advTimeDays = 0;
        advTimeField = 'create';
        advStartDate = '';
        advEndDate = '';
        advIsPublic = false;
        advIsPinned = false;
        advNavVisible = false;
        advNoLabel = false;
        advKeyword = '';
        siteFilter = '';
        localStorage.removeItem(SEARCH_STATE_KEY);
        renderAdvPanel();
        applyAdvSearch(false);
    }

    // --- Bookmark list ---
    function closeSwipeRows(exceptRow) {
        var rows = document.querySelectorAll('#bm-list .bm-row-swipe-open, #bm-list .bm-row-swiping');
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] === exceptRow) continue;
            rows[i].classList.remove('bm-row-swipe-open', 'bm-row-swiping');
            rows[i].style.removeProperty('--bm-swipe-x');
            rows[i].style.removeProperty('--bm-swipe-width');
        }
    }

    function getRowSwipeWidth(row) {
        if (!row) return 96;
        var actions = row.querySelector('.bm-row-swipe-actions');
        return actions ? Math.max(96, Math.round(actions.getBoundingClientRect().width)) : 96;
    }

    function initSwipeActions() {
        var list = document.getElementById('bm-list');
        if (!list || list.getAttribute('data-swipe-bound') === '1') return;
        list.setAttribute('data-swipe-bound', '1');

        var state = null;
        function isMobileSwipe() {
            return window.innerWidth <= 640 && isLoggedIn && !editMode;
        }

        list.addEventListener('touchstart', function(e) {
            if (!isMobileSwipe() || e.touches.length !== 1) return;
            if (e.target.closest('.bm-row-swipe-actions') || e.target.closest('.bm-row-actions') || e.target.closest('.bm-row-checkbox')) return;
            var row = e.target.closest('.bm-row');
            if (!row) return;
            var t = e.touches[0];
            state = {
                row: row,
                startX: t.clientX,
                startY: t.clientY,
                lastX: t.clientX,
                dragging: false,
                wasOpen: row.classList.contains('bm-row-swipe-open'),
                actionWidth: getRowSwipeWidth(row)
            };
            row.style.setProperty('--bm-swipe-width', state.actionWidth + 'px');
        }, { passive: true });

        list.addEventListener('touchmove', function(e) {
            if (!state || e.touches.length !== 1) return;
            var t = e.touches[0];
            var dx = t.clientX - state.startX;
            var dy = t.clientY - state.startY;
            state.lastX = t.clientX;
            if (!state.dragging) {
                if (Math.abs(dx) < 8) return;
                if (Math.abs(dx) <= Math.abs(dy) * 1.15) {
                    state = null;
                    return;
                }
                state.dragging = true;
                closeSwipeRows(state.row);
                state.row.classList.add('bm-row-swiping');
            }
            var base = state.wasOpen ? -state.actionWidth : 0;
            var x = Math.max(-state.actionWidth, Math.min(0, base + dx));
            state.row.style.setProperty('--bm-swipe-x', x + 'px');
            if (e.cancelable) e.preventDefault();
        }, { passive: false });

        function finishSwipe() {
            if (!state) return;
            var dx = state.lastX - state.startX;
            var shouldOpen = state.wasOpen ? dx > 36 ? false : true : dx < -36;
            state.row.classList.remove('bm-row-swiping');
            state.row.style.removeProperty('--bm-swipe-x');
            state.row.style.setProperty('--bm-swipe-width', state.actionWidth + 'px');
            state.row.classList.toggle('bm-row-swipe-open', shouldOpen);
            state = null;
        }

        list.addEventListener('touchend', finishSwipe, { passive: true });
        list.addEventListener('touchcancel', function() {
            if (!state) return;
            state.row.classList.remove('bm-row-swiping');
            state.row.style.removeProperty('--bm-swipe-x');
            state = null;
        }, { passive: true });

        list.addEventListener('click', function(e) {
            var openRow = list.querySelector('.bm-row-swipe-open');
            if (!openRow) return;
            if (e.target.closest('.bm-row-swipe-actions')) return;
            if (openRow.contains(e.target)) {
                e.preventDefault();
                e.stopPropagation();
            }
            closeSwipeRows();
        }, true);
    }

    function replaceBookmarkRow(b) {
        var row = document.querySelector('#bm-list .bm-row[data-id="' + b.bookmark_id + '"]');
        if (!row) return;
        var tmp = document.createElement('div');
        tmp.innerHTML = renderSingleRow(b);
        row.replaceWith(tmp.firstElementChild);
    }

    function withRowActionLock(key, fn) {
        if (rowActionLocks[key]) return;
        rowActionLocks[key] = true;
        Promise.resolve().then(fn).finally(function() {
            delete rowActionLocks[key];
        });
    }

    function updateBookmarkFlag(bid, opts) {
        withRowActionLock(opts.lockKey + ':' + bid, function() {
            var b = currentBookmarks.find(function(x) { return x.bookmark_id === bid; });
            if (!b) return Promise.resolve();
            closeSwipeRows();
            return csrfFetch(opts.url, {
                method: opts.method || 'PATCH',
                headers: opts.body ? {'Content-Type': 'application/json'} : undefined,
                body: opts.body ? JSON.stringify(opts.body) : undefined
            }).then(function(r) {
                if (!r.ok) return r.json().then(function(d) { throw new Error(d.message || window.__('bookmark.toast.update_failed')); });
                return r.json();
            }).then(function(res) {
                opts.apply(b, res);
                replaceBookmarkRow(b);
                if (opts.success) BSDialog.toast(opts.success, 'success');
            }).catch(function(e) {
                BSDialog.toast(e.message || window.__('bookmark.toast.network_error'), 'error');
            });
        });
    }

    function toggleBookmarkPin(bid) {
        updateBookmarkFlag(bid, {
            lockKey: 'pin',
            url: '/api/bookmarks/' + bid + '/pin',
            apply: function(b, res) {
                var data = res.data || res;
                b.is_pinned = typeof data.is_pinned === 'boolean' ? data.is_pinned : !b.is_pinned;
            },
            success: window.__('bookmark.toast.updated')
        });
    }

    function setBookmarkNavVisible(bid, visible) {
        updateBookmarkFlag(bid, {
            lockKey: 'nav',
            url: '/api/bookmarks/' + bid + '/nav-visible',
            body: {nav_visible: visible},
            apply: function(b) { b.nav_visible = visible; },
            success: visible ? window.__('bookmark.batch.result.show_nav') : window.__('bookmark.batch.result.hide_nav')
        });
    }

    function setBookmarkPublic(bid, isPublic) {
        updateBookmarkFlag(bid, {
            lockKey: 'public',
            url: '/api/bookmarks/' + bid + '/public',
            body: {is_public: isPublic},
            apply: function(b) { b.is_public = isPublic; },
            success: isPublic ? window.__('bookmark.batch.result.shared') : window.__('bookmark.batch.result.unshared')
        });
    }

    function renderSingleRow(b) {
        var sel = !!selectedIds[b.bookmark_id];
        var pinnedClass = b.is_pinned ? ' is-pinned' : '';
        var rowAttrs = editMode ? ' tabindex="0" role="button" aria-pressed="' + (sel ? 'true' : 'false') + '" onkeydown="BM.onRowKey(event,' + b.bookmark_id + ')"' : '';
        var html = '<div class="bm-row' + (sel ? ' bm-row-selected' : '') + pinnedClass + '" data-id="' + b.bookmark_id + '"' + rowAttrs + ' onclick="BM.onRowClick(event,' + b.bookmark_id + ')">';
        if (isLoggedIn) {
            html += '<div class="bm-row-swipe-actions">';
            html += '<button type="button" onclick="event.stopPropagation();BM.editBookmark(' + b.bookmark_id + ')" class="bm-row-swipe-action" title="' + window.__('bookmark.edit') + '" aria-label="' + window.__('bookmark.edit') + '"><i class="fa-solid fa-pen"></i></button>';
            if (isAdmin) {
                html += '<button type="button" onclick="event.stopPropagation();BM.toggleBookmarkPin(' + b.bookmark_id + ')" class="bm-row-swipe-action pin' + (b.is_pinned ? ' off' : '') + '" title="' + (b.is_pinned ? window.__('bookmark.batch.unpin') : window.__('bookmark.batch.pin')) + '" aria-label="' + (b.is_pinned ? window.__('bookmark.batch.unpin') : window.__('bookmark.batch.pin')) + '"><i class="fa-solid fa-thumbtack"></i></button>';
            }
            html += '<button type="button" onclick="event.stopPropagation();BM.setBookmarkNavVisible(' + b.bookmark_id + ',' + (!b.nav_visible) + ')" class="bm-row-swipe-action nav' + (b.nav_visible ? ' off' : '') + '" title="' + (b.nav_visible ? window.__('bookmark.batch.hide_nav') : window.__('bookmark.batch.show_nav')) + '" aria-label="' + (b.nav_visible ? window.__('bookmark.batch.hide_nav') : window.__('bookmark.batch.show_nav')) + '"><i class="fa-solid ' + (b.nav_visible ? 'fa-eye-slash' : 'fa-eye') + '"></i></button>';
            html += '<button type="button" onclick="event.stopPropagation();BM.setBookmarkPublic(' + b.bookmark_id + ',' + (!b.is_public) + ')" class="bm-row-swipe-action share' + (b.is_public ? ' off' : '') + '" title="' + (b.is_public ? window.__('bookmark.batch.unshare') : window.__('bookmark.batch.share')) + '" aria-label="' + (b.is_public ? window.__('bookmark.batch.unshare') : window.__('bookmark.batch.share')) + '"><i class="fa-solid ' + (b.is_public ? 'fa-rotate-left' : 'fa-share-nodes') + '"></i></button>';
            html += '<button type="button" onclick="event.stopPropagation();BM.deleteBookmark(' + b.bookmark_id + ')" class="bm-row-swipe-action danger" title="' + window.__('bookmark.batch.delete') + '" aria-label="' + window.__('bookmark.batch.delete') + '"><i class="fa-solid fa-trash-can"></i></button>';
            html += '</div>';
        }
        html += '<div class="bm-row-content">';
        html += '<input type="checkbox" class="bm-row-checkbox" data-id="' + b.bookmark_id + '"' + (sel ? ' checked' : '') + ' onclick="event.stopPropagation();BM.toggleSelect(' + b.bookmark_id + ')">';
        html += '<div class="bm-row-body">';
        html += '<div class="bm-row-top">';
        var faviconHtml = b.favicon
            ? '<img src="' + escAttr(faviconProxyUrl(b.favicon)) + '" class="bm-row-favicon bm-site-icon" loading="lazy" data-id="' + b.bookmark_id + '" data-title="' + escAttr(b.title || '') + '" data-url="' + escAttr(b.url || '') + '" onclick="event.preventDefault();event.stopPropagation();BM.searchBySite(this)" onkeydown="BM.activateOnKey(event, \'site\', \'\')" tabindex="0" role="button" aria-label="' + window.__('bookmark.favicon_search') + '" title="' + window.__('bookmark.favicon_search') + '">'
            : (function() { var fb = faviconFallback(b.title || '', b.url || ''); return fb.replace('bm-favicon-fallback"', 'bm-favicon-fallback bm-site-icon" data-id="' + b.bookmark_id + '" data-url="' + escAttr(b.url || '') + '" onclick="event.preventDefault();event.stopPropagation();BM.searchBySite(this)" onkeydown="BM.activateOnKey(event, \'site\', \'\')" tabindex="0" role="button" aria-label="' + window.__('bookmark.favicon_search') + '" title="' + window.__('bookmark.favicon_search') + '"'); })();
        var dotHtml = b.is_public ? ' <span class="bm-shared-dot" title="' + window.__('bookmark.badge.shared') + '">●</span>' : '';
        var pinBadge = b.is_pinned ? '<span class="bm-pin-badge">' + window.__('bookmark.badge.pin') + '</span>' : '';
        if (editMode) {
            html += '<span class="bm-row-title">' + faviconHtml + esc(b.title) + dotHtml + pinBadge + '</span>';
        } else {
            html += '<a href="' + escAttr(b.url || '#') + '" target="_blank" rel="noopener" class="bm-row-title" onclick="event.stopPropagation()">' + faviconHtml + esc(b.title) + dotHtml + pinBadge + '</a>';
        }
        html += '</div>';
        if (b.description || (b.labels && b.labels.length > 0) || isLoggedIn) {
            html += '<div class="bm-row-second">';
            if (b.description) {
                html += '<span class="bm-row-desc">' + esc(b.description) + '</span>';
            }
            if ((b.labels && b.labels.length > 0) || isLoggedIn) {
                html += '<div class="bm-row-label-line">';
                html += '<span class="bm-row-labels">';
                if (b.labels && b.labels.length > 0) {
                    for (var li = 0; li < b.labels.length; li++) {
                        html += '<span class="bm-label-badge" tabindex="0" role="button" onclick="event.stopPropagation();BM.searchByLabel(\'' + escAttr(b.labels[li]).replace(/'/g, "\\'") + '\')" onkeydown="BM.activateOnKey(event, \'searchLabel\', \'' + escAttr(escJs(b.labels[li])) + '\')">' + esc(b.labels[li]) + '</span>';
                    }
                }
                html += '</span>';
                if (isLoggedIn) {
                    html += '<div class="bm-row-actions">';
                    html += '<button onclick="event.stopPropagation();BM.editBookmark(' + b.bookmark_id + ')" class="bm-row-action" title="' + window.__('bookmark.edit') + '" aria-label="' + window.__('bookmark.edit') + '"><i class="fa-solid fa-pen"></i></button>';
                    html += '</div>';
                }
                html += '</div>';
            }
            html += '</div>';
        }
        html += '</div>';
        html += '</div>';
        html += '</div>';
        return html;
    }

    function renderBookmarkList() {
        var html = '';
        if (currentBookmarks.length === 0) {
            html = '<div class="bm-empty"><p class="text-base mb-1">' + window.__('bookmark.empty.state') + '</p><p class="text-sm">' + window.__('bookmark.empty.hint') + '</p></div>';
        } else {
            for (var i = 0; i < currentBookmarks.length; i++) {
                html += renderSingleRow(currentBookmarks[i]);
            }
        }
        document.getElementById('bm-list').innerHTML = html;
        updateEditModeUI();
        closeSwipeRows();
        setupFaviconTimeouts();
        // Lazy-refresh favicons that are empty or default /favicon.ico
        if (isLoggedIn) {
            for (var i = 0; i < currentBookmarks.length; i++) {
                if (needsFaviconRefresh(currentBookmarks[i].favicon)) {
                    queueFaviconRefresh(currentBookmarks[i].bookmark_id, currentBookmarks[i].url);
                }
            }
        }
    }

    function onRowClick(e, id) {
        if (!editMode) return;
        // Don't toggle if clicking on action buttons
        if (e.target.closest('.bm-row-actions') || e.target.closest('.bm-row-checkbox')) return;
        toggleSelect(id);
        updateBatchBar();
        updateRowSelectUI(id);
    }

    function onRowKey(e, id) {
        if (!editMode || !e || (e.key !== 'Enter' && e.key !== ' ')) return;
        if (e.target.closest('.bm-row-actions') || e.target.closest('.bm-row-checkbox')) return;
        e.preventDefault();
        onRowClick(e, id);
    }

    // Lightweight UI updates (no DOM rebuild)
    function updateBatchUI() {
        var listEl = document.getElementById('bm-list');
        if (!listEl) return;
        // Clear selection state
        var rows = listEl.querySelectorAll('.bm-row');
        for (var j = 0; j < rows.length; j++) {
            rows[j].classList.remove('bm-row-selected');
            var cb = rows[j].querySelector('.bm-row-checkbox');
            if (cb) cb.checked = false;
        }
    }

    function updateRowSelectUI(id) {
        var listEl = document.getElementById('bm-list');
        if (!listEl) return;
        var rows = listEl.querySelectorAll('.bm-row');
        for (var i = 0; i < rows.length; i++) {
            var cb = rows[i].querySelector('.bm-row-checkbox');
            if (!cb) continue;
            var rowId = parseInt(cb.getAttribute('data-id') || (cb.getAttribute('onclick').match(/toggleSelect\((\d+)/) || [])[1], 10);
            if (rowId === id) {
                var sel = !!selectedIds[id];
                cb.checked = sel;
                rows[i].classList.toggle('bm-row-selected', sel);
                break;
            }
        }
    }

    function updateAllRowSelectUI() {
        var listEl = document.getElementById('bm-list');
        if (!listEl) return;
        var rows = listEl.querySelectorAll('.bm-row');
        for (var i = 0; i < rows.length; i++) {
            var cb = rows[i].querySelector('.bm-row-checkbox');
            if (!cb) continue;
            var m = cb.getAttribute('data-id') || (cb.getAttribute('onclick').match(/toggleSelect\((\d+)/) || [])[1];
            if (!m) continue;
            var rowId = parseInt(m, 10);
            var sel = !!selectedIds[rowId];
            cb.checked = sel;
            rows[i].classList.toggle('bm-row-selected', sel);
        }
    }

    function openBookmark(e, id) {
        for (var i = 0; i < currentBookmarks.length; i++) {
            if (currentBookmarks[i].bookmark_id === id) {
                window.open(currentBookmarks[i].url, '_blank');
                break;
            }
        }
    }

    // --- CRUD ---
    function showBookmarkDialog(existing) {
        var isEdit = !!existing;
        var title = isEdit ? existing.title : '';
        var url = isEdit ? existing.url : '';
        var desc = isEdit ? existing.description : '';
        var existingLabels = isEdit ? (existing.labels || []) : [];
        var isPublic = isEdit ? existing.is_public : false;
        _dialogFavicon = isEdit ? (existing.favicon || '') : '';

        var html = '<div class="bm-form-group"><label class="bm-form-label" for="bm-b-title">' + window.__('bookmark.dialog.title') + '</label><input id="bm-b-title" class="bm-form-input" value="' + escAttr(title) + '" oninput="document.getElementById(\'bm-b-title-err\').textContent=\'\';this.classList.remove(\'bm-form-input-err\')"><div id="bm-b-title-err" class="bm-form-err"></div></div>'
            + '<div class="bm-form-group"><label class="bm-form-label" for="bm-b-url">' + window.__('bookmark.dialog.url') + '</label><div class="bm-url-row"><input id="bm-b-url" class="bm-form-input" value="' + escAttr(url) + '" placeholder="' + window.__('bookmark.dialog.url_placeholder') + '" oninput="document.getElementById(\'bm-b-url-err\').textContent=\'\';this.classList.remove(\'bm-form-input-err\')"><img id="bm-favicon-preview" class="bm-favicon-preview" style="display:none"></div><div id="bm-b-url-err" class="bm-form-err"></div><span id="bm-meta-status" class="bm-meta-status"></span></div>'
            + '<div class="bm-form-group"><label class="bm-form-label" for="bm-b-desc">' + window.__('bookmark.dialog.desc') + '</label><input id="bm-b-desc" class="bm-form-input" value="' + escAttr(desc) + '"></div>'
            + '<div class="bm-form-group"><label class="bm-form-label">' + window.__('bookmark.dialog.tags') + '</label>'
            + '<div id="bm-tag-container"></div>'
            + '<div class="bm-tag-hint">' + window.__('bookmark.dialog.tag_hint') + '</div>'
            + '</div>'
            + '<div class="bm-form-group"><label class="bm-form-label"><input type="checkbox" id="bm-b-public"' + (isPublic ? ' checked' : '') + '> ' + window.__('bookmark.dialog.public') + '</label></div>';

        showFormDialog(isEdit ? window.__('bookmark.dialog.modal.edit') : window.__('bookmark.dialog.modal.add'), html, async function() {
            // 清除旧错误
            var titleErr = document.getElementById('bm-b-title-err');
            var urlErr = document.getElementById('bm-b-url-err');
            if (titleErr) titleErr.textContent = '';
            if (urlErr) urlErr.textContent = '';
            var titleInput = document.getElementById('bm-b-title');
            var urlInput = document.getElementById('bm-b-url');
            if (titleInput) titleInput.classList.remove('bm-form-input-err');
            if (urlInput) urlInput.classList.remove('bm-form-input-err');

            var t = titleInput ? titleInput.value.trim() : '';
            var u = urlInput ? urlInput.value.trim() : '';
            var hasErr = false;
            if (!t) { if (titleErr) titleErr.textContent = window.__('bookmark.dialog.title_error'); if (titleInput) titleInput.classList.add('bm-form-input-err'); hasErr = true; }
            if (!u) { if (urlErr) urlErr.textContent = window.__('bookmark.dialog.url_error'); if (urlInput) urlInput.classList.add('bm-form-input-err'); hasErr = true; }
            if (hasErr) return false;
            var d = document.getElementById('bm-b-desc').value.trim();
            var l = dialogTagInput ? dialogTagInput.getTags() : '';
            var p = document.getElementById('bm-b-public').checked;
            var body = { title: t, url: u, description: d, labels: l, is_public: p, favicon: _dialogFavicon || '' };
            if (isEdit) {
                var r = await csrfFetch('/api/bookmarks/' + existing.bookmark_id, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) });
                if (r.ok) {
                    existing.title = t;
                    existing.url = u;
                    existing.description = d;
                    existing.labels = l.split(',').filter(function(x) { return x; });
                    existing.is_public = p;
                    var row = document.querySelector('#bm-list .bm-row[data-id="' + existing.bookmark_id + '"]');
                    if (row) {
                        var tmp = document.createElement('div');
                        tmp.innerHTML = renderSingleRow(existing);
                        row.replaceWith(tmp.firstElementChild);
                    }
                    BSDialog.toast(window.__('bookmark.toast.updated'), 'success');
                } else {
                    var err = await r.json();
                    BSDialog.alert2(err.message || window.__('bookmark.toast.update_failed'));
                    return false;
                }
            } else {
                var r = await csrfFetch('/api/bookmarks', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) });
                if (r.ok) {
                    fetchBookmarks(false);
                    BSDialog.toast(window.__('bookmark.toast.added'), 'success');
                } else {
                    var err = await r.json();
                    BSDialog.alert2(err.message || window.__('bookmark.toast.add_failed'));
                    return false;
                }
            }
            return true;
        });

        // Init TagInput for dialog
        var tagContainer = document.getElementById('bm-tag-container');
        if (tagContainer) {
            dialogTagInput = new TagInput(tagContainer, { placeholder: window.__('bookmark.dialog.tag_placeholder'), useSheet: true });
            if (existingLabels && existingLabels.length > 0) {
                dialogTagInput.setTags(existingLabels);
            }
        }

        // URL blur auto-fill
        setTimeout(function() {
            var urlInput = document.getElementById('bm-b-url');
            var _urlFetchTimer = null;
            if (urlInput) {
                urlInput.addEventListener('keydown', function(e) { if (e.key === 'Enter') { e.preventDefault(); urlInput.blur(); } });
                urlInput.addEventListener('blur', function() {
                    var v = urlInput.value.trim();
                    var preview = document.getElementById('bm-favicon-preview');
                    if (_urlFetchTimer) { clearTimeout(_urlFetchTimer); _urlFetchTimer = null; }
                    if (v) {
                        try { var u = new URL(v); preview.src = '/api/favicon?url=' + encodeURIComponent(u.origin + '/favicon.ico'); preview.style.display = 'inline'; (function(el){ var t=setTimeout(function(){el.style.display='none';},FAVICON_TIMEOUT); el.onload=function(){clearTimeout(t);}; el.onerror=function(){clearTimeout(t);el.style.display='none';}; })(preview); } catch(e) { preview.style.display = 'none'; }
                        var titleInput = document.getElementById('bm-b-title');
                        var descInput = document.getElementById('bm-b-desc');
                        var publicInput = document.getElementById('bm-b-public');
                        var statusEl = document.getElementById('bm-meta-status');
                        if (statusEl) { statusEl.textContent = window.__('bookmark.meta.parsing'); statusEl.className = 'bm-meta-status bm-meta-loading'; }
                        // 先查 URL 是否已存在
                        csrfFetch('/api/bookmarks/check/?url=' + encodeURIComponent(v))
                        .then(function(r) { return r.json(); })
                        .then(function(res) {
                            var bm = res.bookmark;
                            var meta = res.metadata || {};
                            if (bm) {
                                // URL 已存在，填充所有字段
                                var fillTitle = bm.title || meta.title;
                                var fillDesc = bm.description || meta.description;
                                if (fillTitle && titleInput) titleInput.value = fillTitle;
                                if (fillDesc && descInput) descInput.value = fillDesc;
                                if (bm.tag_names && bm.tag_names.length > 0) {
                                    if (dialogTagInput) dialogTagInput.setTags(bm.tag_names);
                                }
                                if (publicInput && bm.shared !== undefined) publicInput.checked = bm.shared;
                                // Use existing bookmark's favicon or meta favicon
                                var metaFav = bm.favicon || meta.favicon || '';
                                if (metaFav) { _dialogFavicon = metaFav; try { var fu = new URL(v); preview.src = '/api/favicon?url=' + encodeURIComponent(metaFav); } catch(e) {} }
                                if (statusEl) { statusEl.textContent = window.__('bookmark.meta.filled'); statusEl.className = 'bm-meta-status bm-meta-ok'; }
                            } else {
                                // URL 不存在，走 fetch-meta 解析
                                csrfFetch('/api/fetch-meta', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({url: v}) })
                                .then(function(r2) { return r2.json(); })
                                .then(function(res2) {
                                    var meta = res2.data || res2;
                                    if (res2.code && res2.code !== 0) { if (statusEl) { statusEl.textContent = window.__('bookmark.meta.parse_failed') + ': ' + (res2.message || ''); statusEl.className = 'bm-meta-status bm-meta-error'; } }
                                    else if (meta.error) { if (statusEl) { statusEl.textContent = window.__('bookmark.meta.parse_failed') + ': ' + meta.error; statusEl.className = 'bm-meta-status bm-meta-error'; } }
                                    else {
                                        if (meta.title && titleInput) titleInput.value = meta.title;
                                        if (meta.description && descInput) descInput.value = meta.description;
                                        // Update favicon preview with real favicon from meta
                                        if (meta.favicon) { _dialogFavicon = meta.favicon; try { preview.src = '/api/favicon?url=' + encodeURIComponent(meta.favicon); } catch(e) {} }
                                        if (statusEl) { statusEl.textContent = window.__('bookmark.meta.parse_success'); statusEl.className = 'bm-meta-status bm-meta-ok'; }
                                    }
                                })
                                .catch(function() { if (statusEl) { statusEl.textContent = window.__('bookmark.meta.parse_failed'); statusEl.className = 'bm-meta-status bm-meta-error'; } });
                            }
                        })
                        .catch(function() { if (statusEl) { statusEl.textContent = window.__('bookmark.meta.query_failed'); statusEl.className = 'bm-meta-status bm-meta-error'; } });
                    } else { preview.style.display = 'none'; _dialogFavicon = ''; }
                });
            }
        }, 100);
    }

    function editBookmark(bid) {
        var b = currentBookmarks.find(function(x) { return x.bookmark_id === bid; });
        if (b) showBookmarkDialog(b);
    }

    async function deleteBookmark(bid) {
        var b = currentBookmarks.find(function(x) { return x.bookmark_id === bid; });
        if (!b) return;
        if (!await BSDialog.confirm2(window.__('bookmark.confirm.delete_single').replace('{title}', b.title))) return;
        var row = document.querySelector('#bm-list .bm-row[data-id="' + bid + '"]');
        var btn = row ? row.querySelector('.bm-action-delete, [onclick*="deleteBookmark"]') : null;
        var request = window.BookStarkRequestLock
            ? BookStarkRequestLock.run('bookmarks:delete:' + bid, function() {
                return csrfFetch('/api/bookmarks/' + bid, { method: 'DELETE' });
            }, btn)
            : csrfFetch('/api/bookmarks/' + bid, { method: 'DELETE' });
        if (!request) return;
        request.then(function(r) {
            if (r.ok) {
                currentBookmarks = currentBookmarks.filter(function(x) { return x.bookmark_id !== bid; });
                totalBookmarks--;
                var row = document.querySelector('#bm-list .bm-row[data-id="' + bid + '"]');
                if (row) row.remove();
                updateBmCount();
                if (currentBookmarks.length === 0) renderBookmarkList();
                renderPagination();
                BSDialog.toast(window.__('bookmark.toast.deleted'), 'success');
            } else {
                r.json().then(function(d) { BSDialog.alert2(d.message || window.__('bookmark.toast.delete_failed')); }).catch(function() { BSDialog.alert2(window.__('bookmark.toast.delete_failed')); });
            }
        }).catch(function() { BSDialog.toast(window.__('bookmark.toast.network_error'), 'error'); });
    }

    // --- Pagination (desktop) ---
    function renderPagination() {
        var el = document.getElementById('bm-pagination');
        if (!el) return;
        if (totalBookmarks === 0) {
            el.style.display = 'none';
            return;
        }
        var totalPages = Math.ceil(totalBookmarks / PAGE_SIZE);
        if (totalPages <= 1) {
            el.style.display = 'none';
            return;
        }
        el.style.display = '';

        var html = '';
        // Prev
        html += '<button class="bm-page-btn" onclick="BM.goToPage(' + (currentPage - 1) + ')" aria-label="' + window.__('bookmark.pagination.prev') + '"' + (currentPage <= 1 ? ' disabled' : '') + '><i class="fa-solid fa-chevron-left" style="font-size:11px"></i></button>';

        // Page numbers: show up to 7 pages with ellipsis
        var pages = getPageRange(currentPage, totalPages);
        for (var i = 0; i < pages.length; i++) {
            if (pages[i] === '...') {
                html += '<span class="bm-page-info">...</span>';
            } else {
                html += '<button class="bm-page-btn' + (pages[i] === currentPage ? ' active' : '') + '" onclick="BM.goToPage(' + pages[i] + ')" aria-label="' + window.__('bookmark.pagination.page').replace('{n}', pages[i]) + '"' + (pages[i] === currentPage ? ' aria-current="page"' : '') + '>' + pages[i] + '</button>';
            }
        }

        // Next
        html += '<button class="bm-page-btn" onclick="BM.goToPage(' + (currentPage + 1) + ')" aria-label="' + window.__('bookmark.pagination.next') + '"' + (currentPage >= totalPages ? ' disabled' : '') + '><i class="fa-solid fa-chevron-right" style="font-size:11px"></i></button>';

        // Info
        html += '<span class="bm-page-info">' + window.__('bookmark.pagination.total').replace('{n}', totalBookmarks) + '</span>';

        el.innerHTML = html;
    }

    function getPageRange(current, total) {
        if (total <= 7) {
            var arr = [];
            for (var i = 1; i <= total; i++) arr.push(i);
            return arr;
        }
        if (current <= 3) return [1, 2, 3, 4, '...', total];
        if (current >= total - 2) return [1, '...', total - 3, total - 2, total - 1, total];
        return [1, '...', current - 1, current, current + 1, '...', total];
    }

    function goToPage(page) {
        var totalPages = Math.ceil(totalBookmarks / PAGE_SIZE);
        if (page < 1 || page > totalPages) return;
        fetchBookmarks(false, page);
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    // --- Search ---
    function doSearch() {
        siteFilter = '';
        updateSearchPlaceholder();
        renderSelectedTags();
        fetchBookmarks(false);
    }

    // --- Form dialog (reuse BSDialog) ---
    function showFormDialog(title, bodyHtml, onConfirm) {
        var previousFocus = document.activeElement;
        var overlay = document.getElementById('bs-dialog-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'bs-dialog-overlay';
            overlay.className = 'bs-dialog-overlay';
            overlay.innerHTML = '<div id="bs-dialog-box" class="bs-dialog-box"></div>';
            document.body.appendChild(overlay);
        }
        var box = document.getElementById('bs-dialog-box');
        overlay.classList.add('bs-dialog-form-overlay');
        box.classList.add('bs-dialog-form-box');
        box.innerHTML = '<div class="bs-dialog-title" style="font-weight:600;font-size:15px;margin-bottom:16px">' + esc(title) + '</div>'
            + bodyHtml
            + '<div class="bs-dialog-actions" style="margin-top:20px"><button class="bs-btn bs-btn-cancel" id="bm-form-cancel">' + window.__('bookmark.dialog.cancel') + '</button><button class="bs-btn bs-btn-primary" id="bm-form-ok">' + window.__('bookmark.dialog.confirm') + '</button></div>';
        if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.apply === 'function') window.BookStarkFormGuards.apply(box);
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('bookmark-form');
        function closeFormDialog() {
            overlay.classList.remove('active');
            overlay.classList.remove('bs-dialog-form-overlay');
            box.classList.remove('bs-dialog-form-box');
            if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('bookmark-form');
            if (previousFocus && typeof previousFocus.focus === 'function') {
                try { previousFocus.focus(); } catch(e) {}
            }
        }
        document.getElementById('bm-form-cancel').onclick = closeFormDialog;
        document.getElementById('bm-form-ok').onclick = async function() {
            var result = await onConfirm();
            if (result !== false) closeFormDialog();
        };
        var firstInput = box.querySelector('input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), select:not([disabled])');
        if (firstInput) {
            firstInput.focus();
            if (typeof firstInput.select === 'function') firstInput.select();
            requestAnimationFrame(function() {
                if (document.activeElement !== firstInput) firstInput.focus();
            });
        }
    }

    // --- Tag input component (for bookmark dialog) ---
    // --- Dialog tag input ---
    var dialogTagInput = null;


    // Close tag input dropdowns on outside click
    document.addEventListener('click', function(e) {
        if (!e.target.closest('#bm-batch-tag-container')) hideBatchTagDropdown();
        if (!e.target.closest('#bm-tag-container') && dialogTagInput) dialogTagInput.hideDropdown();
        // Close adv tag input dropdowns
        if (!e.target.closest('.bm-adv-tag-container')) {
            advTagInputs.forEach(function(ti) { ti.hideDropdown(); });
        }
    });

    // Handle viewport resize: close sidebar if switching to mobile
    window.addEventListener('resize', function() {
        if (!isDesktop() && sidebarOpen) {
            closeSidebar();
        }
    });

    // --- Utilities (esc alias for global escHtml; escAttr is global from utils.js) ---
    var esc = escHtml;

    function highlightRow(id) {
        var row = document.querySelector('.bm-row[data-id="' + id + '"]');
        if (row) {
            row.scrollIntoView({ behavior: 'smooth', block: 'center' });
            row.classList.add('bm-row-highlight');
            setTimeout(function() { row.classList.remove('bm-row-highlight'); }, 3000);
        }
        return !!row;
    }

    function fetchAndPrependBookmark(id) {
        return fetch('/api/bookmarks/' + id + '/')
            .then(function(r) { if (!r.ok) throw new Error(); return r.json(); })
            .then(function(data) {
                var b = {
                    bookmark_id: data.id,
                    title: data.title,
                    url: data.url,
                    description: data.description,
                    labels: data.tag_names || [],
                    is_public: data.shared || false,
                    is_pinned: false,
                    nav_visible: false,
                    favicon: '',
                    create_time: data.date_added || ''
                };
                currentBookmarks.unshift(b);
                renderBookmarkList();
                highlightRow(id);
            })
            .catch(function() {});
    }

    // --- Init ---
    function init() {
        initSwipeActions();
        var params = new URLSearchParams(window.location.search);
        var highlightId = params.get('id');
        var labelParam = params.get('label');
        var panelParam = window.BookStarkTabURL ? window.BookStarkTabURL.get('panel', ['tags', 'adv'], '') : '';
        if (panelParam) switchPanelTab(panelParam, { updateUrl: false });

        // 从 localStorage 恢复搜索状态
        var restored = restoreSearchState();

        // URL 参数优先：label 参数覆盖 localStorage 的标签
        if (labelParam) {
            selectedLabels = [labelParam];
            activeParentFilter = null;
        }

        // 恢复后同步 UI
        if (restored || labelParam) {
            if (isDesktop()) {
                renderSidebarTags();
                renderSidebarSelected();
            }
            renderSelectedTags();
            if (siteFilter) updateSearchPlaceholder();
        }

        var initPage = (restored && currentPage > 1) ? currentPage : undefined;
        fetchBookmarks(false, initPage).then(function() {
            // 页码超出范围时回退到第1页
            var totalPages = Math.ceil(totalBookmarks / PAGE_SIZE);
            if (currentPage > 1 && currentPage > totalPages) {
                currentPage = 1;
                fetchBookmarks(false, 1);
            }
            if (highlightId) {
                if (!highlightRow(highlightId)) {
                    fetchAndPrependBookmark(highlightId);
                }
                // Clean URL
                if (window.history.replaceState) {
                    var url = new URL(window.location);
                    url.searchParams.delete('id');
                    window.history.replaceState(null, '', url.toString());
                }
            }
            if (params.get('command') === 'new-bookmark') {
                if (window.history.replaceState) {
                    window.history.replaceState(null, '', '/bookmarks');
                }
                setTimeout(function() { showBookmarkDialog(); }, 120);
            }
        });

        document.getElementById('bm-search').addEventListener('keydown', function(e) {
            if (e.key === 'Enter') { e.preventDefault(); fetchBookmarks(false); }
        });

        // Sidebar tag search with debounce
        var sidebarSearch = document.getElementById('bm-sidebar-search');
        if (sidebarSearch) {
            sidebarSearch.addEventListener('input', debounce(function() {
                filterSidebarTags();
            }, 200));
        }
    }

    // --- Batch dropdowns (mobile group menus) ---
    function toggleBatchDropdown(name) {
        var dd = document.querySelector('.bm-batch-dropdown[data-group="' + name + '"]');
        if (!dd) return;
        if (window.BSActionDropdown) {
            window.BSActionDropdown.toggle(dd);
            return;
        }
        var wasOpen = dd.classList.contains('open');
        closeAllBatchDropdowns();
        if (!wasOpen) {
            dd.classList.add('open');
            var menu = dd.querySelector('.bm-batch-dd-menu');
            if (menu) menu.style.display = '';
            dd.querySelector('.bm-batch-dd-btn').setAttribute('aria-expanded', 'true');
        }
    }

    function closeAllBatchDropdowns() {
        if (window.BSActionDropdown) {
            window.BSActionDropdown.closeAll();
            return;
        }
        var dropdowns = document.querySelectorAll('.bm-batch-dropdown.open');
        for (var i = 0; i < dropdowns.length; i++) {
            dropdowns[i].classList.remove('open');
            var menu = dropdowns[i].querySelector('.bm-batch-dd-menu');
            if (menu) menu.style.display = 'none';
            var btn = dropdowns[i].querySelector('.bm-batch-dd-btn');
            if (btn) btn.setAttribute('aria-expanded', 'false');
        }
    }

    // Close dropdowns on outside click
    document.addEventListener('click', function(e) {
        if (!e.target.closest('.bm-batch-dropdown')) {
            closeAllBatchDropdowns();
        }
    });

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && sidebarOpen && !isDesktop()) {
            closeMobileDrawer();
        }
    });

    // --- Public API ---
    window.BM = {
        openTagDrawer: openTagDrawer,
        closeTagDrawer: closeTagDrawer,
        toggleEditMode: toggleEditMode,
        onRowClick: onRowClick,
        onRowKey: onRowKey,
        activateOnKey: activateOnKey,
        toggleLabel: toggleLabel,
        removeLabel: removeLabel,
        toggleParent: toggleParent,
        toggleTreeNode: toggleTreeNode,
        toggleFlatTags: toggleFlatTags,
        toggleFlatLetter: toggleFlatLetter,
        setAllFlatLettersExpanded: setAllFlatLettersExpanded,
        scrollToLetter: function() {},
        filterSidebarTags: filterSidebarTags,
        clearLabelFilter: clearLabelFilter,
        switchPanelTab: switchPanelTab,
        doSearch: function() { fetchBookmarks(false); },
        faviconFallback: faviconFallback,
        addAdvLabel: addAdvLabel,
        removeAdvLabel: removeAdvLabel,
        setAdvLogic: setAdvLogic,
        selectAdvTime: selectAdvTime,
        setAdvTimeField: setAdvTimeField,
        clearAdvTimeFilter: clearAdvTimeFilter,
        executeAdvSearch: executeAdvSearch,
        resetAdvSearch: resetAdvSearch,
        onAdvKeywordInput: onAdvKeywordInput,
        onAdvPublicToggle: onAdvPublicToggle,
        onAdvPinnedToggle: onAdvPinnedToggle,
        onAdvNavVisibleToggle: onAdvNavVisibleToggle,
        onAdvNoLabelToggle: onAdvNoLabelToggle,
        onAdvStartDate: onAdvStartDate,
        onAdvEndDate: onAdvEndDate,
        toggleBatch: toggleBatch,
        toggleSelect: toggleSelect,
        toggleSelectAll: toggleSelectAll,
        batchAction: batchAction,
        confirmBatchTag: confirmBatchTag,
        executeBatch: executeBatch,
        addBatchTag: addBatchTag,
        removeBatchTag: removeBatchTag,
        toggleBatchDropdown: toggleBatchDropdown,
        closeAllBatchDropdowns: closeAllBatchDropdowns,
        openBookmark: openBookmark,
        showBookmarkDialog: showBookmarkDialog,
        editBookmark: editBookmark,
        deleteBookmark: deleteBookmark,
        toggleBookmarkPin: toggleBookmarkPin,
        setBookmarkNavVisible: setBookmarkNavVisible,
        setBookmarkPublic: setBookmarkPublic,
        searchBySite: searchBySite,
        searchByLabel: searchByLabel,
        clearSiteFilter: clearSiteFilter,
        doSearch: doSearch,
        goToPage: goToPage
    };

    init();
})();
