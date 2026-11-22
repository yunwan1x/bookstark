import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_feed_models.dart';
import '../../core/public_feed_repository.dart';

class PublicFeedPage extends StatefulWidget {
  const PublicFeedPage({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onCreate,
    this.english = false,
  });
  final PublicFeedRepository repository;
  final Future<void> Function(PublicFeedItem) onOpen;
  final Future<void> Function() onCreate;
  final bool english;
  @override
  State<PublicFeedPage> createState() => _PublicFeedPageState();
}

class _PublicFeedPageState extends State<PublicFeedPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  PublicFeedQuery _query = PublicFeedQuery();
  PublicFeedPageData? _data;
  Completer<void>? _abort;
  int _generation = 0;
  bool _loading = false, _opening = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load(_query);
  }

  @override
  void dispose() {
    _generation++;
    _abort?.complete();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(PublicFeedQuery query) async {
    _abort?.complete();
    final abort = _abort = Completer<void>();
    final generation = ++_generation;
    setState(() {
      _query = query;
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.repository.load(
        query,
        abortTrigger: abort.future,
      );
      if (!mounted || generation != _generation) return;
      if (data.query != query) {
        throw const FormatException('Public feed query mismatch');
      }
      setState(() => _data = data);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _generation &&
            _scroll.hasClients &&
            _scroll.position.hasContentDimensions) {
          _scroll.jumpTo(0);
        }
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

  void _submitSearch(String value) {
    try {
      unawaited(_load(_query.copyWith(keyword: value, page: 1)));
    } on FormatException catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _kind(PublicFeedKind kind) => switch (kind) {
    PublicFeedKind.article => t('文章', 'Articles'),
    PublicFeedKind.note => t('笔记', 'Notes'),
    PublicFeedKind.book => t('书籍', 'Books'),
    PublicFeedKind.bookmark => t('书签', 'Bookmarks'),
  };
  IconData _icon(PublicFeedKind kind) => switch (kind) {
    PublicFeedKind.article => Icons.article_outlined,
    PublicFeedKind.note => Icons.edit_note,
    PublicFeedKind.book => Icons.menu_book_outlined,
    PublicFeedKind.bookmark => Icons.bookmark_border,
  };
  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('公开广场', 'Public feed')),
        actions: [
          IconButton(
            tooltip: t('刷新', 'Refresh'),
            onPressed: _loading ? null : () => _load(_query),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _opening ? null : () => _action(widget.onCreate),
        icon: const Icon(Icons.add),
        label: Text(t('新建资源', 'Create resource')),
        shape: const StadiumBorder(),
      ),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: t('搜索公开内容', 'Search public content'),
                        prefixIcon: const Icon(Icons.search),
                        counterText: '',
                        suffixIcon: IconButton(
                          tooltip: t('搜索', 'Search'),
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => _submitSearch(_search.text),
                        ),
                      ),
                      onSubmitted: _submitSearch,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kind in PublicFeedKind.values)
                          ChoiceChip(
                            label: Text(_kind(kind)),
                            showCheckmark: false,
                            shape: const StadiumBorder(),
                            selectedColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            labelStyle: TextStyle(
                              color: _query.kind == kind
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                            ),
                            selected: _query.kind == kind,
                            onSelected: (_) => _load(
                              _query.copyWith(kind: kind, label: '', page: 1),
                            ),
                          ),
                      ],
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          spacing: 8,
                          children: [
                            for (final category in data.categories)
                              FilterChip(
                                label: Text(
                                  category.label.isEmpty
                                      ? t('全部标签', 'All labels')
                                      : category.label,
                                ),
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                selectedColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                side: BorderSide(
                                  color: category.selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                ),
                                labelStyle: TextStyle(
                                  color: category.selected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                selected: category.selected,
                                onSelected: (_) => _load(
                                  _query.copyWith(
                                    label: category.label,
                                    page: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        for (final sort in PublicFeedSort.values)
                          Semantics(
                            selected: _query.sort == sort,
                            button: true,
                            child: InkWell(
                              onTap: () =>
                                  _load(_query.copyWith(sort: sort, page: 1)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      width: 3,
                                      color: _query.sort == sort
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  sort == PublicFeedSort.latest
                                      ? t('最新分享', 'Latest shares')
                                      : t('最近更新', 'Recently updated'),
                                  style: TextStyle(
                                    fontWeight: _query.sort == sort
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: _query.sort == sort
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('浏览所有人公开的内容', 'Browse publicly shared content'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _load(_query),
                          child: Text(t('重试', 'Retry')),
                        ),
                      ),
                    ],
                    if (data != null && data.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          t('暂无匹配的公开内容', 'No matching public content'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (data != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: data.items.length,
                  itemBuilder: (context, index) {
                    final item = data.items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: _opening
                            ? null
                            : () => _action(() => widget.onOpen(item)),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(_icon(item.kind), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.format.isEmpty
                                          ? _kind(item.kind)
                                          : item.format,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                    ),
                                  ),
                                  if (item.pinned)
                                    Icon(
                                      Icons.push_pin_outlined,
                                      semanticLabel: t('置顶', 'Pinned'),
                                      size: 18,
                                    ),
                                  if (item.locked)
                                    Icon(
                                      Icons.lock_outline,
                                      semanticLabel: t(
                                        '需密码',
                                        'Password required',
                                      ),
                                      size: 18,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                item.title.isEmpty && item.locked
                                    ? t('加密内容', 'Protected content')
                                    : item.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              if (item.locked)
                                Text(t('需密码查看', 'Password required to read'))
                              else if (item.excerpt.isNotEmpty)
                                Text(
                                  item.excerpt,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  if (item.author.isNotEmpty) Text(item.author),
                                  if (item.date.isNotEmpty) Text(item.date),
                                ],
                              ),
                              if (!item.locked && item.labels.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final label in item.labels)
                                        ActionChip(
                                          label: Text(label),
                                          shape: const StadiumBorder(),
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          side: BorderSide.none,
                                          onPressed: () => _load(
                                            _query.copyWith(
                                              label: label,
                                              page: 1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (data != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: data.previous == null
                            ? null
                            : () => _load(data.previous!),
                        child: Text(t('上一页', 'Previous')),
                      ),
                      Text(t('第${_query.page}页', 'Page ${_query.page}')),
                      OutlinedButton(
                        onPressed: data.next == null
                            ? null
                            : () => _load(data.next!),
                        child: Text(t('下一页', 'Next')),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
