import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_upload_copy.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';

void main() {
  late Directory root, stageRoot, destination;
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-copy-');
    stageRoot = await Directory('${root.path}/stage').create();
    destination = await Directory('${root.path}/destination').create();
    await File('${destination.path}/keep.bin').writeAsBytes([9, 8, 7]);
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyCandidateUploads> plan([
    String name = 'upload-shared-thumb',
  ]) async {
    final file = File('test/fixtures/legacy_zip/identity-$name.zip');
    final stage = await LegacyZipStage.inspect(
      file,
      privateParent: stageRoot,
      expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(stage);
    final selection = LegacyFormatSelection(
      LegacyFormatSource.fromInspection(source, scopeKey: 'b' * 32),
      choices: {
        for (final item in LegacyFormatSource.fromInspection(
          source,
          scopeKey: 'b' * 32,
        ).items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    return LegacyCandidateUploads.fromRecords(
      LegacyImportRecords.fromExport(
        source,
        LegacyImportMapping.fromRecipe(
          source,
          selection.toJson(),
          scopeKey: 'b' * 32,
        ),
      ),
      stage,
    );
  }

  Future<void> onlySentinel() async {
    expect(
      await destination.list().map((f) => f.path.split('/').last).toList(),
      ['keep.bin'],
    );
    expect(await File('${destination.path}/keep.bin').readAsBytes(), [9, 8, 7]);
  }

  Future<int> plenty() async => 4 * 1024 * 1024 * 1024;
  test(
    'binary originals/shared Unicode thumbnail copy exactly into owned generated names',
    () async {
      final p = await plan(), progress = <LegacyUploadCopyProgress>[];
      final result = await copyLegacyCandidateUploads(
        p,
        privateParent: destination,
        availableBytes: plenty,
        onProgress: progress.add,
      );
      expect(result.files.length, 3);
      expect(result.planSha256, p.planSha256);
      expect(result.sourceSha256, p.sourceSha256);
      expect(result.recipeSha256, p.recipeSha256);
      expect(
        result.directory.parent.path,
        await destination.resolveSymbolicLinks(),
      );
      for (final item in result.files) {
        expect(item.file.path.split('/').last, item.blob.attachmentId);
        expect(
          await item.file.readAsBytes(),
          await item.blob.staged.file.readAsBytes(),
        );
        expect(
          await FileSystemEntity.type(item.file.path, followLinks: false),
          FileSystemEntityType.file,
        );
      }
      expect(progress.last.files, 3);
      expect(progress.last.bytes, 18);
      expect(() => result.files.clear(), throwsUnsupportedError);
      expect(await File('${destination.path}/keep.bin').readAsBytes(), [
        9,
        8,
        7,
      ]);
    },
  );
  test(
    'preflight shortage creates no files and preserves existing destination',
    () async {
      final p = await plan();
      await expectLater(
        copyLegacyCandidateUploads(
          p,
          privateParent: destination,
          availableBytes: () async => p.totalBytes + 128 * 1024 * 1024 - 1,
        ),
        throwsA(isA<LocalBackupSpaceUnavailable>()),
      );
      await onlySentinel();
    },
  );
  test(
    'same-size staged corruption fails digest and removes only owned child',
    () async {
      final p = await plan();
      await p.blobs.first.staged.file.writeAsBytes(
        List.filled(p.blobs.first.bytes, 42),
      );
      await expectLater(
        copyLegacyCandidateUploads(
          p,
          privateParent: destination,
          availableBytes: plenty,
        ),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.integrity,
          ),
        ),
      );
      await onlySentinel();
    },
  );
  test(
    'staged symlink is rejected without deleting its unrelated target',
    () async {
      final p = await plan(), input = p.blobs.first.staged.file;
      final sentinel = File('${root.path}/outside-owned-copy.bin');
      await sentinel.writeAsBytes([1, 2, 3, 4, 5, 6, 7]);
      await input.delete();
      await Link(input.path).create(sentinel.path);
      await expectLater(
        copyLegacyCandidateUploads(
          p,
          privateParent: destination,
          availableBytes: plenty,
        ),
        throwsA(isA<LegacyUploadFailure>()),
      );
      expect(await sentinel.readAsBytes(), [1, 2, 3, 4, 5, 6, 7]);
      await onlySentinel();
    },
  );
  test(
    'cancellation after first byte progress cleans partial outputs, never source files',
    () async {
      final p = await plan();
      var cancelled = false;
      await expectLater(
        copyLegacyCandidateUploads(
          p,
          privateParent: destination,
          availableBytes: plenty,
          isCancelled: () => cancelled,
          onProgress: (v) {
            if (v.bytes > 0) cancelled = true;
          },
        ),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      await onlySentinel();
      for (final blob in p.blobs) {
        expect(await blob.staged.file.length(), blob.bytes);
      }
    },
  );
  test(
    'late progress corruption is caught by the final independent readback',
    () async {
      final p = await plan();
      var changed = false;
      await expectLater(
        copyLegacyCandidateUploads(
          p,
          privateParent: destination,
          availableBytes: plenty,
          onProgress: (v) {
            if (v.files == v.totalFiles && !changed) {
              changed = true;
              final owned = destination
                  .listSync()
                  .whereType<Directory>()
                  .single;
              File(
                '${owned.path}/${p.blobs.first.attachmentId}',
              ).writeAsBytesSync(List.filled(p.blobs.first.bytes, 33));
            }
          },
        ),
        throwsA(isA<LegacyUploadFailure>()),
      );
      expect(changed, true);
      await onlySentinel();
    },
  );
  test(
    'empty plan returns an owned empty directory without inventing bindings',
    () async {
      final p = await plan('upload-empty');
      final result = await copyLegacyCandidateUploads(
        p,
        privateParent: destination,
        availableBytes: plenty,
      );
      expect(result.files, isEmpty);
      expect(await result.directory.list().toList(), isEmpty);
      expect(result.planSha256, p.planSha256);
    },
  );
  test(
    'multi-chunk binary is streamed and rechecks reserve during transfer',
    () async {
      final p = await plan('upload-large');
      var spaceChecks = 0, maxDelta = 0, last = 0;
      final result = await copyLegacyCandidateUploads(
        p,
        privateParent: destination,
        availableBytes: () async {
          spaceChecks++;
          return plenty();
        },
        onProgress: (v) {
          final delta = v.bytes - last;
          if (delta > maxDelta) maxDelta = delta;
          last = v.bytes;
        },
      );
      expect(p.totalBytes, 9100000);
      expect(spaceChecks, greaterThanOrEqualTo(3));
      expect(maxDelta, lessThanOrEqualTo(1024 * 1024));
      expect(
        (await sha256.bind(result.files.single.file.openRead()).first)
            .toString(),
        p.blobs.single.sha256Hex,
      );
    },
  );
  test('reserve loss mid-stream rolls back only this copy', () async {
    final p = await plan('upload-large');
    var calls = 0;
    await expectLater(
      copyLegacyCandidateUploads(
        p,
        privateParent: destination,
        availableBytes: () async => ++calls == 1 ? 4 * 1024 * 1024 * 1024 : 0,
      ),
      throwsA(isA<LocalBackupSpaceUnavailable>()),
    );
    expect(calls, 2);
    await onlySentinel();
  });
}
