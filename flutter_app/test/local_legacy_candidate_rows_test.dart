import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
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
    root = await parent.createTemp('legacy-rows-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyImportRecords> records([
    String variant = 'known-formats',
  ]) async {
    final file = File('test/fixtures/legacy_zip/identity-$variant.zip');
    final source = await LegacyGoExport.inspect(
      await LegacyZipStage.inspect(
        file,
        privateParent: root,
        expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
      ),
    );
    final real = LegacyFormatSource.fromInspection(source, scopeKey: 'b' * 32);
    final selected = LegacyFormatSelection(
      real,
      choices: {
        for (final item in real.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    return LegacyImportRecords.fromExport(
      source,
      LegacyImportMapping.fromRecipe(
        source,
        selected.toJson(),
        scopeKey: 'b' * 32,
      ),
    );
  }

  Future<LegacyCandidateRows> plan([String variant = 'known-formats']) async =>
      LegacyCandidateRows.fromRecords(await records(variant));
  List<LegacyNativeRow> rows(
    LegacyCandidateRows plan,
    LegacyNativeTable table,
  ) => plan.rows().where((r) => r.table == table).toList();

  test(
    'all supported primary families are planned and uploads remain explicit',
    () async {
      final value = await plan();
      expect(value.rows().length, 19);
      expect(value.counts.values.fold<int>(0, (a, b) => a + b), 19);
      expect(value.counts[LegacyNativeTable.notes], 2);
      expect(value.counts[LegacyNativeTable.documents], 2);
      expect(value.counts[LegacyNativeTable.comments], 3);
      expect(value.counts[LegacyNativeTable.friendLinks], 2);
      expect(value.pendingUploads, 1);
    },
  );
  test(
    'body BOM/CRLF, opaque complex JSON and original TEXT dates are unchanged',
    () async {
      final value = await plan(),
          before = jsonEncode((await records()).source.sections);
      final docs = rows(value, LegacyNativeTable.documents);
      expect(docs[0].values['markdown'], '\uFEFF# parent\r\n');
      expect(
        docs[1].values['markdown'],
        '{"type":"excalidraw","future":{"opaque":true}}',
      );
      expect(docs[1].values['doc_type'], 'drawing');
      expect(docs[0].values['modify_time'], '');
      expect(
        rows(value, LegacyNativeTable.notes)[0].values['content'],
        '\uFEFF# body\r\n',
      );
      expect(jsonEncode(value.records.source.sections), before);
    },
  );
  test(
    'all foreign IDs are remapped, including task max64 and comment parents',
    () async {
      final value = await plan();
      final docs = rows(value, LegacyNativeTable.documents);
      expect(docs[1].values['parent_id'], 1);
      expect(docs.every((r) => r.values['book_id'] == 1), isTrue);
      final tasks = rows(value, LegacyNativeTable.tasks);
      expect(tasks.map((r) => r.id).toList(), [1, 2]);
      expect(tasks[1].values['parent_id'], 1);
      expect(tasks.every((r) => r.values['topic_id'] == 1), isTrue);
      final resources = rows(value, LegacyNativeTable.resources);
      expect(resources[0].values['target_id'], 2);
      expect(resources[1].values['resource_type'], 'article');
      expect(resources[1].values['target_id'], 2);
      final comments = rows(value, LegacyNativeTable.comments);
      expect(comments.map((r) => r.values['parent_comment_id']).toList(), [
        0,
        1,
        0,
      ]);
      expect(comments.every((r) => r.values['target_id'] == 1), isTrue);
    },
  );
  test(
    'supported locked record keeps original body and hash without verification',
    () async {
      final value = await plan('protected-formats');
      final source =
          (value.records.source.sections['blogs.json'] as List).first as Map;
      final note = rows(value, LegacyNativeTable.notes).first.values;
      expect(note['content'], source['blog_content']);
      expect(note['password_hash'], source['password']);
      expect(note['is_pinned'], 1);
      expect(note['visibility'], 2);
      expect(note['legacy_version'], 3);
      expect(note['revision'], 1);
    },
  );
  test(
    'negative history time and max original version do not become local revision',
    () async {
      final note = rows(
        await plan('pre-epoch'),
        LegacyNativeTable.notes,
      ).first.values;
      expect(note['updated_at'], -1);
      expect(note['legacy_version'], 9223372036854775807);
      expect(note['revision'], 1);
      expect(note['create_time'], '1969-12-31T23:59:59.999999999Z');
    },
  );
  test(
    'tuple-scoped chapters receive safe globally distinct native identifies',
    () async {
      final value = await plan('tuple-native');
      final docs = rows(value, LegacyNativeTable.documents);
      expect(docs.length, 4);
      expect(docs.map((r) => r.values['identify']).toSet().length, 4);
      for (final row in [...docs, ...rows(value, LegacyNativeTable.books)]) {
        expect(
          row.values['identify'],
          matches(RegExp(r'^legacy-[bd]-[a-f0-9]{64}-[1-9]\d*$')),
        );
      }
      expect(docs[2].values['book_id'], 2);
      expect(docs[3].values['book_id'], 3);
    },
  );
  test(
    'label arrays use declared relations while duplicate source records survive',
    () async {
      final value = await plan('duplicate-label-relations');
      expect(
        rows(value, LegacyNativeTable.notes).first.values['labels'],
        '["资料"]',
      );
      expect(
        rows(value, LegacyNativeTable.books).single.values['labels'],
        '[]',
      );
      expect(value.records.labelRelations().length, 2);
      final original =
          (value.records.source.sections['books.json'] as List).single as Map;
      expect(original['label'], '资料');
    },
  );
  test(
    'native uniqueness, flag and row-size conflicts block without modifying source',
    () async {
      for (final pair in [
        ('duplicate-books-native', LegacyNativeRowReason.duplicateBookName),
        ('duplicate-articles', LegacyNativeRowReason.duplicateArticleTitle),
        ('invalid-flag', LegacyNativeRowReason.invalidFlag),
        ('duplicate-target', LegacyNativeRowReason.duplicateTopicTarget),
        ('large-inline', LegacyNativeRowReason.headerTooLarge),
      ]) {
        final source = await records(pair.$1),
            before = jsonEncode((await records(pair.$1)).source.sections);
        expect(
          () => LegacyCandidateRows.fromRecords(source),
          throwsA(
            isA<LegacyNativeRowFailure>().having(
              (e) => e.reason,
              'reason',
              pair.$2,
            ),
          ),
        );
        expect(jsonEncode(source.source.sections), before);
      }
    },
  );
  test('forward parents resolve before any table has been inserted', () async {
    final value = await plan('forward-native');
    expect(
      rows(value, LegacyNativeTable.documents).first.values['parent_id'],
      2,
    );
    expect(rows(value, LegacyNativeTable.tasks).first.values['parent_id'], 2);
    expect(
      rows(value, LegacyNativeTable.comments).first.values['parent_comment_id'],
      2,
    );
  });
  test(
    'plans are deterministic and all published row values and counts immutable',
    () async {
      final value = await plan();
      Object snapshot() =>
          value.rows().map((r) => [r.table.name, r.values]).toList();
      expect(snapshot(), snapshot());
      expect(() => value.counts.clear(), throwsUnsupportedError);
      expect(
        () => value.rows().first.values['book_name'] = 'replace',
        throwsUnsupportedError,
      );
      final friends = rows(value, LegacyNativeTable.friendLinks);
      expect(friends[0].values['link_url'], friends[1].values['link_url']);
      expect(friends.map((r) => r.id).toList(), [1, 2]);
      expect(friends[0].values['description'], 'keep');
    },
  );
  test(
    'large bodies bypass only the inline header limit and cancellation remains effective',
    () async {
      final source = await records('record-chunks');
      final value = LegacyCandidateRows.fromRecords(source);
      final note = rows(value, LegacyNativeTable.notes).first.values;
      expect(
        utf8.encode(note['content'] as String).length,
        greaterThan(2 * 1024 * 1024),
      );
      expect(
        () => LegacyCandidateRows.fromRecords(source, isCancelled: () => true),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      var cancelled = false;
      final iterator = value.rows(isCancelled: () => cancelled).iterator;
      expect(iterator.moveNext(), isTrue);
      cancelled = true;
      expect(() => iterator.moveNext(), throwsA(isA<LegacyRecordsCancelled>()));
    },
  );
}
