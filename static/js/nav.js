(function() {
    'use strict';

    var navData = null;
    var isLoggedIn = window.NAV_IS_LOGGED_IN || false;
    var isAdmin = window.NAV_IS_ADMIN || false;
    var rowActionLocks = Object.create(null);
    var esc = typeof escHtml === 'function' ? escHtml : function(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); };
    var escAttr = typeof window.escAttr === 'function' ? window.escAttr : function(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); };

    var VIEW_ICONS = {
        'default': 'fa-table-cells-large',
        'list': 'fa-list',
        'compact': 'fa-table-cells'
    };

    var currentView = (function() {
        try { var v = localStorage.getItem('nav_view') || 'default'; return (v === 'grid') ? 'default' : v; }
        catch(e) { return 'default'; }
    })();

    // Collapsed state persistence
    var collapsedGroups = (function() {
        try { return JSON.parse(localStorage.getItem('nav_collapsed') || '{}'); }
        catch(e) { return {}; }
    })();

    // Active group filter persistence
    var activeGroupFilters = (function() {
        try { return JSON.parse(localStorage.getItem('nav_group_filters') || '[]'); }
        catch(e) { return []; }
    })();

    var searchTimer = null;
    var FAVICON_TIMEOUT = 5000;
    // 记录加载失败的 favicon 的书签 id，切换视图重渲染时直接用 fallback，避免破碎图标
    var _failedFavicons = Object.create(null);

    function faviconProxyUrl(faviconUrl) {
        if (!faviconUrl) return '';
        return '/api/favicon?url=' + encodeURIComponent(faviconUrl);
    }

    function faviconFallback(title, url) {
        var ch = '?';
        var bg = '';
        var hostname = '';
        if (url) {
            try { hostname = new URL(url).hostname; } catch(e) {}
        }
        if (hostname) {
            ch = typeof domainChar === 'function' ? domainChar(hostname) : hostname.charAt(0).toUpperCase();
            bg = typeof domainColor === 'function' ? domainColor(hostname) : 'var(--color-gray-300)';
        } else {
            var t = title || '';
            if (t) {
                var first = t.charAt(0);
                var code = first.charCodeAt(0);
                ch = (code >= 0x4E00 && code <= 0x9FFF) ? first : first.toUpperCase();
            }
            bg = typeof charColor === 'function' ? charColor(t || ch) : 'var(--color-gray-300)';
        }
        return '<span class="nav-card-favicon-fallback" style="background:' + bg + '">' + esc(ch) + '</span>';
    }

    function replaceFaviconWithFallback(img) {
        if (!img || !img.parentNode) return;
        var tmp = document.createElement('span');
        var url = img.getAttribute('data-url') || '';
        if (!url) {
            var card = img.closest('.nav-card');
            if (card) url = card.getAttribute('data-url') || '';
        }
        var id = img.getAttribute('data-id');
        if (id) _failedFavicons[id] = true;
        tmp.innerHTML = faviconFallback(img.getAttribute('data-title') || '', url);
        img.replaceWith(tmp.firstElementChild);
    }

    function setupFaviconTimeouts() {
        var imgs = document.querySelectorAll('img.nav-card-favicon:not([data-ft])');
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

    function findBookmarkById(id) {
        if (!navData) return null;
        id = parseInt(id, 10);
        var lists = [];
        if (navData.pinned) lists.push(navData.pinned);
        if (navData.ungrouped) lists.push(navData.ungrouped);
        if (navData.groups) {
            for (var g = 0; g < navData.groups.length; g++) {
                if (navData.groups[g].bookmarks) lists.push(navData.groups[g].bookmarks);
            }
        }
        for (var i = 0; i < lists.length; i++) {
            for (var j = 0; j < lists[i].length; j++) {
                if (parseInt(lists[i][j].bookmark_id, 10) === id) return lists[i][j];
            }
        }
        return null;
    }

    function closeSwipeCards(exceptCard) {
        var cards = document.querySelectorAll('#nav-content .nav-card-swipe-open, #nav-content .nav-card-swiping');
        for (var i = 0; i < cards.length; i++) {
            if (cards[i] === exceptCard) continue;
            cards[i].classList.remove('nav-card-swipe-open', 'nav-card-swiping');
            cards[i].style.removeProperty('--nav-swipe-x');
            cards[i].style.removeProperty('--nav-swipe-width');
        }
    }

    function getCardSwipeWidth(card) {
        var actions = card ? card.querySelector('.nav-card-swipe-actions') : null;
        return actions ? Math.max(88, Math.round(actions.getBoundingClientRect().width)) : 88;
    }

    function initSwipeActions() {
        var content = document.getElementById('nav-content');
        if (!content || content.getAttribute('data-swipe-bound') === '1') return;
        content.setAttribute('data-swipe-bound', '1');
        var state = null;
        function isMobileSwipe() {
            return window.innerWidth <= 640 && isLoggedIn && isAdmin;
        }
        content.addEventListener('touchstart', function(e) {
            if (!isMobileSwipe() || e.touches.length !== 1) return;
            if (e.target.closest('.nav-card-swipe-actions')) return;
            var card = e.target.closest('.nav-card-manageable');
            if (!card) return;
            var t = e.touches[0];
            state = {
                card: card,
                startX: t.clientX,
                startY: t.clientY,
                lastX: t.clientX,
                dragging: false,
                wasOpen: card.classList.contains('nav-card-swipe-open'),
                actionWidth: getCardSwipeWidth(card)
            };
            card.style.setProperty('--nav-swipe-width', state.actionWidth + 'px');
        }, { passive: true });
        content.addEventListener('touchmove', function(e) {
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
                closeSwipeCards(state.card);
                state.card.classList.add('nav-card-swiping');
            }
            var base = state.wasOpen ? -state.actionWidth : 0;
            var x = Math.max(-state.actionWidth, Math.min(0, base + dx));
            state.card.style.setProperty('--nav-swipe-x', x + 'px');
            if (e.cancelable) e.preventDefault();
        }, { passive: false });
        function finishSwipe() {
            if (!state) return;
            var dx = state.lastX - state.startX;
            var shouldOpen = state.wasOpen ? dx > 32 ? false : true : dx < -32;
            state.card.classList.remove('nav-card-swiping');
            state.card.style.removeProperty('--nav-swipe-x');
            state.card.style.setProperty('--nav-swipe-width', state.actionWidth + 'px');
            state.card.classList.toggle('nav-card-swipe-open', shouldOpen);
            state = null;
        }
        content.addEventListener('touchend', finishSwipe, { passive: true });
        content.addEventListener('touchcancel', function() {
            if (!state) return;
            state.card.classList.remove('nav-card-swiping');
            state.card.style.removeProperty('--nav-swipe-x');
            state = null;
        }, { passive: true });
        content.addEventListener('click', function(e) {
            var openCard = content.querySelector('.nav-card-swipe-open');
            if (!openCard) return;
            if (e.target.closest('.nav-card-swipe-actions')) return;
            if (openCard.contains(e.target)) {
                e.preventDefault();
                e.stopPropagation();
            }
            closeSwipeCards();
        }, true);
    }

    function withActionLock(key, fn) {
        if (rowActionLocks[key]) return;
        rowActionLocks[key] = true;
        Promise.resolve().then(fn).finally(function() {
            delete rowActionLocks[key];
        });
    }

    function toggleNavVisible(id, visible) {
        if (!isAdmin) return;
        withActionLock('nav:' + id, function() {
            closeSwipeCards();
            return csrfFetch('/api/bookmarks/' + id + '/nav-visible', {
                method: 'PATCH',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ nav_visible: visible })
            }).then(function(r) {
                if (!r.ok) return r.json().then(function(d) { throw new Error(d.message || window.__('bookmark.toast.update_failed')); });
                return r.json();
            }).then(function() {
                var msg = visible ? window.__('bookmark.batch.result.show_nav') : window.__('bookmark.batch.result.hide_nav');
                if (window.BSDialog) BSDialog.toast(msg, 'success');
                fetchNavData();
            }).catch(function(e) {
                if (window.BSDialog) BSDialog.toast(e.message || window.__('bookmark.toast.network_error'), 'error');
            });
        });
    }

    function openBookmarkEditSheet(id) {
        var b = findBookmarkById(id);
        if (!b || !isAdmin) return;
        closeSwipeCards();
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
        box.innerHTML = '<div class="bs-dialog-title" style="font-weight:600;font-size:15px;margin-bottom:16px">' + esc(window.__('bookmark.dialog.modal.edit')) + '</div>'
            + '<div class="bm-form-group"><label class="bm-form-label" for="nav-b-title">' + window.__('bookmark.dialog.title') + '</label><input id="nav-b-title" class="bm-form-input" value="' + escAttr(b.title || '') + '"><div id="nav-b-title-err" class="bm-form-err"></div></div>'
            + '<div class="bm-form-group"><label class="bm-form-label" for="nav-b-url">' + window.__('bookmark.dialog.url') + '</label><input id="nav-b-url" class="bm-form-input" value="' + escAttr(b.url || '') + '"><div id="nav-b-url-err" class="bm-form-err"></div></div>'
            + '<div class="bm-form-group"><label class="bm-form-label" for="nav-b-desc">' + window.__('bookmark.dialog.desc') + '</label><input id="nav-b-desc" class="bm-form-input" value="' + escAttr(b.description || '') + '"></div>'
            + '<div class="bm-form-group"><label class="bm-form-label">' + window.__('bookmark.dialog.tags') + '</label><div id="nav-tag-container"></div><div class="bm-tag-hint">' + window.__('bookmark.dialog.tag_hint') + '</div></div>'
            + '<div class="bm-form-group"><label class="bm-form-label"><input type="checkbox" id="nav-b-public"' + (b.is_public ? ' checked' : '') + '> ' + window.__('bookmark.dialog.public') + '</label></div>'
            + '<div class="bs-dialog-actions" style="margin-top:20px"><button class="bs-btn bs-btn-cancel" id="nav-form-cancel">' + window.__('bookmark.dialog.cancel') + '</button><button class="bs-btn bs-btn-primary" id="nav-form-ok">' + window.__('bookmark.dialog.confirm') + '</button></div>';
        if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.apply === 'function') window.BookStarkFormGuards.apply(box);
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('nav-bookmark-form');
        var tagInput = null;
        var tagContainer = document.getElementById('nav-tag-container');
        if (tagContainer && window.TagInput) {
            tagInput = new TagInput(tagContainer, { placeholder: window.__('bookmark.dialog.tag_placeholder'), useSheet: true });
            tagInput.setTags(b.labels || []);
        }
        function close() {
            overlay.classList.remove('active');
            overlay.classList.remove('bs-dialog-form-overlay');
            box.classList.remove('bs-dialog-form-box');
            overlay.onclick = null;
            if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('nav-bookmark-form');
            if (previousFocus && typeof previousFocus.focus === 'function') {
                try { previousFocus.focus(); } catch(e) {}
            }
        }
        document.getElementById('nav-form-cancel').onclick = close;
        overlay.onclick = function(e) {
            if (e.target === overlay && window.innerWidth <= 640) close();
        };
        document.getElementById('nav-form-ok').onclick = function() {
            var titleInput = document.getElementById('nav-b-title');
            var urlInput = document.getElementById('nav-b-url');
            var titleErr = document.getElementById('nav-b-title-err');
            var urlErr = document.getElementById('nav-b-url-err');
            var title = titleInput.value.trim();
            var url = urlInput.value.trim();
            var hasErr = false;
            if (titleErr) titleErr.textContent = '';
            if (urlErr) urlErr.textContent = '';
            if (!title) { if (titleErr) titleErr.textContent = window.__('bookmark.dialog.title_error'); hasErr = true; }
            if (!url) { if (urlErr) urlErr.textContent = window.__('bookmark.dialog.url_error'); hasErr = true; }
            if (hasErr) return;
            var okBtn = document.getElementById('nav-form-ok');
            okBtn.disabled = true;
            csrfFetch('/api/bookmarks/' + id, {
                method: 'PUT',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    title: title,
                    url: url,
                    description: document.getElementById('nav-b-desc').value.trim(),
                    labels: tagInput ? tagInput.getTags() : (b.labels || []).join(','),
                    is_public: document.getElementById('nav-b-public').checked
                })
            }).then(function(r) {
                if (!r.ok) return r.json().then(function(d) { throw new Error(d.message || window.__('bookmark.toast.update_failed')); });
                return r.json();
            }).then(function() {
                close();
                if (window.BSDialog) BSDialog.toast(window.__('bookmark.toast.updated'), 'success');
                fetchNavData();
            }).catch(function(e) {
                okBtn.disabled = false;
                if (window.BSDialog) BSDialog.toast(e.message || window.__('bookmark.toast.network_error'), 'error');
            });
        };
        var firstInput = box.querySelector('input:not([type="hidden"]):not([disabled])');
        if (firstInput) firstInput.focus();
    }

    // Lazy-refresh favicons that are empty or default /favicon.ico
    var _navFaviconQueue = [];
    var _navFaviconRefreshing = false;

    function navNeedsFaviconRefresh(favicon) {
        if (!favicon) return true;
        try { var u = new URL(favicon); return u.pathname === '/favicon.ico'; } catch(e) { return false; }
    }

    function navQueueFaviconRefresh(bookmarkId) {
        if (_navFaviconQueue.some(function(q) { return q === bookmarkId; })) return;
        _navFaviconQueue.push(bookmarkId);
        navProcessFaviconQueue();
    }

    function navProcessFaviconQueue() {
        if (_navFaviconRefreshing || _navFaviconQueue.length === 0) return;
        _navFaviconRefreshing = true;
        var id = _navFaviconQueue.shift();
        csrfFetch('/api/bookmarks/' + id + '/favicon', { method: 'PATCH', headers: {'Content-Type': 'application/json'} })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            var data = res.data || res;
            if (data && data.updated && data.favicon) {
                // 拿到新 favicon，清掉失败标记，切换视图时允许重新加载
                if (_failedFavicons[id]) delete _failedFavicons[id];
                // Update in-memory data
                var found = false;
                if (navData && navData.groups) {
                    for (var g = 0; g < navData.groups.length && !found; g++) {
                        var items = navData.groups[g].bookmarks || [];
                        for (var b = 0; b < items.length && !found; b++) {
                            if (items[b].bookmark_id === id) {
                                items[b].favicon = data.favicon;
                                found = true;
                            }
                        }
                    }
                }
                if (navData && navData.ungrouped) {
                    for (var u = 0; u < navData.ungrouped.length && !found; u++) {
                        if (navData.ungrouped[u].bookmark_id === id) {
                            navData.ungrouped[u].favicon = data.favicon;
                            found = true;
                        }
                    }
                }
                if (navData && navData.pinned) {
                    for (var p = 0; p < navData.pinned.length; p++) {
                        if (navData.pinned[p].bookmark_id === id) {
                            navData.pinned[p].favicon = data.favicon;
                        }
                    }
                }
                // Update DOM img
                var img = document.querySelector('img.nav-card-favicon[data-id="' + id + '"]');
                if (img) img.src = faviconProxyUrl(data.favicon);
            }
        })
        .catch(function() {})
        .finally(function() {
            _navFaviconRefreshing = false;
            setTimeout(navProcessFaviconQueue, 200);
        });
    }

    function initFaviconFallbacks() {
        var spans = document.querySelectorAll('.nav-card-favicon-fallback:not([style*="background"])');
        for (var i = 0; i < spans.length; i++) {
            var card = spans[i].closest('.nav-card');
            var url = card ? card.getAttribute('data-url') || '' : '';
            var hostname = '';
            if (url) {
                try { hostname = new URL(url).hostname; } catch(e) {}
            }
            var bg;
            if (hostname && typeof domainColor === 'function') {
                bg = domainColor(hostname);
                var ch = typeof domainChar === 'function' ? domainChar(hostname) : hostname.charAt(0).toUpperCase();
                spans[i].textContent = ch;
            } else {
                var title = card ? card.getAttribute('data-title') || '' : '';
                bg = typeof charColor === 'function' ? charColor(title || spans[i].textContent) : 'var(--color-gray-300)';
            }
            spans[i].style.background = bg;
        }
    }

    // --- AJAX data loading ---
    function fetchNavData() {
        var scope = isLoggedIn ? 'mine' : 'public';
        var contentEl = document.getElementById('nav-content');
        if (window.BookStarkState) {
            BookStarkState.loadingTimeout('nav:content', contentEl, {
                type: 'error',
                title: window.__('nav_page.load_failed'),
                message: window.__('nav_page.load_failed.hint'),
                actionText: '重试',
                onAction: fetchNavData
            });
        }
        fetch('/api/bookmarks-grouped?scope=' + scope, { credentials: 'same-origin' })
            .then(function(r) { return r.json(); })
            .then(function(res) {
                if (window.BookStarkState) BookStarkState.clear('nav:content');
                navData = res.data || {};
                renderNav(navData);
                renderGroupTags();
                updateCount();
                restoreCollapsedState();
                restoreGroupFilters();
                restoreView();
                initFaviconFallbacks();
                setupFaviconTimeouts();
                // Lazy-refresh favicons that are empty or default /favicon.ico
                if (isLoggedIn && navData && navData.groups) {
                    for (var g = 0; g < navData.groups.length; g++) {
                        for (var b = 0; b < navData.groups[g].bookmarks.length; b++) {
                            var item = navData.groups[g].bookmarks[b];
                            if (navNeedsFaviconRefresh(item.favicon)) {
                                navQueueFaviconRefresh(item.bookmark_id);
                            }
                        }
                    }
                }
            })
            .catch(function() {
                if (window.BookStarkState) BookStarkState.clear('nav:content');
                var el = document.getElementById('nav-content');
                if (el) {
                    if (window.BookStarkState) {
                        BookStarkState.render(el, {
                            type: 'error',
                            title: window.__('nav_page.load_failed'),
                            message: window.__('nav_page.load_failed.hint'),
                            actionText: '重试',
                            onAction: fetchNavData
                        });
                        return;
                    }
                    el.innerHTML = '<div class="nav-empty"><p class="nav-empty-title">' + window.__('nav_page.load_failed') + '</p><p style="font-size:13px">' + window.__('nav_page.load_failed.hint') + '</p></div>';
                }
            });
    }

    function updateCount() {
        var el = document.getElementById('nav-count');
        if (el && navData) {
            el.textContent = window.__('nav_page.total').replace('{n}', navData.total || 0);
        }
    }

    // --- Client-side rendering ---
    function renderCard(b) {
        var pinnedClass = b.is_pinned ? ' nav-card-pinned' : '';
        var isList = currentView === 'list';
        var manageable = isLoggedIn && isAdmin;
        var navVisible = b.nav_visible !== false && b.nav_visible !== 0;
        var html = '<div class="nav-card' + pinnedClass + (manageable ? ' nav-card-manageable' : '') + '" data-id="' + b.bookmark_id + '" data-title="' + escAttr(b.title || '') + '" data-url="' + escAttr(b.url || '') + '" data-desc="' + escAttr(b.description || '') + '">';
        if (manageable) {
            html += '<div class="nav-card-swipe-actions">';
            html += '<button type="button" onclick="event.stopPropagation();NavApp.openBookmarkEditSheet(' + b.bookmark_id + ')" class="nav-card-swipe-action" title="' + window.__('bookmark.edit') + '" aria-label="' + window.__('bookmark.edit') + '"><i class="fa-solid fa-pen"></i></button>';
            html += '<button type="button" onclick="event.stopPropagation();NavApp.toggleNavVisible(' + b.bookmark_id + ',' + (!navVisible) + ')" class="nav-card-swipe-action nav' + (navVisible ? ' off' : '') + '" title="' + (navVisible ? window.__('bookmark.batch.hide_nav') : window.__('bookmark.batch.show_nav')) + '" aria-label="' + (navVisible ? window.__('bookmark.batch.hide_nav') : window.__('bookmark.batch.show_nav')) + '"><i class="fa-solid ' + (navVisible ? 'fa-eye-slash' : 'fa-eye') + '"></i></button>';
            html += '</div><div class="nav-card-content">';
        }

        if (isList) {
            // List view: same row flow as the bookmarks page.
            html += '<a href="' + escAttr(b.url || '#') + '" target="_blank" rel="noopener" class="nav-card-link">';
            html += '<div class="nav-card-body">';
            html += '<div class="nav-card-head">';
            var faviconHtml = '';
            if (b.favicon && !_failedFavicons[b.bookmark_id]) {
                faviconHtml = '<img src="' + escAttr(faviconProxyUrl(b.favicon)) + '" class="nav-card-favicon" loading="lazy" data-id="' + b.bookmark_id + '" data-title="' + escAttr(b.title || '') + '" data-url="' + escAttr(b.url || '') + '" alt="">';
            } else {
                faviconHtml = faviconFallback(b.title || '', b.url || '');
            }
            html += '<span class="nav-card-title">' + faviconHtml + esc(b.title || '') + '</span>';
            html += '</div>';
            html += '<div class="nav-card-second">';
            if (b.description) {
                html += '<span class="nav-card-desc">' + esc(b.description) + '</span>';
            }
            if (b.labels && b.labels.length > 0) {
                html += '<span class="nav-card-labels">';
                var maxShow = 3;
                for (var i = 0; i < b.labels.length && i < maxShow; i++) {
                    html += '<span class="tag-badge tag-badge-clickable" onclick="event.stopPropagation();NavApp.searchLabel(\'' + escAttr(b.labels[i]).replace(/'/g, "\\'") + '\')">' + esc(b.labels[i]) + '</span>';
                }
                if (b.labels.length > maxShow) {
                    var extra = b.labels.slice(maxShow);
                    html += '<span class="tag-badge tag-badge-more" title="' + escAttr(extra.join(', ')) + '">+' + extra.length + '</span>';
                }
                html += '</span>';
            }
            html += '</div>';
            html += '</div></a>';
        } else {
            // Default/compact: div card
            html += '<a href="' + escAttr(b.url || '#') + '" target="_blank" rel="noopener" class="nav-card-link">';
            html += '<div class="nav-card-head">';
            if (b.favicon && !_failedFavicons[b.bookmark_id]) {
                html += '<img src="' + escAttr(faviconProxyUrl(b.favicon)) + '" class="nav-card-favicon" loading="lazy" data-id="' + b.bookmark_id + '" data-title="' + escAttr(b.title || '') + '" data-url="' + escAttr(b.url || '') + '" alt="">';
            } else {
                html += faviconFallback(b.title || '', b.url || '');
            }
            html += '<span class="nav-card-title" title="' + escAttr(b.title || '') + '">' + esc(b.title || '') + '</span>';
            html += '</div>';
            html += '<div class="nav-card-desc"' + (b.description ? ' title="' + escAttr(b.description) + '"' : '') + '>' + (b.description ? esc(b.description) : '') + '</div>';
            html += '<div class="nav-card-labels">';
            if (b.labels && b.labels.length > 0) {
                var maxShow = 3;
                for (var i = 0; i < b.labels.length && i < maxShow; i++) {
                    html += '<span class="tag-badge tag-badge-clickable" onclick="event.stopPropagation();NavApp.searchLabel(\'' + escAttr(b.labels[i]).replace(/'/g, "\\'") + '\')">' + esc(b.labels[i]) + '</span>';
                }
                if (b.labels.length > maxShow) {
                    var extra = b.labels.slice(maxShow);
                    html += '<span class="tag-badge tag-badge-more" title="' + escAttr(extra.join(', ')) + '">+' + extra.length + '</span>';
                }
            }
            html += '</div>';
            html += '</a>';
        }

        if (manageable) html += '</div>';
        html += '</div>';
        return html;
    }

    function renderGridOpen() {
        return '<div class="nav-card-grid">';
    }

    function renderGridClose() {
        return '</div>';
    }

    function renderNav(data) {
        var el = document.getElementById('nav-content');
        if (!el) return;

        var html = '';
        var hasContent = false;

        // Pinned section
        if (data.pinned && data.pinned.length > 0) {
            hasContent = true;
            html += '<section class="nav-section nav-pinned-section" data-group="__pinned__">';
            html += '<div class="nav-section-header">';
            html += '<span class="nav-section-icon"><i class="fa-solid fa-thumbtack"></i></span>';
            html += '<h2 class="nav-section-title">' + window.__('nav_page.section.pinned') + '</h2>';
            html += '<span class="nav-section-count">' + data.pinned.length + '</span>';
            html += '</div>';
            html += '<div class="nav-section-body">' + renderGridOpen();
            for (var i = 0; i < data.pinned.length; i++) {
                html += renderCard(data.pinned[i]);
            }
            html += renderGridClose() + '</div></section>';
        }

        // Group sections
        if (data.groups && data.groups.length > 0) {
            hasContent = true;
            for (var g = 0; g < data.groups.length; g++) {
                var group = data.groups[g];
                var gname = escAttr(group.name);
                html += '<section class="nav-section" data-group="' + gname + '">';
                html += '<div class="nav-section-header" onclick="NavApp.toggleGroup(\'' + escAttr(group.name.replace(/'/g, "\\'")) + '\')">';
                html += '<span class="nav-section-chevron"><i class="fa-solid fa-chevron-down" style="font-size:12px"></i></span>';
                html += '<h2 class="nav-section-title">' + esc(group.name) + '</h2>';
                html += '<span class="nav-section-count">' + group.bookmarks.length + '</span>';
                html += '</div>';
                html += '<div class="nav-section-body">' + renderGridOpen();
                for (var b = 0; b < group.bookmarks.length; b++) {
                    html += renderCard(group.bookmarks[b]);
                }
                html += renderGridClose() + '</div></section>';
            }
        }

        // Ungrouped section
        if (data.ungrouped && data.ungrouped.length > 0) {
            hasContent = true;
            html += '<section class="nav-section" data-group="__ungrouped__">';
            html += '<div class="nav-section-header" onclick="NavApp.toggleGroup(\'__ungrouped__\')">';
            html += '<span class="nav-section-chevron"><i class="fa-solid fa-chevron-down" style="font-size:12px"></i></span>';
            html += '<h2 class="nav-section-title">' + window.__('nav_page.section.ungrouped') + '</h2>';
            html += '<span class="nav-section-count">' + data.ungrouped.length + '</span>';
            html += '</div>';
            html += '<div class="nav-section-body">' + renderGridOpen();
            for (var u = 0; u < data.ungrouped.length; u++) {
                html += renderCard(data.ungrouped[u]);
            }
            html += renderGridClose() + '</div></section>';
        }

        // Empty state
        if (!hasContent) {
            html = '<div class="nav-empty"><p class="nav-empty-title">' + window.__('nav_page.empty') + '</p>';
            if (isLoggedIn) {
                html += '<a href="/bookmarks" class="nav-empty-link">' + window.__('nav_page.empty.add') + '</a>';
            }
            html += '</div>';
        }

        el.innerHTML = html;
        closeSwipeCards();
        }

    // View switching
    function switchView(view) {
        var container = document.querySelector('.nav-container');
        if (!container) return;

        var prevView = currentView;
        container.classList.remove('view-default', 'view-list', 'view-compact');
        if (view !== 'default') {
            container.classList.add('view-' + view);
        }
        currentView = view;
        try { localStorage.setItem('nav_view', view); } catch(e) {}

        // Re-render to apply view class changes (CSS handles layout)
        if (navData) {
            renderNav(navData);
            restoreCollapsedState();
            restoreGroupFilters();
            // 重渲染后给新 img 绑定 onerror/超时；已失败的 favicon 已在 renderCard 中跳过 img
            initFaviconFallbacks();
            setupFaviconTimeouts();
        }

        // Update menu active state
        var options = document.querySelectorAll('.nav-view-option');
        for (var i = 0; i < options.length; i++) {
            options[i].classList.toggle('active', options[i].getAttribute('data-view') === view);
        }

        // Update button icon
        var icon = document.getElementById('nav-view-icon');
        if (icon) {
            icon.className = 'fa-solid ' + (VIEW_ICONS[view] || VIEW_ICONS['default']);
        }

        closeViewMenu();
    }

    function viewMenuItems() {
        var menu = document.getElementById('nav-view-menu');
        if (!menu) return [];
        return Array.prototype.slice.call(menu.querySelectorAll('.nav-view-option, [role="menuitem"], button, a[href]')).filter(function(item) {
            return !item.disabled && item.getAttribute('aria-disabled') !== 'true' && item.offsetParent !== null;
        });
    }

    function focusViewMenuItem(index) {
        var items = viewMenuItems();
        if (!items.length) return;
        items[(index + items.length) % items.length].focus();
    }

    function toggleViewMenu() {
        var menu = document.getElementById('nav-view-menu');
        var btn = document.getElementById('nav-view-btn');
        if (!menu) return;
        menu.classList.toggle('open');
        if (btn) btn.setAttribute('aria-expanded', menu.classList.contains('open') ? 'true' : 'false');
    }

    function closeViewMenu() {
        var menu = document.getElementById('nav-view-menu');
        var btn = document.getElementById('nav-view-btn');
        if (menu) menu.classList.remove('open');
        if (btn) btn.setAttribute('aria-expanded', 'false');
    }

    function restoreView() {
        switchView(currentView);
    }

    function init() {
        fetchNavData();

        // Close view menu on outside click
        document.addEventListener('click', function(e) {
            var switcher = document.querySelector('.nav-view-switcher');
            if (switcher && !switcher.contains(e.target)) {
                closeViewMenu();
            }
        });

        var viewBtn = document.getElementById('nav-view-btn');
        var viewMenu = document.getElementById('nav-view-menu');
        if (viewBtn && viewMenu) {
            viewBtn.addEventListener('keydown', function(e) {
                if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                    e.preventDefault();
                    if (!viewMenu.classList.contains('open')) toggleViewMenu();
                    focusViewMenuItem(e.key === 'ArrowDown' ? 0 : -1);
                }
            });
            viewMenu.addEventListener('keydown', function(e) {
                var items = viewMenuItems();
                var idx = items.indexOf(document.activeElement);
                if (e.key === 'Escape') {
                    e.preventDefault();
                    closeViewMenu();
                    viewBtn.focus();
                } else if (e.key === 'ArrowDown' && items.length) {
                    e.preventDefault();
                    focusViewMenuItem(idx + 1);
                } else if (e.key === 'ArrowUp' && items.length) {
                    e.preventDefault();
                    focusViewMenuItem(idx - 1);
                } else if (e.key === 'Home') {
                    e.preventDefault();
                    focusViewMenuItem(0);
                } else if (e.key === 'End') {
                    e.preventDefault();
                    focusViewMenuItem(-1);
                } else if ((e.key === 'Enter' || e.key === ' ') && document.activeElement && document.activeElement.getAttribute('role') === 'menuitem') {
                    e.preventDefault();
                    document.activeElement.click();
                }
            });
        }
    }

    // Group tags bar
    function renderGroupTags() {
        var container = document.getElementById('nav-group-tags');
        if (!container || !navData) return;

        var allLabels = navData.all_labels || [];
        var groupNames = [];
        var seen = {};
        for (var i = 0; i < allLabels.length; i++) {
            var slashIdx = allLabels[i].indexOf('/');
            if (slashIdx > 0) {
                var prefix = allLabels[i].substring(0, slashIdx);
                if (!seen[prefix]) {
                    seen[prefix] = true;
                    groupNames.push(prefix);
                }
            }
        }

        var html = '<span class="nav-group-tag active" onclick="NavApp.filterGroup(\'\')"><i class="fa-solid fa-border-all" style="font-size:10px"></i>' + window.__('nav_page.tag.all') + '</span>';
        for (var g = 0; g < groupNames.length; g++) {
            var c = typeof charColor === 'function' ? charColor(groupNames[g]) : '';
            html += '<span class="nav-group-tag" data-color="' + c + '" onclick="NavApp.filterGroup(\'' + esc(groupNames[g]).replace(/'/g, "\\'") + '\')">' + esc(groupNames[g]) + '</span>';
        }
        if (navData.ungrouped_count > 0 || (navData.ungrouped && navData.ungrouped.length > 0)) {
            var uc = typeof charColor === 'function' ? charColor('未分组') : '';
            html += '<span class="nav-group-tag" data-color="' + uc + '" onclick="NavApp.filterGroup(\'__ungrouped__\')">' + window.__('nav_page.tag.ungrouped') + '</span>';
        }
        container.innerHTML = html;
    }

    // Toggle group collapse
    function toggleGroup(name) {
        var section = document.querySelector('.nav-section[data-group="' + name + '"]');
        if (!section) return;
        section.classList.toggle('collapsed');
        collapsedGroups[name] = section.classList.contains('collapsed');
        try { localStorage.setItem('nav_collapsed', JSON.stringify(collapsedGroups)); } catch(e) {}
    }

    function restoreCollapsedState() {
        for (var name in collapsedGroups) {
            if (collapsedGroups[name]) {
                var section = document.querySelector('.nav-section[data-group="' + name + '"]');
                if (section) section.classList.add('collapsed');
            }
        }
    }

    // Search
    function onSearch(query) {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(function() {
            performSearch(query.trim().toLowerCase());
        }, 200);
    }

    function performSearch(query) {
        var sections = document.querySelectorAll('.nav-section');
        for (var i = 0; i < sections.length; i++) {
            var cards = sections[i].querySelectorAll('.nav-card');
            if (!query) {
                sections[i].style.display = '';
                for (var j = 0; j < cards.length; j++) cards[j].style.display = '';
                continue;
            }
            var hasVisible = false;
            for (var j = 0; j < cards.length; j++) {
                var title = (cards[j].getAttribute('data-title') || '').toLowerCase();
                var url = (cards[j].getAttribute('data-url') || '').toLowerCase();
                var desc = (cards[j].getAttribute('data-desc') || '').toLowerCase();
                var match = title.indexOf(query) >= 0 || url.indexOf(query) >= 0 || desc.indexOf(query) >= 0;
                cards[j].style.display = match ? '' : 'none';
                if (match) hasVisible = true;
            }
            sections[i].style.display = hasVisible ? '' : 'none';
        }
    }

    // Filter by group (multi-select toggle)
    function filterGroup(groupName) {
        var tags = document.querySelectorAll('.nav-group-tag');
        var allTag = tags[0]; // "全部" button

        if (groupName === '') {
            // "全部" clicked: clear all other selections, show all
            for (var i = 0; i < tags.length; i++) {
                tags[i].classList.remove('active');
                tags[i].style.color = '';
                tags[i].style.borderColor = '';
                tags[i].style.background = '';
            }
            allTag.classList.add('active');
            activeGroupFilters = [];
            saveGroupFilters();
            var sections = document.querySelectorAll('.nav-section');
            for (var i = 0; i < sections.length; i++) {
                sections[i].style.display = '';
            }
            return;
        }

        // Deselect "全部"
        allTag.classList.remove('active');

        // Find the clicked tag and toggle it
        var clickedTag = null;
        for (var i = 1; i < tags.length; i++) {
            var tagGroup = tags[i].textContent;
            if (tagGroup === groupName || (groupName === '__ungrouped__' && tagGroup === '未分组')) {
                clickedTag = tags[i];
                break;
            }
        }

        if (!clickedTag) return;

        // Toggle the clicked tag
        var isNowActive = !clickedTag.classList.contains('active');
        if (isNowActive) {
            clickedTag.classList.add('active');
            var c = clickedTag.getAttribute('data-color');
            if (c) {
                clickedTag.style.color = c;
                clickedTag.style.borderColor = c;
                clickedTag.style.background = c + '15';
            }
        } else {
            clickedTag.classList.remove('active');
            clickedTag.style.color = '';
            clickedTag.style.borderColor = '';
            clickedTag.style.background = '';
        }

        // If no group tag is active, revert to "全部"
        var hasActive = false;
        for (var i = 1; i < tags.length; i++) {
            if (tags[i].classList.contains('active')) {
                hasActive = true;
                break;
            }
        }
        if (!hasActive) {
            allTag.classList.add('active');
        }

        // Show/hide sections based on active tags
        var activeGroups = {};
        activeGroupFilters = [];
        for (var i = 1; i < tags.length; i++) {
            if (tags[i].classList.contains('active')) {
                var g = tags[i].textContent;
                activeGroups[g] = true;
                activeGroupFilters.push(groupName === '__ungrouped__' && g === '未分组' ? '__ungrouped__' : g);
                // Also map __ungrouped__ for section matching
                if (g === '未分组') activeGroups['__ungrouped__'] = true;
            }
        }
        saveGroupFilters();

        var showAll = !hasActive;
        var sections = document.querySelectorAll('.nav-section');
        for (var i = 0; i < sections.length; i++) {
            if (showAll) {
                sections[i].style.display = '';
            } else {
                var sectionGroup = sections[i].getAttribute('data-group');
                // Pinned section always visible when filtering
                if (sectionGroup === '__pinned__') {
                    sections[i].style.display = '';
                } else {
                    sections[i].style.display = activeGroups[sectionGroup] ? '' : 'none';
                }
            }
        }
    }

    function saveGroupFilters() {
        try { localStorage.setItem('nav_group_filters', JSON.stringify(activeGroupFilters)); } catch(e) {}
    }

    function restoreGroupFilters() {
        if (!activeGroupFilters || activeGroupFilters.length === 0) return;
        // Apply each saved filter
        for (var i = 0; i < activeGroupFilters.length; i++) {
            filterGroup(activeGroupFilters[i]);
        }
    }

    function searchLabel(label) {
        window.location.href = '/bookmarks?label=' + encodeURIComponent(label);
    }

    window.NavApp = {
        toggleGroup: toggleGroup,
        filterGroup: filterGroup,
        onSearch: onSearch,
        switchView: switchView,
        searchLabel: searchLabel,
        toggleViewMenu: toggleViewMenu,
        toggleNavVisible: toggleNavVisible,
        openBookmarkEditSheet: openBookmarkEditSheet
    };

    initSwipeActions();
    init();
})();
