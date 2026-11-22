import 'dart:convert';
import 'api_client.dart';
import 'bookmarks_repository.dart';
import 'local_bookmarks_repository.dart';
import 'local_store.dart';

class BookmarkGroup {
  const BookmarkGroup(this.name, this.items);
  final String name;
  final List<BookmarkItem> items;
}

class NavigationResult {
  const NavigationResult({
    this.groups = const [],
    this.pinned = const [],
    this.ungrouped = const [],
    this.labels = const [],
    required this.total,
  });
  final List<BookmarkGroup> groups;
  final List<BookmarkItem> pinned, ungrouped;
  final List<String> labels;

  /// Server-reported loaded row count before group filters, never a whole-library count.
  final int total;
  Iterable<BookmarkItem> get items sync* {
    yield* pinned;
    yield* ungrouped;
    for (final group in groups) {
      yield* group.items;
    }
  }

  factory NavigationResult.fromJson(Map<String, dynamic> json) {
    List<BookmarkItem> rows(Object? value) => List.unmodifiable(
      (value as List? ?? []).map((row) => BookmarkItem.fromJson(row as Map)),
    );
    final result = NavigationResult(
      groups: List.unmodifiable(
        (json['groups'] as List? ?? []).map((value) {
          final row = value as Map;
          return BookmarkGroup(row['name'] as String, rows(row['bookmarks']));
        }),
      ),
      pinned: rows(json['pinned']),
      ungrouped: rows(json['ungrouped']),
      labels: List.unmodifiable(
        (json['all_labels'] as List? ?? []).cast<String>(),
      ),
      total: json['total'] as int? ?? 0,
    );
    final all = result.items.toList();
    if (result.total < 0 ||
        all.length > result.total ||
        all.any(
          (item) => item.id == null || item.id! <= 0 || !item.navVisible,
        ) ||
        all.map((item) => item.id).toSet().length != all.length ||
        result.groups.map((group) => group.name).toSet().length !=
            result.groups.length) {
      throw const FormatException('Invalid grouped bookmarks');
    }
    return result;
  }
}

abstract interface class NavigationRepository {
  Future<NavigationResult> load({
    String keyword = '',
    BookmarkScope scope = BookmarkScope.mine,
  });
}

class RemoteNavigationRepository implements NavigationRepository {
  RemoteNavigationRepository(this.client);
  final BookstarkClient client;
  @override
  Future<NavigationResult> load({
    String keyword = '',
    BookmarkScope scope = BookmarkScope.mine,
  }) async => NavigationResult.fromJson(
    await client.get(
      '/api/bookmarks-grouped?${Uri(queryParameters: {'keyword': keyword, 'scope': scope.name}).query}',
    ),
  );
}

class LocalNavigationRepository implements NavigationRepository {
  LocalNavigationRepository(this.store);
  final LocalStore store;
  @override
  Future<NavigationResult> load({
    String keyword = '',
    BookmarkScope scope = BookmarkScope.mine,
  }) => store.maintenance.use(() async {
    if (scope == BookmarkScope.public) {
      throw UnsupportedError(
        '公开导航需要服务器空间 / Public navigation requires a server',
      );
    }
    final bookmarks = LocalBookmarksRepository(store);
    final rows = <BookmarkItem>[];
    var page = 1;
    while (true) {
      final result = await bookmarks.list(
        BookmarkQuery(keyword: keyword, navVisible: true, page: page),
      );
      rows.addAll(result.items);
      if (!result.hasMore) break;
      page++;
    }
    final pinned = <BookmarkItem>[], ungrouped = <BookmarkItem>[];
    final grouped = <String, List<BookmarkItem>>{};
    for (final item in rows) {
      if (item.isPinned) {
        pinned.add(item);
        continue;
      }
      var name = '';
      for (final label in item.labels) {
        final slash = label.indexOf('/');
        if (slash > 0) {
          name = label.substring(0, slash);
          break;
        }
      }
      if (name.isEmpty) {
        ungrouped.add(item);
      } else {
        grouped.putIfAbsent(name, () => []).add(item);
      }
    }
    final groups =
        grouped.entries
            .map(
              (entry) =>
                  BookmarkGroup(entry.key, List.unmodifiable(entry.value)),
            )
            .toList()
          ..sort((a, b) {
            final count = b.items.length.compareTo(a.items.length);
            return count == 0 ? a.name.compareTo(b.name) : count;
          });
    final labelRows = await (await store.database).query(
      'bookmarks',
      columns: ['labels'],
      where: 'deleted = 0',
    );
    final labels =
        labelRows
            .expand(
              (row) =>
                  (jsonDecode(row['labels'] as String) as List).cast<String>(),
            )
            .toSet()
            .toList()
          ..sort();
    return NavigationResult(
      groups: List.unmodifiable(groups),
      pinned: List.unmodifiable(pinned),
      ungrouped: List.unmodifiable(ungrouped),
      labels: List.unmodifiable(labels),
      total: rows.length,
    );
  });
}
