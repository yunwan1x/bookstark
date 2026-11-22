import 'dart:io';
import 'package:path/path.dart' as paths;
import 'attachments.dart';
import 'local_backup_exporter.dart';
import 'local_data_maintenance.dart';
import 'local_generation_state.dart';
import 'native_local_data_control.dart';

/// A pre-restore archive bound to one uninterrupted exclusive operation.
/// The native prepare operation separately validates and syncs every file.
class FreshLocalRetention {
  FreshLocalRetention._(
    this.metadata,
    this.sourcePointerRaw,
    this._gate,
    this._lease,
  );
  final LocalRetention metadata;
  final String? sourcePointerRaw;
  final LocalDataMaintenance _gate;
  final Object _lease;

  void requireFresh(LocalDataControlState baseline) {
    if (!_gate.exclusiveOperationDrained ||
        !identical(_gate.exclusiveIdentity, _lease) ||
        baseline.observation.needsReview ||
        baseline.pointerRaw != sourcePointerRaw) {
      throw StateError(
        'Pre-restore archive is no longer bound to this operation',
      );
    }
  }
}

/// Requires trusted OS roots and the already-held source maintenance operation.
/// This never installs a lock, switches data, or deletes a completed archive.
class LocalRetainedBackupBuilder {
  LocalRetainedBackupBuilder({
    required this.exporter,
    required this.control,
    String Function()? identity,
  }) : _identity = identity ?? attachmentId;
  final LocalBackupExporter exporter;
  final NativeLocalDataControl control;
  final String Function() _identity;
  static const reserveBytes = 128 * 1024 * 1024;

  Future<FreshLocalRetention> capture() async {
    final store = exporter.store;
    final gate = store.maintenance;
    final lease = gate.exclusiveIdentity;
    final layout = store.dataPaths;
    if (lease == null || !gate.exclusiveOperationDrained || layout == null) {
      throw StateError(
        'Snapshot requires the active storage exclusive operation',
      );
    }
    if (paths.normalize(exporter.attachments.path) != layout.attachments.path ||
        paths.normalize(exporter.driveBlobs.path) != layout.driveBlobs.path) {
      throw StateError('Snapshot sources do not match the current storage');
    }
    final baseline = await control.readState();
    if (baseline.observation.needsReview ||
        baseline.observation.pointer?.generation != layout.generationId) {
      throw StateError('Current local storage requires read-only review');
    }
    final support = layout.privateSupport;
    if (await support.resolveSymbolicLinks() != support.path) {
      throw const FormatException('Private storage root must be canonical');
    }
    // The SQL snapshot and framed archive coexist until the former is removed.
    // Include WAL and all owned bytes conservatively before either is created.
    var estimate = reserveBytes + 8 * 1024 * 1024;
    for (final file in [
      File(store.path),
      File('${store.path}-wal'),
      File('${store.path}-shm'),
    ]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        estimate += 3 * await file.length();
      } else if (type != FileSystemEntityType.notFound) {
        throw const FormatException('Invalid local database source');
      }
    }
    for (final directory in [layout.attachments, layout.driveBlobs]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.directory) {
        throw const FormatException('Invalid local blob source');
      }
      await for (final entry in directory.list(followLinks: false)) {
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FormatException('Unexpected local blob entry');
        }
        estimate += 2 * await File(entry.path).length();
      }
    }
    if (await control.availableBytes() < estimate) {
      throw const FileSystemException(
        'Insufficient private space for a recovery copy',
      );
    }
    final completed = await exporter.create();
    Directory? owned;
    var published = false;
    try {
      final fresh = await control.readState();
      if (fresh.pointerRaw != baseline.pointerRaw ||
          fresh.observation.needsReview ||
          !identical(gate.exclusiveIdentity, lease)) {
        throw StateError('Local source changed while retaining its snapshot');
      }
      final id = _identity();
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
        throw const FormatException('Invalid retained archive identity');
      }
      for (final directory in [
        layout.controlRoot,
        Directory(paths.join(layout.controlRoot.path, 'retained')),
      ]) {
        final type = await FileSystemEntity.type(
          directory.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          await directory.create();
        } else if (type != FileSystemEntityType.directory) {
          throw const FormatException('Invalid private retained archive root');
        }
      }
      final destination = Directory(
        paths.join(layout.controlRoot.path, 'retained', id),
      );
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Retained archive identity already exists');
      }
      await destination.create();
      owned = destination;
      // Cache and files are on the same private Android filesystem. Refuse a
      // cross-device move rather than silently duplicating a multi-GiB archive.
      await completed.file.rename(
        paths.join(destination.path, 'content.bsbackup'),
      );
      final metadata = LocalRetention(
        id: id,
        sourcePointerSHA256: baseline.pointerSHA256,
        sourceGeneration: layout.generationId ?? 'legacy',
        manifestSHA256: completed.manifestSHA256,
      );
      await File(
        paths.join(destination.path, '_ready.json'),
      ).writeAsString(metadata.encode(), flush: true);
      final result = FreshLocalRetention._(
        metadata,
        baseline.pointerRaw,
        gate,
        lease,
      );
      result.requireFresh(fresh);
      published = true;
      return result;
    } finally {
      if (!published && owned != null) {
        await owned.delete(recursive: true);
      }
      await completed.dispose();
    }
  }
}
