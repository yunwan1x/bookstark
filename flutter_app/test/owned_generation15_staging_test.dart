import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_generation15_staging.dart';

void main() {
  late Directory root;
  late LegacyZipStage zip;
  late LegacyFormatSelection selection;
  bool current = true;
  OwnedGeneration15Staging? stage;
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
    root = await parent.createTemp('owned15-stage-unit-');
    current = true;
    stage = null;
    final file = File(
      'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
    );
    zip = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(zip);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
    );
    selection = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
  });
  tearDown(() async {
    await stage?.retire();
    await root.delete(recursive: true);
  });
  Future<OwnedGeneration15Staging> build({
    AttachmentCancellation? cancellation,
  }) => OwnedGeneration15Staging.build(
    stage: zip,
    selection: selection,
    privateParent: root,
    availableBytes: () async => 4 * 1024 * 1024 * 1024,
    isCurrentScope: () => current,
    factory: databaseFactoryFfiNoIsolate,
    cancellation: cancellation,
  );

  test(
    'fresh real source creates separate proof-bound staging and schema15 archive',
    () async {
      final untouched = File('${root.path}/untouched-active14.db');
      await untouched.writeAsBytes([0, 1, 2, 3, 255], flush: true);
      stage = await build();
      final rows = await stage!.readSnapshot((db) async {
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          15,
        );
        expect(
          (await db.rawQuery('PRAGMA query_only')).single.values.single,
          1,
        );
        await expectLater(
          db.execute("UPDATE notes SET title='forbidden'"),
          throwsA(anything),
        );
        return OwnedGeneration15SchemaGate().rowDigests(db);
      });
      final proofFile = File(
        '${stage!.generation.privateSupport.path}/activation-proof.json',
      );
      final proof = jsonDecode(await proofFile.readAsString()) as Map;
      expect(proof['sourceSHA256'], zip.sourceSha256);
      expect(proof['freshDatabase'], isTrue);
      expect(proof['typedRows'], rows);
      expect(proof.keys, contains('runtimeMetadata'));
      final backup = await StagedGeneration15BackupExporter(
        stage: stage!,
        factory: databaseFactoryFfiNoIsolate,
        workspace: Directory('${root.path}/exports'),
        checkPendingRecovery: () async {},
      ).create();
      try {
        expect(backup.manifest.databaseSchema, 15);
        expect(backup.manifest.toJson()['version'], 3);
        final output = File('${root.path}/roundtrip.db');
        final files = <String, Uint8List>{};
        await LocalBackupCodec.decode(backup.file.openRead(), (
          entry,
          stream,
        ) async {
          final builder = BytesBuilder(copy: false);
          await for (final bytes in stream) {
            builder.add(bytes);
          }
          files[entry.path] = builder.takeBytes();
        });
        await output.writeAsBytes(files['database/content.db']!, flush: true);
        final db = await databaseFactoryFfiNoIsolate.openDatabase(
          output.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await OwnedGeneration15SchemaGate().rowDigests(db), rows);
        } finally {
          await db.close();
        }
        await for (final entry in stage!.generation.attachments.list(
          followLinks: false,
        )) {
          final file = File(entry.path);
          expect(
            files['attachments/${file.uri.pathSegments.last}'],
            await file.readAsBytes(),
          );
        }
        expect(await untouched.readAsBytes(), [0, 1, 2, 3, 255]);
      } finally {
        await backup.dispose();
      }
    },
  );
  test('already cancelled request creates no owned staging root', () async {
    final cancellation = AttachmentCancellation()..cancel();
    await expectLater(build(cancellation: cancellation), throwsA(anything));
    expect(
      (await root.list().toList()).where(
        (entry) => entry.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('owned15-stage-'),
      ),
      isEmpty,
    );
  });
  test(
    'late owner change blocks staged reads while cleanup still removes only own root',
    () async {
      stage = await build();
      current = false;
      var calls = 0;
      await expectLater(
        stage!.readSnapshot((db) async {
          calls++;
        }),
        throwsStateError,
      );
      expect(calls, 0);
      final owned = stage!.generation.privateSupport;
      await stage!.retire();
      expect(await owned.exists(), isFalse);
    },
  );
  test('modified proof cannot authorize a read or publish a backup', () async {
    stage = await build();
    final proof = File(
      '${stage!.generation.privateSupport.path}/activation-proof.json',
    );
    await proof.writeAsString('{}', flush: true);
    await expectLater(
      stage!.readSnapshot((db) async {}),
      throwsFormatException,
    );
    await expectLater(
      StagedGeneration15BackupExporter(
        stage: stage!,
        factory: databaseFactoryFfiNoIsolate,
        workspace: Directory('${root.path}/exports'),
        checkPendingRecovery: () async {},
      ).create(),
      throwsFormatException,
    );
    expect(await Directory('${root.path}/exports').exists(), isFalse);
  });
}
