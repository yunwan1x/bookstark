import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'local_backup_importer.dart' show LocalBackupSpaceUnavailable;
import 'local_data_maintenance.dart';
import 'local_data_paths.dart';
import 'local_generation_content_repository.dart';
import 'local_legacy_candidate_metadata.dart';
import 'local_legacy_candidate_rows.dart';
import 'local_legacy_candidate_schema.dart';
import 'local_legacy_candidate_uploads.dart';
import 'local_legacy_candidate_upload_copy.dart';
import 'local_legacy_format_selection.dart';
import 'local_legacy_go_export.dart';
import 'local_legacy_import_mapping.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_zip_stage.dart';
import 'owned_generation15_schema.dart';

/// Freshly rebuilt from the selected ZIP and explicit format recipe. No API
/// accepts a ReviewSession or its database; this object grants no live writer.
final class OwnedGeneration15Staging {
  OwnedGeneration15Staging._(
    this._root,
    this._parent,
    this._markerSHA,
    this._proofSHA,
    this.generation,
    this._factory,
    this._scope,
  );
  final Directory _root;
  final String _parent, _markerSHA, _proofSHA;
  final DatabaseFactory _factory;
  final bool Function() _scope;
  final LocalDataPaths generation;
  final _gate = LocalDataMaintenance();
  bool _retired = false;
  Future<void>? _closing;

  void _check() {
    if (_retired || !_scope()) throw StateError('Owned staging scope changed');
  }

