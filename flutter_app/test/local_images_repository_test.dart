import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';

Uint8List svg() => Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="blue"/></svg>',
  ),
);
void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory directory;
  late LocalStore store;
  late LocalAttachments media;
  late LocalImagesRepository repo;
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    directory = await base.createTemp('images-');
    store = LocalStore(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    media = LocalAttachments(Directory('${directory.path}/attachments'));
    repo = LocalImagesRepository(
      store,
      media,
      clock: () => DateTime(2026, 11, 4, 10, 20),
    );
  });
  tearDown(() async {
    repo.dispose();
    media.close();
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'legacy attachment discovery recovers actual URI filename, keeps unknown time/category and stable ID',
    () async {
      final source = File('${directory.path}/路径[阅读].svg');
      await source.writeAsBytes(svg());
      final attached = await media.add(XFile(source.path));
      await store.createNote(
        '真实笔记',
        markdownAttachment('只是说明文字', attached.uri, image: true),
      );
      final result = await repo.list(const ImagesQuery());
      final item = result.items.single;
      expect(item.name, '路径[阅读].svg');
      expect(item.category, isEmpty);
      expect(item.createdOn, isEmpty);
      expect(item.mime, 'image/svg+xml');
      expect(item.knownDimensions, isFalse);
      expect(result.totalImageBytes, svg().length);
      expect(await repo.bytes(item.uri), svg());
      await store.close();
      expect((await repo.list(const ImagesQuery())).items.single.id, item.id);
    },
  );
  test(
    'local upload deduplicates real bytes without changing original category or name',
    () async {
      final one = ImageUploadPayload.fromBytes(
        name: '原始.svg',
        bytes: svg(),
        category: ImageCategory.note,
      );
      final first = await repo.upload(one);
      final second = await repo.upload(
        ImageUploadPayload.fromBytes(
          name: '另一个名字.svg',
          bytes: svg(),
          category: ImageCategory.drawing,
        ),
      );
      expect(second.id, first.id);
      expect(second.name, '原始.svg');
      final page = await repo.list(const ImagesQuery());
      expect(page.total, 1);
      expect(page.items.single.category, 'note');
      expect(repo.publicLinks, isFalse);
      expect(await repo.bytes(first.uri), svg());
      await expectLater(
        repo.bytes(first.uri, maxBytes: 8),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'failed database deletion restores renamed file and successful retry cannot resurrect it',
    () async {
      final uploaded = await repo.upload(
        ImageUploadPayload.fromBytes(
          name: '保留.svg',
          bytes: svg(),
          category: ImageCategory.editor,
        ),
      );
      final item = (await repo.list(const ImagesQuery())).items.single;
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER reject_delete BEFORE UPDATE OF deleted ON local_images WHEN NEW.deleted=1 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      await expectLater(repo.remove(item), throwsA(isA<DatabaseException>()));
      expect(await repo.bytes(uploaded.uri), svg());
      expect((await repo.list(const ImagesQuery())).total, 1);
      await db.execute('DROP TRIGGER reject_delete');
      final removed = await repo.remove(item);
      expect(removed.recordRemoved, isTrue);
      expect(removed.linkAvailable, isFalse);
      expect((await repo.list(const ImagesQuery())).items, isEmpty);
      expect((await repo.list(const ImagesQuery())).items, isEmpty);
      await expectLater(repo.bytes(item.uri), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'post-commit cleanup failure is retained and can be retried without reviving the URI',
    () async {
      var fail = true;
      repo.dispose();
      repo = LocalImagesRepository(
        store,
        media,
        cleanupFile: (file) async {
          if (fail) {
            throw FileSystemException('fixture cleanup failure', file.path);
          }
          await file.delete();
        },
      );
      await repo.upload(
        ImageUploadPayload.fromBytes(
          name: '清理.svg',
          bytes: svg(),
          category: ImageCategory.editor,
        ),
      );
      final item = (await repo.list(const ImagesQuery())).items.single;
      final result = await repo.remove(item);
      expect(result.recordRemoved, isTrue);
      expect(result.cleanupPending, isTrue);
      expect(result.linkAvailable, isFalse);
      expect((await repo.list(const ImagesQuery())).items, isEmpty);
      final remaining = await media.directory.list().toList();
      expect(remaining.length, 1);
      expect(
        remaining.single.uri.pathSegments.last,
        startsWith('.image-delete-'),
      );
      fail = false;
      repo.dispose();
      await store.close();
      repo = LocalImagesRepository(store, media);
      expect((await repo.pendingCleanup()).single.id, item.id);
      expect((await repo.remove(item)).cleanupPending, isFalse);
      expect(await repo.pendingCleanup(), isEmpty);
      expect(await media.directory.list().toList(), isEmpty);
    },
  );
  test(
    'symbolic links and non-image files never enter image list or escape the attachment root',
    () async {
      await media.directory.create(recursive: true);
      final outside = File('${directory.path}/outside.svg');
      await outside.writeAsBytes(svg());
      const id = '0123456789abcdef0123456789abcdef';
      await Link('${media.directory.path}/$id').create(outside.path);
      await File(
        '${media.directory.path}/fedcba9876543210fedcba9876543210',
      ).writeAsString('not an image');
      expect((await repo.list(const ImagesQuery())).items, isEmpty);
      await expectLater(
        repo.bytes(Uri.parse('bookstark-attachment:///$id/outside.svg')),
        throwsA(isA<ApiFailure>()),
      );
      expect(await outside.readAsBytes(), svg());
    },
  );
  test(
    'actual version nine database upgrade preserves previous notes, labels and topics',
    () async {
      final note = await store.createNote('保留笔记', '# 正文', labels: ['保留标签']);
      final db = await store.database;
      await db.insert('local_labels', {'label_name': '保留标签'});
      await db.insert('topics', {
        'title': '保留主题',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      await db.execute('DROP TABLE local_images');
      await db.execute('DROP TABLE local_drive_nodes');
      // Reconstruct the actual older schema, not only its version number.
      await db.execute('DROP TRIGGER html_preview_resources_note_delete');
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute('DROP TABLE html_creation_receipts');
      await db.execute('ALTER TABLE notes DROP COLUMN editor_type');
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.setVersion(9);
      await store.close();
      final reopened = await store.database;
      expect(await reopened.getVersion(), 16);
      expect(
        (await reopened.query(
          'notes',
          where: 'id = ?',
          whereArgs: [note],
        )).single['content'],
        '# 正文',
      );
      expect(
        (await reopened.query('local_labels')).single['label_name'],
        '保留标签',
      );
      expect((await reopened.query('topics')).single['title'], '保留主题');
      expect(await reopened.query('local_images'), isEmpty);
    },
  );
}
