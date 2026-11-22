import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/owned_writable_generation15.dart';

/// The dedicated owned schema15 catalog. It never exposes a LocalStore or
/// upgrades a review session into a writable capability.
class Owned15Feature extends StatefulWidget {
  const Owned15Feature({
    super.key,
    required this.owner,
    required this.isCurrent,
    required this.openResource,
    required this.openBackup,
    required this.openMigration,
    required this.onConnection,
    this.openCreation,
    this.openCreationRecovery,
    this.english = false,
  });
  final OwnedWritableGeneration15 owner;
  final bool Function() isCurrent;
  final Future<void> Function(GenerationContentMetadata actual) openResource;
  final Future<void> Function() openBackup, openMigration, onConnection;
  final Future<void> Function()? openCreation, openCreationRecovery;
  final bool english;
  @override
  State<Owned15Feature> createState() => _Owned15FeatureState();
}

class _Owned15FeatureState extends State<Owned15Feature> {
  final _search = TextEditingController();
  AttachmentCancellation? _request;
  int _epoch = 0, _page = 1;
  String _collection = 'all';
  bool _busy = false, _hasMore = false;
  String? _error;
  List<GenerationContentListEntry> _items = [];
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && widget.owner.current && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant Owned15Feature old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner)) {
      _request?.cancel();
      _epoch++;
      _items = [];
      _page = 1;
      _hasMore = false;
      _error = null;
      _busy = false;
      _search.clear();
      _collection = 'all';
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _request?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (!current || (_busy && next)) return;
    _request?.cancel();
    final epoch = ++_epoch, owner = widget.owner, collection = _collection;
    final keyword = _search.text, page = next ? _page + 1 : 1;
    final request = AttachmentCancellation();
    _request = request;
    bool owned() =>
        current && epoch == _epoch && identical(owner, widget.owner);
    setState(() {
      _busy = true;
      _error = null;
      if (!next) {
        _items = [];
        _hasMore = false;
      }
    });
    try {
      await owner.confirmCurrent();
      if (!owned()) return;
      final items = await owner.content.list(
        collection: collection,
        keyword: keyword,
        page: page,
        cancellation: request,
      );
      if (!owned()) return;
      // IDs are scoped by actual collection, never by title or index.
      final keys = <String>{};
      for (final item in items) {
        final m = item.metadata;
        if (m.generationId != owner.pointer.generation ||
            m.id <= 0 ||
            !{'note', 'article'}.contains(m.collection) ||
            !keys.add('${m.collection}:${m.id}')) {
          throw StateError('Owned15 list identity mismatch');
        }
      }
      setState(() {
        _items = next ? [..._items, ...items] : items;
        _page = page;
        _hasMore = items.length == 20;
      });
    } catch (_) {
      if (owned()) {
        setState(
          () => _error = t('资料读取失败，请重试。', 'Content could not be read. Retry.'),
        );
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (!current || _busy) return;
    final owner = widget.owner, epoch = _epoch;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (current && epoch == _epoch && identical(owner, widget.owner)) {
        setState(
          () => _error = t(
            '操作未完成，资料与恢复记录已保留。',
            'The operation did not complete. Content and recovery records are retained.',
          ),
        );
      }
    } finally {
      if (current && epoch == _epoch && identical(owner, widget.owner)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open(GenerationContentMetadata item) async {
    if (!current || _busy) return;
    final owner = widget.owner, epoch = _epoch, open = widget.openResource;
    try {
      await owner.confirmCurrent();
      if (!current || epoch != _epoch || !identical(owner, widget.owner)) {
        return;
      }
      await open(item);
      if (current && identical(owner, widget.owner)) await _load();
    } catch (_) {
      if (current && epoch == _epoch && identical(owner, widget.owner)) {
        setState(
          () => _error = t(
            '无法打开资料，原记录已保留。',
            'Unable to open content. The record is retained.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('本机资料', 'Local content')),
      actions: [
        if (widget.openCreation != null || widget.openCreationRecovery != null)
          PopupMenuButton<String>(
            tooltip: t('新建与恢复', 'Creation and recovery'),
            enabled: current && !_busy,
            onSelected: (value) {
              final action = value == 'create'
                  ? widget.openCreation
                  : widget.openCreationRecovery;
              if (action != null) {
                final owner = widget.owner, epoch = _epoch;
                _action(() async {
                  await action();
                  if (current &&
                      epoch == _epoch &&
                      identical(owner, widget.owner)) {
                    await _load();
                  }
                });
              }
            },
            itemBuilder: (context) => [
              if (widget.openCreation != null)
                PopupMenuItem(
                  value: 'create',
                  child: Text(t('新建笔记或文章', 'New note or article')),
                ),
              if (widget.openCreationRecovery != null)
                PopupMenuItem(
                  value: 'recover',
                  child: Text(t('核对新建结果', 'Review creation result')),
                ),
            ],
            icon: const Icon(Icons.add_circle_outline),
          ),
        IconButton(
          tooltip: t('切换空间', 'Switch space'),
          onPressed: _busy ? null : () => _action(widget.onConnection),
          icon: const Icon(Icons.swap_horiz),
        ),
        IconButton(
          tooltip: t('完整备份与恢复', 'Complete backup and recovery'),
          onPressed: current && !_busy
              ? () => _action(widget.openBackup)
              : null,
          icon: const Icon(Icons.backup_outlined),
        ),
        IconButton(
          tooltip: t('导入旧资料', 'Import legacy content'),
          onPressed: current && !_busy
              ? () => _action(widget.openMigration)
              : null,
          icon: const Icon(Icons.folder_open),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              t(
                '此空间保留原有保护状态。笔记和文章使用此空间专属编辑与新建流程；任务和书籍不会使用旧库写入。',
                'This space retains its original protection. Notes and articles use this space’s dedicated editing and creation flow; tasks and books never use legacy database writers.',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: t('搜索资料', 'Search content'),
                suffixIcon: IconButton(
                  onPressed: _busy ? null : () => _load(),
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final c in ['all', 'note', 'article'])
                  ChoiceChip(
                    selected: _collection == c,
                    label: Text(
                      c == 'all'
                          ? t('全部', 'All')
                          : c == 'note'
                          ? t('笔记', 'Notes')
                          : t('文章', 'Articles'),
                    ),
                    onSelected: _busy
                        ? null
                        : (_) {
                            setState(() => _collection = c);
                            _load();
                          },
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () => _load(),
                    child: Text(t('重试', 'Retry')),
                  ),
                ],
              ),
            ),
          ...[
            if (!_busy && _error == null && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t('没有匹配资料', 'No matching content')),
              ),
            for (final item in _items)
              ListTile(
                leading: Icon(
                  item.metadata.isProtected
                      ? Icons.lock_outline
                      : Icons.description_outlined,
                ),
                title: Text(item.metadata.title),
                subtitle: Text(
                  '${item.metadata.collection} · ${item.metadata.format.name}${item.metadata.isProtected ? ' · ${t('受保护', 'Protected')}' : ''}${item.previewUnavailable ? ' · ' + t('原文已保留，无法预览', 'Original retained; preview unavailable') : ''}',
                ),
                onTap: current && !_busy ? () => _open(item.metadata) : null,
              ),
            if (_hasMore)
              TextButton(
                onPressed: _busy ? null : () => _load(next: true),
                child: Text(t('加载更多', 'Load more')),
              ),
          ],
        ],
      ),
    ),
  );
}
