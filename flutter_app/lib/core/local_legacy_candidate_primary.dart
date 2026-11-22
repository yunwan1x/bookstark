part of 'local_legacy_candidate_metadata.dart';

enum LegacyPrimaryWriteReason {
  incompatibleSchema,
  sourceMismatch,
  nonemptyCandidate,
  integrity,
  storage,
}

final class LegacyPrimaryWriteFailure implements Exception {
  const LegacyPrimaryWriteFailure(this.reason);
  final LegacyPrimaryWriteReason reason;
  @override
  String toString() => 'Candidate primary resources could not be stored';
}

final class LegacyPrimaryProgress {
  const LegacyPrimaryProgress(this.rows, this.totalRows);
  final int rows, totalRows;
}

final class LegacyPrimaryFacts {
  LegacyPrimaryFacts._(
    this.sourceSha256,
    Map<LegacyNativeTable, int> counts,
    this.verifiedCells,
    this.verifiedTextBytes,
    this.pendingUploads,
  ) : counts = Map.unmodifiable(counts);
  final String sourceSha256;
  final Map<LegacyNativeTable, int> counts;
  final int verifiedCells, verifiedTextBytes, pendingUploads;
  // No uploaded files, editor-body verdict or activation receipt is returned.
}

/// Runs AFTER metadata in the SAME owned fresh-candidate transaction.
/// Any failure must escape that transaction; there is no replace/ignore mode.
Future<LegacyPrimaryFacts> writeLegacyCandidatePrimaryRows(
  Transaction tx,
  LegacyCandidateRows plan, {
  bool Function()? isCancelled,
  void Function(LegacyPrimaryProgress)? onProgress,
}) async {
  void check() {
    if (isCancelled?.call() == true) throw const LegacyRecordsCancelled();
  }

  try {
    check();
    final version = await tx.rawQuery('PRAGMA user_version');
    final foreign = await tx.rawQuery('PRAGMA foreign_keys');
    final encoding = await tx.rawQuery('PRAGMA encoding');
    if (version.length != 1 ||
        version.single.values.single != legacyCandidateSchemaVersion ||
        foreign.length != 1 ||
        foreign.single.values.single != 1 ||
        encoding.length != 1 ||
        encoding.single.values.single != 'UTF-8') {
      throw const LegacyPrimaryWriteFailure(
        LegacyPrimaryWriteReason.incompatibleSchema,
      );
    }
    final source = plan.records.source, mapping = plan.records.mapping;
    final registry = await tx.query(
      'legacy_import_sources',
      columns: ['source_sha256', 'source_kind'],
    );
    if (registry.length != 1 ||
        registry.single['source_sha256'] != source.sourceSha256 ||
        registry.single['source_kind'] != 'go_zip_v1') {
      throw const LegacyPrimaryWriteFailure(
        LegacyPrimaryWriteReason.sourceMismatch,
      );
    }
    try {
      final recipe = utf8.encode(mapping.recipeJson);
      await _verifyColumn(
        tx,
        'legacy_import_sources',
        'format_recipe_json',
        'source_sha256=?',
        [source.sourceSha256],
        recipe.length,
        mapping.recipeSha256,
        check,
      );
    } on LegacyMetadataFailure {
      throw const LegacyPrimaryWriteFailure(
        LegacyPrimaryWriteReason.sourceMismatch,
      );
    }
    final totalMetadata = mapping.identities.counts.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    if ((await tx.rawQuery(
          'SELECT count(*) AS n FROM legacy_import_records',
        )).single['n'] !=
        totalMetadata) {
      throw const LegacyPrimaryWriteFailure(
        LegacyPrimaryWriteReason.sourceMismatch,
      );
    }
    for (final table in LegacyNativeTable.values) {
      check();
      if ((await tx.rawQuery(
            'SELECT count(*) AS n FROM "${table.sqlName}"',
          )).single['n'] !=
          0) {
        throw const LegacyPrimaryWriteFailure(
          LegacyPrimaryWriteReason.nonemptyCandidate,
        );
      }
    }
    final counts = <LegacyNativeTable, int>{};
    var completed = 0, cells = 0, textBytes = 0;
    final total = plan.counts.values.fold<int>(0, (a, b) => a + b);
    onProgress?.call(LegacyPrimaryProgress(0, total));
    for (final row in plan.rows(isCancelled: isCancelled)) {
      check();
      final columns = row.values.keys.toList(growable: false);
      final placeholders = <String>[];
      final arguments = <Object?>[];
      for (final name in columns) {
        final value = row.values[name];
        if (value is String) {
          // Android binds Java strings via sqlite3_bind_text16, which consumes
          // an initial U+FEFF. Bind UTF8 bytes, then cast inside the UTF8 DB.
          placeholders.add('CAST(? AS TEXT)');
          arguments.add(Uint8List.fromList(utf8.encode(value)));
        } else {
          placeholders.add('?');
          arguments.add(value);
        }
      }
      await tx.rawInsert(
        'INSERT INTO "${row.table.sqlName}" '
        '(${columns.map((name) => '"$name"').join(',')}) '
        'VALUES (${placeholders.join(',')})',
        arguments,
      );
      final key = '"${row.table.idColumn}"=?', args = <Object?>[row.id];
      for (final item in row.values.entries) {
        check();
        final header = await tx.rawQuery(
          'SELECT typeof("${item.key}") AS t, '
          'CASE WHEN typeof("${item.key}") IN (\'integer\',\'null\') '
          'THEN "${item.key}" ELSE NULL END AS value '
          'FROM "${row.table.sqlName}" WHERE $key',
          args,
        );
        if (header.length != 1) {
          throw const LegacyPrimaryWriteFailure(
            LegacyPrimaryWriteReason.integrity,
          );
        }
        final value = item.value, type = header.single['t'];
        if (value is String) {
          if (type != 'text') {
            throw const LegacyPrimaryWriteFailure(
              LegacyPrimaryWriteReason.integrity,
            );
          }
          final bytes = utf8.encode(value);
          await _verifyColumn(
            tx,
            row.table.sqlName,
            item.key,
            key,
            args,
            bytes.length,
            sha256.convert(bytes).toString(),
            check,
          );
          textBytes += bytes.length;
        } else if (value is int) {
          if (type != 'integer' || header.single['value'] != value) {
            throw const LegacyPrimaryWriteFailure(
              LegacyPrimaryWriteReason.integrity,
            );
          }
        } else if (value == null) {
          if (type != 'null' || header.single['value'] != null) {
            throw const LegacyPrimaryWriteFailure(
              LegacyPrimaryWriteReason.integrity,
            );
          }
        } else {
          throw const LegacyPrimaryWriteFailure(
            LegacyPrimaryWriteReason.integrity,
          );
        }
        cells++;
      }
      counts.update(row.table, (n) => n + 1, ifAbsent: () => 1);
      completed++;
      onProgress?.call(LegacyPrimaryProgress(completed, total));
    }
    check();
    if (completed != total) {
      throw const LegacyPrimaryWriteFailure(LegacyPrimaryWriteReason.integrity);
    }
    for (final table in LegacyNativeTable.values) {
      if ((await tx.rawQuery(
                'SELECT count(*) AS n FROM "${table.sqlName}"',
              )).single['n'] !=
              (plan.counts[table] ?? 0) ||
          (counts[table] ?? 0) != (plan.counts[table] ?? 0)) {
        throw const LegacyPrimaryWriteFailure(
          LegacyPrimaryWriteReason.integrity,
        );
      }
    }
    return LegacyPrimaryFacts._(
      source.sourceSha256,
      counts,
      cells,
      textBytes,
      plan.pendingUploads,
    );
  } on LegacyMetadataFailure {
    throw const LegacyPrimaryWriteFailure(LegacyPrimaryWriteReason.integrity);
  } on DatabaseException {
    throw const LegacyPrimaryWriteFailure(LegacyPrimaryWriteReason.storage);
  }
}
