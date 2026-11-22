import 'support/frozen_schema14_store.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
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
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookstark-schema16-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<String> rows(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name!='assistant_creation_receipts' ORDER BY name",
    );
    return jsonEncode({
      for (final table in tables)
        table['name'] as String: await db.query(table['name'] as String),
    });
  }

  Future<String> schema(Database db) async => jsonEncode(
    await db.rawQuery(
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
    ),
  );
  test(
    'owned14 upgrade retains every old table value and produces the exact fresh16 schema',
    () async {
      final store = FrozenSchema14Store(
        path: '${directory.path}/old.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote('保留😀', '\ufefforiginal body', labels: [' 原始 ']);
        await store.createNote('Deleted', 'ENC:v1:opaque');
        final db = await store.database;
        await db.update(
          'notes',
          {'deleted': 1, 'updated_at': 123},
          where: 'id=?',
          whereArgs: [2],
        );
        final before = await rows(db);
        await db.transaction(extendSchema14ForAssistant16);
        expect(await rows(db), before);
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          16,
        );
        expect(await db.query('assistant_creation_receipts'), isEmpty);
        final fresh = await databaseFactoryFfiNoIsolate.openDatabase(
          '${directory.path}/new.db',
          options: OpenDatabaseOptions(
            version: 16,
            onCreate: (db, _) => createLocalSchema16(db),
          ),
        );
        try {
          expect(await schema(db), await schema(fresh));
        } finally {
          await fresh.close();
        }
      } finally {
        await store.close();
      }
    },
  );
  test(
    'candidate15 is rejected without modifying its schema or rows',
    () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        '${directory.path}/candidate.db',
        options: OpenDatabaseOptions(
          version: 15,
          onCreate: (db, _) => createLegacyCandidateSchema15(db),
        ),
      );
      try {
        final beforeSchema = await schema(db), beforeRows = await rows(db);
        await expectLater(
          db.transaction(extendSchema14ForAssistant16),
          throwsFormatException,
        );
        expect(await schema(db), beforeSchema);
        expect(await rows(db), beforeRows);
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          15,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'a conflicting receipt table aborts migration without changing version or data',
    () async {
      final store = FrozenSchema14Store(
        path: '${directory.path}/conflict.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote('Original', 'Keep');
        final db = await store.database;
        await db.execute(
          'CREATE TABLE assistant_creation_receipts (unexpected TEXT)',
        );
        final beforeRows = await rows(db), beforeSchema = await schema(db);
        await expectLater(
          db.transaction(extendSchema14ForAssistant16),
          throwsA(isA<DatabaseException>()),
        );
        expect(await rows(db), beforeRows);
        expect(await schema(db), beforeSchema);
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          14,
        );
      } finally {
        await store.close();
      }
    },
  );
  test('active opener upgrades real14 once and preserves all rows', () async {
    final path = '${directory.path}/active.db';
    final old = FrozenSchema14Store(
      path: path,
      factory: databaseFactoryFfiNoIsolate,
    );
    await old.createNote('Original', '\ufeffexact', labels: [' x ']);
    final before = await rows(await old.database);
    await old.close();
    for (var i = 0; i < 2; i++) {
      final active = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await active.database;
        expect(await db.getVersion(), 16);
        expect(await rows(db), before);
        expect(await db.query('assistant_creation_receipts'), isEmpty);
      } finally {
        await active.close();
      }
    }
  });
  test(
    'active opener rejects candidate15 without changing any file bytes',
    () async {
      final path = '${directory.path}/reject15.db';
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 15,
          onCreate: (db, _) => createLegacyCandidateSchema15(db),
        ),
      );
      await db.close();
      final before = await File(path).readAsBytes();
      final active = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      await expectLater(active.database, throwsA(anything));
      expect(await File(path).readAsBytes(), before);
    },
  );
  test(
    'failed active migration rolls back receipt DDL and retains14 bytes',
    () async {
      final path = '${directory.path}/reject-conflict.db';
      final old = FrozenSchema14Store(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      await old.createNote('Keep', 'Original');
      await (await old.database).execute(
        'CREATE TABLE assistant_creation_receipts (unexpected TEXT)',
      );
      await old.close();
      final before = await File(path).readAsBytes();
      final active = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      await expectLater(active.database, throwsA(isA<DatabaseException>()));
      expect(await File(path).readAsBytes(), before);
    },
  );
  test(
    'unknown newer version is rejected without changing file bytes',
    () async {
      final path = '${directory.path}/future.db';
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 17,
          onCreate: (db, _) => db.execute('CREATE TABLE future (id INTEGER)'),
        ),
      );
      await db.close();
      final before = await File(path).readAsBytes();
      final active = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      await expectLater(active.database, throwsA(anything));
      expect(await File(path).readAsBytes(), before);
    },
  );
}
