import '../../core/task_draft_save_context.dart';
import 'task_editor_action_route.dart';
import '../../core/task_action_drafts.dart';

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/task_card.dart';

import 'task_editor_page.dart';

import 'package:bookstark_flutter/features/tasks/task_month_grid.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.repository,
    this.vault,
    this.attachments,
    this.english = false,
    this.parent,
    this.calendar = false,
    this.clock,
    this.actions,
    this.editorActionsFactory,
    this.isCurrentScope,
    this.recoverCreation,
  }) : assert(!calendar || parent == null);
  final TasksRepository repository;
  final Future<void> Function()? recoverCreation;
  final bool Function()? isCurrentScope;
  final TaskEditorActionBindings? actions;
  final TaskEditorActionsFactory? editorActionsFactory;
  final TaskDraftVault? vault;
  final AttachmentRepository? attachments;
  final bool english, calendar;
  final TaskItem? parent;
  final DateTime Function()? clock;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final Set<int> _operating = {}, _writing = {};
  List<TaskItem> _items = [];
  int _page = 1, _total = 0, _generation = 0;
  bool _fetching = false,
      _hasMore = false,
      _opening = false,
      _refreshRequired = false;
  bool? _done;
  String _dueOn = '', _dueBefore = '', _dueAfter = '', _modifiedOn = '';
  String? _error;
  late DateTime _month;
  Future<List<TaskDailyCount>>? _counts;
  String t(String zh, String en) => widget.english ? en : zh;
  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  bool get _current => mounted && (widget.isCurrentScope?.call() ?? true);
  bool get _canAct => _current && _operating.isEmpty && !_refreshRequired;
  Object get _actionQuery => (
    _search.text,
    _done,
    _dueOn,
    _dueBefore,
    _dueAfter,
    _modifiedOn,
    widget.calendar,
    widget.parent?.id,
  );
  TaskEditorActionsFactory? _routeFactory() {
    final factory = widget.editorActionsFactory;
    if (factory == null) return null;
    final repository = widget.repository,
        generation = _generation,
        query = _actionQuery;
    return ({required isCurrent, required abortTrigger}) => factory(
      isCurrent: () =>
          isCurrent() &&
          mounted &&
          identical(factory, widget.editorActionsFactory) &&
          identical(repository, widget.repository) &&
          generation == _generation &&
          query == _actionQuery,
      abortTrigger: abortTrigger,
    );
  }

  TaskEditorActionBindings? _routeActions() {
    final binding = widget.actions;
    if (binding == null) return null;
    final repository = widget.repository,
        generation = _generation,
        query = _actionQuery;
    return binding.guarded(
      () =>
          mounted &&
          identical(widget.actions, binding) &&
          identical(widget.repository, repository) &&
          generation == _generation &&
          query == _actionQuery,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _done = widget.calendar || widget.parent != null ? null : false;
    final now = _now();
    _month = DateTime(now.year, now.month);
    if (widget.calendar) {
      _modifiedOn = taskDate(now);
      _counts = widget.repository.dailyCounts(_month.year, _month.month);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.parent?.id != widget.parent?.id ||
        oldWidget.calendar != widget.calendar) {
      _generation++;
      _operating.clear();
      _writing.clear();
      _items = [];
      _opening = false;
      _fetching = false;
      _refreshRequired = false;
      _page = 1;
      _total = 0;
      _hasMore = false;
      _error = null;
      _search.clear();
      _done = widget.calendar || widget.parent != null ? null : false;
      _dueOn = '';
      _dueBefore = '';
      _dueAfter = '';
      _modifiedOn = widget.calendar ? taskDate(_now()) : '';
      _counts = widget.calendar
          ? widget.repository.dailyCounts(_month.year, _month.month)
          : null;
      _load();
    }
  }

  TaskQuery _query(int page) => TaskQuery(
    keyword: _search.text,
    done: _done,
    parentId: widget.parent?.id,
    dueOn: _dueOn,
    dueBefore: _dueBefore,
    dueAfter: _dueAfter,
    modifiedOn: _modifiedOn,
    page: page,
  );
  Future<bool?> _load({bool next = false, bool refreshLoaded = false}) async {
    if (!_current) return null;
    final repository = widget.repository;
    bool owner() => _current && identical(repository, widget.repository);
    if (next && (_fetching || !_hasMore)) return null;
    final generation = ++_generation;
    final firstPage = next ? _page + 1 : 1;
    final lastPage = refreshLoaded ? _page : firstPage;
    final base = _query(firstPage);
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final fresh = <TaskItem>[];
      TaskPage? result;
      for (var page = firstPage; page <= lastPage; page++) {
        if (!owner()) return null;
        result = await repository.list(
          TaskQuery(
            keyword: base.keyword,
            done: base.done,
            parentId: base.parentId,
            dueOn: base.dueOn,
            dueBefore: base.dueBefore,
            dueAfter: base.dueAfter,
            modifiedOn: base.modifiedOn,
            page: page,
            pageSize: base.pageSize,
          ),
        );
        if (!owner() || generation != _generation) return null;
        final ids = fresh.map((item) => item.id).toSet();
        fresh.addAll(result.items.where((item) => ids.add(item.id)));
        if (!result.hasMore) break;
      }
      if (!owner() || generation != _generation || result == null) return null;
      setState(() {
        final ids = next ? _items.map((item) => item.id).toSet() : <int?>{};
        _items = next
            ? [..._items, ...fresh.where((item) => ids.add(item.id))]
            : fresh;
        _total = result!.total;
        _page = result.page;
        _hasMore = result.hasMore;
        _refreshRequired = false;
      });
      return true;
    } catch (error) {
      if (owner() && generation == _generation) {
        setState(() => _error = error.toString());
      }
      return generation == _generation ? false : null;
    } finally {
      if (owner() && generation == _generation) {
        setState(() => _fetching = false);
      }
    }
  }

  void _refreshCounts() {
    if (!widget.calendar || !mounted) return;
    final future = widget.repository.dailyCounts(_month.year, _month.month);
    setState(() {
      _counts = future;
    });
  }

  Future<void> _refresh() async {
    _refreshCounts();
    await _load(refreshLoaded: true);
  }

  Future<void> _write(TaskItem task, Future<void> Function() action) async {
    final id = task.id!, repository = widget.repository;
    bool owned() => _current && identical(repository, widget.repository);
    if (!owned() || _operating.contains(id) || _refreshRequired) return;
    setState(() {
      _operating.add(id);
      _writing.add(id);
      _error = null;
    });
    try {
      await action();
      if (!owned()) return;
      setState(() => _writing.remove(id));
      _refreshCounts();
      final refreshed = await _load(refreshLoaded: true);
      if (owned() && refreshed == false) {
        setState(() {
          _refreshRequired = true;
          _error =
              '${t('操作已完成，但刷新失败；请刷新后再操作。', 'The change was saved, but refreshing failed. Refresh before making another change.')}\n${_error ?? ''}';
        });
      }
    } catch (error) {
      if (owned()) {
        setState(() {
          _refreshRequired = true;
          _error = error.toString();
        });
      }
    } finally {
      if (owned()) {
        setState(() {
          _writing.remove(id);
          _operating.remove(id);
        });
      }
    }
  }

  void _toggle(TaskItem task, bool done) {
    if (!_canAct) return;
    final repository = widget.repository;
    _write(task, () => repository.setDone(task.id!, done));
  }

  Future<void> _remove(TaskItem task) async {
    if (!_canAct) return;
    final repository = widget.repository, generation = _generation;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('移到回收站？', 'Move to trash?')),
        content: Text(
          t(
            '会将此待办及全部子待办一起移到回收站。',
            'This task and all its descendants will be moved to trash.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('移到回收站', 'Move to trash')),
          ),
        ],
      ),
    );
    if (_current &&
        yes == true &&
        generation == _generation &&
        identical(repository, widget.repository)) {
      await _write(task, () => repository.remove(task.id!));
    }
  }

  Future<void> _edit({TaskItem? task, TaskItem? parent}) async {
    if (_opening || !_canAct) return;
    _opening = true;
    final repository = widget.repository;
    bool owned() => _current && identical(repository, widget.repository);
    try {
      if (task == null &&
          repository is TaskDraftSaveRepository &&
          await (repository as TaskDraftSaveRepository)
              .hasRetainedTaskCreation()) {
        if (!mounted || !owned()) return;
        final recover = widget.recoverCreation;
        if (recover == null)
          throw StateError('Retained task creation requires readonly recovery');
        await recover();
        return;
      }
      if (!mounted || !owned()) return;
      final now = _now();
      final content = task == null
          ? TaskItem(
              content: '',
              dueDate: taskDate(DateTime(now.year, now.month, now.day + 7)),
              parentId: parent?.id ?? widget.parent?.id ?? 0,
              topicId: parent?.topicId ?? widget.parent?.topicId,
            )
          : await repository.read(task.id!);
      if (!owned()) return;
      final routeFactory = _routeFactory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ownedTaskEditorRoute(
            factory: routeFactory,
            english: widget.english,
            builder: (ownedActions) => TaskEditorPage(
              onCreationRecovery: widget.recoverCreation,
              repository: repository,
              task: content,
              vault: widget.vault,
              attachments: widget.attachments,
              english: widget.english,
              clock: widget.clock,
              actions: ownedActions ?? _routeActions(),
            ),
          ),
        ),
      );
      if (owned()) {
        _refreshCounts();
        await _load(refreshLoaded: true);
      }
    } catch (error) {
      if (owned()) setState(() => _error = error.toString());
    } finally {
      if (owned()) _opening = false;
    }
  }

  Future<void> _parent(int id) async {
    if (_opening || !_canAct) return;
    _opening = true;
    final repository = widget.repository;
    bool owned() => _current && identical(repository, widget.repository);
    try {
      final task = await repository.read(id);
      if (!owned()) return;
      final routeFactory = _routeFactory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ownedTaskEditorRoute(
            factory: routeFactory,
            english: widget.english,
            builder: (ownedActions) => TaskEditorPage(
              onCreationRecovery: widget.recoverCreation,
              repository: repository,
              task: task,
              vault: widget.vault,
              attachments: widget.attachments,
              english: widget.english,
              clock: widget.clock,
              actions: ownedActions ?? _routeActions(),
            ),
          ),
        ),
      );
      if (owned()) {
        _refreshCounts();
        await _load(refreshLoaded: true);
      }
    } catch (error) {
      if (owned()) setState(() => _error = error.toString());
    } finally {
      if (owned()) _opening = false;
    }
  }

  Future<void> _children(TaskItem task) async {
    if (_opening || !_canAct) return;
    _opening = true;
    final repository = widget.repository;
    bool owned() => _current && identical(repository, widget.repository);
    try {
      final routeFactory = _routeFactory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TasksPage(
            recoverCreation: widget.recoverCreation,
            isCurrentScope: owned,
            repository: repository,
            parent: task,
            vault: widget.vault,
            attachments: widget.attachments,
            english: widget.english,
            clock: widget.clock,
            actions: _routeActions(),
            editorActionsFactory: routeFactory,
          ),
        ),
      );
      if (owned()) {
        _refreshCounts();
        await _load(refreshLoaded: true);
      }
    } finally {
      if (owned()) _opening = false;
    }
  }

  Future<void> _calendar() async {
    if (_opening || !_canAct) return;
    _opening = true;
    final repository = widget.repository;
    bool owned() => _current && identical(repository, widget.repository);
    try {
      final routeFactory = _routeFactory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TasksPage(
            recoverCreation: widget.recoverCreation,
            isCurrentScope: owned,
            repository: repository,
            calendar: true,
            vault: widget.vault,
            attachments: widget.attachments,
            english: widget.english,
            clock: widget.clock,
            actions: _routeActions(),
            editorActionsFactory: routeFactory,
          ),
        ),
      );
      if (owned()) await _load(refreshLoaded: true);
    } finally {
      if (owned()) _opening = false;
    }
  }

  Future<void> _dueFilter(String value) async {
    if (_operating.isNotEmpty) return;
    final now = _now();
    final today = taskDate(now);
    String selected = '';
    if (value == 'pick') {
      FocusManager.instance.primaryFocus?.unfocus();
      final date = await showDatePicker(
        context: context,
        initialDate: validTaskDate(_dueOn) ? DateTime.parse(_dueOn) : now,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
        helpText: t('按截止日期筛选', 'Filter by due date'),
      );
      if (!mounted || date == null) return;
      selected = taskDate(date);
    }
    if (!mounted) return;
    setState(() {
      _dueOn = value == 'today' ? today : selected;
      _dueBefore = value == 'before' ? today : '';
      _dueAfter = value == 'after' ? today : '';
    });
    await _load();
  }

  void _monthChanged(int delta) {
    final value = DateTime(_month.year, _month.month + delta);
    if (value.year < 1 || value.year > 9999 || _operating.isNotEmpty) return;
    setState(() {
      _month = value;
      _modifiedOn = taskDate(value);
      _counts = widget.repository.dailyCounts(value.year, value.month);
    });
    _load();
  }

  Widget _calendarHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        t('按修改日期统计 · 全部状态', 'Modified date · all statuses'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<TaskDailyCount>>(
        future: _counts,
        builder: (context, snapshot) => Column(
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              const LinearProgressIndicator(),
            if (snapshot.hasError)
              MaterialBanner(
                content: Text(snapshot.error.toString()),
                actions: [
                  TextButton(
                    onPressed: _refreshCounts,
                    child: Text(t('重试计数', 'Retry counts')),
                  ),
                ],
              ),
            TaskMonthGrid(
              month: _month,
              selected: _modifiedOn,
              counts: snapshot.data ?? const [],
              english: widget.english,
              loading: snapshot.connectionState != ConnectionState.done,
              countsUnavailable: snapshot.hasError,
              enabled: _operating.isEmpty,
              onPrevious: () => _monthChanged(-1),
              onNext: () => _monthChanged(1),
              onDay: (day) {
                if (_operating.isNotEmpty) return;
                setState(() => _modifiedOn = taskDate(day));
                _load();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        t(
          '这里统计修改记录，与截止日期筛选独立。',
          'These counts use modification dates. Due dates are filtered separately.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Text(
        _modifiedOn.isEmpty
            ? t('全部日期 · 修改记录', 'All modification dates')
            : t('$_modifiedOn · 修改记录', 'Modified on $_modifiedOn'),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('task-search'),
        controller: _search,
        enabled: _operating.isEmpty,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _load(),
        decoration: InputDecoration(
          hintText: t('搜索待办', 'Search tasks'),
          prefixIcon: const Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 328 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in <bool?, String>{
                  false: t('未完成', 'Open'),
                  null: t('全部', 'All'),
                  true: t('已完成', 'Completed'),
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _done == entry.key,
                    onSelected: _operating.isNotEmpty
                        ? null
                        : (_) {
                            setState(() => _done = entry.key);
                            _load();
                          },
                  ),
              ],
            );
          }
          return SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'open', label: Text(t('未完成', 'Open'))),
              ButtonSegment(value: 'all', label: Text(t('全部', 'All'))),
              ButtonSegment(value: 'done', label: Text(t('已完成', 'Completed'))),
            ],
            selected: {
              _done == null
                  ? 'all'
                  : _done!
                  ? 'done'
                  : 'open',
            },
            onSelectionChanged: _operating.isNotEmpty
                ? null
                : (values) {
                    setState(
                      () => _done = values.single == 'all'
                          ? null
                          : values.single == 'done',
                    );
                    _load();
                  },
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              side: WidgetStatePropertyAll(
                BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .1)
                    : Theme.of(context).colorScheme.surface,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      PopupMenuButton<String>(
        enabled: _operating.isEmpty,
        onSelected: _dueFilter,
        itemBuilder: (_) => [
          for (final entry in {
            'all': t('所有日期', 'All due dates'),
            'today': t('今天截止', 'Due today'),
            'before': t('今天及以前', 'Due today or earlier'),
            'after': t('今天以后', 'Due after today'),
            'pick': t('选择截止日期', 'Choose due date'),
          }.entries)
            PopupMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        child: Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              _dueOn.isNotEmpty
                  ? t('截止：$_dueOn', 'Due: $_dueOn')
                  : _dueBefore.isNotEmpty
                  ? t('今天及以前', 'Due today or earlier')
                  : _dueAfter.isNotEmpty
                  ? t('今天以后', 'Due after today')
                  : t('所有日期', 'All due dates'),
            ),
          ),
        ),
      ),
      if (widget.parent != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            t('父待办：', 'Parent task: ') +
                widget.parent!.content.split('\n').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      const SizedBox(height: 8),
      Text(
        t(
          '按截止日期分组 · 已加载${_items.length}/$_total条',
          'Grouped by due date · ${_items.length}/$_total loaded',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
    ],
  );
  List<Widget> _cards() {
    final byId = {for (final item in _items) item.id: item};
    final nested = <int, List<TaskItem>>{};
    final hiddenIds = <int>{};
    for (final item in _items) {
      final parent = byId[item.parentId];
      if (parent != null &&
          parent.parentId == 0 &&
          parent.dueDate == item.dueDate) {
        nested.putIfAbsent(parent.id!, () => []).add(item);
        hiddenIds.add(item.id!);
      }
    }
    final groups = SplayTreeMap<String, List<TaskItem>>(
      (a, b) => a.isEmpty
          ? (b.isEmpty ? 0 : 1)
          : b.isEmpty
          ? -1
          : a.compareTo(b),
    );
    for (final item in _items.where((item) => !hiddenIds.contains(item.id))) {
      groups.putIfAbsent(item.dueDate, () => []).add(item);
    }
    final today = taskDate(_now());
    final widgets = <Widget>[];
    var futureHeading = false;
    for (final entry in groups.entries) {
      if (!widget.calendar) {
        final upcoming =
            validTaskDate(entry.key) && entry.key.compareTo(today) > 0;
        if (!upcoming || !futureHeading) {
          final day = validTaskDate(entry.key)
              ? DateTime.parse(entry.key)
              : null;
          final todayLabel = widget.english
              ? MaterialLocalizations.of(context).formatShortDate(_now())
              : '${_now().month}月${_now().day}日';
          final label = entry.key.isEmpty
              ? t('未设置截止日期', 'No due date')
              : day == null
              ? t('日期待检查', 'Date needs review')
              : entry.key == today
              ? t('今天 · $todayLabel', 'Today · $todayLabel')
              : upcoming
              ? t('接下来', 'Upcoming')
              : _done == false
              ? t('逾期 · ${entry.key}', 'Overdue · ${entry.key}')
              : entry.key;
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        if (upcoming) futureHeading = true;
      }
      for (final item in entry.value) {
        widgets.add(
          TaskCard(
            task: item,
            children: nested[item.id] ?? const [],
            busyIds: _operating,
            english: widget.english,
            enableActions: _canAct,
            allowStatusChanges: !_refreshRequired,
            showParent: widget.parent == null,
            attachments: widget.attachments,
            onToggle: _toggle,
            onEdit: (task) => _edit(task: task),
            onAddChild: (task) => _edit(parent: task),
            onChildren: _children,
            onRemove: _remove,
            onParent: _parent,
          ),
        );
      }
    }
    return widgets;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_opening &&
        _operating.isEmpty &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _writing.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('正在更新，请稍候', 'Updating. Please wait.'))),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.calendar
              ? t('待办日历', 'Task calendar')
              : widget.parent != null
              ? t('子待办', 'Subtasks')
              : t('行动 · 待办', 'Actions · Tasks'),
        ),
        actions: [
          if (widget.recoverCreation != null)
            IconButton(
              onPressed: _canAct ? widget.recoverCreation : null,
              tooltip: t('恢复待办创建', 'Recover task creation'),
              icon: const Icon(Icons.restore),
            ),
          if (!widget.calendar && widget.parent == null)
            IconButton(
              onPressed: _canAct ? _calendar : null,
              tooltip: t('打开待办日历', 'Open task calendar'),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
        ],
      ),
      floatingActionButton: widget.calendar
          ? null
          : FloatingActionButton(
              shape: const CircleBorder(),
              onPressed: _canAct ? () => _edit() : null,
              tooltip: widget.parent == null
                  ? t('新建待办', 'New task')
                  : t('新建子待办', 'New subtask'),
              child: const Icon(Icons.add),
            ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.calendar) _calendarHeader() else _filters(),
            if (_fetching) const LinearProgressIndicator(),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _writing.isEmpty ? () => _refresh() : null,
                    child: Text(t('重试刷新', 'Retry refresh')),
                  ),
                ],
              ),
            if (!_fetching && _error == null && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t('没有匹配的待办', 'No matching tasks')),
              ),
            ..._cards(),
            if (widget.calendar)
              TextButton(
                onPressed: _operating.isNotEmpty
                    ? null
                    : () {
                        setState(() => _modifiedOn = '');
                        _load();
                      },
                child: Text(t('清除日期筛选', 'Clear date filter')),
              ),
            if (_hasMore)
              TextButton(
                onPressed: _fetching || _operating.isNotEmpty
                    ? null
                    : () => _load(next: true),
                child: Text(t('加载更多', 'Load more')),
              ),
          ],
        ),
      ),
    ),
  );
}
