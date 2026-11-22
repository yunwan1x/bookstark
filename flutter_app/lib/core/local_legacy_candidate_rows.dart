import 'dart:convert';
import 'local_legacy_import_identities.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_import_time.dart';

enum LegacyNativeTable {
  notes('notes', 'id'),
  books('books', 'book_id'),
  documents('documents', 'document_id'),
  bookmarks('bookmarks', 'bookmark_id'),
  tasks('tasks', 'task_id'),
  topics('topics', 'topic_id'),
  summaries('topic_summaries', 'summary_id'),
  resources('topic_resources', 'topic_resource_id'),
  comments('topic_comments', 'comment_id'),
  labels('local_labels', 'label_id'),
  friendLinks('legacy_friend_links', 'link_id');

  const LegacyNativeTable(this.sqlName, this.idColumn);
  final String sqlName, idColumn;
}

enum LegacyNativeRowReason {
  duplicateBookName,
  duplicateArticleTitle,
  duplicateTopicTarget,
  invalidFlag,
  headerTooLarge,
}

final class LegacyNativeRowFailure implements Exception {
  const LegacyNativeRowFailure(this.reason);
  final LegacyNativeRowReason reason;
  @override
  String toString() => 'Legacy primary rows require review';
}

final class LegacyNativeRow {
  LegacyNativeRow._(this.table, Map<String, Object?> values)
    : values = Map.unmodifiable(values);
  final LegacyNativeTable table;
  final Map<String, Object?> values;
  int get id => values[table.idColumn] as int;
}

/// Pure, repeatable row plan for a NEW candidate. Does not map/copy uploads,
/// validate editor-engine bodies, write SQL, publish files or activate data.
final class LegacyCandidateRows {
  LegacyCandidateRows._(this.records);
  final LegacyImportRecords records;
  final _labels = <(LegacyImportKind, int), Set<String>>{};
  final _counts = <LegacyNativeTable, int>{};
  static const maxInlineBytes = 256 * 1024;
  Map<LegacyNativeTable, int> get counts => Map.unmodifiable(_counts);
  int get pendingUploads => records.source.counts['uploads']!;
  List<Map<String, Object?>> _rows(Object? value) =>
      value == null ? [] : (value as List).cast<Map<String, Object?>>();
  void _check(bool Function()? cancelled) {
    if (cancelled?.call() == true) {
      throw const LegacyRecordsCancelled();
    }
  }

  int _flag(Object? value) {
    if (value == true || value == 1) {
      return 1;
    }
    if (value == false || value == 0) {
      return 0;
    }
    throw const LegacyNativeRowFailure(LegacyNativeRowReason.invalidFlag);
  }

  String _tags(LegacyImportKind kind, int id) =>
      jsonEncode(_labels[(kind, id)]?.toList() ?? const <String>[]);
  String _identify(String prefix, int id) =>
      'legacy-$prefix-${records.source.sourceSha256}-$id';
  LegacyNativeRow _row(
    LegacyNativeTable table,
    Map<String, Object?> values,
    bool Function()? cancelled,
  ) {
    _check(cancelled);
    var bytes = 0;
    for (final item in values.entries) {
      if (table == LegacyNativeTable.notes && item.key == 'content' ||
          table == LegacyNativeTable.documents && item.key == 'markdown') {
        continue;
      }
      if (item.value is String) {
        bytes += utf8.encode(item.value as String).length;
      }
      if (bytes > maxInlineBytes) {
        throw const LegacyNativeRowFailure(
          LegacyNativeRowReason.headerTooLarge,
        );
      }
    }
    return LegacyNativeRow._(table, values);
  }

