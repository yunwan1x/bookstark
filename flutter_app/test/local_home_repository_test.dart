import 'package:bookstark_flutter/core/local_home_tracking_repositories.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:bookstark_flutter/core/home_dashboard_repository.dart';
import 'package:bookstark_flutter/core/local_home_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

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
  late Directory directory;
  late LocalStore store;
  late LocalHomePreferences prefs;
  late LocalHomeDashboardRepository repo;
  late Map<String, String> values;
  late int note, article;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookstark-local-home-');
    store = LocalStore(
      path: '${directory.path}/home.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    values = {};
    prefs = LocalHomePreferences(
      namespace: store.path,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      now: () => DateTime.utc(2026, 11, 10, 10),
    );
    repo = LocalHomeDashboardRepository(store, prefs);
    note = await store.createNote('Actual note', '\ufeffliteral body');
    article = await store.createNote(
      'Actual article',
      'original',
      collection: 'article',
    );
    final db = await store.database;
    await db.update('notes', {
      'updated_at': DateTime(2026, 11, 10, 12).millisecondsSinceEpoch,
    });
    await db.insert('books', {
      'book_name': 'Actual book',
      'identify': 'home-book',
      'create_time': '2024-02-29T10:00:00',
      'modify_time': '2026-11-10T10:00:00',
    });
    await db.insert('bookmarks', {
      'title': 'Actual bookmark',
      'url': 'https://example.invalid',
      'nav_visible': 1,
      'create_time': DateTime(2024, 2, 29, 11).millisecondsSinceEpoch,
      'modify_time': DateTime(2026, 11, 10, 11).millisecondsSinceEpoch,
    });
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<String> databaseState() async {
    final db = await store.database;
    final names = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    return jsonEncode({
      for (final row in names)
        row['name'] as String: await db.query(row['name'] as String),
    });
  }

  test(
    'real summaries do not invent visits or mutate any existing table',
    () async {
      final before = await databaseState();
      final result = await repo.load(HomeQuery(month: DateTime(2026, 11)));
      expect(result.recent, isEmpty);
      expect(result.sections.length, 7);
      expect(result.layout.length, 9);
      expect(
        result.sections.firstWhere((s) => s.key == 'notes').items.single.title,
        'Actual note',
      );
      expect(
        result.activity['2026-11-10'],
        4,
      ); // note, article, book, bookmark; nav is not double counted.
      expect(await databaseState(), before);
      expect(values, isEmpty);
    },
  );
  test(
    'created cutoff uses actual fields and marks missing note creation dates unknown',
    () async {
      final result = await repo.load(
        HomeQuery(
          month: DateTime(2024, 2),
          order: 'created',
          end: '2024-02-29',
        ),
      );
      expect(result.sections.firstWhere((s) => s.key == 'notes').total, 0);
      expect(result.unknownDates['notes'], 1);
      expect(result.unknownDates['articles'], 1);
      expect(result.sections.firstWhere((s) => s.key == 'books').total, 1);
      expect(result.sections.firstWhere((s) => s.key == 'bookmarks').total, 1);
      expect(result.activity['2024-02-29'], 2);
    },
  );
  test(
    'visits resolve current titles, exclude deleted content and clear only owned history',
    () async {
      await repo.recordVisit('note', note);
      expect(values.values.single.contains('Actual note'), false);
      expect(values.values.single.contains('literal body'), false);
      final db = await store.database;
      await db.update(
        'notes',
        {'title': 'Renamed'},
        where: 'id=?',
        whereArgs: [note],
      );
      var result = await repo.load(HomeQuery());
      expect(result.recent.single.title, 'Renamed');
      expect(result.recent.single.visitedAt, DateTime.utc(2026, 11, 10, 10));
      await db.update(
        'notes',
        {'deleted': 1},
        where: 'id=?',
        whereArgs: [note],
      );
      result = await repo.load(HomeQuery());
      expect(result.recent, isEmpty);
      await repo.saveLayout([
        const HomeLayoutItem(key: 'assets', width: 3, hidden: true),
      ]);
      final before = await databaseState();
      await repo.clearVisits();
      expect((await prefs.read()).$1.first.toJson(), {
        'key': 'assets',
        'width': 3,
        'hidden': true,
      });
      expect((await prefs.read()).$2, isEmpty);
      expect(await databaseState(), before);
    },
  );
  test(
    'serialized preference updates retain layout and visits, scoped to actual database',
    () async {
      await Future.wait([
        repo.saveLayout([const HomeLayoutItem(key: 'books', width: 2)]),
        repo.recordVisit('article', article),
      ]);
      final state = await prefs.read();
      expect(state.$1.first.key, 'books');
      expect(state.$2.single.id, article);
      final other = LocalHomePreferences(
        namespace: '${store.path}-other',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
      );
      await other.clearVisits();
      expect((await prefs.read()).$2.length, 1);
      expect((await other.read()).$2, isEmpty);
    },
  );
  test(
    'history is bounded, deduplicated and does not accept arbitrary resource kinds',
    () async {
      for (var id = 1; id <= 25; id++) {
        await prefs.record('note', id);
      }
      await prefs.record('article', 25);
      final visits = (await prefs.read()).$2;
      expect(visits.length, 20);
      expect(visits.first.kind, 'article');
      expect(visits.where((v) => v.id == 25).length, 1);
      await expectLater(
        repo.recordVisit('untrusted', note),
        throwsFormatException,
      );
    },
  );
  test(
    'corrupt preferences are not silently replaced with fabricated defaults',
    () async {
      values[prefs.key] = '{"format":2,"visits":[]}';
      final before = Map.of(values);
      await expectLater(repo.load(HomeQuery()), throwsFormatException);
      await expectLater(
        repo.clearVisits(),
        throwsA(isA<HomeWriteUnconfirmed>()),
      );
      expect(values, before);
    },
  );
  test(
    'a retired clear cannot rewrite preferences after it was cancelled',
    () async {
      await repo.recordVisit('note', note);
      final before = Map.of(values);
      final abort = Completer<void>()..complete();
      await expectLater(
        repo.clearVisits(abortTrigger: abort.future),
        throwsA(isA<HomeWriteUnconfirmed>()),
      );
      expect(values, before);
    },
  );
  test(
    'tracking keeps local WebView repository dispatch and does not record failed identities',
    () async {
      final events = <String>[];
      final tracked = HomeLocalNotesRepository(
        store,
        onOpened: (kind, id) async {
          events.add('$kind/$id');
          await repo.recordVisit(kind, id);
        },
      );
      expect(tracked, isA<LocalNotesRepository>());
      await tracked.read(note);
      expect(events, ['note/$note']);
      await expectLater(tracked.read(99999), throwsStateError);
      expect(events.length, 1);
      final db = await store.database;
      await db.update(
        'notes',
        {'editor_type': 'drawing'},
        where: 'id=?',
        whereArgs: [note],
      );
      await expectLater(
        tracked.read(note),
        throwsA(
          isA<DedicatedEditorRequired>().having(
            (e) => e.editorType,
            'engine',
            'drawing',
          ),
        ),
      );
      expect((await prefs.read()).$2.single.id, note);
      final unavailable = HomeLocalNotesRepository(
        store,
        onOpened: (kind, id) async {
          throw StateError('preferences unavailable');
        },
      );
      await db.update(
        'notes',
        {'editor_type': 'markdown'},
        where: 'id=?',
        whereArgs: [note],
      );
      expect((await unavailable.read(note)).title, 'Actual note');
    },
  );
  test(
    'explicit preferences reset recovers corrupt metadata without changing content',
    () async {
      final before = await databaseState();
      values[prefs.key] = '{broken';
      values['unrelated-private-key'] = 'keep';
      await expectLater(prefs.read(), throwsA(isA<HomePreferencesCorrupt>()));
      expect(values[prefs.key], '{broken');
      await prefs.reset();
      final loaded = await repo.load(HomeQuery());
      expect(loaded.recent, isEmpty);
      expect(loaded.layout.length, 9);
      expect(values['unrelated-private-key'], 'keep');
      expect(await databaseState(), before);
    },
  );
  test(
    'filters survive reconstruction and preserve layout and actual visits per database',
    () async {
      await prefs.record('note', note);
      await prefs.saveLayout([
        const HomeLayoutItem(key: 'books', width: 3, hidden: true),
      ]);
      final query = HomeQuery(
        month: DateTime(2024, 2),
        order: 'created',
        limit: 20,
        end: '2024-02-29',
        view: HomeCalendarView.week,
      );
      await repo.rememberQuery(query);
      final reopened = LocalHomePreferences(
        namespace: store.path,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
      );
      expect(
        (await reopened.restoreQuery())!.toPreference(),
        query.toPreference(),
      );
      final saved = await reopened.read();
      expect(saved.$1.first.key, 'books');
      expect(saved.$2.single.id, note);
      final other = LocalHomePreferences(
        namespace: 'other-db',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
      );
      expect(await other.restoreQuery(), isNull);
      expect(values[prefs.key], isNot(contains('Actual note')));
      expect(values[prefs.key], isNot(contains('literal body')));
      await prefs.clearVisits();
      expect(
        (await prefs.restoreQuery())!.toPreference(),
        query.toPreference(),
      );
    },
  );
  test(
    'corrupt filter preferences are retained until explicit reset',
    () async {
      values[prefs.key] = jsonEncode({
        'format': 1,
        'layout': null,
        'visits': [],
        'query': {
          'month': '2026-02',
          'order': 'created',
          'limit': 99,
          'view': 'day',
          'end': null,
        },
      });
      final original = values[prefs.key];
      await expectLater(
        prefs.restoreQuery(),
        throwsA(isA<HomePreferencesCorrupt>()),
      );
      await expectLater(
        prefs.rememberQuery(HomeQuery()),
        throwsA(isA<HomePreferencesCorrupt>()),
      );
      expect(values[prefs.key], original);
      await prefs.reset();
      expect(await prefs.restoreQuery(), isNull);
    },
  );
}
