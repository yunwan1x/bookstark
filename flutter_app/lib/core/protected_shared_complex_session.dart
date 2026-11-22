import 'anonymous_shared_capability.dart';
import 'complex_recovery_vault.dart';
import 'local_complex_editor_controller.dart';
import 'local_complex_notes_repository.dart';
import 'protected_shared_identity.dart';
import 'protected_shared_journal.dart';
import 'protected_shared_lifetime.dart';
import 'protected_shared_memory_store.dart';
import 'shared_complex_store.dart';

/// Protected capability bodies use only this route-owned memory vault.
/// The persistent journal accepts hashes/receipt metadata, never source bytes.
class ProtectedSharedComplexSession {
  ProtectedSharedComplexSession._(
    this.owner,
    this.journal,
    this.repository,
    this.memory,
    this.controller,
  );
  final ProtectedSharedLifetime owner;
  final ProtectedSharedJournal journal;
  final SharedComplexStore repository;
  final ProtectedSharedMemoryStore memory;
  final LocalComplexEditorController controller;
  bool _closed = false;

  static Future<ProtectedSharedComplexSession> open({
    required ProtectedSharedLifetime owner,
    required ProtectedSharedJournal journal,
    required SharedCapabilitySource initial,
    String? password,
  }) async {
    if (!owner.current ||
        !initial.identity.protected ||
        protectedSharedIdentity(initial.identity) != journal.identity) {
      throw StateError('Protected shared identity changed');
    }
    if ((await journal.loadGroup()).isNotEmpty) {
      throw StateError(
        'Previous protected submission requires explicit review',
      );
    }
    final memory = ProtectedSharedMemoryStore(journal);
    owner.bindMemory(memory);
    final repository = SharedComplexStore(
      transport: owner.transport,
      initial: initial,
      password: password,
      isCurrent: () => owner.current,
      beforeSubmit: (baseline, document) async {
        if (!owner.current ||
            protectedSharedIdentity(baseline.identity) != journal.identity) {
          throw StateError('Protected shared owner changed');
        }
        // Called only after exact anonymous auth/CSRF preparation, immediately
        // before the single immutable CAS mutation is allowed to leave transport.
        await journal.claimUnknown(
          expectedSource: baseline.document.digest,
          submittedSource: document.digest,
        );
      },
      onKnownReceipt: (digest, modified) async {
        journal.rememberKnown(sourceDigest: digest, modified: modified);
        await journal.persistKnown(); // Storage-only retry never invokes send.
      },
    );
    try {
      final baseline = await repository.read(repository.resourceId);
      if (!owner.current) throw StateError('Protected shared owner retired');
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: repository.collection,
        kind: repository.kind,
        store: memory,
      );
      final controller = LocalComplexEditorController(
        repository: repository,
        vault: vault,
        baseline: baseline,
        ephemeralDrafts: true,
        beforeAdoptReviewed: (ComplexNote actual) async {
          if (!owner.current || actual.resourceFingerprint == null) {
            throw StateError('Protected shared review retired');
          }
          // This hook is NOT consent to discard an unknown submission. The explicit
          // record-review page must already have ended it against a fresh full FP.
          if ((await journal.loadGroup()).isNotEmpty) {
            throw StateError(
              'Review and explicitly end the submission record first',
            );
          }
        },
      );
      return ProtectedSharedComplexSession._(
        owner,
        journal,
        repository,
        memory,
        controller,
      );
    } catch (_) {
      repository.dispose();
      memory.close();
      rethrow;
    }
  }

  /// UI may retry a verified receipt's local metadata write, never the PUT.
  Future<void> retryKnownStorage() async {
    if (_closed || !owner.current || !journal.hasKnown) {
      throw StateError('No live known receipt');
    }
    await journal.persistKnown();
  }

  /// Caller owns the page/controller disposal; owner retirement erases RAM and
  /// drains exact routes before Root can activate another principal.
  Future<void> retire() async {
    if (_closed) return;
    _closed = true;
    await owner.retire();
    memory.close();
  }
}
