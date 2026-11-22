import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'bounded_note_text_reader.dart';
import 'label_creation_attempt.dart';
import 'label_creation_controller.dart';
import 'local_legacy_json.dart';
import 'local_store.dart';

/// Complete bounded local metadata only. No source title or body is selected.
class LocalLabelCreationMetadataReader {
  LocalLabelCreationMetadataReader({
    required this.store,
    required this.isCurrent,
  });
  final LocalStore store;
  final bool Function() isCurrent;
  void guard() {
    if (!isCurrent() || store.maintenance.retired) {
      throw StateError('Local label owner retired');
    }
  }

  Future<LabelCreationReview> inspect(
    LabelCreationAttempt attempt,
    int id,
  ) => store.maintenance.use(() async {
    guard();
    if (id <= 0) throw const FormatException('Actual local label ID required');
    final db = await store.database;
    guard();
    return db.transaction((tx) async {
      guard();
      final sizes = await tx.rawQuery(
        'SELECT length(CAST(label_name AS BLOB)) AS n FROM local_labels WHERE label_id=?',
        [id],
      );
      if (sizes.length != 1 ||
          sizes.single['n'] is! int ||
          (sizes.single['n'] as int) > 100) {
        throw const FormatException('Complete local label unavailable');
      }
      final rows = await tx.rawQuery(
        'SELECT CAST(label_name AS BLOB) AS name FROM local_labels WHERE label_id=?',
        [id],
      );
      final raw = rows.single['name'];
      if (raw is! Uint8List) {
        throw const FormatException('Exact local label bytes unavailable');
      }
      final name = BoundedNoteTextReader.decodeUtf8PreservingBom(raw);
      // Validates exact Unicode and today's name budget without trimming identity.
      LabelCreationAttempt(
        scope: attempt.scope,
        key: attempt.key,
        body: {'label_name': name},
      );
      final relations = <Map<String, Object?>>[];
      final counts = <String, int>{
        'book': 0,
        'blog': 0,
        'bookmark': 0,
        'document': 0,
      };
      var totalBytes = 0, totalRows = 0;
      for (final source in const [
        ('notes', 'id', 'updated_at', 'blog'),
        ('books', 'book_id', 'modify_time', 'book'),
        ('bookmarks', 'bookmark_id', 'modify_time', 'bookmark'),
        ('documents', 'document_id', 'modify_time', 'document'),
      ]) {
        final (table, key, time, kind) = source;
        final where = kind == 'document'
            ? 'deleted=0 AND book_id IN (SELECT book_id FROM books WHERE deleted=0)'
            : 'deleted=0';
        final stats = (await tx.rawQuery(
          'SELECT COUNT(*) AS n,COALESCE(SUM(length(CAST(labels AS BLOB))),0) AS bytes,COALESCE(MAX(length(CAST(labels AS BLOB))),0) AS biggest FROM $table WHERE $where',
        )).single;
        final n = stats['n'],
            bytes = stats['bytes'],
            biggest = stats['biggest'];
        if (n is! int || bytes is! int || biggest is! int || biggest > 65536) {
          throw const FormatException(
            'Complete local association review unavailable',
          );
        }
        totalRows += n;
        totalBytes += bytes;
        if (totalRows > 10000 || totalBytes > 1048576) {
          throw const FormatException(
            'Local association metadata exceeds budget',
          );
        }
        for (var offset = 0; offset < n; offset += 50) {
          final page = await tx.rawQuery(
            'SELECT $key AS id,CAST(labels AS BLOB) AS labels,$time AS modified FROM $table WHERE $where ORDER BY $key LIMIT 50 OFFSET ?',
            [offset],
          );
          for (final row in page) {
            guard();
            final sourceId = row['id'], labelBytes = row['labels'];
            if (sourceId is! int || sourceId <= 0 || labelBytes is! Uint8List) {
              throw const FormatException('Invalid local association metadata');
            }
            final labels = decodeLegacyJson(
              labelBytes,
              limits: const LegacyJsonLimits(
                maxBytes: 65536,
                maxStringBytes: 65536,
                maxEncodedStringCharacters: 65536,
                maxDepth: 2,
                maxNodes: 2048,
                maxObjectMembers: 1,
                maxArrayLength: 1024,
              ),
            );
            if (labels is! List || labels.any((v) => v is! String)) {
              throw const FormatException('Invalid local labels');
            }
            if (!labels.contains(name)) continue;
            final modified = row['modified'];
            if (modified is! int && modified is! String && modified != null) {
              throw const FormatException('Invalid local association time');
            }
            if (modified is String && utf8.encode(modified).length > 64) {
              throw const FormatException(
                'Local association time exceeds budget',
              );
            }
            relations.add({
              'resource_id': sourceId,
              'relation_type': kind,
              'modify_time': modified,
            });
            counts[kind] = counts[kind]! + 1;
            if (relations.length > 500) {
              throw const FormatException(
                'Complete local association review exceeds budget',
              );
            }
          }
        }
      }
      final wire = <String, Object?>{
        'label_id': id,
        'label_name': name,
        'book_count': counts['book'],
        'blog_count': counts['blog'],
        'bookmark_count': counts['bookmark'],
        'document_count': counts['document'],
        'relation_count': relations.length,
        'relations': relations,
      };
      final display = jsonEncode(wire);
      if (utf8.encode(display).length > 262144) {
        throw const FormatException('Local review exceeds budget');
      }
      guard();
      return LabelCreationReview(
        id: id,
        fingerprint: sha256.convert(utf8.encode(display)).toString(),
        display: display,
        matchesFrozenInput: name == attempt.body['label_name'],
        wire: Map.unmodifiable(wire),
      );
    });
  });
}
