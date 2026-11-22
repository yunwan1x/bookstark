import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/completion_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/summary_editor_repository.dart';
import '../../core/task_draft_vault.dart';
import '../../core/tasks_repository.dart';
import '../../core/topic_draft_vault.dart';
import '../../core/topic_resource_picker_repository.dart';
import '../../core/topic_tasks_repository.dart';
import '../../core/topics_repository.dart';
import '../../widgets/bookstark_markdown.dart';
import '../notes/notes_page.dart';
import '../tasks/task_card.dart';
import '../tasks/task_editor_page.dart';
import '../tasks/tasks_page.dart';
import 'ai_draft_page.dart';
import 'topic_comments_page.dart';
import 'topic_editor_page.dart';
import 'topic_resource_picker_page.dart';

enum TopicSection { summaries, resources, tasks, comments }

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.repository,
    required this.topicId,
    required this.tasks,
    required this.picker,
    required this.onOpenResource,
    this.topicDrafts,
    this.summaryDrafts,
    this.commentDrafts,
    this.taskDrafts,
    this.recoverTaskCreation,
    this.attachments,
    this.completion,
    this.onSpeak,
    this.english = false,
    this.local = false,
    this.clock,
  });
  final TopicsRepository repository;
  final int topicId;
  final TasksRepository tasks;
  final TopicResourcePickerRepository picker;
  final Future<void> Function(TopicResource resource) onOpenResource;
  final TopicDraftVault? topicDrafts;
  final DraftVault? summaryDrafts;
  final DraftVault Function(TopicCommentTarget type, int targetId)?
  commentDrafts;
  final TaskDraftVault? taskDrafts;
  final Future<void> Function()? recoverTaskCreation;
  final AttachmentRepository? attachments;
  final CompletionRepository? completion;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  final bool english, local;
  final DateTime Function()? clock;
  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  late final _tasksRepository = TopicTasksRepository(
    widget.tasks,
    widget.topicId,
  );
  final _search = TextEditingController();
  final _filters = <TopicSection, String>{};
  TopicSection _section = TopicSection.summaries;
  TopicDetail? _detail;
  List<TaskItem> _tasks = [];
  int _taskTotal = 0,
      _allTaskTotal = 0,
      _taskPage = 0,
      _generation = 0,
      _taskGeneration = 0;
  bool _showSearch = false;
  bool _loading = true,
      _busy = false,
      _opening = false,
      _taskLoading = false,
      _taskMore = false,
      _refreshRequired = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _canAct =>
      !_loading &&
      !_busy &&
      !_taskLoading &&
      !_refreshRequired &&
      _detail != null;
  String get _taskKeyword => _filters[TopicSection.tasks] ?? '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _taskGeneration++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _taskGeneration++;
    final last = _taskPage < 1 ? 1 : _taskPage;
    setState(() {
      _loading = true;
      _taskLoading = false;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.read(widget.topicId),
        _tasksRepository.list(TaskQuery(keyword: _taskKeyword, pageSize: 30)),
        if (_taskKeyword.trim().isNotEmpty)
          _tasksRepository.list(const TaskQuery(pageSize: 1)),
      ]);
      if (!mounted || generation != _generation) return;
      final detail = results[0] as TopicDetail;
      var page = results[1] as TaskPage;
      final total = results.length > 2
          ? (results[2] as TaskPage).total
          : page.total;
      final expectedTotal = page.total;
      final tasks = List<TaskItem>.of(page.items);
      for (var index = 2; index <= last && page.hasMore; index++) {
        page = await _tasksRepository.list(
          TaskQuery(keyword: _taskKeyword, page: index, pageSize: 30),
        );
        if (!mounted || generation != _generation) return;
        if (page.page != index ||
            page.total != expectedTotal ||
            (page.hasMore && page.items.isEmpty)) {
          throw const FormatException('Invalid topic task page');
        }
        tasks.addAll(page.items);
      }
      if (tasks.map((item) => item.id).toSet().length != tasks.length) {
        throw StateError(
          t('任务列表有变化，请刷新核对', 'Task list changed; reload to verify'),
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _detail = detail;
        _tasks = tasks;
        _taskPage = page.page;
        _taskMore = page.hasMore;
        _taskTotal = page.total;
        _allTaskTotal = total;
        _refreshRequired = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _moreTasks() async {
    if (!_canAct || !_taskMore) return;
    final generation = ++_taskGeneration;
    final parent = _generation;
    final next = _taskPage + 1;
    setState(() => _taskLoading = true);
    try {
      final page = await _tasksRepository.list(
        TaskQuery(keyword: _taskKeyword, page: next, pageSize: 30),
      );
      if (!mounted || generation != _taskGeneration || parent != _generation) {
        return;
      }
      final tasks = [..._tasks, ...page.items];
      if (page.page != next ||
          page.total != _taskTotal ||
          (page.hasMore && page.items.isEmpty) ||
          tasks.map((item) => item.id).toSet().length != tasks.length) {
        throw const FormatException('Task page changed');
      }
      setState(() {
        _tasks = tasks;
        _taskPage = next;
        _taskMore = page.hasMore;
        _taskTotal = page.total;
      });
    } catch (error) {
      if (mounted && generation == _taskGeneration) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted && generation == _taskGeneration) {
        setState(() => _taskLoading = false);
      }
    }
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    if (!_canAct) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认', 'Confirm')),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _settings() async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => TopicEditorPage(
            repository: widget.repository,
            topic: _detail!.topic,
            vault: widget.topicDrafts,
            english: widget.english,
          ),
        ),
      );
      if (mounted) await _load();
    } finally {
      _opening = false;
    }
  }

  Future<void> _delete() async {
    if (!_canAct) return;
    if (!await _confirm(
          t('删除主题', 'Delete topic'),
          t(
            '将删除本主题、小结、资料关联、$_allTaskTotal条主题内任务、评论和主题分享。源资料保留。',
            'Deletes this topic, summaries, associations, $_allTaskTotal topic tasks, comments and topic shares. Source resources are retained.',
          ),
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.remove(widget.topicId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _summaryTitle(TopicSummary item) {
    final lines = item.content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.isEmpty
        ? t('未命名小结', 'Untitled summary')
        : String.fromCharCodes(
            lines.first.replaceFirst(RegExp(r'^#{1,6}\s+'), '').runes.take(200),
          );
  }

  String _aiContext() {
    final detail = _detail!;
    return '${t('主题', 'Topic')}：${detail.topic.title}\n${t('核心问题', 'Question')}：${detail.topic.question}\n\n${detail.summaries.map((item) => item.content).join('\n\n')}\n\n${t('资料标题', 'Resource titles')}：\n${detail.resources.map((item) => item.title).join('\n')}';
  }

  Future<void> _editSummary([TopicSummary? summary, bool ai = false]) async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      final writer = widget.repository;
      if (summary != null && writer is SummaryContentWriter) {
        summary = await (writer as SummaryContentWriter).readSummaryForEditing(
          widget.topicId,
          summary.id!,
        );
        if (!mounted) return;
      }
      var content = summary?.content ?? '';
      if (ai) {
        final completion = widget.completion;
        if (completion == null) {
          throw StateError(
            t('此空间尚未配置AI服务', 'AI is not configured for this space'),
          );
        }
        final draft = await Navigator.push<CompletionDraft>(
          context,
          MaterialPageRoute(
            builder: (_) => AIDraftPage(
              repository: completion,
              title: _detail!.topic.title,
              initialContext: _aiContext(),
              initialInstruction: t(
                '提炼三个可执行的行动',
                'Extract three actionable steps',
              ),
              attachments: widget.attachments,
              english: widget.english,
            ),
          ),
        );
        if (!mounted || draft == null) return;
        content = draft.markdown;
      }
      final value =
          summary ??
          TopicSummary(
            topicId: widget.topicId,
            content: '',
            type: ai ? 'ai' : 'manual',
          );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(
            repository: SummaryEditorRepository(widget.repository, value),
            note: Note(id: value.id, title: '', content: content),
            documentPath:
                '${_detail!.topic.title} · ${value.type == 'ai' ? t('AI小结', 'AI summary') : t('手动记录', 'Manual note')}',
            contentEditorTitle: t('编辑小结', 'Edit summary'),
            drafts: widget.summaryDrafts,
            attachments: widget.attachments,
            english: widget.english,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _comments([TopicCommentDestination? target]) async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TopicCommentsPage(
            repository: widget.repository,
            topic: _detail!.topic,
            initialTarget: target,
            drafts: widget.commentDrafts,
            attachments: widget.attachments,
            completion: widget.completion,
            english: widget.english,
            local: widget.local,
          ),
        ),
      );
      if (mounted) await _load();
    } finally {
      _opening = false;
    }
  }

  Future<void> _picker() async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => TopicResourcePickerPage(
            repository: widget.picker,
            topics: widget.repository,
            topic: _detail!.topic,
            existing: {
              for (final item in _detail!.resources) (item.type, item.targetId),
            },
            english: widget.english,
          ),
        ),
      );
      if (mounted) await _load();
    } finally {
      _opening = false;
    }
  }

  Future<void> _openResource(TopicResource item) async {
    if (_opening || !_canAct || item.missing) return;
    _opening = true;
    try {
      await widget.onOpenResource(item);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _taskEditor([TaskItem? item, TaskItem? parent]) async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      if (item == null && await _tasksRepository.hasRetainedTaskCreation()) {
        if (!mounted || !_canAct) return;
        final recover = widget.recoverTaskCreation;
        if (recover == null)
          throw StateError('Retained task creation requires readonly recovery');
        await recover();
        return;
      }
      if (!mounted || !_canAct) return;
      final now = (widget.clock ?? DateTime.now)();
      final value = item == null
          ? TaskItem(
              content: '',
              dueDate: taskDate(DateTime(now.year, now.month, now.day + 7)),
              topicId: widget.topicId,
              parentId: parent?.id ?? 0,
            )
          : await _tasksRepository.read(item.id!);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TaskEditorPage(
            onCreationRecovery: widget.recoverTaskCreation,
            repository: _tasksRepository,
            task: value,
            vault: widget.taskDrafts,
            attachments: widget.attachments,
            english: widget.english,
            clock: widget.clock,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _children(TaskItem item) async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      final parent = await _tasksRepository.read(item.id!);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TasksPage(
            recoverCreation: widget.recoverTaskCreation,
            repository: _tasksRepository,
            parent: parent,
            vault: widget.taskDrafts,
            attachments: widget.attachments,
            english: widget.english,
            clock: widget.clock,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _parent(int id) async {
    try {
      final parent = await _tasksRepository.read(id);
      await _children(parent);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _removeTask(TaskItem item) async {
    if (await _confirm(
          t('删除待办及全部子项？', 'Delete task and all children?'),
          item.content,
        ) &&
        mounted) {
      await _mutate(() => _tasksRepository.remove(item.id!));
    }
  }

  Future<void> _summaryAction(TopicSummary item, String action) async {
    if (action == 'edit') {
      await _editSummary(item);
      return;
    }
    if (action == 'comments') {
      await _comments(
        TopicCommentDestination(
          TopicCommentTarget.summary,
          item.id!,
          _summaryTitle(item),
        ),
      );
      return;
    }
    if (action == 'speak') {
      try {
        await widget.onSpeak?.call(
          item.content,
          _summaryTitle(item),
          _detail!.topic.title,
        );
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
      return;
    }
    if (action == 'delete') {
      if (await _confirm(
            t('删除小结及其评论？', 'Delete summary and its comments?'),
            _summaryTitle(item),
          ) &&
          mounted) {
        await _mutate(
          () => widget.repository.removeSummary(widget.topicId, item.id!),
        );
      }
      return;
    }
    final rows = List<TopicSummary>.of(_detail!.summaries);
    final index = rows.indexWhere((row) => row.id == item.id);
    final next = index + (action == 'up' ? -1 : 1);
    if (index < 0 || next < 0 || next >= rows.length) return;
    final other = rows[next];
    rows[next] = rows[index];
    rows[index] = other;
    await _mutate(
      () => widget.repository.sortSummaries(widget.topicId, {
        for (var index = 0; index < rows.length; index++)
          rows[index].id!: index,
      }),
    );
  }

  Future<void> _resourceAction(TopicResource item, String action) async {
    if (action == 'comments') {
      await _comments(
        TopicCommentDestination(
          TopicCommentTarget.resource,
          item.id!,
          item.title,
        ),
      );
      return;
    }
    if (action == 'remove') {
      if (await _confirm(
            t('移除资料关联？', 'Remove association?'),
            t(
              '仅移除此主题中的关联，源资料保留。',
              'Only removes this topic association; source resource is retained.',
            ),
          ) &&
          mounted) {
        await _mutate(
          () => widget.repository.removeResource(widget.topicId, item.id!),
        );
      }
      return;
    }
    final rows = List<TopicResource>.of(_detail!.resources);
    final index = rows.indexWhere((row) => row.id == item.id);
    final next = index + (action == 'up' ? -1 : 1);
    if (index < 0 || next < 0 || next >= rows.length) return;
    final other = rows[next];
    rows[next] = rows[index];
    rows[index] = other;
    await _mutate(
      () => widget.repository.sortResources(widget.topicId, {
        for (var index = 0; index < rows.length; index++)
          rows[index].id!: index,
      }),
    );
  }

  String _date(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return widget.english
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : '${date.month}月${date.day}日';
  }

  Widget _badge(String label, {bool ai = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: ai ? const Color(0xffdbeafe) : const Color(0xfff1f5f9),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: ai ? const Color(0xff2563eb) : const Color(0xff475569),
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _summaryCard(TopicSummary item) {
    final rows = _detail!.summaries;
    final index = rows.indexWhere((row) => row.id == item.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _badge(
                      item.type == 'ai'
                          ? t('AI小结', 'AI summary')
                          : item.type == 'manual'
                          ? t('手动记录', 'Manual note')
                          : item.type,
                      ai: item.type == 'ai',
                    ),
                  ),
                ),
                if (item.modifiedAt != null)
                  Text(
                    _date(item.modifiedAt!.toIso8601String()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: t('小结操作', 'Summary actions'),
                  enabled: _canAct,
                  onSelected: (action) => _summaryAction(item, action),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
                    PopupMenuItem(
                      value: 'up',
                      enabled: index > 0,
                      child: Text(t('上移', 'Move up')),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: index < rows.length - 1,
                      child: Text(t('下移', 'Move down')),
                    ),
                    if (widget.onSpeak != null)
                      PopupMenuItem(
                        value: 'speak',
                        child: Text(t('朗读', 'Read aloud')),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(t('删除', 'Delete')),
                    ),
                  ],
                ),
              ],
            ),
            BookstarkMarkdown(
              data: item.content,
              attachments: widget.attachments,
              english: widget.english,
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _canAct
                    ? () => _comments(
                        TopicCommentDestination(
                          TopicCommentTarget.summary,
                          item.id!,
                          _summaryTitle(item),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  t('评论${item.commentCount}', '${item.commentCount} comments'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceCard(TopicResource item) {
    final rows = _detail!.resources;
    final index = rows.indexWhere((row) => row.id == item.id);
    final type = switch (item.type) {
      TopicResourceType.document => t('文档', 'Document'),
      TopicResourceType.note => t('笔记', 'Note'),
      TopicResourceType.article => t('文章', 'Article'),
      TopicResourceType.bookmark => t('书签', 'Bookmark'),
      TopicResourceType.task => t('任务', 'Task'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _canAct && !item.missing
                        ? () => _openResource(item)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            type,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (item.description.isNotEmpty)
                            Text(item.description),
                          if (item.missing)
                            Text(
                              t(
                                '源资料已失效，保留原快照',
                                'Source unavailable; snapshot retained',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: t('资料操作', 'Resource actions'),
                  enabled: _canAct,
                  onSelected: (value) => _resourceAction(item, value),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'up',
                      enabled: index > 0,
                      child: Text(t('上移', 'Move up')),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: index < rows.length - 1,
                      child: Text(t('下移', 'Move down')),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(t('移除关联', 'Remove association')),
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _canAct
                    ? () => _comments(
                        TopicCommentDestination(
                          TopicCommentTarget.resource,
                          item.id!,
                          item.title,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  t('评论${item.commentCount}', '${item.commentCount} comments'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _switch(TopicSection section) {
    if (section == TopicSection.comments) {
      _comments();
      return;
    }
    setState(() {
      _section = section;
      _search.text = _filters[section] ?? '';
    });
  }

  void _filter() {
    _filters[_section] = _search.text;
    if (_section == TopicSection.tasks) {
      _taskPage = 0;
      _load();
    } else {
      setState(() {});
    }
  }

  Widget _tabs() {
    final detail = _detail!;
    final labels = {
      TopicSection.summaries: t(
        '小结${detail.summaries.length}',
        '${detail.summaries.length} summaries',
      ),
      TopicSection.resources: t(
        '资料${detail.resources.length}',
        '${detail.resources.length} resources',
      ),
      TopicSection.tasks: t('任务$_allTaskTotal', '$_allTaskTotal tasks'),
      TopicSection.comments: t(
        '评论${detail.commentCount}',
        '${detail.commentCount} comments',
      ),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!widget.english &&
            MediaQuery.textScalerOf(context).scale(14) <= 17 &&
            constraints.maxWidth >= 340) {
          return SegmentedButton<TopicSection>(
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xff2563eb)
                    : Colors.white,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : const Color(0xff475569),
              ),
            ),
            segments: [
              for (final entry in labels.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {_section},
            onSelectionChanged: _loading || _busy
                ? null
                : (values) => _switch(values.single),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in labels.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _section == entry.key,
                onSelected: _loading || _busy
                    ? null
                    : (_) => _switch(entry.key),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final filter = (_filters[_section] ?? '').toLowerCase();
    final summaries =
        detail?.summaries
            .where((item) => item.content.toLowerCase().contains(filter))
            .toList() ??
        [];
    final resources =
        detail?.resources
            .where(
              (item) => '${item.title} ${item.description}'
                  .toLowerCase()
                  .contains(filter),
            )
            .toList() ??
        [];
    final searchLabel = switch (_section) {
      TopicSection.summaries => t('搜索小结', 'Search summaries'),
      TopicSection.resources => t('搜索资料', 'Search resources'),
      TopicSection.tasks => t('搜索主题内任务', 'Search topic tasks'),
      TopicSection.comments => t('搜索评论', 'Search comments'),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.topic.title ?? t('主题', 'Topic')),
        actions: [
          if (detail != null)
            PopupMenuButton<String>(
              tooltip: t('主题操作', 'Topic actions'),
              enabled: _canAct,
              onSelected: (value) {
                switch (value) {
                  case 'search':
                    setState(() => _showSearch = !_showSearch);
                  case 'edit':
                    _settings();
                  case 'pin':
                    _mutate(
                      () => widget.repository.setPinned(
                        widget.topicId,
                        !detail.topic.isPinned,
                      ),
                    );
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'search',
                  child: Text(
                    _showSearch
                        ? t('收起搜索', 'Hide search')
                        : t('搜索当前分区', 'Search this section'),
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Text(t('编辑主题', 'Edit topic')),
                ),
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    detail.topic.isPinned ? t('取消置顶', 'Unpin') : t('置顶', 'Pin'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t('删除主题', 'Delete topic')),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton(
              shape: const CircleBorder(),
              tooltip: _section == TopicSection.summaries
                  ? t('添加小结', 'Add summary')
                  : _section == TopicSection.resources
                  ? t('添加资料', 'Add resources')
                  : t('添加主题任务', 'Add topic task'),
              onPressed: !_canAct
                  ? null
                  : () => switch (_section) {
                      TopicSection.summaries => _editSummary(),
                      TopicSection.resources => _picker(),
                      TopicSection.tasks => _taskEditor(),
                      TopicSection.comments => _comments(),
                    },
              child: const Icon(Icons.add),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: Text(t('刷新核对', 'Reload to verify')),
                ),
              ],
              if (detail != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _badge(t('核心问题', 'Core question')),
                        const SizedBox(height: 8),
                        Text(
                          detail.topic.question.isEmpty
                              ? t('尚未设置核心问题', 'No core question set')
                              : detail.topic.question,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (detail.topic.modifiedOn.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            t(
                              '更新时间 ${_date(detail.topic.modifiedOn)}',
                              'Updated ${_date(detail.topic.modifiedOn)}',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _tabs(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _section == TopicSection.summaries
                            ? t('主题小结', 'Topic summaries')
                            : _section == TopicSection.resources
                            ? t('关联资料', 'Resources')
                            : t('主题内任务', 'Topic tasks'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_section == TopicSection.summaries)
                      TextButton(
                        onPressed: _canAct
                            ? () => _editSummary(null, true)
                            : null,
                        child: Text(t('AI草拟', 'AI draft')),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_showSearch || filter.isNotEmpty)
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: searchLabel,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: t('搜索', 'Search'),
                        onPressed: _busy ? null : _filter,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                    onSubmitted: _busy ? null : (_) => _filter(),
                  ),
                if (_showSearch || filter.isNotEmpty)
                  const SizedBox(height: 16),
                if (_section == TopicSection.summaries) ...[
                  for (final item in summaries) _summaryCard(item),
                  if (summaries.isEmpty)
                    Text(t('暂无匹配小结', 'No matching summaries')),
                ],
                if (_section == TopicSection.resources) ...[
                  for (final item in resources) _resourceCard(item),
                  if (resources.isEmpty)
                    Text(t('暂无匹配资料', 'No matching resources')),
                ],
                if (_section == TopicSection.tasks) ...[
                  Text(t('$_taskTotal条匹配任务', '$_taskTotal matching tasks')),
                  const SizedBox(height: 12),
                  for (final item in _tasks) ...[
                    TaskCard(
                      task: item,
                      enableActions: _canAct,
                      allowStatusChanges: _canAct,
                      english: widget.english,
                      attachments: widget.attachments,
                      busyIds: _busy ? {item.id!} : {},
                      onToggle: (task, done) => _mutate(
                        () => _tasksRepository.setDone(task.id!, done),
                      ),
                      onEdit: _taskEditor,
                      onAddChild: (parent) => _taskEditor(null, parent),
                      onChildren: _children,
                      onRemove: _removeTask,
                      onParent: _parent,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _canAct
                            ? () => _comments(
                                TopicCommentDestination(
                                  TopicCommentTarget.task,
                                  item.id!,
                                  String.fromCharCodes(
                                    item.content.runes.take(200),
                                  ),
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(t('任务评论', 'Task comments')),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_tasks.isEmpty && !_loading)
                    Text(t('暂无匹配任务', 'No matching tasks')),
                  if (_taskMore)
                    OutlinedButton(
                      onPressed: _canAct ? _moreTasks : null,
                      child: Text(t('加载更多任务', 'Load more tasks')),
                    ),
                ],
              ],
              if (_loading || _busy || _taskLoading)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
