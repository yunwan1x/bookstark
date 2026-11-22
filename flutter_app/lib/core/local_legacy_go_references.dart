import 'local_legacy_go_issue.dart';

/// Call only after typed section validation; no database or filesystem I/O.
List<LegacyGoIssue> inspectLegacyGoReferences(Map<String, Object?> sections) {
  final scan = _References();
  scan.inspect(sections);
  return scan.issues;
}

typedef _Row = Map<String, Object?>;

final class _References {
  final issues = <LegacyGoIssue>[];
  void issue(LegacyGoIssueCode code, String location) =>
      issues.add(LegacyGoIssue(code, location));
  List<_Row> rows(Object? value) =>
      value == null ? [] : (value as List).cast<_Row>();

  Map<Object, _Row> identities(
    List<_Row> values,
    String field,
    String location, {
    bool optional = false,
  }) {
    final result = <Object, _Row>{};
    for (var i = 0; i < values.length; i++) {
      final key = values[i][field];
      if (optional && (key == null || key == 0)) continue;
      if (key is! String && key is! int ||
          key is String && key.isEmpty ||
          key is int && key <= 0) {
        issue(LegacyGoIssueCode.invalidIdentity, '$location[$i]');
      } else if (result.containsKey(key)) {
        issue(LegacyGoIssueCode.duplicateIdentity, '$location[$i]');
      } else {
        result[key!] = values[i];
      }
    }
    return result;
  }

  void tree(List<_Row> values, String id, String parent, String location) {
    final parents = <Object, Object?>{};
    final locations = <Object, String>{};
    for (var i = 0; i < values.length; i++) {
      final key = values[i][id];
      if (key == null || key == 0 || key == '' || parents.containsKey(key)) {
        continue;
      }
      final above = values[i][parent];
      parents[key] = above == null || above == '' || above == 0 ? null : above;
      locations[key] = '$location[$i]';
    }
    // Linear and iterative even for a 100000-node chain or cycle.
    final done = <Object>{};
    for (final start in parents.keys) {
      if (done.contains(start)) continue;
      final path = <Object>{};
      Object? current = start;
      while (current != null && !done.contains(current)) {
        if (!parents.containsKey(current)) {
          issue(LegacyGoIssueCode.unresolvedReference, locations[path.last]!);
          break;
        }
        if (!path.add(current)) {
          issue(LegacyGoIssueCode.cyclicHierarchy, locations[current]!);
          break;
        }
        current = parents[current];
      }
      done.addAll(path);
    }
  }

  void inspect(Map<String, Object?> sections) {
    final books = rows(sections['books.json']);
    final blogs = rows(sections['blogs.json']);
    final bookmarks = rows(sections['bookmarks.json']);
    final tasks = rows(sections['tasks.json']);
    final topics = rows(sections['topics.json']);
    final labels = sections['labels.json'] as _Row;
    final bookIds = identities(books, 'identify', 'books');
    final blogIds = identities(blogs, 'blog_identify', 'blogs');
    final taskIds = identities(tasks, 'task_id', 'tasks');
    final topicIds = identities(topics, 'topic_id', 'topics');
    final labelIds = identities(
      rows(labels['labels']),
      'label_name',
      'labels.labels',
    );
    final documentIds = <String, List<_Row>>{};
    final bookmarkIds = <String, List<_Row>>{};
    for (final bookmark in bookmarks) {
      bookmarkIds
          .putIfAbsent(bookmark['url'] as String, () => [])
          .add(bookmark);
    }
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      final docs = rows(book['documents']);
      identities(docs, 'identify', 'books[$i].documents');
      tree(docs, 'identify', 'parent_identify', 'books[$i].documents');
      for (final doc in docs) {
        final composite = '${book['identify']}/${doc['identify']}';
        documentIds.putIfAbsent(composite, () => []).add(doc);
      }
    }
    tree(tasks, 'task_id', 'parent_id', 'tasks');
    for (var i = 0; i < tasks.length; i++) {
      final topic = tasks[i]['topic_id'];
      if (topic != null && topic != 0 && !topicIds.containsKey(topic)) {
        issue(LegacyGoIssueCode.unresolvedReference, 'tasks[$i].topic_id');
      }
    }
    void lookup(String kind, String target, String location) {
      bool exists;
      switch (kind) {
        case 'book':
          exists = bookIds.containsKey(target);
        case 'blog':
          exists = blogIds.containsKey(target);
        case 'note':
        case 'article':
          exists = blogIds[target]?['blog_type'] == kind;
        case 'document':
          final matches = documentIds[target] ?? [];
          if (matches.length > 1) {
            issue(LegacyGoIssueCode.ambiguousReference, location);
            return;
          }
          exists = matches.length == 1;
        case 'bookmark':
          final matches = bookmarkIds[target] ?? [];
          if (matches.length > 1) {
            issue(LegacyGoIssueCode.ambiguousReference, location);
            return;
          }
          exists = matches.length == 1;
        case 'task':
          final id = int.tryParse(target);
          exists =
              id != null && id.toString() == target && taskIds.containsKey(id);
        default:
          issue(LegacyGoIssueCode.unsupportedResourceKind, location);
          return;
      }
      if (!exists) issue(LegacyGoIssueCode.unresolvedReference, location);
    }

