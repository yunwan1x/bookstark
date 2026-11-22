import 'support/frozen_schema14_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_store.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space, attachments, blobs, work;
  late LocalStore store;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('backup-export-');
    attachments = Directory('${space.path}/attachments');
    blobs = Directory('${space.path}/drive-blobs');
    work = Directory('${space.path}/work');
    await attachments.create();
    await blobs.create();
    store = FrozenSchema14Store(
      path: '${space.path}/source.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
  });
  tearDown(() async {
    await store.close();
    await space.delete(recursive: true);
  });
  LocalBackupExporter exporter({Future<void> Function()? preflight}) =>
      LocalBackupExporter(
        store: store,
        attachments: attachments,
        driveBlobs: blobs,
        workspace: work,
        checkPendingRecovery: preflight ?? () async {},
        clock: () => DateTime.utc(2026, 11, 8),
      );
  Future<Map<String, Uint8List>> contents(
    CompletedLocalBackup completed,
  ) async {
    final files = <String, Uint8List>{};
    await LocalBackupCodec.decode(completed.file.openRead(), (
      entry,
      stream,
    ) async {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      files[entry.path] = builder.takeBytes();
    });
    return files;
  }

  test(
    'actual WAL snapshot retains all rows and exact attachments/quarantine bytes',
    () async {
      final db = await store.database;
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await store.createNote('完整😀', '\uFEFF# 中文\r\n正文', labels: ['资料']);
      await db.insert('html_creation_receipts', {
        'creation_key': 'a' * 32,
        'note_id': 1,
        'collection': 'note',
        'input_hash': 'b' * 64,
        'created_at': 1,
      });
      final imageKey = 'c' * 32;
      final quarantine = '.image-delete-${'d' * 32}-${'e' * 32}';
      await File(
        '${attachments.path}/$imageKey',
      ).writeAsBytes(utf8.encode('原始附件😀'));
      await File(
        '${attachments.path}/$quarantine',
      ).writeAsBytes([0, 255, 1, 2]);
      await File('${blobs.path}/${'f' * 32}.blob').writeAsBytes([9, 8, 7, 0]);
      final html = await db.insert('notes', {
        'title': 'HTML资源绑定',
        'content': '<img src="assets/owned.bin">',
        'updated_at': 1,
        'editor_type': 'html',
      });
      final deleted = await store.createNote('已删除原文', '不丢失');
      await store.deleteNote(deleted);
      final driveHash = sha256.convert([9, 8, 7, 0]).toString();
      final node = await db.insert('local_drive_nodes', {
        'path': 'owned.bin',
        'parent_path': '',
        'name': 'owned.bin',
        'directory': 0,
        'file_size': 4,
        'file_hash': driveHash,
        'mime_type': 'application/octet-stream',
        'blob_key': '${'f' * 32}.blob',
        'create_time': '2026-11-08',
        'modify_time': '2026-11-08',
      });
      await db.insert('html_preview_resources', {
        'note_id': html,
        'resource_path': 'assets/owned.bin',
        'node_id': node,
        'approved_hash': driveHash,
      });
      final before = await db.query('notes');
      final completed = await exporter().create();
      try {
        expect(
          completed.manifest.sqliteVersion,
          (await db.rawQuery('SELECT sqlite_version() AS v')).single['v'],
        );
        expect(
          completed.sha256,
          (await sha256.bind(completed.file.openRead()).first).toString(),
        );
        expect(completed.size, await completed.file.length());
        final files = await contents(completed);
        expect(files['attachments/$imageKey'], utf8.encode('原始附件😀'));
        expect(files['attachments/$quarantine'], [0, 255, 1, 2]);
        expect(files['drive-blobs/${'f' * 32}.blob'], [9, 8, 7, 0]);
        final restored = File('${space.path}/readback.db');
        await restored.writeAsBytes(files['database/content.db']!);
        final read = await databaseFactoryFfiNoIsolate.openDatabase(
          restored.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await read.query('notes'), before);
          expect(
            await read.query('html_creation_receipts'),
            await db.query('html_creation_receipts'),
          );
          expect(
            await read.query('sqlite_sequence'),
            await db.query('sqlite_sequence'),
          );
          for (final table in completed.manifest.tables.keys) {
            expect(
              await read.query(table, orderBy: 'rowid'),
              await db.query(table, orderBy: 'rowid'),
              reason: table,
            );
          }
        } finally {
          await read.close();
        }
        expect(await db.query('notes'), before);
      } finally {
        await completed.dispose();
      }
      expect(await work.list().toList(), isEmpty);
      expect(await File('${attachments.path}/$imageKey').exists(), isTrue);
    },
  );

  test(
    'new writers wait through the complete backup and remain in current data',
    () async {
      await store.createNote('before', 'kept');
      final entered = Completer<void>(), release = Completer<void>();
      final creating = exporter(
        preflight: () async {
          entered.complete();
          await release.future;
        },
      ).create();
      await entered.future;
      var written = false;
      final write = store
          .createNote('after', 'new')
          .then((_) => written = true);
      await Future<void>.value();
      expect(written, isFalse);
      release.complete();
      final completed = await creating;
      await write;
      try {
        expect(completed.manifest.tables['notes'], 1);
        expect(await store.notes(), hasLength(2));
        final files = await contents(completed);
        final restored = File('${space.path}/readback.db');
        await restored.writeAsBytes(files['database/content.db']!);
        final read = await databaseFactoryFfiNoIsolate.openDatabase(
          restored.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect((await read.query('notes')).single['title'], 'before');
        } finally {
          await read.close();
        }
      } finally {
        await completed.dispose();
      }
    },
  );

  test(
    'pending recovery blocks before a backup task or snapshot is created',
    () async {
      await store.createNote('unchanged', 'body');
      await expectLater(
        exporter(
          preflight: () async {
            throw StateError('Owned pending local draft');
          },
        ).create(),
        throwsStateError,
      );
      expect(await work.exists(), isFalse);
      expect((await store.notes()).single['title'], 'unchanged');
      expect(store.maintenance.maintenanceRequested, isFalse);
    },
  );

  test(
    'symlink or nested directory is rejected without reading outside bytes',
    () async {
      final outside = File('${space.path}/outside');
      await outside.writeAsString('owned outside sentinel');
      final link = Link('${attachments.path}/${'a' * 32}');
      await link.create(outside.path);
      await expectLater(exporter().create(), throwsFormatException);
      expect(await outside.readAsString(), 'owned outside sentinel');
      expect(await work.list().toList(), isEmpty);
      await link.delete();
      await Directory('${attachments.path}/nested').create();
      await expectLater(exporter().create(), throwsFormatException);
      expect(await Directory('${attachments.path}/nested').exists(), isTrue);
    },
  );

  test(
    'oversized sparse source fails before hashing and keeps all originals',
    () async {
      final oversized = File('${blobs.path}/${'b' * 32}.blob');
      final handle = await oversized.open(mode: FileMode.write);
      try {
        await handle.truncate(LocalBackupManifest.maxFileBytes + 1);
      } finally {
        await handle.close();
      }
      await expectLater(exporter().create(), throwsFormatException);
      expect(await oversized.length(), LocalBackupManifest.maxFileBytes + 1);
      expect(await work.list().toList(), isEmpty);
    },
  );
  test(
    'future16 export declares exact schema and preserves historical creation receipt',
    () async {
      await (await store.database).transaction(extendSchema14ForAssistant16);
      final input = LocalAssistantCreationInput.note(
        const Note(title: 'Historical', content: 'Exact'),
      );
      final service = LocalAssistantCreationReceipts(store);
      final receipt = await service.create(
        'a' * 32,
        input,
        preparedHash: input.digest,
      );
      await (await store.database).delete(
        'notes',
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      final completed = await exporter().create();
      try {
        expect(completed.manifest.databaseSchema, 16);
        expect(completed.manifest.toJson()['version'], 2);
        expect(completed.manifest.tables['assistant_creation_receipts'], 1);
        expect(completed.manifest.tables['notes'], 0);
        final files = await contents(completed);
        expect(files.containsKey('database/content.db'), true);
      } finally {
        await completed.dispose();
      }
      expect(await work.list().toList(), isEmpty);
    },
  );
}
