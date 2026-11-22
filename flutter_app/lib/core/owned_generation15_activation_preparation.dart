import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'local_backup_exporter.dart';
import 'local_backup_importer.dart';
import 'local_legacy_format_selection.dart';
import 'local_legacy_zip_stage.dart';
import 'local_storage_session.dart';
import 'owned_generation15_staging.dart';

/// One explicit source selection owns one preparation. Native mutation is not
/// exposed here. Retirement is separate from Navigator lifetime and must be
/// registered in Root's transition barrier.
final class OwnedGeneration15ActivationPreparation {
  OwnedGeneration15ActivationPreparation({
    required this.zip,
    required this.selection,
    required this.session,
    required this.privateCache,
    required this.workspace,
    required this.isCurrentScope,
  });
  final LegacyZipStage zip;
  final LegacyFormatSelection selection;
  final LocalStorageSession session;
  final Directory privateCache, workspace;
  final bool Function() isCurrentScope;
  AttachmentCancellation? _request;
  Future<LocalBackupCandidate>? _work;
  Future<void>? _closing;
  LocalBackupCandidate? _candidate;
  OwnedGeneration15Staging? _stage;
  CompletedLocalBackup? _archive;
  File? _inboxFile;
  bool _retired = false, _builderCleanupUnknown = false;
  bool get current => !_retired && isCurrentScope();
  void _check() {
    if (!current || (_request?.cancelled ?? false)) {
      throw const AttachmentCancelled();
    }
  }

  Future<LocalBackupCandidate> prepare(AttachmentCancellation cancellation) {
    _check();
    final existing = _work;
    if (existing != null) return existing;
    _request = cancellation;
    return _work = _prepare();
  }

  Future<LocalBackupCandidate> _prepare() async {
    OwnedGeneration15Staging? stage;
    CompletedLocalBackup? archive;
    try {
      _check();
      if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await FileSystemEntity.type(privateCache.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await workspace.resolveSymbolicLinks() !=
              paths.normalize(workspace.path) ||
          await privateCache.resolveSymbolicLinks() !=
              paths.normalize(privateCache.path)) {
        throw const FormatException('Trusted activation workspace required');
      }
      stage = await OwnedGeneration15Staging.build(
        stage: zip,
        selection: selection,
        privateParent: workspace,
        availableBytes: session.control.availableBytes,
        isCurrentScope: () => current,
        cancellation: _request,
        factory: session.factory,
      );
      _stage = stage;
      _check();
      archive = await StagedGeneration15BackupExporter(
        stage: stage,
        factory: session.factory ?? databaseFactory,
        workspace: Directory(paths.join(workspace.path, 'archives')),
        checkPendingRecovery: () async {
          _check();
        },
      ).create();
      _archive = archive;
      _check();
      final inbox = Directory(
        paths.join(privateCache.path, 'local-backup-inbox-v1'),
      );
      final type = await FileSystemEntity.type(inbox.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await inbox.create();
      } else if (type != FileSystemEntityType.directory) {
        throw const FormatException('Activation inbox is linked');
      }
      if (await inbox.resolveSymbolicLinks() !=
          paths.join(privateCache.path, 'local-backup-inbox-v1')) {
        throw const FormatException('Activation inbox escaped');
      }
      final id = attachmentId();
      final file = File(paths.join(inbox.path, '$id.bsbackup'));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Activation inbox identity collision');
      }
      _inboxFile = file;
      final output = file.openWrite();
      try {
        await output.addStream(
          archive.file.openRead().map((bytes) {
            _check();
            return bytes;
          }),
        );
        await output.flush();
      } finally {
        await output.close();
      }
      _check();
      final candidate = await LocalBackupCandidateImporter(
        privateSupport: session.privateSupport,
        privateCache: privateCache,
        factory: session.factory ?? databaseFactory,
        availableBytes: session.control.availableBytes,
        discardCandidate: (id) async {
          await session.control.discardCandidate(id);
        },
      ).inspectPicked(id, cancellation: _request);
      _candidate = candidate;
      if (candidate.manifest.databaseSchema != 15 ||
          candidate.sourceSHA256 != archive.sha256 ||
          candidate.sourceBytes != archive.size) {
        throw const FormatException(
          'Prepared owned copy differs from source archive',
        );
      }
      _check();
      return candidate;
    } catch (error) {
      if (error is LegacyReviewCleanupRequired) _builderCleanupUnknown = true;
      final candidate = _candidate;
      if (candidate != null && !candidate.preservedForActivation) {
        await candidate.discardUnprepared();
        _candidate = null;
      }
      rethrow;
    } finally {
      await _cleanupTemporary();
    }
  }

  Future<void> _cleanupTemporary() async {
    // Keep failed cleanup handles for an explicit Root barrier retry.
    final inboxFile = _inboxFile;
    if (inboxFile != null) {
      final type = await FileSystemEntity.type(
        inboxFile.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.file) {
        await inboxFile.delete();
      } else if (type != FileSystemEntityType.notFound) {
        throw StateError('Owned activation inbox cleanup requires attention');
      }
      _inboxFile = null;
    }
    final archive = _archive;
    if (archive != null) {
      await archive.dispose();
      _archive = null;
    }
    final stage = _stage;
    if (stage != null) {
      await stage.retire();
      _stage = null;
    }
  }

  Future<void> retire() {
    _retired = true;
    _request?.cancel();
    final closing = _closing;
    if (closing != null) return closing;
    final work = () async {
      try {
        await _work;
      } catch (_) {}
      await _cleanupTemporary();
      if (_builderCleanupUnknown) {
        throw StateError('Fresh staging cleanup remains unconfirmed');
      }
      final candidate = _candidate;
      if (candidate != null && !candidate.preservedForActivation) {
        await candidate.discardUnprepared();
        _candidate = null;
      }
    }();
    _closing = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_closing, work)) _closing = null;
      }),
    );
    return work;
  }
}
