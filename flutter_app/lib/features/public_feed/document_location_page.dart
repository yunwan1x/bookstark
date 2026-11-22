import 'package:flutter/material.dart';
import '../../core/books_repository.dart';
import '../../core/documents_repository.dart';

class DocumentLocation {
  const DocumentLocation({
    required this.book,
    required this.parentId,
    required this.parentName,
  });
  final BookItem book;
  final int parentId;
  final String parentName;
}

class DocumentLocationPage extends StatefulWidget {
  const DocumentLocationPage({
    super.key,
    required this.books,
    required this.documents,
    this.initialBook,
    this.english = false,
  });
  final BooksRepository books;
  final DocumentsRepository documents;
  final BookItem? initialBook;
  final bool english;
  @override
  State<DocumentLocationPage> createState() => _DocumentLocationPageState();
}

class _DocumentLocationPageState extends State<DocumentLocationPage> {
  BookItem? _book;
  List<DocumentNode> _roots = [], _path = [];
  bool _loading = false, _confirming = false, _ready = false;
  int _generation = 0;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    if (widget.initialBook != null) _loadBook(widget.initialBook!);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Map<int, DocumentNode> _validate(List<DocumentNode> roots) {
    final index = <int, DocumentNode>{};
    void visit(List<DocumentNode> rows, int parent, int depth) {
      if (depth > 256) throw const FormatException('Document tree too deep');
      for (final node in rows) {
        if (node.id <= 0 ||
            node.parentId != parent ||
            index.containsKey(node.id)) {
          throw const FormatException('Invalid parent membership');
        }
        index[node.id] = node;
        visit(node.children, node.id, depth + 1);
      }
    }

    visit(roots, 0, 0);
    return index;
  }

  Future<void> _loadBook(BookItem book) async {
    final generation = ++_generation;
    setState(() {
      _book = book;
      _roots = [];
      _path = [];
      _loading = true;
      _ready = false;
      _error = null;
    });
    try {
      final id = book.id;
      if (id == null || id <= 0) {
        throw const FormatException('Missing book identity');
      }
      final actual = await widget.books.read(id);
      if (actual.id != id) throw const FormatException('Book identity changed');
      final roots = await widget.documents.tree(id);
      _validate(roots);
      if (!mounted || generation != _generation) return;
      setState(() {
        _book = actual;
        _roots = roots;
        _ready = true;
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

  Future<void> _chooseBook() async {
    if (_confirming) return;
    final result = await showModalBottomSheet<BookItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: _BookPicker(books: widget.books, english: widget.english),
      ),
    );
    if (mounted && result != null) await _loadBook(result);
  }

  Future<void> _confirm() async {
    final book = _book;
    if (!_ready || _loading || _confirming || book?.id == null) return;
    final generation = _generation;
    final parentId = _path.isEmpty ? 0 : _path.last.id;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final actual = await widget.books.read(book!.id!);
      if (actual.id != book.id) {
        throw const FormatException('Book identity changed');
      }
      final roots = await widget.documents.tree(book.id!);
      final index = _validate(roots);
      if (!mounted || generation != _generation) return;
      if (parentId != 0 && !index.containsKey(parentId)) {
        setState(() {
          _roots = roots;
          _path = [];
          _error = t(
            '所选父目录已删除，请重新选择。',
            'The selected parent was removed. Choose a location again.',
          );
        });
        return;
      }
      Navigator.of(context).pop(
        DocumentLocation(
          book: actual,
          parentId: parentId,
          parentName: parentId == 0
              ? t('书籍根目录', 'Book root')
              : index[parentId]!.name,
        ),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _ready = false;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _confirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _path.isEmpty ? t('书籍根目录', 'Book root') : _path.last.name;
    final children = _path.isEmpty ? _roots : _path.last.children;
    return Scaffold(
      appBar: AppBar(title: Text(t('选择文档位置', 'Choose document location'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: !_ready || _loading || _confirming ? null : _confirm,
                child: Text(
                  _confirming
                      ? t('正在核对…', 'Verifying…')
                      : t('选择此位置', 'Choose this location'),
                ),
              ),
              TextButton(
                onPressed: _confirming
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t('所属书籍', 'Book'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _confirming ? null : _chooseBook,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_book?.name ?? t('请选择书籍', 'Choose a book')),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t('文档继承所属书籍的访问范围。', 'Documents inherit access from their book.'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Divider(),
            ),
            Text(
              t('父目录', 'Parent'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_loading || _confirming) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _book == null || _confirming
                    ? null
                    : () => _loadBook(_book!),
                child: Text(t('重新加载', 'Reload')),
              ),
            ],
            if (_ready) ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _confirming
                        ? null
                        : () => setState(() => _path = []),
                    icon: const Icon(Icons.home_outlined),
                    label: Text(t('书籍根目录', 'Book root')),
                  ),
                  for (var index = 0; index < _path.length; index++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chevron_right),
                        Flexible(
                          child: TextButton(
                            onPressed: _confirming
                                ? null
                                : () => setState(
                                    () =>
                                        _path = _path.take(index + 1).toList(),
                                  ),
                            child: Text(_path[index].name),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    if (_path.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: Text(t('返回上一级', 'Up one level')),
                        onTap: _confirming
                            ? null
                            : () => setState(
                                () => _path = _path
                                    .take(_path.length - 1)
                                    .toList(),
                              ),
                      ),
                    for (final node in children)
                      ListTile(
                        leading: Icon(
                          Icons.folder_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(node.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _confirming
                            ? null
                            : () => setState(() {
                                _path = [..._path, node];
                                _error = null;
                              }),
                      ),
                    if (children.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(t('此位置暂无子目录', 'No child locations')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('当前选择：$current', 'Selected: $current'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t(
                              '只选择位置，尚未创建文档。',
                              'This selects a location. No document has been created.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookPicker extends StatefulWidget {
  const _BookPicker({required this.books, required this.english});
  final BooksRepository books;
  final bool english;
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  final _search = TextEditingController();
  final _items = <BookItem>[];
  String _keyword = '';
  int _page = 0, _generation = 0;
  bool _loading = false, _more = false;
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
    if (more && (_loading || !_more)) return;
    final generation = ++_generation, page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _items.clear();
    });
    try {
      final result = await widget.books.list(keyword: _keyword, page: page);
      if (!mounted || generation != _generation) return;
      if (result.page != page ||
          result.items.any((book) => book.id == null || book.id! <= 0) ||
          result.items.map((book) => book.id).toSet().length !=
              result.items.length) {
        throw const FormatException('Invalid book page');
      }
      setState(() {
        final ids = _items.map((book) => book.id).toSet();
        _items.addAll(result.items.where((book) => ids.add(book.id)));
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
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('选择书籍', 'Choose a book'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: t('关闭', 'Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(labelText: t('搜索书籍', 'Search books')),
          onSubmitted: (value) {
            _keyword = value;
            _load();
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        Expanded(
          child: ListView(
            children: [
              for (final book in _items)
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book.name),
                  onTap: () => Navigator.of(context).pop(book),
                ),
              if (!_loading && _items.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t('暂无匹配书籍', 'No matching books')),
                ),
              if (_more || _error != null)
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => _load(more: _items.isNotEmpty),
                  child: Text(
                    _error == null ? t('加载更多', 'Load more') : t('重试', 'Retry'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
