(function() {
    var currentPage = 1;
    var currentType = '';
    var totalPages = 0;
    var totalItems = 0;
    var selectedIds = [];
    var selectAllMode = false;
    var selectAllTotal = 0;
    var skeletonHtml = document.getElementById('trash-loading').innerHTML;

    function tr(key, fallback, vars) {
        var msg = window.__ ? window.__(key) : key;
        if (!msg || msg === key) msg = fallback || key;
        Object.keys(vars || {}).forEach(function(name) {
            msg = msg.replace(new RegExp('\\{' + name + '\\}', 'g'), vars[name]);
        });
        return msg;
    }

    var typeLabels = {
        book: tr('trash.type.book', '书籍'),
        blog: tr('trash.type.blog', '博客'),
        bookmark: tr('trash.type.bookmark', '书签'),
        document: tr('trash.type.doc', '文档'),
        task: tr('trash.type.task', '待办'),
        topic: tr('trash.type.topic', '专题')
    };
    var typeIcons = { book: 'fa-book', blog: 'fa-pen-nib', bookmark: 'fa-bookmark', document: 'fa-file-lines', task: 'fa-list-check', topic: 'fa-folder-tree' };

    window.switchType = function(btn, type, opts) {
        opts = opts || {};
        currentType = type;
        if (opts.updateUrl !== false && window.BookStarkTabURL) window.BookStarkTabURL.set('tab', type || 'all');
        currentPage = 1;
        selectedIds = [];
        selectAllMode = false;
        selectAllTotal = 0;
        updateBatchBar();
        document.querySelectorAll('.filter-tab').forEach(function(t) { t.classList.remove('active'); });
        btn.classList.add('active');
        loadTrash();
    };

    window.toggleSelectAll = function(checked) {
        if (checked) {
            selectAllMode = true;
            selectAllTotal = totalItems;
            var boxes = document.querySelectorAll('.trash-item-checkbox');
            boxes.forEach(function(b) {
                b.checked = true;
                var id = parseInt(b.dataset.id);
                if (selectedIds.indexOf(id) === -1) selectedIds.push(id);
            });
        } else {
            selectAllMode = false;
            selectAllTotal = 0;
            selectedIds = [];
            var boxes = document.querySelectorAll('.trash-item-checkbox');
            boxes.forEach(function(b) { b.checked = false; });
        }
        updateBatchBar();
    };

    window.toggleSelect = function(id, checked) {
        if (selectAllMode) {
            // Exit selectAllMode: keep only current page items, toggle the clicked one
            selectAllMode = false;
            selectAllTotal = 0;
            var newIds = [];
            var boxes = document.querySelectorAll('.trash-item-checkbox');
            boxes.forEach(function(b) {
                var bid = parseInt(b.dataset.id);
                if (bid !== id) newIds.push(bid);
            });
            selectedIds = newIds;
            // Update checkbox UI
            boxes.forEach(function(b) {
                var bid = parseInt(b.dataset.id);
                b.checked = bid !== id;
            });
            updateBatchBar();
            return;
        }
        if (checked) {
            if (selectedIds.indexOf(id) === -1) selectedIds.push(id);
        } else {
            selectedIds = selectedIds.filter(function(x) { return x !== id; });
        }
        updateBatchBar();
    };

    function updateBatchBar() {
        var bar = document.getElementById('batch-bar');
        var countEl = document.getElementById('selected-count');
        var selectAll = document.getElementById('select-all');
        var count = selectAllMode ? selectAllTotal : selectedIds.length;
        if (count > 0) {
            bar.classList.add('active');
            countEl.textContent = '已选 ' + count + ' 项';
            countEl.classList.toggle('trash-count-all', selectAllMode);
        } else {
            bar.classList.remove('active');
            countEl.classList.remove('trash-count-all');
        }
        var boxes = document.querySelectorAll('.trash-item-checkbox');
        if (selectAllMode) {
            selectAll.checked = true;
        } else if (boxes.length > 0) {
            var allChecked = true;
            boxes.forEach(function(b) { if (!b.checked) allChecked = false; });
            selectAll.checked = allChecked;
        } else {
            selectAll.checked = false;
        }
    }

    // Build current filter for batch-by-filter API
    function getTrashFilter() {
        var f = {};
        if (currentType) f.type = currentType;
        return f;
    }

    window.restoreItem = async function(id, name) {
        var ok = await BSDialog.confirm2('确定恢复「' + name + '」？');
        if (!ok) return;
        try {
            var r = await csrfFetch('/api/trash/' + id + '/restore', { method: 'POST' });
            var d = await r.json();
            if (d.code && d.code !== 0) { BSDialog.toast(d.message || '操作失败', 'error'); return; }
            BSDialog.toast('恢复成功', 'success');
            loadTrash();
        } catch(e) {
            BSDialog.toast('恢复失败', 'error');
        }
    };

    window.permanentDeleteItem = async function(id, name) {
        var ok = await BSDialog.confirm2('确定永久删除「' + name + '」？此操作不可恢复。');
        if (!ok) return;
        try {
            var r = await csrfFetch('/api/trash/' + id, { method: 'DELETE' });
            var d = await r.json();
            if (d.code && d.code !== 0) { BSDialog.toast(d.message || '操作失败', 'error'); return; }
            BSDialog.toast('已永久删除', 'success');
            loadTrash();
        } catch(e) {
            BSDialog.toast('删除失败', 'error');
        }
    };

    window.batchRestore = async function() {
        var count = selectAllMode ? selectAllTotal : selectedIds.length;
        if (count === 0) { BSDialog.toast('请先选择项目', 'error'); return; }
        var ok = await BSDialog.confirm2('确定恢复选中的 ' + count + ' 个项目？');
        if (!ok) return;
        var body;
        if (selectAllMode) {
            body = JSON.stringify({ filter: getTrashFilter() });
        } else {
            body = JSON.stringify({ ids: selectedIds });
        }
        try {
            var r = await csrfFetch('/api/trash/batch-restore', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: body
            });
            var d = await r.json();
            if (d.code && d.code !== 0) { BSDialog.toast(d.message || '批量恢复部分失败', 'error'); return; }
            else { BSDialog.toast('批量恢复成功', 'success'); }
            selectedIds = [];
            selectAllMode = false;
            selectAllTotal = 0;
            loadTrash();
        } catch(e) {
            BSDialog.toast('批量恢复失败', 'error');
        }
    };

    window.batchDelete = async function() {
        var count = selectAllMode ? selectAllTotal : selectedIds.length;
        if (count === 0) { BSDialog.toast('请先选择项目', 'error'); return; }
        var ok = await BSDialog.confirm2('确定永久删除选中的 ' + count + ' 个项目？此操作不可恢复。');
        if (!ok) return;
        var body;
        if (selectAllMode) {
            body = JSON.stringify({ filter: getTrashFilter() });
        } else {
            body = JSON.stringify({ ids: selectedIds });
        }
        try {
            var res = await csrfFetch('/api/trash/batch-delete', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: body
            });
            var d = await res.json();
            if (d.code && d.code !== 0) { BSDialog.toast(d.message || '操作失败', 'error'); return; }
            BSDialog.toast('已永久删除', 'success');
            selectedIds = [];
            selectAllMode = false;
            selectAllTotal = 0;
            loadTrash();
        } catch(e) {
            BSDialog.toast('批量删除失败', 'error');
        }
    };

    window.purgeTrash = async function() {
        var ok = await BSDialog.confirm2('确定清空回收站？所有项目将被永久删除，此操作不可恢复。');
        if (!ok) return;
        try {
            var r = await csrfFetch('/api/trash/purge', { method: 'DELETE' });
            var d = await r.json();
            if (d.code && d.code !== 0) { BSDialog.toast(d.message || '操作失败', 'error'); return; }
            BSDialog.toast('回收站已清空', 'success');
            selectedIds = [];
            selectAllMode = false;
            selectAllTotal = 0;
            loadTrash();
        } catch(e) {
            BSDialog.toast('清空失败', 'error');
        }
    };

    async function loadTrash() {
        var listEl = document.getElementById('trash-list');
        listEl.innerHTML = skeletonHtml;
        listEl.style.display = '';

        var params = 'page=' + currentPage + '&page_size=20';
        if (currentType) params += '&type=' + currentType;

        try {
            var r = await csrfFetch('/api/trash?' + params);
            if (!r.ok) throw new Error('请求失败');
            var d = await r.json();
            var items = d.data || [];
            totalItems = d.total || 0;

            document.getElementById('trash-count').textContent = totalItems > 0 ? ('共 ' + totalItems + ' 项') : '';
            var purgeBtn = document.getElementById('purge-btn');
            purgeBtn.style.display = totalItems > 0 ? '' : 'none';

            if (!items || items.length === 0) {
                listEl.innerHTML = '<div class="text-center py-16 text-slate-500"><i class="fa-solid fa-trash-can text-4xl mb-4" style="display:block"></i><p class="text-lg mb-2">回收站为空</p></div>';
                document.getElementById('trash-pagination').innerHTML = '';
                document.getElementById('batch-bar').classList.remove('active');
                return;
            }

            listEl.innerHTML = items.map(function(item) {
                var typeLabel = typeLabels[item.resource_type] || item.resource_type;
                var typeIcon = typeIcons[item.resource_type] || 'fa-file';
                var typeClass = 'trash-type-' + item.resource_type;
                var time = item.delete_time ? item.delete_time.substring(0, 16).replace('T', ' ') : '';
                var checked = selectedIds.indexOf(item.trash_id) !== -1 ? 'checked' : '';
                return '<div class="list-row" style="display:flex;align-items:center;gap:10px">' +
                    '<input type="checkbox" class="trash-checkbox trash-item-checkbox" data-id="' + item.trash_id + '" ' + checked + ' onchange="toggleSelect(' + item.trash_id + ', this.checked)" aria-label="选择">' +
                    '<span class="trash-type-badge ' + typeClass + '"><i class="fa-solid ' + typeIcon + '" style="font-size:10px"></i>' + escHtml(typeLabel) + '</span>' +
                    '<div style="flex:1;min-width:0">' +
                        (item.resource_url
                            ? '<a href="' + escAttr(item.resource_url) + '" target="_blank" rel="noopener noreferrer" class="list-row-title" style="display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-decoration:none">' + escHtml(item.resource_name) + '</a>'
                            : '<div class="list-row-title" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + escHtml(item.resource_name) + '</div>') +
                        '<div style="font-size:12px;color:var(--color-gray-500);margin-top:2px">' + time + '</div>' +
                    '</div>' +
                    '<div class="trash-actions">' +
                        '<button class="trash-action-btn trash-action-restore" onclick="restoreItem(' + item.trash_id + ', \'' + escAttr(item.resource_name) + '\')" aria-label="恢复">恢复</button>' +
                        '<button class="trash-action-btn trash-action-delete" onclick="permanentDeleteItem(' + item.trash_id + ', \'' + escAttr(item.resource_name) + '\')" aria-label="永久删除">删除</button>' +
                    '</div>' +
                '</div>';
            }).join('');

            totalPages = Math.ceil(totalItems / 20) || 1;
            renderPagination('trash-pagination', currentPage, totalPages, function(page) { currentPage = page; loadTrash(); });

            // In selectAllMode, auto-select all rows on current page
            if (selectAllMode) {
                selectedIds = [];
                items.forEach(function(item) {
                    selectedIds.push(item.trash_id);
                });
                selectAllTotal = totalItems;
                var boxes = document.querySelectorAll('.trash-item-checkbox');
                boxes.forEach(function(b) { b.checked = true; });
            }

            updateBatchBar();
        } catch(e) {
            listEl.innerHTML = '<div class="text-center py-16 text-slate-500"><p class="text-lg mb-2">加载失败</p><p class="text-sm">请检查网络后重试</p></div>';
            document.getElementById('trash-count').textContent = '';
        }
    }

    if (window.BookStarkTabURL) {
        var initialType = window.BookStarkTabURL.get('tab', ['all', 'book', 'blog', 'bookmark', 'document', 'task', 'topic'], '');
        if (initialType) {
            var typeValue = initialType === 'all' ? '' : initialType;
            var initialBtn = document.querySelector('.filter-tab[data-type="' + typeValue + '"]');
            if (initialBtn) {
                currentType = typeValue;
                document.querySelectorAll('.filter-tab').forEach(function(t) { t.classList.remove('active'); });
                initialBtn.classList.add('active');
            }
        }
    }
    loadTrash();
})();
