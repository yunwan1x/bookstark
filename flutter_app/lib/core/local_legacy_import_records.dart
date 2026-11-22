import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_go_export.dart';
import 'local_legacy_import_identities.dart';
import 'local_legacy_import_mapping.dart';

enum LegacyRecordReason { unresolvedSource, sourceMismatch, payloadTooLarge }

final class LegacyRecordFailure implements Exception {
  const LegacyRecordFailure(this.reason);
  final LegacyRecordReason reason;
  @override
  String toString() => 'Legacy source record cannot be prepared';
}

final class LegacyRecordsCancelled implements Exception {
  const LegacyRecordsCancelled();
}

final class LegacyRecordPayload {
  const LegacyRecordPayload._(
    this.identity,
    this.sourceOrdinal,
    this.json,
    this.sha256Hex,
    this.bytes,
  );
  final LegacyImportIdentity identity;
  final int sourceOrdinal;
  // Private-candidate storage data, never an error/report/UI description.
  final String json, sha256Hex;
  final int bytes;
}

final class LegacyLabelRelationPayload {
  const LegacyLabelRelationPayload._(
    this.sourceOrdinal,
    this.labelId,
    this.target,
    this.json,
    this.sha256Hex,
    this.bytes,
  );
  final int sourceOrdinal, labelId;
  final LegacyImportIdentity target;
  final String json, sha256Hex;
  final int bytes;
}

/// Streams one bounded original-field record at a time. No SQL, files, unlock,
/// active-store writes, or approval of unknown fields takes place here.
final class LegacyImportRecords {
  LegacyImportRecords._(this.source, this.mapping);
  final LegacyGoExport source;
  final LegacyImportMapping mapping;
  static const maxPayloadBytes = 64 * 1024 * 1024 + 64 * 1024;

  factory LegacyImportRecords.fromExport(
    LegacyGoExport source,
    LegacyImportMapping mapping,
  ) {
    if (source.sourceSha256 != mapping.sourceSha256) {
      throw const LegacyRecordFailure(LegacyRecordReason.sourceMismatch);
    }
    const handled = {
      LegacyGoIssueCode.editorTypeMissing,
      LegacyGoIssueCode.protectedContent,
    };
    if (source.issues.any((issue) => !handled.contains(issue.code))) {
      // Unknown fields must be classified by a new reviewed contract first.
      // In particular, do not blindly copy unknown account/session secrets.
      throw const LegacyRecordFailure(LegacyRecordReason.unresolvedSource);
    }
    return LegacyImportRecords._(source, mapping);
  }
  List<Map<String, Object?>> _rows(Object? value) =>
      value == null ? [] : (value as List).cast<Map<String, Object?>>();
  void _check(bool Function()? cancelled) {
    if (cancelled?.call() == true) throw const LegacyRecordsCancelled();
  }

  (String, String, int) _encode(
    Map<String, Object?> value,
    bool Function()? cancelled,
  ) {
    _check(cancelled);
    final text = jsonEncode(value);
    final bytes = utf8.encode(text);
    if (bytes.length > maxPayloadBytes) {
      throw const LegacyRecordFailure(LegacyRecordReason.payloadTooLarge);
    }
    final digest = sha256.convert(bytes).toString();
    _check(cancelled);
    return (text, digest, bytes.length);
  }

  LegacyRecordPayload _record(
    LegacyImportIdentity entry,
    Map<String, Object?> row,
    int ordinal,
    bool Function()? cancelled, {
    LegacyImportIdentity? parent,
    List<String> children = const [],
  }) {
    final data = _encode({
      'version': 1, 'source_sha256': source.sourceSha256,
      'format_recipe_sha256': mapping.recipeSha256,
      'kind': entry.kind.name, 'local_id': entry.localId,
      'source_key': entry.parts, 'source_ordinal': ordinal,
      if (parent != null)
        'parent': {'kind': parent.kind.name, 'local_id': parent.localId},
      if (children.isNotEmpty)
        'child_sections': {
          for (final name in children)
            name: {
              'present': row.containsKey(name),
              'count': _rows(row[name]).length,
            },
        },
      // Children have their own source-ordered records. Never duplicate a whole
      // book/topic's content into its header record.
      'fields': {
        for (final e in row.entries)
          if (!children.contains(e.key)) e.key: e.value,
      },
    }, cancelled);
    return LegacyRecordPayload._(entry, ordinal, data.$1, data.$2, data.$3);
  }

