import 'attachments.dart';
import 'local_backup_importer.dart';
import 'local_generation_state.dart';
import 'local_retained_backup.dart';
import 'native_local_data_control.dart';

class LocalRestoreNotStarted extends StateError {
  LocalRestoreNotStarted(this.cause)
    : super('Restore stopped before closing the source session');
  final Object cause;
}

/// Applies a validated candidate only after retaining the entire current source.
/// A switched receipt still requires the separate read-only review/acknowledge UI.
class LocalRestoreCoordinator {
  LocalRestoreCoordinator({
    required this.retainedBuilder,
    String Function()? identity,
  }) : _identity = identity ?? attachmentId;
  final LocalRetainedBackupBuilder retainedBuilder;
  final String Function() _identity;
  bool _running = false;

  Future<LocalControlReceipt> apply(LocalBackupCandidate candidate) async {
    if (_running) throw StateError('A local restore is already active');
    final store = retainedBuilder.exporter.store;
    if (store.maintenance.exclusiveIdentity != null) {
      throw StateError(
        'Restore requires its own outermost maintenance operation',
      );
    }
    final layout = store.dataPaths;
    if (layout == null ||
        candidate.layout.privateSupport.path != layout.privateSupport.path ||
        candidate.layout.generationId != candidate.id ||
        candidate.id == layout.generationId) {
      throw StateError('Candidate belongs to another local storage scope');
    }
    _running = true;
    try {
      return await store.maintenance.exclusive(() async {
        var sealingStarted = false;
        try {
          final retained = await retainedBuilder.capture();
          final baseline = await retainedBuilder.control.readState();
          retained.requireFresh(baseline);
          final operationId = _identity();
          final intent = LocalRestoreIntent(
            operationId: operationId,
            sourcePointerRaw: baseline.pointerRaw,
            retainedId: retained.metadata.id,
            retainedManifestSHA256: retained.metadata.manifestSHA256,
            targetPointerRaw: LocalGenerationPointer(
              generation: candidate.id,
              epoch: (baseline.observation.pointer?.epoch ?? 0) + 1,
              activationId: operationId,
              sourceSHA256: candidate.sourceSHA256,
            ).encode(),
          );
          // From here the old UI session may never reopen this database, even
          // when close or the native durable preparation returns an error.
          sealingStarted = true;
          await store.close();
          retained.requireFresh(baseline);
          candidate.preserveForActivation();
          await retainedBuilder.control.prepare(intent);
          return await retainedBuilder.control.commit(intent);
        } catch (error, stack) {
          if (!sealingStarted) {
            Error.throwWithStackTrace(LocalRestoreNotStarted(error), stack);
          }
          rethrow;
        } finally {
          if (sealingStarted) store.maintenance.retire();
        }
      });
    } finally {
      _running = false;
    }
  }
}
