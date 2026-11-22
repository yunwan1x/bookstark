import 'dart:io';

import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('go-export-inspect-'),
  );
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyGoExport> inspect(
    String variant, {
    bool Function()? cancelled,
  }) async {
    final source = File('test/fixtures/legacy_zip/contract-$variant.zip');
    final receipt = (await sha256.bind(source.openRead()).first).toString();
    final stage = await LegacyZipStage.inspect(
      source,
      privateParent: root,
      expectedSha256: receipt,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    return LegacyGoExport.inspect(stage, isCancelled: cancelled);
  }

  test(
    'Go v1 preserves nil arrays, max IDs, hierarchy, labels and exact complex JSON',
    () async {
      final result = await inspect('good');
      expect(result.counts, {
        'books': 1,
        'documents': 2,
        'blogs': 1,
        'bookmarks': 0,
        'tasks': 1,
        'topics': 1,
        'labels': 1,
        'friend_links': 1,
        'uploads': 1,
      });
      expect(result.issues.map((issue) => issue.code), [
        LegacyGoIssueCode.editorTypeMissing,
      ]);
      expect(result.requiresResolution, isTrue);
      final book = ((result.sections['books.json'] as List).single as Map);
      final docs = book['documents'] as List;
      expect((docs[0] as Map)['markdown'], '\uFEFF# parent\r\n');
      expect((docs[1] as Map)['parent_identify'], 'parent-id');
      expect(
        (docs[1] as Map)['markdown'],
        '{"type":"excalidraw","future":{"opaque":true}}',
      );
      final task = ((result.sections['tasks.json'] as List).single as Map);
      expect(task['task_id'], 9223372036854775807);
      final blog = ((result.sections['blogs.json'] as List).single as Map);
      expect(blog['blog_content'], '\uFEFF# body\r\n');
      expect(blog['visibility'], 2);
      expect(blog['pin_order'], 5);
      expect(blog.containsKey('editor_type'), isFalse);
      expect(() => blog['blog_content'] = 'overwrite', throwsUnsupportedError);
      expect(() => docs.clear(), throwsUnsupportedError);
    },
  );

  test('manifest mismatch and missing required field block parsing', () async {
    for (final variant in ['count-mismatch', 'missing-type']) {
      await expectLater(inspect(variant), throwsFormatException);
    }
  });

  test(
    'missing file, wrong size and wrong SHA are distinct blocked issues',
    () async {
      for (final pair in [
        ('missing-upload', LegacyGoIssueCode.missingUpload),
        ('size-mismatch', LegacyGoIssueCode.uploadSizeMismatch),
        ('hash-mismatch', LegacyGoIssueCode.uploadHashMismatch),
      ]) {
        final result = await inspect(pair.$1);
        expect(result.issues.map((issue) => issue.code), contains(pair.$2));
        expect(result.requiresResolution, isTrue);
        expect(
          result.issues.map((issue) => issue.location).join(),
          isNot(contains('bytes.bin')),
        );
      }
    },
  );

  test('unknown fields remain exact and require explicit handling', () async {
    final result = await inspect('unknown-field');
    expect(
      result.issues.map((issue) => issue.code),
      contains(LegacyGoIssueCode.unknownField),
    );
    final blog = (result.sections['blogs.json'] as List).single as Map;
    expect(blog['future_secret_field'], {'nested': 'preserve'});
    expect(
      result.issues.map((issue) => issue.location).join(),
      isNot(contains('future_secret_field')),
    );
  });

  test(
    'structurally protected content is never declared unlocked or ready',
    () async {
      final result = await inspect('protected');
      expect(
        result.issues.map((issue) => issue.code),
        contains(LegacyGoIssueCode.protectedContent),
      );
      expect(
        result.issues.map((issue) => issue.code),
        isNot(contains(LegacyGoIssueCode.unsupportedProtection)),
      );
      final blog = (result.sections['blogs.json'] as List).single as Map;
      expect(blog['blog_content'], startsWith('ENC:v1:'));
      expect(blog['password'], startsWith(r'$2a$10$'));
      expect(result.requiresResolution, isTrue);
    },
  );

  test(
    'unrecognized protected formats are reported without plaintext conversion',
    () async {
      final result = await inspect('unsupported-protection');
      expect(
        result.issues.map((issue) => issue.code),
        containsAll([
          LegacyGoIssueCode.protectedContent,
          LegacyGoIssueCode.unsupportedProtection,
        ]),
      );
      final blog = (result.sections['blogs.json'] as List).single as Map;
      expect(blog['blog_content'], 'ENC:v9:unsupported');
    },
  );

  test(
    'exports without uploads require explicit missing-resource resolution',
    () async {
      final result = await inspect('uploads-omitted');
      expect(result.counts['uploads'], 0);
      expect(
        result.issues.map((issue) => issue.code),
        contains(LegacyGoIssueCode.uploadsNotIncluded),
      );
    },
  );

  test('unknown archive sections cannot silently disappear', () async {
    final result = await inspect('unknown-entry');
    expect(
      result.issues.map((issue) => issue.code),
      contains(LegacyGoIssueCode.unknownEntry),
    );
    expect(result.requiresResolution, isTrue);
  });

  test('staged JSON changed without a size change is rejected', () async {
    final source = File('test/fixtures/legacy_zip/contract-good.zip');
    final receipt = (await sha256.bind(source.openRead()).first).toString();
    final stage = await LegacyZipStage.inspect(
      source,
      privateParent: root,
      expectedSha256: receipt,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final bodyFile = stage.files['blogs.json']!;
    final before = await bodyFile.file.readAsString();
    final after = before.replaceFirst('# body', '# B0DY');
    expect(after, isNot(before));
    await bodyFile.file.writeAsString(after);
    expect(await bodyFile.file.length(), bodyFile.bytes);
    await expectLater(LegacyGoExport.inspect(stage), throwsFormatException);
  });

  test('cancelled inspection cannot become a result', () async {
    await expectLater(
      inspect('good', cancelled: () => true),
      throwsA(isA<LegacyZipStageCancelled>()),
    );
  });
}
