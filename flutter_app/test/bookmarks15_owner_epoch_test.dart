import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import '../tool/fixtures/bookmarks.dart';

class OwnerFixture extends BookmarksFixture {
  int removals = 0, lists = 0;
  Completer<void>? heldRemove;
  @override
  Future<BookmarkPageResult> list(BookmarkQuery query) {
    lists++;
    return super.list(query);
  }

  @override
  Future<void> remove(int id) async {
    removals++;
    await heldRemove?.future;
    await super.remove(id);
  }
}

void main() {
  testWidgets(
    'old bookmark delete confirmation cannot mutate replacement owner same ID',
    (tester) async {
      final a = OwnerFixture(), b = OwnerFixture();
      var selected = a;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return BookmarksPage(
                repository: selected,
                labelsRepository: selected,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('书签操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除书签'), findsOneWidget);
      rebuild(() => selected = b);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(a.removals, 0);
      expect(b.removals, 0);
      expect(a.items.containsKey(1), isTrue);
      expect(b.items.containsKey(1), isTrue);
    },
  );
  testWidgets(
    'old bookmark popup selection cannot open replacement owner delete',
    (tester) async {
      final a = OwnerFixture(), b = OwnerFixture();
      var selected = a;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return BookmarksPage(
                repository: selected,
                labelsRepository: selected,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('书签操作').first);
      await tester.pumpAndSettle();
      rebuild(() => selected = b);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除书签'), findsNothing);
      expect(a.removals, 0);
      expect(b.removals, 0);
    },
  );
  testWidgets(
    'old bookmark mutation response cannot refresh or lock replacement owner',
    (tester) async {
      final a = OwnerFixture()..heldRemove = Completer<void>(),
          b = OwnerFixture();
      var selected = a;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return BookmarksPage(
                repository: selected,
                labelsRepository: selected,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('书签操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pump();
      expect(a.removals, 1);
      rebuild(() => selected = b);
      await tester.pumpAndSettle();
      final before = b.lists;
      a.heldRemove!.completeError(StateError('old owner failed'));
      await tester.pumpAndSettle();
      expect(b.lists, before);
      expect(find.textContaining('old owner failed'), findsNothing);
      expect(find.byTooltip('书签操作').first.hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('书签操作').first);
      await tester.pumpAndSettle();
      expect(find.text('编辑'), findsOneWidget);
    },
  );
  test(
    'all remote bookmark writes recheck owner after held CSRF and send no mutation',
    () async {
      final operations = <Future<void> Function(RemoteBookmarksRepository)>[
        (r) => r.remove(1),
        (r) => r.setPublic(1, true),
        (r) => r.setNavVisible(1, true),
        (r) => r.batch(BookmarkBatch.delete, [1]),
        (r) => r.sort({1: 2}),
        (r) => r.refreshFavicon(1),
        (r) async {
          await r.metadata('https://example.test/');
        },
        (r) async {
          await r.save(
            const BookmarkItem(
              id: 1,
              memberId: 7,
              title: 'exact',
              url: 'https://example.test/',
            ),
          );
        },
      ];
      for (final operation in operations) {
        final reached = Completer<void>(), csrf = Completer<http.Response>();
        var current = true, writes = 0;
        final client = BookstarkClient(
          'https://owner.test',
          transport: MockClient((request) async {
            if (request.url.path == '/api/csrf-token') {
              reached.complete();
              return csrf.future;
            }
            if (request.method != 'GET') writes++;
            return http.Response(
              jsonEncode({'code': 0, 'data': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final repo = RemoteBookmarksRepository(
          client,
          memberId: 7,
          isCurrent: () => current,
        );
        try {
          final result = operation(repo);
          final rejected = expectLater(result, throwsA(isA<StateError>()));
          await reached.future;
          current = false;
          csrf.complete(
            http.Response(
              jsonEncode({'code': 0}),
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=${'a' * 64}; Path=/',
              },
            ),
          );
          await rejected;
          expect(writes, 0);
        } finally {
          client.close();
        }
      }
    },
  );
}
