import 'local_protected_content.dart';
import 'dart:convert';
import 'api_client.dart';
import 'notes_repository.dart';

enum SearchKind { document, blog, book, bookmark, task, topic, label }

const searchGroupKeys = {
  SearchKind.document: 'documents',
  SearchKind.blog: 'blogs',
  SearchKind.book: 'books',
  SearchKind.bookmark: 'bookmarks',
  SearchKind.task: 'tasks',
  SearchKind.topic: 'topics',
  SearchKind.label: 'labels',
};
String normalizeSearchQuery(String value) {
  final result = value.trim();
  if (result.isEmpty || utf8.encode(result).length > 100) {
    throw const FormatException(
      '搜索词必填，最多100字节（UTF-8） / Enter a search query of at most 100 UTF-8 bytes',
    );
  }
  return result;
}

int _number(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0)) {
    throw const FormatException('Invalid search number');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String) throw const FormatException('Invalid search text');
  return value;
}

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.snippet = '',
    this.identify = '',
    this.bookName = '',
    this.bookIdentify = '',
    this.url = '',
    this.description = '',
    this.blogType = '',
    this.question = '',
    this.dueDate = '',
    this.done = false,
    this.parentId = 0,
    this.documentCount = 0,
    this.itemCount = 0,
  });
  final SearchKind kind;
  final int id, parentId, documentCount, itemCount;
  final String title,
      snippet,
      identify,
      bookName,
      bookIdentify,
      url,
      description,
      blogType,
      question,
      dueDate;
  final bool done;
  NoteCollection? get collection => switch (blogType) {
    'note' => NoteCollection.note,
    'article' => NoteCollection.article,
    _ => null,
  };
  (SearchKind, int) get key => (kind, id);
  factory SearchHit.fromJson(SearchKind kind, Map row) {
    final id = _number(row['id'], positive: true);
    final title = _text(
      row[switch (kind) {
        SearchKind.document || SearchKind.book || SearchKind.label => 'name',
        SearchKind.task => 'content',
        _ => 'title',
      }],
    );
    String text(String key) => _text(row[key] ?? '');
    var snippet = text('snippet');
    if ((kind == SearchKind.blog || kind == SearchKind.document) &&
        isLocalProtectedEnvelopePrefix(snippet)) {
      snippet = '';
    }
    final done = row['done'];
    if (kind == SearchKind.task && done is! bool) {
      throw const FormatException('Invalid search task status');
    }
    return SearchHit(
      kind: kind,
      id: id,
      title: title,
      snippet: snippet,
      identify: text('identify'),
      bookName: text('book_name'),
      bookIdentify: text('book_identify'),
      url: text('url'),
      description: text('description'),
      blogType: text('blog_type'),
      question: text('question'),
      dueDate: text('due_date'),
      done: done == true,
      parentId: _number(row['parent_id'] ?? 0),
      documentCount: _number(row['doc_count'] ?? 0),
      itemCount: _number(row['item_count'] ?? 0),
    );
  }
}

class SearchResults {
  SearchResults({
    required this.query,
    required Map<SearchKind, List<SearchHit>> groups,
  }) : groups = Map.unmodifiable({
         for (final kind in SearchKind.values)
           kind: List<SearchHit>.unmodifiable(groups[kind] ?? const []),
       }) {
    for (final entry in this.groups.entries) {
      if (entry.value.length > 20 ||
          entry.value.any((item) => item.kind != entry.key || item.id <= 0) ||
          entry.value.map((item) => item.id).toSet().length !=
              entry.value.length) {
        throw const FormatException('Invalid search group');
      }
    }
  }
  final String query;
  final Map<SearchKind, List<SearchHit>> groups;
  int get loaded => groups.values.fold(0, (count, rows) => count + rows.length);
  List<SearchHit> get all => [for (final rows in groups.values) ...rows];
  factory SearchResults.fromJson(String query, Map data) {
    final counts = data['counts'];
    if (counts is! Map) throw const FormatException('Invalid search counts');
    final groups = <SearchKind, List<SearchHit>>{};
    for (final entry in searchGroupKeys.entries) {
      final rows = data[entry.value];
      if (rows != null && rows is! List) {
        throw const FormatException('Invalid search results');
      }
      final hits = (rows as List? ?? const [])
          .map((row) => SearchHit.fromJson(entry.key, row as Map))
          .toList();
      if (_number(counts[entry.value]) != hits.length) {
        throw const FormatException(
          'Search counts do not match loaded results',
        );
      }
      groups[entry.key] = hits;
    }
    return SearchResults(query: query, groups: groups);
  }
}

abstract interface class SearchRepository {
  Future<SearchResults> search(String query);
}

class RemoteSearchRepository implements SearchRepository {
  RemoteSearchRepository(this.client, {this.isCurrent})
    : _revision = client.sessionRevision;
  final BookstarkClient client;
  final bool Function()? isCurrent;
  final int _revision;
  void _guard() {
    if (client.sessionRevision != _revision || !(isCurrent?.call() ?? true)) {
      throw StateError('Search owner retired');
    }
  }

  @override
  Future<SearchResults> search(String query) async {
    _guard();
    final normalized = normalizeSearchQuery(query);
    final result=await client.readSearchJson(normalized,
      expectedSessionRevision:_revision,ownerGuard:_guard);
    _guard();
    return SearchResults.fromJson(normalized, result);
  }
}
