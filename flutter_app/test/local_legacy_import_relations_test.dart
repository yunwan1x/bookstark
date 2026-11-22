import 'dart:io';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_import_identities.dart';
import 'package:bookstark_flutter/core/local_legacy_import_relations.dart';
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
    root = await parent.createTemp('legacy-relations-');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<LegacyGoExport> source(String variant) async {
    final file = File('test/fixtures/legacy_zip/identity-$variant.zip');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final stage = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: hash,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    return LegacyGoExport.inspect(stage);
  }

  Future<LegacyImportRelations> plan(String variant) async {
    final value = await source(variant);
    return LegacyImportRelations.fromExport(
      value,
      LegacyImportIdentities.fromExport(value),
    );
  }

  List<LegacyImportRelation> edges(
    LegacyImportRelations value,
    LegacyImportRelationKind kind,
  ) => value.edges.where((e) => e.kind == kind).toList();

  test(
    'all Go relationships bind to source-scoped fresh local identities',
    () async {
      final value = await plan('good');
      expect(value.edges.length, 20);
      expect(
        value.edges.every(
          (e) =>
              e.from.sourceSha256 == value.sourceSha256 &&
              e.to.sourceSha256 == value.sourceSha256,
        ),
        isTrue,
      );
      final parent = edges(
        value,
        LegacyImportRelationKind.documentParent,
      ).single;
      expect(parent.from.localId, 2);
      expect(parent.to.localId, 1);
      final task = edges(value, LegacyImportRelationKind.taskParent).single;
      expect(task.from.localId, 2);
      expect(task.to.localId, 1);
      expect(edges(value, LegacyImportRelationKind.taskTopic).length, 2);
      final targets = edges(value, LegacyImportRelationKind.resourceTarget);
      expect(targets[0].to.kind, LegacyImportKind.document);
      expect(targets[0].to.localId, 2);
      expect(targets[1].to.kind, LegacyImportKind.note);
      expect(targets[1].to.parts, ['article-id']);
      final label = edges(value, LegacyImportRelationKind.labelResource).single;
      expect(label.from.kind, LegacyImportKind.label);
      expect(label.to.parts, ['note-id']);
    },
  );
  test(
    'forward document, task and comment parents resolve after allocation',
    () async {
      final value = await plan('forward-parents');
      for (final kind in [
        LegacyImportRelationKind.documentParent,
        LegacyImportRelationKind.taskParent,
        LegacyImportRelationKind.commentParent,
      ]) {
        final edge = edges(value, kind).single;
        expect(edge.from.localId, 1);
        expect(edge.to.localId, 2);
      }
    },
  );
  test(
    'comment targets distinguish summary, resource and exact max64 task',
    () async {
      final summaries = await plan('good');
      expect(
        edges(summaries, LegacyImportRelationKind.commentTarget).every(
          (e) => e.to.kind == LegacyImportKind.summary && e.to.localId == 1,
        ),
        isTrue,
      );
      final value = await plan('comment-targets');
      final targets = edges(value, LegacyImportRelationKind.commentTarget);
      expect(targets.map((e) => e.to.kind).toList(), [
        LegacyImportKind.topicResource,
        LegacyImportKind.topicResource,
        LegacyImportKind.task,
      ]);
      expect(targets.last.to.parts, ['9223372036854775807']);
      expect(targets.last.to.localId, 1);
    },
  );
  test('repeated child IDs never bind comments to a different topic', () async {
    final value = await plan('cross-topic');
    expect(value.edges.length, 33);
    final comments = edges(value, LegacyImportRelationKind.commentTarget);
    expect(comments.take(3).map((e) => e.to.localId), everyElement(1));
    expect(comments.skip(3).map((e) => e.to.localId), everyElement(3));
    final parents = edges(value, LegacyImportRelationKind.commentParent);
    expect(parents.map((e) => [e.from.localId, e.to.localId]).toList(), [
      [2, 1],
      [5, 4],
    ]);
  });
  test(
    'tuple-owned chapters remain separate despite an ambiguous exported alias',
    () async {
      final value = await plan('tuple-alias');
      final owners = edges(value, LegacyImportRelationKind.documentBook);
      expect(owners.length, 4);
      expect(owners[2].from.parts, ['a/b', 'c']);
      expect(owners[3].from.parts, ['a', 'b/c']);
      expect(owners[2].to.parts, ['a/b']);
      expect(owners[3].to.parts, ['a']);
    },
  );
  test(
    'source mismatch fails before planning and result edges are immutable',
    () async {
      final first = await source('good'), other = await source('tuple-alias');
      expect(
        () => LegacyImportRelations.fromExport(
          first,
          LegacyImportIdentities.fromExport(other),
        ),
        throwsA(
          isA<LegacyIdentityFailure>().having(
            (e) => e.reason,
            'reason',
            LegacyIdentityReason.invalidSource,
          ),
        ),
      );
      final value = await plan('good');
      expect(() => value.edges.clear(), throwsUnsupportedError);
    },
  );
}
