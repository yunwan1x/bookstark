import 'dart:convert';
import 'local_legacy_go_export.dart';

enum LegacyImportKind {
  book,
  document,
  note,
  bookmark,
  task,
  topic,
  summary,
  topicResource,
  comment,
  label,
  friendLink,
  upload,
}

enum LegacyIdentityReason { invalidSource, duplicate, unresolved, ambiguous }

final class LegacyIdentityFailure implements Exception {
  const LegacyIdentityFailure(this.reason);
  final LegacyIdentityReason reason;
  @override
  String toString() => 'Legacy identity mapping failed';
}

/// An ID in a fresh, isolated candidate. It never identifies an existing store.
final class LegacyImportIdentity {
  LegacyImportIdentity._(
    this.kind,
    List<String> parts,
    this.localId,
    this.sourceSha256,
  ) : parts = List.unmodifiable(parts);
  final LegacyImportKind kind;
  final List<String> parts;
  final int localId;
  final String sourceSha256;
}

/// Deterministic ID allocation for an inspected Go ZIP only. No database writes,
/// content decoding, default editor type, or activation takes place here.
/// Raw database owner scopes must use a separate, explicitly selected dataset.
final class LegacyImportIdentities {
  LegacyImportIdentities._(this.sourceSha256);
  final String sourceSha256;
  final _entries = <LegacyImportIdentity>[];
  final _keys = <String, LegacyImportIdentity>{};
  final _aliases = <String, List<LegacyImportIdentity>>{};
  final _next = <LegacyImportKind, int>{};
  List<LegacyImportIdentity> get entries => List.unmodifiable(_entries);
  Map<LegacyImportKind, int> get counts => Map.unmodifiable(_next);

  static String _key(LegacyImportKind kind, List<String> parts) =>
      jsonEncode([kind.name, ...parts]);
  static String _alias(String kind, String target) =>
      jsonEncode([kind, target]);

