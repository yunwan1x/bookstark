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
import 'local_html_preview_document.dart';
import 'local_legacy_candidate_metadata.dart';
import 'local_legacy_candidate_rows.dart';
import 'local_legacy_candidate_schema.dart';
import 'local_legacy_candidate_uploads.dart';
import 'local_legacy_candidate_upload_copy.dart';
import 'local_legacy_format_selection.dart';
import 'local_legacy_go_export.dart';
import 'local_legacy_import_mapping.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_upload_alias_index.dart';
import 'local_legacy_upload_alias_policy.dart';
import 'local_legacy_zip_stage.dart';
import 'native_local_content_crypto.dart';

final class LegacyReviewCleanupRequired implements Exception {
  const LegacyReviewCleanupRequired();
  @override
  String toString() => 'The temporary review copy requires cleanup';
}

/// Owns a verified ephemeral copy, never the selected input or active store.
/// Only read operations escape this class; the private repository can never be saved.
final class LegacyCandidateReviewSession {
  LegacyCandidateReviewSession._(
    this._root,
    this._parentCanonical,
    this._markerSHA,
    this._database,
    this._generation,
    this._sourceSHA,
    this._scope,
    NativeLocalContentCrypto? crypto,
  ) {
    _repository = LocalGenerationContentRepository(
      database: _database,
      generation: _generation,
      isCurrent: () => isCurrent,
      crypto: crypto,
      maintenance: LocalDataMaintenance(),
    );
  }
  final Directory _root;
  final String _parentCanonical, _markerSHA, _sourceSHA;
  final Database _database;
  final LocalDataPaths _generation;
  final bool Function() _scope;
  late final LocalGenerationContentRepository _repository;
  final _handles = <GenerationContentHandle>{};
  final _opens = <AttachmentCancellation>{};
  final _views = <LegacyReviewHtmlView>{};
  final _rasterIndexes = <GenerationContentHandle, LegacyUploadAliasIndex>{};
  final _readers = <Future<void>>{};
  final _viewOwners = <Object, Future<void> Function()>{};
  bool _closed = false, _retired = false;
  int _bodyEpoch = 0;
  Future<void>? _closing;
  bool _cleanupComplete = false;

  bool get isCurrent {
    if (_closed || _retired || !_database.isOpen) return false;
    try {
      if (!_scope()) _retired = true;
    } catch (_) {
      _retired = true;
    }
    return !_retired;
  }

  void _check() {
    if (!isCurrent) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    _check();
    final done = Completer<void>();
    _readers.add(done.future);
    try {
      final value = await action();
      _check();
      return value;
    } finally {
      _readers.remove(done.future);
      done.complete();
    }
  }

  Future<GenerationContentCounts> counts() => _read(() => _repository.counts());
  Future<List<GenerationContentListEntry>> list({
    String collection = 'all',
    int page = 1,
  }) => _read(() => _repository.list(collection: collection, page: page));
  Future<GenerationContentHandle> open(
    int id, {
    String collection = 'note',
    String? password,
    AttachmentCancellation? cancellation,
  }) {
    final epoch = _bodyEpoch,
        request = cancellation ?? AttachmentCancellation();
    return _read(() async {
      _opens.add(request);
      try {
        final handle = await _repository.open(
          id,
          collection: collection,
          password: password,
          cancellation: request,
        );
        if (!isCurrent || epoch != _bodyEpoch || request.cancelled) {
          handle.close();
          throw const GenerationContentFailure(
            GenerationContentReason.cancelled,
          );
        }
        _handles.add(handle);
        return handle;
      } finally {
        _opens.remove(request);
      }
    });
  }

  LegacyReviewHtmlView html(GenerationContentHandle handle) {
    _check();
    if (!_handles.contains(handle) || !handle.isCurrent) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    final index = LegacyUploadAliasIndex(
      database: _database,
      generation: _generation,
      sourceSha256: _sourceSHA,
      policy: LegacyUploadAliasPolicy(
        isolatedOrigin: Uri.parse(
          'https://${_generation.generationId}.bookstark-local.invalid',
        ),
      ),
      isCurrent: () => isCurrent,
    );
    try {
      final view = LegacyReviewHtmlView._(
        this,
        index,
        GenerationHtmlRasterBinding(index: index, content: handle),
      );
      _views.add(view);
      return view;
    } catch (_) {
      index.dispose();
      rethrow;
    }
  }

