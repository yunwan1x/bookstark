import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/comment_editor_repository.dart';
import '../../core/completion_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/topics_repository.dart';
import '../../widgets/bookstark_markdown.dart';
import '../notes/notes_page.dart';
import 'ai_draft_page.dart';

class TopicCommentDestination {
  const TopicCommentDestination(this.type, this.id, this.title);
  final TopicCommentTarget type;
  final int id;
  final String title;
  (TopicCommentTarget, int) get key => (type, id);
}

class TopicCommentsPage extends StatefulWidget {
  const TopicCommentsPage({
    super.key,
    required this.repository,
    required this.topic,
    this.initialTarget,
    this.drafts,
    this.attachments,
    this.completion,
    this.english = false,
    this.local = false,
  });
  final TopicsRepository repository;
  final TopicItem topic;
  final TopicCommentDestination? initialTarget;
  final DraftVault Function(TopicCommentTarget type, int targetId)? drafts;
  final AttachmentRepository? attachments;
  final CompletionRepository? completion;
  final bool english, local;
  @override
  State<TopicCommentsPage> createState() => _TopicCommentsPageState();
}

class _TopicCommentsPageState extends State<TopicCommentsPage> {
  late TopicCommentDestination? _target = widget.initialTarget;
  List<TopicCommentDestination> _targets = [];
  List<TopicComment> _items = [];
  int _total = 0, _page = 0, _generation = 0, _targetGeneration = 0;
  bool _loading = true,
      _targetsLoading = true,
      _more = false,
      _busy = false,
      _opening = false,
      _refreshRequired = false;
  String? _error, _targetError, _targetNotice;
  String t(String zh, String en) => widget.english ? en : zh;
  String _kind(TopicCommentTarget type) => switch (type) {
    TopicCommentTarget.summary => t('小结', 'Summary'),
    TopicCommentTarget.resource => t('资料', 'Resource'),
    TopicCommentTarget.task => t('任务', 'Task'),
  };
  String _summaryTitle(String markdown) {
    final lines = markdown
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.isEmpty
        ? t('未命名小结', 'Untitled summary')
        : String.fromCharCodes(
            lines.first.replaceFirst(RegExp(r'^#{1,6}\s+'), '').runes.take(200),
          );
  }

  bool get _canAct =>
      !_loading &&
      !_targetsLoading &&
      !_busy &&
      !_refreshRequired &&
      _targetError == null;
  @override
  void initState() {
    super.initState();
    _loadTargets();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _targetGeneration++;
    super.dispose();
  }

  Future<void> _loadTargets() async {
    final generation = ++_targetGeneration;
    setState(() {
      _targetsLoading = true;
      _targetError = null;
    });
    try {
      final detail = await widget.repository.read(widget.topic.id!);
      final targets = <TopicCommentDestination>[
        for (final item in detail.summaries)
          TopicCommentDestination(
            TopicCommentTarget.summary,
            item.id!,
            _summaryTitle(item.content),
          ),
        for (final item in detail.resources)
          TopicCommentDestination(
            TopicCommentTarget.resource,
            item.id!,
            item.title,
          ),
      ];
      var page = 1;
      while (true) {
        final result = await widget.repository.tasks(
          widget.topic.id!,
          page: page,
        );
        if (!mounted || generation != _targetGeneration) return;
        if (result.page != page || (result.hasMore && result.items.isEmpty)) {
          throw const FormatException('Invalid topic task targets');
        }
        targets.addAll(
          result.items.map(
            (item) => TopicCommentDestination(
              TopicCommentTarget.task,
              item.id!,
              String.fromCharCodes(item.content.runes.take(200)),
            ),
          ),
        );
        if (!result.hasMore) break;
        page++;
      }
      if (targets.map((item) => item.key).toSet().length != targets.length) {
        throw const FormatException('Duplicate comment targets');
      }
      if (!mounted || generation != _targetGeneration) return;
      var missing = false;
      setState(() {
        _targets = targets;
        if (_target != null) {
          final matches = targets.where((item) => item.key == _target!.key);
          if (matches.isEmpty) {
            _target = null;
            missing = true;
            _targetNotice = t(
              '原评论目标已失效，当前显示全部目标。',
              'The original target is missing; showing all targets.',
            );
          } else {
            _target = matches.first;
          }
        }
      });
      if (missing) await _load();
    } catch (error) {
      if (mounted && generation == _targetGeneration) {
        setState(() => _targetError = error.toString());
      }
    } finally {
      if (mounted && generation == _targetGeneration) {
        setState(() => _targetsLoading = false);
      }
    }
  }

