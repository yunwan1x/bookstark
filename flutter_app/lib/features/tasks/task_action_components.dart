import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

import '../../core/task_action_drafts.dart';

class TaskSuggestionPreviewPage extends StatefulWidget {
  const TaskSuggestionPreviewPage({
    super.key,
    required this.suggestion,
    required this.readCurrentDraft,
    required this.compareAndApply,
    required this.isCurrent,
    this.english = false,
  });
  final TaskTextSuggestion suggestion;
  final Future<TaskActionSnapshot> Function() readCurrentDraft;

  /// Atomic draft-only compare-and-apply in the owning editor; MUST NOT save SQL.
  final Future<bool> Function(String expectedFingerprint, TaskItem update)
  compareAndApply;
  final bool Function() isCurrent;
  final bool english;
  @override
  State<TaskSuggestionPreviewPage> createState() => _SuggestionState();
}

class _SuggestionState extends State<TaskSuggestionPreviewPage> {
  bool _busy = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<void> _apply() async {
    if (_busy || !widget.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh = await widget.readCurrentDraft();
      if (!mounted || !widget.isCurrent()) return;
      final update = widget.suggestion.applyToDraft(fresh);
      final applied = await widget.compareAndApply(fresh.fingerprint, update);
      if (!mounted || !widget.isCurrent()) return;
      if (!applied) throw const TaskActionChanged();
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '当前待办已变化或建议未完成，请重新核对。',
            'The task changed or the suggestion is incomplete. Review again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(String title, String text) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          BookstarkMarkdown(
            data: text,
            english: widget.english,
            onLink: (_, _) async {},
            imageBuilder: (_, _, alt) =>
                Text(alt ?? t('图片引用', 'Image reference')),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('AI 建议', 'AI suggestion'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t('仅为建议，没有保存任何内容。', 'Suggestion only. Nothing is saved.'),
              ),
            ),
          ),
          _preview(
            t('当前待办', 'Current task'),
            widget.suggestion.origin.task.content,
          ),
          _preview(t('建议内容', 'Suggested wording'), widget.suggestion.content),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _busy || !widget.suggestion.complete ? null : _apply,
            child: Text(t('放入编辑框', 'Put into editor')),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(t('保留当前内容', 'Keep current text')),
          ),
          Text(
            t(
              '日期、父待办、专题和完成状态保持原值；之后仍需明确保存。',
              'Date, parent, topic and status stay unchanged. Save explicitly in the editor.',
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}

class TaskTopicPickerPage extends StatefulWidget {
  const TaskTopicPickerPage({
    super.key,
    required this.source,
    this.currentTopicId,
    this.english = false,
  });
  final OwnedTaskTopicSource source;
  final int? currentTopicId;
  final bool english;
  @override
  State<TaskTopicPickerPage> createState() => _TopicState();
}

class _TopicState extends State<TaskTopicPickerPage> {
  final _search = TextEditingController();
  final _items = <TopicItem>[];
  late int _selected;
  int _page = 0, _generation = 0;
  bool _busy = false, _more = false;
  String? _error;
  String _loadedKeyword = '';
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void didUpdateWidget(covariant TaskTopicPickerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _selected = widget.currentTopicId ?? 0;
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.currentTopicId ?? 0;
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (_busy && next) return;
    final generation = ++_generation,
        query = next ? _loadedKeyword : _search.text,
        page = next ? _page + 1 : 1;
    setState(() {
      _busy = true;
      _error = null;
      if (!next) _items.clear();
    });
    final source = widget.source;
    try {
      final result = await source.list(query, page);
      if (!mounted ||
          generation != _generation ||
          !identical(source, widget.source)) {
        return;
      }
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        _items.addAll(result.items.where((e) => known.add(e.id)));
        _page = page;
        _loadedKeyword = query;
        _more = result.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = t(
            '无法读取专题，当前选择已保留。',
            'Could not load topics. Your current selection is retained.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _use() async {
    if (_busy || !widget.source.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final selected = _selected, source = widget.source;
    try {
      if (selected > 0) await source.inspect(selected);
      if (!mounted ||
          !identical(source, widget.source) ||
          !source.isCurrent()) {
        return;
      }
      Navigator.pop(
        context,
        selected == 0
            ? const TaskTopicChoice.clear()
            : TaskTopicChoice.select(selected),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '专题已变化或不可用，请重新选择；待办未改变。',
            'The topic changed or is unavailable. Your task was not changed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choiceTile({
    required int value,
    required Widget title,
    Widget? subtitle,
    bool enabled = true,
  }) => Semantics(
    checked: _selected == value,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      title: title,
      subtitle: subtitle,
      selected: _selected == value,
      enabled: enabled && !_busy,
      leading: Icon(
        _selected == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      onTap: enabled && !_busy ? () => setState(() => _selected = value) : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('选择专题', 'Choose a topic'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: t('搜索我的专题', 'Search your topics'),
              suffixIcon: IconButton(
                onPressed: () => _load(),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          _choiceTile(value: 0, title: Text(t('无专题', 'No topic'))),
          if (_selected > 0 && !_items.any((e) => e.id == _selected))
            _choiceTile(
              value: _selected,
              enabled: false,
              title: Text(
                t('当前专题 #', 'Current topic #') + _selected.toString(),
              ),
              subtitle: Text(
                t(
                  '未加载仍保留；应用前重新核对。',
                  'Retained while unloaded; checked again before applying.',
                ),
              ),
            ),
          for (final topic in _items)
            _choiceTile(value: topic.id!, title: Text(topic.title)),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_more)
            OutlinedButton(
              onPressed: _busy ? null : () => _load(next: true),
              child: Text(t('加载更多', 'Load more')),
            ),
          if (_busy) const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            t(
              '专题选择只改变专题，不改变父待办、日期或完成状态。',
              'Changing the topic does not change the parent, due date or done status.',
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _use,
            child: Text(t('使用选中的专题', 'Use selected topic')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('取消并保留当前专题', 'Cancel and keep current topic')),
          ),
        ],
      ),
    ),
  );
}

/// Safe interim decomposition display: text only, no task INSERT/batch action.
class TaskSplitSuggestionList extends StatelessWidget {
  const TaskSplitSuggestionList({
    super.key,
    required this.suggestions,
    required this.onCopy,
    this.english = false,
  });
  final List<String> suggestions;
  final Future<void> Function(String) onCopy;
  final bool english;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(english ? 'Draft suggestions, not saved tasks.' : '仅为建议，尚未创建待办。'),
      for (final text in suggestions)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                TextButton(
                  onPressed: () => onCopy(text),
                  child: Text(english ? 'Copy suggestion' : '复制建议'),
                ),
              ],
            ),
          ),
        ),
      Text(
        english
            ? 'No automatic child creation. Save each task explicitly after review.'
            : '不会自动创建子待办；每条都需核对后明确保存。',
      ),
    ],
  );
}
