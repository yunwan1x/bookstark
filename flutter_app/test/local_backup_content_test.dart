import 'support/frozen_schema14_store.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_schema.dart';
import 'package:bookstark_flutter/core/local_backup_content.dart';

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
  late Database db;
  late Map<String, List<int>> payloads;
  var serial = 0;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('backup-content-');
    store = FrozenSchema14Store(
      path: '${space.path}/source.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    db = await store.database;
    payloads = {};
  });
  tearDown(() async {
    await store.close();
    await space.delete(recursive: true);
  });
  Future<int> note({
    String type = 'markdown',
    String labels = '[]',
    int deleted = 0,
  }) => db.insert('notes', {
    'title': '原文😀',
    'content': '\uFEFF<p>正文\r\nfuture</p>',
    'updated_at': 1,
    'editor_type': type,
    'labels': labels,
    'deleted': deleted,
  });
  Future<int> task({int parent = 0, int deleted = 0}) => db.insert('tasks', {
    'content': '完整任务',
    'due_date': '2026-11-08',
    'parent_id': parent,
    'deleted': deleted,
    'create_time': '2026-11-08',
    'modify_time': '2026-11-08',
  });
  Future<int> drive({
    String path = 'a.bin',
    List<int> bytes = const [0, 255, 1],
    String? hash,
  }) async {
    final key = 'a' * 32 + '.blob';
    payloads['drive-blobs/$key'] = bytes;
    return db.insert('local_drive_nodes', {
      'path': path,
      'parent_path': driveParentForTest(path),
      'name': path.split('/').last,
      'directory': 0,
      'file_size': bytes.length,
      'file_hash': hash ?? sha256.convert(bytes).toString(),
      'blob_key': key,
      'mime_type': 'image/png',
      'create_time': '2026-11-08',
      'modify_time': '2026-11-08',
    });
  }

  Future<void> bind(int owner, int node, String hash) => db
      .insert('html_preview_resources', {
        'note_id': owner,
        'resource_path': 'assets/image.png',
        'node_id': node,
        'approved_hash': hash,
      })
      .then((_) {});
  Future<LocalBackupContentReport> check() async {
    final file = File('${space.path}/copy-${++serial}.db');
    await db.execute('VACUUM INTO ?', [file.path]);
    final schema = await LocalBackupSchemaVerifier(
      factory: databaseFactoryFfiNoIsolate,
      workspace: Directory('${space.path}/verify'),
    ).verify(file);
    final manifest = LocalBackupManifest(
      id: 'b' * 32,
      createdAt: '2026-11-08T00:00:00.000Z',
      sqliteVersion: schema.readerSQLiteVersion,
      tables: schema.tables,
      files: [
        LocalBackupFile(
          path: 'database/content.db',
          bytes: await file.length(),
          sha256: (await sha256.bind(file.openRead()).first).toString(),
        ),
        for (final entry in payloads.entries)
          LocalBackupFile(
            path: entry.key,
            bytes: entry.value.length,
            sha256: sha256.convert(entry.value).toString(),
          ),
      ],
    );
    final before = await file.readAsBytes();
    final result = await LocalBackupContentVerifier(
      databaseFactoryFfiNoIsolate,
    ).verify(file, manifest, schema);
    expect(await file.readAsBytes(), before);
    return result;
  }

  test(
    'valid exact source, labels and real task trash payload remain untouched',
    () async {
      final id = await note(labels: '[ " 资料 ", "comma,label", "资料" ]');
      await db.insert('html_creation_receipts', {
        'creation_key': 'c' * 32,
        'note_id': id,
        'collection': 'note',
        'input_hash': 'd' * 64,
        'created_at': 1,
      });
      final t = await task();
      await LocalTasksRepository(store).remove(t);
      final before = await db.query('trash_entries');
      final report = await check();
      expect(report.needsAdditionalReview, isFalse);
      expect(await db.query('trash_entries'), before);
      expect(
        (await db.query('notes')).single['labels'],
        '[ " 资料 ", "comma,label", "资料" ]',
      );
    },
  );

  test(
    'missing owned drive bytes and SQL/blob hash mismatch are rejected',
    () async {
      await drive();
      payloads.clear();
      await expectLater(check(), throwsFormatException);
      payloads['drive-blobs/${'a' * 32}.blob'] = [1, 2, 3];
      await expectLater(check(), throwsFormatException);
    },
  );

  test(
    'unsafe drive virtual hierarchy never becomes a filesystem instruction',
    () async {
      await drive(path: '../outside');
      await expectLater(check(), throwsFormatException);
    },
  );

  test('active task cycle and unavailable parent are rejected', () async {
    final id = await task(parent: 1);
    expect(id, 1);
    await expectLater(check(), throwsFormatException);
    await db.update(
      'tasks',
      {'parent_id': 999},
      where: 'task_id=?',
      whereArgs: [id],
    );
    await expectLater(check(), throwsFormatException);
  });

  test('deleted orphan remains preserved and explicitly reported', () async {
    final id = await task(parent: 999, deleted: 1);
    final result = await check();
    expect(result.unavailableReferences, 1);
    expect(
      (await db.query(
        'tasks',
        where: 'task_id=?',
        whereArgs: [id],
      )).single['parent_id'],
      999,
    );
  });

  test(
    'malformed labels, unsupported editor, invalid bool and SQLite affinity fail',
    () async {
      final id = await note(labels: '{"not":"a list"}');
      await expectLater(check(), throwsFormatException);
      for (final values in [
        <String, Object?>{'labels': '[1]'},
        <String, Object?>{'labels': '[]', 'editor_type': 'future-unsupported'},
        <String, Object?>{'editor_type': 'markdown', 'deleted': 2},
        <String, Object?>{'deleted': 0, 'updated_at': 'not an integer'},
      ]) {
        await db.update('notes', values, where: 'id=?', whereArgs: [id]);
        await expectLater(check(), throwsFormatException);
      }
    },
  );

  test(
    'changed resource hash is preserved as disabled instead of re-approved',
    () async {
      final owner = await note(type: 'html');
      final node = await drive();
      await bind(owner, node, 'f' * 64);
      final result = await check();
      expect(result.disabledHtmlBindings, 1);
      expect(
        (await db.query('html_preview_resources')).single['approved_hash'],
        'f' * 64,
      );
    },
  );

  test(
    'removed drive node keeps revoked approval when its sequence is retained',
    () async {
      final owner = await note(type: 'html');
      final node = await drive();
      await bind(owner, node, sha256.convert([0, 255, 1]).toString());
      await db.delete(
        'local_drive_nodes',
        where: 'node_id=?',
        whereArgs: [node],
      );
      payloads.clear();
      expect((await check()).disabledHtmlBindings, 1);
      await db.update(
        'sqlite_sequence',
        {'seq': 0},
        where: 'name=?',
        whereArgs: ['local_drive_nodes'],
      );
      await expectLater(check(), throwsFormatException);
    },
  );

  test(
    'a historical creation receipt prevents deleted note ID reuse',
    () async {
      final owner = await note();
      await db.insert('html_creation_receipts', {
        'creation_key': 'c' * 32,
        'note_id': owner,
        'collection': 'note',
        'input_hash': 'd' * 64,
        'created_at': 1,
      });
      await db.delete('notes', where: 'id=?', whereArgs: [owner]);
      expect((await check()).needsAdditionalReview, isFalse);
      await db.update(
        'sqlite_sequence',
        {'seq': 0},
        where: 'name=?',
        whereArgs: ['notes'],
      );
      await expectLater(check(), throwsFormatException);
    },
  );

  test('binding without its original HTML owner is rejected', () async {
    await bind(999, 1, 'f' * 64);
    await db.insert('local_drive_nodes', {
      'node_id': 1,
      'path': 'folder',
      'parent_path': '',
      'name': 'folder',
      'directory': 1,
      'mime_type': 'inode/directory',
      'create_time': '2026-11-08',
      'modify_time': '2026-11-08',
    });
    await expectLater(check(), throwsFormatException);
  });

  test(
    'active image missing its bytes fails; completed quarantine cleanup may be pending',
    () async {
      final id = 'e' * 32;
      final image = await db.insert('local_images', {
        'attachment_id': id,
        'file_name': 'image.png',
        'mime_type': 'image/png',
        'file_hash': sha256.convert([1, 2, 3]).toString(),
        'file_size': 3,
        'modify_time': '2026-11-08',
      });
      await expectLater(check(), throwsFormatException);
      await db.update(
        'local_images',
        {
          'deleted': 1,
          'file_present': 0,
          'quarantine_name': '.image-delete-$id-${'f' * 32}',
        },
        where: 'image_id=?',
        whereArgs: [image],
      );
      expect((await check()).pendingImageCleanup, 1);
    },
  );

  test(
    'structured metadata bound rejects oversize without changing original',
    () async {
      final labels = jsonEncode([
        'x' * (LocalBackupContentVerifier.maxStructuredBytes + 1),
      ]);
      await note(labels: labels);
      await expectLater(check(), throwsFormatException);
      expect((await db.query('notes')).single['labels'], labels);
    },
  );
}

String driveParentForTest(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
