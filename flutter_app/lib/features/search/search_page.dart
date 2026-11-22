import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/search_repository.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    required this.onOpenHit,
    this.initialQuery = '',
    this.english = false,
    this.local = false,
    this.scopeIdentity,
  });
  final SearchRepository repository;
  final Object? scopeIdentity;
  final Future<void> Function(SearchHit hit) onOpenHit;
  final String initialQuery;
  final bool english, local;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final _query = TextEditingController(text: widget.initialQuery);
  SearchResults? _results;
  SearchKind? _kind;
  bool _loading = false, _opening = false;
  int _generation = 0, _ownerEpoch = 0;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _query.addListener(_input);
    if (widget.initialQuery.trim().isNotEmpty) _run();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.local != widget.local ||
        oldWidget.scopeIdentity != widget.scopeIdentity ||
        (widget.scopeIdentity == null &&
            !identical(oldWidget.repository, widget.repository)) ||
        oldWidget.initialQuery != widget.initialQuery;
    if (!changed) return;
    _ownerEpoch++;
    _generation++;
    _results = null;
    _kind = null;
    _error = null;
    _loading = false;
    _opening = false;
    _query.removeListener(_input);
    _query.text = widget.initialQuery;
    _query.addListener(_input);
    final epoch = _ownerEpoch;
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _ownerEpoch) _run();
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _ownerEpoch++;
    _query.dispose();
    super.dispose();
  }

  void _input() {
    setState(() {});
  }

  Future<void> _run({String? queryOverride, bool keepFilter = false}) async {
    final generation = ++_generation, epoch = _ownerEpoch;
    final repository = widget.repository;
    String query;
    try {
      query = normalizeSearchQuery(queryOverride ?? _query.text);
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (!keepFilter) _kind = null;
    });
    try {
      final result = await repository.search(query);
      if (result.query != query) {
        throw const FormatException('Search query mismatch');
      }
      if (mounted && epoch == _ownerEpoch && generation == _generation) {
        setState(() => _results = result);
      }
    } catch (error) {
      if (mounted && epoch == _ownerEpoch && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && epoch == _ownerEpoch && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _run();
  }

  List<SearchHit> _mixed(SearchResults result) {
    const order = [
      SearchKind.document,
      SearchKind.blog,
      SearchKind.task,
      SearchKind.topic,
      SearchKind.book,
      SearchKind.bookmark,
      SearchKind.label,
    ];
    return [
      for (var index = 0; index < 20; index++)
        for (final kind in order)
          if (index < result.groups[kind]!.length) result.groups[kind]![index],
    ];
  }

  void _clear() {
    _generation++;
    _query.clear();
    setState(() {
      _results = null;
      _kind = null;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _open(SearchHit hit) async {
    if (_opening || _loading) return;
    final results = _results;
    if (results == null ||
        !results.groups[hit.kind]!.any((actual) => identical(actual, hit))) {
      return;
    }
    final generation = _generation, epoch = _ownerEpoch, query = results.query;
    final open = widget.onOpenHit;
    setState(() => _opening = true);
    try {
      await open(hit);
      if (mounted && epoch == _ownerEpoch && generation == _generation) {
        await _run(queryOverride: query, keepFilter: true);
      }
    } catch (error) {
      if (mounted && epoch == _ownerEpoch && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && epoch == _ownerEpoch) setState(() => _opening = false);
    }
  }

  String _kindName(SearchKind kind) => switch (kind) {
    SearchKind.document => t('文档', 'Documents'),
    SearchKind.blog => t('笔记/文章', 'Notes/articles'),
    SearchKind.book => t('书籍', 'Books'),
    SearchKind.bookmark => t('书签', 'Bookmarks'),
    SearchKind.task => t('待办', 'Tasks'),
    SearchKind.topic => t('主题', 'Topics'),
    SearchKind.label => t('标签', 'Labels'),
  };
  String _hitKind(SearchHit hit) => hit.kind == SearchKind.blog
      ? switch (hit.blogType) {
          'note' => t('笔记', 'Note'),
          'article' => t('文章', 'Article'),
          _ => t('未知内容类型', 'Unknown content type'),
        }
      : _kindName(hit.kind);
  IconData _icon(SearchHit hit) => switch (hit.kind) {
    SearchKind.document => Icons.description_outlined,
    SearchKind.blog => Icons.note_outlined,
    SearchKind.book => Icons.menu_book_outlined,
    SearchKind.bookmark => Icons.bookmark_outline,
    SearchKind.task =>
      hit.done ? Icons.check_box_outlined : Icons.check_box_outline_blank,
    SearchKind.topic => Icons.hub_outlined,
    SearchKind.label => Icons.sell_outlined,
  };
  Widget _highlight(String value, {TextStyle? style, int? maxLines}) {
    final query = _results?.query ?? '';
    if (query.isEmpty) {
      return Text(
        value,
        style: style,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }
    final spans = <TextSpan>[];
    var index = 0;
    for (final match in RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(value)) {
      if (match.start > index) {
        spans.add(TextSpan(text: value.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: value.substring(match.start, match.end),
          style: const TextStyle(
            color: Color(0xff2563eb),
            backgroundColor: Color(0xffdbeafe),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      index = match.end;
    }
    if (index < value.length) spans.add(TextSpan(text: value.substring(index)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  Widget _card(SearchHit hit) {
    final title = hit.title.isEmpty ? '${_hitKind(hit)} #${hit.id}' : hit.title;
    final subtitle = switch (hit.kind) {
      SearchKind.document => hit.bookName,
      SearchKind.bookmark => hit.url,
      SearchKind.book => t(
        '${hit.documentCount}篇文档',
        '${hit.documentCount} documents',
      ),
      SearchKind.task => t(
        '${hit.done ? '已完成' : '未完成'}${hit.dueDate.isEmpty ? '' : ' · 截止 ${hit.dueDate}'}',
        '${hit.done ? 'Completed' : 'Open'}${hit.dueDate.isEmpty ? '' : ' · Due ${hit.dueDate}'}',
      ),
      SearchKind.topic => t(
        '${hit.itemCount}条资料关联',
        '${hit.itemCount} resource associations',
      ),
      SearchKind.label =>
        widget.local
            ? t('当前本地空间', 'Current local space')
            : t('全服务器共享标签', 'Shared server label'),
      SearchKind.blog => '',
    };
    final snippet = hit.snippet.isNotEmpty
        ? hit.snippet
        : hit.kind == SearchKind.topic
        ? hit.question
        : hit.description;
    return Card(
      key: ValueKey('search-${hit.kind.name}-${hit.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _loading || _opening ? null : () => _open(hit),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffeff6ff),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_icon(hit), color: const Color(0xff2563eb)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff1f5f9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _hitKind(hit),
                        style: const TextStyle(color: Color(0xff475569)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _highlight(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _highlight(snippet, maxLines: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _results;
    final hits = result == null
        ? <SearchHit>[]
        : _kind == null
        ? _mixed(result)
        : result.groups[_kind] ?? <SearchHit>[];
    return Scaffold(
      appBar: AppBar(title: Text(t('全局搜索', 'Global search'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => result == null || _opening
              ? Future<void>.value()
              : _run(queryOverride: result.query, keepFilter: true),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _query,
                enabled: !_opening,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: t('搜索资料', 'Search resources'),
                  counterText:
                      '${utf8.encode(_query.text.trim()).length} / 100 ${t('字节', 'bytes')}',
                  prefixIcon: IconButton(
                    tooltip: t('搜索', 'Search'),
                    onPressed: _opening ? null : _submit,
                    icon: const Icon(Icons.search),
                  ),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: t('清空', 'Clear'),
                          onPressed: _opening ? null : _clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.local
                    ? t('搜索范围：当前本地空间', 'Scope: current local space')
                    : t(
                        '搜索范围：我的资料 · 标签全局共享',
                        'Scope: my resources · labels are shared across the server',
                      ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (result != null)
                  Text(
                    t(
                      '以下保留上次成功搜索的结果',
                      'Previous successful results are retained below',
                    ),
                  ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_opening) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                Text(t('正在打开资源', 'Opening resource')),
              ],
              if (result == null && !_loading && _error == null) ...[
                const SizedBox(height: 32),
                const Icon(Icons.search, size: 48, color: Color(0xff64748b)),
                const SizedBox(height: 16),
                Text(
                  t(
                    '输入关键词，查找文档、笔记、书籍、书签、待办、主题和标签。',
                    'Enter a query to find documents, notes, books, bookmarks, tasks, topics and labels.',
                  ),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      showCheckmark: false,
                      selectedColor: const Color(0xff2563eb),
                      label: Text(
                        t('全部${result.loaded}', 'All ${result.loaded}'),
                        style: TextStyle(
                          color: _kind == null ? Colors.white : null,
                        ),
                      ),
                      selected: _kind == null,
                      onSelected: _loading || _opening
                          ? null
                          : (_) => setState(() => _kind = null),
                    ),
                    for (final kind in SearchKind.values)
                      ChoiceChip(
                        showCheckmark: false,
                        selectedColor: const Color(0xff2563eb),
                        label: Text(
                          '${_kindName(kind)} ${result.groups[kind]!.length}',
                          style: TextStyle(
                            color: _kind == kind ? Colors.white : null,
                          ),
                        ),
                        selected: _kind == kind,
                        onSelected: _loading || _opening
                            ? null
                            : (_) => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  color: const Color(0xffeff6ff),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      t(
                        '每类最多返回20条，数量仅代表本次返回结果。',
                        'Each type returns up to 20 items. Counts describe this response.',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t(
                    '“${result.query}”的搜索结果 · 已加载${result.loaded}条',
                    'Results for “${result.query}” · ${result.loaded} loaded',
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_query.text.trim() != result.query)
                  Text(
                    t(
                      '以上结果属于已提交的关键词；当前输入尚未搜索。',
                      'Results belong to the submitted query; the current input has not been searched.',
                    ),
                  ),
                const SizedBox(height: 16),
                for (final hit in hits) _card(hit),
                if (hits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      t(
                        '本次返回结果中没有匹配资料',
                        'No matching resources in this response',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
