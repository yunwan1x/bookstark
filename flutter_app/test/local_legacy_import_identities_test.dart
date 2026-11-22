import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_import_identities.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher reason(LegacyIdentityReason value) =>
    isA<LegacyIdentityFailure>().having((e) => e.reason, 'reason', value);
void main() {
  late Directory root;
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-identities-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyGoExport> inspect(String name) async {
    final file = File('test/fixtures/legacy_zip/$name.zip');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final stage = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: hash,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    return LegacyGoExport.inspect(stage);
  }

  Future<LegacyImportIdentities> index([String variant = 'good']) async =>
      LegacyImportIdentities.fromExport(await inspect('identity-$variant'));
  Object signature(LegacyImportIdentities value) => value.entries
      .map((e) => [e.kind.name, e.parts, e.localId, e.sourceSha256])
      .toList();

  test(
    'fresh candidate IDs keep namespaces and exact max64 references',
    () async {
      final value = await index();
      expect(value.entries.length, 20);
      expect(value.lookup(LegacyImportKind.book, ['book-id']).localId, 1);
      expect(
        value.lookup(LegacyImportKind.document, [
          'book-id',
          'child-id',
        ]).localId,
        2,
      );
      expect(value.lookup(LegacyImportKind.note, ['article-id']).localId, 2);
      expect(
        value.lookup(LegacyImportKind.task, ['9223372036854775807']).localId,
        1,
      );
      expect(value.lookup(LegacyImportKind.task, ['7']).localId, 2);
      expect(value.taskParent(9223372036854775807), 1);
      expect(value.taskParent(0), 0);
      expect(value.documentParent('book-id', 'parent-id'), 1);
      expect(value.documentParent('book-id', ''), 0);
    },
  );
  test(
    'repeated inspected source produces the same source-bound mapping',
    () async {
      final source = await inspect('identity-good');
      final first = LegacyImportIdentities.fromExport(source);
      final second = LegacyImportIdentities.fromExport(source);
      expect(signature(first), signature(second));
      expect(
        first.entries.every((e) => e.sourceSha256 == source.sourceSha256),
        isTrue,
      );
      final other = await index('tuple-alias');
      expect(other.sourceSha256, isNot(first.sourceSha256));
    },
  );
  test(
    'tuple identities survive slash aliases and ambiguous lookup blocks',
    () async {
      final value = await index('tuple-alias');
      final first = value.lookup(LegacyImportKind.document, ['a/b', 'c']);
      final second = value.lookup(LegacyImportKind.document, ['a', 'b/c']);
      expect(first.localId, isNot(second.localId));
      expect(
        () => value.resource('document', 'a/b/c'),
        throwsA(reason(LegacyIdentityReason.ambiguous)),
      );
      expect(value.resource('document', 'book-id/child-id').localId, 2);
    },
  );
  test('note and article aliases cannot cross their real collection', () async {
    final value = await index();
    expect(value.resource('note', 'note-id').localId, 1);
    expect(value.resource('article', 'article-id').localId, 2);
    expect(value.resource('blog', 'article-id').localId, 2);
    expect(
      () => value.resource('note', 'article-id'),
      throwsA(reason(LegacyIdentityReason.unresolved)),
    );
    expect(
      () => value.resource('task', '09223372036854775807'),
      throwsA(reason(LegacyIdentityReason.unresolved)),
    );
  });
  test(
    'optional old IDs keep every row without creating fake references',
    () async {
      final value = await index();
      expect(value.counts[LegacyImportKind.summary], 2);
      expect(value.counts[LegacyImportKind.topicResource], 2);
      expect(value.counts[LegacyImportKind.comment], 3);
      expect(
        value.childAt(LegacyImportKind.summary, 4, 0),
        same(value.childByOldId(LegacyImportKind.summary, 4, 5)),
      );
      expect(value.childAt(LegacyImportKind.summary, 4, 1).localId, 2);
      expect(
        () => value.childByOldId(LegacyImportKind.summary, 4, 0),
        throwsA(reason(LegacyIdentityReason.unresolved)),
      );
      expect(value.commentParent(4, 8), 1);
      expect(value.commentParent(4, 0), 0);
    },
  );
  test(
    'same old child IDs in two topics resolve to different local rows',
    () async {
      final value = await index('cross-topic');
      final first = value.childByOldId(LegacyImportKind.summary, 4, 5);
      final second = value.childByOldId(LegacyImportKind.summary, 9, 5);
      expect(first.localId, 1);
      expect(second.localId, 3);
      expect(value.commentParent(4, 8), 1);
      expect(value.commentParent(9, 8), 4);
    },
  );
  test(
    'duplicate native bookmark URL is rejected without merging source rows',
    () async {
      final source = await inspect('identity-duplicate-bookmark');
      expect((source.sections['bookmarks.json'] as List).length, 2);
      expect(
        () => LegacyImportIdentities.fromExport(source),
        throwsA(reason(LegacyIdentityReason.duplicate)),
      );
      expect((source.sections['bookmarks.json'] as List).length, 2);
      final good = await index();
      expect(good.counts[LegacyImportKind.friendLink], 2);
    },
  );
  test(
    'unresolved references and duplicate children cannot allocate a candidate',
    () async {
      for (final variant in ['bad-reference', 'duplicate-child']) {
        final source = await inspect('identity-$variant');
        expect(
          () => LegacyImportIdentities.fromExport(source),
          throwsA(reason(LegacyIdentityReason.invalidSource)),
        );
      }
      expect(
        const LegacyIdentityFailure(LegacyIdentityReason.unresolved).toString(),
        isNot(contains('secret-source-value')),
      );
    },
  );
  test('published entries, tuple parts and counts are immutable', () async {
    final value = await index();
    expect(() => value.entries.clear(), throwsUnsupportedError);
    expect(() => value.entries.first.parts.clear(), throwsUnsupportedError);
    expect(() => value.counts.clear(), throwsUnsupportedError);
  });
  test(
    'unknown metadata and protected source are unchanged and never decoded',
    () async {
      for (final variant in ['unknown-field', 'protected']) {
        final source = await inspect('contract-$variant');
        final before = jsonEncode(source.sections);
        final value = LegacyImportIdentities.fromExport(source);
        expect(jsonEncode(source.sections), before);
        final wire = jsonEncode(signature(value));
        expect(wire, isNot(contains('ENC:v1:')));
        expect(wire, isNot(contains('future_secret_field')));
        expect(wire, isNot(contains('blog_content')));
        expect(wire, isNot(contains('password')));
      }
    },
  );
}
