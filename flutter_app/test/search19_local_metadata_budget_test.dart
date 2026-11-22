import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/local_search_content_reader.dart';
import 'package:bookstark_flutter/core/local_search_metadata_reader.dart';
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
    'label discovery projects labels only despite unrelated huge source title and private body',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        final id = await db.rawInsert(
          "INSERT INTO notes(title,content,labels,updated_at) VALUES(CAST(zeroblob(?) AS TEXT),CAST(? AS TEXT),?,1)",
          [
            3 * 1024 * 1024,
            Uint8List.fromList(utf8.encode('\ufeffprivate source\r\n😀')),
            jsonEncode(['Legacy label']),
          ],
        );
        final before = (await db.rawQuery(
          'SELECT length(CAST(title AS BLOB)) AS title_bytes,CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
          [id],
        )).single;
        final results = await LocalSearchRepository(store).search('Legacy');
        expect(results.groups[SearchKind.label], hasLength(1));
        expect(results.groups[SearchKind.label]!.single.title, 'Legacy label');
        expect(results.groups[SearchKind.blog], isEmpty);
        expect(
          (await db.rawQuery(
            'SELECT length(CAST(title AS BLOB)) AS title_bytes,CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
            [id],
          )).single,
          before,
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'matched oversized metadata refuses result and rolls back newly discovered registry names',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final id = await store.createNote(
          'Needle ${'x' * 4096}',
          'body',
          labels: ['unregistered'],
        );
        final db = await store.database;
        expect(await db.query('local_labels'), isEmpty);
        await expectLater(
          LocalSearchRepository(store).search('Needle'),
          throwsA(isA<LocalSearchContentLimit>()),
        );
        expect(await db.query('local_labels'), isEmpty);
        expect(
          (await db.query(
            'notes',
            columns: ['labels', 'updated_at'],
            where: 'id=?',
            whereArgs: [id],
          )).single['labels'],
          jsonEncode(['unregistered']),
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'oversized label array rejected by scalar preflight before any partial registration',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote('First', 'private', labels: ['first-name']);
        final db = await store.database;
        await db.rawInsert(
          "INSERT INTO notes(title,content,labels,updated_at) VALUES('Second','private',CAST(zeroblob(?) AS TEXT),2)",
          [LocalSearchMetadataReader.maxLabelsBytes + 1],
        );
        final before = await db.rawQuery(
          'SELECT id,length(CAST(labels AS BLOB)) AS n,updated_at FROM notes ORDER BY id',
        );
        await expectLater(
          LocalSearchRepository(store).search('First'),
          throwsA(isA<LocalSearchContentLimit>()),
        );
        expect(await db.query('local_labels'), isEmpty);
        expect(
          await db.rawQuery(
            'SELECT id,length(CAST(labels AS BLOB)) AS n,updated_at FROM notes ORDER BY id',
          ),
          before,
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'late registry SQL failure atomically restores all prior discovery insertions and source bytes',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final id = await store.createNote(
          'Needle',
          '\ufeffprivate\r\n😀',
          labels: ['A', 'B'],
        );
        final db = await store.database;
        await db.execute(
          "CREATE TRIGGER reject_late_discovery BEFORE INSERT ON local_labels WHEN NEW.label_name='B' BEGIN SELECT RAISE(ABORT,'synthetic second registry failure'); END",
        );
        final before = (await db.rawQuery(
          'SELECT CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
          [id],
        )).single;
        await expectLater(
          LocalSearchRepository(store).search('Needle'),
          throwsA(isA<DatabaseException>()),
        );
        expect(await db.query('local_labels'), isEmpty);
        expect(
          (await db.rawQuery(
            'SELECT CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
            [id],
          )).single,
          before,
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'bounded metadata BLOB decode retains actual BOM and emoji title without CursorWindow TEXT normalization',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        const title = '\ufeffNeedle 😀';
        await store.createNote(title, 'ordinary body');
        final actual = (await LocalSearchRepository(
          store,
        ).search('Needle')).groups[SearchKind.blog]!;
        expect(actual, hasLength(1));
        expect(actual.single.title, title);
      } finally {
        await store.close();
      }
    },
  );
  test(
    'repeated existing-name discovery preserves registry IDs and AUTOINCREMENT state',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote('Needle', 'body', labels: ['Legacy']);
        final repo = LocalSearchRepository(store);
        await repo.search('Legacy');
        final db = await store.database;
        final rows = await db.rawQuery(
          'SELECT label_id,CAST(label_name AS BLOB) AS name FROM local_labels ORDER BY label_id',
        );
        final sequence = await db.rawQuery(
          "SELECT seq FROM sqlite_sequence WHERE name='local_labels'",
        );
        await repo.search('Legacy');
        expect(
          await db.rawQuery(
            'SELECT label_id,CAST(label_name AS BLOB) AS name FROM local_labels ORDER BY label_id',
          ),
          rows,
        );
        expect(
          await db.rawQuery(
            "SELECT seq FROM sqlite_sequence WHERE name='local_labels'",
          ),
          sequence,
        );
      } finally {
        await store.close();
      }
    },
  );
}
