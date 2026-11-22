import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/features/search/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/search.dart';

void main() {
  testWidgets(
    'category filtering keeps type-keyed source identity and loaded limits',
    (tester) async {
      final repo = SearchFixture();
      SearchHit? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: SearchPage(
            repository: repo,
            initialQuery: '阅读',
            onOpenHit: (hit) async {
              opened = hit;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('全部17'), findsOneWidget);
      expect(find.textContaining('每类最多返回20条'), findsOneWidget);
      await tester.tap(find.text('书签 2'));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('search-bookmark-1'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(opened!.kind, SearchKind.bookmark);
      expect(opened!.id, 1);
      expect(repo.calls, ['阅读', '阅读']);
      expect(find.textContaining('已加载17条'), findsOneWidget);
    },
  );
  testWidgets('late search response never replaces newer query', (
    tester,
  ) async {
    final repo = SearchFixture(sample: false);
    final old = Completer<SearchResults>();
    repo.searchOverride = (q) async => q == '旧'
        ? old.future
        : SearchResults(
            query: q,
            groups: {
              SearchKind.book: [
                const SearchHit(kind: SearchKind.book, id: 2, title: '新结果'),
              ],
            },
          );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: SearchPage(repository: repo, onOpenHit: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    old.complete(
      SearchResults(
        query: '旧',
        groups: {
          SearchKind.book: [
            const SearchHit(kind: SearchKind.book, id: 1, title: '旧结果'),
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('“新”的搜索结果'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-book-1')), findsNothing);
  });
  testWidgets('invalid query and clear invalidate an in-flight request', (
    tester,
  ) async {
    final repo = SearchFixture(sample: false);
    final pending = Completer<SearchResults>();
    repo.searchOverride = (_) => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: SearchPage(repository: repo, onOpenHit: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), List.filled(34, '书').join());
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    pending.complete(
      SearchResults(
        query: '旧',
        groups: {
          SearchKind.book: [
            const SearchHit(kind: SearchKind.book, id: 1, title: '旧结果'),
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('100字节'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-book-1')), findsNothing);
    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(repo.calls, ['旧']);
  });
  testWidgets(
    'search snippets remain literal text and never create image widgets',
    (tester) async {
      final repo = SearchFixture(sample: false);
      repo.groups[SearchKind.document] = [
        const SearchHit(
          kind: SearchKind.document,
          id: 1,
          title: 'HTML示例',
          snippet: '<img src="https://example.invalid/private">',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: SearchPage(
            repository: repo,
            initialQuery: 'img',
            onOpenHit: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('search-document-1'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(find.textContaining('<img', findRichText: true), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'English small search supports 200 percent text and scrolling results',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = SearchFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SearchPage(
            repository: repo,
            initialQuery: '阅读',
            english: true,
            onOpenHit: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('search-document-1'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
