import 'local_legacy_go_export.dart';
import 'local_legacy_import_identities.dart';

enum LegacyImportRelationKind {
  documentBook,
  documentParent,
  taskParent,
  taskTopic,
  summaryTopic,
  resourceTopic,
  resourceTarget,
  commentTopic,
  commentTarget,
  commentParent,
  labelResource,
}

final class LegacyImportRelation {
  const LegacyImportRelation(this.kind, this.from, this.to);
  final LegacyImportRelationKind kind;
  final LegacyImportIdentity from, to;
}

/// Pure source-bound foreign-key plan. Original rows, including duplicate label
/// relations and unknown metadata, remain owned by the immutable source export.
final class LegacyImportRelations {
  LegacyImportRelations._(this.sourceSha256, List<LegacyImportRelation> edges)
    : edges = List.unmodifiable(edges);
  final String sourceSha256;
  final List<LegacyImportRelation> edges;

  factory LegacyImportRelations.fromExport(
    LegacyGoExport source,
    LegacyImportIdentities identities,
  ) {
    if (source.sourceSha256 != identities.sourceSha256) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.invalidSource);
    }
    final edges = <LegacyImportRelation>[];
    void add(
      LegacyImportRelationKind kind,
      LegacyImportIdentity from,
      LegacyImportIdentity to,
    ) {
      if (from.sourceSha256 != source.sourceSha256 ||
          to.sourceSha256 != source.sourceSha256) {
        throw const LegacyIdentityFailure(LegacyIdentityReason.invalidSource);
      }
      edges.add(LegacyImportRelation(kind, from, to));
    }

    List<Map<String, Object?>> rows(Object? value) =>
        value == null ? [] : (value as List).cast<Map<String, Object?>>();
    final sections = source.sections;
    for (final book in rows(sections['books.json'])) {
      final identify = book['identify'] as String;
      final owner = identities.lookup(LegacyImportKind.book, [identify]);
      for (final doc in rows(book['documents'])) {
        final entry = identities.lookup(LegacyImportKind.document, [
          identify,
          doc['identify'] as String,
        ]);
        add(LegacyImportRelationKind.documentBook, entry, owner);
        final parent = doc['parent_identify'] as String;
        if (parent.isNotEmpty) {
          add(
            LegacyImportRelationKind.documentParent,
            entry,
            identities.lookup(LegacyImportKind.document, [identify, parent]),
          );
        }
      }
    }
    for (final task in rows(sections['tasks.json'])) {
      final entry = identities.lookup(LegacyImportKind.task, [
        (task['task_id'] as int).toString(),
      ]);
      final parent = task['parent_id'] as int;
      if (parent != 0) {
        add(
          LegacyImportRelationKind.taskParent,
          entry,
          identities.lookup(LegacyImportKind.task, ['$parent']),
        );
      }
      final topic = task['topic_id'] as int? ?? 0;
      if (topic != 0) {
        add(
          LegacyImportRelationKind.taskTopic,
          entry,
          identities.lookup(LegacyImportKind.topic, ['$topic']),
        );
      }
    }
    for (final topic in rows(sections['topics.json'])) {
      final oldId = topic['topic_id'] as int;
      final owner = identities.lookup(LegacyImportKind.topic, ['$oldId']);
      final summaries = rows(topic['summaries']);
      for (var i = 0; i < summaries.length; i++) {
        add(
          LegacyImportRelationKind.summaryTopic,
          identities.childAt(LegacyImportKind.summary, oldId, i),
          owner,
        );
      }
      final resources = rows(topic['resources']);
      for (var i = 0; i < resources.length; i++) {
        final entry = identities.childAt(
          LegacyImportKind.topicResource,
          oldId,
          i,
        );
        add(LegacyImportRelationKind.resourceTopic, entry, owner);
        add(
          LegacyImportRelationKind.resourceTarget,
          entry,
          identities.resource(
            resources[i]['resource_type'] as String,
            resources[i]['target_identify'] as String,
          ),
        );
      }
      final comments = rows(topic['comments']);
      for (var i = 0; i < comments.length; i++) {
        final row = comments[i];
        final entry = identities.childAt(LegacyImportKind.comment, oldId, i);
        add(LegacyImportRelationKind.commentTopic, entry, owner);
        final targetId = row['target_id'] as int;
        final target = switch (row['target_type']) {
          'summary' => identities.childByOldId(
            LegacyImportKind.summary,
            oldId,
            targetId,
          ),
          'resource' => identities.childByOldId(
            LegacyImportKind.topicResource,
            oldId,
            targetId,
          ),
          'task' => identities.lookup(LegacyImportKind.task, ['$targetId']),
          _ => throw const LegacyIdentityFailure(
            LegacyIdentityReason.invalidSource,
          ),
        };
        add(LegacyImportRelationKind.commentTarget, entry, target);
        final parentId = row['parent_comment_id'] as int? ?? 0;
        if (parentId != 0) {
          add(
            LegacyImportRelationKind.commentParent,
            entry,
            identities.childByOldId(LegacyImportKind.comment, oldId, parentId),
          );
        }
      }
    }
    final labels = sections['labels.json'] as Map<String, Object?>;
    for (final row in rows(labels['relations'])) {
      add(
        LegacyImportRelationKind.labelResource,
        identities.lookup(LegacyImportKind.label, [
          row['label_name'] as String,
        ]),
        identities.resource(
          row['resource_type'] as String,
          row['resource_identify'] as String,
        ),
      );
    }
    return LegacyImportRelations._(source.sourceSha256, edges);
  }
}
