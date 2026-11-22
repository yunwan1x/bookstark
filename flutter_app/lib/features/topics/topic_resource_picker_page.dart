import 'package:flutter/material.dart';
import '../../core/books_repository.dart';
import '../../core/topics_repository.dart';
import '../../core/topic_resource_picker_repository.dart';

class TopicResourcePickerPage extends StatefulWidget {
  const TopicResourcePickerPage({
    super.key,
    required this.repository,
    required this.topics,
    required this.topic,
    required this.existing,
    this.english = false,
  });
  final TopicResourcePickerRepository repository;
  final TopicsRepository topics;
  final TopicItem topic;
  final Set<(TopicResourceType, int)> existing;
  final bool english;
  @override
  State<TopicResourcePickerPage> createState() =>
      _TopicResourcePickerPageState();
}

class _TopicResourcePickerPageState extends State<TopicResourcePickerPage> {
  final _search = TextEditingController();
  final _selected = <(TopicResourceType, int), TopicResourceCandidate>{};
  late final _existing = Set<(TopicResourceType, int)>.of(widget.existing);
  TopicResourceType _type = TopicResourceType.note;
  BookItem? _book;
  List<TopicResourceCandidate> _items = [];
  int _generation = 0, _page = 0, _added = 0, _processed = 0, _requested = 0;
  bool _loading = true,
      _more = false,
      _saving = false,
      _stop = false,
      _allowLeave = false,
      _touched = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  String _typeLabel(TopicResourceType type) => switch (type) {
    TopicResourceType.document => t('文档', 'Documents'),
    TopicResourceType.note => t('笔记', 'Notes'),
    TopicResourceType.article => t('文章', 'Articles'),
    TopicResourceType.bookmark => t('书签', 'Bookmarks'),
    TopicResourceType.task => t('任务', 'Tasks'),
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    if (_type == TopicResourceType.document && _book == null) {
      setState(() {
        _loading = false;
        _items = [];
        _more = false;
        _error = null;
      });
      return;
    }
    final page = more ? _page + 1 : 1;
    final type = _type;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.list(
        type,
        keyword: _search.text,
        page: page,
        bookId: _book?.id,
      );
      if (!mounted || generation != _generation) return;
      final items = [if (more) ..._items, ...result.items];
      if (items.any((item) => item.id <= 0 || item.type != type) ||
          items.map((item) => item.key).toSet().length != items.length ||
          (result.hasMore && result.items.isEmpty)) {
        throw const FormatException(
          '资料列表有变化，请重新搜索 / Candidate list changed; search again',
        );
      }
      setState(() {
        _items = items;
        _page = page;
        _more = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeType(TopicResourceType type) {
    if (_saving) return;
    _type = type;
    _search.clear();
    _items = [];
    _page = 0;
    _load();
  }

  Future<void> _chooseBook() async {
    final book = await showDialog<BookItem>(
      context: context,
      builder: (_) => _TopicBookPicker(
        repository: widget.repository,
        english: widget.english,
      ),
    );
    if (book == null || !mounted) return;
    _book = book;
    _items = [];
    _page = 0;
    _load();
  }

  void _toggle(TopicResourceCandidate item, bool selected) {
    if (_saving || _existing.contains(item.key)) return;
    if (selected && _selected.length >= 50) {
      setState(
        () => _error = t('一次最多选择50项', 'Select up to 50 items at a time'),
      );
      return;
    }
    setState(() {
      if (selected) {
        _selected[item.key] = item;
      } else {
        _selected.remove(item.key);
      }
    });
  }

  Future<void> _confirm() async {
    if (_saving || _selected.isEmpty) return;
    final pending = _selected.values.toList();
    setState(() {
      _saving = true;
      _stop = false;
      _error = null;
      _processed = 0;
      _requested = pending.length;
      _touched = true;
    });
    final failures = <String>[];
    try {
      final current = await widget.topics.read(widget.topic.id!);
      if (!mounted) return;
      _existing
        ..clear()
        ..addAll(current.resources.map((item) => (item.type, item.targetId)));
      for (final candidate in pending) {
        if (_stop) break;
        if (_existing.contains(candidate.key)) {
          _selected.remove(candidate.key);
          _processed++;
          continue;
        }
        try {
          await widget.topics.addResource(candidate.forTopic(widget.topic.id!));
          _existing.add(candidate.key);
          _selected.remove(candidate.key);
          _added++;
        } catch (error) {
          // A failed response may follow a committed insert. Read canonical
          // associations before treating it as retryable or sending another POST.
          var found = false;
          try {
            final actual = await widget.topics.read(widget.topic.id!);
            found = actual.resources.any(
              (item) =>
                  item.type == candidate.type && item.targetId == candidate.id,
            );
          } catch (_) {
            /* Preserve selection until a later canonical refresh succeeds. */
          }
          if (found) {
            _existing.add(candidate.key);
            _selected.remove(candidate.key);
            _added++;
          } else {
            failures.add('${candidate.title}: $error');
          }
        }
        if (!mounted) return;
        setState(() => _processed++);
      }
      if (!mounted) return;
      if (_selected.isEmpty) {
        _allowLeave = true;
        Navigator.pop(context, true);
        return;
      }
      setState(
        () => _error =
            '${t('仍有${_selected.length}项待添加，已添加项保留。', '${_selected.length} items remain; added associations are retained.')}\n${failures.take(3).join('\n')}',
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (_selected.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
          title: Text(t('退出资料选择？', 'Leave selection?')),
          content: Text(
            t(
              '仍有${_selected.length}项未添加。已经添加的关联会保留。',
              '${_selected.length} items have not been added. Added associations are retained.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续选择', 'Keep selecting')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('退出', 'Leave')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _allowLeave = true;
    Navigator.pop(context, _touched);
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          onPressed: _saving ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(t('添加资料', 'Add resources')),
        actions: [
          TextButton(
            onPressed: _saving || _loading || _selected.isEmpty
                ? null
                : _confirm,
            child: Text(t('确认', 'Confirm')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t('添加到 ${widget.topic.title}', 'Add to ${widget.topic.title}'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in TopicResourceType.values)
                  ChoiceChip(
                    label: Text(_typeLabel(type)),
                    selected: _type == type,
                    onSelected: _saving ? null : (_) => _changeType(type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_type == TopicResourceType.document) ...[
              OutlinedButton.icon(
                onPressed: _saving ? null : _chooseBook,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(_book?.name ?? t('先选择书籍', 'Choose a book first')),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _search,
              enabled: !_saving,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: t(
                  '搜索${_typeLabel(_type)}',
                  'Search ${_typeLabel(_type).toLowerCase()}',
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: t('搜索', 'Search'),
                  onPressed: _saving ? null : () => _load(),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              onSubmitted: _saving ? null : (_) => _load(),
            ),
            const SizedBox(height: 24),
            Text(
              t('选择已有资料', 'Choose existing resources'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              t(
                '仅添加关联，源资料保留。',
                'Only adds associations; source resources are retained.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (!_saving)
                TextButton(
                  onPressed: () => _load(),
                  child: Text(t('刷新候选资料', 'Reload candidates')),
                ),
            ],
            for (final item in _items)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: CheckboxListTile(
                  value:
                      _existing.contains(item.key) ||
                      _selected.containsKey(item.key),
                  onChanged: _saving || _existing.contains(item.key)
                      ? null
                      : (value) => _toggle(item, value == true),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _existing.contains(item.key)
                        ? t('已关联', 'Already associated')
                        : item.protected
                        ? t('受保护笔记', 'Protected note')
                        : item.description,
                  ),
                  secondary: Icon(
                    item.protected
                        ? Icons.lock_outline
                        : Icons.description_outlined,
                  ),
                ),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _error == null && _items.isEmpty)
              Text(
                _type == TopicResourceType.document && _book == null
                    ? t('请先选择书籍以加载章节', 'Choose a book to load its chapters')
                    : t('暂无可选资料', 'No candidates'),
              ),
            if (_more)
              OutlinedButton(
                onPressed: _loading || _saving ? null : () => _load(more: true),
                child: Text(t('加载更多', 'Load more')),
              ),
            const SizedBox(height: 16),
            Text(
              t(
                '已选择${_selected.length}项（最多50项）',
                '${_selected.length} selected (up to 50)',
              ),
            ),
            if (_added > 0)
              Text(t('本次已添加$_added项', '$_added associations added')),
            if (_saving) ...[
              const LinearProgressIndicator(),
              Text(
                t(
                  '正在处理$_processed/$_requested项',
                  'Processing $_processed/$_requested',
                ),
              ),
              TextButton(
                onPressed: _stop ? null : () => setState(() => _stop = true),
                child: Text(t('停止后续添加', 'Stop remaining additions')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _TopicBookPicker extends StatefulWidget {
  const _TopicBookPicker({required this.repository, required this.english});
  final TopicResourcePickerRepository repository;
  final bool english;
  @override
  State<_TopicBookPicker> createState() => _TopicBookPickerState();
}

class _TopicBookPickerState extends State<_TopicBookPicker> {
  final _search = TextEditingController();
  List<BookItem> _items = [];
  int _page = 0, _generation = 0;
  bool _loading = true, _more = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.books(
        keyword: _search.text,
        page: page,
      );
      if (!mounted || generation != _generation) return;
      final items = [if (more) ..._items, ...result.items];
      if (result.page != page ||
          items.any((item) => item.id == null) ||
          items.map((item) => item.id).toSet().length != items.length) {
        throw const FormatException('Invalid book page');
      }
      setState(() {
        _items = items;
        _page = page;
        _more = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t('选择书籍', 'Choose a book')),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(labelText: t('搜索书籍', 'Search books')),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: () => _load(), child: Text(t('重试', 'Retry'))),
          ],
          for (final book in _items)
            ListTile(
              title: Text(book.name),
              subtitle: Text(book.description),
              onTap: _loading ? null : () => Navigator.pop(context, book),
            ),
          if (_loading) const CircularProgressIndicator(),
          if (_more)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: Text(t('加载更多', 'Load more')),
            ),
        ],
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
