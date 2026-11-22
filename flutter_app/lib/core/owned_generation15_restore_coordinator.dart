import 'dart:io';
import 'package:path/path.dart' as paths;
import 'attachments.dart';
import 'local_backup_exporter.dart';
import 'local_backup_importer.dart';
import 'local_generation_state.dart';
import 'local_restore_coordinator.dart';
import 'native_local_data_control.dart';
import 'owned_writable_generation15.dart';

/// Complete source retention precedes sealing. This coordinator cannot accept
/// a read-only candidate as its source, and never acknowledges a switched DB.
final class OwnedGeneration15RestoreCoordinator {
  OwnedGeneration15RestoreCoordinator({
    required this.owner,
    required this.exporter,
    required this.control,
    required this.beforeSeal,
    String Function()? identity,
  }) : _identity = identity ?? attachmentId;
  final OwnedWritableGeneration15 owner;
  final OwnedGeneration15BackupExporter exporter;
  final NativeLocalDataControl control;
  final Future<void> Function() beforeSeal;
  final String Function() _identity;
  bool _running = false;
  Future<LocalControlReceipt> apply(LocalBackupCandidate candidate) async {
    if (_running) throw StateError('Owned restore already active');
    if (!identical(exporter.owner, owner) ||
        candidate.layout.privateSupport.path !=
            owner.generation.privateSupport.path ||
        candidate.id == owner.generation.generationId ||
        candidate.layout.generationId != candidate.id) {
      throw StateError('Owned restore candidate belongs to another scope');
    }
    _running = true;
    try {
      // Retire/drain preview readers before requesting exclusive DB access.
      // Waiting for a preview's queued shared read while holding exclusive
      // maintenance would deadlock. This callback must NOT retire the owner.
      try {
        await beforeSeal();
      } catch (error, stack) {
        Error.throwWithStackTrace(LocalRestoreNotStarted(error), stack);
      }
      return await owner.exclusiveSnapshot((database) async {
        var sealing = false;
        CompletedLocalBackup? completed;
        Directory? unpublished;
        try {
          await owner.confirmCurrent();
          var estimate = 128 * 1024 * 1024;
          for (final suffix in ['', '-wal', '-shm']) {
            final file = File(owner.generation.databasePath + suffix);
            final type = await FileSystemEntity.type(
              file.path,
              followLinks: false,
            );
            if (type == FileSystemEntityType.file) {
              estimate += 3 * await file.length();
            } else if (type != FileSystemEntityType.notFound) {
              throw const FormatException('Owned source journal is linked');
            }
          }
          for (final folder in [
            owner.generation.attachments,
            owner.generation.driveBlobs,
          ]) {
            await for (final entry in folder.list(followLinks: false)) {
              if (await FileSystemEntity.type(entry.path, followLinks: false) !=
                  FileSystemEntityType.file) {
                throw const FormatException(
                  'Owned source resources are linked or nested',
                );
              }
              estimate += 2 * await File(entry.path).length();
            }
          }
          if (await control.availableBytes() < estimate) {
            throw const LocalBackupSpaceUnavailable();
          }
          completed = await exporter.create();
          await owner.confirmCurrent();
          final baseline = await control.readState();
          if (baseline.observation.needsReview ||
              baseline.pointerRaw != owner.pointer.encode()) {
            throw StateError('Owned source changed while retaining backup');
          }
          final id = _identity();
          if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
            throw const FormatException('Invalid owned retention identity');
          }
          final retained = Directory(
            paths.join(owner.generation.controlRoot.path, 'retained'),
          );
          final kind = await FileSystemEntity.type(
            retained.path,
            followLinks: false,
          );
          if (kind == FileSystemEntityType.notFound) {
            await retained.create();
          } else if (kind != FileSystemEntityType.directory) {
            throw const FormatException('Owned retention root is linked');
          }
          if (await retained.resolveSymbolicLinks() !=
              paths.join(
                await owner.generation.controlRoot.resolveSymbolicLinks(),
                'retained',
              )) {
            throw const FormatException('Owned retention root escaped');
          }
          final destination = Directory(paths.join(retained.path, id));
          if (await FileSystemEntity.type(
                destination.path,
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound) {
            throw StateError('Owned retention identity already exists');
          }
          await destination.create();
          unpublished = destination;
          await completed.file.rename(
            paths.join(destination.path, 'content.bsbackup'),
          );
          final metadata = LocalRetention(
            id: id,
            sourcePointerSHA256: baseline.pointerSHA256,
            sourceGeneration: owner.generation.generationId!,
            manifestSHA256: completed.manifestSHA256,
          );
          await File(
            paths.join(destination.path, '_ready.json'),
          ).writeAsString(metadata.encode(), flush: true);
          // A published retained source is never deleted after a late callback,
          // failed close, uncertain native prepare or commit.
          unpublished = null;
          await owner.confirmCurrent();
          final operation = _identity();
          if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(operation)) {
            throw const FormatException('Invalid owned activation identity');
          }
          final intent = LocalRestoreIntent(
            operationId: operation,
            sourcePointerRaw: baseline.pointerRaw,
            retainedId: id,
            retainedManifestSHA256: metadata.manifestSHA256,
            targetPointerRaw: LocalGenerationPointer(
              generation: candidate.id,
              epoch: owner.pointer.epoch + 1,
              activationId: operation,
              sourceSHA256: candidate.sourceSHA256,
            ).encode(),
          );
          sealing = true;
          await owner.sealForActivationWithinSnapshot();
          candidate.preserveForActivation();
          await control.prepare(intent);
          return await control.commit(intent);
        } catch (error, stack) {
          if (!sealing) {
            Error.throwWithStackTrace(LocalRestoreNotStarted(error), stack);
          }
          rethrow;
        } finally {
          if (unpublished != null) await unpublished.delete(recursive: true);
          await completed?.dispose();
        }
      });
    } finally {
      _running = false;
    }
  }
}
