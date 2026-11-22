import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/bookmark_favicon_store.dart';
import 'package:bookstark_flutter/core/navigation_repository.dart';
import 'package:bookstark_flutter/features/navigation/navigation_page.dart';
import '../tool/fixtures/bookmarks.dart';

class Nav implements NavigationRepository {
  Nav(this.title);
  final String title;
  int loads = 0;
  Completer<NavigationResult>? pending;
  @override
  Future<NavigationResult> load({
    String keyword = '',
    BookmarkScope scope = BookmarkScope.mine,
  }) async {
    loads++;
    if (pending != null) return pending!.future;
    return NavigationResult(
      total: 1,
      ungrouped: [
        BookmarkItem(
          id: 1,
          memberId: 7,
          title: title,
          url: 'https://example.test/',
          favicon: 'https://icons.test/$title.png',
          navVisible: true,
        ),
      ],
    );
  }
}

class IconsStore extends BookmarkFaviconStore {
  final reads = <String>[];
  @override
  Future<Uint8List?> read(String url) async {
    reads.add(url);
    return null;
  }
}

void main() {
  testWidgets(
    'navigation replacement clears old rows and ignores held old result',
    (tester) async {
      final a = Nav('A')..pending = Completer<NavigationResult>(), b = Nav('B');
      final bookmarks = BookmarksFixture();
      Widget page(Nav n) => MaterialApp(
        home: NavigationPage(
          repository: n,
          bookmarks: bookmarks,
          labels: bookmarks,
        ),
      );
      await tester.pumpWidget(page(a));
      await tester.pump();
      await tester.pumpWidget(page(b));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      a.pending!.complete(const NavigationResult(total: 0));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    },
  );
  testWidgets(
    'navigation old hide confirmation cannot target replacement same ID',
    (tester) async {
      final a = Nav('A'),
          b = Nav('B'),
          oldBookmarks = BookmarksFixture(),
          newBookmarks = BookmarksFixture();
      oldBookmarks.items[1] = oldBookmarks.items[1]!.copyWith(navVisible: true);
      newBookmarks.items[1] = newBookmarks.items[1]!.copyWith(navVisible: true);
      var selected = a;
      var books = oldBookmarks;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return NavigationPage(
                repository: selected,
                bookmarks: books,
                labels: books,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('快捷收藏操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从导航隐藏'));
      await tester.pumpAndSettle();
      rebuild(() {
        selected = b;
        books = newBookmarks;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(oldBookmarks.items[1]!.navVisible, isTrue);
      expect(newBookmarks.items[1]!.navVisible, isTrue);
      expect(find.text('B'), findsOneWidget);
    },
  );
  testWidgets(
    'navigation real favicon component reads explicit URL and retires old owner store',
    (tester) async {
      final a = Nav('A'), b = Nav('B'), bookmarks = BookmarksFixture();
      final iconsA = IconsStore(), iconsB = IconsStore();
      BookmarkFaviconStore makeA() => iconsA;
      BookmarkFaviconStore makeB() => iconsB;
      Widget page(Nav n, BookmarkFaviconStore Function() icons) => MaterialApp(
        home: NavigationPage(
          repository: n,
          bookmarks: bookmarks,
          labels: bookmarks,
          faviconStoreFactory: icons,
        ),
      );
      await tester.pumpWidget(page(a, makeA));
      await tester.pumpAndSettle();
      expect(iconsA.reads, ['https://icons.test/A.png']);
      await tester.pumpWidget(page(b, makeB));
      await tester.pumpAndSettle();
      expect(iconsA.retired, isTrue);
      expect(iconsB.reads, ['https://icons.test/B.png']);
      expect(find.byIcon(Icons.link), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(iconsB.retired, isTrue);
    },
  );
}
