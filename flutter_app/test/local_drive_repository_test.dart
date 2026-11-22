import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/drive_models.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space, blobs;
  late LocalStore store;
  late LocalDriveRepository repo;
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    space = await base.createTemp('drive-');
    blobs = Directory('${space.path}/drive-blobs');
    store = LocalStore(
      path: '${space.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalDriveRepository(store, blobs);
  });
  tearDown(() async {
    repo.dispose();
    await store.close();
    await space.delete(recursive: true);
  });
  Future<DriveNode> upload(String target, String text) async {
    final file = File('${space.path}/source.txt');
    await file.writeAsString(text, flush: true);
    final snapshot = await DriveSourceSnapshot.prepare(
      XFile(file.path),
      maxBytes: 1024 * 1024,
    );
    return (await repo.upload(snapshot, target: target)).node;
  }

  test(
    'actual files survive reopen, preserve BOM and stable IDs across emoji tree moves',
    () async {
      final folder = await repo.mkdir('', '📚资料%');
      final original = await upload('📚资料%/a.md', '\ufefffirst\r\nsecond');
      final document = await repo.readText(original);
      expect(document.hasBom, isTrue);
      expect(document.content, 'first\r\nsecond');
      await repo.rename(folder, '新目录');
      final moved = (await repo.list('新目录')).single;
      expect(moved.id, original.id);
      expect(moved.path, '新目录/a.md');
      await repo.copy(moved, 'copy.md');
      final copy = (await repo.lookup('copy.md'))!;
      expect(copy.id, isNot(original.id));
      final usage = (await repo.profile()).usage;
      expect(usage.storedBytes, original.size);
      expect(usage.logicalBytes, original.size * 2);
      repo.dispose();
      await store.close();
      store = LocalStore(
        path: '${space.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      repo = LocalDriveRepository(store, blobs);
      expect(
        (await repo.readText((await repo.lookup('新目录/a.md'))!)).content,
        'first\r\nsecond',
      );
      await repo.remove((await repo.lookup('新目录'))!);
      expect(await repo.lookup('新目录'), isNull);
      expect((await repo.readText(copy)).content, 'first\r\nsecond');
    },
  );
  test(
    'SQL failure after file publication preserves old content and removes unreferenced replacement',
    () async {
      final original = await upload('a.md', 'old');
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER fail_save BEFORE UPDATE ON local_drive_nodes BEGIN SELECT RAISE(ABORT,'injected failure'); END",
      );
      await expectLater(
        repo.saveText(await repo.readText(original), 'replacement'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.readText(original)).content, 'old');
      expect((await blobs.list().toList()).length, 1);
      await db.execute('DROP TRIGGER fail_save');
      final saved = await repo.saveText(await repo.readText(original), '');
      expect(saved.id, original.id);
      expect(saved.size, 0);
      expect(await repo.bytes(saved), isEmpty);
    },
  );
  test(
    'post-commit cleanup failure does not turn an acknowledged save into another write',
    () async {
      final original = await upload('a.md', 'old');
      repo.dispose();
      var fail = true;
      repo = LocalDriveRepository(
        store,
        blobs,
        deleteBlob: (file) async {
          if (fail) throw const FileSystemException('cleanup failure');
          await file.delete();
        },
      );
      final saved = await repo.saveText(await repo.readText(original), 'new');
      expect((await repo.readText(saved)).content, 'new');
      expect(repo.cleanupErrors, isNotEmpty);
      expect((await blobs.list().toList()).length, 2);
      fail = false;
      await repo.recoverCleanup();
      expect(repo.cleanupErrors, isEmpty);
      expect((await blobs.list().toList()).length, 1);
    },
  );
  test(
    'reopen recovers orphan files but never follows symbolic links or deletes unknown files',
    () async {
      await upload('a.md', 'actual');
      final orphan = File('${blobs.path}/${'a' * 32}.blob');
      await orphan.writeAsString('orphan');
      final temp = File('${blobs.path}/.tmp-${'b' * 32}');
      await temp.writeAsString('partial');
      final unknown = File('${blobs.path}/unrelated.txt');
      await unknown.writeAsString('keep');
      final outside = File('${space.path}/outside');
      await outside.writeAsString('private');
      final link = Link('${blobs.path}/${'c' * 32}.blob');
      await link.create(outside.path);
      repo.dispose();
      repo = LocalDriveRepository(store, blobs);
      await repo.list('');
      expect(await orphan.exists(), isFalse);
      expect(await temp.exists(), isFalse);
      expect(await unknown.readAsString(), 'keep');
      expect(await outside.readAsString(), 'private');
      expect(await link.exists(), isTrue);
      final node = (await repo.lookup('a.md'))!;
      final db = await store.database;
      final row = (await db.query(
        'local_drive_nodes',
        where: 'node_id=?',
        whereArgs: [node.id],
      )).single;
      final physical = File('${blobs.path}/${row['blob_key']}');
      await physical.delete();
      await Link(physical.path).create(outside.path);
      await expectLater(repo.bytes(node), throwsFormatException);
    },
  );
  test('native file range and stale If-Range use exact bytes', () async {
    final node = await upload('a.txt', '0123456789');
    var read = await repo.open(node, range: 'bytes=2-4');
    expect(read.status, 206);
    expect(utf8.decode(await read.stream.expand((v) => v).toList()), '234');
    read = await repo.open(node, range: 'bytes=-3');
    expect(utf8.decode(await read.stream.expand((v) => v).toList()), '789');
    read = await repo.open(node, range: 'bytes=2-4', ifRange: '"stale"');
    expect(read.status, 200);
    expect(
      utf8.decode(await read.stream.expand((v) => v).toList()),
      '0123456789',
    );
  });
  test(
    'actual version ten upgrade preserves notes and creates new drive tables',
    () async {
      final id = await store.createNote('保留', '# 旧内容');
      final db = await store.database;
      await db.execute('DROP TABLE local_drive_nodes');
      // Reconstruct the actual older schema, not only its version number.
      await db.execute('DROP TRIGGER html_preview_resources_note_delete');
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute('DROP TABLE html_creation_receipts');
      await db.execute('ALTER TABLE notes DROP COLUMN editor_type');
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.setVersion(10);
      await store.close();
      final upgraded = await store.database;
      expect(await upgraded.getVersion(), 16);
      expect(
        (await upgraded.query(
          'notes',
          where: 'id=?',
          whereArgs: [id],
        )).single['content'],
        '# 旧内容',
      );
      expect(await repo.list(''), isEmpty);
      final folder = await repo.mkdir('', '升级后目录');
      expect(folder.directory, isTrue);
    },
  );
  test(
    'an untrusted linked drive ancestor is still rejected before creating files',
    () async {
      final outside = Directory('${space.path}/outside');
      await outside.create();
      await Link('${space.path}/linked-parent').create(outside.path);
      final linked = LocalDriveRepository(
        store,
        Directory('${space.path}/linked-parent/blobs'),
      );
      await expectLater(linked.list(''), throwsFormatException);
      expect(await Directory('${outside.path}/blobs').exists(), isFalse);
      linked.dispose();
    },
  );
}
