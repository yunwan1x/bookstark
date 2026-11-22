import 'package:flutter/material.dart';
import '../../core/books_repository.dart';
import '../../core/documents_repository.dart';

class ChaptersPage extends StatefulWidget {
  const ChaptersPage({
    super.key,
    required this.bookId,
    required this.books,
    required this.documents,
    required this.onOpen,
    required this.onSettings,
    this.english = false,
    this.isCurrentScope,
  });
  final int bookId;
  final bool Function()? isCurrentScope;
  final BooksRepository books;
  final DocumentsRepository documents;
  final Future<void> Function(BuildContext, int) onOpen;
  final Future<void> Function(BuildContext, BookItem) onSettings;
  final bool english;
  @override
  State<ChaptersPage> createState() => _ChaptersPageState();
}

class _ChaptersPageState extends State<ChaptersPage> {
  final _search = TextEditingController();
  final _expanded = <int>{};
  List<DocumentNode> _roots = [];
  BookItem? _book;
  bool _loading = true, _busy = false, _refreshRequired = false;
  String? _error;
  int _generation = 0;
  late final _documents = widget.documents;
  late final _books = widget.books;
  late final _bookId = widget.bookId;
  bool get _current =>
      mounted &&
      (widget.isCurrentScope?.call() ?? true) &&
      identical(widget.documents, _documents) &&
      identical(widget.books, _books) &&
      widget.bookId == _bookId;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await _books.read(_bookId);
      final roots = await _documents.tree(_bookId);
      if (!_current || generation != _generation) return;
      setState(() {
        _book = book;
        _roots = roots;
        _refreshRequired = false;
      });
    } catch (error) {
      if (_current && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _write(Future<void> Function() operation) async {
    if (!_current || _busy || _refreshRequired || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (!_current) return;
      setState(() => _refreshRequired = true);
      await _load();
    } catch (error) {
      if (_current) setState(() => _error = error.toString());
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<String?> _nameDialog(String title, {String value = ''}) async {
    final controller = TextEditingController(text: value);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: t('文档名称', 'Document name'),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                try {
                  validateDocumentName(controller.text);
                  Navigator.pop(context, controller.text);
                } catch (failure) {
                  update(() => error = failure.toString());
                }
              },
              child: Text(t('确定', 'Confirm')),
            ),
          ],
        ),
      ),
    );
    // Route exit animation may still reference its editable controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result;
  }

  Future<void> _create({int parentId = 0}) async {
    final name = await _nameDialog(t('新建文档', 'New document'));
    if (name == null || !_current) return;
    int? created;
    await _write(() async {
      created = (await _documents.create(_bookId, name, parentId: parentId)).id;
      if (parentId != 0) _expanded.add(parentId);
    });
    if (created != null && _current && !_refreshRequired) await _open(created!);
  }

  Future<void> _open(int id) async {
    if (!_current || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onOpen(context, id);
      if (_current) await _load();
    } catch (error) {
      if (_current) setState(() => _error = error.toString());
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    if (!_current || _book == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSettings(context, _book!);
      if (_current) await _load();
    } catch (error) {
      if (_current) setState(() => _error = error.toString());
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _move(DocumentNode node) async {
    if (!_current) return;
    final excluded = flattenDocuments([node]).map((item) => item.id).toSet();
    final options = flattenDocuments(
      _roots,
    ).where((item) => !excluded.contains(item.id)).toList();
    final target = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(t('移动到父章节', 'Move to parent chapter')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 0),
            child: Text(t('书籍根目录', 'Book root')),
          ),
          ...options.map(
            (item) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text(item.name),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: Text(t('取消', 'Cancel')),
          ),
        ],
      ),
    );
    if (target == null || !_current) return;
    await _write(() => _documents.move(_bookId, node.id, target));
    if (mounted && !_refreshRequired && target != 0) {
      setState(() => _expanded.add(target));
    }
  }

  Future<void> _menu(DocumentNode node, String action) async {
    if (!_current || _busy || _refreshRequired) return;
    if (action == 'open') {
      await _open(node.id);
      return;
    }
    if (action == 'create') {
      await _create(parentId: node.id);
      return;
    }
    if (action == 'move') {
      await _move(node);
      return;
    }
    if (action == 'rename') {
      final name = await _nameDialog(
        t('重命名文档', 'Rename document'),
        value: node.name,
      );
      if (name != null && _current) {
        await _write(() => _documents.rename(node.id, name));
      }
      return;
    }
    if (action == 'delete') {
      if (node.children.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(t('章节包含子文档', 'Chapter has child documents')),
            content: Text(
              t(
                '请先移动或删除子文档，再删除当前章节。',
                'Move or delete child documents before deleting this chapter.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('知道了', 'OK')),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t('删除文档？', 'Delete document?')),
          content: Text(t('将删除“${node.name}”。', 'Delete “${node.name}”.')),
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
      if (confirmed == true && _current) {
        await _write(() => _documents.remove(node.id));
      }
      return;
    }
    await _write(() => _documents.reorder(node.id, action));
  }

  bool _matches(DocumentNode node) =>
      node.name.toLowerCase().contains(_search.text.toLowerCase()) ||
      node.children.any(_matches);
  List<Widget> _nodes(List<DocumentNode> nodes, {int depth = 0}) {
    final searching = _search.text.isNotEmpty;
    return [
      for (final node in nodes.where(
        (node) => !searching || _matches(node),
      )) ...[
        Padding(
          padding: EdgeInsets.only(left: depth.clamp(0, 3) * 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (node.children.isNotEmpty)
                IconButton(
                  tooltip: t('展开或收起', 'Expand or collapse'),
                  onPressed: () => setState(() {
                    if (!_expanded.add(node.id)) _expanded.remove(node.id);
                  }),
                  icon: Icon(
                    searching || _expanded.contains(node.id)
                        ? Icons.expand_more
                        : Icons.chevron_right,
                  ),
                ),
              if (node.children.isEmpty && depth > 0) const SizedBox(width: 48),
              Expanded(
                child: InkWell(
                  onTap: !_current || _busy ? null : () => _open(node.id),
                  onLongPress: !_current || _busy ? null : () => _move(node),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          node.children.isNotEmpty
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (depth > 3)
                                Text(t('第${depth + 1}层', 'Level ${depth + 1}')),
                              if (node.children.isNotEmpty &&
                                  !searching &&
                                  !_expanded.contains(node.id))
                                Text(
                                  t(
                                    '${flattenDocuments(node.children).length}篇子文档',
                                    '${flattenDocuments(node.children).length} descendant documents',
                                  ),
                                ),
                              if (node.type != 'markdown') Text(node.type),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: t('文档菜单', 'Document menu'),
                enabled: _current && !_busy && !_loading && !_refreshRequired,
                onSelected: (action) => _menu(node, action),
                itemBuilder: (_) => [
                  for (final entry in {
                    'open': t('打开', 'Open'),
                    'rename': t('重命名', 'Rename'),
                    'create': t('新建子文档', 'New child'),
                    'up': t('上移', 'Move up'),
                    'down': t('下移', 'Move down'),
                    'indent': t('缩进', 'Indent'),
                    'outdent': t('提升', 'Outdent'),
                    'move': t('选择父章节', 'Choose parent'),
                    'delete': t('删除', 'Delete'),
                  }.entries)
                    PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (searching || _expanded.contains(node.id))
          ..._nodes(node.children, depth: depth + 1),
      ],
    ];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_book?.name ?? t('章节目录', 'Chapters')),
        actions: [
          IconButton(
            tooltip: t('书籍设置', 'Book settings'),
            onPressed: !_current || _busy || _loading ? null : _settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        tooltip: t('新建文档', 'New document'),
        onPressed: !_current || _busy || _loading || _refreshRequired
            ? null
            : _create,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('搜索本书文档', 'Search this book'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  t('章节目录', 'Chapters'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_book != null)
                  Text(
                    t(
                      '${flattenDocuments(_roots).length}篇文档',
                      '${flattenDocuments(_roots).length} documents',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(onPressed: _load, child: Text(t('重试', 'Retry'))),
            ],
            if (_refreshRequired)
              Text(t('刷新成功后可继续调整', 'Reload before making more changes')),
            if (!_loading && _error == null && !_roots.any(_matches))
              Text(t('没有匹配的文档', 'No matching documents')),
            if (_roots.isNotEmpty)
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _current ? _nodes(_roots) : const <Widget>[],
                ),
              ),
            const SizedBox(height: 24),
            Text(
              t('长按或菜单可调整章节位置', 'Long press or use a menu to move chapters'),
            ),
          ],
        ),
      ),
    ),
  );
}