  Future<void> _identity() async {
    _check();
    if (await FileSystemEntity.type(_root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await _root.resolveSymbolicLinks() !=
            paths.join(_parent, paths.basename(_root.path))) {
      throw const FormatException('Owned staging identity changed');
    }
    var current = _root.path;
    for (final component in [
      'local-data-v1',
      'generations',
      generation.generationId!,
      'database',
    ]) {
      current = paths.join(current, component);
      if (await FileSystemEntity.type(current, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Owned staging database parent changed');
      }
    }
    final rootCanonical = await _root.resolveSymbolicLinks();
    if (await FileSystemEntity.type(
              generation.databasePath,
              followLinks: false,
            ) !=
            FileSystemEntityType.file ||
        await File(generation.databasePath).resolveSymbolicLinks() !=
            paths.join(
              rootCanonical,
              'local-data-v1',
              'generations',
              generation.generationId!,
              'database',
              'content.db',
            )) {
      throw const FormatException('Owned staging database escaped');
    }
    for (final suffix in ['-wal', '-journal']) {
      final file = File(generation.databasePath + suffix);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          (type != FileSystemEntityType.file || await file.length() != 0)) {
        throw const FormatException(
          'Closed staging contains unmerged journal data',
        );
      }
    }
    final shm = File('${generation.databasePath}-shm');
    final shmType = await FileSystemEntity.type(shm.path, followLinks: false);
    if (shmType != FileSystemEntityType.notFound &&
        shmType != FileSystemEntityType.file) {
      throw const FormatException('Closed staging sidecar is linked');
    }
    for (final folder in [generation.attachments, generation.driveBlobs]) {
      if (await FileSystemEntity.type(folder.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await folder.resolveSymbolicLinks() !=
              paths.join(
                rootCanonical,
                'local-data-v1',
                'generations',
                generation.generationId!,
                paths.basename(folder.path),
              )) {
        throw const FormatException('Owned staging resource root changed');
      }
    }
    for (final spec in [
      ('owned.json', _markerSHA),
      ('activation-proof.json', _proofSHA),
    ]) {
      final file = File(paths.join(_root.path, spec.$1));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 65536 ||
          sha256.convert(await file.readAsBytes()).toString() != spec.$2) {
        throw const FormatException('Owned staging proof changed');
      }
    }
    _check();
  }

  Future<T> readSnapshot<T>(Future<T> Function(Database database) read) =>
      _gate.use(() async {
        await _identity();
        final db = await _factory.openDatabase(
          generation.databasePath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          await db.execute('PRAGMA query_only=ON');
          if ((await db.rawQuery('PRAGMA query_only')).single.values.single !=
              1) {
            throw const FormatException(
              'Owned staging read-only guard unavailable',
            );
          }
          final before = await OwnedGeneration15SchemaGate().rowDigests(
            db,
            isCurrent: () => !_retired && _scope(),
          );
          final proof =
              jsonDecode(
                    await File(
                      paths.join(_root.path, 'activation-proof.json'),
                    ).readAsString(),
                  )
                  as Map;
          if (jsonEncode(before) != jsonEncode(proof['typedRows'])) {
            throw const FormatException('Owned staged rows changed');
          }
          final result = await read(db);
          await _identity();
          final after = await OwnedGeneration15SchemaGate().rowDigests(
            db,
            isCurrent: () => !_retired && _scope(),
          );
          if (jsonEncode(before) != jsonEncode(after)) {
            throw const FormatException('Owned staging read changed data');
          }
          return result;
        } finally {
          await db.close();
        }
      });
  Future<void> retire() {
    _retired = true;
    final existing = _closing;
    if (existing != null) return existing;
    final work = _gate.exclusive(() async {
      if (!await _deleteOwned(_root, _parent, _markerSHA)) {
        throw StateError('Owned staging cleanup requires attention');
      }
      _gate.retire();
    });
    _closing = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_closing, work)) _closing = null;
      }),
    );
    return work;
  }

  static Future<OwnedGeneration15Staging> build({
    required LegacyZipStage stage,
    required LegacyFormatSelection selection,
    required Directory privateParent,
    required Future<int> Function() availableBytes,
    required bool Function() isCurrentScope,
    DatabaseFactory? factory,
    AttachmentCancellation? cancellation,
  }) async {
    final request = cancellation ?? AttachmentCancellation();
    void check() {
      if (request.cancelled) {
        throw const GenerationContentFailure(GenerationContentReason.cancelled);
      }
      bool current = false;
      try {
        current = isCurrentScope();
      } catch (_) {}
      if (!current) {
        throw const GenerationContentFailure(GenerationContentReason.retired);
      }
    }

    check();
    if (!selection.complete ||
        selection.source.archiveSha256 != stage.sourceSha256 ||
        !paths.isAbsolute(privateParent.path) ||
        await FileSystemEntity.type(privateParent.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    final parentCanonical = await privateParent.resolveSymbolicLinks();
    check();
    // Inspect actual staged bytes again, not the mutable previously shown objects.
    final source = await LegacyGoExport.inspect(
      stage,
      isCancelled: () => request.cancelled || !isCurrentScope(),
    );
    check();
    final mapping = LegacyImportMapping.fromRecipe(
      source,
      selection.toJson(),
      scopeKey: selection.source.scopeKey,
    );
    final records = LegacyImportRecords.fromExport(source, mapping);
    final rows = LegacyCandidateRows.fromRecords(
      records,
      isCancelled: () => request.cancelled,
    );
    final uploads = LegacyCandidateUploads.fromRecords(records, stage);
    var sqlBytes = 0;
    for (final record in records.records(
      isCancelled: () => request.cancelled,
    )) {
      check();
      sqlBytes += record.bytes + 4096;
    }
    for (final relation in records.labelRelations(
      isCancelled: () => request.cancelled,
    )) {
      check();
      sqlBytes += relation.bytes + 4096;
    }
    for (final row in rows.rows(isCancelled: () => request.cancelled)) {
      check();
      sqlBytes += 4096;
      for (final value in row.values.values) {
        if (value is String) sqlBytes += utf8.encode(value).length;
      }
    }
    Future<void> space(int required) async {
      check();
      final free = await availableBytes();
      check();
      if (free < required) throw const LocalBackupSpaceUnavailable();
    }

    const reserve = 128 * 1024 * 1024;
    await space(reserve + 3 * sqlBytes + uploads.totalBytes);
    Directory? root;
    Database? writing, reading;
    String? markerSHA;
    final dbFactory = factory ?? databaseFactory;
    try {
      root = await privateParent.createTemp('owned15-stage-');
      final random = Random.secure();
      final nonce = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final marker = utf8.encode(
        jsonEncode({
          'format': 1,
          'kind': 'owned-generation15-staging',
          'nonce': nonce,
          'sourceSHA256': source.sourceSha256,
          'recipeSHA256': mapping.recipeSha256,
        }),
      );
      markerSHA = sha256.convert(marker).toString();
      await File(
        paths.join(root.path, 'owned.json'),
      ).writeAsBytes(marker, flush: true);
      check();
      final generation = LocalDataPaths.generation(
        id: nonce,
        privateSupport: root,
      );
      final work = await Directory(paths.join(root.path, 'copy-work')).create();
      check();
      final copied = await copyLegacyCandidateUploads(
        uploads,
        privateParent: work,
        availableBytes: availableBytes,
        isCancelled: () => request.cancelled || !isCurrentScope(),
      );
      check();
      await space(reserve + 3 * sqlBytes);
      await File(generation.databasePath).parent.create(recursive: true);
      check();
      writing = await dbFactory.openDatabase(
        generation.databasePath,
        options: OpenDatabaseOptions(
          version: 15,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, v) => createLegacyCandidateSchema15(db),
        ),
      );
      check();
      await writing.transaction((tx) async {
        await writeLegacyCandidateMetadata(
          tx,
          records,
          importedAt: DateTime.now().toUtc(),
          isCancelled: () => request.cancelled || !isCurrentScope(),
        );
        check();
        await writeLegacyCandidatePrimaryRows(
          tx,
          rows,
          isCancelled: () => request.cancelled || !isCurrentScope(),
        );
        check();
        await writeLegacyCandidateUploads(
          tx,
          uploads,
          copied,
          isCancelled: () => request.cancelled || !isCurrentScope(),
        );
        check();
        await space(reserve);
      });
      check();
      if (await FileSystemEntity.type(
            generation.attachments.path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      await copied.directory.rename(generation.attachments.path);
      await generation.driveBlobs.create();
      check();
      final expectedFiles = uploads.blobs.map((b) => b.attachmentId).toSet();
      final actualFiles = <String>{};
      await for (final entry in generation.attachments.list(
        followLinks: false,
      )) {
        check();
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        actualFiles.add(paths.basename(entry.path));
      }
      if (actualFiles.length != expectedFiles.length ||
          !actualFiles.containsAll(expectedFiles)) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      for (final blob in uploads.blobs) {
        check();
        final file = File(
          paths.join(generation.attachments.path, blob.attachmentId),
        );
        if (await file.length() != blob.bytes) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        final digest = await sha256
            .bind(
              file.openRead().map((bytes) {
                check();
                return bytes;
              }),
            )
            .first;
        check();
        if (digest.toString() != blob.sha256Hex ||
            await file.length() != blob.bytes) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
      }
      final integrity = await writing.rawQuery('PRAGMA integrity_check');
      check();
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          (await writing.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      await writing.close();
      writing = null;
      check();
      reading = await dbFactory.openDatabase(
        generation.databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await reading.execute('PRAGMA query_only=ON');
      check();
      if ((await reading.rawQuery('PRAGMA query_only')).single.values.single !=
          1) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      check();
      final gate = OwnedGeneration15SchemaGate();
      await gate.verify(reading, factory: dbFactory, workspace: work);
      final typedRows = await gate.rowDigests(
        reading,
        isCurrent: () => !request.cancelled && isCurrentScope(),
      );
      check();
      final metadata = await reading.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='android_metadata'",
      );
      final locale = metadata.isEmpty
          ? null
          : {
              'columns': await reading.rawQuery(
                'PRAGMA table_info(android_metadata)',
              ),
              'rowsSHA256': typedRows['android_metadata'],
            };
      final proof = utf8.encode(
        jsonEncode({
          'format': 1,
          'kind': 'owned15-fresh-staging',
          'sourceSHA256': source.sourceSha256,
          'recipeSHA256': mapping.recipeSha256,
          'typedRows': typedRows,
          'runtimeMetadata': locale,
          'freshDatabase': true,
        }),
      );
      if (proof.length > 65536) {
        throw const FormatException('Owned staging proof bound');
      }
      final proofSHA = sha256.convert(proof).toString();
      await File(
        paths.join(root.path, 'activation-proof.json'),
      ).writeAsBytes(proof, flush: true);
      check();
      final result = OwnedGeneration15Staging._(
        root,
        parentCanonical,
        markerSHA,
        proofSHA,
        generation,
        dbFactory,
        isCurrentScope,
      );
      await reading.close();
      reading = null;
      return result;
    } catch (_) {
      await writing?.close();
      await reading?.close();
      if (root != null &&
          markerSHA != null &&
          !await _deleteOwned(root, parentCanonical, markerSHA)) {
        throw const LegacyReviewCleanupRequired();
      }
      rethrow;
    }
  }
}

Future<bool> _deleteOwned(
  Directory root,
  String parent,
  String markerSHA,
) async {
  try {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.directory ||
        !paths.basename(root.path).startsWith('owned15-stage-') ||
        await root.resolveSymbolicLinks() !=
            paths.join(parent, paths.basename(root.path))) {
      return false;
    }
    final marker = File(paths.join(root.path, 'owned.json'));
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await marker.length() > 4096 ||
        sha256.convert(await marker.readAsBytes()).toString() != markerSHA) {
      return false;
    }
    await for (final child in root.list(followLinks: false)) {
      if (!{
        'owned.json',
        'local-data-v1',
        'copy-work',
        'activation-proof.json',
      }.contains(paths.basename(child.path))) {
        return false;
      }
    }
    await root.delete(recursive: true);
    return true;
  } catch (_) {
    return false;
  }
}

final class LegacyReviewCleanupRequired implements Exception {
  const LegacyReviewCleanupRequired();
  @override
  String toString() => 'Owned staging cleanup requires attention';
}
