import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/features/search/search_page.dart';

SearchResults result(String query, String title, int id) => SearchResults(
  query: query,
  groups: {
    SearchKind.blog: [
      SearchHit(kind: SearchKind.blog, id: id, title: title, blogType: 'note'),
    ],
  },
);

class _Repository implements SearchRepository {
  _Repository(this.read);
  final Future<SearchResults> Function(String) read;
  @override
  Future<SearchResults> search(String query) => read(query);
}

Map<String, Object?> emptyWire() => {
  'counts': {for (final name in searchGroupKeys.values) name: 0},
  for (final name in searchGroupKeys.values) name: [],
};
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  test(
    'held old-account search response is rejected after same client session replacement',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      var calls = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/search');
          entered.complete();
          return reply.future;
        }),
      );
      client.restoreSession({'token': 'synthetic-A'});
      final repo = RemoteSearchRepository(client);
      try {
        var published=false;
        final pending = repo.search('Exact').then((result){published=true;return result;});
        final rejected = expectLater(pending,
          throwsA(isA<ApiFailure>().having((error)=>error.status,'retired status',499)));
        await entered.future;
        client.restoreSession({'token': 'synthetic-B'});
        reply.complete(
          http.Response(
            jsonEncode({'code': 0, 'data': emptyWire()}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await rejected;
        expect(published,isFalse);
        expect(calls, 1);
      } finally {
        client.close();
      }
    },
  );
  test('retired remote owner cannot start even a read request', () async {
    var calls = 0;
    final client = BookstarkClient(
      'https://fixture.invalid',
      transport: MockClient((_) async {
        calls++;
        throw StateError('No request');
      }),
    );
    try {
      await expectLater(
        RemoteSearchRepository(client, isCurrent: () => false).search('Exact'),
        throwsStateError,
      );
      expect(calls, 0);
    } finally {
      client.close();
    }
  });
  test(
    'retired local search cannot register source labels as a side effect',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote('Exact', 'Body', labels: ['not-registered']);
        final db = await store.database;
        expect(await db.query('local_labels'), isEmpty);
        await expectLater(
          LocalSearchRepository(store, isCurrent: () => false).search('Exact'),
          throwsStateError,
        );
        expect(await db.query('local_labels'), isEmpty);
      } finally {
        await store.close();
      }
    },
  );
  testWidgets('held A search cannot repopulate replaced B query or rows', (
    tester,
  ) async {
    final held = Completer<SearchResults>();
    var bReads = 0;
    final a = _Repository((_) => held.future);
    final b = _Repository((q) async {
      bReads++;
      return result(q, 'Beta result', 2);
    });
    Widget page(SearchRepository repository, String query) => MaterialApp(
      home: SearchPage(
        repository: repository,
        initialQuery: query,
        onOpenHit: (_) async {},
        english: true,
      ),
    );
    try {
      await tester.pumpWidget(page(a, 'Alpha'));
      await tester.pump();
      await tester.pumpWidget(page(b, 'Beta'));
      await tester.pumpAndSettle();
      expect(find.text('Beta result'), findsOneWidget);
      held.complete(result('Alpha', 'Alpha result', 1));
      await tester.pumpAndSettle();
      expect(find.text('Alpha result'), findsNothing);
      expect(find.text('Beta result'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Beta',
      );
      expect(bReads, 1);
    } finally {
      if (!held.isCompleted) held.complete(result('Alpha', 'Alpha result', 1));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets(
    'old opening error cannot clear B opening state or refresh wrong owner',
    (tester) async {
      final releaseA = Completer<void>(), releaseB = Completer<void>();
      var aReads = 0, bReads = 0, aOpens = 0, bOpens = 0;
      final a = _Repository((q) async {
        aReads++;
        return result(q, 'Alpha result', 1);
      });
      final b = _Repository((q) async {
        bReads++;
        return result(q, 'Beta result', 2);
      });
      Widget page(bool ownerA) => MaterialApp(
        home: SearchPage(
          repository: ownerA ? a : b,
          initialQuery: ownerA ? 'Alpha' : 'Beta',
          english: true,
          onOpenHit: (_) async {
            if (ownerA) {
              aOpens++;
              await releaseA.future;
              throw StateError('retired-A-error');
            }
            bOpens++;
            await releaseB.future;
          },
        ),
      );
      try {
        await tester.pumpWidget(page(true));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-blog-1')));
        await tester.pump();
        expect(aOpens, 1);
        await tester.pumpWidget(page(false));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-blog-2')));
        await tester.pump();
        expect(bOpens, 1);
        expect(find.text('Opening resource'), findsOneWidget);
        releaseA.complete();
        await tester.pump();
        await tester.pump();
        expect(find.text('Opening resource'), findsOneWidget);
        expect(find.textContaining('retired-A-error'), findsNothing);
        expect(aReads, 1);
        expect(bReads, 1);
        releaseB.complete();
        await tester.pumpAndSettle();
        expect(bReads, 2);
        expect(find.text('Beta result'), findsOneWidget);
      } finally {
        if (!releaseA.isCompleted) releaseA.complete();
        if (!releaseB.isCompleted) releaseB.complete();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
