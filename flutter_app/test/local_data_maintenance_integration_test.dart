import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';
import 'package:bookstark_flutter/core/images_repository.dart';

class _PausedAttachment extends XFile {
  _PausedAttachment(this.started, this.release) : super('owned-paused.txt');
  final Completer<void> started, release;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.fromList([65, 66]);
    started.complete();
    await release.future;
    yield Uint8List.fromList([67, 68]);
  }
}

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
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('maintenance-');
    store = LocalStore(
      path: '${space.path}/content.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
  });
  tearDown(() async {
    await store.close();
    await space.delete(recursive: true);
  });

  test(
    'same database instances wait until backup releases its snapshot',
    () async {
      final second = LocalStore(
        path: '${space.path}/./content.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      expect(identical(second.maintenance, store.maintenance), isTrue);
      final began = Completer<void>(), release = Completer<void>();
      final backup = store.maintenance.exclusive(() async {
        began.complete();
        await release.future;
        expect(await store.notes(), isEmpty);
      });
      await began.future;
      var written = false;
      final write = second.createNote('after snapshot', '完整正文').then((_) {
        written = true;
      });
      await Future<void>.value();
      expect(written, isFalse);
      release.complete();
      await Future.wait([backup, write]);
      expect((await store.notes()).single['content'], '完整正文');
      // Both instances intentionally share sqflite's one database connection.
      await second.close();
    },
  );

  test(
    'backup waits for the complete attachment stream, not its first chunk',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final attachments = LocalAttachments(
        Directory('${space.path}/attachments'),
        maintenance: store.maintenance,
      );
      final writing = attachments.add(_PausedAttachment(entered, release));
      await entered.future;
      var inspected = false;
      final backup = store.maintenance.exclusive(() async {
        final files = await attachments.directory.list().toList();
        expect(files, hasLength(1));
        expect(await File(files.single.path).readAsBytes(), [65, 66, 67, 68]);
        inspected = true;
      });
      await Future<void>.value();
      expect(inspected, isFalse);
      release.complete();
      await Future.wait([writing, backup]);
      expect(inspected, isTrue);
    },
  );

  test(
    'published image and its SQL metadata enter the same snapshot',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final attachments = LocalAttachments(
        Directory('${space.path}/attachments'),
        maintenance: store.maintenance,
      );
      final repo = LocalImagesRepository(
        store,
        attachments,
        dimensionsReader: (_) async {
          entered.complete();
          await release.future;
          return (1, 1);
        },
      );
      final bytes = Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        1,
        2,
        3,
      ]);
      final upload = repo.upload(
        ImageUploadPayload.fromBytes(
          name: 'fixture.png',
          bytes: bytes,
          category: ImageCategory.editor,
        ),
      );
      await entered.future; // File has been renamed; SQL insert has not run.
      var inspected = false;
      final backup = store.maintenance.exclusive(() async {
        final rows = await (await store.database).query('local_images');
        expect(rows, hasLength(1));
        final file = File(
          '${attachments.directory.path}/${rows.single['attachment_id']}',
        );
        expect(await file.readAsBytes(), bytes);
        expect(rows.single['width'], 1);
        inspected = true;
      });
      await Future<void>.value();
      expect(inspected, isFalse);
      release.complete();
      await Future.wait([upload, backup]);
      expect(inspected, isTrue);
      repo.dispose();
    },
  );

  test(
    'drive orphan cleanup finishes before maintenance inspects files',
    () async {
      final blobs = Directory('${space.path}/drive-blobs');
      await blobs.create();
      final orphan = File('${blobs.path}/${'a' * 32}.blob');
      await orphan.writeAsString('unreferenced owned bytes');
      final entered = Completer<void>(), release = Completer<void>();
      final repo = LocalDriveRepository(
        store,
        blobs,
        deleteBlob: (file) async {
          entered.complete();
          await release.future;
          await file.delete();
        },
      );
      final cleanup = repo.recoverCleanup();
      await entered.future;
      var inspected = false;
      final backup = store.maintenance.exclusive(() async {
        expect(await blobs.list().toList(), isEmpty);
        expect(
          await (await store.database).query('local_drive_nodes'),
          isEmpty,
        );
        inspected = true;
      });
      await Future<void>.value();
      expect(inspected, isFalse);
      release.complete();
      await Future.wait([cleanup, backup]);
      expect(inspected, isTrue);
      repo.dispose();
    },
  );
  test(
    'collection lookup waits for exclusive maintenance before reading',
    () async {
      final id = await store.createNote('文章', '原文', collection: 'article');
      final entered = Completer<void>(), release = Completer<void>();
      final backup = store.maintenance.exclusive(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      String? collection;
      final reading = store
          .noteCollectionOf(id)
          .then((value) => collection = value);
      await Future<void>.value();
      expect(collection, isNull);
      release.complete();
      await Future.wait([backup, reading]);
      expect(collection, 'article');
      await store.deleteNote(id, collection: 'article');
      await expectLater(store.noteCollectionOf(id), throwsStateError);
    },
  );
}
