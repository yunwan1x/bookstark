// Headless, synthetic-only ARM64 SQLite probe. This is never the production
// entrypoint and exposes no diagnostics or fault switch in main.dart.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'legacy_candidate_fixture_seed.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_upload_copy.dart';

Future<Map<String, dynamic>> _jsonFile(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 32768) {
    throw StateError('Owned marker unavailable');
  }
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic>) {
    throw StateError('Owned marker invalid');
  }
  return value;
}

Future<void> _emit(
  Directory root,
  String name,
  Map<String, Object?> data,
) async {
  final file = File(paths.join(root.path, name));
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Owned result already exists');
  }
  await file.writeAsString(jsonEncode(data), flush: true);
}

Future<Map<String, Object?>> _summary(
  Database db,
  Directory root,
  String copiedName,
) async {
  final version = (await db.rawQuery(
    'PRAGMA user_version',
  )).single.values.single;
  if (version != 15 ||
      (await db.rawQuery('PRAGMA quick_check')).single.values.single != 'ok' ||
      (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
    throw StateError('Owned database verification failed');
  }
  final counts = <String, int>{};
  for (final table in LegacyNativeTable.values) {
    counts[table.sqlName] =
        (await db.rawQuery(
              'SELECT count(*) AS n FROM "${table.sqlName}"',
            )).single['n']
            as int;
  }
  final noteFlags = await db.rawQuery(
    'SELECT id,revision,updated_at,legacy_version,'
    'typeof(legacy_version) AS legacy_version_type,'
    'length(CAST(content AS BLOB)) AS content_bytes,'
    'hex(substr(CAST(content AS BLOB),1,3)) AS content_prefix '
    'FROM notes ORDER BY id',
  );
  if (!RegExp(r'^legacy-upload-[A-Za-z0-9_-]{6,64}$').hasMatch(copiedName)) {
    throw StateError('Owned copy child invalid');
  }
  final copied = Directory(paths.join(root.path, 'copied-uploads', copiedName));
  if (await FileSystemEntity.type(copied.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      !(await copied.resolveSymbolicLinks()).startsWith(
        paths.join(await root.resolveSymbolicLinks(), 'copied-uploads') +
            paths.separator,
      )) {
    throw StateError('Owned copy root invalid');
  }
  final blobs = await db.query('legacy_import_upload_blobs');
  final copiedFiles = await copied.list(followLinks: false).toList();
  if (copiedFiles.length != blobs.length) {
    throw StateError('Owned copy count mismatch');
  }
  var uploadBytes = 0;
  for (final blob in blobs) {
    final id = blob['attachment_id'],
        size = blob['file_size'],
        hash = blob['file_sha256'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        size is! int ||
        size < 0 ||
        size > 512 * 1024 * 1024 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw StateError('Owned blob row invalid');
    }
    final file = File(paths.join(copied.path, id));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != size) {
      throw StateError('Owned blob unavailable');
    }
    var read = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((part) {
            read += part.length;
            if (read > size) {
              throw StateError('Owned blob exceeds bound');
            }
            return part;
          }),
        )
        .first;
    if (read != size || digest.toString() != hash) {
      throw StateError('Owned blob hash mismatch');
    }
    uploadBytes += read;
  }
  return {
    'sqlite_version': (await db.rawQuery(
      'SELECT sqlite_version() AS v',
    )).single['v'],
    'schema': version,
    'primary_counts': counts,
    'note_flags': noteFlags,
    'metadata_records': (await db.rawQuery(
      'SELECT count(*) AS n FROM legacy_import_records',
    )).single['n'],
    'label_relations': (await db.rawQuery(
      'SELECT count(*) AS n FROM legacy_import_label_relations',
    )).single['n'],
    'pending_uploads': 0,
    'upload_blobs': blobs.length,
    'upload_bindings': (await db.rawQuery(
      'SELECT count(*) AS n FROM legacy_import_upload_bindings',
    )).single['n'],
    'upload_bytes': uploadBytes,
    'copied_directory': copiedName,
    'copy_cancel_cleanup_passed': true,
    'upload_alias_runtime_connected': false,
    'activation_requested': false,
    'production_migration_ui': false,
    'all45_complete': false,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  Directory? root;
  Database? database;
  var validatedRoot = false, phase = 'startup';
  var metadataRows = 0, primaryRows = 0;
  var copiedName = '';
  try {
    final support = await getApplicationSupportDirectory();
    root = Directory(paths.join(support.path, 'legacy-candidate-probe'));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await root.create();
    } else if (type != FileSystemEntityType.directory) {
      throw StateError('Owned root invalid');
    }
    if (!(await root.resolveSymbolicLinks()).startsWith(
      (await support.resolveSymbolicLinks()) + paths.separator,
    )) {
      throw StateError('Owned root escaped');
    }
    validatedRoot = true;
    final marker = await _jsonFile(File(paths.join(root.path, 'owned.json')));
    if (marker.length != 5 ||
        marker['format'] != 1 ||
        marker['synthetic_only'] != true ||
        !['build', 'verify'].contains(marker['phase']) ||
        marker['fixture'] is! String ||
        marker['nonce'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(marker['nonce'] as String)) {
      throw StateError('Owned marker mismatch');
    }
    phase = marker['phase'] as String;
    final fixture = marker['fixture'] as String,
        nonce = marker['nonce'] as String;
    final expected = legacyCandidateProbeHashes[fixture];
    if (expected == null) {
      throw StateError('Only pinned synthetic input is permitted');
    }
    final input = File(paths.join(root.path, 'source.zip'));
    if (await FileSystemEntity.type(input.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await sha256.bind(input.openRead()).first).toString() != expected) {
      throw StateError('Pinned synthetic input mismatch');
    }
    final target = File(paths.join(root.path, 'candidate.db'));
    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (phase == 'build') {
      if (targetType != FileSystemEntityType.notFound) {
        throw StateError('Never replay a build');
      }
      final stage = await LegacyZipStage.inspect(
        input,
        privateParent: root,
        expectedSha256: expected,
        availableBytes: NativeLocalDataControl().availableBytes,
      );
      final source = await LegacyGoExport.inspect(stage);
      final real = LegacyFormatSource.fromInspection(source, scopeKey: nonce);
      final choice = LegacyFormatSelection(
        real,
        choices: {
          for (final item in real.items)
            item.id: item.collection == 'article'
                ? LegacyContentFormat.html
                : LegacyContentFormat.markdown,
        },
      );
      final mapping = LegacyImportMapping.fromRecipe(
        source,
        choice.toJson(),
        scopeKey: nonce,
      );
      final records = LegacyImportRecords.fromExport(source, mapping);
      final plan = LegacyCandidateRows.fromRecords(records);
      final uploadPlan = LegacyCandidateUploads.fromRecords(records, stage);
      final copyParent = await Directory(
        paths.join(root.path, 'copied-uploads'),
      ).create();
      var cancelled = false, cancelObserved = false;
      try {
        await copyLegacyCandidateUploads(
          uploadPlan,
          privateParent: copyParent,
          availableBytes: NativeLocalDataControl().availableBytes,
          isCancelled: () => cancelled,
          onProgress: (p) {
            if (p.bytes > 0 || uploadPlan.blobs.isEmpty) cancelled = true;
          },
        );
      } on LegacyRecordsCancelled {
        cancelObserved = true;
      }
      if (!cancelObserved ||
          (await copyParent.list().toList()).isNotEmpty ||
          (await sha256.bind(input.openRead()).first).toString() != expected) {
        throw StateError('Owned cancellation cleanup mismatch');
      }
      final uploadCopy = await copyLegacyCandidateUploads(
        uploadPlan,
        privateParent: copyParent,
        availableBytes: NativeLocalDataControl().availableBytes,
      );
      copiedName = paths.basename(uploadCopy.directory.path);

      database = await databaseFactory.openDatabase(
        target.path,
        options: OpenDatabaseOptions(
          version: 15,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, version) => createLegacyCandidateSchema15(db),
        ),
      );
      await database.transaction((tx) async {
        await writeLegacyCandidateMetadata(
          tx,
          records,
          importedAt: DateTime.utc(2026, 11, 8),
          onProgress: (p) => metadataRows = p.records,
        );
        await writeLegacyCandidatePrimaryRows(
          tx,
          plan,
          onProgress: (p) => primaryRows = p.rows,
        );
        await writeLegacyCandidateUploads(tx, uploadPlan, uploadCopy);
      });
    } else {
      if (targetType != FileSystemEntityType.file) {
        throw StateError('Owned candidate missing');
      }
      final built = await _jsonFile(
        File(paths.join(root.path, 'build-proof.json')),
      );
      if (built['passed'] != true ||
          built['nonce'] != nonce ||
          built['fixture'] != fixture ||
          built['source_sha256'] != expected) {
        throw StateError('Owned proof mismatch');
      }
      if (built['copy_cancel_cleanup_passed'] != true ||
          built['copied_directory'] is! String) {
        throw StateError('Owned upload observation missing');
      }
      copiedName = built['copied_directory'] as String;
      database = await databaseFactory.openDatabase(
        target.path,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA trusted_schema=OFF'),
        ),
      );
      if ((await database.rawQuery(
            'PRAGMA trusted_schema',
          )).single.values.single !=
          0) {
        throw StateError('Read-only verifier restriction unavailable');
      }
    }
    final data = await _summary(database, root, copiedName);
    await database.close();
    database = null;
    await _emit(
      root,
      phase == 'build' ? 'build-proof.json' : 'cold-proof.json',
      {
        'passed': true,
        'synthetic_only': true,
        'phase': phase,
        'nonce': nonce,
        'fixture': fixture,
        'source_sha256': expected,
        'read_only': phase == 'verify',
        ...data,
      },
    );
  } catch (error) {
    if (validatedRoot && root != null) {
      try {
        await _emit(root, 'failure-$phase.json', {
          'passed': false,
          'phase': phase,
          'error_type': error.runtimeType.toString(),
          if (error is LegacyUploadFailure) 'fixed_reason': error.reason.name,
          if (error is LegacyPrimaryWriteFailure)
            'fixed_reason': error.reason.name,
          if (error is LegacyMetadataFailure) 'fixed_reason': error.reason.name,
          'verified_metadata_rows': metadataRows,
          'verified_primary_rows': primaryRows,
          'source_values_redacted': true,
          'all45_complete': false,
        });
      } catch (_) {
        /* Preserve an existing result; never print source/provider data. */
      }
    }
  } finally {
    if (database != null && database.isOpen) {
      try {
        await database.close();
      } catch (_) {
        /* Process stop closes owned handles. */
      }
    }
  }
}
