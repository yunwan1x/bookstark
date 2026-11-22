import 'dart:io';
import 'dart:ffi';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_upload_copy.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';

void main() {
  late Directory root, destination;
  late Database db;
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
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-upload-sql-');
    destination = await Directory('${root.path}/copies').create();
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      '${root.path}/candidate.db',
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<(LegacyImportRecords, LegacyCandidateUploads, LegacyCopiedUploads)>
  input([String name = 'upload-shared-thumb']) async {
    final file = File('test/fixtures/legacy_zip/identity-$name.zip');
    final stage = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(stage);
    final format = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
    );
    final selected = LegacyFormatSelection(
      format,
      choices: {
        for (final item in format.items)
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
        scopeKey: 'b' * 32,
      ),
    );
    final plan = LegacyCandidateUploads.fromRecords(records, stage);
    final copy = await copyLegacyCandidateUploads(
      plan,
      privateParent: destination,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    return (records, plan, copy);
  }

  Future<void> seed(Transaction tx, LegacyImportRecords records) async {
    await writeLegacyCandidateMetadata(
      tx,
      records,
      importedAt: DateTime.utc(2026, 11, 8),
    );
    await writeLegacyCandidatePrimaryRows(
      tx,
      LegacyCandidateRows.fromRecords(records),
    );
  }

  Future<void> empty() async {
    for (final (name,) in (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => (row['name'] as String,))) {
      expect(
        (await db.rawQuery('SELECT count(*) AS n FROM "$name"')).single['n'],
        0,
        reason: name,
      );
    }
  }

  test(
    'real Go originals and shared thumbnail bind same-source metadata with exact aliases and bytes',
    () async {
      final (records, plan, copy) = await input();
      final facts = await db.transaction((tx) async {
        await seed(tx, records);
        return writeLegacyCandidateUploads(tx, plan, copy);
      });
      expect(facts.blobs, 3);
      expect(facts.bindings, 4);
      expect(facts.planSha256, plan.planSha256);
      final blobs = await db.query(
        'legacy_import_upload_blobs',
        orderBy: 'logical_name',
      );
      expect(blobs.length, 3);
      for (final blob in plan.blobs) {
        final row = blobs.singleWhere(
          (row) => row['attachment_id'] == blob.attachmentId,
        );
        expect(row['source_sha256'], plan.sourceSha256);
        expect(row['logical_name'], blob.logicalName);
        expect(row['alias_path'], blob.aliasPath);
        expect(row['file_size'], blob.bytes);
        expect(
          row['file_sha256'],
          (await sha256
                  .bind(
                    File(
                      '${copy.directory.path}/${blob.attachmentId}',
                    ).openRead(),
                  )
                  .first)
              .toString(),
        );
      }
      final bindings = await db.query(
        'legacy_import_upload_bindings',
        orderBy: 'upload_id,role',
      );
      expect(
        bindings
            .where((r) => r['role'] == 'thumbnail')
            .map((r) => r['attachment_id'])
            .toSet()
            .length,
        1,
      );
      expect(
        (await db.query(
          'legacy_import_records',
          where: "kind='upload'",
        )).length,
        2,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await db.query('local_images'), isEmpty);
      expect(await db.query('local_drive_nodes'), isEmpty);
    },
  );
  test(
    'same transaction rolls back all metadata/primary rows on upload insert abort',
    () async {
      final (records, plan, copy) = await input();
      await db.execute(
        "CREATE TRIGGER fail_upload BEFORE INSERT ON legacy_import_upload_blobs BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      await expectLater(
        db.transaction((tx) async {
          await seed(tx, records);
          await writeLegacyCandidateUploads(tx, plan, copy);
        }),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.storage,
          ),
        ),
      );
      await empty();
      expect(await copy.files.first.file.exists(), true);
    },
  );
  test(
    'cancellation after one blob rolls back source registry and all rows',
    () async {
      final (records, plan, copy) = await input();
      var cancelled = false;
      await expectLater(
        db.transaction((tx) async {
          await seed(tx, records);
          await writeLegacyCandidateUploads(
            tx,
            plan,
            copy,
            isCancelled: () => cancelled,
            onProgress: (v) {
              if (v.blobs == 1) cancelled = true;
            },
          );
        }),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      await empty();
    },
  );
  test(
    'late SQL trigger tampering is caught by final exact-cell verification',
    () async {
      final (records, plan, copy) = await input();
      await db.execute(
        "CREATE TRIGGER tamper_upload AFTER INSERT ON legacy_import_upload_bindings BEGIN UPDATE legacy_import_upload_blobs SET file_sha256='${'0' * 64}'; END",
      );
      await expectLater(
        db.transaction((tx) async {
          await seed(tx, records);
          await writeLegacyCandidateUploads(tx, plan, copy);
        }),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.integrity,
          ),
        ),
      );
      await empty();
    },
  );
  test(
    'missing source upload metadata blocks before bindings and rolls back everything',
    () async {
      final (records, plan, copy) = await input();
      await expectLater(
        db.transaction((tx) async {
          await seed(tx, records);
          await tx.delete('legacy_import_records', where: "kind='upload'");
          await writeLegacyCandidateUploads(tx, plan, copy);
        }),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.sourceMismatch,
          ),
        ),
      );
      await empty();
    },
  );
  test(
    'corrupted copy after receipt is rechecked before SQL and all metadata rolls back',
    () async {
      final (records, plan, copy) = await input();
      await copy.files.first.file.writeAsBytes(
        List.filled(copy.files.first.blob.bytes, 42),
      );
      await expectLater(
        db.transaction((tx) async {
          await seed(tx, records);
          await writeLegacyCandidateUploads(tx, plan, copy);
        }),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.integrity,
          ),
        ),
      );
      await empty();
    },
  );
  test('unexpected file in copy directory is not silently admitted', () async {
    final (records, plan, copy) = await input();
    await File('${copy.directory.path}/extra.bin').writeAsBytes([1]);
    await expectLater(
      db.transaction((tx) async {
        await seed(tx, records);
        await writeLegacyCandidateUploads(tx, plan, copy);
      }),
      throwsA(isA<LegacyUploadFailure>()),
    );
    await empty();
  });
  test('copy observation from another source cannot be reused', () async {
    final (records, plan, _) = await input();
    final (_, _, other) = await input('known-formats');
    await expectLater(
      db.transaction((tx) async {
        await seed(tx, records);
        await writeLegacyCandidateUploads(tx, plan, other);
      }),
      throwsA(
        isA<LegacyUploadFailure>().having(
          (e) => e.reason,
          'reason',
          LegacyUploadReason.sourceMismatch,
        ),
      ),
    );
    await empty();
  });
  test(
    'committed upload observations are not replaced on repeat invocation',
    () async {
      final (records, plan, copy) = await input();
      await db.transaction((tx) async {
        await seed(tx, records);
        await writeLegacyCandidateUploads(tx, plan, copy);
      });
      final before = await db.query('legacy_import_upload_blobs');
      await expectLater(
        db.transaction((tx) => writeLegacyCandidateUploads(tx, plan, copy)),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.nonemptyCandidate,
          ),
        ),
      );
      expect(await db.query('legacy_import_upload_blobs'), before);
    },
  );
  test(
    'explicit zero-upload export stores no invented attachment records',
    () async {
      final (records, plan, copy) = await input('upload-empty');
      final result = await db.transaction((tx) async {
        await seed(tx, records);
        return writeLegacyCandidateUploads(tx, plan, copy);
      });
      expect(result.blobs, 0);
      expect(result.bindings, 0);
      expect(await db.query('legacy_import_upload_blobs'), isEmpty);
    },
  );
  test(
    'foreign keys enforce source/upload/role association and retain original plus thumbnail',
    () async {
      final (records, plan, copy) = await input('upload-original-thumb');
      await db.transaction((tx) async {
        await seed(tx, records);
        await writeLegacyCandidateUploads(tx, plan, copy);
      });
      expect((await db.query('legacy_import_upload_blobs')).length, 1);
      expect((await db.query('legacy_import_upload_bindings')).length, 2);
      await expectLater(
        db.insert('legacy_import_upload_bindings', {
          'source_sha256': plan.sourceSha256,
          'upload_kind': 'note',
          'upload_id': 1,
          'role': 'original',
          'attachment_id': plan.blobs.single.attachmentId,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('legacy_import_upload_bindings', {
          'source_sha256': plan.sourceSha256,
          'upload_id': 999,
          'role': 'original',
          'attachment_id': plan.blobs.single.attachmentId,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}
