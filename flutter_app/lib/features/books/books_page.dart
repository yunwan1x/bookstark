import 'package:flutter/material.dart';
import '../../core/books_repository.dart';
import '../../core/book_draft_vault.dart';
import '../../core/labels_repository.dart';
import 'book_editor_page.dart';

class BooksPage extends StatefulWidget {
  const BooksPage({
    super.key,
    required this.repository,
    required this.labelsRepository,
    required this.onOpen,
    this.vault,
    this.onShareSettings,
    this.onCreate,
    this.english = false,
  });
  final Future<void> Function(BuildContext context)? onCreate;
  final BooksRepository repository;
  final Future<void> Function(BuildContext, BookItem)? onShareSettings;
  final LabelsRepository labelsRepository;
  final Future<void> Function(BuildContext, BookItem) onOpen;
  final BookDraftVault? vault;
  final bool english;
  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  final _search = TextEditingController();
  List<BookItem> _items = [];
  int _page = 1, _generation = 0;
  bool _loading = false,
      _more = false,
      _opening = false,
      _writing = false,
      _refreshRequired = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<void> _share(BookItem book) async {
    final callback = widget.onShareSettings;
    if (callback == null || _opening || _writing) {
      return;
    }
    setState(() => _opening = true);
    try {
      await callback(context, book);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开分享设置。', 'Sharing settings could not be opened.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false, bool refreshLoaded = false}) async {
    if (next && (_loading || !_more)) return;
    final generation = ++_generation;
    final first = next ? _page + 1 : 1;
    final last = refreshLoaded ? _page : first;
    final keyword = _search.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = <BookItem>[];
      BooksPageResult? result;
      for (var page = first; page <= last; page++) {
        result = await widget.repository.list(keyword: keyword, page: page);
        if (!mounted || generation != _generation) return;
        fresh.addAll(result.items);
        if (!result.hasMore) break;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        final byId = <int?, BookItem>{
          for (final item in [...(next ? _items : <BookItem>[]), ...fresh])
            item.id: item,
        };
        _items = byId.values.toList();
        _page = result!.page;
        _more = result.hasMore;
        _refreshRequired = false;
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

  Future<void> _edit(BookItem? item) async {
    if (_opening || _writing || _refreshRequired) return;
    setState(() => _opening = true);
    try {
      if (item == null && widget.onCreate != null) {
        final repository = widget.repository;
        await widget.onCreate!(context);
        if (mounted && identical(repository, widget.repository)) {
          await _load(refreshLoaded: true);
        }
        return;
      }
      final detail = item == null
          ? const BookItem(name: '')
          : await widget.repository.read(item.id!);
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BookEditorPage(
            repository: widget.repository,
            book: detail,
            labelsRepository: widget.labelsRepository,
            vault: widget.vault,
            english: widget.english,
          ),
        ),
      );
      if (changed == true && mounted) {
        setState(() => _refreshRequired = true);
        await _load(refreshLoaded: true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _open(BookItem item) async {
    if (_opening || _writing) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen(context, item);
      if (mounted) await _load(refreshLoaded: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _remove(BookItem item) async {
    if (_opening || _writing || _refreshRequired) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('删除书籍及全部文档？', 'Delete book and all documents?')),
        content: Text(
          t(
            '将删除“${item.name}”、全部下级文档和相关分享。',
            'This deletes “${item.name}”, all its documents and related shares.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await widget.repository.remove(item.id!);
      if (!mounted) return;
      setState(() {
        _writing = false;
        _refreshRequired = true;
      });
      await _load(refreshLoaded: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_writing,
      child: Scaffold(
        appBar: AppBar(title: Text(t('书籍', 'Books'))),
        floatingActionButton: FloatingActionButton(
          shape: const CircleBorder(),
          tooltip: t('新建书籍', 'New book'),
          onPressed: _opening || _writing || _refreshRequired
              ? null
              : () => _edit(null),
          child: const Icon(Icons.add),
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(refreshLoaded: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                controller: _search,
                enabled: !_writing,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: t('搜索书名或标签', 'Search book names or labels'),
                  suffixIcon: IconButton(
                    tooltip: t('搜索', 'Search'),
                    onPressed: _writing ? null : () => _load(),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t('你的知识书架', 'Your knowledge shelf'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(t('按最近更新排序', 'Sorted by latest update')),
              const SizedBox(height: 16),
              if (_loading || _opening || _writing)
                const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                TextButton(
                  onPressed: () => _load(refreshLoaded: true),
                  child: Text(t('重新加载', 'Reload')),
                ),
              ],
              if (_refreshRequired)
                Text(
                  t(
                    '刷新成功后可继续修改',
                    'Reload successfully before making more changes',
                  ),
                ),
              if (!_loading && _items.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t('还没有书籍', 'No books yet')),
                ),
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _opening || _writing ? null : () => _open(item),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 56,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.menu_book_outlined,
                                  color: theme.colorScheme.primary,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  if (item.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        item.description,
                                        maxLines: 1,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (item.labelText.isNotEmpty)
                                        Text(
                                          item.labelText,
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      Text(
                                        t(
                                          '${item.documentCount}篇文档',
                                          '${item.documentCount} documents',
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      if (item.modifiedAt != null)
                                        Text(
                                          MaterialLocalizations.of(
                                            context,
                                          ).formatShortMonthDay(
                                            item.modifiedAt!,
                                          ),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: t('书籍菜单', 'Book menu'),
                              enabled:
                                  !_opening && !_writing && !_refreshRequired,
                              onSelected: (action) {
                                if (action == 'edit') {
                                  _edit(item);
                                } else if (action == 'sharing') {
                                  _share(item);
                                } else {
                                  _remove(item);
                                }
                              },
                              itemBuilder: (_) => [
                                if (widget.onShareSettings != null)
                                  PopupMenuItem(
                                    value: 'sharing',
                                    child: Text(t('分享设置', 'Sharing settings')),
                                  ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(t('设置', 'Settings')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(t('删除', 'Delete')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_more)
                TextButton(
                  onPressed: _loading ? null : () => _load(next: true),
                  child: Text(t('加载更多', 'Load more')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
