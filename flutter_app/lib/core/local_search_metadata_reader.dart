import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'bounded_note_text_reader.dart';
import 'local_legacy_json.dart';
import 'local_search_content_reader.dart';

/// Fixed metadata policies only; never source titles or bodies in discovery.
class LocalSearchMetadataReader {
  LocalSearchMetadataReader(this.budget, {required this.guard});
  final LocalSearchContentReader budget;
  final void Function() guard;
  static const maxDiscoveryBytes = 16 * 1024 * 1024,
      maxDiscoveryRows = 250000,
      maxLabelsBytes = 1024 * 1024;
  Future<void> synchronizeLabels(DatabaseExecutor tx) async {
    guard();
    var count = 0, bytes = 0;
    final plans = <({String table, String key, String where, int count})>[];
    for (final source in const [
      ('notes', 'id'),
      ('books', 'book_id'),
      ('bookmarks', 'bookmark_id'),
      ('documents', 'document_id'),
    ]) {
      final (table, key) = source;
      final where = table == 'documents'
          ? 'deleted=0 AND book_id IN (SELECT book_id FROM books WHERE deleted=0)'
          : 'deleted=0';
      final stats = (await tx.rawQuery(
        'SELECT COUNT(*) AS n,COALESCE(SUM(length(CAST(labels AS BLOB))),0) AS bytes,COALESCE(MAX(length(CAST(labels AS BLOB))),0) AS biggest,COUNT(labels) AS present FROM $table WHERE $where',
      )).single;
      guard();
      final n = stats['n'], size = stats['bytes'], biggest = stats['biggest'];
      if (n is! int ||
          size is! int ||
          biggest is! int ||
          stats['present'] != n ||
          n < 0 ||
          size < 0 ||
          biggest > maxLabelsBytes) {
        throw const LocalSearchContentLimit();
      }
      count += n;
      bytes += size;
      if (count > maxDiscoveryRows || bytes > maxDiscoveryBytes) {
        throw const LocalSearchContentLimit();
      }
      plans.add((table: table, key: key, where: where, count: n));
    }
    // Reserve before any discovery write or page fetch. Per-array1MiB fits a row.
    budget.reserve(bytes);
    final discoveredNames = <String>{};
    for (final plan in plans) {
      for (var offset = 0; offset < plan.count; offset += 32) {
        guard();
        final rows = await tx.rawQuery(
          'SELECT ${plan.key} AS id,CAST(labels AS BLOB) AS labels FROM ${plan.table} WHERE ${plan.where} ORDER BY ${plan.key} LIMIT 32 OFFSET ?',
          [offset],
        );
        guard();
        for (final row in rows) {
          final raw = row['labels'];
          if (row['id'] is! int ||
              (row['id'] as int) <= 0 ||
              raw is! Uint8List ||
              raw.length > maxLabelsBytes) {
            throw const LocalSearchContentLimit();
          }
          final decoded = decodeLegacyJson(
            raw,
            limits: const LegacyJsonLimits(
              maxBytes: maxLabelsBytes,
              maxStringBytes: 65536,
              maxEncodedStringCharacters: maxLabelsBytes,
              maxDepth: 2,
              maxNodes: 10001,
              maxObjectMembers: 1,
              maxArrayLength: 10000,
            ),
          );
          if (decoded is! List || decoded.any((v) => v is! String)) {
            throw const FormatException('Invalid local label metadata');
          }
          // Preserve exact legacy names, including names outside today's create cap.
          for (final name in decoded.cast<String>().toSet()) {
            if (!discoveredNames.add(name)) continue;
            if (discoveredNames.length > 20000) {
              throw const LocalSearchContentLimit();
            }
            guard();
            final existing = await tx.query(
              'local_labels',
              columns: ['label_id'],
              where: 'label_name=?',
              whereArgs: [name],
              limit: 1,
            );
            guard();
            if (existing.isEmpty) {
              await tx.insert('local_labels', {'label_name': name});
            }
          }
        }
      }
    }
    guard();
  }

  List<Map<String, Object?>> decode(
    List<Map<String, Object?>> rows,
    Map<String, int> fields,
  ) {
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      guard();
      final next = Map<String, Object?>.of(row);
      for (final entry in fields.entries) {
        final bytes = row[entry.key];
        // SQL returns NULL instead of materializing a field beyond its own cap.
        if (bytes is! Uint8List || bytes.length > entry.value) {
          throw const LocalSearchContentLimit();
        }
        budget.reserve(bytes.length);
        next[entry.key] = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
      }
      result.add(next);
    }
    return result;
  }
}
