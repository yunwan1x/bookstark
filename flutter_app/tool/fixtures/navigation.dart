import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/navigation_repository.dart';
import 'bookmarks.dart';

BookmarksFixture navigationBookmarksFixture() {
  final repo = BookmarksFixture();
  repo.items[1] = repo.items[1]!.copyWith(isPinned: true, navVisible: true);
  repo.items[3] = repo.items[3]!.copyWith(isPinned: true, navVisible: true);
  repo.items[2] = repo.items[2]!.copyWith(
    labels: ['开发/Dart'],
    navVisible: true,
  );
  repo.items[4] = const BookmarkItem(
    id: 4,
    memberId: 7,
    title: 'Flutter 示例',
    url: 'https://flutter.dev/examples',
    description: '构建跨平台应用的参考入口',
    labels: ['开发/Flutter'],
    navVisible: true,
  );
  repo.items[5] = const BookmarkItem(
    id: 5,
    memberId: 7,
    title: '个人知识库',
    url: 'https://example.org/library',
    navVisible: true,
  );
  return repo;
}

class NavigationFixture implements NavigationRepository {
  NavigationFixture(this.bookmarks);
  final BookmarksFixture bookmarks;
  @override
  Future<NavigationResult> load({
    String keyword = '',
    BookmarkScope scope = BookmarkScope.mine,
  }) async {
    final all = bookmarks.items.values
        .where(
          (item) =>
              item.navVisible &&
              (scope == BookmarkScope.mine
                  ? item.memberId == 7
                  : item.isPublic) &&
              '${item.title} ${item.url} ${item.description}'.contains(keyword),
        )
        .toList();
    final groups = <String, List<BookmarkItem>>{};
    final pinned = <BookmarkItem>[], ungrouped = <BookmarkItem>[];
    for (final item in all) {
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
        groups.putIfAbsent(name, () => []).add(item);
      }
    }
    return NavigationResult(
      total: all.length,
      pinned: pinned,
      ungrouped: ungrouped,
      groups: groups.entries
          .map((entry) => BookmarkGroup(entry.key, entry.value))
          .toList(),
    );
  }
}
