import 'support/frozen_schema14_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space, support, cache, inbox;
  late LocalStore source, old;
  late File input, originalAttachment;
  late List<String> discarded;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await root.create(recursive: true);
    space = await root.createTemp('backup-import-');
    support = Directory('${space.path}/files');
    await support.create();
    cache = Directory('${space.path}/cache');
    await cache.create();
    inbox = Directory('${cache.path}/local-backup-inbox-v1');
    await inbox.create();
    source = FrozenSchema14Store(
      path: '${space.path}/source.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    old = FrozenSchema14Store(
      path: '${space.path}/old.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await source.createNote(
      'incoming😀',
      '\uFEFFexact\r\nsource',
      labels: [' literal,label '],
    );
    await old.createNote('original', 'must remain untouched');
    final originalDir = Directory('${support.path}/attachments');
    await originalDir.create();
    originalAttachment = File('${originalDir.path}/${'9' * 32}');
    await originalAttachment.writeAsString('original attachment');
    discarded = [];
  });
  tearDown(() async {
    await source.close();
    await old.close();
    await space.delete(recursive: true);
  });
  Future<void> makeInput({bool large = false}) async {
    final attachments = Directory('${space.path}/source-attachments');
    await attachments.create();
    if (large) {
      final file = await File(
        '${attachments.path}/${'1' * 32}',
      ).open(mode: FileMode.write);
      try {
        await file.truncate(9 * 1024 * 1024);
      } finally {
        await file.close();
      }
    }
    final backup = await LocalBackupExporter(
      store: source,
      attachments: attachments,
      driveBlobs: Directory('${space.path}/source-blobs'),
      workspace: Directory('${cache.path}/source-export'),
      checkPendingRecovery: () async {},
    ).create();
    input = File('${inbox.path}/${'c' * 32}.bsbackup');
    await backup.file.copy(input.path);
    await backup.dispose();
  }

  LocalBackupCandidateImporter importer({Future<int> Function()? spaceCheck}) =>
      LocalBackupCandidateImporter(
        privateSupport: support,
        privateCache: cache,
        factory: databaseFactoryFfiNoIsolate,
        identity: () => 'd' * 32,
        availableBytes: spaceCheck ?? () async => 4 * 1024 * 1024 * 1024,
        discardCandidate: (id) async {
          discarded.add(id);
          await Directory(
            '${support.path}/local-data-v1/generations/$id',
          ).delete(recursive: true);
        },
      );
  Future<void> oldUntouched() async {
    expect((await old.notes()).single['content'], 'must remain untouched');
    expect(await originalAttachment.readAsString(), 'original attachment');
    expect(
      await File('${support.path}/local-data-v1/pointer.json').exists(),
      isFalse,
    );
  }

  Future<List<FileSystemEntity>> generations() async {
    final dir = Directory('${support.path}/local-data-v1/generations');
    return await dir.exists() ? await dir.list().toList() : [];
  }

  test(
    'fully checked new working copy never overwrites current data or input',
    () async {
      await makeInput();
      final before = await sha256.bind(input.openRead()).first;
      final candidate = await importer().inspectPicked('c' * 32);
      expect(candidate.id, 'd' * 32);
      expect(candidate.id, isNot(candidate.manifest.id));
      expect(candidate.sourceSHA256, before.toString());
      expect(candidate.manifest.tables['notes'], 1);
      final read = await databaseFactoryFfiNoIsolate.openDatabase(
        candidate.layout.databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        final original =
            (await (await source.database).rawQuery(
                  'SELECT CAST(content AS BLOB) AS bytes FROM notes',
                )).single['bytes']
                as List<int>;
        final copied =
            (await read.rawQuery(
                  'SELECT CAST(content AS BLOB) AS bytes FROM notes',
                )).single['bytes']
                as List<int>;
        expect(original.take(3).toList(), [239, 187, 191]);
        expect(copied, original);
      } finally {
        await read.close();
      }
      await oldUntouched();
      expect(await sha256.bind(input.openRead()).first, before);
      await candidate.discardUnprepared();
      expect(discarded, ['d' * 32]);
      expect(await generations(), isEmpty);
      await oldUntouched();
    },
  );

  test(
    'candidate becomes retained before any native activation submission',
    () async {
      await makeInput();
      final candidate = await importer().inspectPicked('c' * 32);
      candidate.preserveForActivation();
      await expectLater(candidate.discardUnprepared(), throwsStateError);
      expect(discarded, isEmpty);
      expect(await generations(), hasLength(1));
      await oldUntouched();
    },
  );

  test(
    'corrupt payload fails and removes only this unpublished new directory',
    () async {
      await makeInput();
      final wire = await input.readAsBytes();
      wire[wire.length - 1] ^= 1;
      await input.writeAsBytes(wire, flush: true);
      final before = await sha256.bind(input.openRead()).first;
      await expectLater(
        importer().inspectPicked('c' * 32),
        throwsFormatException,
      );
      expect(await generations(), isEmpty);
      expect(await sha256.bind(input.openRead()).first, before);
      await oldUntouched();
    },
  );

  test(
    'a colliding private generation is retained rather than reused or deleted',
    () async {
      await makeInput();
      final existing = Directory(
        '${support.path}/local-data-v1/generations/${'d' * 32}',
      );
      await existing.create(recursive: true);
      final sentinel = File('${existing.path}/owned-sentinel');
      await sentinel.writeAsString('keep');
      await expectLater(importer().inspectPicked('c' * 32), throwsStateError);
      expect(await sentinel.readAsString(), 'keep');
      await oldUntouched();
    },
  );

  test(
    'insufficient space and early cancellation create no candidate',
    () async {
      await makeInput();
      await expectLater(
        importer(spaceCheck: () async => 0).inspectPicked('c' * 32),
        throwsA(isA<LocalBackupSpaceUnavailable>()),
      );
      final cancel = AttachmentCancellation()..cancel();
      await expectLater(
        importer().inspectPicked('c' * 32, cancellation: cancel),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(await generations(), isEmpty);
      await oldUntouched();
    },
  );

  test(
    'space loss during streamed extraction keeps input and active data',
    () async {
      await makeInput(large: true);
      var checks = 0;
      final before = await sha256.bind(input.openRead()).first;
      await expectLater(
        importer(
          spaceCheck: () async => ++checks == 1 ? 4 * 1024 * 1024 * 1024 : 0,
        ).inspectPicked('c' * 32),
        throwsA(isA<LocalBackupSpaceUnavailable>()),
      );
      expect(checks, 2);
      expect(await generations(), isEmpty);
      expect(await sha256.bind(input.openRead()).first, before);
      await oldUntouched();
    },
  );

  test(
    'linked inbox and path-like identifiers cannot become input paths',
    () async {
      await makeInput();
      await expectLater(
        importer().inspectPicked('../outside'),
        throwsFormatException,
      );
      final moved = await inbox.rename('${space.path}/inbox-elsewhere');
      await Link(inbox.path).create(moved.path);
      await expectLater(
        importer().inspectPicked('c' * 32),
        throwsFormatException,
      );
      expect(await generations(), isEmpty);
      await oldUntouched();
    },
  );
  test(
    'a hash-valid SQLite archive with invalid domain flags never becomes ready',
    () async {
      await makeInput();
      final original = await LocalBackupCodec.decode(input.openRead(), (
        _,
        body,
      ) async {
        await body.drain<void>();
      });
      await (await source.database).update('notes', {'deleted': 2});
      final snapshot = File('${space.path}/untrusted-snapshot.db');
      await (await source.database).execute('VACUUM INTO ?', [snapshot.path]);
      final manifest = LocalBackupManifest(
        id: original.id,
        createdAt: original.createdAt,
        sqliteVersion: original.sqliteVersion,
        tables: original.tables,
        files: [
          LocalBackupFile(
            path: 'database/content.db',
            bytes: await snapshot.length(),
            sha256: (await sha256.bind(snapshot.openRead()).first).toString(),
          ),
        ],
      );
      final sink = input.openWrite();
      try {
        await sink.addStream(
          LocalBackupCodec.encode(manifest, (_) => snapshot.openRead()),
        );
      } finally {
        await sink.close();
      }
      await expectLater(
        importer().inspectPicked('c' * 32),
        throwsFormatException,
      );
      expect(await generations(), isEmpty);
      await oldUntouched();
    },
  );
  test(
    'future16 import verifies receipts without opening or publishing the active store',
    () async {
      await (await source.database).transaction(extendSchema14ForAssistant16);
      final actual = LocalAssistantCreationInput.note(
        const Note(title: 'Receipt', content: 'Keep exact'),
      );
      final saved = await LocalAssistantCreationReceipts(
        source,
      ).create('a' * 32, actual, preparedHash: actual.digest);
      await (await source.database).delete(
        'notes',
        where: 'id=?',
        whereArgs: [saved.resourceId],
      );
      await makeInput();
      final candidate = await importer().inspectPicked('c' * 32);
      expect(candidate.manifest.databaseSchema, 16);
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        candidate.layout.databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          16,
        );
        expect(
          (await db.query('assistant_creation_receipts')).single['resource_id'],
          saved.resourceId,
        );
        expect(
          (await db.query(
            'sqlite_sequence',
            where: 'name=?',
            whereArgs: ['notes'],
          )).single['seq'],
          saved.resourceId,
        );
      } finally {
        await db.close();
      }
      await oldUntouched();
      await candidate.discardUnprepared();
      expect(await generations(), isEmpty);
    },
  );
}
