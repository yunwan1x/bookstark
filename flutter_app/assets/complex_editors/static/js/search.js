/* ===== BookStark Global Search ===== */
(function() {
    'use strict';

    var currentTab = 'all';
    var currentKeyword = '';
    var abortController = null;

    function tr(key, fallback, vars) {
        var msg = window.__ ? window.__(key) : key;
        if (!msg || msg === key) msg = fallback || key;
        Object.keys(vars || {}).forEach(function(name) {
            msg = msg.replace(new RegExp('\\{' + name + '\\}', 'g'), vars[name]);
        });
        return msg;
    }

    // Initialize on DOM ready
    document.addEventListener('DOMContentLoaded', function() {
        var urlParams = new URLSearchParams(window.location.search);
        var q = urlParams.get('q') || '';
        var type = urlParams.get('tab') || urlParams.get('type') || 'all';
        var allowedTypes = ['all', 'documents', 'notes', 'articles', 'books', 'bookmarks', 'tasks', 'topics', 'labels'];
        if (allowedTypes.indexOf(type) === -1) type = 'all';
        currentKeyword = q.trim();
        currentTab = type;

        initSearchInput();
        initTabs();
        initSearchButton();

        if (currentKeyword) {
            doSearch(currentKeyword);
        } else {
            showEmpty();
        }
    });

    function initSearchInput() {
        var input = document.getElementById('search-page-input');
        if (!input) return;
        input.value = currentKeyword;

        input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                var q = input.value.trim();
                if (q) {
                    currentTab = 'all';
                    resetTabUI();
                    doSearch(q);
                } else {
                    currentKeyword = '';
                    updateURL();
                    showEmpty();
                }
            }
        });
    }

    function initSearchButton() {
        var btn = document.getElementById('search-page-btn');
        var input = document.getElementById('search-page-input');
        if (!btn || !input) return;
        btn.addEventListener('click', function() {
            var q = input.value.trim();
            if (q) {
                currentTab = 'all';
                resetTabUI();
                doSearch(q);
            } else {
                currentKeyword = '';
                updateURL();
                showEmpty();
            }
        });
    }

    function initTabs() {
        var tabs = document.querySelectorAll('.search-tab');
        var activeTab = null;
        tabs.forEach(function(tb) {
            var isActive = tb.getAttribute('data-tab') === currentTab;
            tb.classList.toggle('active', isActive);
            if (isActive) activeTab = tb;
        });
        scrollTabIntoView(activeTab, false);
        tabs.forEach(function(tab) {
            tab.addEventListener('click', function() {
                var t = this.getAttribute('data-tab');
                if (t === currentTab) return;
                currentTab = t;
                tabs.forEach(function(tb) { tb.classList.remove('active'); });
                this.classList.add('active');
                scrollTabIntoView(this, true);
                updateURL();
                renderResults();
            });
        });
    }

    function scrollTabIntoView(tab, smooth) {
        if (!tab || typeof tab.scrollIntoView !== 'function') return;
        try {
            tab.scrollIntoView({
                behavior: smooth ? 'smooth' : 'auto',
                block: 'nearest',
                inline: 'center'
            });
        } catch (err) {
            tab.scrollIntoView(false);
        }
    }

    function resetTabUI() {
        var tabs = document.querySelectorAll('.search-tab');
        tabs.forEach(function(tb) { tb.classList.remove('active'); });
        var allTab = document.querySelector('.search-tab[data-tab="all"]');
        if (allTab) {
            allTab.classList.add('active');
            scrollTabIntoView(allTab, true);
        }
    }

    function updateURL() {
        var url = '/search?q=' + encodeURIComponent(currentKeyword);
        if (currentTab && currentTab !== 'all') {
            url += '&tab=' + encodeURIComponent(currentTab);
        }
        history.replaceState(null, '', url);
    }

    function doSearch(keyword) {
        if (abortController) {
            abortController.abort();
        }
        abortController = new AbortController();

        currentKeyword = keyword.trim();

        var input = document.getElementById('search-page-input');
        if (input && input.value.trim() !== currentKeyword) {
            input.value = currentKeyword;
        }

        updateURL();
        showSkeleton();
        if (window.BookStarkState) {
            BookStarkState.loadingTimeout('search:results', document.getElementById('search-results'), {
                type: 'error',
                title: '搜索超时',
                message: '搜索服务暂时没有响应',
                actionText: '重试',
                onAction: function() { doSearch(currentKeyword); }
            });
        }

        fetch('/api/search?q=' + encodeURIComponent(currentKeyword), {
            credentials: 'same-origin',
            signal: abortController.signal
        })
        .then(function(res) {
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
        })
        .then(function(json) {
            if (window.BookStarkState) BookStarkState.clear('search:results');
            if (json.code !== 0 && json.code !== undefined) {
                throw new Error(json.message || '搜索失败');
            }
            var data = json.data || json;
            window._searchData = data;
            updateCounts(data.counts || {}, data.blogs || []);
            renderResults();
        })
        .catch(function(err) {
            if (err.name === 'AbortError') return;
            if (window.BookStarkState) BookStarkState.clear('search:results');
            console.error('Search failed:', err);
            showError();
        });
    }

    function updateCounts(counts, blogs) {
        // Split blog counts by type
        var noteCount = 0, articleCount = 0;
        if (blogs) {
            blogs.forEach(function(b) {
                if (b.blog_type === 'note') noteCount++;
                else articleCount++;
            });
        }
        var total = (counts.documents || 0) + noteCount + articleCount + (counts.books || 0) + (counts.bookmarks || 0) + (counts.tasks || 0) + (counts.topics || 0) + (counts.labels || 0);
        setCount('count-all', total);
        setCount('count-documents', counts.documents || 0);
        setCount('count-notes', noteCount);
        setCount('count-articles', articleCount);
        setCount('count-books', counts.books || 0);
        setCount('count-bookmarks', counts.bookmarks || 0);
        setCount('count-tasks', counts.tasks || 0);
        setCount('count-topics', counts.topics || 0);
        setCount('count-labels', counts.labels || 0);
    }

    function setCount(id, n) {
        var el = document.getElementById(id);
        if (el) el.textContent = n;
    }

    function renderResults() {
        var data = window._searchData;
        if (!data) return;

        var container = document.getElementById('search-results');
        if (!container) return;

        var docs = data.documents || [];
        var blogs = data.blogs || [];
        var books = data.books || [];
        var bms = data.bookmarks || [];
        var tasks = data.tasks || [];
        var topics = data.topics || [];
        var labels = data.labels || [];
        var kw = currentKeyword;

        // Split blogs by type
        var notes = [], articles = [];
        blogs.forEach(function(b) {
            if (b.blog_type === 'note') notes.push(b);
            else articles.push(b);
        });

        var html = '';

        if (currentTab === 'all' || currentTab === 'documents') {
            if (docs.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-file-lines"></i> 文档</div>';
                docs.forEach(function(d) {
                    html += renderItem('doc', 'fa-file-lines',
                        highlight(escHtml(d.name), kw),
                        escHtml(d.book_name),
                        highlight(escHtml(d.snippet), kw),
                        '/books/' + escAttr(d.book_identify) + '/edit?doc=' + d.id + '&from=' + encodeURIComponent(location.pathname + location.search)
                    );
                });
                if (docs.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'notes') {
            if (notes.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-note-sticky"></i> 笔记</div>';
                notes.forEach(function(b) {
                    html += renderItem('note', 'fa-note-sticky',
                        highlight(escHtml(b.title), kw),
                        '',
                        highlight(escHtml(b.snippet), kw),
                        '/notes?id=' + b.id
                    );
                });
                if (notes.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'articles') {
            if (articles.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-pen-nib"></i> 文章</div>';
                articles.forEach(function(b) {
                    html += renderItem('article', 'fa-pen-nib',
                        highlight(escHtml(b.title), kw),
                        '',
                        highlight(escHtml(b.snippet), kw),
                        '/notes?id=' + b.id
                    );
                });
                if (articles.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'books') {
            if (books.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-book"></i> 书籍</div>';
                books.forEach(function(bk) {
                    var meta = bk.doc_count > 0 ? bk.doc_count + ' 篇文档' : '';
                    html += renderItem('book', 'fa-book',
                        highlight(escHtml(bk.name), kw),
                        meta,
                        highlight(escHtml(bk.description), kw),
                        '/books/' + escAttr(bk.identify) + '/edit?from=' + encodeURIComponent(location.pathname + location.search)
                    );
                });
                if (books.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'bookmarks') {
            if (bms.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-bookmark"></i> 书签</div>';
                bms.forEach(function(bm) {
                    html += renderItem('bookmark', 'fa-bookmark',
                        highlight(escHtml(bm.title), kw),
                        escHtml(bm.url),
                        '',
                        '/bookmarks?id=' + bm.id
                    );
                });
                if (bms.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'tasks') {
            if (tasks.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-list-check"></i> ' + escHtml(tr('search.section.tasks', '待办')) + '</div>';
                tasks.forEach(function(t) {
                    var meta = [];
                    if (t.due_date) meta.push(tr('search.task.due', '截止 {date}', { date: t.due_date }));
                    meta.push(t.done ? tr('task.status.done', '已完成') : tr('task.status.open', '未完成'));
                    html += renderItem('task', 'fa-list-check',
                        highlight(escHtml(firstLine(t.content) || tr('search.task.untitled', '未命名待办')), kw),
                        escHtml(meta.join(' · ')),
                        highlight(escHtml(t.snippet || t.content), kw),
                        '/notes?tab=tasks&task_id=' + encodeURIComponent(t.id)
                    );
                });
                if (tasks.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'topics') {
            if (topics.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-box-archive"></i> ' + escHtml(tr('search.section.topics', '专题')) + '</div>';
                topics.forEach(function(topic) {
                    var meta = topic.item_count > 0 ? topic.item_count + ' 项资料' : tr('search.section.topics', '专题');
                    html += renderItem('topic', 'fa-box-archive',
                        highlight(escHtml(topic.title || tr('topic.untitled', '未命名专题')), kw),
                        escHtml(meta),
                        highlight(escHtml(topic.snippet || topic.question), kw),
                        '/topics?id=' + encodeURIComponent(topic.id)
                    );
                });
                if (topics.length >= 20) {
                    html += '<div class="search-more-hint">结果较多，试试更具体的关键词</div>';
                }
                html += '</div>';
            }
        }

        if (currentTab === 'all' || currentTab === 'labels') {
            if (labels.length > 0) {
                html += '<div class="search-section">';
                html += '<div class="search-section-title"><i class="fa-solid fa-tag"></i> 标签</div>';
                labels.forEach(function(l) {
                    html += renderItem('label', 'fa-tag',
                        highlight(escHtml(l.name), kw),
                        '',
                        '',
                        '/labels?id=' + l.id
                    );
                });
                html += '</div>';
            }
        }

        if (!html) {
            if (window.BookStarkState) {
                BookStarkState.render(container, { type: 'empty', title: '该分类下无匹配结果', icon: 'fa-folder-open' });
                return;
            }
            html = '<div class="search-empty">' +
                '<i class="fa-solid fa-folder-open" style="font-size:2rem;margin-bottom:1rem;display:block"></i>' +
                '<p style="font-size:1rem;margin-bottom:0.5rem">该分类下无匹配结果</p></div>';
        }

        container.innerHTML = html;
    }

    function renderItem(type, icon, title, meta, snippet, href) {
        var html = '<a href="' + href + '" class="search-item list-row">';
        html += '<div class="search-icon ' + type + '"><i class="fa-solid ' + icon + '"></i></div>';
        html += '<div class="search-body">';
        html += '<div class="search-title">' + title + '</div>';
        if (meta) {
            html += '<div class="search-meta">' + meta + '</div>';
        }
        if (snippet) {
            html += '<div class="search-snippet">' + snippet + '</div>';
        }
        html += '</div></a>';
        return html;
    }

    function highlight(text, keyword) {
        if (!keyword) return text;
        var k = keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        return text.replace(new RegExp(k, 'gi'), '<mark>$&</mark>');
    }

    function firstLine(str) {
        return String(str || '').split(/\r?\n/)[0].trim();
    }

    function showSkeleton() {
        var container = document.getElementById('search-results');
        if (!container) return;
        var html = '';
        for (var i = 0; i < 4; i++) {
            html += '<div class="search-skeleton list-row">';
            html += '<div class="search-skeleton-icon skeleton"></div>';
            html += '<div class="search-skeleton-body">';
            html += '<div class="search-skeleton-title skeleton"></div>';
            html += '<div class="search-skeleton-meta skeleton"></div>';
            html += '<div class="search-skeleton-snippet skeleton"></div>';
            html += '</div></div>';
        }
        container.innerHTML = html;
    }

    function showEmpty() {
        var container = document.getElementById('search-results');
        if (!container) return;
        if (window.BookStarkState) {
            BookStarkState.render(container, {
                type: 'empty',
                icon: 'fa-magnifying-glass',
                title: '输入关键词开始搜索',
                message: '搜索范围：文档标题与内容、笔记与文章、待办、专题、书籍名称与描述、书签标题与链接、标签名'
            });
            return;
        }
        container.innerHTML = '<div class="search-empty">' +
            '<i class="fa-solid fa-magnifying-glass" style="font-size:2rem;margin-bottom:1rem;display:block"></i>' +
            '<p style="font-size:1rem;margin-bottom:0.5rem">输入关键词开始搜索</p>' +
            '<p style="font-size:0.75rem;color:var(--color-gray-400)">搜索范围：文档标题与内容、笔记与文章、待办、专题、书籍名称与描述、书签标题与链接、标签名</p></div>';
    }

    function showError() {
        var container = document.getElementById('search-results');
        if (!container) return;
        if (window.BookStarkState) {
            BookStarkState.render(container, {
                type: 'error',
                title: '搜索出错',
                message: '请检查网络后重试',
                actionText: '重试',
                onAction: function() { if (currentKeyword) doSearch(currentKeyword); }
            });
            return;
        }
        container.innerHTML = '<div class="search-error">' +
            '<i class="fa-solid fa-circle-exclamation" style="font-size:2rem;margin-bottom:1rem;display:block"></i>' +
            '<p style="font-size:1rem;margin-bottom:0.5rem">搜索出错，请重试</p></div>';
    }

    // Expose for header search
    window.BookStarkSearch = {
        doSearch: doSearch
    };
})();
