import 'support/frozen_schema14_store.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_backup_schema.dart';
import 'package:bookstark_flutter/core/local_store.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space;
  late LocalStore store;
  late LocalBackupSchemaVerifier verifier;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('backup-schema-');
    store = FrozenSchema14Store(
      path: '${space.path}/source.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    verifier = LocalBackupSchemaVerifier(
      factory: databaseFactoryFfiNoIsolate,
      workspace: Directory('${space.path}/verify'),
    );
    await store.database;
  });
  tearDown(() async {
    await store.close();
    await space.delete(recursive: true);
  });
  Future<File> snapshot() async {
    final target = File('${space.path}/copy.db');
    await (await store.database).execute('VACUUM INTO ?', [target.path]);
    return target;
  }

  test(
    'actual VACUUM database schema and exact rows pass without modifying bytes',
    () async {
      await store.createNote('完整笔记😀', '\uFEFF# 原文\r\n保留', labels: ['原始']);
      final db = await store.database;
      await db.insert('html_creation_receipts', {
        'creation_key': 'a' * 32,
        'note_id': 1,
        'collection': 'note',
        'input_hash': 'b' * 64,
        'created_at': 1,
      });
      final file = await snapshot();
      final before = sha256.convert(await file.readAsBytes());
      final facts = await verifier.verify(file);
      expect(facts.tables['notes'], 1);
      expect(facts.tables['html_creation_receipts'], 1);
      expect(facts.readerSQLiteVersion, isNotEmpty);
      await verifier.verify(file, declaredRows: facts.tables);
      expect(sha256.convert(await file.readAsBytes()), before);
      expect(await Directory('${space.path}/verify').list().toList(), isEmpty);
    },
  );

  for (final sql in [
    'CREATE TABLE unexpected (id INTEGER)',
    'CREATE VIEW untrusted_view AS SELECT * FROM notes',
    'CREATE INDEX unexpected_index ON notes(title)',
    'CREATE TRIGGER unexpected_trigger AFTER UPDATE ON notes BEGIN DELETE FROM books; END',
    'ALTER TABLE notes ADD COLUMN unexpected TEXT',
    'DROP INDEX local_images_hash',
  ]) {
    test('untrusted schema rejected: $sql', () async {
      await (await store.database).execute(sql);
      await expectLater(
        verifier.verify(await snapshot()),
        throwsFormatException,
      );
    });
  }

  test(
    'quoted CHECK expression cannot masquerade as the trusted expression',
    () async {
      final db = await store.database;
      final rows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name='html_preview_resources'",
      );
      final sql = rows.single['sql'] as String;
      final changed = sql.replaceFirst(
        'CHECK(note_id > 0)',
        'CHECK("note_id > 0")',
      );
      expect(changed, isNot(sql));
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute(changed);
      await expectLater(
        verifier.verify(await snapshot()),
        throwsFormatException,
      );
    },
  );

  test(
    'wrong user_version is not upgraded and source remains unchanged',
    () async {
      final db = await store.database;
      await db.execute('PRAGMA user_version = 13');
      final file = await snapshot();
      final before = sha256.convert(await file.readAsBytes());
      await expectLater(verifier.verify(file), throwsFormatException);
      expect(sha256.convert(await file.readAsBytes()), before);
      final read = await databaseFactoryFfiNoIsolate.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(
          (await read.rawQuery('PRAGMA user_version')).single.values.single,
          13,
        );
      } finally {
        await read.close();
      }
    },
  );

  test('manifest row counts are checked against actual database', () async {
    final file = await snapshot();
    final facts = await verifier.verify(file);
    await expectLater(
      verifier.verify(file, declaredRows: {...facts.tables, 'notes': 7}),
      throwsFormatException,
    );
  });

  test(
    'metadata table can be absent or use the exact Android locale shape',
    () async {
      final db = await store.database;
      await db.execute('CREATE TABLE android_metadata (locale TEXT)');
      await db.insert('android_metadata', {'locale': 'zh_CN'});
      expect(
        (await verifier.verify(await snapshot())).tables['android_metadata'],
        1,
      );
    },
  );

  test(
    'malformed Android metadata table is not exempted from validation',
    () async {
      await (await store.database).execute(
        'CREATE TABLE android_metadata (secret BLOB)',
      );
      await expectLater(
        verifier.verify(await snapshot()),
        throwsFormatException,
      );
    },
  );
  test(
    'actual v11 upgrade has the trusted v14 shape and preserves existing data',
    () async {
      await store.createNote('旧版本😀', '原始内容');
      final path = store.path;
      await store.close();
      final old = await databaseFactoryFfiNoIsolate.openDatabase(path);
      try {
        await old.execute('DROP TRIGGER html_preview_resources_note_delete');
        await old.execute('DROP TABLE html_preview_resources');
        await old.execute('DROP TABLE html_creation_receipts');
        await old.execute('ALTER TABLE notes DROP COLUMN editor_type');
        await old.execute('PRAGMA user_version = 11');
      } finally {
        await old.close();
      }
      store = LocalStore(path: path, factory: databaseFactoryFfiNoIsolate);
      final upgraded = await store.database;
      expect((await upgraded.query('notes')).single['content'], '原始内容');
      final facts = await verifier.verify(await snapshot(), expectedSchema: 16);
      expect(facts.tables['notes'], 1);
      expect(facts.tables['html_creation_receipts'], 0);
      expect(facts.tables['html_preview_resources'], 0);
    },
  );
}
