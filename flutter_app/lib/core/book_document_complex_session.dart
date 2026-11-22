import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'local_book_document_complex_store.dart';
import 'scoped_complex_recovery_store.dart';

enum BookDocumentDraftChoice { restore, discard, cancel }

/// Root holds the existing HtmlEditorLease until route completion and provides
/// the existing draft choice/review UI. No automatic draft acceptance.
class BookDocumentComplexSession {
  BookDocumentComplexSession._(
    this.repository,
    this.vault,
    this.baseline,
    this.recovery,
    this.bytes,
  );
  final LocalBookDocumentComplexStore repository;
  final ComplexRecoveryVault vault;
  final ComplexNote baseline;
  final ComplexRecoveryRecord? recovery;
  final ScopedComplexRecoveryStore bytes;
  bool _transferred = false;
  static Future<BookDocumentComplexSession> inspect({
    required LocalStore store,
    required int bookId,
    required int documentId,
    required ComplexEditorKind kind,
    required ComplexRecoveryBytesStore recoveryStore,
    required bool Function() isCurrent,
  }) async {
    final repository = LocalBookDocumentComplexStore(
      store,
      bookId: bookId,
      kind: kind,
      isCurrent: isCurrent,
    );
    final bytes = ScopedComplexRecoveryStore(
      recoveryStore,
      isCurrent: () => isCurrent() && !store.maintenance.retired,
    );
    try {
      final baseline = await repository.read(documentId);
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: repository.collection,
        kind: kind,
        store: bytes,
        maintenance: store.maintenance,
      );
      final recovery = await vault.read(documentId);
      if (!isCurrent() || store.maintenance.retired) {
        throw StateError('Retired');
      }
      return BookDocumentComplexSession._(
        repository,
        vault,
        baseline,
        recovery,
        bytes,
      );
    } catch (_) {
      bytes.retire();
      repository.dispose();
      rethrow;
    }
  }

  bool get requiresExplicitDraftChoice =>
      recovery != null &&
      !recovery!.pending &&
      recovery!.baselineMatches(baseline);
  bool get requiresUnknownReview =>
      recovery != null &&
      (recovery!.pending || !recovery!.baselineMatches(baseline));
  Future<LocalComplexEditorController?> enter({
    required BookDocumentDraftChoice choice,
  }) async {
    if (_transferred) throw StateError('Session already transferred');
    if (choice == BookDocumentDraftChoice.cancel) return null;
    var selected = recovery;
    // Pending or mismatched drafts are always review-only initially; discard
    // cannot bypass the existing fresh-observation/conflict workflow.
    if (requiresExplicitDraftChoice &&
        choice == BookDocumentDraftChoice.discard) {
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

  /// Call after route/controller disposal; retirement never clears saved/draft data.
  void retire() {
    bytes.retire();
    if (!_transferred) repository.dispose();
  }
}
