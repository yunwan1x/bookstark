import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_search_body_scan.dart';
import 'package:bookstark_flutter/core/local_search_content_reader.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/search_matching.dart';
import 'package:bookstark_flutter/core/search_repository.dart';

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
    'streaming matches exact existing snippet and word contract across boundaries',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        for (final query in ['needle', 'NeEdLe', '😀针📚', 'a-a']) {
          for (final pad in [
            0,
            1,
            65520,
            65529,
            65530,
            65531,
            65532,
            65533,
            65534,
            65535,
            65536,
          ]) {
            final source =
                '\ufeff${'x' * pad} 😀 $query! needleSuffix\r\n${'📚' * 100} tail';
            final id = await store.createNote('Plain', source);
            final actual = await db.transaction(
              (tx) => LocalSearchBodyScan.read(
                tx,
                id: id,
                query: query,
                guard: () {},
                collection: 'note',
                editorType: 'markdown',
              ),
            );
            expect(
              actual.snippet,
              searchSnippet(source, query),
              reason: 'query $query pad $pad',
            );
            expect(
              actual.wholeWord,
              matchesSearchWord(source, query),
              reason: 'query $query pad $pad',
            );
            await db.delete('notes', where: 'id=?', whereArgs: [id]);
          }
        }
        for (final body in [
          '${'x' * 65529} needleSuffix',
          '${'x' * 65529} needleSuffix ${'q' * 65536} needle!',
        ]) {
          final id = await store.createNote('Plain', body);
          final actual = await db.transaction(
            (tx) => LocalSearchBodyScan.read(
              tx,
              id: id,
              query: 'needle',
              guard: () {},
              collection: 'note',
              editorType: 'markdown',
            ),
          );
          expect(actual.wholeWord, matchesSearchWord(body, 'needle'));
          expect(actual.snippet, searchSnippet(body, 'needle'));
        }
      } finally {
        await store.close();
      }
    },
  );
  test(
    'short and double-BOM EOF snippets retain exact rune contract',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        for (final body in [
          '',
          '\ufeff',
          '\ufeff\ufeffNeedle\r\n😀',
          '${'📚' * 180} Needle',
          'No matching source',
        ]) {
          final id = await store.createNote('Plain', body);
          final scan = await db.transaction(
            (tx) => LocalSearchBodyScan.read(
              tx,
              id: id,
              query: 'needle',
              guard: () {},
              collection: 'note',
              editorType: 'markdown',
            ),
          );
          expect(scan.snippet, searchSnippet(body, 'needle'));
          expect(scan.wholeWord, matchesSearchWord(body, 'needle'));
        }
      } finally {
        await store.close();
      }
    },
  );
  test('early match never skips malformed UTF8 tail or mutates rows', () async {
    final store = LocalStore(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    try {
      final db = await store.database;
      await db.rawInsert(
        "INSERT INTO notes(collection,title,content,labels,updated_at,editor_type) VALUES('note','Plain',CAST(? AS TEXT),'[]',17,'markdown')",
        [
          Uint8List.fromList([
            78,
            101,
            101,
            100,
            108,
            101,
            32,
            ...List.filled(2 * LocalSearchBodyScan.chunkBytes, 120),
            240,
            159,
          ]),
        ],
      );
      final before = await db.rawQuery(
        'SELECT id,hex(substr(CAST(content AS BLOB),-2)) AS tail,length(CAST(content AS BLOB)) AS n,updated_at FROM notes',
      );
      await expectLater(
        LocalSearchRepository(store).search('Needle'),
        throwsFormatException,
      );
      expect(
        await db.rawQuery(
          'SELECT id,hex(substr(CAST(content AS BLOB),-2)) AS tail,length(CAST(content AS BLOB)) AS n,updated_at FROM notes',
        ),
        before,
      );
    } finally {
      await store.close();
    }
  });
  test(
    'owner retirement cancels body blocks before result publication',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final id = await store.createNote(
          'Plain',
          'Needle ${'x' * (3 * LocalSearchBodyScan.chunkBytes)}',
        );
        final db = await store.database;
        var guards = 0;
        await expectLater(
          db.transaction(
            (tx) => LocalSearchBodyScan.read(
              tx,
              id: id,
              query: 'Needle',
              collection: 'note',
              editorType: 'markdown',
              guard: () {
                if (++guards == 6) throw StateError('retired');
              },
            ),
          ),
          throwsStateError,
        );
        expect(guards, 6);
        expect(
          (await db.query(
            'notes',
            columns: ['id'],
            where: 'id=?',
            whereArgs: [id],
          )).single['id'],
          id,
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'topic complete context retains preflight limit with no truncated question',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        await db.rawInsert(
          "INSERT INTO topics(title,question,create_time,modify_time) VALUES('Needle',CAST(zeroblob(?) AS TEXT),'x','x')",
          [LocalSearchContentReader.maxRecordBytes + 1],
        );
        await expectLater(
          LocalSearchRepository(store).search('Needle'),
          throwsA(isA<LocalSearchContentLimit>()),
        );
        expect(
          (await db.rawQuery(
            'SELECT length(CAST(question AS BLOB)) AS n FROM topics',
          )).single['n'],
          LocalSearchContentReader.maxRecordBytes + 1,
        );
      } finally {
        await store.close();
      }
    },
  );
  test('protected body is excluded even on title hit', () async {
    final store = LocalStore(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    try {
      await store.createNote('Visible', '\ufeffENC:unknown:Needle');
      final repo = LocalSearchRepository(store);
      expect((await repo.search('Needle')).groups[SearchKind.blog], isEmpty);
      expect(
        (await repo.search('Visible')).groups[SearchKind.blog]!.single.snippet,
        isEmpty,
      );
    } finally {
      await store.close();
    }
  });
  test(
    'long direct-helper queries recover centered snippets from overlap across blocks',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        // Production queries are limited to100 UTF8 bytes, but this lower-level
        // scanner still preserves the full searchSnippet contract for direct callers.
        for (final query in ['N' * 1000, '😀' * 800]) {
          for (final pad in [65536 - 1901, 65536 - 901, 65536 - 101]) {
            final body = '\ufeff${'x' * pad} $query!${'📚' * 1000}';
            final id = await store.createNote('Plain', body);
            final actual = await db.transaction(
              (tx) => LocalSearchBodyScan.read(
                tx,
                id: id,
                query: query,
                guard: () {},
                collection: 'note',
                editorType: 'markdown',
              ),
            );
            expect(
              actual.snippet,
              searchSnippet(body, query),
              reason: 'long queryUTF16 ${query.length} pad $pad',
            );
            expect(actual.wholeWord, matchesSearchWord(body, query));
            expect(actual.snippet.runes.length, lessThanOrEqualTo(156));
          }
        }
      } finally {
        await store.close();
      }
    },
  );
}
