import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'local_content_crypto_limits.dart';

/// Reads local note/document TEXT without returning an unbounded value in a
/// SQLite CursorWindow row. SQL identifiers are fixed by this class; callers
/// can only pass bound IDs, collection/type values and byte limits.
class BoundedNoteTextReader {
  BoundedNoteTextReader._();

  static const maxBytes = 20 * 1024 * 1024;
  // The default remains the plain-document bound. Only explicit protected
  // callers request the larger stored envelope budget.
  static const maxStoredNoteBytes = localCryptoMaxWireBytes;
  static const chunkBytes = 256 * 1024;
  static const _editorTypes = {
    'markdown',
    'html',
    'spreadsheet',
    'drawing',
    'mindmap',
    'richdoc',
    'presentation',
  };

  static Future<String> readNoteContent(
    DatabaseExecutor tx, {
    required int id,
    required String collection,
    required String editorType,
    int? maxRecordBytes = maxBytes,
  }) async {
    if (id <= 0 ||
        !{'note', 'article'}.contains(collection) ||
        !_editorTypes.contains(editorType) ||
        (maxRecordBytes == null && editorType != 'markdown') ||
        (maxRecordBytes != null &&
            (maxRecordBytes < 0 || maxRecordBytes > maxStoredNoteBytes))) {
      throw ArgumentError('Invalid bounded note body identity or byte limit');
    }
    final lengthRows = await tx.rawQuery(
      'SELECT length(CAST(content AS BLOB)) AS byte_length FROM notes '
      'WHERE id = ? AND collection = ? AND editor_type = ? AND deleted = 0',
      [id, collection, editorType],
    );
    if (lengthRows.length != 1) throw StateError('Note body no longer exists');
    return _readChunks(
      tx,
      lengthRows.single['byte_length'],
      maxRecordBytes,
      (offset, count) => tx.rawQuery(
        'SELECT substr(CAST(content AS BLOB), ?, ?) AS body_chunk FROM notes '
        'WHERE id = ? AND collection = ? AND editor_type = ? AND deleted = 0',
        [offset + 1, count, id, collection, editorType],
      ),
    );
  }

  static Future<String> readDocumentMarkdown(
    DatabaseExecutor tx, {
    required int id,
    int? maxRecordBytes = maxBytes,
  }) async {
    if (id <= 0 ||
        (maxRecordBytes != null &&
            (maxRecordBytes < 0 || maxRecordBytes > maxBytes))) {
      throw ArgumentError('Invalid bounded document identity or byte limit');
    }
    final lengthRows = await tx.rawQuery(
      'SELECT length(CAST(markdown AS BLOB)) AS byte_length FROM documents '
      "WHERE document_id = ? AND deleted = 0 AND doc_type != 'html'",
      [id],
    );
    if (lengthRows.length != 1) {
      throw StateError('Document body no longer exists');
    }
    return _readChunks(
      tx,
      lengthRows.single['byte_length'],
      maxRecordBytes,
      (offset, count) => tx.rawQuery(
        'SELECT substr(CAST(markdown AS BLOB), ?, ?) AS body_chunk '
        "FROM documents WHERE document_id = ? AND deleted = 0 AND doc_type != 'html'",
        [offset + 1, count, id],
      ),
    );
  }

  static Future<String> _readChunks(
    DatabaseExecutor tx,
    Object? value,
    int? maxRecordBytes,
    Future<List<Map<String, Object?>>> Function(int offset, int count)
    queryChunk,
  ) async {
    if (value is! int ||
        value < 0 ||
        (maxRecordBytes != null && value > maxRecordBytes)) {
      throw const FormatException('Local text exceeds byte limit');
    }
    // Allocate once, then fill in place. This avoids retaining all chunk
    // buffers plus a second full-body copy for large records.
    final bytes = Uint8List(value);
    for (var offset = 0; offset < value;) {
      final count = math.min(chunkBytes, value - offset);
      final rows = await queryChunk(offset, count);
      final chunk = rows.length == 1 ? rows.single['body_chunk'] : null;
      if (chunk is! Uint8List || chunk.length != count) {
        throw StateError('Local text chunk read incomplete');
      }
      bytes.setRange(offset, offset + count, chunk);
      offset += count;
    }
    return decodeUtf8PreservingBom(bytes);
  }

  static String decodeUtf8PreservingBom(Uint8List bytes) {
    var offset = 0;
    var bomCount = 0;
    while (offset + 2 < bytes.length &&
        bytes[offset] == 0xef &&
        bytes[offset + 1] == 0xbb &&
        bytes[offset + 2] == 0xbf) {
      offset += 3;
      bomCount++;
    }
    // Dart's UTF-8 decoder consumes one leading BOM. Strip all byte BOMs
    // explicitly, decode the remaining body strictly, then restore the exact
    // count so repeated leading U+FEFF characters remain byte-identical.
    final text = utf8.decode(
      Uint8List.sublistView(bytes, offset),
      allowMalformed: false,
    );
    final prefix = ''.padLeft(bomCount, '\ufeff');
    return '$prefix$text';
  }
}