  factory LegacyCandidateRows.fromRecords(
    LegacyImportRecords records, {
    bool Function()? isCancelled,
  }) {
    final plan = LegacyCandidateRows._(records),
        source = records.source.sections,
        ids = records.mapping.identities;
    plan._check(isCancelled);
    final labels = source['labels.json'] as Map<String, Object?>;
    for (final row in plan._rows(labels['relations'])) {
      plan._check(isCancelled);
      final target = ids.resource(
        row['resource_type'] as String,
        row['resource_identify'] as String,
      );
      plan._labels
          .putIfAbsent((target.kind, target.localId), () => {})
          .add(row['label_name'] as String);
    }
    final books = <String>{},
        articles = <String>{},
        targets = <(int, String, int)>{};
    for (final row in plan.rows(isCancelled: isCancelled)) {
      if (row.table == LegacyNativeTable.books &&
          !books.add(row.values['book_name'] as String)) {
        throw const LegacyNativeRowFailure(
          LegacyNativeRowReason.duplicateBookName,
        );
      }
      if (row.table == LegacyNativeTable.notes &&
          row.values['collection'] == 'article' &&
          !articles.add(row.values['title'] as String)) {
        throw const LegacyNativeRowFailure(
          LegacyNativeRowReason.duplicateArticleTitle,
        );
      }
      if (row.table == LegacyNativeTable.resources &&
          !targets.add((
            row.values['topic_id'] as int,
            row.values['resource_type'] as String,
            row.values['target_id'] as int,
          ))) {
        throw const LegacyNativeRowFailure(
          LegacyNativeRowReason.duplicateTopicTarget,
        );
      }
      plan._counts.update(row.table, (n) => n + 1, ifAbsent: () => 1);
    }
    return plan;
  }
  Iterable<LegacyNativeRow> rows({bool Function()? isCancelled}) sync* {
    _check(isCancelled);
    final sections = records.source.sections, ids = records.mapping.identities;
    final exported =
        (sections['manifest.json'] as Map)['export_time'] as String;
    for (final row in _rows(sections['books.json'])) {
      final old = row['identify'] as String,
          book = ids.lookup(LegacyImportKind.book, [old]);
      final docs = _rows(row['documents']);
      yield _row(LegacyNativeTable.books, {
        'book_id': book.localId,
        'book_name': row['book_name'],
        'description': row['description'],
        'identify': _identify('b', book.localId),
        'labels': _tags(LegacyImportKind.book, book.localId),
        'doc_count': docs.length,
        'create_time': row['create_time'],
        'modify_time': row['modify_time'],
        'deleted': 0,
      }, isCancelled);
      for (final doc in docs) {
        final id = ids.lookup(LegacyImportKind.document, [
          old,
          doc['identify'] as String,
        ]).localId;
        yield _row(LegacyNativeTable.documents, {
          'document_id': id,
          'book_id': book.localId,
          'document_name': doc['document_name'],
          'identify': _identify('d', id),
          'parent_id': ids.documentParent(
            old,
            doc['parent_identify'] as String,
          ),
          'order_sort': doc['order_sort'],
          'doc_type': records.mapping.documentFormats[id]!.name,
          'markdown': doc['markdown'],
          'create_time': doc['create_time'],
          'modify_time': doc['modify_time'],
          'labels': _tags(LegacyImportKind.document, id),
          'deleted': 0,
          'revision': 1,
        }, isCancelled);
      }
    }
    for (final row in _rows(sections['blogs.json'])) {
      final id = ids.lookup(LegacyImportKind.note, [
        row['blog_identify'] as String,
      ]).localId;
      yield _row(LegacyNativeTable.notes, {
        'id': id,
        'title': row['blog_title'],
        'content': row['blog_content'],
        'updated_at': resolveLegacyImportTimestamp(
          modified: row['modify_time'] as String,
          created: row['create_time'] as String,
          exported: exported,
        ),
        'deleted': 0,
        'labels': _tags(LegacyImportKind.note, id),
        'collection': row['blog_type'],
        'editor_type': records.mapping.noteFormats[id]!.name,
        'password_hash': row['password'],
        'is_pinned': _flag(row['is_pinned']),
        'pin_order': row['pin_order'],
        'visibility': row['visibility'],
        'legacy_version': row['version'],
        'create_time': row['create_time'],
        'revision': 1,
      }, isCancelled);
    }
    for (final row in _rows(sections['bookmarks.json'])) {
      final id = ids.lookup(LegacyImportKind.bookmark, [
        row['url'] as String,
      ]).localId;
      yield _row(LegacyNativeTable.bookmarks, {
        'bookmark_id': id,
        'title': row['title'],
        'url': row['url'],
        'description': row['description'],
        'favicon': row['favicon'],
        'labels': _tags(LegacyImportKind.bookmark, id),
        'is_public': _flag(row['is_public']),
        'is_pinned': _flag(row['is_pinned']),
        'nav_visible': _flag(row['nav_visible']),
        'order_sort': row['order_sort'],
        'deleted': 0,
        'create_time': resolveLegacyImportTimestamp(
          modified: '',
          created: row['create_time'] as String,
          exported: exported,
        ),
        'modify_time': resolveLegacyImportTimestamp(
          modified: row['modify_time'] as String,
          created: row['create_time'] as String,
          exported: exported,
        ),
      }, isCancelled);
    }
    for (final row in _rows(sections['tasks.json'])) {
      final topic = row['topic_id'] as int? ?? 0;
      yield _row(LegacyNativeTable.tasks, {
        'task_id': ids.lookup(LegacyImportKind.task, [
          (row['task_id'] as int).toString(),
        ]).localId,
        'content': row['content'],
        'due_date': row['due_date'],
        'done': _flag(row['done']),
        'parent_id': ids.taskParent(row['parent_id'] as int),
        'topic_id': topic == 0
            ? 0
            : ids.lookup(LegacyImportKind.topic, ['$topic']).localId,
        'create_time': row['create_time'],
        'modify_time': row['modify_time'],
        'complete_time': row['complete_time'],
        'deleted': 0,
      }, isCancelled);
    }
    final topics = _rows(sections['topics.json']);
    for (final row in topics) {
      final old = row['topic_id'] as int,
          topic = ids.lookup(LegacyImportKind.topic, ['$old']).localId;
      yield _row(LegacyNativeTable.topics, {
        'topic_id': topic,
        'title': row['title'],
        'question': row['question'],
        'is_pinned': _flag(row['is_pinned']),
        'create_time': row['create_time'],
        'modify_time': row['modify_time'],
        'deleted': 0,
      }, isCancelled);
      final summaries = _rows(row['summaries']);
      for (var i = 0; i < summaries.length; i++) {
        final child = summaries[i];
        yield _row(LegacyNativeTable.summaries, {
          'summary_id': ids.childAt(LegacyImportKind.summary, old, i).localId,
          'topic_id': topic,
          'content': child['content'],
          'summary_type': child['summary_type'],
          'order_sort': child['order_sort'],
          'create_time': child['create_time'],
          'modify_time': child['modify_time'],
        }, isCancelled);
      }
      final resources = _rows(row['resources']);
      for (var i = 0; i < resources.length; i++) {
        final child = resources[i], kind = child['resource_type'] as String;
        yield _row(LegacyNativeTable.resources, {
          'topic_resource_id': ids
              .childAt(LegacyImportKind.topicResource, old, i)
              .localId,
          'topic_id': topic,
          'resource_type': kind,
          'target_id': ids
              .resource(kind, child['target_identify'] as String)
              .localId,
          'title_snapshot': child['title_snapshot'],
          'desc_snapshot': child['desc_snapshot'],
          'order_sort': child['order_sort'],
          'create_time': child['create_time'],
        }, isCancelled);
      }
      final comments = _rows(row['comments']);
      for (var i = 0; i < comments.length; i++) {
        final child = comments[i], target = child['target_id'] as int;
        final localTarget = switch (child['target_type']) {
          'summary' =>
            ids.childByOldId(LegacyImportKind.summary, old, target).localId,
          'resource' =>
            ids
                .childByOldId(LegacyImportKind.topicResource, old, target)
                .localId,
          'task' => ids.lookup(LegacyImportKind.task, ['$target']).localId,
          _ => throw const LegacyIdentityFailure(
            LegacyIdentityReason.invalidSource,
          ),
        };
        yield _row(LegacyNativeTable.comments, {
          'comment_id': ids.childAt(LegacyImportKind.comment, old, i).localId,
          'topic_id': topic,
          'target_type': child['target_type'],
          'target_id': localTarget,
          'content': child['content'],
          'parent_comment_id': ids.commentParent(
            old,
            child['parent_comment_id'] as int? ?? 0,
          ),
          'create_time': child['create_time'],
          'modify_time': child['modify_time'],
        }, isCancelled);
      }
    }
    final labels = sections['labels.json'] as Map<String, Object?>;
    for (final row in _rows(labels['labels'])) {
      yield _row(LegacyNativeTable.labels, {
        'label_id': ids.lookup(LegacyImportKind.label, [
          row['label_name'] as String,
        ]).localId,
        'label_name': row['label_name'],
      }, isCancelled);
    }
    final friends = _rows(sections['friend_links.json']);
    for (var i = 0; i < friends.length; i++) {
      final row = friends[i];
      yield _row(LegacyNativeTable.friendLinks, {
        'link_id': ids.lookup(LegacyImportKind.friendLink, ['$i']).localId,
        'source_sha256': records.source.sourceSha256,
        'link_name': row['link_name'],
        'link_url': row['link_url'],
        'group_name': row['group_name'] ?? '',
        'group_order': row['group_order'] ?? 0,
        'qr_code': row['qr_code'] ?? '',
        'description': row['description'] ?? '',
        'sort_weight': row['sort_weight'],
        'is_enabled': _flag(row['is_enabled']),
        'create_time': row['create_time'],
        'modify_time': row['modify_time'],
      }, isCancelled);
    }
  }
}