  Future<LocalHtmlRasterResponse?> raster(
    GenerationContentHandle handle,
    String url,
  ) async {
    if (!isCurrent || !_handles.contains(handle) || !handle.isCurrent) {
      return null;
    }
    try {
      return await _read(() async {
        final index = _rasterIndexes.putIfAbsent(
          handle,
          () => LegacyUploadAliasIndex(
            database: _database,
            generation: _generation,
            sourceSha256: _sourceSHA,
            policy: LegacyUploadAliasPolicy(
              isolatedOrigin: Uri.parse(
                'https://${_generation.generationId}.bookstark-local.invalid',
              ),
            ),
            isCurrent: () => isCurrent,
          ),
        );
        final result = await index.readRaster(url, content: handle);
        if (result == null || !handle.isCurrent) return null;
        return LocalHtmlRasterResponse(mime: result.mime, bytes: result.bytes);
      });
    } catch (_) {
      return null;
    }
  }

  /// Register the route's owned retirement barrier before it can show content.
  void attachViewer(Object owner, Future<void> Function() closeView) {
    _check();
    if (_viewOwners.containsKey(owner)) {
      throw StateError('Review viewer is already attached');
    }
    _viewOwners[owner] = closeView;
  }

  Future<void> detachViewer(Object owner) async {
    final closeView = _viewOwners[owner];
    if (closeView == null) return;
    await closeView();
    if (identical(_viewOwners[owner], closeView)) _viewOwners.remove(owner);
  }

  /// Callers first await retirement of their own rendered native views.
  void lockContent() {
    _bodyEpoch++;
    for (final request in _opens.toList()) {
      request.cancel();
    }
    for (final index in _rasterIndexes.values) {
      index.dispose();
    }
    _rasterIndexes.clear();
    for (final view in _views.toList()) {
      view.dispose();
    }
    for (final handle in _handles.toList()) {
      handle.close();
    }
    _handles.clear();
  }

  Future<void> close() {
    if (_cleanupComplete) return Future<void>.value();
    final pending = _closing;
    if (pending != null) return pending;
    final work = _close();
    _closing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_closing, work)) _closing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _close() async {
    _closed = true;
    for (final closeView in _viewOwners.values.toList()) {
      await closeView();
    }
    _viewOwners.clear();
    lockContent();
    _repository.dispose();
    await Future.wait(_readers.toList());
    if (_database.isOpen) {
      await _repository.maintenance.exclusive(() async {
        await _database.close();
        _repository.maintenance.retire();
      });
    }
    if (!await _deleteOwned(_root, _parentCanonical, _markerSHA)) {
      throw const LegacyReviewCleanupRequired();
    }
    _cleanupComplete = true;
  }

  static Future<LegacyCandidateReviewSession> build({
    required LegacyZipStage stage,
    required LegacyFormatSelection selection,
    required Directory privateParent,
    required Future<int> Function() availableBytes,
    required bool Function() isCurrentScope,
    DatabaseFactory? factory,
    AttachmentCancellation? cancellation,
    NativeLocalContentCrypto? crypto,
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
      root = await privateParent.createTemp('review-');
      final random = Random.secure();
      final nonce = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final marker = utf8.encode(
        jsonEncode({
          'format': 1,
          'kind': 'legacy-candidate-review',
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
      final result = LegacyCandidateReviewSession._(
        root,
        parentCanonical,
        markerSHA,
        reading,
        generation,
        source.sourceSha256,
        isCurrentScope,
        crypto,
      );
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
        !paths.basename(root.path).startsWith('review-') ||
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

final class LegacyReviewHtmlView {
  LegacyReviewHtmlView._(this._owner, this._index, this._binding);
  final LegacyCandidateReviewSession _owner;
  final LegacyUploadAliasIndex _index;
  final GenerationHtmlRasterBinding _binding;
  bool _closed = false;
  bool get isCurrent => !_closed && _owner.isCurrent && _binding.isCurrent;
  String get scopeKey => _binding.scopeKey;
  LocalHtmlPreviewDocument get document {
    _owner._check();
    if (!isCurrent) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    return _binding.document;
  }

  Future<LocalHtmlRasterResponse?> load(String url) async {
    if (!isCurrent) return null;
    try {
      return await _owner._read(() => _binding.load(url));
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _binding.dispose();
    _index.dispose();
    _owner._views.remove(this);
  }
}
