import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/scoped_complex_recovery_store.dart';
import 'remote_owned_complex_store.dart';

enum RemoteComplexDraftChoice { restore, discard, cancel }

class RemoteOwnedComplexSession {
  RemoteOwnedComplexSession._(
    this.repository,
    this.vault,
    this.baseline,
    this.recovery,
    this.bytes,
  );
  final RemoteOwnedComplexStore repository;
  final ComplexRecoveryVault vault;
  final ComplexNote baseline;
  final ComplexRecoveryRecord? recovery;
  final ScopedComplexRecoveryStore bytes;
  bool _transferred = false;
  static Future<RemoteOwnedComplexSession> inspect({
    required BookstarkClient client,
    required int memberId,
    required int resourceId,
    required int bookId,
    required bool note,
    required ComplexEditorKind kind,
    required String recoveryNamespace,
    required bool Function() isCurrent,
    ComplexRecoveryBytesStore? recoveryStore,
  }) async {
    final repository = RemoteOwnedComplexStore(
      client: client,
      memberId: memberId,
      resourceId: resourceId,
      bookId: bookId,
      kind: kind,
      note: note,
      recoveryNamespace: recoveryNamespace,
      isCurrent: isCurrent,
    );
    final bytes = ScopedComplexRecoveryStore(
      recoveryStore ?? NativeComplexRecoveryStore(),
      isCurrent: () =>
          isCurrent() && client.sessionRevision == repository.revision,
    );
    try {
      final baseline = await repository.read(resourceId);
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: repository.collection,
        kind: kind,
        store: bytes,
      );
      final recovery = await vault.read(resourceId);
      if (!isCurrent() || client.sessionRevision != repository.revision) {
        throw StateError('Remote owner retired');
      }
      return RemoteOwnedComplexSession._(
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
    RemoteComplexDraftChoice choice,
  ) async {
    if (_transferred) throw StateError('Session already transferred');
    if (choice == RemoteComplexDraftChoice.cancel) return null;
    var selected = recovery;
    if (requiresChoice && choice == RemoteComplexDraftChoice.discard) {
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
