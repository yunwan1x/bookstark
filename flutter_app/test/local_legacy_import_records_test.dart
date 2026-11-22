import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_identities.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-records-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyGoExport> source(String variant) async {
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

  LegacyImportMapping mapping(LegacyGoExport source) {
    final real = LegacyFormatSource.fromInspection(source, scopeKey: 'b' * 32);
    final selected = LegacyFormatSelection(
      real,
      choices: {
        for (final row in real.items)
          row.id: row.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    return LegacyImportMapping.fromRecipe(
      source,
      selected.toJson(),
      scopeKey: 'b' * 32,
    );
  }

  Future<LegacyImportRecords> records([
    String variant = 'known-formats',
  ]) async {
    final value = await source(variant);
    return LegacyImportRecords.fromExport(value, mapping(value));
  }

  Map<String, dynamic> value(LegacyRecordPayload record) =>
      jsonDecode(record.json) as Map<String, dynamic>;

  test(
    'Go20MiB escaped presentation survives inspection and canonical payload above32MiB',
    () async {
      final input = await source('budget-presentation');
      final formats = LegacyFormatSource.fromInspection(
        input,
        scopeKey: 'b' * 32,
      );
      final selection = LegacyFormatSelection(
        formats,
        choices: {
          for (final item in formats.items)
            item.id: utf8.encode(item.originalBody).length == 20 * 1024 * 1024
                ? LegacyContentFormat.presentation
                : item.collection == 'article'
                ? LegacyContentFormat.html
                : LegacyContentFormat.markdown,
        },
      );
      final plan = LegacyImportMapping.fromRecipe(
        input,
        selection.toJson(),
        scopeKey: 'b' * 32,
      );
      final original =
          ((input.sections['blogs.json'] as List).first as Map)['blog_content']
              as String;
      expect(
        ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          original,
        ).byteLength,
        20 * 1024 * 1024,
      );
      final prepared = LegacyImportRecords.fromExport(input, plan);
      final row = prepared.records().singleWhere(
        (r) =>
            r.identity.kind == LegacyImportKind.note && r.identity.localId == 1,
      );
      expect(row.bytes, greaterThan(32 * 1024 * 1024));
      expect(row.bytes, lessThan(LegacyImportRecords.maxPayloadBytes));
      expect((value(row)['fields'] as Map)['blog_content'], original);
      expect(row.sha256Hex, sha256.convert(utf8.encode(row.json)).toString());
    },
  );
  test(
    'every fresh identity has exactly one source-bound checksummed record',
    () async {
      final prepared = await records();
      final rows = prepared.records().toList();
      expect(rows.length, prepared.mapping.identities.entries.length);
      expect(rows.length, 20);
      expect(
        rows
            .map((r) => jsonEncode([r.identity.kind.name, r.identity.localId]))
            .toSet()
            .length,
        20,
      );
      for (final record in rows) {
        final parsed = value(record);
        expect(parsed['source_sha256'], prepared.source.sourceSha256);
        expect(parsed['format_recipe_sha256'], prepared.mapping.recipeSha256);
        expect(parsed['local_id'], record.identity.localId);
        expect(parsed['source_key'], record.identity.parts);
        expect(
          record.sha256Hex,
          sha256.convert(utf8.encode(record.json)).toString(),
        );
      }
    },
  );
  test(
    'headers keep child presence/count while each document retains exact source',
    () async {
      final rows = (await records()).records().toList();
      final book = value(
        rows.singleWhere((r) => r.identity.kind == LegacyImportKind.book),
      );
      expect((book['fields'] as Map).containsKey('documents'), isFalse);
      expect(book['child_sections'], {
        'documents': {'present': true, 'count': 2},
      });
      final docs = rows
          .where((r) => r.identity.kind == LegacyImportKind.document)
          .toList();
      final first = value(docs[0]), second = value(docs[1]);
      expect(first['source_ordinal'], 0);
      expect(second['source_ordinal'], 1);
      expect(first['parent'], {'kind': 'book', 'local_id': 1});
      expect(first['fields']['markdown'], '\uFEFF# parent\r\n');
      expect(
        second['fields']['markdown'],
        '{"type":"excalidraw","future":{"opaque":true}}',
      );
      expect(second['fields']['doc_type'], 'drawing');
    },
  );
  test(
    'max64 task references and all optional-ID topic children remain exact',
    () async {
      final rows = (await records()).records().toList();
      final tasks = rows
          .where((r) => r.identity.kind == LegacyImportKind.task)
          .toList();
      expect(value(tasks[0])['fields']['task_id'], 9223372036854775807);
      expect(value(tasks[1])['fields']['parent_id'], 9223372036854775807);
      final comments = rows
          .where((r) => r.identity.kind == LegacyImportKind.comment)
          .toList();
      expect(comments.length, 3);
      expect(value(comments.last)['fields'].containsKey('comment_id'), isFalse);
      expect(value(comments.last)['parent'], {'kind': 'topic', 'local_id': 1});
      final topic = value(
        rows.singleWhere((r) => r.identity.kind == LegacyImportKind.topic),
      );
      expect((topic['fields'] as Map).containsKey('comments'), isFalse);
      expect(topic['child_sections']['comments'], {
        'present': true,
        'count': 3,
      });
    },
  );
  test(
    'protected payload preserves original hash and ENC without decrypting it',
    () async {
      final prepared = await records('protected-formats');
      final original =
          (prepared.source.sections['blogs.json'] as List).first as Map;
      final row = prepared.records().singleWhere(
        (r) =>
            r.identity.kind == LegacyImportKind.note &&
            r.identity.parts.single == 'note-id',
      );
      final stored = value(row)['fields'];
      expect(stored['password'], original['password']);
      expect(stored['blog_content'], original['blog_content']);
      expect(stored['blog_content'], startsWith('ENC:v1:'));
      expect(stored.containsKey('editor_type'), isFalse);
    },
  );
  test(
    'duplicate label relations remain separate source-ordered records',
    () async {
      final prepared = await records('duplicate-label-relations');
      final rows = prepared.labelRelations().toList();
      expect(rows.length, 2);
      expect(rows.map((r) => r.sourceOrdinal).toList(), [0, 1]);
      expect(
        rows.every((r) => r.labelId == 1 && r.target.localId == 1),
        isTrue,
      );
      final first = jsonDecode(rows[0].json) as Map;
      final second = jsonDecode(rows[1].json) as Map;
      expect(first['fields'], second['fields']);
      expect(first['fields']['resource_type'], 'blog');
      expect(first['resource_kind'], 'note');
      expect(rows[0].sha256Hex, isNot(rows[1].sha256Hex));
    },
  );
  test(
    'unknown fields and unsupported protections block before payload generation',
    () async {
      for (final variant in ['review-required', 'missing-hash', 'high-cost']) {
        final original = await source(variant);
        final before = jsonEncode(original.sections);
        expect(
          () => LegacyImportRecords.fromExport(original, mapping(original)),
          throwsA(
            isA<LegacyRecordFailure>().having(
              (e) => e.reason,
              'reason',
              LegacyRecordReason.unresolvedSource,
            ),
          ),
        );
        expect(jsonEncode(original.sections), before);
      }
    },
  );
  test(
    'cross-source mapping is refused before records can be streamed',
    () async {
      final original = await source('known-formats'),
          other = await source('protected-formats');
      expect(
        () => LegacyImportRecords.fromExport(original, mapping(other)),
        throwsA(
          isA<LegacyRecordFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyRecordReason.sourceMismatch,
          ),
        ),
      );
    },
  );
  test(
    'pre-cancel and between-record cancellation leave the source unchanged',
    () async {
      final prepared = await records(),
          before = jsonEncode((await source('known-formats')).sections);
      expect(
        () => prepared.records(isCancelled: () => true).iterator.moveNext(),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      var cancelled = false;
      final iterator = prepared.records(isCancelled: () => cancelled).iterator;
      expect(iterator.moveNext(), isTrue);
      cancelled = true;
      expect(() => iterator.moveNext(), throwsA(isA<LegacyRecordsCancelled>()));
      expect(jsonEncode(prepared.source.sections), before);
      expect(
        () => prepared
            .labelRelations(isCancelled: () => true)
            .iterator
            .moveNext(),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
    },
  );
}
