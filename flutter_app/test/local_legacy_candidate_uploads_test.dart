import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';

void main() {
  late Directory root;
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-upload-plan-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<(LegacyImportRecords, LegacyZipStage)> input(String name) async {
    final file = File('test/fixtures/legacy_zip/identity-$name.zip');
    final stage = await LegacyZipStage.inspect(
      file,
      privateParent: root,
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
    final mapping = LegacyImportMapping.fromRecipe(
      source,
      selection.toJson(),
      scopeKey: 'b' * 32,
    );
    return (LegacyImportRecords.fromExport(source, mapping), stage);
  }

  Future<LegacyCandidateUploads> plan(String name) async {
    final (records, stage) = await input(name);
    return LegacyCandidateUploads.fromRecords(records, stage);
  }

  test(
    'genuine Go original produces deterministic source-bound safe basename without writes',
    () async {
      final (records, stage) = await input('known-formats');
      final before = jsonEncode(records.source.sections);
      final paths = await root
          .list(recursive: true)
          .map((e) => e.path)
          .toList();
      final a = LegacyCandidateUploads.fromRecords(records, stage),
          b = LegacyCandidateUploads.fromRecords(records, stage);
      expect(a.uploadRows, 1);
      expect(a.blobs.length, 1);
      expect(a.bindings.length, 1);
      expect(a.blobs.single.attachmentId, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(a.blobs.single.aliasPath, '/upload-files/bytes.bin');
      expect(a.totalBytes, 7);
      expect(a.planSha256, b.planSha256);
      expect(a.sourceSha256, stage.sourceSha256);
      expect(a.recipeSha256, records.mapping.recipeSha256);
      expect(jsonEncode(records.source.sections), before);
      expect(
        await root.list(recursive: true).map((e) => e.path).toList(),
        paths,
      );
      expect(() => a.blobs.clear(), throwsUnsupportedError);
      expect(() => a.bindings.clear(), throwsUnsupportedError);
    },
  );
  test(
    'thumbnail keeps exact staged digest and encodes Unicode path once',
    () async {
      final a = await plan('upload-thumbnails');
      expect(a.uploadRows, 1);
      expect(a.blobs.length, 2);
      expect(a.bindings.length, 2);
      expect(a.totalBytes, 11);
      final thumb = a.bindings.singleWhere(
        (b) => b.role == LegacyUploadRole.thumbnail,
      );
      expect(
        thumb.blob.aliasPath,
        '/upload-files/thumbs/${Uri.encodeComponent('预览🙂.bin')}',
      );
      expect(thumb.blob.sha256Hex, sha256.convert([0, 255, 13, 10]).toString());
      expect(thumb.uploadId, 1);
    },
  );
  test(
    'shared thumbnail copies one logical blob but preserves every binding and distinct originals',
    () async {
      final a = await plan('upload-shared-thumb');
      expect(a.uploadRows, 2);
      expect(a.blobs.length, 3);
      expect(a.bindings.length, 4);
      expect(a.totalBytes, 18);
      final thumbs = a.bindings
          .where((b) => b.role == LegacyUploadRole.thumbnail)
          .toList();
      expect(identical(thumbs[0].blob, thumbs[1].blob), true);
      final originals = a.bindings
          .where((b) => b.role == LegacyUploadRole.original)
          .toList();
      expect(originals.map((b) => b.uploadId).toList(), [1, 2]);
      expect(originals[0].blob.sha256Hex, originals[1].blob.sha256Hex);
      expect(
        originals[0].blob.attachmentId,
        isNot(originals[1].blob.attachmentId),
      );
    },
  );
  test(
    'original used as own thumbnail retains both roles and one file',
    () async {
      final a = await plan('upload-original-thumb');
      expect(a.blobs.length, 1);
      expect(a.bindings.length, 2);
      expect(a.totalBytes, 7);
      expect(a.bindings.map((b) => b.role).toList(), LegacyUploadRole.values);
      expect(identical(a.bindings[0].blob, a.bindings[1].blob), true);
    },
  );
  test('explicit empty upload section has an empty verifiable plan', () async {
    final a = await plan('upload-empty');
    expect(a.uploadRows, 0);
    expect(a.blobs, isEmpty);
    expect(a.bindings, isEmpty);
    expect(a.totalBytes, 0);
    expect(a.planSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
  });
  test(
    'raw Go percent path is ambiguous and blocks instead of interpreting it',
    () async {
      final (records, stage) = await input('upload-ambiguous-path');
      expect(
        () => LegacyCandidateUploads.fromRecords(records, stage),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.ambiguousPath,
          ),
        ),
      );
    },
  );
  test(
    'stage from a different source cannot satisfy otherwise valid records',
    () async {
      final (records, _) = await input('known-formats');
      final (_, stage) = await input('upload-thumbnails');
      expect(
        () => LegacyCandidateUploads.fromRecords(records, stage),
        throwsA(
          isA<LegacyUploadFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyUploadReason.sourceMismatch,
          ),
        ),
      );
    },
  );
  test('cancellation interrupts planning without a partial result', () async {
    final (records, stage) = await input('upload-shared-thumb');
    var checks = 0;
    expect(
      () => LegacyCandidateUploads.fromRecords(
        records,
        stage,
        isCancelled: () => ++checks >= 4,
      ),
      throwsA(isA<LegacyRecordsCancelled>()),
    );
  });
  test(
    'source changes allocate different local attachment identities',
    () async {
      final a = await plan('known-formats'),
          b = await plan('upload-thumbnails');
      expect(a.blobs.first.logicalName, b.blobs.first.logicalName);
      expect(a.blobs.first.attachmentId, isNot(b.blobs.first.attachmentId));
      expect(a.planSha256, isNot(b.planSha256));
    },
  );
}