  Iterable<LegacyRecordPayload> records({bool Function()? isCancelled}) sync* {
    _check(isCancelled);
    final ids = mapping.identities, sections = source.sections;
    final books = _rows(sections['books.json']);
    for (var i = 0; i < books.length; i++) {
      final row = books[i], key = row['identify'] as String;
      final owner = ids.lookup(LegacyImportKind.book, [key]);
      yield _record(owner, row, i, isCancelled, children: const ['documents']);
      final docs = _rows(row['documents']);
      for (var j = 0; j < docs.length; j++) {
        yield _record(
          ids.lookup(LegacyImportKind.document, [
            key,
            docs[j]['identify'] as String,
          ]),
          docs[j],
          j,
          isCancelled,
          parent: owner,
        );
      }
    }
    for (final spec in [
      ('blogs.json', LegacyImportKind.note, 'blog_identify'),
      ('bookmarks.json', LegacyImportKind.bookmark, 'url'),
      ('tasks.json', LegacyImportKind.task, 'task_id'),
    ]) {
      final rows = _rows(sections[spec.$1]);
      for (var i = 0; i < rows.length; i++) {
        yield _record(
          ids.lookup(spec.$2, [rows[i][spec.$3].toString()]),
          rows[i],
          i,
          isCancelled,
        );
      }
    }
    final topics = _rows(sections['topics.json']);
    for (var i = 0; i < topics.length; i++) {
      final row = topics[i], oldId = row['topic_id'] as int;
      final owner = ids.lookup(LegacyImportKind.topic, ['$oldId']);
      yield _record(
        owner,
        row,
        i,
        isCancelled,
        children: const ['summaries', 'resources', 'comments'],
      );
      for (final spec in [
        ('summaries', LegacyImportKind.summary),
        ('resources', LegacyImportKind.topicResource),
        ('comments', LegacyImportKind.comment),
      ]) {
        final children = _rows(row[spec.$1]);
        for (var j = 0; j < children.length; j++) {
          yield _record(
            ids.childAt(spec.$2, oldId, j),
            children[j],
            j,
            isCancelled,
            parent: owner,
          );
        }
      }
    }
    final labels = source.sections['labels.json'] as Map<String, Object?>;
    final labelRows = _rows(labels['labels']);
    for (var i = 0; i < labelRows.length; i++) {
      final row = labelRows[i];
      yield _record(
        ids.lookup(LegacyImportKind.label, [row['label_name'] as String]),
        row,
        i,
        isCancelled,
      );
    }
    final friends = _rows(sections['friend_links.json']);
    for (var i = 0; i < friends.length; i++) {
      yield _record(
        ids.lookup(LegacyImportKind.friendLink, ['$i']),
        friends[i],
        i,
        isCancelled,
      );
    }
    final uploads = _rows(sections['uploads.json']);
    for (var i = 0; i < uploads.length; i++) {
      final row = uploads[i];
      yield _record(
        ids.lookup(LegacyImportKind.upload, [row['storage_path'] as String]),
        row,
        i,
        isCancelled,
      );
    }
  }

  Iterable<LegacyLabelRelationPayload> labelRelations({
    bool Function()? isCancelled,
  }) sync* {
    _check(isCancelled);
    final labels = source.sections['labels.json'] as Map<String, Object?>;
    final rows = _rows(labels['relations']), ids = mapping.identities;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final label = ids.lookup(LegacyImportKind.label, [
        row['label_name'] as String,
      ]);
      final target = ids.resource(
        row['resource_type'] as String,
        row['resource_identify'] as String,
      );
      final data = _encode({
        'version': 1,
        'source_sha256': source.sourceSha256,
        'format_recipe_sha256': mapping.recipeSha256,
        'source_ordinal': i,
        'label_id': label.localId,
        'resource_kind': target.kind.name,
        'resource_id': target.localId,
        'fields': row,
      }, isCancelled);
      yield LegacyLabelRelationPayload._(
        i,
        label.localId,
        target,
        data.$1,
        data.$2,
        data.$3,
      );
    }
  }
}
