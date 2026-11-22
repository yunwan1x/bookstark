import '../../core/bookmark_favicon_store.dart';
import '../../widgets/bookmark_favicon.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/bookmark_draft_vault.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'package:bookstark_flutter/widgets/label_picker.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmark_editor_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({
    super.key,
    required this.repository,
    required this.labelsRepository,
    this.vault,
    this.english = false,
    this.local = false,
    this.faviconScopeKey,
    this.faviconIsCurrent,
    this.faviconStoreFactory,
    this.recoverCreation,
  });
  final Future<BookmarkItem?> Function()? recoverCreation;
  final BookmarksRepository repository;
  final LabelsRepository labelsRepository;
  final BookmarkDraftVault? vault;
  final bool english, local;
  final Object? faviconScopeKey;
  final bool Function()? faviconIsCurrent;
  final BookmarkFaviconStore Function()? faviconStoreFactory;
  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  late BookmarkFaviconStore _favicons;
  final _search = TextEditingController();
  BookmarkQuery _query = const BookmarkQuery();
  List<BookmarkItem> _items = [];
  final Set<int> _selected = {};
  int _total = 0, _page = 0, _generation = 0, _ownerEpoch = 0, _pageSize = 20;
  bool _owns(int epoch, BookmarksRepository repository) =>
      mounted &&
      epoch == _ownerEpoch &&
      identical(repository, widget.repository);
  bool _loading = true,
      _more = false,
      _busy = false,
      _selecting = false,
      _refreshRequired = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _favicons = widget.faviconStoreFactory?.call() ?? BookmarkFaviconStore();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookmarksPage old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository ||
        old.local != widget.local ||
        old.faviconScopeKey != widget.faviconScopeKey ||
        old.faviconStoreFactory != widget.faviconStoreFactory) {
      _favicons.retire();
      _favicons = widget.faviconStoreFactory?.call() ?? BookmarkFaviconStore();
      _ownerEpoch++;
      _busy = false;
      _selecting = false;
      _generation++;
      _items = [];
      _selected.clear();
      _total = 0;
      _page = 0;
      _more = false;
      _error = null;
      _refreshRequired = false;
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _favicons.retire();
    _search.dispose();
    _generation++;
    _ownerEpoch++;
    super.dispose();
  }

  Future<void> _load({bool more = false, bool reloadLoaded = false}) async {
    final generation = ++_generation;
    final query = _query;
    final target = more
        ? _page + 1
        : reloadLoaded
        ? (_page < 1 ? 1 : _page)
        : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = more ? List<BookmarkItem>.of(_items) : <BookmarkItem>[];
      BookmarkPageResult? result;
      int? expectedTotal = more ? _total : null,
          expectedPageSize = more ? _pageSize : null;
      for (var page = more ? target : 1; page <= target; page++) {
        result = await widget.repository.list(query.atPage(page));
        if (!mounted || generation != _generation) return;
        if (result.page != page ||
            result.items.any((item) => item.id == null || item.id! <= 0) ||
            result.total < 0 ||
            result.pageSize < 1 ||
            result.pageSize > 200 ||
            (expectedTotal != null && result.total != expectedTotal) ||
            (expectedPageSize != null && result.pageSize != expectedPageSize) ||
            result.items.length !=
                (result.total - (page - 1) * result.pageSize).clamp(
                  0,
                  result.pageSize,
                )) {
          throw const FormatException('Invalid bookmark page');
        }
        expectedTotal ??= result.total;
        expectedPageSize ??= result.pageSize;
        rows.addAll(result.items);
        if (!result.hasMore) break;
      }
      if (rows.map((item) => item.id).toSet().length != rows.length) {
        throw StateError(
          t('列表有变化，请刷新后继续', 'List changed; refresh to continue'),
        );
      }
      setState(() {
        _items = rows;
        _total = result!.total;
        _page = result.page;
        _pageSize = result.pageSize;
        _more = result.hasMore;
        _refreshRequired = false;
        _selected.removeWhere(
          (id) => !rows.any(
            (item) => item.id == id && widget.repository.canEdit(item),
          ),
        );
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

  ValueChanged<T> _ownedSelection<T>(Future<void> Function(T) action) {
    final epoch = _ownerEpoch, repository = widget.repository;
    return (value) {
      if (_owns(epoch, repository)) action(value);
    };
  }

  BookmarkQuery _searchQuery(String keyword, {List<String>? labels}) =>
      BookmarkQuery(
        scope: _query.scope,
        keyword: keyword,
        labels: labels ?? _query.labels,
        labelsOr: _query.labelsOr,
        isPublic: _query.isPublic,
        isPinned: _query.isPinned,
        navVisible: _query.navVisible,
        noLabel: _query.noLabel,
        site: _query.site,
        start: _query.start,
        end: _query.end,
        modified: _query.modified,
      );
  void _changeQuery(BookmarkQuery value) {
    if (_busy) return;
    _query = value;
    _selected.clear();
    _selecting = false;
    _items = [];
    _page = 0;
    _total = 0;
    _load();
  }

  Future<void> _recoverCreation() async {
    if (_busy || widget.recoverCreation == null) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    BookmarkItem? actual;
    try {
      actual = await widget.recoverCreation!();
    } catch (_) {
      if (_owns(epoch, repository)) {
        setState(() {
          _error = t('恢复记录不可用，请重新核对', 'Recovery unavailable. Review again.');
        });
      }
    } finally {
      if (_owns(epoch, repository)) {
        setState(() {
          _busy = false;
        });
      }
    }
    if (!_owns(epoch, repository)) return;
    // Actual owner-scoped complete snapshot, never an item inferred from URL.
    if (actual != null) await _edit(actual);
  }

  Future<void> _edit([BookmarkItem? item]) async {
    if (_busy || _loading || _refreshRequired) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookmarkEditorPage(
          repository: widget.repository,
          bookmark:
              item ??
              BookmarkItem(
                title: '',
                url: '',
                memberId: widget.repository.memberId,
              ),
          labelsRepository: widget.labelsRepository,
          vault: widget.vault,
          english: widget.english,
          local: widget.local,
        ),
      ),
    );
    if (changed == true && _owns(epoch, repository)) {
      await _load(reloadLoaded: true);
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
  Future<void> _mutate(Future<void> Function() operation) async {
    if (_busy || _loading || _refreshRequired) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    setState(() => _busy = true);
    try {
      await operation();
      if (_owns(epoch, repository)) await _load(reloadLoaded: true);
    } catch (error) {
      if (_owns(epoch, repository)) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (_owns(epoch, repository)) setState(() => _busy = false);
    }
  }

  String _actionName(BookmarkBatch action) => switch (action) {
    BookmarkBatch.delete => t('删除', 'Delete'),
    BookmarkBatch.share => t('设为公开', 'Make public'),
    BookmarkBatch.unshare => t('设为私密', 'Make private'),
    BookmarkBatch.pin => t('置顶', 'Pin'),
    BookmarkBatch.unpin => t('取消置顶', 'Unpin'),
    BookmarkBatch.addLabels => t('添加标签', 'Add labels'),
    BookmarkBatch.removeLabels => t('移除标签', 'Remove labels'),
    BookmarkBatch.showNav => t('显示到导航', 'Show in navigation'),
    BookmarkBatch.hideNav => t('从导航隐藏', 'Hide from navigation'),
  };
  Future<void> _batch(BookmarkBatch action) async {
    final epoch = _ownerEpoch, repository = widget.repository;
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    List<String> labels = [];
    if ({
      BookmarkBatch.addLabels,
      BookmarkBatch.removeLabels,
    }.contains(action)) {
      labels =
          await showLabelPicker(
            context,
            repository: widget.labelsRepository,
            selected: [],
            english: widget.english,
          ) ??
          [];
      if (labels.isEmpty || !_owns(epoch, repository)) return;
    }
    if (!await _confirm(
          _actionName(action),
          t(
            '对已选的${ids.length}条书签执行此操作？',
            'Apply to ${ids.length} selected bookmarks?',
          ),
        ) ||
        !_owns(epoch, repository)) {
      return;
    }
    await _mutate(() => repository.batch(action, ids, labels: labels));
    if (_owns(epoch, repository) && _error == null) {
      setState(() => _selected.clear());
    }
  }

  Future<void> _menu(BookmarkItem item, String action) async {
    final epoch = _ownerEpoch, repository = widget.repository;
    if (!repository.canEdit(item)) return;
    switch (action) {
      case 'edit':
        await _edit(item);
      case 'delete':
        if (await _confirm(
              t('删除书签', 'Delete bookmark'),
              '${item.title}\n${item.url}',
            ) &&
            _owns(epoch, repository)) {
          await _mutate(() => repository.remove(item.id!));
        }
      case 'public':
        if (await _confirm(
              item.isPublic
                  ? t('设为私密', 'Make private')
                  : t('设为公开', 'Make public'),
              item.title,
            ) &&
            _owns(epoch, repository)) {
          await _mutate(() => repository.setPublic(item.id!, !item.isPublic));
        }
      case 'nav':
        await _mutate(
          () => repository.setNavVisible(item.id!, !item.navVisible),
        );
      case 'pin':
        if (!repository.isAdmin) return;
        await _mutate(
          () => repository.batch(
            item.isPinned ? BookmarkBatch.unpin : BookmarkBatch.pin,
            [item.id!],
          ),
        );
      case 'favicon':
        await _mutate(() => repository.refreshFavicon(item.id!));
    }
  }

  Future<void> _filter() async {
    final epoch = _ownerEpoch, repository = widget.repository;
    final result = await showDialog<BookmarkQuery>(
      context: context,
      builder: (_) => _BookmarkFilter(
        query: _query,
        english: widget.english,
        labelsRepository: widget.labelsRepository,
      ),
    );
    if (result != null && _owns(epoch, repository)) _changeQuery(result);
  }

  Widget _favicon(BookmarkItem item) {
    final generation = _generation,
        store = _favicons,
        scope = widget.faviconScopeKey;
    return BookmarkFavicon(
      key: ValueKey((item.id, item.favicon, generation, scope)),
      explicitUrl: item.favicon,
      store: store,
      scopeKey: (widget.repository, generation, scope),
      isCurrent: () =>
          mounted &&
          generation == _generation &&
          identical(store, _favicons) &&
          scope == widget.faviconScopeKey &&
          !store.retired &&
          (widget.faviconIsCurrent?.call() ?? true),
    );
  }

  Widget _card(BookmarkItem item) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selecting && widget.repository.canEdit(item))
            Checkbox(
              value: _selected.contains(item.id),
              onChanged: _busy || _loading
                  ? null
                  : (value) => setState(() {
                      if (value == true && _selected.length < 200) {
                        _selected.add(item.id!);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _favicon(item),
              ),
            ),
          Expanded(
            child: InkWell(
              onTap: _selecting
                  ? null
                  : () => openBookstarkLink(
                      context,
                      item.title,
                      item.url,
                      english: widget.english,
                    ),
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
                  const SizedBox(height: 4),
                  Text(Uri.tryParse(item.url)?.host ?? item.url),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.description),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final label in item.labels)
                        _badge(
                          label.isEmpty
                              ? t('空名称标签', 'Empty-name label')
                              : label,
                          true,
                        ),
                      _badge(
                        item.isPublic ? t('公开', 'Public') : t('私密', 'Private'),
                        false,
                      ),
                      if (item.navVisible) _badge(t('导航', 'Navigation'), false),
                      if (item.isPinned) _badge(t('置顶', 'Pinned'), false),
                      if (item.account.isNotEmpty) _badge(item.account, false),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!_selecting && widget.repository.canEdit(item))
            PopupMenuButton<String>(
              tooltip: t('书签操作', 'Bookmark actions'),
              enabled: !_loading && !_busy && !_refreshRequired,
              onSelected: _ownedSelection((value) => _menu(item, value)),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
                PopupMenuItem(
                  value: 'public',
                  child: Text(
                    item.isPublic
                        ? t('设为私密', 'Make private')
                        : t('设为公开', 'Make public'),
                  ),
                ),
                PopupMenuItem(
                  value: 'nav',
                  child: Text(
                    item.navVisible
                        ? t('从导航隐藏', 'Hide from navigation')
                        : t('显示到导航', 'Show in navigation'),
                  ),
                ),
                if (widget.repository.isAdmin)
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(
                      item.isPinned ? t('取消置顶', 'Unpin') : t('置顶', 'Pin'),
                    ),
                  ),
                if (!widget.local)
                  PopupMenuItem(
                    value: 'favicon',
                    child: Text(t('刷新图标', 'Refresh icon')),
                  ),
                PopupMenuItem(value: 'delete', child: Text(t('删除', 'Delete'))),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _badge(String text, bool primary) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: primary
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: primary ? Theme.of(context).colorScheme.primary : null,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('书签', 'Bookmarks')),
      actions: [
        if (!widget.local && widget.recoverCreation != null)
          IconButton(
            tooltip: t('创建恢复记录', 'Creation recovery'),
            onPressed: _busy ? null : _recoverCreation,
            icon: const Icon(Icons.history),
          ),
        IconButton(
          tooltip: _selecting
              ? t('结束选择', 'Finish selecting')
              : t('批量选择', 'Select bookmarks'),
          onPressed: _busy || _loading
              ? null
              : () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
          icon: Icon(_selecting ? Icons.close : Icons.checklist),
        ),
      ],
    ),
    floatingActionButton: _selecting
        ? null
        : FloatingActionButton(
            shape: const CircleBorder(),
            tooltip: t('新建书签', 'New bookmark'),
            onPressed: _loading || _busy || _refreshRequired
                ? null
                : () => _edit(),
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
                labelText: t('搜索标题、网址或说明', 'Search title, URL or description'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: t('搜索', 'Search'),
                  onPressed: _busy
                      ? null
                      : () => _changeQuery(_searchQuery(_search.text)),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              onSubmitted: _busy
                  ? null
                  : (value) => _changeQuery(_searchQuery(value)),
            ),
            const SizedBox(height: 16),
            if (!widget.local) ...[
              SegmentedButton<BookmarkScope>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: BookmarkScope.mine,
                    label: Text(t('我的', 'Mine')),
                  ),
                  ButtonSegment(
                    value: BookmarkScope.public,
                    label: Text(t('公开', 'Public')),
                  ),
                ],
                selected: {_query.scope},
                onSelectionChanged: _busy
                    ? null
                    : (values) => _changeQuery(
                        BookmarkQuery(
                          scope: values.single,
                          keyword: _search.text,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final epoch = _ownerEpoch,
                              repository = widget.repository;
                          final names = await showLabelPicker(
                            context,
                            repository: widget.labelsRepository,
                            selected: _query.labels,
                            english: widget.english,
                          );
                          if (names != null && _owns(epoch, repository)) {
                            _changeQuery(
                              _searchQuery(_search.text, labels: names),
                            );
                          }
                        },
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    _query.labels.isEmpty
                        ? t('全部标签', 'All labels')
                        : _query.labels.join('、'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _filter,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: Text(t('筛选', 'Filters')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _search.clear();
                          _changeQuery(BookmarkQuery(scope: _query.scope));
                        },
                  child: Text(t('重置', 'Reset')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _query.scope == BookmarkScope.mine
                  ? t('我的收藏', 'My collection')
                  : t('公开书签', 'Public bookmarks'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(t('$_total条书签', '$_total bookmarks')),
            const SizedBox(height: 12),
            if (_selecting) ...[
              Text(
                t(
                  '已选择${_selected.length}/200条（仅已加载条目）',
                  '${_selected.length}/200 selected (loaded rows only)',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selected.clear();
                            _selected.addAll(
                              _items
                                  .where(widget.repository.canEdit)
                                  .take(200)
                                  .map((item) => item.id!),
                            );
                          }),
                    child: Text(t('选择已加载条目', 'Select loaded rows')),
                  ),
                  PopupMenuButton<BookmarkBatch>(
                    enabled:
                        !_busy &&
                        !_loading &&
                        !_refreshRequired &&
                        _selected.isNotEmpty,
                    tooltip: t('批量操作', 'Batch actions'),
                    onSelected: _ownedSelection(_batch),
                    itemBuilder: (_) => [
                      for (final action in BookmarkBatch.values)
                        PopupMenuItem(
                          value: action,
                          child: Text(_actionName(action)),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(t('批量操作', 'Batch actions')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
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
                child: Text(t('暂无书签', 'No bookmarks')),
              ),
            if (_more && !_refreshRequired)
              OutlinedButton(
                onPressed: _loading || _busy ? null : () => _load(more: true),
                child: Text(t('加载更多', 'Load more')),
              ),
          ],
        ),
      ),
    ),
  );
}

class _BookmarkFilter extends StatefulWidget {
  const _BookmarkFilter({
    required this.query,
    required this.english,
    required this.labelsRepository,
  });
  final BookmarkQuery query;
  final bool english;
  final LabelsRepository labelsRepository;
  @override
  State<_BookmarkFilter> createState() => _BookmarkFilterState();
}

class _BookmarkFilterState extends State<_BookmarkFilter> {
  late bool? _public = widget.query.isPublic,
      _pinned = widget.query.isPinned,
      _nav = widget.query.navVisible;
  late bool _noLabel = widget.query.noLabel, _modified = widget.query.modified;
  late List<String> _and = List.of(widget.query.labels),
      _or = List.of(widget.query.labelsOr);
  late final _site = TextEditingController(text: widget.query.site);
  late final _start = TextEditingController(
    text: widget.query.start?.toIso8601String() ?? '',
  );
  late final _end = TextEditingController(
    text: widget.query.end?.toIso8601String() ?? '',
  );
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _site.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Widget _flag(String label, bool? value, ValueChanged<bool?> changed) =>
      DropdownButtonFormField<int>(
        initialValue: value == null
            ? -1
            : value
            ? 1
            : 0,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: -1, child: Text(t('全部', 'Any'))),
          DropdownMenuItem(value: 1, child: Text(t('是', 'Yes'))),
          DropdownMenuItem(value: 0, child: Text(t('否', 'No'))),
        ],
        onChanged: (value) => changed(value == -1 ? null : value == 1),
      );
  void _apply() {
    try {
      DateTime? parse(String value) {
        if (value.isEmpty) return null;
        final result = DateTime.tryParse(value);
        if (result == null ||
            result.toIso8601String().substring(0, 10) !=
                value.substring(0, 10)) {
          throw const FormatException('日期格式错误 / Invalid date');
        }
        return result;
      }

      final query = BookmarkQuery(
        scope: widget.query.scope,
        keyword: widget.query.keyword,
        labels: _and,
        labelsOr: _or,
        isPublic: _public,
        isPinned: _pinned,
        navVisible: _nav,
        noLabel: _noLabel,
        modified: _modified,
        site: _site.text,
        start: parse(_start.text),
        end: parse(_end.text),
      );
      query.parameters();
      Navigator.pop(context, query);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t('筛选书签', 'Filter bookmarks')),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.query.scope == BookmarkScope.mine)
            _flag(t('公开', 'Public'), _public, (value) => _public = value),
          const SizedBox(height: 12),
          _flag(t('置顶', 'Pinned'), _pinned, (value) => _pinned = value),
          const SizedBox(height: 12),
          _flag(t('导航显示', 'Navigation'), _nav, (value) => _nav = value),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final result = await showLabelPicker(
                context,
                repository: widget.labelsRepository,
                selected: _and,
                english: widget.english,
              );
              if (result != null && mounted) setState(() => _and = result);
            },
            child: Text('AND: ${_and.join('、')}'),
          ),
          OutlinedButton(
            onPressed: () async {
              final result = await showLabelPicker(
                context,
                repository: widget.labelsRepository,
                selected: _or,
                english: widget.english,
              );
              if (result != null && mounted) setState(() => _or = result);
            },
            child: Text('OR: ${_or.join('、')}'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('仅无标签', 'Without labels')),
            value: _noLabel,
            onChanged: (value) => setState(() => _noLabel = value),
          ),
          TextField(
            controller: _site,
            decoration: InputDecoration(
              labelText: t('站点域名（可含端口）', 'Site host (optional port)'),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('按修改时间筛选', 'Use modification time')),
            value: _modified,
            onChanged: (value) => setState(() => _modified = value),
          ),
          TextField(
            controller: _start,
            decoration: InputDecoration(
              labelText: t('起始日期时间', 'Start date/time'),
              helperText: 'YYYY-MM-DDTHH:mm:ss',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _end,
            decoration: InputDecoration(
              labelText: t('截止日期时间', 'End date/time'),
              helperText: 'YYYY-MM-DDTHH:mm:ss',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(onPressed: _apply, child: Text(t('应用', 'Apply'))),
    ],
  );
}
