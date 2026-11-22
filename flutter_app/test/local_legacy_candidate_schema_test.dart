import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_backup_schema.dart';
import 'package:crypto/crypto.dart';
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
  late Directory root;
  final opened = <Database>[];
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('candidate15-');
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.isOpen) await db.close();
    }
    opened.clear();
    await root.delete(recursive: true);
  });
  Future<Database> database(String name, int version) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      '${root.path}/$name.db',
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, version) => version == 15
            ? createLegacyCandidateSchema15(db)
            : createLocalSchema14(db),
      ),
    );
    opened.add(db);
    return db;
  }

  Future<void> seed(Database db) async {
    final rows = <String, Map<String, Object?>>{
      'notes': {
        'id': 3,
        'title': 'source',
        'content': '\uFEFF<p>exact</p>\r\n',
        'updated_at': 17,
        'labels': '["old"]',
        'collection': 'article',
        'editor_type': 'html',
      },
      'books': {
        'book_id': 5,
        'book_name': 'book',
        'identify': 'book',
        'create_time': '',
        'modify_time': '',
      },
      'documents': {
        'document_id': 7,
        'book_id': 5,
        'document_name': 'doc',
        'identify': 'doc',
        'markdown': '\uFEFF# exact\r\n',
        'create_time': '',
        'modify_time': '',
      },
      'tasks': {
        'task_id': 9,
        'content': 'task',
        'due_date': '',
        'create_time': '',
        'modify_time': '',
      },
      'topics': {
        'topic_id': 11,
        'title': 'topic',
        'create_time': '',
        'modify_time': '',
      },
      'topic_summaries': {
        'summary_id': 13,
        'topic_id': 11,
        'content': 'summary',
        'create_time': '',
        'modify_time': '',
      },
      'topic_resources': {
        'topic_resource_id': 15,
        'topic_id': 11,
        'resource_type': 'note',
        'target_id': 3,
        'title_snapshot': 'source',
        'create_time': '',
      },
      'topic_comments': {
        'comment_id': 17,
        'topic_id': 11,
        'target_type': 'summary',
        'target_id': 13,
        'content': 'comment',
        'create_time': '',
        'modify_time': '',
      },
      'local_labels': {'label_id': 19, 'label_name': 'old'},
      'bookmarks': {
        'bookmark_id': 21,
        'title': 'url',
        'url': 'https://example.invalid',
        'create_time': 1,
        'modify_time': 2,
      },
      'trash_entries': {
        'trash_id': 23,
        'resource_type': 'note',
        'resource_id': 31,
        'name': 'old',
        'payload': '{}',
        'deleted_at': '',
      },
      'local_drive_nodes': {
        'node_id': 25,
        'path': 'fixture.bin',
        'parent_path': '',
        'name': 'fixture.bin',
        'directory': 0,
        'mime_type': 'application/octet-stream',
        'create_time': '',
        'modify_time': '',
      },
      'local_images': {
        'image_id': 27,
        'attachment_id': 'a' * 32,
        'file_name': 'image.png',
        'mime_type': 'image/png',
        'file_size': 0,
        'modify_time': '',
      },
      'label_recommendation_settings': {'id': 1, 'settings': '{}'},
      'html_creation_receipts': {
        'creation_key': 'c' * 32,
        'note_id': 3,
        'collection': 'article',
        'input_hash': 'd' * 64,
        'created_at': 17,
      },
      'html_preview_resources': {
        'note_id': 3,
        'resource_path': 'fixture.bin',
        'node_id': 25,
        'approved_hash': 'd' * 64,
      },
    };
    for (final item in rows.entries) {
      await db.insert(item.key, item.value);
    }
  }

  test(
    'candidate extension preserves all old tables, IDs, bytes and sequences',
    () async {
      final db = await database('clone', 14);
      await seed(db);
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((row) => row['name'] as String).toList();
      final columns = <String, List<String>>{},
          before = <String, List<Map<String, Object?>>>{};
      for (final name in tables) {
        columns[name] = (await db.rawQuery(
          'PRAGMA table_info("$name")',
        )).map((row) => row['name'] as String).toList();
        before[name] = await db.query(name, orderBy: 'rowid');
      }
      final bytes = await db.rawQuery(
        'SELECT hex(CAST(content AS BLOB)) AS exact FROM notes',
      );
      expect(bytes.single['exact'], startsWith('EFBBBF'));
      await db.transaction((tx) => extendSchema14ForLegacyCandidate15(tx));
      expect(await db.getVersion(), 15);
      for (final name in tables) {
        expect(
          await db.query(name, columns: columns[name], orderBy: 'rowid'),
          before[name],
          reason: name,
        );
      }
      expect(
        await db.rawQuery(
          'SELECT hex(CAST(content AS BLOB)) AS exact FROM notes',
        ),
        bytes,
      );
      final note = (await db.query('notes')).single;
      expect(note['password_hash'], '');
      expect(note['is_pinned'], 0);
      expect((await db.query('topic_comments')).single['parent_comment_id'], 0);
    },
  );
  test(
    'fresh draft has source constraints and permits duplicate friend URLs',
    () async {
      final db = await database('fresh', 15);
      expect(await db.getVersion(), legacyCandidateSchemaVersion);
      final source = {
        'source_sha256': 'a' * 64,
        'source_kind': 'go_zip_v1',
        'manifest_json': '{}',
        'format_recipe_json': '{}',
        'imported_at': '',
      };
      await db.insert('legacy_import_sources', source);
      for (final patch in [
        {'source_sha256': 'A' * 64},
        {'source_sha256': 'z' * 64},
        {'source_sha256': 'b' * 64, 'source_kind': 'raw_sqlite_unselected'},
      ]) {
        await expectLater(
          db.insert('legacy_import_sources', {...source, ...patch}),
          throwsA(isA<DatabaseException>()),
        );
      }
      final friend = {
        'source_sha256': 'a' * 64,
        'link_name': 'same',
        'link_url': 'https://example.invalid',
        'group_name': 'group',
        'group_order': 7,
        'qr_code': 'opaque',
        'description': 'keep',
        'sort_weight': -3,
        'is_enabled': 0,
        'create_time': '',
        'modify_time': '',
      };
      await db.insert('legacy_friend_links', {'link_id': 1, ...friend});
      await db.insert('legacy_friend_links', {'link_id': 2, ...friend});
      expect((await db.query('legacy_friend_links')).length, 2);
      await expectLater(
        db.insert('legacy_friend_links', {
          'link_id': 3,
          ...friend,
          'is_enabled': 2,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('legacy_import_records', {
          'kind': 'note',
          'local_id': 1,
          'source_sha256': 'b' * 64,
          'source_key': '["note"]',
          'payload': '{}',
          'payload_sha256': 'c' * 64,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('wrong-version clone is rejected before changing its catalog', () async {
    final db = await database('wrong', 13);
    final before = await db.rawQuery(
      'SELECT type,name,sql FROM sqlite_master ORDER BY name',
    );
    await expectLater(
      db.transaction((tx) => extendSchema14ForLegacyCandidate15(tx)),
      throwsFormatException,
    );
    expect(await db.getVersion(), 13);
    expect(
      await db.rawQuery(
        'SELECT type,name,sql FROM sqlite_master ORDER BY name',
      ),
      before,
    );
  });
  test(
    'frozen v14 backup reader refuses draft15 without changing its bytes',
    () async {
      final db = await database('unsupported', 15);
      await db.close();
      final file = File('${root.path}/unsupported.db');
      final before = (await sha256.bind(file.openRead()).first).toString();
      final verifier = LocalBackupSchemaVerifier(
        factory: databaseFactoryFfiNoIsolate,
        workspace: Directory('${root.path}/verify'),
      );
      await expectLater(verifier.verify(file), throwsFormatException);
      expect((await sha256.bind(file.openRead()).first).toString(), before);
      final active = LocalStore(
        path: '${root.path}/active.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        expect(await (await active.database).getVersion(), 16);
      } finally {
        await active.close();
      }
    },
  );
}