    final relations = rows(labels['relations']);
    for (var i = 0; i < relations.length; i++) {
      final relation = relations[i];
      final location = 'labels.relations[$i]';
      if (!labelIds.containsKey(relation['label_name'])) {
        issue(LegacyGoIssueCode.unresolvedReference, location);
      }
      final kind = relation['resource_type'] as String;
      if (!{'book', 'blog', 'document', 'bookmark'}.contains(kind)) {
        issue(LegacyGoIssueCode.unsupportedResourceKind, location);
      } else {
        lookup(kind, relation['resource_identify'] as String, location);
      }
    }
    for (var i = 0; i < topics.length; i++) {
      final topic = topics[i];
      final summaries = rows(topic['summaries']);
      final resources = rows(topic['resources']);
      final comments = rows(topic['comments']);
      final base = 'topics[$i]';
      final summaryIds = identities(
        summaries,
        'summary_id',
        '$base.summaries',
        optional: true,
      );
      final resourceIds = identities(
        resources,
        'topic_resource_id',
        '$base.resources',
        optional: true,
      );
      final commentIds = identities(
        comments,
        'comment_id',
        '$base.comments',
        optional: true,
      );
      tree(comments, 'comment_id', 'parent_comment_id', '$base.comments');
      for (var j = 0; j < resources.length; j++) {
        final resource = resources[j];
        final location = '$base.resources[$j]';
        final kind = resource['resource_type'] as String;
        if (!{
          'note',
          'article',
          'document',
          'bookmark',
          'task',
        }.contains(kind)) {
          issue(LegacyGoIssueCode.unsupportedResourceKind, location);
        } else {
          lookup(kind, resource['target_identify'] as String, location);
        }
      }
      for (var j = 0; j < comments.length; j++) {
        final comment = comments[j];
        final target = comment['target_id'];
        final kind = comment['target_type'];
        final location = '$base.comments[$j]';
        final valid = switch (kind) {
          'summary' => summaryIds.containsKey(target),
          'resource' => resourceIds.containsKey(target),
          'task' => taskIds[target]?['topic_id'] == topic['topic_id'],
          _ => null,
        };
        if (valid == null) {
          issue(LegacyGoIssueCode.unsupportedResourceKind, location);
        } else if (!valid) {
          issue(LegacyGoIssueCode.unresolvedReference, location);
        }
        final parent = comment['parent_comment_id'];
        if (parent != null && parent != 0) {
          final parentRow = commentIds[parent];
          if (parentRow == null ||
              parentRow['target_type'] != kind ||
              parentRow['target_id'] != target) {
            issue(LegacyGoIssueCode.unresolvedReference, location);
          }
        }
      }
    }
  }
}
