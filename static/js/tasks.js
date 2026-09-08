(function() {
    var root = document.getElementById('bookstarkTasksRoot');
    if (!root) return;

    var state = {
        tasks: [],
        selectedDate: null,
        doneFilter: null,
        dueFilter: null,
        keyword: '',
        editingTask: null,
        modalParentID: 0,
        modalFromQuick: false,
        taskMap: {}
    };
    var taskQuickComposer = null;
    var taskModalComposer = null;

    function $(id) { return document.getElementById(id); }
    function text(v) { return String(v == null ? '' : v); }
    function esc(s) { return typeof escHtml === 'function' ? escHtml(text(s)) : text(s).replace(/[&<>"']/g, function(ch) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch];
    }); }
    function toast(msg, type) {
        if (window.BSDialog && BSDialog.toast) BSDialog.toast(msg, type || 'info');
    }
    function tr(key, fallback, vars) {
        var msg = window.__ ? window.__(key) : key;
        if (!msg || msg === key) msg = fallback || key;
        Object.keys(vars || {}).forEach(function(name) {
            msg = msg.replace(new RegExp('\\{' + name + '\\}', 'g'), vars[name]);
        });
        return msg;
    }
    function apiJSON(url, options) {
        return csrfFetch(url, options || {}).then(function(resp) {
            return resp.json().then(function(data) {
                if (!resp.ok || !data || data.code !== 0) throw new Error((data && data.message) || tr('task.request_failed', '请求失败'));
                return data;
            });
        });
    }
    function todayISO() {
        var d = new Date();
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    }
    function defaultDueDateISO() {
        var d = new Date();
        d.setDate(d.getDate() + 7);
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    }
    function normalizeDueDate(value) {
        value = String(value || '').trim();
        return value || defaultDueDateISO();
    }
    function setDefaultDueDate(inputID) {
        var input = $(inputID);
        if (input && !input.value) input.value = defaultDueDateISO();
    }
    function bindRequiredDueDate(inputID) {
        var input = $(inputID);
        if (!input || input.__bookstarkRequiredDueDate) return;
        input.__bookstarkRequiredDueDate = true;
        setDefaultDueDate(inputID);
        ['change', 'blur'].forEach(function(type) {
            input.addEventListener(type, function() {
                if (!input.value) input.value = defaultDueDateISO();
            });
        });
    }
    function isOverdue(task) {
        return !task.done && task.due_date && task.due_date <= todayISO();
    }
    function isDueAfterToday(task) {
        return !task.due_date || task.due_date > todayISO();
    }
    function taskURL(parentID) {
        var p = new URLSearchParams();
        var keyword = state.keyword || ($('taskKeyword') ? $('taskKeyword').value.trim() : '');
        if (keyword) p.set('keyword', keyword);
        if (state.selectedDate) p.set('date', state.selectedDate);
        if (state.doneFilter === 'open') p.set('done', 'false');
        if (state.doneFilter === 'done') p.set('done', 'true');
        if (state.dueFilter === 'overdue') p.set('due_before', todayISO());
        if (state.dueFilter === 'upcoming') p.set('due_after', todayISO());
        p.set('parent_id', String(parentID || 0));
        p.set('page_size', '100');
        return '/api/tasks?' + p.toString();
    }
    function loadAll() {
        return loadTasks().then(refreshSharedCalendar);
    }
    function refreshSharedCalendar() {
        if (window.notesApp && typeof window.notesApp.loadCalendarData === 'function') {
            return window.notesApp.loadCalendarData();
        }
        return Promise.resolve();
    }
    function loadTasks() {
        state.keyword = $('taskKeyword') ? $('taskKeyword').value.trim() : '';
        return apiJSON(taskURL(0), { method: 'GET' }).then(function(data) {
            state.tasks = data.data || [];
            renderTasks();
            renderFilterChips();
        }).catch(function(err) { toast(err.message, 'error'); });
    }
    function renderTasks() {
        var list = $('taskList');
        if (!list) return;
        if (!state.tasks.length) {
            list.innerHTML = '<div class="tasks-empty">' + esc(tr('task.empty', '暂无待办')) + '</div>';
            updateCount();
            return;
        }
        state.taskMap = {};
        state.tasks.forEach(function(task) {
            state.taskMap[task.task_id] = task;
        });
        list.innerHTML = state.tasks.map(renderTask).join('');
        updateCount();
    }
    function updateCount() {
        var total = state.tasks.length;
        var open = state.tasks.filter(function(t) { return !t.done; }).length;
        var count = $('taskCount');
        if (count) count.textContent = tr('task.count', '{total} 个待办 · {open} 个未完成', { total: total, open: open });
        updateHeaderCountLabel();
    }
    function updateHeaderCountLabel() {
        var countEl = $('totalCount');
        if (!countEl || !window.notesApp || window.notesApp.activeTab !== 'tasks') return;
        var total = state.tasks.length;
        countEl.textContent = tr('task.header_count', '共 {n} 个', { n: total });
    }
    function renderTask(task) {
        var childSummary = task.child_total ? '<span class="task-pill">' + esc(tr('task.child_summary', '子待办 {done}/{total}', { done: task.child_done || 0, total: task.child_total })) + '</span>' : '';
        var doneLabel = tr('task.status.done', '已完成');
        var openLabel = tr('task.status.open', '未完成');
        return '<article class="task-row' + (task.done ? ' done' : '') + (isOverdue(task) ? ' overdue' : '') + '" data-task-id="' + task.task_id + '">' +
            '<div class="task-tools">' +
                '<button type="button" class="task-icon-btn task-check-btn" data-action="toggle-done" aria-label="' + esc(task.done ? tr('task.action.mark_open', '标记未完成') : tr('task.action.mark_done', '标记完成')) + '"><i class="fa-solid fa-check"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="children" title="' + esc(tr('task.action.children', '子待办')) + '" aria-label="' + esc(tr('task.action.children', '子待办')) + '"><i class="fa-solid fa-list-ul"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="add-child" title="' + esc(tr('task.action.add_child', '添加子待办')) + '" aria-label="' + esc(tr('task.action.add_child', '添加子待办')) + '"><i class="fa-solid fa-plus"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="edit" title="' + esc(tr('task.action.edit', '编辑')) + '" aria-label="' + esc(tr('task.action.edit', '编辑')) + '"><i class="fa-solid fa-pen"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="delete" title="' + esc(tr('task.action.delete', '删除')) + '" aria-label="' + esc(tr('task.action.delete', '删除')) + '"><i class="fa-solid fa-trash-can"></i></button>' +
            '</div>' +
            '<div class="task-body">' +
                '<div class="task-content note-content">' + renderMarkdownContent(task.content) + '</div>' +
            '</div>' +
            '<div class="task-meta">' +
                renderDuePill(task) +
                renderStatusPill(task, doneLabel, openLabel) +
                childSummary +
            '</div>' +
            '<div class="task-children" id="taskChildren-' + task.task_id + '" hidden></div>' +
        '</article>';
    }
    function renderChildTask(child) {
        var doneLabel = tr('task.status.done', '已完成');
        var openLabel = tr('task.status.open', '未完成');
        return '<div class="task-child-row' + (child.done ? ' done' : '') + (isOverdue(child) ? ' overdue' : '') + '" data-task-id="' + child.task_id + '">' +
            '<div class="task-tools child-actions">' +
                '<button type="button" class="task-icon-btn task-check-btn child" data-action="toggle-done" aria-label="' + esc(child.done ? tr('task.action.mark_open', '标记未完成') : tr('task.action.mark_done', '标记完成')) + '"><i class="fa-solid fa-check"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="edit" title="' + esc(tr('task.action.edit', '编辑')) + '" aria-label="' + esc(tr('task.action.edit', '编辑')) + '"><i class="fa-solid fa-pen"></i></button>' +
                '<button type="button" class="task-icon-btn" data-action="delete" title="' + esc(tr('task.action.delete', '删除')) + '" aria-label="' + esc(tr('task.action.delete', '删除')) + '"><i class="fa-solid fa-trash-can"></i></button>' +
            '</div>' +
            '<div class="task-body">' +
                '<div class="task-content note-content">' + renderMarkdownContent(child.content) + '</div>' +
            '</div>' +
            '<div class="task-meta">' +
                renderDuePill(child) +
                renderStatusPill(child, doneLabel, openLabel) +
            '</div>' +
        '</div>';
    }
    function renderStatusPill(task, doneLabel, openLabel) {
        if (task.done) return '<span class="task-pill done">' + esc(doneLabel) + '</span>';
        if (isOverdue(task)) return '<span class="task-pill overdue">' + esc(tr('task.status.overdue', '已过期')) + '</span>';
        return '<span class="task-pill">' + esc(openLabel) + '</span>';
    }
    function renderDuePill(task) {
        if (!task || !task.due_date) return '';
        var label = tr('task.action.set_due', '设置到期时间');
        return '<button type="button" class="task-pill task-due-pill' + (isOverdue(task) ? ' overdue' : '') + '" data-action="edit-due" title="' + esc(label) + '" aria-label="' + esc(label) + '">' +
            '<i class="fa-regular fa-calendar"></i> ' + esc(task.due_date) +
        '</button>';
    }
    function renderChildren(parent, children) {
        var host = $('taskChildren-' + parent.task_id);
        if (!host) return;
        host.hidden = false;
        children.forEach(function(child) {
            state.taskMap[child.task_id] = child;
        });
        var rows = children.length ? children.map(function(child) {
            return renderChildTask(child);
        }).join('') : '<div class="tasks-empty child-empty">' + esc(tr('task.empty.children', '暂无子待办')) + '</div>';
        host.innerHTML = rows;
    }
    function taskMatchesCurrentView(task) {
        if (!task || Number(task.parent_id || 0) !== 0) return false;
        if (state.doneFilter === 'open' && task.done) return false;
        if (state.doneFilter === 'done' && !task.done) return false;
        if (state.dueFilter === 'overdue' && !(task.due_date && task.due_date <= todayISO())) return false;
        if (state.dueFilter === 'upcoming' && !isDueAfterToday(task)) return false;
        if (state.keyword && String(task.content || '').toLowerCase().indexOf(state.keyword.toLowerCase()) === -1) return false;
        if (state.selectedDate && state.selectedDate !== todayISO()) return false;
        return true;
    }
    function normalizeTask(task) {
        task = task || {};
        task.task_id = Number(task.task_id || 0);
        task.parent_id = Number(task.parent_id || 0);
        task.child_total = Number(task.child_total || 0);
        task.child_done = Number(task.child_done || 0);
        task.done = !!task.done;
        return task;
    }
    function mergeTask(oldTask, patch) {
        var merged = {};
        Object.keys(oldTask || {}).forEach(function(key) { merged[key] = oldTask[key]; });
        Object.keys(patch || {}).forEach(function(key) { merged[key] = patch[key]; });
        return normalizeTask(merged);
    }
    function replaceRootTask(task) {
        task = normalizeTask(task);
        state.taskMap[task.task_id] = task;
        var idx = state.tasks.findIndex(function(t) { return Number(t.task_id) === task.task_id; });
        var row = document.querySelector('.task-row[data-task-id="' + task.task_id + '"]');
        if (!taskMatchesCurrentView(task)) {
            if (idx >= 0) state.tasks.splice(idx, 1);
            if (row) row.remove();
            renderEmptyIfNeeded();
            updateCount();
            return;
        }
        if (idx >= 0) state.tasks[idx] = task;
        else state.tasks.unshift(task);
        if (row) {
            var oldChildren = row.querySelector('.task-children');
            var wasExpanded = oldChildren && !oldChildren.hidden;
            var childrenHTML = oldChildren ? oldChildren.innerHTML : '';
            var wrapper = document.createElement('div');
            wrapper.innerHTML = renderTask(task);
            var newRow = wrapper.firstElementChild;
            var newChildren = newRow ? newRow.querySelector('.task-children') : null;
            if (newChildren && wasExpanded) {
                newChildren.hidden = false;
                newChildren.innerHTML = childrenHTML;
            }
            if (newRow) row.replaceWith(newRow);
        } else {
            var list = $('taskList');
            if (list) {
                var empty = list.querySelector('.tasks-empty:not(.child-empty)');
                if (empty) empty.remove();
                list.insertAdjacentHTML('afterbegin', renderTask(task));
            }
        }
        updateCount();
    }
    function replaceChildTask(task) {
        task = normalizeTask(task);
        state.taskMap[task.task_id] = task;
        var row = document.querySelector('.task-child-row[data-task-id="' + task.task_id + '"]');
        if (row) row.outerHTML = renderChildTask(task);
    }
    function renderEmptyIfNeeded() {
        var list = $('taskList');
        if (!list) return;
        if (!state.tasks.length) list.innerHTML = '<div class="tasks-empty">' + esc(tr('task.empty', '暂无待办')) + '</div>';
    }
    function addChildToOpenParent(child) {
        child = normalizeTask(child);
        state.taskMap[child.task_id] = child;
        var host = $('taskChildren-' + child.parent_id);
        if (!host || host.hidden) return;
        var empty = host.querySelector('.child-empty');
        if (empty) empty.remove();
        host.insertAdjacentHTML('beforeend', renderChildTask(child));
    }
    function removeTaskLocally(task) {
        task = normalizeTask(task);
        delete state.taskMap[task.task_id];
        if (task.parent_id) {
            var childRow = document.querySelector('.task-child-row[data-task-id="' + task.task_id + '"]');
            if (childRow) childRow.remove();
            var host = $('taskChildren-' + task.parent_id);
            if (host && !host.hidden && !host.querySelector('.task-child-row')) {
                host.innerHTML = '<div class="tasks-empty child-empty">' + esc(tr('task.empty.children', '暂无子待办')) + '</div>';
            }
            adjustParentChildCount(task.parent_id, -1, task.done ? -1 : 0);
            return;
        }
        state.tasks = state.tasks.filter(function(t) { return Number(t.task_id) !== task.task_id; });
        var row = document.querySelector('.task-row[data-task-id="' + task.task_id + '"]');
        if (row) row.remove();
        renderEmptyIfNeeded();
        updateCount();
    }
    function adjustParentChildCount(parentID, totalDelta, doneDelta) {
        parentID = Number(parentID || 0);
        if (!parentID) return;
        var parent = findTask(parentID);
        if (!parent) return;
        parent = mergeTask(parent, {
            child_total: Math.max(0, Number(parent.child_total || 0) + Number(totalDelta || 0)),
            child_done: Math.max(0, Number(parent.child_done || 0) + Number(doneDelta || 0))
        });
        replaceRootTask(parent);
    }
    function applyLocalTaskUpdate(task, oldTask) {
        task = normalizeTask(task);
        oldTask = normalizeTask(oldTask || findTask(task.task_id) || task);
        if (task.parent_id) {
            replaceChildTask(task);
            if (!!oldTask.done !== !!task.done) adjustParentChildCount(task.parent_id, 0, task.done ? 1 : -1);
            return;
        }
        replaceRootTask(task);
    }
    function handleCreatedTask(task) {
        task = normalizeTask(task);
        if (task.parent_id) {
            addChildToOpenParent(task);
            adjustParentChildCount(task.parent_id, 1, task.done ? 1 : 0);
            return;
        }
        replaceRootTask(task);
    }
    function renderFilterChips() {
        var hasFilter = hasActiveFilter();
        var all = $('taskAllChip');
        var done = $('taskDoneChip');
        var due = $('taskDueChip');
        if (all) {
            all.classList.toggle('active', !hasFilter);
            all.setAttribute('aria-pressed', !hasFilter ? 'true' : 'false');
        }
        if (done) {
            done.classList.toggle('active', state.doneFilter !== null);
            done.setAttribute('aria-pressed', state.doneFilter !== null ? 'true' : 'false');
            if (state.doneFilter === 'open') {
                done.innerHTML = '<i class="fa-regular fa-circle" style="font-size:10px;"></i> ' + esc(tr('task.filter.open', '未完成'));
            } else {
                done.innerHTML = '<i class="fa-solid fa-check" style="font-size:10px;"></i> ' + esc(tr('task.filter.done', '已完成'));
            }
        }
        if (due) {
            due.classList.toggle('active', state.dueFilter !== null);
            due.setAttribute('aria-pressed', state.dueFilter !== null ? 'true' : 'false');
            if (state.dueFilter === 'upcoming') {
                due.innerHTML = '<i class="fa-regular fa-calendar" style="font-size:10px;"></i> ' + esc(tr('task.filter.upcoming', '未过期'));
            } else {
                due.innerHTML = '<i class="fa-regular fa-calendar-check" style="font-size:10px;"></i> ' + esc(tr('task.filter.overdue', '已过期'));
            }
        }
        updateMobileFilterButton();
    }
    function hasActiveFilter() {
        return state.doneFilter !== null || state.dueFilter !== null || !!state.selectedDate;
    }
    function updateMobileFilterButton() {
        var btn = $('mobileFilterBtn');
        if (btn) btn.classList.toggle('has-active', hasActiveFilter());
    }
    function clearFilters() {
        state.doneFilter = null;
        state.dueFilter = null;
        state.selectedDate = null;
        state.keyword = '';
        if ($('taskKeyword')) $('taskKeyword').value = '';
        closeMobileDrawer();
        renderFilterChips();
        loadTasks();
    }
    function toggleDoneFilter() {
        if (state.doneFilter === null) state.doneFilter = 'open';
        else if (state.doneFilter === 'open') state.doneFilter = 'done';
        else state.doneFilter = null;
        renderFilterChips();
        loadTasks();
    }
    function toggleDueFilter() {
        if (state.dueFilter === null) state.dueFilter = 'overdue';
        else if (state.dueFilter === 'overdue') state.dueFilter = 'upcoming';
        else state.dueFilter = null;
        renderFilterChips();
        loadTasks();
    }
    function setSelectedDate(dateStr, opts) {
        opts = opts || {};
        state.selectedDate = dateStr || null;
        renderFilterChips();
        if (opts.reload === false) return Promise.resolve();
        return loadTasks();
    }
    function openTaskSheet(task, defaults) {
        defaults = defaults || {};
        openComposeModal({
            task: task || null,
            parentID: task ? task.parent_id || 0 : defaults.parent_id || 0
        });
    }
    function createTask(content, dueDate, parentID) {
        content = String(content || '').trim();
        dueDate = normalizeDueDate(dueDate);
        if (!content) {
            toast(tr('task.error.empty', '请输入待办内容'), 'warning');
            return Promise.resolve();
        }
        return apiJSON('/api/tasks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ content: content, due_date: dueDate, parent_id: Number(parentID || 0) }),
            lockKey: 'task-create:' + content
        }).then(function(data) {
            toast(parentID ? tr('task.toast.child_added', '子待办已添加') : tr('task.toast.added', '待办已添加'), 'success');
            return data && data.data ? data.data : null;
        });
    }
    function findTask(id) {
        id = Number(id);
        return state.taskMap[id] || null;
    }
    function fetchTask(id) {
        var cached = findTask(id);
        if (cached) return Promise.resolve(cached);
        return apiJSON('/api/tasks/' + encodeURIComponent(id), { method: 'GET' }).then(function(data) {
            return data && data.data ? normalizeTask(data.data) : null;
        });
    }
    function toggleDone(task) {
        return apiJSON('/api/tasks/' + task.task_id + '/done', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ done: !task.done }),
            lockKey: 'task-done:' + task.task_id
        }).then(function() {
            var updated = mergeTask(task, { done: !task.done, modify_time: new Date().toISOString() });
            applyLocalTaskUpdate(updated, task);
            return refreshSharedCalendar();
        }).catch(function(err) { toast(err.message, 'error'); });
    }
    function updateTaskDueDate(task, dueDate) {
        dueDate = normalizeDueDate(dueDate);
        return apiJSON('/api/tasks/' + task.task_id, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                content: task.content || '',
                due_date: dueDate,
                done: !!task.done,
                parent_id: Number(task.parent_id || 0)
            }),
            lockKey: 'task-due:' + task.task_id
        }).then(function() {
            var updated = mergeTask(task, { due_date: dueDate, modify_time: new Date().toISOString() });
            applyLocalTaskUpdate(updated, task);
            toast(tr('task.toast.due_saved', '到期时间已更新'), 'success');
            return refreshSharedCalendar();
        });
    }
    function openDueDatePicker(task, source) {
        if (!source || source.__bookstarkDuePickerOpen) return;
        var currentDue = normalizeDueDate(task.due_date);
        var input = document.createElement('input');
        var closed = false;
        var saving = false;
        input.type = 'date';
        input.value = currentDue;
        input.setAttribute('aria-label', tr('task.action.set_due', '设置到期时间'));
        input.tabIndex = -1;
        input.style.position = 'fixed';
        input.style.left = '-9999px';
        input.style.top = '-9999px';
        input.style.opacity = '0';
        input.style.width = '1px';
        input.style.height = '1px';
        input.style.pointerEvents = 'none';
        source.__bookstarkDuePickerOpen = true;
        document.body.appendChild(input);
        if (typeof source.blur === 'function') source.blur();
        function close(force) {
            if (closed || (saving && !force)) return;
            closed = true;
            source.__bookstarkDuePickerOpen = false;
            if (input.parentNode) input.parentNode.removeChild(input);
        }
        function save(value) {
            value = normalizeDueDate(value);
            input.value = value;
            if (closed || saving) return;
            if (value === currentDue) {
                close(true);
                return;
            }
            saving = true;
            input.disabled = true;
            updateTaskDueDate(task, value).then(function() {
                close(true);
            }).catch(function(err) {
                saving = false;
                toast(err.message, 'error');
                close(true);
            });
        }
        input.addEventListener('change', function() { save(input.value); });
        input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                save(input.value);
            }
            if (e.key === 'Escape') {
                e.preventDefault();
                close(true);
            }
        });
        input.addEventListener('blur', function() {
            setTimeout(function() { close(false); }, 240);
        });
        setTimeout(function() {
            input.focus();
            if (typeof input.showPicker === 'function') {
                try {
                    input.showPicker();
                    return;
                } catch (err) {}
            }
            input.click();
        }, 0);
    }
    function deleteTask(task) {
        var msg = task.child_total ? tr('task.confirm.delete_children', '删除这个待办及其子待办？') : tr('task.confirm.delete', '删除这个待办？');
        var confirm = window.BSDialog && BSDialog.confirm2 ? BSDialog.confirm2(msg) : Promise.resolve(window.confirm(msg));
        confirm.then(function(ok) {
            if (!ok) return;
            return apiJSON('/api/tasks/' + task.task_id, {
                method: 'DELETE',
                lockKey: 'task-delete:' + task.task_id
            }).then(function() {
                removeTaskLocally(task);
                toast(tr('task.toast.deleted', '待办已删除'), 'success');
                return refreshSharedCalendar();
            }).catch(function(err) { toast(err.message, 'error'); });
        });
    }
    function toggleChildren(task, opts) {
        opts = opts || {};
        var host = $('taskChildren-' + task.task_id);
        if (!host) return Promise.resolve();
        if (!host.hidden && host.innerHTML) {
            if (opts.keepOpen) return Promise.resolve();
            host.hidden = true;
            return Promise.resolve();
        }
        return apiJSON('/api/tasks?parent_id=' + encodeURIComponent(task.task_id) + '&page_size=100', { method: 'GET' }).then(function(data) {
            renderChildren(task, data.data || []);
        }).catch(function(err) { toast(err.message, 'error'); });
    }
    function handleTaskAction(e) {
        var btn = e.target.closest('[data-action]');
        if (!btn) return;
        var row = e.target.closest('[data-task-id]');
        var id = row ? Number(row.getAttribute('data-task-id')) : 0;
        var action = btn.getAttribute('data-action');
        fetchTask(id).then(function(task) {
            if (!task) return;
            if (action === 'toggle-done') toggleDone(task);
            if (action === 'children') toggleChildren(task);
            if (action === 'add-child') openTaskSheet(null, { parent_id: task.task_id });
            if (action === 'edit-due') openDueDatePicker(task, btn);
            if (action === 'edit') openTaskSheet(task);
            if (action === 'delete') deleteTask(task);
        });
    }
    function uploadTaskImage(file, composer) {
        if (window.notesApp && typeof window.notesApp.uploadImageFile === 'function') {
            window.notesApp.uploadImageFile(file, composer);
            return;
        }
        toast(tr('task.upload.unavailable', '图片上传不可用'), 'warning');
    }
    function renderMarkdown(text) {
        text = String(text || '').trim();
        if (!text) return '';
        return typeof marked !== 'undefined' ? marked.parse(text) : esc(text);
    }
    function renderMarkdownContent(text) {
        text = String(text || '');
        if (!text) return '';
        return typeof marked !== 'undefined' ? marked.parse(text) : esc(text);
    }
    function setPreviewState(host, preview, btn, composer, active) {
        if (!host || !preview || !btn) return;
        if (active) {
            preview.innerHTML = renderMarkdown(composer ? composer.getValue() : host.textContent || '');
            preview.style.display = 'block';
            host.style.display = 'none';
            btn.innerHTML = '<i class="fa-solid fa-pen"></i>';
            btn.classList.add('active');
        } else {
            preview.style.display = 'none';
            host.style.display = '';
            btn.innerHTML = '<i class="fa-solid fa-file-lines"></i>';
            btn.classList.remove('active');
        }
    }
    function toggleModalPreview() {
        var preview = $('taskModalPreview');
        setPreviewState($('taskModalContent'), preview, $('taskModalPreviewBtn'), taskModalComposer, !(preview && preview.style.display === 'block'));
    }
    function hideModalPreview() {
        setPreviewState($('taskModalContent'), $('taskModalPreview'), $('taskModalPreviewBtn'), taskModalComposer, false);
    }
    function toggleQuickPreview() {
        var preview = $('taskQuickPreview');
        setPreviewState($('taskQuickContent'), preview, $('taskQuickPreviewBtn'), taskQuickComposer, !(preview && preview.style.display === 'block'));
    }
    function hideQuickPreview() {
        setPreviewState($('taskQuickContent'), $('taskQuickPreview'), $('taskQuickPreviewBtn'), taskQuickComposer, false);
    }
    function initComposer(hostID, opts) {
        opts = opts || {};
        var host = $(hostID);
        if (!host) return null;
        if (window.MarkdownComposer) {
            return window.MarkdownComposer.create(host, {
                placeholder: host.getAttribute('data-placeholder') || '',
                ariaLabel: host.getAttribute('data-placeholder') || '',
                minHeight: opts.minHeight || 96,
                maxHeight: opts.maxHeight || 240,
                submitOnCtrlEnter: true,
                onPasteFile: function(file) { uploadTaskImage(file, opts.getComposer ? opts.getComposer() : null); },
                onSubmit: opts.onSubmit
            });
        }
        host.setAttribute('contenteditable', 'true');
        host.setAttribute('role', 'textbox');
        host.setAttribute('aria-label', host.getAttribute('data-placeholder') || tr('task.aria.content', '待办内容'));
        return null;
    }
    function initModalComposer() {
        if (taskModalComposer) return;
        taskModalComposer = initComposer('taskModalContent', {
            minHeight: 320,
            maxHeight: 9999,
            getComposer: function() { return taskModalComposer; },
            onSubmit: submitModalTask
        });
    }
    function initQuickComposer() {
        var host = $('taskQuickContent');
        if (!host || taskQuickComposer) return;
        taskQuickComposer = initComposer('taskQuickContent', {
            getComposer: function() { return taskQuickComposer; },
            onSubmit: function() {
                var form = $('taskQuickCreate');
                if (form && typeof form.requestSubmit === 'function') form.requestSubmit();
            }
        });
    }
    function toggleEmoji(buttonID, composer, source) {
        var btn = $(buttonID);
        if (!btn || !window.notesApp || typeof window.notesApp._toggleEmojiPicker !== 'function') return;
        window.notesApp._toggleEmojiPicker(btn, composer, source);
    }
    function openComposeModal(opts) {
        opts = opts || {};
        initModalComposer();
        hideQuickPreview();
        hideModalPreview();
        state.editingTask = opts.task || null;
        state.modalParentID = Number(opts.parentID || 0);
        state.modalFromQuick = !!opts.fromQuick;
        var quickContent = state.modalFromQuick ? getQuickContent() : '';
        var quickDueDate = state.modalFromQuick && $('taskQuickDueDate') ? $('taskQuickDueDate').value : '';
        var content = state.editingTask ? state.editingTask.content || '' : quickContent;
        var dueDate = state.editingTask ? normalizeDueDate(state.editingTask.due_date) : normalizeDueDate(quickDueDate);
        var title = state.editingTask ? tr('task.edit.title', '编辑待办') : (state.modalParentID ? tr('task.new_child.title', '新建子待办') : tr('task.new.title', '新建待办'));
        var titleEl = $('taskComposeModalTitle');
        var submitBtn = $('taskModalSubmitBtn');
        if (titleEl) titleEl.textContent = title;
        if (submitBtn) submitBtn.textContent = state.editingTask ? tr('task.submit.save', '保存') : tr('task.submit.add', '添加');
        if (taskModalComposer) taskModalComposer.setValue(content);
        else if ($('taskModalContent')) $('taskModalContent').textContent = content;
        if ($('taskModalDueDate')) $('taskModalDueDate').value = dueDate;
        var overlay = $('taskComposeOverlay');
        if (!overlay) return;
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('task-compose-modal');
        setTimeout(function() {
            if (taskModalComposer) taskModalComposer.focus();
        }, 80);
    }
    function closeComposeModal() {
        var overlay = $('taskComposeOverlay');
        if (overlay) overlay.classList.remove('active');
        state.editingTask = null;
        state.modalParentID = 0;
        state.modalFromQuick = false;
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('task-compose-modal');
    }
    function getQuickContent() {
        if (taskQuickComposer) return taskQuickComposer.getValue();
        var host = $('taskQuickContent');
        return host ? host.textContent || '' : '';
    }
    function getTaskAIParentContext() {
        var parentID = 0;
        if (state.editingTask && state.editingTask.parent_id) parentID = Number(state.editingTask.parent_id || 0);
        else parentID = Number(state.modalParentID || 0);
        if (!parentID) return '';
        var parent = findTask(parentID);
        if (!parent || !parent.content) return '';
        return tr('task.ai.parent_context', '父待办：\n{content}', { content: parent.content });
    }
    function _parseTaskAIActions(raw) {
        return String(raw || '').split(/\r?\n/).map(function(line) {
            line = line.trim();
            if (!line || line.charAt(0) === '#') return null;
            var idx = line.indexOf('|');
            if (idx < 0) return null;
            var label = line.slice(0, idx).trim();
            var prompt = line.slice(idx + 1).trim();
            if (!label || !prompt) return null;
            return { label: label, prompt: prompt };
        }).filter(Boolean);
    }
    function _getTaskAIActions() {
        var actions = _parseTaskAIActions(window.TASK_AI_ACTIONS_RAW || '');
        if (actions.length) return actions;
        return [
            { label: '整理待办', prompt: '把这段内容整理成一个清晰、可执行的待办。要求：动词开头，保留关键约束，去掉废话，只返回待办内容。' },
            { label: '拆成子待办', prompt: '把这件事拆成 3-7 个可执行子待办。每个子待办要具体、可完成、不要太宽泛。只返回 Markdown checklist。' },
            { label: '改成今日可做', prompt: '把这件事压缩成今天可以完成的一小步。如果原任务太大，只保留最小可推进动作。只返回一个待办。' },
            { label: '生成验收标准', prompt: '为当前待办生成 2-5 条完成验收标准。要求可判断、可检查。只返回 Markdown checklist。' }
        ];
    }
    function openTaskAI() {
        if (!window.AI_ENABLED || !window.notesApp || typeof window.notesApp._openInlineAIPrompt !== 'function') {
            toast(tr('task.ai.disabled', 'AI 助手未开启'), 'warning');
            return;
        }
        var overlay = $('taskComposeOverlay');
        var modalOpen = overlay && overlay.classList.contains('active');
        var composer = modalOpen ? taskModalComposer : taskQuickComposer;
        if (!composer) return;
        window.notesApp._openInlineAIPrompt(composer, '', {
            contextPrefix: getTaskAIParentContext(),
            emptyText: tr('task.ai.empty_text', '空待办，将在当前光标位置插入。'),
            scene: 'task',
            systemPrompt: tr('task.ai.system_prompt', '你是一个待办助手。请把用户输入整理成清晰、可执行的中文待办内容。适合写入 Markdown 待办输入框。只返回待办内容，不要解释。'),
            quickActions: _getTaskAIActions()
        });
    }
    function clearQuickCreate() {
        hideQuickPreview();
        if (taskQuickComposer) taskQuickComposer.clear();
        else if ($('taskQuickContent')) $('taskQuickContent').textContent = '';
        if ($('taskQuickDueDate')) $('taskQuickDueDate').value = defaultDueDateISO();
    }
    function clearModalCreate() {
        hideModalPreview();
        if (taskModalComposer) taskModalComposer.clear();
        else if ($('taskModalContent')) $('taskModalContent').textContent = '';
        if ($('taskModalDueDate')) $('taskModalDueDate').value = defaultDueDateISO();
    }
    function getModalContent() {
        if (taskModalComposer) return taskModalComposer.getValue();
        return $('taskModalContent') ? $('taskModalContent').textContent || '' : '';
    }
    function quickCreate(e) {
        e.preventDefault();
        var content = getQuickContent();
        var dueDate = normalizeDueDate($('taskQuickDueDate') ? $('taskQuickDueDate').value : '');
        if ($('taskQuickDueDate')) $('taskQuickDueDate').value = dueDate;
        createTask(content, dueDate, 0).then(function(task) {
            if (!task) return;
            handleCreatedTask(task);
            clearQuickCreate();
            return refreshSharedCalendar();
        }).catch(function(err) { toast(err.message, 'error'); });
    }
    function submitModalTask() {
        var content = getModalContent();
        var dueDate = normalizeDueDate($('taskModalDueDate') ? $('taskModalDueDate').value : '');
        if ($('taskModalDueDate')) $('taskModalDueDate').value = dueDate;
        content = String(content || '').trim();
        if (!content) {
            toast(tr('task.error.empty', '请输入待办内容'), 'warning');
            return;
        }
        var editing = state.editingTask;
        var submitBtn = $('taskModalSubmitBtn');
        if (submitBtn) submitBtn.disabled = true;
        var request = editing ? apiJSON('/api/tasks/' + editing.task_id, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                content: content,
                due_date: dueDate,
                done: !!editing.done,
                parent_id: Number(editing.parent_id || 0)
            }),
            lockKey: 'task-save:' + editing.task_id
        }) : createTask(content, dueDate, state.modalParentID);
        request.then(function(task) {
            if (editing) {
                applyLocalTaskUpdate(mergeTask(editing, {
                    content: content,
                    due_date: dueDate,
                    modify_time: new Date().toISOString()
                }), editing);
                toast(tr('task.toast.saved', '待办已保存'), 'success');
            } else if (task) {
                handleCreatedTask(task);
            }
            return refreshSharedCalendar();
        }).then(function() {
            clearModalCreate();
            if (state.modalFromQuick) clearQuickCreate();
            closeComposeModal();
        }).catch(function(err) {
            toast(err.message, 'error');
        }).finally(function() {
            if (submitBtn) submitBtn.disabled = false;
        });
    }
    function toggleComposeMaximized() {
        var modal = document.querySelector('#taskComposeOverlay .asset-modal');
        var btn = $('taskComposeMaximizeBtn');
        if (!modal || !btn) return;
        var maximized = !modal.classList.contains('is-maximized');
        modal.classList.toggle('is-maximized', maximized);
        btn.setAttribute('aria-pressed', maximized ? 'true' : 'false');
        btn.innerHTML = '<i class="fa-solid ' + (maximized ? 'fa-compress' : 'fa-expand') + '"></i>';
    }
    function openDatePicker(inputID) {
        var input = $(inputID);
        if (!input) return;
        input.focus();
        if (typeof input.showPicker === 'function') input.showPicker();
    }
    function openMobileDrawer() {
        if ($('taskMobileDrawer')) $('taskMobileDrawer').classList.add('active');
        if ($('taskMobileDrawerOverlay')) $('taskMobileDrawerOverlay').classList.add('active');
    }
    function closeMobileDrawer() {
        if ($('taskMobileDrawer')) $('taskMobileDrawer').classList.remove('active');
        if ($('taskMobileDrawerOverlay')) $('taskMobileDrawerOverlay').classList.remove('active');
    }
    function ensureRootTaskVisible(task) {
        task = normalizeTask(task);
        var exists = state.tasks.some(function(t) { return Number(t.task_id) === task.task_id; });
        state.taskMap[task.task_id] = task;
        if (!exists) {
            state.tasks.unshift(task);
            renderTasks();
        }
    }
    function highlightTask(id) {
        id = Number(id || 0);
        if (!id) return;
        var row = document.querySelector('[data-task-id="' + id + '"]');
        if (!row) return;
        document.querySelectorAll('.task-row.is-located, .task-child-row.is-located').forEach(function(el) {
            el.classList.remove('is-located');
        });
        row.classList.add('is-located');
        row.scrollIntoView({ block: 'center', behavior: 'smooth' });
        setTimeout(function() { row.classList.remove('is-located'); }, 3200);
    }
    function locateTask(id) {
        id = Number(id || 0);
        if (!id) return Promise.resolve();
        state.doneFilter = null;
        state.dueFilter = null;
        state.selectedDate = null;
        state.keyword = '';
        if ($('taskKeyword')) $('taskKeyword').value = '';
        renderFilterChips();
        return fetchTask(id).then(function(target) {
            if (!target) return;
            var parentPromise = target.parent_id ? fetchTask(target.parent_id) : Promise.resolve(target);
            return parentPromise.then(function(parent) {
                if (!parent) parent = target;
                return loadTasks().then(function() {
                    ensureRootTaskVisible(parent);
                    if (target.parent_id) {
                        return toggleChildren(parent, { keepOpen: true }).then(function() { highlightTask(target.task_id); });
                    }
                    highlightTask(target.task_id);
                });
            });
        }).catch(function(err) { toast(err.message || tr('task.locate.failed', '定位待办失败'), 'error'); });
    }
    function bind() {
        initQuickComposer();
        initModalComposer();
        bindRequiredDueDate('taskQuickDueDate');
        bindRequiredDueDate('taskModalDueDate');
        var quickForm = $('taskQuickCreate');
        if (quickForm) {
            quickForm.addEventListener('submit', quickCreate);
            $('taskQuickClear').addEventListener('click', clearQuickCreate);
            $('taskQuickImageBtn').addEventListener('click', function() { $('taskQuickFileInput').click(); });
            $('taskQuickFileInput').addEventListener('change', function(e) {
                if (e.target.files && e.target.files[0]) uploadTaskImage(e.target.files[0], taskQuickComposer);
                e.target.value = '';
            });
            $('taskQuickEmojiBtn').addEventListener('click', function() { toggleEmoji('taskQuickEmojiBtn', taskQuickComposer, 'taskQuick'); });
            $('taskQuickPreviewBtn').addEventListener('click', toggleQuickPreview);
            $('taskQuickExpandBtn').addEventListener('click', function() { openComposeModal({ fromQuick: true }); });
        }
        if ($('newTaskBtn')) {
            $('newTaskBtn').addEventListener('click', function() { openTaskSheet(null); });
        }
        $('newTaskFab').addEventListener('click', function() { openTaskSheet(null); });
        $('taskSearchBtn').addEventListener('click', loadTasks);
        if ($('taskQuickAIButton')) {
            $('taskQuickAIButton').addEventListener('click', openTaskAI);
        }
        if ($('taskModalAIButton')) {
            $('taskModalAIButton').addEventListener('click', openTaskAI);
        }
        $('taskKeyword').addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                loadTasks();
            }
        });
        $('taskAllChip').addEventListener('click', clearFilters);
        $('taskDoneChip').addEventListener('click', toggleDoneFilter);
        $('taskDueChip').addEventListener('click', toggleDueFilter);
        $('taskMobileDrawerClose').addEventListener('click', closeMobileDrawer);
        $('taskMobileDrawerOverlay').addEventListener('click', closeMobileDrawer);
        $('taskModalImageBtn').addEventListener('click', function() { $('taskModalFileInput').click(); });
        $('taskModalFileInput').addEventListener('change', function(e) {
            if (e.target.files && e.target.files[0]) uploadTaskImage(e.target.files[0], taskModalComposer);
            e.target.value = '';
        });
        $('taskModalEmojiBtn').addEventListener('click', function() { toggleEmoji('taskModalEmojiBtn', taskModalComposer, 'taskModal'); });
        $('taskModalPreviewBtn').addEventListener('click', toggleModalPreview);
        $('taskModalClearBtn').addEventListener('click', clearModalCreate);
        $('taskModalSubmitBtn').addEventListener('click', submitModalTask);
        $('taskComposeMaximizeBtn').addEventListener('click', toggleComposeMaximized);
        document.querySelectorAll('[data-date-picker]').forEach(function(el) {
            el.addEventListener('click', function(e) {
                e.preventDefault();
                openDatePicker(el.getAttribute('data-date-picker'));
            });
        });
        $('taskList').addEventListener('click', handleTaskAction);
    }
    function applyCommand() {
        var params = new URLSearchParams(window.location.search);
        if (params.get('command') === 'new-task') openTaskSheet(null);
        if (params.get('task_id')) locateTask(params.get('task_id'));
    }

    document.addEventListener('DOMContentLoaded', function() {
        bind();
        loadAll().then(applyCommand);
    });

    window.BookStarkTasks = {
        openTask: openTaskSheet,
        reload: loadAll,
        setDate: setSelectedDate,
        updateCountLabel: updateHeaderCountLabel,
        updateFilterButton: updateMobileFilterButton,
        openMobileDrawer: openMobileDrawer,
        closeMobileDrawer: closeMobileDrawer,
        closeComposeModal: closeComposeModal,
        locateTask: locateTask
    };
})();
