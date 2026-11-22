import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space;
  late List<Object?> expected;
  setUpAll(() async {
    final fixture =
        jsonDecode(
              await File(
                'test/fixtures/local-schema14-contract.json',
              ).readAsString(),
            )
            as Map;
    expect(fixture['schemaVersion'], 14);
    expect(fixture['userRowsIncluded'], false);
    expected = fixture['objects'] as List<Object?>;
  });
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('schema14-contract-');
  });
  tearDown(() async => space.delete(recursive: true));

  Future<List<Map<String, Object?>>> objects(Database db) => db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name!='android_metadata' ORDER BY type,name",
  );

  test(
    'independent schema14 template equals immutable pre-extraction contract',
    () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        '${space.path}/template.db',
        options: OpenDatabaseOptions(
          version: 14,
          singleInstance: false,
          onCreate: (db, version) => createLocalSchema14(db),
        ),
      );
      try {
        expect(await db.getVersion(), 14);
        expect(await objects(db), expected);
      } finally {
        await db.close();
      }
    },
  );

  test('active store retains every frozen14 schema object exactly', () async {
    final store = LocalStore(
      path: '${space.path}/active.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    try {
      final actual = await objects(await store.database);
      final names = expected.map((row) => (row as Map)['name']).toSet();
      expect(
        actual.where((row) => names.contains(row['name'])).toList(),
        expected,
      );
    } finally {
      await store.close();
    }
  });

  test(
    'v13 upgrade still calls frozen helpers without rewriting existing rows',
    () async {
      final path = '${space.path}/upgrade.db';
      final initial = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      const row = {
        'id': 71,
        'title': 'old',
        'content': '\uFEFF<p>exact</p>\r\n',
        'updated_at': 17,
        'deleted': 1,
        'labels': '["old"]',
        'collection': 'note',
        'editor_type': 'html',
      };
      await (await initial.database).insert('notes', row);
      await initial.close();
      final raw = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await raw.execute('DROP TRIGGER html_preview_resources_note_delete');
      await raw.execute('DROP TABLE html_preview_resources');
      await raw.execute('DROP TABLE assistant_creation_receipts');
      await raw.setVersion(13);
      final sequence = await raw.rawQuery(
        'SELECT * FROM sqlite_sequence ORDER BY name',
      );
      await raw.close();
      final migrated = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await migrated.database;
        expect(await db.getVersion(), 16);
        expect(
          (await objects(db))
              .where((row) => row['tbl_name'] != 'assistant_creation_receipts')
              .toList(),
          expected,
        );
        // Compare stored bytes, not the driver's String conversion (which
        // itself strips a leading UTF8 BOM). A schema upgrade must preserve it.
        final stored = (await db.rawQuery(
          'SELECT id,title,hex(CAST(content AS BLOB)) AS content_hex,'
          'updated_at,deleted,labels,collection,editor_type FROM notes',
        )).single;
        final expectedRow = Map<String, Object?>.from(row)..remove('content');
        expectedRow['content_hex'] = utf8
            .encode(row['content'] as String)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
        expect(stored, expectedRow);
        expect(
          await db.rawQuery('SELECT * FROM sqlite_sequence ORDER BY name'),
          sequence,
        );
        expect(await db.query('html_preview_resources'), isEmpty);
      } finally {
        await migrated.close();
      }
    },
  );
}