  Future<void> _load({bool more = false, bool reloadLoaded = false}) async {
    final generation = ++_generation;
    final target = _target;
    final last = more
        ? _page + 1
        : reloadLoaded && _page > 0
        ? _page
        : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = more ? List<TopicComment>.of(_items) : <TopicComment>[];
      TopicCommentPage? result;
      for (var page = more ? last : 1; page <= last; page++) {
        result = await widget.repository.comments(
          widget.topic.id!,
          target: target?.type,
          targetId: target?.id,
          page: page,
        );
        if (!mounted || generation != _generation) return;
        if (result.page != page || (result.hasMore && result.items.isEmpty)) {
          throw const FormatException('Invalid comment page');
        }
        items.addAll(result.items);
        if (!result.hasMore) break;
      }
      if (items.map((item) => item.id).toSet().length != items.length) {
        throw StateError(
          t('评论列表有变化，请刷新核对', 'Comments changed; reload to verify'),
        );
      }
      setState(() {
        _items = items;
        _total = result!.total;
        _page = result.page;
        _more = result.hasMore;
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

  Future<void> _refresh() async {
    await Future.wait([_loadTargets(), _load(reloadLoaded: true)]);
  }

  Future<TopicCommentDestination?> _choose({required bool includeAll}) async {
    if (_targetsLoading || _targetError != null) return null;
    final selected = await showDialog<_ChosenCommentTarget>(
      context: context,
      builder: (_) => _CommentTargetPicker(
        targets: _targets,
        includeAll: includeAll,
        english: widget.english,
      ),
    );
    if (selected == null || !mounted) return null;
    if (includeAll) {
      setState(() {
        _target = selected.target;
        _targetNotice = null;
        _items = [];
        _page = 0;
      });
      await _load();
    }
    return selected.target;
  }

  TopicCommentDestination? _destination(TopicComment comment) {
    for (final target in _targets) {
      if (target.key == (comment.target, comment.targetId)) return target;
    }
    return null;
  }

  Future<void> _edit([TopicComment? comment, bool generate = false]) async {
    if (_opening || !_canAct) return;
    _opening = true;
    try {
      final target = comment == null
          ? (_target ?? await _choose(includeAll: false))
          : _destination(comment);
      if (!mounted || target == null) return;
      var content = comment?.content ?? '';
      if (generate) {
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
              title: widget.topic.title,
              initialContext:
                  '${widget.topic.question}\n\n${_kind(target.type)}：${target.title}',
              initialInstruction: t(
                '根据上下文写一条有帮助的评论',
                'Write a useful comment based on the context',
              ),
              scene: CompletionScene.topicComment,
              attachments: widget.attachments,
              english: widget.english,
            ),
          ),
        );
        if (!mounted || draft == null) return;
        content = draft.markdown;
      }
      final value = TopicComment(
        id: comment?.id,
        topicId: widget.topic.id!,
        target: target.type,
        targetId: target.id,
        content: comment?.content ?? '',
      );
      final repository = CommentEditorRepository(widget.repository, value);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(
            repository: repository,
            note: Note(id: value.id, title: '', content: content),
            contentEditorTitle: t('编辑评论', 'Edit comment'),
            documentPath: '${widget.topic.title} · ${_kind(target.type)}',
            contentContextTag: target.title,
            drafts: widget.drafts?.call(target.type, target.id),
            attachments: widget.attachments,
            english: widget.english,
          ),
        ),
      );
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _add() async {
    if (widget.completion == null) {
      await _edit();
      return;
    }
    final ai = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t('编写评论', 'Write a comment')),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(t('AI草拟评论', 'Draft with AI')),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (ai != null && mounted) await _edit(null, ai);
  }

  Future<void> _remove(TopicComment comment) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: Text(t('删除评论？', 'Delete comment?')),
        content: Text(comment.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.removeComment(widget.topic.id!, comment.id!);
      if (mounted) await _refresh();
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

  Widget _card(TopicComment item) {
    final target = _destination(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${_kind(item.target)} · ${target?.title ?? t('目标已失效', 'Target unavailable')}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: t('评论操作', 'Comment actions'),
                  enabled: _canAct,
                  onSelected: (action) {
                    if (action == 'edit') {
                      _edit(item);
                    } else {
                      _remove(item);
                    }
                  },
                  itemBuilder: (_) => [
                    if (target != null)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(t('编辑', 'Edit')),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(t('删除', 'Delete')),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              '${widget.local ? t('本地用户', 'Local user') : item.author}${item.createdAt == null ? '' : ' · ${item.createdAt!.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            BookstarkMarkdown(
              data: item.content,
              attachments: widget.attachments,
              english: widget.english,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('评论', 'Comments')),
      actions: [
        IconButton(
          tooltip: t('添加评论', 'Add comment'),
          onPressed: _canAct && _targets.isNotEmpty ? _add : null,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.topic.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _targetsLoading || _busy || _targetError != null
                  ? null
                  : () => _choose(includeAll: true),
              icon: const Icon(Icons.expand_more),
              label: Text(
                '${t('评论目标', 'Target')} · ${_target == null ? t('全部目标', 'All targets') : '${_kind(_target!.type)} · ${_target!.title}'}',
              ),
            ),
            const SizedBox(height: 24),
            if (_targetNotice != null) Text(_targetNotice!),
            if (_targetError != null) ...[
              Text(
                _targetError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _loadTargets,
                child: Text(t('重试评论目标', 'Retry targets')),
              ),
            ],
            Text(
              t('$_total条评论', '$_total comments'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : () => _load(reloadLoaded: true),
                child: Text(t('刷新核对', 'Reload to verify')),
              ),
            ],
            for (final item in _items) _card(item),
            if (_loading || _targetsLoading || _busy)
              const Center(child: CircularProgressIndicator()),
            if (!_loading && _error == null && _items.isEmpty)
              Text(t('暂无评论', 'No comments')),
            if (_more && !_refreshRequired)
              OutlinedButton(
                onPressed: _loading || _busy ? null : () => _load(more: true),
                child: Text(t('加载更多', 'Load more')),
              ),
            const SizedBox(height: 24),
            Text(
              t(
                '选择小结、资料或任务后发表评论。',
                'Choose a summary, resource or task before commenting.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChosenCommentTarget {
  const _ChosenCommentTarget(this.target);
  final TopicCommentDestination? target;
}

class _CommentTargetPicker extends StatefulWidget {
  const _CommentTargetPicker({
    required this.targets,
    required this.includeAll,
    required this.english,
  });
  final List<TopicCommentDestination> targets;
  final bool includeAll, english;
  @override
  State<_CommentTargetPicker> createState() => _CommentTargetPickerState();
}

class _CommentTargetPickerState extends State<_CommentTargetPicker> {
  final _search = TextEditingController();
  String t(String zh, String en) => widget.english ? en : zh;
  String _kind(TopicCommentTarget type) => switch (type) {
    TopicCommentTarget.summary => t('小结', 'Summary'),
    TopicCommentTarget.resource => t('资料', 'Resource'),
    TopicCommentTarget.task => t('任务', 'Task'),
  };
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.targets
        .where(
          (item) => '${_kind(item.type)} ${item.title}'.toLowerCase().contains(
            _search.text.toLowerCase(),
          ),
        )
        .toList();
    return AlertDialog(
      title: Text(t('选择评论目标', 'Choose comment target')),
      content: SizedBox(
        width: 400,
        height: 360,
        child: ListView.builder(
          itemCount: rows.length + (widget.includeAll ? 2 : 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: t('搜索目标', 'Search targets'),
                ),
                onChanged: (_) => setState(() {}),
              );
            }
            if (widget.includeAll && index == 1) {
              return ListTile(
                title: Text(t('全部目标', 'All targets')),
                onTap: () =>
                    Navigator.pop(context, const _ChosenCommentTarget(null)),
              );
            }
            final item = rows[index - (widget.includeAll ? 2 : 1)];
            return ListTile(
              title: Text(item.title),
              subtitle: Text(_kind(item.type)),
              onTap: () => Navigator.pop(context, _ChosenCommentTarget(item)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
      ],
    );
  }
}
