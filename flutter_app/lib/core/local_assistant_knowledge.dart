import 'local_protected_content.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'assistant_repository.dart';
import 'local_store.dart';
import 'search_repository.dart';

enum LocalKnowledgeIssue {
  permission,
  retired,
  invalid,
  notFound,
  protected,
  unreadable,
}

final class LocalKnowledgeFailure implements Exception {
  const LocalKnowledgeFailure(this.issue);
  final LocalKnowledgeIssue issue;
}

final class LocalKnowledgeSearch {
  const LocalKnowledgeSearch(this.results, {required this.more});
  final List<Map<String, Object?>> results;
  final bool more;
}

final class _Source {
  const _Source(
    this.kind,
    this.table,
    this.id,
    this.title,
    this.body,
    this.format,
    this.order, {
    this.filter = '1=1',
    this.extra = '',
  });
  final String kind, table, id, title, body, format, order, filter, extra;
}

// All SQL identifiers originate in this fixed application list, never tool args.
const _sources = <_Source>[
  _Source(
    'note',
    'notes',
    'id',
    'title',
    'content',
    'editor_type',
    'updated_at',
    filter: "collection='note'",
  ),
  _Source(
    'article',
    'notes',
    'id',
    'title',
    'content',
    'editor_type',
    'updated_at',
    filter: "collection='article'",
  ),
  _Source(
    'document',
    'documents',
    'document_id',
    'document_name',
    'markdown',
    'doc_type',
    'modify_time',
    filter:
        'EXISTS(SELECT 1 FROM books b WHERE b.book_id=documents.book_id AND b.deleted=0)',
    extra: ',book_id',
  ),
  _Source(
    'book',
    'books',
    'book_id',
    'book_name',
    'description',
    "'markdown'",
    'modify_time',
  ),
  _Source(
    'task',
    'tasks',
    'task_id',
    'content',
    'content',
    "'plain'",
    'modify_time',
    extra: ',due_date,done,parent_id,topic_id',
  ),
  _Source(
    'bookmark',
    'bookmarks',
    'bookmark_id',
    'title',
    'description',
    "'plain'",
    'modify_time',
    extra:
        ',CASE WHEN length(url)<=4096 THEN url ELSE NULL END AS resource_url',
  ),
  _Source(
    'topic',
    'topics',
    'topic_id',
    'title',
    'question',
    "'markdown'",
    'modify_time',
  ),
];

// Source identifiers below are fixed app constants, never model arguments.
String _protectedSql(_Source source) =>
    "(hex(substr(CAST(${source.body} AS BLOB),1,4))='454E433A' OR "
    "hex(substr(CAST(${source.body} AS BLOB),1,7))='EFBBBF454E433A')";

String _clip(String value, int maxBytes) {
  if (utf8.encode(value).length <= maxBytes) return value;
  final out = StringBuffer();
  var count = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune),
        bytes = utf8.encode(String.fromCharCode(rune)).length;
    if (count + bytes > maxBytes) break;
    out.write(char);
    count += bytes;
  }
  return out.toString();
}

