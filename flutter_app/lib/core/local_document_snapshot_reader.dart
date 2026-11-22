// Prepared scratch only. No app/N edits or executed regressions.
import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;
import 'documents_repository.dart';

const localTrashPayloadMaxBytes = 32 * 1024 * 1024;
const localDocumentMetadataMaxBytes = 4 * 1024 * 1024;
const localDocumentSnapshotMaxRows = 10000;

class LocalTrashPayloadLimit implements Exception {
  const LocalTrashPayloadLimit(this.actualBytes, this.maxBytes);
  final int actualBytes, maxBytes;
}

class _BoundedPayloadBytes implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> chunk) {
    count += chunk.length;
    if (count > localTrashPayloadMaxBytes) {
      throw LocalTrashPayloadLimit(count, localTrashPayloadMaxBytes);
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

/// Encoding is bounded incrementally, including JSON escaping. Never trim or
/// normalize an existing payload; consumers read its stored exact UTF8 bytes.
String encodeBoundedLocalTrashPayload(Object? value) {
  final output = _BoundedPayloadBytes();
  final encoder = JsonUtf8Encoder().startChunkedConversion(output);
  encoder.add(value);
  encoder.close();
  return BoundedNoteTextReader.decodeUtf8PreservingBom(
    output.bytes.takeBytes(),
  );
}

class LocalDocumentSnapshotReader {
  LocalDocumentSnapshotReader._();
  static const documentColumns = [
    'document_id',
    'book_id',
    'document_name',
    'identify',
    'parent_id',
    'order_sort',
    'doc_type',
    'create_time',
    'modify_time',
    'deleted',
    'labels',
  ];
  static const _documentText = [
    'document_name',
    'identify',
    'doc_type',
    'create_time',
    'modify_time',
    'labels',
  ];
  static const _bookText = [
    'book_name',
    'description',
    'identify',
    'labels',
    'create_time',
    'modify_time',
  ];
  static const chunkBytes = 256 * 1024;

  /// All caller work stays on the same externally owned transaction.
  static Future<List<Map<String, Object?>>> metadata(
    DatabaseExecutor tx, {
    required int bookId,
    int? documentId,
    int deleted = 0,
  }) async {
    if (bookId <= 0 ||
        (documentId != null && documentId <= 0) ||
        (deleted != 0 && deleted != 1)) {
      throw ArgumentError('Invalid scope');
    }
    final where =
        'book_id=? AND deleted=?${documentId == null ? '' : ' AND document_id=?'}';
    final args = [bookId, deleted, ?documentId];
    const lengths =
        'length(CAST(document_name AS BLOB))+length(CAST(identify AS BLOB))+'
        'length(CAST(doc_type AS BLOB))+length(CAST(create_time AS BLOB))+length(CAST(modify_time AS BLOB))+length(CAST(labels AS BLOB))';
    final aggregate = (await tx.rawQuery(
      'SELECT COUNT(*) AS n,COALESCE(SUM($lengths),0) AS bytes FROM documents WHERE $where',
      args,
    )).single;
    final n = aggregate['n'], bytes = aggregate['bytes'];
    if (n is! int ||
        bytes is! int ||
        n > localDocumentSnapshotMaxRows ||
        bytes > localDocumentMetadataMaxBytes) {
      throw const LocalTrashPayloadLimit(-1, localDocumentMetadataMaxBytes);
    }
    final projection = documentColumns
        .map(
          (name) => _documentText.contains(name)
              ? 'CASE WHEN length(CAST($name AS BLOB))<=65536 THEN CAST($name AS BLOB) ELSE NULL END AS $name'
              : name,
        )
        .join(',');
    final result = await tx.rawQuery(
      'SELECT $projection FROM documents WHERE $where ORDER BY order_sort,document_id',
      args,
    );
    final rows = result.map((row) => <String, Object?>{...row}).toList();
    for (final row in rows) {
      for (final key in _documentText) {
        final bytes = row[key];
        if (bytes is! Uint8List) {
          throw const FormatException('Invalid document metadata text');
        }
        row[key] = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
      }
      if (_documentText.any((key) => row[key] is! String) ||
          row['document_id'] is! int ||
          (row['document_id'] as int) <= 0 ||
          row['parent_id'] is! int ||
          row['order_sort'] is! int) {
        throw const FormatException('Invalid bounded document metadata');
      }
    }
    return rows;
  }

  static Future<Map<String, Object?>> oneMetadata(
    DatabaseExecutor tx,
    int id, {
    int deleted = 0,
  }) async {
    final identity = await tx.query(
      'documents',
      columns: ['book_id'],
      where: 'document_id=? AND deleted=?',
      whereArgs: [id, deleted],
    );
    if (identity.length != 1 || identity.single['book_id'] is! int) {
      throw StateError('Document identity missing');
    }
    final rows = await metadata(
      tx,
      bookId: identity.single['book_id'] as int,
      documentId: id,
      deleted: deleted,
    );
    if (rows.length != 1) throw StateError('Document identity missing');
    return rows.single;
  }

  static Future<Uint8List> _blob(
    DatabaseExecutor tx, {
    required String table,
    required String column,
    required String where,
    required List<Object?> args,
    required int limit,
  }) async {
    // Private fixed identifiers only; no identifier comes from a snapshot.
    if (!((table == 'documents' && column == 'markdown') ||
        (table == 'trash_entries' && column == 'payload') ||
        (table == 'books' && _bookText.contains(column)))) {
      throw ArgumentError('Unsupported bounded field');
    }
    final rows = await tx.rawQuery(
      'SELECT length(CAST($column AS BLOB)) AS bytes FROM $table WHERE $where',
      args,
    );
    final length = rows.length == 1 ? rows.single['bytes'] : null;
    if (length is! int || length < 0) throw StateError('Bounded body missing');
    if (length > limit) throw LocalTrashPayloadLimit(length, limit);
    final bytes = Uint8List(length);
    for (var offset = 0; offset < length;) {
      final remaining = length - offset,
          count = remaining > chunkBytes ? chunkBytes : remaining;
      final rows = await tx.rawQuery(
        'SELECT substr(CAST($column AS BLOB),?,?) AS bytes FROM $table WHERE $where',
        [offset + 1, count, ...args],
      );
      final chunk = rows.length == 1 ? rows.single['bytes'] : null;
      if (chunk is! Uint8List || chunk.length != count) {
        throw StateError('Incomplete bounded body');
      }
      bytes.setRange(offset, offset + count, chunk);
      offset += count;
    }
    return bytes;
  }

  static Future<(String, int)> body(
    DatabaseExecutor tx,
    Map<String, Object?> row, {
    int markdownBudget = documentReadMaxBytes,
    bool allowProtected = false,
  }) async {
    final id = row['document_id'] as int, book = row['book_id'] as int;
    final type = row['doc_type'] as String, deleted = row['deleted'] as int;
    const where = 'document_id=? AND book_id=? AND doc_type=? AND deleted=?';
    final args = [id, book, type, deleted];
    final meta = await tx.rawQuery(
      'SELECT length(CAST(markdown AS BLOB)) AS bytes,'
      'hex(substr(CAST(markdown AS BLOB),1,7)) AS prefix FROM documents WHERE $where',
      args,
    );
    if (meta.length != 1) throw StateError('Document identity changed');
    if (!allowProtected &&
        isLocalProtectedEnvelopeHexPrefix(meta.single['prefix'])) {
      throw NoteLocked(id);
    }
    final limit = documentBodyBudget(type, markdownBudget),
        length = meta.single['bytes'];
    if (length is! int || length < 0) {
      throw const FormatException('Invalid body byte length');
    }
    if (length > limit) throw DocumentReadLimit(id, type, length, limit);
    final bytes = await _blob(
      tx,
      table: 'documents',
      column: 'markdown',
      where: where,
      args: args,
      limit: limit,
    );
    return (BoundedNoteTextReader.decodeUtf8PreservingBom(bytes), length);
  }

  static Future<void> preflightBodies(
    DatabaseExecutor tx,
    List<Map<String, Object?>> rows,
  ) async {
    var total = 0;
    for (final row in rows) {
      final values = await tx.rawQuery(
        'SELECT length(CAST(markdown AS BLOB)) AS bytes FROM documents '
        'WHERE document_id=? AND book_id=? AND doc_type=? AND deleted=?',
        [row['document_id'], row['book_id'], row['doc_type'], row['deleted']],
      );
      final n = values.length == 1 ? values.single['bytes'] : null;
      final limit = documentBodyBudget(
        row['doc_type'] as String,
        documentReadMaxBytes,
      );
      if (n is! int || n < 0) throw StateError('Document identity changed');
      if (n > limit) {
        throw DocumentReadLimit(
          row['document_id'] as int,
          row['doc_type'] as String,
          n,
          limit,
        );
      }
      total += n;
      if (total > localTrashPayloadMaxBytes) {
        throw LocalTrashPayloadLimit(total, localTrashPayloadMaxBytes);
      }
    }
  }

  static Future<List<Map<String, Object?>>> snapshots(
    DatabaseExecutor tx,
    List<Map<String, Object?>> rows,
  ) async {
    await preflightBodies(
      tx,
      rows,
    ); // All byte gates before allocating any body.
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final source = await body(tx, row, allowProtected: true);
      result.add({...row, 'markdown': source.$1});
    }
    return result;
  }

  static Future<Map<String, Object?>> book(
    DatabaseExecutor tx,
    int id, {
    required int deleted,
  }) async {
    final rows = await tx.query(
      'books',
      columns: ['book_id', 'doc_count', 'deleted'],
      where: 'book_id=? AND deleted=?',
      whereArgs: [id, deleted],
    );
    if (rows.length != 1) throw StateError('Book identity missing');
    final result = <String, Object?>{...rows.single};
    var total = 0;
    for (final column in _bookText) {
      final bytes = await _blob(
        tx,
        table: 'books',
        column: column,
        where: 'book_id=? AND deleted=?',
        args: [id, deleted],
        limit: column == 'book_name' ? 65536 : localDocumentMetadataMaxBytes,
      );
      total += bytes.length;
      if (total > localDocumentMetadataMaxBytes) {
        throw LocalTrashPayloadLimit(total, localDocumentMetadataMaxBytes);
      }
      result[column] = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
    }
    return result;
  }

  static Future<String> payload(DatabaseExecutor tx, int trashId) async {
    final bytes = await _blob(
      tx,
      table: 'trash_entries',
      column: 'payload',
      where: 'trash_id=?',
      args: [trashId],
      limit: localTrashPayloadMaxBytes,
    );
    return BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
  }

  static void validateGraph(
    List<Map<String, Object?>> rows,
    int bookId, {
    bool complete = true,
  }) {
    final byId = <int, Map<String, Object?>>{};
    for (final row in rows) {
      final id = row['document_id'], parent = row['parent_id'];
      if (id is! int ||
          id <= 0 ||
          parent is! int ||
          parent < 0 ||
          row['book_id'] != bookId ||
          byId.containsKey(id)) {
        throw const FormatException('Invalid owned document graph');
      }
      byId[id] = row;
    }
    final depths = <int, int>{0: -1};
    for (final id in byId.keys) {
      final visiting = <int>{}, path = <int>[];
      var current = id;
      while (!depths.containsKey(current)) {
        if (!visiting.add(current)) {
          throw const FormatException('Document cycle');
        }
        final node = byId[current];
        if (node == null) {
          if (complete) {
            throw const FormatException('Orphan/foreign document parent');
          }
          break;
        }
        path.add(current);
        current = node['parent_id'] as int;
      }
      var depth = depths[current] ?? -1;
      for (final nodeId in path.reversed) {
        depth++;
        if (depth > 256) {
          throw const FormatException('Document graph exceeds tree depth');
        }
        depths[nodeId] = depth;
      }
    }
  }

  static Future<void> rejectForeignChildren(
    DatabaseExecutor tx,
    int bookId,
  ) async {
    final foreign = await tx.rawQuery(
      'SELECT child.document_id FROM documents child '
      'JOIN documents parent ON child.parent_id=parent.document_id '
      'WHERE parent.book_id=? AND child.book_id!=? LIMIT 1',
      [bookId, bookId],
    );
    if (foreign.isNotEmpty) {
      throw const FormatException('Cross-book child edge');
    }
  }
}
