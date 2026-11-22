import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'local_backup_codec.dart';
import 'local_legacy_candidate_schema.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_candidate_rows.dart';
import 'local_legacy_candidate_uploads.dart';
import 'local_legacy_candidate_upload_copy.dart';

part 'local_legacy_candidate_primary.dart';
part 'local_legacy_candidate_upload_sql.dart';

enum LegacyMetadataReason {
  incompatibleSchema,
  nonemptyCandidate,
  integrity,
  storage,
  headerTooLarge,
}

final class LegacyMetadataFailure implements Exception {
  const LegacyMetadataFailure(this.reason);
  final LegacyMetadataReason reason;
  @override
  String toString() => 'Candidate source metadata could not be stored';
}

final class LegacyMetadataProgress {
  const LegacyMetadataProgress(
    this.records,
    this.relations,
    this.totalRecords,
    this.totalRelations,
  );
  final int records, relations, totalRecords, totalRelations;
}

final class LegacyMetadataFacts {
  const LegacyMetadataFacts(
    this.sourceSha256,
    this.records,
    this.labelRelations,
    this.verifiedBytes,
  );
  final String sourceSha256;
  final int records, labelRelations, verifiedBytes;
  // Facts about metadata only; no primary resources or activation receipt.
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Only for an owned NEW candidate, inside its transaction. The caller must
/// let failures propagate so ALL inserted metadata rolls back. This writes no
/// primary resources, blobs, activation pointer, or current user database.
Future<LegacyMetadataFacts> writeLegacyCandidateMetadata(
  Transaction tx,
  LegacyImportRecords records, {
  required DateTime importedAt,
  bool Function()? isCancelled,
  void Function(LegacyMetadataProgress)? onProgress,
}) async {
  void check() {
    if (isCancelled?.call() == true) throw const LegacyRecordsCancelled();
  }

  try {
    check();
    final version = await tx.rawQuery('PRAGMA user_version');
    final foreign = await tx.rawQuery('PRAGMA foreign_keys');
    if (version.length != 1 ||
        version.single.values.single != legacyCandidateSchemaVersion ||
        foreign.length != 1 ||
        foreign.single.values.single != 1) {
      throw const LegacyMetadataFailure(
        LegacyMetadataReason.incompatibleSchema,
      );
    }
    const expected = {
      ...LocalBackupManifest.requiredTables,
      'legacy_import_sources',
      'legacy_import_records',
      'legacy_import_label_relations',
      'legacy_friend_links',
      'legacy_import_upload_blobs',
      'legacy_import_upload_bindings',
    };
    final names =
        (await tx.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((r) => r['name'] as String)
            .where((name) => name != 'android_metadata')
            .toSet();
    if (names.length != expected.length || !names.containsAll(expected)) {
      throw const LegacyMetadataFailure(
        LegacyMetadataReason.incompatibleSchema,
      );
    }
    for (final name in expected) {
      check();
      if ((await tx.rawQuery(
            'SELECT count(*) AS n FROM "$name"',
          )).single['n'] !=
          0) {
        throw const LegacyMetadataFailure(
          LegacyMetadataReason.nonemptyCandidate,
        );
      }
    }
    final source = records.source, mapping = records.mapping;
    final manifest = jsonEncode(source.sections['manifest.json']);
    final recipe = mapping.recipeJson;
    final manifestBytes = utf8.encode(manifest),
        recipeBytes = utf8.encode(recipe);
    if (manifestBytes.length > 8 * 1024 * 1024 ||
        recipeBytes.length > 8 * 1024 * 1024) {
      throw const LegacyMetadataFailure(LegacyMetadataReason.headerTooLarge);
    }
    if (sha256.convert(recipeBytes).toString() != mapping.recipeSha256) {
      throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
    }
    check();
    await tx.insert('legacy_import_sources', {
      'source_sha256': source.sourceSha256,
      'source_kind': 'go_zip_v1',
      'manifest_json': manifest,
      'format_recipe_json': recipe,
      'imported_at': importedAt.toUtc().toIso8601String(),
    });
    await _verifyColumn(
      tx,
      'legacy_import_sources',
      'manifest_json',
      'source_sha256=?',
      [source.sourceSha256],
      manifestBytes.length,
      sha256.convert(manifestBytes).toString(),
      check,
    );
    await _verifyColumn(
      tx,
      'legacy_import_sources',
      'format_recipe_json',
      'source_sha256=?',
      [source.sourceSha256],
      recipeBytes.length,
      mapping.recipeSha256,
      check,
    );
    var count = 0,
        relations = 0,
        bytes = manifestBytes.length + recipeBytes.length;
    final total = records.mapping.identities.counts.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    final labels = source.sections['labels.json'] as Map;
    final totalRelations = (labels['relations'] as List).length;
    void progress() => onProgress?.call(
      LegacyMetadataProgress(count, relations, total, totalRelations),
    );
    progress();
    for (final row in records.records(isCancelled: isCancelled)) {
      check();
      final entry = row.identity;
      await tx.insert('legacy_import_records', {
        'kind': entry.kind.name,
        'local_id': entry.localId,
        'source_sha256': source.sourceSha256,
        'source_key': jsonEncode(entry.parts),
        'payload': row.json,
        'payload_sha256': row.sha256Hex,
      });
      final key = [entry.kind.name, entry.localId];
      final header = await tx.query(
        'legacy_import_records',
        columns: ['payload_sha256', 'source_sha256', 'source_key'],
        where: 'kind=? AND local_id=?',
        whereArgs: key,
      );
      if (header.length != 1 ||
          header.single['payload_sha256'] != row.sha256Hex ||
          header.single['source_sha256'] != source.sourceSha256 ||
          header.single['source_key'] != jsonEncode(entry.parts)) {
        throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
      }
      await _verifyColumn(
        tx,
        'legacy_import_records',
        'payload',
        'kind=? AND local_id=?',
        key,
        row.bytes,
        row.sha256Hex,
        check,
      );
      count++;
      bytes += row.bytes;
      progress();
    }
    for (final row in records.labelRelations(isCancelled: isCancelled)) {
      check();
      final id = row.sourceOrdinal + 1;
      await tx.insert('legacy_import_label_relations', {
        'relation_id': id,
        'source_sha256': source.sourceSha256,
        'label_id': row.labelId,
        'resource_kind': row.target.kind.name,
        'resource_id': row.target.localId,
        'payload': row.json,
        'payload_sha256': row.sha256Hex,
      });
      final header = await tx.query(
        'legacy_import_label_relations',
        columns: [
          'source_sha256',
          'label_id',
          'resource_kind',
          'resource_id',
          'payload_sha256',
        ],
        where: 'relation_id=?',
        whereArgs: [id],
      );
      if (header.length != 1 ||
          header.single['source_sha256'] != source.sourceSha256 ||
          header.single['label_id'] != row.labelId ||
          header.single['resource_kind'] != row.target.kind.name ||
          header.single['resource_id'] != row.target.localId ||
          header.single['payload_sha256'] != row.sha256Hex) {
        throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
      }
      await _verifyColumn(
        tx,
        'legacy_import_label_relations',
        'payload',
        'relation_id=?',
        [id],
        row.bytes,
        row.sha256Hex,
        check,
      );
      relations++;
      bytes += row.bytes;
      progress();
    }
    check();
    if (count != total ||
        relations != totalRelations ||
        (await tx.rawQuery(
              'SELECT count(*) AS n FROM legacy_import_records',
            )).single['n'] !=
            count ||
        (await tx.rawQuery(
              'SELECT count(*) AS n FROM legacy_import_label_relations',
            )).single['n'] !=
            relations) {
      throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
    }
    return LegacyMetadataFacts(source.sourceSha256, count, relations, bytes);
  } on DatabaseException {
    // A driver exception may carry SQL arguments. Do not expose it to UI.
    throw const LegacyMetadataFailure(LegacyMetadataReason.storage);
  }
}

Future<void> _verifyColumn(
  DatabaseExecutor db,
  String table,
  String column,
  String where,
  List<Object?> args,
  int expectedBytes,
  String expectedHash,
  void Function() check,
) async {
  check();
  final header = await db.rawQuery(
    'SELECT typeof("$column") AS t, length(CAST("$column" AS BLOB)) AS n FROM "$table" WHERE $where',
    args,
  );
  if (header.length != 1 ||
      header.single['t'] != 'text' ||
      header.single['n'] != expectedBytes) {
    throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
  }
  final output = _DigestSink(), sink = sha256.startChunkedConversion(output);
  try {
    for (var offset = 0; offset < expectedBytes;) {
      check();
      final size = (expectedBytes - offset).clamp(0, 16384);
      final rows = await db.rawQuery(
        'SELECT substr(CAST("$column" AS BLOB),?,?) AS chunk FROM "$table" WHERE $where',
        [offset + 1, size, ...args],
      );
      if (rows.length != 1 || rows.single['chunk'] is! Uint8List) {
        throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
      }
      final chunk = rows.single['chunk'] as Uint8List;
      if (chunk.length != size) {
        throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
      }
      sink.add(chunk);
      offset += chunk.length;
    }
  } finally {
    sink.close();
  }
  check();
  if (output.value?.toString() != expectedHash) {
    throw const LegacyMetadataFailure(LegacyMetadataReason.integrity);
  }
}
