// Draft only; no Flutter run.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/bookmark_favicon_store.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/widgets/bookmark_favicon.dart';

class _PendingStore extends BookmarkFaviconStore {
  final answers = <String, Completer<Uint8List?>>{};
  @override
  Future<Uint8List?> read(String url) =>
      answers.putIfAbsent(url, Completer<Uint8List?>.new).future;
}

class _ListRepository implements BookmarksRepository {
  _ListRepository(this.answer);
  final Future<BookmarkPageResult> answer;
  @override
  int get memberId => 7;
  @override
  bool get isAdmin => false;
  @override
  bool canEdit(BookmarkItem item) => false;
  @override
  Future<BookmarkPageResult> list(BookmarkQuery query) => answer;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedLabels implements LabelsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'scope switch clears old rows before pending new list and never fetches old icons in new store',
    (tester) async {
      final oldStore = _PendingStore(),
          newStore = _PendingStore(),
          labels = _UnusedLabels();
      final oldRepo = _ListRepository(
        Future.value(
          const BookmarkPageResult(
            [
              BookmarkItem(
                id: 1,
                title: 'OLD PRIVATE ROW',
                url: 'https://old.invalid/page',
                favicon: 'https://old.invalid/icon',
              ),
            ],
            1,
            1,
            20,
          ),
        ),
      );
      final pending = Completer<BookmarkPageResult>(),
          newRepo = _ListRepository(pending.future);
      BookmarkFaviconStore makeOld() => oldStore;
      BookmarkFaviconStore makeNew() => newStore;
      Widget page(
        BookmarksRepository repo,
        int scope,
        BookmarkFaviconStore Function() factory,
      ) => MaterialApp(
        home: BookmarksPage(
          repository: repo,
          labelsRepository: labels,
          faviconScopeKey: scope,
          faviconStoreFactory: factory,
        ),
      );
      await tester.pumpWidget(page(oldRepo, 1, makeOld));
      await tester.pump();
      expect(find.text('OLD PRIVATE ROW'), findsOneWidget);
      await tester.pumpWidget(page(newRepo, 2, makeNew));
      await tester.pump();
      expect(find.text('OLD PRIVATE ROW'), findsNothing);
      expect(newStore.answers, isEmpty);
      expect(oldStore.retired, true);
      pending.complete(const BookmarkPageResult([], 0, 1, 20));
      await tester.pumpAndSettle();
      expect(newStore.answers, isEmpty);
      oldStore.answers.values.single.complete(null);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial stale scope issues zero read requests', (tester) async {
    final store = _PendingStore();
    await tester.pumpWidget(
      MaterialApp(
        home: BookmarkFavicon(
          explicitUrl: 'https://old.invalid/icon',
          store: store,
          scopeKey: 1,
          isCurrent: () => false,
        ),
      ),
    );
    await tester.pump();
    expect(store.answers, isEmpty);
    expect(find.byIcon(Icons.link), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.retire();
  });

  testWidgets(
    'row URL/scope reuse never paints old decode; failure keeps link',
    (tester) async {
      final store = _PendingStore();
      var current = true;
      Widget row(String url, Object scope) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 48,
            height: 48,
            child: BookmarkFavicon(
              explicitUrl: url,
              store: store,
              scopeKey: scope,
              isCurrent: () => current,
            ),
          ),
        ),
      );
      await tester.pumpWidget(row('https://old.invalid/icon', 1));
      await tester.pumpWidget(row('https://new.invalid/icon', 2));
      store.answers['https://old.invalid/icon']!.complete(
        Uint8List.fromList([1, 2, 3]),
      );
      await tester.pump();
      expect(find.byIcon(Icons.link), findsOneWidget);
      store.answers['https://new.invalid/icon']!.complete(
        Uint8List.fromList([1, 2, 3]),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.link), findsOneWidget);
      current = false;
      await tester.pumpWidget(row('https://new.invalid/icon', 3));
      store.retire();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dispose with pending image never sets state afterward', (
    tester,
  ) async {
    final store = _PendingStore();
    await tester.pumpWidget(
      MaterialApp(
        home: BookmarkFavicon(
          explicitUrl: 'https://a.invalid/icon',
          store: store,
          scopeKey: 1,
          isCurrent: () => true,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    store.answers.values.single.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    store.retire();
  });
}
