import 'anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/scoped_complex_recovery_store.dart';
import 'shared_complex_store.dart';

enum SharedComplexDraftChoice { restore, discard, cancel }

class SharedComplexSession {
  SharedComplexSession._(
    this.repository,
    this.vault,
    this.baseline,
    this.recovery,
    this.bytes,
  );
  final SharedComplexStore repository;
  final ComplexRecoveryVault vault;
  final ComplexNote baseline;
  final ComplexRecoveryRecord? recovery;
  final ScopedComplexRecoveryStore bytes;
  bool _transferred = false;
  static Future<SharedComplexSession> inspect({
    required AnonymousSharedCapability transport,
    required SharedCapabilitySource initial,
    String? password,
    required bool Function() isCurrent,
    ComplexRecoveryBytesStore? recoveryStore,
  }) async {
    final repository = SharedComplexStore(
      transport: transport,
      initial: initial,
      password: password,
      isCurrent: isCurrent,
    );
    final bytes = ScopedComplexRecoveryStore(
      recoveryStore ?? NativeComplexRecoveryStore(),
      isCurrent: isCurrent,
    );
    try {
      final baseline = await repository.read(repository.resourceId);
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: repository.collection,
        kind: repository.kind,
        store: bytes,
      );
      final recovery = await vault.read(repository.resourceId);
      if (!isCurrent()) throw StateError('Shared capability retired');
      return SharedComplexSession._(
        repository,
        vault,
        baseline,
        recovery,
        bytes,
      );
    } catch (_) {
      repository.dispose();
      bytes.retire();
      rethrow;
    }
  }

  bool get requiresChoice =>
      recovery != null &&
      !recovery!.pending &&
      recovery!.baselineMatches(baseline);
  Future<LocalComplexEditorController?> enter(
    SharedComplexDraftChoice choice,
  ) async {
    if (_transferred) throw StateError('Session already transferred');
    if (choice == SharedComplexDraftChoice.cancel) return null;
    var selected = recovery;
    if (requiresChoice && choice == SharedComplexDraftChoice.discard) {
      await vault.remove(baseline.id);
      selected = null;
    }
    final controller = LocalComplexEditorController(
      repository: repository,
      vault: vault,
      baseline: baseline,
      recovery: selected,
    );
    _transferred = true;
    return controller;
  }

  void retire() {
    bytes.retire();
    if (!_transferred) repository.dispose();
  }
}