/// Strictly read-only: it does not call the ordinary UI search's label-registry
/// synchronization, does not record visits, decrypt notes or read drive files.
final class LocalAssistantKnowledge {
  LocalAssistantKnowledge(
    this.store, {
    required this.permitted,
    this.isCurrent,
  });
  final LocalStore store;
  final bool Function() permitted;
  final bool Function()? isCurrent;
  bool get _current => !store.maintenance.retired && isCurrent?.call() != false;
  void _guard({required bool requirePermission}) {
    if (!_current) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.retired);
    }
    if (requirePermission && !permitted()) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.permission);
    }
  }

  Future<T> _use<T>(
    Future<T> Function(Database) action, {
    bool requirePermission = true,
  }) async {
    _guard(requirePermission: requirePermission);
    try {
      return await store.maintenance.use(() async {
        _guard(requirePermission: requirePermission);
        final db = await store.database;
        _guard(requirePermission: requirePermission);
        final result = await action(db);
        _guard(requirePermission: requirePermission);
        return result;
      });
    } on LocalKnowledgeFailure {
      rethrow;
    } catch (_) {
      throw LocalKnowledgeFailure(
        _current ? LocalKnowledgeIssue.unreadable : LocalKnowledgeIssue.retired,
      );
    }
  }

  Future<LocalKnowledgeSearch> search(
    String query, {
    String? kind,
    int limit = 8,
  }) {
    if (limit < 1 ||
        limit > 20 ||
        (kind != null && !_sources.any((s) => s.kind == kind))) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.invalid);
    }
    final String q;
    try {
      q = normalizeSearchQuery(query);
    } on FormatException {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.invalid);
    }
    final escaped = q
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final like = '%$escaped%';
    return _use(
      (db) => db.transaction((tx) async {
        final groups = <List<Map<String, Object?>>>[];
        for (final source in _sources.where(
          (s) => kind == null || s.kind == kind,
        )) {
          _guard(requirePermission: true);
          final rows = await tx.rawQuery(
            'SELECT ${source.id} AS id,substr(${source.title},1,120) AS title,${source.format} AS format,'
            "CASE WHEN ${_protectedSql(source)} THEN 1 ELSE 0 END AS protected,"
            "CASE WHEN ${_protectedSql(source)} THEN '' ELSE "
            'substr(${source.body},max(1,instr(lower(${source.body}),lower(?))-48),160) END AS snippet '
            'FROM ${source.table} WHERE deleted=0 AND (${source.filter}) AND '
            "(${source.title} LIKE ? ESCAPE '\\' OR (NOT ${_protectedSql(source)} AND ${source.body} LIKE ? ESCAPE '\\')) "
            'ORDER BY ${source.order} DESC,${source.id} DESC LIMIT ?',
            [q, like, like, limit + 1],
          );
          groups.add([
            for (final row in rows)
              {
                'kind': source.kind,
                'id': row['id'],
                'title': _clip(row['title'] as String, 200),
                'format': row['format'],
                'protected': row['protected'] == 1,
                'snippet': _clip(row['snippet'] as String, 512),
              },
          ]);
        }
        final result = <Map<String, Object?>>[];
        var index = 0;
        while (result.length < limit) {
          var added = false;
          for (final group in groups) {
            if (index < group.length && result.length < limit) {
              result.add(Map.unmodifiable(group[index]));
              added = true;
            }
          }
          if (!added) break;
          index++;
        }
        return LocalKnowledgeSearch(
          List.unmodifiable(result),
          more:
              groups.fold<int>(0, (count, g) => count + g.length) >
              result.length,
        );
      }, exclusive: false),
    );
  }

  String _body(Object? value, Object? total, int maxBytes) {
    // SQLite substr of an empty BLOB may be NULL; its byte count proves empty.
    if (total == 0 && value == null) return '';
    if (value is! Uint8List || total is! int || total < 0) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.unreadable);
    }
    String? decoded;
    final complete = total <= value.length;
    for (
      var drop = 0;
      drop <= (complete ? 0 : 3) && drop <= value.length;
      drop++
    ) {
      try {
        decoded = utf8.decode(value.sublist(0, value.length - drop));
        break;
      } on FormatException {
        if (complete) rethrow;
      }
    }
    if (decoded == null) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.unreadable);
    }
    // Utf8Decoder consumes an initial BOM; source text and byte accounting must
    // retain it, including a source consisting only of the BOM.
    if (value.length >= 3 &&
        value[0] == 0xef &&
        value[1] == 0xbb &&
        value[2] == 0xbf) {
      decoded = '\ufeff$decoded';
    }
    if (isLocalProtectedEnvelopePrefix(decoded)) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.protected);
    }

    return _clip(decoded, maxBytes);
  }

  Map<String, Object?> _safeUrl(Object? raw) {
    if (raw is! String) return {'url': '', 'url_omitted': true};
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return {'url': '', 'url_omitted': true};
    }
    return {
      'url': uri
          .replace(userInfo: '')
          .toString()
          .split('#')
          .first
          .split('?')
          .first,
      'url_redacted':
          uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment,
    };
  }

  Future<Map<String, Object?>?> _liveReference(
    DatabaseExecutor tx,
    Object? type,
    Object? id,
  ) async {
    if (id is! int || id <= 0) return null;
    if (type == 'blog') {
      final rows = await tx.rawQuery(
        'SELECT collection FROM notes WHERE id=? AND deleted=0',
        [id],
      );
      if (rows.length != 1) return null;
      type = rows.single['collection'];
    }
    final matches = _sources.where((source) => source.kind == type);
    if (matches.length != 1) return null;
    final source = matches.single;
    final rows = await tx.rawQuery(
      'SELECT substr(${source.title},1,120) AS title,${source.format} AS format '
      'FROM ${source.table} WHERE ${source.id}=? AND deleted=0 AND (${source.filter})',
      [id],
    );
    if (rows.length != 1) return null;
    return {
      'kind': source.kind,
      'id': id,
      'title': _clip(rows.single['title'] as String, 200),
      'format': rows.single['format'],
    };
  }

  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> reference, {
    bool forModel = true,
  }) {
    final kind = reference['kind'], id = reference['id'];
    final matches = _sources.where((s) => s.kind == kind);
    if (id is! int || id <= 0 || matches.length != 1) {
      throw const LocalKnowledgeFailure(LocalKnowledgeIssue.invalid);
    }
    final source = matches.single;
    return _use(
      (db) => db.transaction((tx) async {
        const budget = 24000;
        final rows = await tx.rawQuery(
          'SELECT ${source.id} AS id,substr(${source.title},1,120) AS title,${source.format} AS format,'
          "CASE WHEN ${_protectedSql(source)} THEN 1 ELSE 0 END AS protected,"
          'length(CAST(${source.body} AS BLOB)) AS body_bytes,'
          "CASE WHEN ${_protectedSql(source)} THEN NULL ELSE "
          'substr(CAST(${source.body} AS BLOB),1,?) END AS body${source.extra} '
          'FROM ${source.table} WHERE ${source.id}=? AND deleted=0 AND (${source.filter})',
          [budget + 4, id],
        );
        if (rows.length != 1) {
          throw const LocalKnowledgeFailure(LocalKnowledgeIssue.notFound);
        }
        final row = rows.single;
        if (row['protected'] == 1) {
          throw const LocalKnowledgeFailure(LocalKnowledgeIssue.protected);
        }
        final body = _body(row['body'], row['body_bytes'], budget);
        final metadata = <String, Object?>{
          'kind': kind,
          'id': id,
          'format': row['format'],
          'body_bytes': row['body_bytes'],
          'truncated': (row['body_bytes'] as int) > utf8.encode(body).length,
        };
        if (kind == 'bookmark') metadata.addAll(_safeUrl(row['resource_url']));
        if (kind == 'task') {
          metadata.addAll({
            'due_date': row['due_date'],
            'done': row['done'] == 1,
            'parent_id': row['parent_id'],
            'topic_id': row['topic_id'],
          });
        }
        if (kind == 'document') metadata['book_id'] = row['book_id'];
        var content = body;
        if (kind == 'topic') {
          final summaries = await tx.rawQuery(
            'SELECT summary_id,substr(CAST(content AS BLOB),1,4804) AS body,length(CAST(content AS BLOB)) AS body_bytes '
            'FROM topic_summaries WHERE topic_id=? ORDER BY order_sort,summary_id LIMIT 6',
            [id],
          );
          final combined = StringBuffer(body);
          var remaining = budget - utf8.encode(body).length;
          var included = 0;
          for (final summary in summaries.take(5)) {
            _guard(requirePermission: forModel);
            if (remaining <= 4) {
              metadata['truncated'] = true;
              break;
            }
            final part = _body(
              summary['body'],
              summary['body_bytes'],
              remaining - 4 < 4800 ? remaining - 4 : 4800,
            );
            combined.write('\n\n');
            combined.write(part);
            remaining -= utf8.encode(part).length + 2;
            included++;
            if ((summary['body_bytes'] as int) > utf8.encode(part).length) {
              metadata['truncated'] = true;
            }
          }
          if (summaries.length > included) metadata['truncated'] = true;
          content = combined.toString();
          metadata['summaries_included'] = included;
          // Resource snapshots are references only; never forward stale bodies.
          final refs = await tx.rawQuery(
            'SELECT resource_type,target_id FROM topic_resources WHERE topic_id=? ORDER BY order_sort,topic_resource_id LIMIT 8',
            [id],
          );
          final live = <Map<String, Object?>>[];
          for (final ref in refs) {
            _guard(requirePermission: forModel);
            final value = await _liveReference(
              tx,
              ref['resource_type'],
              ref['target_id'],
            );
            if (value != null) live.add(value);
          }
          metadata['resource_references'] = live;
        }
        _guard(requirePermission: forModel);
        return AssistantResourceDetail(
          _clip(row['title'] as String, 200),
          content,
          metadata: Map.unmodifiable(metadata),
        );
      }, exclusive: false),
      requirePermission: forModel,
    );
  }
}
