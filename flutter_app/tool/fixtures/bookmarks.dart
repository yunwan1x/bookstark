import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';

class BookmarksFixture implements BookmarksRepository, LabelsRepository {
  final items = <int, BookmarkItem>{
    1: const BookmarkItem(
      id: 1,
      memberId: 7,
      title: 'Flutter 开发文档',
      url: 'https://flutter.dev',
      description: '构建跨平台应用的参考入口',
      labels: ['Flutter'],
    ),
    2: const BookmarkItem(
      id: 2,
      memberId: 7,
      title: 'Dart 语言指南',
      url: 'https://dart.dev',
      description: '语言与工具链的学习资料',
      labels: ['编程'],
    ),
    3: const BookmarkItem(
      id: 3,
      memberId: 7,
      title: '阅读清单',
      url: 'https://example.org',
      description: '值得再次阅读的文章',
      labels: ['阅读'],
      isPublic: true,
    ),
  };
  int saves = 0;
  Future<BookmarkMetadata> Function(String)? onMetadata;
  @override
  int get memberId => 7;
  @override
  bool get isAdmin => false;
  @override
  bool canEdit(BookmarkItem item) => item.memberId == memberId;
  @override
  Future<BookmarkPageResult> list(BookmarkQuery query) async {
    final rows = items.values
        .where(
          (item) =>
              (query.scope == BookmarkScope.mine
                  ? item.memberId == memberId
                  : item.isPublic) &&
              '${item.title} ${item.url} ${item.description}'.contains(
                query.keyword,
              ) &&
              query.labels.every(item.labels.contains) &&
              (query.isPublic == null || item.isPublic == query.isPublic) &&
              (query.isPinned == null || item.isPinned == query.isPinned),
        )
        .toList();
    return BookmarkPageResult(
      rows.skip((query.page - 1) * 20).take(20).toList(),
      rows.length,
      query.page,
      20,
    );
  }

  @override
  Future<BookmarkItem> read(int id) async {
    final item = items[id];
    if (item == null) throw StateError('Bookmark no longer exists');
    return item;
  }

  @override
  Future<BookmarkItem?> findByUrl(String url) async {
    for (final item in items.values) {
      if (item.url == url) return item;
    }
    return null;
  }

  @override
  Future<int> save(BookmarkItem bookmark, {BookmarkItem? original}) async {
    bookmark.validate();
    final duplicate = await findByUrl(bookmark.url);
    if (duplicate != null && duplicate.id != bookmark.id) {
      throw BookmarkAlreadyExists(duplicate);
    }
    saves++;
    final id =
        bookmark.id ??
        (items.keys.fold<int>(0, (highest, id) => id > highest ? id : highest) +
            1);
    items[id] = bookmark.copyWith(id: id, memberId: memberId);
    return id;
  }

  @override
  Future<BookmarkMetadata> metadata(String url) async => onMetadata == null
      ? const BookmarkMetadata(title: '网页标题', description: '网页说明')
      : await onMetadata!(url);
  @override
  Future<void> remove(int id) async {
    items.remove(id);
  }

  @override
  Future<void> setPublic(int id, bool value) async {
    items[id] = items[id]!.copyWith(isPublic: value);
  }

  @override
  Future<void> setNavVisible(int id, bool value) async {
    items[id] = items[id]!.copyWith(navVisible: value);
  }

  @override
  Future<void> batch(
    BookmarkBatch action,
    List<int> ids, {
    List<String> labels = const [],
  }) async {
    for (final id in ids) {
      final item = items[id]!;
      switch (action) {
        case BookmarkBatch.delete:
          items.remove(id);
        case BookmarkBatch.share:
          items[id] = item.copyWith(isPublic: true);
        case BookmarkBatch.unshare:
          items[id] = item.copyWith(isPublic: false);
        case BookmarkBatch.pin:
          items[id] = item.copyWith(isPinned: true);
        case BookmarkBatch.unpin:
          items[id] = item.copyWith(isPinned: false);
        case BookmarkBatch.showNav:
          items[id] = item.copyWith(navVisible: true);
        case BookmarkBatch.hideNav:
          items[id] = item.copyWith(navVisible: false);
        case BookmarkBatch.addLabels:
          items[id] = item.copyWith(
            labels: {...item.labels, ...labels}.toList(),
          );
        case BookmarkBatch.removeLabels:
          items[id] = item.copyWith(
            labels: item.labels
                .where((name) => !labels.contains(name))
                .toList(),
          );
      }
    }
  }

  @override
  Future<void> sort(Map<int, int> order) async {
    for (final entry in order.entries) {
      items[entry.key] = items[entry.key]!.copyWith(order: entry.value);
    }
  }

  @override
  Future<void> refreshFavicon(int id) async {}
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => page == 1
      ? items.values
            .expand((item) => item.labels)
            .toSet()
            .where((name) => name.contains(keyword))
            .toList()
      : [];
}
