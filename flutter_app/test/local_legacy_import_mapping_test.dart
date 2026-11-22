import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const scope = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
void main() {
  late Directory root;
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-mapping-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyGoExport> source([String variant = 'known-formats']) async {
    final file = File('test/fixtures/legacy_zip/identity-$variant.zip');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    return LegacyGoExport.inspect(
      await LegacyZipStage.inspect(
        file,
        privateParent: root,
        expectedSha256: hash,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
      ),
    );
  }

  LegacyFormatSelection choice(LegacyGoExport source) => LegacyFormatSelection(
    LegacyFormatSource.fromInspection(source, scopeKey: scope),
    choices: const {
      'note-id': LegacyContentFormat.markdown,
      'article-id': LegacyContentFormat.html,
    },
  );
  Matcher fail(LegacyMappingReason reason) =>
      isA<LegacyMappingFailure>().having((e) => e.reason, 'reason', reason);
  test(
    'real picker recipe binds actual local IDs without altering source bytes',
    () async {
      final value = await source();
      final before = jsonEncode(value.sections);
      final selected = choice(value);
      final mapped = LegacyImportMapping.fromRecipe(
        value,
        selected.toJson(),
        scopeKey: scope,
      );
      expect(mapped.sourceSha256, value.sourceSha256);
      expect(mapped.recipeSha256, selected.digest);
      expect(mapped.noteFormats, {
        1: LegacyContentFormat.markdown,
        2: LegacyContentFormat.html,
      });
      expect(mapped.documentFormats, {
        1: LegacyContentFormat.markdown,
        2: LegacyContentFormat.drawing,
      });
      expect(mapped.unresolvedIssues, isEmpty);
      expect(jsonEncode(value.sections), before);
      expect(jsonEncode(selected.toJson()), isNot(contains('blog_content')));
    },
  );
  test(
    'archive mismatch or invalid source scope cannot bind a recipe',
    () async {
      final value = await source();
      for (final wire in [
        {...choice(value).toJson(), 'source_sha256': 'a' * 64},
        {...choice(value).toJson(), 'version': 2},
      ]) {
        expect(
          () => LegacyImportMapping.fromRecipe(value, wire, scopeKey: scope),
          throwsA(fail(LegacyMappingReason.invalidRecipe)),
        );
      }
      expect(
        () => LegacyImportMapping.fromRecipe(
          value,
          choice(value).toJson(),
          scopeKey: 'not-a-scope',
        ),
        throwsA(fail(LegacyMappingReason.invalidRecipe)),
      );
    },
  );
  test(
    'missing, duplicated, foreign and unsupported choices are rejected',
    () async {
      final value = await source();
      for (final rows in [
        [
          {'identify': 'note-id', 'format': 'markdown'},
        ],
        [
          {'identify': 'note-id', 'format': 'markdown'},
          {'identify': 'note-id', 'format': 'html'},
        ],
        [
          {'identify': 'note-id', 'format': 'markdown'},
          {'identify': 'foreign-source-value', 'format': 'html'},
        ],
        [
          {'identify': 'note-id', 'format': 'markdown'},
          {'identify': 'article-id', 'format': 'HTML'},
        ],
      ]) {
        expect(
          () => LegacyImportMapping.fromRecipe(value, {
            ...choice(value).toJson(),
            'editors': rows,
          }, scopeKey: scope),
          throwsA(fail(LegacyMappingReason.invalidRecipe)),
        );
      }
    },
  );
  test(
    'unknown chapter format is never inferred from Excalidraw body data',
    () async {
      final value = await source('good');
      expect(
        () => LegacyImportMapping.fromRecipe(
          value,
          choice(value).toJson(),
          scopeKey: scope,
        ),
        throwsA(fail(LegacyMappingReason.unsupportedDocumentFormat)),
      );
    },
  );
  test(
    'picker-owned fake bodies and collection do not replace inspected rows',
    () async {
      final value = await source();
      final before = jsonEncode(value.sections);
      final fake = LegacyFormatSource(
        archiveSha256: value.sourceSha256,
        scopeKey: scope,
        items: const [
          LegacyFormatItem(
            id: 'note-id',
            title: 'fake',
            collection: 'article',
            originalBody: 'replace-source',
            passwordHash: 'fake',
          ),
          LegacyFormatItem(
            id: 'article-id',
            title: 'fake',
            collection: 'note',
            originalBody: 'replace-source',
            passwordHash: 'fake',
          ),
        ],
      );
      final selected = LegacyFormatSelection(
        fake,
        choices: const {
          'note-id': LegacyContentFormat.markdown,
          'article-id': LegacyContentFormat.html,
        },
      );
      final mapped = LegacyImportMapping.fromRecipe(
        value,
        selected.toJson(),
        scopeKey: scope,
      );
      expect(mapped.noteFormats[1], LegacyContentFormat.markdown);
      expect(jsonEncode(value.sections), before);
    },
  );
  test(
    'all seven explicit user choices remain explicit, without format defaults',
    () async {
      final value = await source();
      final real = LegacyFormatSource.fromInspection(value, scopeKey: scope);
      for (final format in LegacyContentFormat.values) {
        final selected = LegacyFormatSelection(
          real,
          choices: {'note-id': format, 'article-id': format},
        );
        final mapped = LegacyImportMapping.fromRecipe(
          value,
          selected.toJson(),
          scopeKey: scope,
        );
        expect(mapped.noteFormats.values, everyElement(format));
      }
    },
  );
  test(
    'format choice never acknowledges protection or unknown metadata',
    () async {
      final value = await source('review-required');
      final mapped = LegacyImportMapping.fromRecipe(
        value,
        choice(value).toJson(),
        scopeKey: scope,
      );
      expect(
        mapped.unresolvedIssues.map((e) => e.code),
        containsAll([
          LegacyGoIssueCode.protectedContent,
          LegacyGoIssueCode.unknownField,
        ]),
      );
      expect(
        mapped.unresolvedIssues.map((e) => e.code),
        isNot(contains(LegacyGoIssueCode.editorTypeMissing)),
      );
      final note = (value.sections['blogs.json'] as List).first as Map;
      expect(note['blog_content'], startsWith('ENC:v1:'));
      expect(note['future_metadata'], {'keep': true});
      expect(jsonEncode(choice(value).toJson()), isNot(contains('password')));
    },
  );
  test(
    'real Go ZIP missing hashes and excessive bcrypt cost remain blocking issues',
    () async {
      for (final variant in ['missing-hash', 'high-cost']) {
        final value = await source(variant);
        final mapped = LegacyImportMapping.fromRecipe(
          value,
          choice(value).toJson(),
          scopeKey: scope,
        );
        expect(
          mapped.unresolvedIssues.map((e) => e.code),
          containsAll([
            LegacyGoIssueCode.protectedContent,
            LegacyGoIssueCode.unsupportedProtection,
          ]),
        );
        final original = (value.sections['blogs.json'] as List).first as Map;
        expect(original['blog_content'], startsWith('ENC:v1:'));
      }
    },
  );
  test(
    'published format maps and unresolved issue list are immutable',
    () async {
      final value = await source();
      final mapped = LegacyImportMapping.fromRecipe(
        value,
        choice(value).toJson(),
        scopeKey: scope,
      );
      expect(() => mapped.noteFormats.clear(), throwsUnsupportedError);
      expect(() => mapped.documentFormats.clear(), throwsUnsupportedError);
      expect(() => mapped.unresolvedIssues.clear(), throwsUnsupportedError);
    },
  );
}
