import 'package:flutter/material.dart';
import '../../core/topics_repository.dart';
import '../../core/topic_draft_vault.dart';
import '../../core/tasks_repository.dart';
import 'topic_editor_page.dart';

class TopicsPage extends StatefulWidget {
  const TopicsPage({
    super.key,
    required this.repository,
    required this.onOpenTopic,
    this.vault,
    this.onCalendar,
    this.onRecoverCreations,
    this.english = false,
  });
  final TopicsRepository repository;
  final Future<void> Function(BuildContext)? onRecoverCreations;
  final Future<void> Function(int id) onOpenTopic;
  final Future<String?> Function(String selectedDate)? onCalendar;
  final TopicDraftVault? vault;
  final bool english;
  @override
  State<TopicsPage> createState() => _TopicsPageState();
}

class _TopicsPageState extends State<TopicsPage> {
  final _search = TextEditingController();
  TopicQuery _query = const TopicQuery();
  List<TopicItem> _items = [];
  int _total = 0, _page = 0, _generation = 0;
  bool _loading = true,
      _busy = false,
      _more = false,
      _refreshRequired = false,
      _opening = false;
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

  Future<void> _load({bool more = false, bool reloadLoaded = false}) async {
    final generation = ++_generation;
    final query = _query;
    final target = more
        ? _page + 1
        : reloadLoaded && _page > 0
        ? _page
        : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = more ? List<TopicItem>.of(_items) : <TopicItem>[];
      TopicPageResult? result;
      for (var page = more ? target : 1; page <= target; page++) {
        result = await widget.repository.list(
          TopicQuery(keyword: query.keyword, date: query.date, page: page),
        );
        if (!mounted || generation != _generation) return;
        if (result.page != page ||
            result.items.any((item) => item.id == null) ||
            (result.hasMore && result.items.isEmpty)) {
          throw const FormatException('Invalid topic page');
        }
        items.addAll(result.items);
        if (!result.hasMore) break;
      }
      if (items.map((item) => item.id).toSet().length != items.length) {
        throw StateError(t('列表有变化，请刷新核对', 'List changed; reload to verify'));
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

  void _filter({String? date}) {
    if (_busy) return;
    _query = TopicQuery(keyword: _search.text, date: date ?? _query.date);
    _items = [];
    _page = 0;
    _total = 0;
    _load();
  }

  Future<void> _date() async {
    final String? selected;
    if (widget.onCalendar != null) {
      selected = await widget.onCalendar!(_query.date);
    } else {
      final date = await showDatePicker(
        context: context,
        initialDate: _query.date.isEmpty
            ? DateTime.now()
            : DateTime.parse(_query.date),
        firstDate: DateTime(1970),
        lastDate: DateTime(9999, 12, 31),
      );
      selected = date == null ? null : taskDate(date);
    }
    if (selected != null && mounted) _filter(date: selected);
  }

  Future<void> _open(TopicItem item) async {
    if (_opening || _loading || _busy || _refreshRequired) return;
    _opening = true;
    try {
      await widget.onOpenTopic(item.id!);
      if (mounted) await _load(reloadLoaded: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _edit([TopicItem? item]) async {
    if (_opening || _loading || _busy || _refreshRequired) return;
    _opening = true;
    try {
      final id = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => TopicEditorPage(
            repository: widget.repository,
            topic:
                item ??
                TopicItem(title: '', memberId: widget.repository.memberId),
            vault: widget.vault,
            english: widget.english,
          ),
        ),
      );
      if (!mounted) return;
      if (id != null && item == null) await widget.onOpenTopic(id);
      if (id != null && mounted) await _load(reloadLoaded: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    if (_busy || _loading || _refreshRequired) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await _load(reloadLoaded: true);
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

  Future<void> _delete(TopicItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: Text(t('删除主题', 'Delete topic')),
        content: Text(
          '${item.title}\n\n${t('将一同删除小结、资料关联、主题内任务、评论和主题分享。源资料本体保留。', 'This also deletes summaries, associations, topic tasks, comments and topic shares. Source resources are retained.')}',
        ),
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
    if (confirmed == true && mounted) {
      await _mutate(() => widget.repository.remove(item.id!));
    }
  }

  Widget _card(TopicItem item) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.hub_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _open(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.isPinned)
                          Text(
                            t('置顶', 'Pinned'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    if (item.question.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(item.question),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      t(
                        '资料${item.resourceCount} · 小结${item.summaryCount} · 任务${item.taskCount}',
                        '${item.resourceCount} resources · ${item.summaryCount} summaries · ${item.taskCount} tasks',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.modifiedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        t(
                          '更新于${item.modifiedAt!.month}月${item.modifiedAt!.day}日',
                          'Updated ${item.modifiedAt!.year}-${item.modifiedAt!.month}-${item.modifiedAt!.day}',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: t('主题操作', 'Topic actions'),
            enabled: !_loading && !_busy && !_refreshRequired,
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  _edit(item);
                case 'pin':
                  _mutate(
                    () => widget.repository.setPinned(item.id!, !item.isPinned),
                  );
                case 'delete':
                  _delete(item);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
              PopupMenuItem(
                value: 'pin',
                child: Text(
                  item.isPinned ? t('取消置顶', 'Unpin') : t('置顶', 'Pin'),
                ),
              ),
              PopupMenuItem(value: 'delete', child: Text(t('删除', 'Delete'))),
            ],
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('主题', 'Topics')),
      actions: [
        if (widget.onRecoverCreations != null)
          IconButton(
            tooltip: t('创建恢复记录', 'Creation recovery records'),
            onPressed: _busy || _opening
                ? null
                : () => widget.onRecoverCreations!(context),
            icon: const Icon(Icons.restore_outlined),
          ),
        IconButton(
          tooltip: t('主题日历', 'Topic calendar'),
          onPressed: _busy ? null : _date,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      shape: const CircleBorder(),
      tooltip: t('新建主题', 'New topic'),
      onPressed: _busy || _loading || _refreshRequired ? null : () => _edit(),
      child: const Icon(Icons.add),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(reloadLoaded: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: t('搜索主题或问题', 'Search topics or questions'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: t('搜索', 'Search'),
                  onPressed: _busy ? null : _filter,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              onSubmitted: _busy ? null : (_) => _filter(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t('全部', 'All')),
                  selected: _query.date.isEmpty,
                  onSelected: _busy ? null : (_) => _filter(date: ''),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _date,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _query.date.isEmpty ? t('按日期', 'By date') : _query.date,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              t('我的主题', 'My topics'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(t('$_total个主题', '$_total topics')),
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
            if (_loading || _busy)
              const Center(child: CircularProgressIndicator()),
            if (!_loading && _error == null && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t('暂无主题', 'No topics')),
              ),
            if (_more && !_refreshRequired)
              OutlinedButton(
                onPressed: _busy || _loading ? null : () => _load(more: true),
                child: Text(t('加载更多', 'Load more')),
              ),
          ],
        ),
      ),
    ),
  );
}
