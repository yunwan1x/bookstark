import 'dart:typed_data';
import 'complex_editor_document.dart';
import 'complex_recovery_vault.dart';
import 'draft_vault.dart';
import 'local_complex_notes_repository.dart';
import 'local_data_maintenance.dart';
import 'notes_repository.dart';
import 'secure_record_store.dart';
import 'local_article_draft_receipt.dart';
export 'local_article_draft_receipt.dart' show LocalArticleDraftDisposition;

/// Immutable user-reviewed old draft. Its original record is never deleted.
final class LocalArticleLegacyDraft {
  LocalArticleLegacyDraft._(this.id, this.digest, this.edit);
  final int id;
  final String digest;
  final ComplexNoteEdit edit;
}

/// Transfer is recovery-first, then a durable metadata-only receipt. An
/// interrupted receipt can be retried without replacing another recovery.
final class LocalArticleDraftHandoff {
  LocalArticleDraftHandoff({
    required this.legacy,
    required String expectedLegacyNamespace,
    required this.recovery,
    required this.maintenance,
    required this.readCurrent,
    required this.flushMarker,
    required this.isCurrentScope,
    this.fingerprintLegacyDraft,
  }) : _markers = SecureRecordStore(
         prefix: LocalArticleDraftReceipt.recordPrefix,
         namespace: legacy.namespace,
         maintenance: maintenance,
         readValue: legacy.readValue,
         writeValue: legacy.writeValue,
         deleteValue: legacy.deleteValue,
       ) {
    if (recovery.collection != 'article' ||
        recovery.kind != ComplexEditorKind.markdown ||
        legacy.namespace.isEmpty ||
        legacy.namespace != expectedLegacyNamespace ||
        !identical(legacy.maintenance, maintenance) ||
        !identical(recovery.maintenance, maintenance)) {
      throw ArgumentError('Owned local Markdown article recovery required');
    }
  }
  final DraftVault legacy;
  final ComplexRecoveryVault recovery;
  final LocalDataMaintenance maintenance;
  final Future<ComplexNote> Function(int id) readCurrent;
  final Future<void> Function() flushMarker;
  final bool Function() isCurrentScope;
  final Future<String?> Function(int id)? fingerprintLegacyDraft;
  final SecureRecordStore _markers;

  void _check(ComplexNote baseline) {
    if (!isCurrentScope() ||
        maintenance.retired ||
        baseline.id <= 0 ||
        baseline.collection != 'article' ||
        baseline.document.kind != ComplexEditorKind.markdown ||
        baseline.scope != recovery.scope) {
      throw StateError('Local article draft scope changed');
    }
  }

  String _digest(Note value, int id) => LocalArticleDraftReceipt.digestOf(
    namespace: legacy.namespace,
    id: id,
    title: value.title,
    source: value.content,
    labels: value.labels,
  );

  Future<LocalArticleLegacyDraft?> _candidate(int id) async {
    final value = await legacy.read(id);
    if (value == null) return null;
    final edit = ComplexNoteEdit(
      title: value.title,
      document: ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        value.content,
      ),
      labels: value.labels,
    );
    edit.validate();
    return LocalArticleLegacyDraft._(id, _digest(value, id), edit);
  }

  Future<LocalArticleDraftReceipt?> _handledReceipt(int id) async {
    final raw = await _markers.readRecord(id);
    if (raw == null) return null;
    final value = LocalArticleDraftReceipt.parse(raw);
    // Do not trust a receipt left only in the plugin's in-memory preferences.
    await flushMarker();
    return value;
  }

  Future<String?> _fingerprint(int id) async {
    final read = fingerprintLegacyDraft;
    if (read == null) {
      return null; // Compatibility with non-Android model stores.
    }
    final value = await read(id);
    if (value == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw StateError('Old article draft fingerprint unavailable');
    }
    return value;
  }

  Future<LocalArticleLegacyDraft?> inspect(
    ComplexNote baseline, {
    bool forceReview = false,
  }) => maintenance.exclusive(() async {
    _check(baseline);
    final draft = await _candidate(baseline.id);
    _check(baseline);
    if (draft == null) return null;
    if (draft.edit.matches(baseline)) {
      // Already saved bytes need no offer or new recovery copy. Preserve the
      // original record, but bind its archive metadata to its current ciphertext.
      if (fingerprintLegacyDraft != null) {
        await _mark(draft, LocalArticleDraftDisposition.matched, baseline);
      }
      return null;
    }
    final handled = await _handledReceipt(baseline.id);
    _check(baseline);
    if (!forceReview && handled?.digest == draft.digest) {
      if (fingerprintLegacyDraft != null) {
        final fingerprint = await _fingerprint(draft.id);
        _check(baseline);
        if (handled!.ciphertextSHA256 != fingerprint) {
          // Upgrade an old receipt only after the actual old source matched.
          await _mark(
            draft,
            handled.disposition,
            baseline,
            knownFingerprint: fingerprint,
          );
        }
      }
      return null;
    }
    return draft;
  });

  Future<void> _mark(
    LocalArticleLegacyDraft draft,
    LocalArticleDraftDisposition disposition,
    ComplexNote baseline, {
    String? knownFingerprint,
  }) async {
    _check(baseline);
    final fingerprint = knownFingerprint ?? await _fingerprint(draft.id);
    _check(baseline);
    await _verifyCandidate(draft, baseline);
    final receipt = LocalArticleDraftReceipt(
      digest: draft.digest,
      disposition: disposition,
      ciphertextSHA256: fingerprint,
    );
    await _markers.writeRecord(draft.id, receipt.encode());
    await flushMarker();
    _check(baseline);
  }

  Future<void> _verifyCandidate(
    LocalArticleLegacyDraft draft,
    ComplexNote baseline,
  ) async {
    _check(baseline);
    if (draft.id != baseline.id) throw StateError('Another article draft');
    final fresh = await readCurrent(baseline.id);
    _check(baseline);
    if (!fresh.same(baseline)) throw ComplexNoteConflict(fresh);
    final actual = await _candidate(draft.id);
    _check(baseline);
    if (actual == null || actual.digest != draft.digest) {
      throw StateError('Old article draft changed after review');
    }
  }

  Future<ComplexRecoveryRecord> restore(
    LocalArticleLegacyDraft draft,
    ComplexNote baseline,
  ) => maintenance.exclusive(() async {
    await _verifyCandidate(draft, baseline);
    final desired = ComplexRecoveryRecord.capture(
      baseline,
      draft.edit,
      pending: false,
    );
    final existing = await recovery.read(draft.id);
    _check(baseline);
    if (existing == null) {
      await recovery.write(desired);
    } else if (!_equal(existing.encode(), desired.encode())) {
      throw StateError('Review the existing WebView recovery first');
    }
    _check(baseline);
    await _mark(draft, LocalArticleDraftDisposition.restored, baseline);
    return desired;
  });

  Future<void> skip(LocalArticleLegacyDraft draft, ComplexNote baseline) =>
      maintenance.exclusive(() async {
        await _verifyCandidate(draft, baseline);
        await _mark(draft, LocalArticleDraftDisposition.skipped, baseline);
      });

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