  factory LegacyImportIdentities.fromExport(LegacyGoExport source) {
    const structural = {
      LegacyGoIssueCode.invalidIdentity,
      LegacyGoIssueCode.duplicateIdentity,
      LegacyGoIssueCode.unresolvedReference,
      LegacyGoIssueCode.ambiguousReference,
      LegacyGoIssueCode.cyclicHierarchy,
      LegacyGoIssueCode.unsupportedResourceKind,
    };
    if (source.issues.any((issue) => structural.contains(issue.code)) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(source.sourceSha256)) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.invalidSource);
    }
    final index = LegacyImportIdentities._(source.sourceSha256);
    List<Map<String, Object?>> rows(Object? value) =>
        value == null ? [] : (value as List).cast<Map<String, Object?>>();
    final sections = source.sections;
    for (final book in rows(sections['books.json'])) {
      final bookKey = book['identify'] as String;
      final entry = index._add(LegacyImportKind.book, [bookKey]);
      index._bind('book', bookKey, entry);
      for (final doc in rows(book['documents'])) {
        final docKey = doc['identify'] as String;
        final entry = index._add(LegacyImportKind.document, [bookKey, docKey]);
        // Keep all matches. A lossy slash-joined export alias may be ambiguous,
        // even though the internal tuple identities remain distinct.
        index._bind('document', '$bookKey/$docKey', entry);
      }
    }
    for (final note in rows(sections['blogs.json'])) {
      final collection = note['blog_type'] as String;
      if (collection != 'note' && collection != 'article') {
        throw const LegacyIdentityFailure(LegacyIdentityReason.invalidSource);
      }
      final identify = note['blog_identify'] as String;
      final entry = index._add(LegacyImportKind.note, [identify]);
      index._bind('blog', identify, entry);
      index._bind(collection, identify, entry);
    }
    for (final row in rows(sections['bookmarks.json'])) {
      final url = row['url'] as String;
      // Native active URLs are unique. Never merge two imported rows silently.
      final entry = index._add(LegacyImportKind.bookmark, [url]);
      index._bind('bookmark', url, entry);
    }
    for (final row in rows(sections['tasks.json'])) {
      final id = (row['task_id'] as int).toString();
      final entry = index._add(LegacyImportKind.task, [id]);
      index._bind('task', id, entry);
    }
    for (final topic in rows(sections['topics.json'])) {
      final topicId = (topic['topic_id'] as int).toString();
      index._add(LegacyImportKind.topic, [topicId]);
      for (final spec in [
        ('summaries', LegacyImportKind.summary, 'summary_id'),
        ('resources', LegacyImportKind.topicResource, 'topic_resource_id'),
        ('comments', LegacyImportKind.comment, 'comment_id'),
      ]) {
        final children = rows(topic[spec.$1]);
        for (var position = 0; position < children.length; position++) {
          final entry = index._add(spec.$2, [topicId, 'row', '$position']);
          final oldId = children[position][spec.$3] as int?;
          if (oldId != null && oldId != 0) {
            index._bindKey(spec.$2, [topicId, 'id', '$oldId'], entry);
          }
        }
      }
    }
    final labels = sections['labels.json'] as Map<String, Object?>;
    for (final row in rows(labels['labels'])) {
      index._add(LegacyImportKind.label, [row['label_name'] as String]);
    }
    final friends = rows(sections['friend_links.json']);
    for (var i = 0; i < friends.length; i++) {
      // Friend URLs/names are not unique in Go. Preserve every row.
      index._add(LegacyImportKind.friendLink, ['$i']);
    }
    for (final row in rows(sections['uploads.json'])) {
      index._add(LegacyImportKind.upload, [row['storage_path'] as String]);
    }
    return index;
  }

  LegacyImportIdentity _add(LegacyImportKind kind, List<String> parts) {
    if (parts.any((part) => part.isEmpty)) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.invalidSource);
    }
    final entry = LegacyImportIdentity._(
      kind,
      parts,
      (_next[kind] ?? 0) + 1,
      sourceSha256,
    );
    _bindKey(kind, parts, entry);
    _next[kind] = entry.localId;
    _entries.add(entry);
    return entry;
  }

  void _bindKey(
    LegacyImportKind kind,
    List<String> parts,
    LegacyImportIdentity value,
  ) {
    final key = _key(kind, parts);
    if (_keys.containsKey(key)) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.duplicate);
    }
    _keys[key] = value;
  }

  void _bind(String kind, String target, LegacyImportIdentity entry) {
    _aliases.putIfAbsent(_alias(kind, target), () => []).add(entry);
  }

  LegacyImportIdentity lookup(LegacyImportKind kind, List<String> parts) {
    final entry = _keys[_key(kind, parts)];
    if (entry == null) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.unresolved);
    }
    return entry;
  }

  LegacyImportIdentity resource(String kind, String target) {
    final matches = _aliases[_alias(kind, target)];
    if (matches == null || matches.isEmpty) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.unresolved);
    }
    if (matches.length != 1) {
      throw const LegacyIdentityFailure(LegacyIdentityReason.ambiguous);
    }
    return matches.single;
  }

  LegacyImportIdentity childAt(
    LegacyImportKind kind,
    int topicId,
    int position,
  ) => lookup(kind, ['$topicId', 'row', '$position']);
  LegacyImportIdentity childByOldId(
    LegacyImportKind kind,
    int topicId,
    int oldId,
  ) => lookup(kind, ['$topicId', 'id', '$oldId']);

  int documentParent(String bookIdentify, String parentIdentify) =>
      parentIdentify.isEmpty
      ? 0
      : lookup(LegacyImportKind.document, [
          bookIdentify,
          parentIdentify,
        ]).localId;
  int taskParent(int oldId) =>
      oldId == 0 ? 0 : lookup(LegacyImportKind.task, ['$oldId']).localId;
  int commentParent(int topicId, int oldId) => oldId == 0
      ? 0
      : childByOldId(LegacyImportKind.comment, topicId, oldId).localId;
}
