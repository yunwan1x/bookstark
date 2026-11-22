part of 'local_legacy_candidate_metadata.dart';

final class LegacyUploadSqlProgress {
  const LegacyUploadSqlProgress(this.blobs, this.bindings);
  final int blobs, bindings;
}

final class LegacyUploadSqlFacts {
  const LegacyUploadSqlFacts._(
    this.sourceSha256,
    this.planSha256,
    this.blobs,
    this.bindings,
  );
  final String sourceSha256, planSha256;
  final int blobs, bindings;
}

/// Same owned candidate transaction as source metadata; errors must propagate.
/// These are copy observations only, never an activation/rendering permission.
Future<LegacyUploadSqlFacts> writeLegacyCandidateUploads(
  Transaction tx,
  LegacyCandidateUploads plan,
  LegacyCopiedUploads copied, {
  bool Function()? isCancelled,
  void Function(LegacyUploadSqlProgress)? onProgress,
}) async {
  void check() {
    if (isCancelled?.call() == true) {
      throw const LegacyRecordsCancelled();
    }
  }

  Future<void> verify(
    String table,
    Map<String, Object> values,
    String key,
    List<Object?> args,
  ) async {
    for (final item in values.entries) {
      check();
      final value = item.value;
      final header = await tx.rawQuery(
        'SELECT typeof("${item.key}") AS t, CASE WHEN typeof("${item.key}")='
        "'integer' THEN \"${item.key}\" ELSE NULL END AS n FROM \"$table\" WHERE $key",
        args,
      );
      if (header.length != 1) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
      if (value is String) {
        if (header.single['t'] != 'text') {
          throw const LegacyUploadFailure(LegacyUploadReason.integrity);
        }
        final bytes = utf8.encode(value);
        await _verifyColumn(
          tx,
          table,
          item.key,
          key,
          args,
          bytes.length,
          sha256.convert(bytes).toString(),
          check,
        );
      } else if (value is int) {
        if (header.single['t'] != 'integer' || header.single['n'] != value) {
          throw const LegacyUploadFailure(LegacyUploadReason.integrity);
        }
      } else {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
    }
  }

  Future<void> insert(String table, Map<String, Object> values) async {
    final columns = values.keys.toList(growable: false);
    final placeholders = [
      for (final column in columns)
        values[column] is String ? 'CAST(? AS TEXT)' : '?',
    ];
    await tx.rawInsert(
      'INSERT INTO "$table" (${columns.map((n) => '"$n"').join(',')}) VALUES (${placeholders.join(',')})',
      [
        for (final name in columns)
          if (values[name] is String)
            Uint8List.fromList(utf8.encode(values[name] as String))
          else
            values[name],
      ],
    );
  }

  try {
    check();
    final version = (await tx.rawQuery(
      'PRAGMA user_version',
    )).single.values.single;
    final foreign = (await tx.rawQuery(
      'PRAGMA foreign_keys',
    )).single.values.single;
    final encoding = (await tx.rawQuery(
      'PRAGMA encoding',
    )).single.values.single;
    if (version != legacyCandidateSchemaVersion ||
        foreign != 1 ||
        encoding != 'UTF-8') {
      throw const LegacyUploadFailure(LegacyUploadReason.incompatibleSchema);
    }
    final registry = await tx.rawQuery(
      'SELECT source_sha256,source_kind,length(CAST(format_recipe_json AS BLOB)) AS recipe_bytes FROM legacy_import_sources',
    );
    if (registry.length != 1 ||
        registry.single['source_sha256'] != plan.sourceSha256 ||
        registry.single['source_kind'] != 'go_zip_v1' ||
        registry.single['recipe_bytes'] is! int ||
        (registry.single['recipe_bytes'] as int) > 8 * 1024 * 1024) {
      throw const LegacyUploadFailure(LegacyUploadReason.sourceMismatch);
    }
    await _verifyColumn(
      tx,
      'legacy_import_sources',
      'format_recipe_json',
      'source_sha256=?',
      [plan.sourceSha256],
      registry.single['recipe_bytes'] as int,
      plan.recipeSha256,
      check,
    );
    for (final table in [
      'legacy_import_upload_blobs',
      'legacy_import_upload_bindings',
    ]) {
      if ((await tx.rawQuery(
            'SELECT count(*) AS n FROM "$table"',
          )).single['n'] !=
          0) {
        throw const LegacyUploadFailure(LegacyUploadReason.nonemptyCandidate);
      }
    }
    final originalIds = {
      for (final binding in plan.bindings)
        if (binding.role == LegacyUploadRole.original) binding.uploadId,
    };
    final metadata = await tx.query(
      'legacy_import_records',
      columns: ['local_id', 'source_sha256'],
      where: "kind='upload'",
    );
    if (metadata.length != plan.uploadRows ||
        originalIds.length != plan.uploadRows ||
        metadata.any(
          (r) =>
              r['source_sha256'] != plan.sourceSha256 ||
              !originalIds.contains(r['local_id']),
        )) {
      throw const LegacyUploadFailure(LegacyUploadReason.sourceMismatch);
    }
    await verifyLegacyCopiedUploads(plan, copied, isCancelled: isCancelled);
    final blobRows = <Map<String, Object>>[],
        bindingRows = <Map<String, Object>>[];
    var blobs = 0, bindings = 0;
    onProgress?.call(const LegacyUploadSqlProgress(0, 0));
    for (final blob in plan.blobs) {
      check();
      final values = <String, Object>{
        'attachment_id': blob.attachmentId,
        'source_sha256': plan.sourceSha256,
        'logical_name': blob.logicalName,
        'alias_path': blob.aliasPath,
        'file_size': blob.bytes,
        'file_sha256': blob.sha256Hex,
      };
      await insert('legacy_import_upload_blobs', values);
      await verify('legacy_import_upload_blobs', values, 'attachment_id=?', [
        blob.attachmentId,
      ]);
      blobRows.add(values);
      blobs++;
      onProgress?.call(LegacyUploadSqlProgress(blobs, bindings));
    }
    for (final binding in plan.bindings) {
      check();
      final values = <String, Object>{
        'source_sha256': plan.sourceSha256,
        'upload_kind': 'upload',
        'upload_id': binding.uploadId,
        'role': binding.role.name,
        'attachment_id': binding.blob.attachmentId,
      };
      await insert('legacy_import_upload_bindings', values);
      await verify(
        'legacy_import_upload_bindings',
        values,
        'source_sha256=? AND upload_id=? AND role=?',
        [plan.sourceSha256, binding.uploadId, binding.role.name],
      );
      bindingRows.add(values);
      bindings++;
      onProgress?.call(LegacyUploadSqlProgress(blobs, bindings));
    }
    for (final row in blobRows) {
      await verify('legacy_import_upload_blobs', row, 'attachment_id=?', [
        row['attachment_id'],
      ]);
    }
    for (final row in bindingRows) {
      await verify(
        'legacy_import_upload_bindings',
        row,
        'source_sha256=? AND upload_id=? AND role=?',
        [row['source_sha256'], row['upload_id'], row['role']],
      );
    }
    for (final pair in [
      ('legacy_import_upload_blobs', blobs),
      ('legacy_import_upload_bindings', bindings),
    ]) {
      if ((await tx.rawQuery(
            'SELECT count(*) AS n FROM "${pair.$1}"',
          )).single['n'] !=
          pair.$2) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
    }
    check();
    if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    return LegacyUploadSqlFacts._(
      plan.sourceSha256,
      plan.planSha256,
      blobs,
      bindings,
    );
  } catch (error) {
    if (error is LegacyUploadFailure || error is LegacyRecordsCancelled) {
      rethrow;
    }
    if (error is LegacyMetadataFailure) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    throw const LegacyUploadFailure(LegacyUploadReason.storage);
  }
}
