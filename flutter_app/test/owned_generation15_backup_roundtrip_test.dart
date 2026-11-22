import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_backup_content.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_backup_schema.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_upload_copy.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-backup-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final factory = databaseFactoryFfiNoIsolate;
  late Directory root, workspace;
  late LocalDataPaths paths;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  late OwnedWritableGeneration15 owner;
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-backup-');
    workspace = await Directory('${root.path}/verify').create();
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 1,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    pointerRaw = pointer.encode();
    paths = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: root,
    );
    await File(paths.databasePath).parent.create(recursive: true);
    await paths.driveBlobs.create();
    final fixture = File(
      'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
    );
    final stage = await LegacyZipStage.inspect(
      fixture,
      privateParent: root,
      expectedSha256: (await sha256.bind(fixture.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(stage);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'd' * 32,
    );
    final selected = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    final records = LegacyImportRecords.fromExport(
      source,
      LegacyImportMapping.fromRecipe(
        source,
        selected.toJson(),
        scopeKey: 'd' * 32,
      ),
    );
    final uploads = LegacyCandidateUploads.fromRecords(records, stage);
    final copied = await copyLegacyCandidateUploads(
      uploads,
      privateParent: await Directory('${root.path}/upload-copies').create(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final db = await factory.openDatabase(
      paths.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, _) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.transaction((tx) async {
      await writeLegacyCandidateMetadata(
        tx,
        records,
        importedAt: DateTime.utc(2026, 11, 11),
      );
      await writeLegacyCandidatePrimaryRows(
        tx,
        LegacyCandidateRows.fromRecords(records),
      );
      await writeLegacyCandidateUploads(tx, uploads, copied);
    });
    // Exercise exact stored state after a legitimate owned edit. Backups do
    // not reinterpret historical payload fields as current edited content.
    await db.rawUpdate(
      "UPDATE notes SET content=?,legacy_version=?,visibility=3,pin_order=-7 "
      "WHERE editor_type='markdown'",
      ['\ufeff# Edited\r\n', 9223372036854775807],
    );
    // Hidden rowid gaps are legal stored provenance. VACUUM would silently
    // renumber these composite-primary-key rows, so require physical snapshot.
    await db.rawUpdate('UPDATE legacy_import_records SET rowid=rowid+10000');
    await db.close();
    await copied.directory.rename(paths.attachments.path);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('Backup must not unlock or transform content');
    });
    owner = await OwnedWritableGeneration15.openActive(
      privateSupport: root,
      workspace: workspace,
      expectedPointer: pointer,
      isCurrentScope: () => true,
      factory: factory,
      crypto: NativeLocalContentCrypto(channel: channel),
      control: NativeLocalDataControl(
        invoke: (name, args) async {
          if (name != 'readState') throw StateError('No activation in export');
          return {
            'format': 1,
            'pointerRaw': pointerRaw,
            'intentRaw': null,
            'currentRetentionRaw': null,
            'sourceRetentionRaw': null,
            'metadataOnly': true,
          };
        },
      ),
    );
  });
  tearDown(() async {
    await owner.retire();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  OwnedGeneration15BackupExporter exporter({
    Future<void> Function()? preflight,
  }) => OwnedGeneration15BackupExporter(
    owner: owner,
    factory: factory,
    workspace: Directory('${root.path}/exports'),
    checkPendingRecovery: preflight ?? () async {},
    clock: () => DateTime.utc(2026, 11, 11),
  );

  test(
    'v3 schema15 genuine source export preserves every typed row and attachment byte',
    () async {
      await owner.exclusiveSnapshot((db) async {
        await db.rawInsert(
          "INSERT INTO notes(id,title,content,labels,updated_at) VALUES(4000000,'Historical raw note',?,'[]',1)",
          [
            Uint8List.fromList([0xff, 0, 0xef, 0xbb, 0xbf]),
          ],
        );
        await db.rawInsert(
          "INSERT INTO tasks(task_id,content,due_date,create_time,modify_time,complete_time) VALUES(6000000,'Historical NULL','','fixture','fixture',NULL)",
        );
      });
      final vector =
          (jsonDecode(
                        await File(
                          'tool/legacy_crypto_test/go-vectors.json',
                        ).readAsString(),
                      )
                      as List)
                  .first
              as Map<String, dynamic>;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'drain') return {'format': 1, 'drained': true};
        if (call.method == 'protectNew') {
          final args = call.arguments as Map;
          expect(args['password'], vector['password']);
          expect(
            args['body'],
            Uint8List.fromList(utf8.encode(vector['plain'] as String)),
          );
          return {
            'format': 1,
            'id': args['id'],
            'body': Uint8List.fromList(utf8.encode(vector['body'] as String)),
            'hash': vector['hash'],
          };
        }
        throw StateError('No backup unlock or undeclared crypto');
      });
      final creator = Owned15GenerationCreator(owner);
      try {
        final prepared = await creator.prepare(
          creationKey: '1' * 32,
          collection: 'note',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            vector['plain'] as String,
          ),
          title: 'Created protected note',
          labels: const [],
          password: vector['password'] as String,
        );
        final receipt = await creator.submit(
          prepared,
          beforeInsert: (_) async {},
        );
        expect(receipt.id, greaterThan(4000000));
      } finally {
        await creator.retire();
      }
      // Real receipt transaction, mock Native protocol via public Go vector;
      // not evidence that Native crypto or the system chooser ran.
      final before = await owner.exclusiveSnapshot(
        (db) => OwnedGeneration15SchemaGate().rowDigests(db),
      );
      final completed = await exporter().create();
      try {
        expect(completed.manifest.databaseSchema, 15);
        expect(completed.manifest.toJson()['version'], 3);
        final restore = await Directory('${root.path}/decoded').create();
        final received = <String, Uint8List>{};
        final decoded = await LocalBackupCodec.decode(
          completed.file.openRead(),
          (entry, stream) async {
            final target = File('${restore.path}/${entry.path}');
            await target.parent.create(recursive: true);
            final output = target.openWrite();
            try {
              await output.addStream(stream);
              await output.flush();
            } finally {
              await output.close();
            }
            received[entry.path] = await target.readAsBytes();
          },
        );
        expect(decoded.toJson(), completed.manifest.toJson());
        for (final pair in const [(1, 15), (2, 15), (3, 14), (3, 16)]) {
          final wrong = Map<String, Object?>.from(decoded.toJson())
            ..['version'] = pair.$1
            ..['schema'] = pair.$2;
          expect(
            () => LocalBackupManifest.fromJson(wrong),
            throwsFormatException,
          );
        }
        final snapshot = File('${restore.path}/database/content.db');
        final facts = await LocalBackupSchemaVerifier(
          factory: factory,
          workspace: Directory('${root.path}/restored-check'),
        ).verify(snapshot, expectedSchema: 15);
        await LocalBackupContentVerifier(
          factory,
        ).verify(snapshot, decoded, facts);
        final db = await factory.openDatabase(
          snapshot.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await OwnedGeneration15SchemaGate().rowDigests(db), before);
        } finally {
          await db.close();
        }
        await for (final entry in paths.attachments.list(followLinks: false)) {
          final file = File(entry.path);
          expect(
            received['attachments/${file.uri.pathSegments.last}'],
            await file.readAsBytes(),
          );
        }
        // Exercise the actual private-inbox importer as well as the framing
        // decoder. Import creates an independent candidate, never a writer.
        final importedSupport = await Directory(
          '${root.path}/imported-support',
        ).create();
        final cache = await Directory('${root.path}/cache').create();
        final inbox = await Directory(
          '${cache.path}/local-backup-inbox-v1',
        ).create();
        await completed.file.copy('${inbox.path}/${'f' * 32}.bsbackup');
        final candidate = await LocalBackupCandidateImporter(
          privateSupport: importedSupport,
          privateCache: cache,
          factory: factory,
          availableBytes: () async => 4 * 1024 * 1024 * 1024,
          identity: () => 'e' * 32,
          discardCandidate: (id) async {
            expect(id, 'e' * 32);
            await Directory(
              '${importedSupport.path}/local-data-v1/generations/$id',
            ).delete(recursive: true);
          },
        ).inspectPicked('f' * 32);
        try {
          expect(candidate.manifest.databaseSchema, 15);
          final imported = await factory.openDatabase(
            candidate.layout.databasePath,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
          try {
            expect(
              await OwnedGeneration15SchemaGate().rowDigests(imported),
              before,
            );
          } finally {
            await imported.close();
          }
          await for (final entry in paths.attachments.list(
            followLinks: false,
          )) {
            final file = File(entry.path);
            expect(
              await File(
                '${candidate.layout.attachments.path}/${file.uri.pathSegments.last}',
              ).readAsBytes(),
              await file.readAsBytes(),
            );
          }
        } finally {
          await candidate.discardUnprepared();
        }
        final after = await owner.exclusiveSnapshot(
          (db) => OwnedGeneration15SchemaGate().rowDigests(db),
        );
        expect(
          after,
          before,
          reason: 'Export cannot alter original data, NULL, IDs or sequence',
        );
      } finally {
        await completed.dispose();
      }
    },
  );
  test(
    'historical plaintext and opaque ciphertext retain exact original protection bytes',
    () async {
      final hash = r'$2b$04$' + ('A' * 53);
      final cipher =
          'ENC:v1:${base64.encode(Uint8List(16))}:${base64.encode(Uint8List(12))}:${base64.encode(Uint8List(16))}';
      await owner.exclusiveSnapshot((db) async {
        for (final value in [
          (7001, '\ufeff# Historical\r\n'),
          (7002, cipher),
        ]) {
          await db.insert('notes', {
            'id': value.$1,
            'title': 'Protected fixture',
            'content': value.$2,
            'labels': '[]',
            'updated_at': 1,
            'collection': 'note',
            'editor_type': 'markdown',
            'password_hash': hash,
          });
        }
      });
      final before = await owner.exclusiveSnapshot(
        (db) => OwnedGeneration15SchemaGate().rowDigests(db),
      );
      final completed = await exporter().create();
      try {
        final extracted = File('${root.path}/protected-copy.db');
        await LocalBackupCodec.decode(completed.file.openRead(), (
          entry,
          stream,
        ) async {
          if (entry.path == 'database/content.db') {
            final sink = extracted.openWrite();
            try {
              await sink.addStream(stream);
              await sink.flush();
            } finally {
              await sink.close();
            }
          } else {
            await stream.drain<void>();
          }
        });
        final db = await factory.openDatabase(
          extracted.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await OwnedGeneration15SchemaGate().rowDigests(db), before);
        } finally {
          await db.close();
        }
      } finally {
        await completed.dispose();
      }
    },
  );
  for (final rejected in [
    'invalid-text',
    'protected-blob',
    'created-blob',
    'complex-blob',
    'article-blob',
  ]) {
    test('opaque backup does not admit $rejected', () async {
      await owner.exclusiveSnapshot((db) async {
        final contentSql = rejected == 'invalid-text' ? 'CAST(? AS TEXT)' : '?';
        await db.rawInsert(
          "INSERT INTO notes(id,title,content,labels,updated_at,collection,editor_type,password_hash) "
          "VALUES(8001,'Rejected opaque',$contentSql,'[]',1,?,?,?)",
          [
            Uint8List.fromList([0xff, 0, 0xef, 0xbb, 0xbf]),
            rejected == 'article-blob' ? 'article' : 'note',
            rejected == 'complex-blob' ? 'drawing' : 'markdown',
            rejected == 'protected-blob' ? r'$2a$10$' + ('A' * 53) : '',
          ],
        );
        if (rejected == 'created-blob') {
          // Rejection fixture, never presented as successful creation evidence.
          await db.rawInsert(
            'INSERT INTO html_creation_receipts(creation_key,note_id,collection,input_hash,created_at) VALUES(?,?,?,?,?)',
            ['2' * 32, 8001, 'note', '3' * 64, 1],
          );
        }
      });
      final before = await owner.exclusiveSnapshot(
        (db) => OwnedGeneration15SchemaGate().rowDigests(db),
      );
      await expectLater(exporter().create(), throwsFormatException);
      expect(
        await owner.exclusiveSnapshot(
          (db) => OwnedGeneration15SchemaGate().rowDigests(db),
        ),
        before,
        reason: 'Failure cannot normalize or delete original cells',
      );
      expect(await Directory('${root.path}/exports').list().toList(), isEmpty);
    });
  }
  test(
    'corrupt historical payload hash is rejected and incomplete export is removed',
    () async {
      await owner.exclusiveSnapshot(
        (db) => db.rawUpdate(
          'UPDATE legacy_import_records SET payload_sha256=? WHERE rowid=(SELECT min(rowid) FROM legacy_import_records)',
          ['0' * 64],
        ),
      );
      await expectLater(exporter().create(), throwsFormatException);
      expect(await Directory('${root.path}/exports').list().toList(), isEmpty);
    },
  );
  test(
    'pending recovery blocks before snapshot and leaves no archive',
    () async {
      await expectLater(
        exporter(
          preflight: () async {
            throw StateError('Unresolved owned operation');
          },
        ).create(),
        throwsStateError,
      );
      final exports = Directory('${root.path}/exports');
      expect(
        await exports.exists() ? await exports.list().toList() : [],
        isEmpty,
      );
    },
  );
  test(
    'native epoch change seals export without publishing a completed archive',
    () async {
      pointerRaw = LocalGenerationPointer(
        generation: pointer.generation,
        epoch: 2,
        activationId: 'e' * 32,
        sourceSHA256: 'c' * 64,
      ).encode();
      await expectLater(exporter().create(), throwsA(anything));
      expect(owner.current, isFalse);
    },
  );
}
