import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import '../tool/fixtures/bookmarks.dart';

class Pages extends BookmarksFixture {
  bool changed = false, invalidSize = false;
  final queries = <BookmarkQuery>[];
  @override
  Future<BookmarkPageResult> list(BookmarkQuery query) async {
    queries.add(query);
    return BookmarkPageResult(
      [items[query.page]!],
      changed && query.page == 2 ? 3 : 2,
      query.page,
      invalidSize ? 0 : 1,
    );
  }
}

Future<void> reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  expect(find.text(text).hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'changed next page blocks batch without replacing verified loaded rows',
    (tester) async {
      final repo = Pages()..changed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: BookmarksPage(repository: repo, labelsRepository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flutter 开发文档'), findsOneWidget);
      await reveal(tester, '加载更多');
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('Flutter 开发文档'), findsOneWidget);
      expect(find.text('Dart 语言指南'), findsNothing);
      expect(find.text('刷新核对'), findsOneWidget);
      expect(find.text('2条书签'), findsOneWidget);
      repo.changed = false;
      await reveal(tester, '刷新核对');
      await tester.tap(find.text('刷新核对'));
      await tester.pumpAndSettle();
      await reveal(tester, '加载更多');
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('Dart 语言指南'), findsOneWidget);
      expect(find.text('刷新核对'), findsNothing);
    },
  );
  testWidgets('zero page size is error not empty successful collection', (
    tester,
  ) async {
    final repo = Pages()..invalidSize = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BookmarksPage(repository: repo, labelsRepository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('刷新核对'), findsOneWidget);
    expect(find.text('暂无书签'), findsNothing);
    expect(find.text('Flutter 开发文档'), findsNothing);
  });
  testWidgets(
    'EN320 200 percent advanced filter applies real site date and keeps query on search',
    (tester) async {
      final repo = Pages();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: BookmarksPage(
              repository: repo,
              labelsRepository: repo,
              english: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await reveal(tester, 'Filters');
        await tester.tap(find.text('Filters'));
        await tester.pumpAndSettle();
        final field1 = find.widgetWithText(
          TextField,
          'Site host (optional port)',
        );
        await tester.ensureVisible(field1);
        await tester.pumpAndSettle();
        await tester.enterText(field1, 'example.test:8443');
        final field2 = find.widgetWithText(TextField, 'Start date/time');
        await tester.ensureVisible(field2);
        await tester.pumpAndSettle();
        await tester.enterText(field2, '2026-11-01T00:00:00');
        final field3 = find.widgetWithText(TextField, 'End date/time');
        await tester.ensureVisible(field3);
        await tester.pumpAndSettle();
        await tester.enterText(field3, '2026-11-11T23:59:59');
        await tester.ensureVisible(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.text('Apply').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        final query = repo.queries.last;
        expect(query.site, 'example.test:8443');
        expect(query.start, DateTime(2026, 11, 1));
        expect(query.end, DateTime(2026, 11, 11, 23, 59, 59));
        final listScroll = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.drag(listScroll, const Offset(0, 1800));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'keyword');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(repo.queries.last.keyword, 'keyword');
        expect(repo.queries.last.site, query.site);
        expect(repo.queries.last.start, query.start);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
