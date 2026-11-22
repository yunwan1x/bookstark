import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'draft_vault.dart';
import 'local_article_creation_legacy_metadata.dart';
import 'local_article_creation_record.dart';
import 'local_complex_notes_repository.dart';
import 'local_data_maintenance.dart';
import 'secure_record_store.dart';

class LocalArticleCreationLegacyDraft {
  LocalArticleCreationLegacyDraft._({
    required this.legacyKey,
    required this.edit,
    required this.digest,
    required this.ciphertextSHA256,
  });
  final String legacyKey, digest, ciphertextSHA256;
  final ComplexNoteEdit edit;
  LocalArticleCreationLegacyBinding get binding =>
      LocalArticleCreationLegacyBinding(
        legacyKey: legacyKey,
        digest: digest,
        ciphertextSHA256: ciphertextSHA256,
      );
}

class LocalArticleCreationLegacyArchive {
  const LocalArticleCreationLegacyArchive(this.draft, this.receipt);
  final LocalArticleCreationLegacyDraft draft;
  final LocalArticleCreationLegacyReceipt receipt;
}

class LocalArticleCreationAlreadyCommitted implements Exception {
  const LocalArticleCreationAlreadyCommitted(this.receipt);
  final ComplexCreationReceipt receipt;
}

/// A copy-before-receipt transfer of the old null-ID article draft. Never
/// deletes/reseals the original secure record or overwrites another creation.
class LocalArticleCreationLegacyReader {
  LocalArticleCreationLegacyReader({
    required this.legacy,
    required String expectedLegacyNamespace,
    required Set<String> ownedNamespaces,
    required this.maintenance,
    required this.fingerprintLegacyDraft,
    required this.flushMarker,
    required this.isCurrentScope,
  }) : _markers = SecureRecordStore(
         prefix: LocalArticleCreationLegacyScope.markerRecordPrefix,
         namespace: legacy.namespace,
         maintenance: maintenance,
         readValue: legacy.readValue,
         writeValue: legacy.writeValue,
         deleteValue: legacy.deleteValue,
       ) {
    final scope = LocalArticleCreationLegacyScope.fromLegacyKey(
      legacy.metadataKey(null),
    );
    LocalArticleCreationLegacyScope.fromMarkerKey(
      scope.markerKey,
      ownedNamespaces,
    );
    if (scope.namespace != expectedLegacyNamespace ||
        legacy.namespace != expectedLegacyNamespace ||
        !identical(legacy.maintenance, maintenance)) {
      throw ArgumentError('Owned local article creation archive required');
    }
  }
  final DraftVault legacy;
  final LocalDataMaintenance maintenance;
  final Future<String?> Function() fingerprintLegacyDraft;
  final Future<void> Function() flushMarker;
  final bool Function() isCurrentScope;
  final SecureRecordStore _markers;
  String get legacyKey => legacy.metadataKey(null);
  void _check() {
    bool current;
    try {
      current = isCurrentScope();
    } catch (_) {
      current = false;
    }
    if (!current || maintenance.retired) {
      throw StateError('Local article creation handoff scope changed');
    }
  }

  Future<String?> _fingerprint() async {
    final value = await fingerprintLegacyDraft();
    _check();
    if (value != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException(
        'Invalid legacy creation ciphertext fingerprint',
      );
    }
    return value;
  }

  Future<LocalArticleCreationLegacyDraft?> _candidate() async {
    _check();
    final before = await _fingerprint();
    final raw = await legacy.readRecord(null);
    _check();
    if (raw == null) {
      if (before != null) throw StateError('Legacy creation record changed');
      return null;
    }
    if (before == null ||
        raw.length > 24 * 1024 * 1024 ||
        utf8.encode(raw).length > 24 * 1024 * 1024) {
      throw const FormatException(
        'Legacy creation draft unavailable or oversized',
      );
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['title'] is! String ||
        data['content'] is! String ||
        data['labels'] is! List ||
        (data['labels'] as List).any((v) => v is! String)) {
      throw const FormatException('Invalid legacy new-article draft');
    }
    final edit = ComplexNoteEdit(
      title: data['title'] as String,
      document: ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        data['content'] as String,
      ),
      labels: (data['labels'] as List).cast<String>(),
    );
    LocalArticleCreationRecord.validateDraft(edit);
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'bookstark.local-article-create-legacy.v1',
              legacy.namespace,
              null,
              edit.title,
              edit.labels,
              edit.document.byteLength,
              edit.document.digest,
            ]),
          ),
        )
        .toString();
    final after = await _fingerprint();
    _check();
    if (after != before) {
      throw StateError('Legacy new-article draft changed while reading');
    }
    return LocalArticleCreationLegacyDraft._(
      legacyKey: legacyKey,
      edit: edit,
      digest: digest,
      ciphertextSHA256: before,
    );
  }

  Future<LocalArticleCreationLegacyReceipt?> _receipt() async {
    _check();
    final raw = await _markers.readRecord(null);
    _check();
    if (raw == null) return null;
    final receipt = LocalArticleCreationLegacyReceipt.parse(raw);
    await flushMarker();
    _check();
    return receipt;
  }

  Future<void> _verify(LocalArticleCreationLegacyDraft expected) async {
    if (expected.legacyKey != legacyKey) {
      throw StateError('Another legacy article creation draft');
    }
    final current = await _candidate();
    _check();
    if (current == null ||
        current.digest != expected.digest ||
        current.ciphertextSHA256 != expected.ciphertextSHA256) {
      throw StateError('Legacy new-article draft changed after review');
    }
  }

  Future<void> _mark(
    LocalArticleCreationLegacyDraft draft,
    LocalArticleCreationLegacyDisposition disposition,
    String? creationKey,
  ) async {
    await _verify(draft);
    _check();
    final receipt = LocalArticleCreationLegacyReceipt(
      digest: draft.digest,
      ciphertextSHA256: draft.ciphertextSHA256,
      disposition: disposition,
      creationKey: creationKey,
    );
    await _markers.writeRecord(null, receipt.encode());
    _check();
    await flushMarker();
    _check();
  }

  Future<LocalArticleCreationLegacyArchive> readHandled() =>
      maintenance.exclusive(() async {
        final draft = await _candidate();
        _check();
        final receipt = await _receipt();
        _check();
        if (draft == null ||
            receipt == null ||
            receipt.digest != draft.digest ||
            receipt.ciphertextSHA256 != draft.ciphertextSHA256) {
          throw StateError('Handled new-article draft changed or unavailable');
        }
        return LocalArticleCreationLegacyArchive(draft, receipt);
      });
}

/// Only this subtype exposes copy/skip operations; the archive reader does not
/// need a SQL repository or an editable creation vault.
class LocalArticleCreationLegacyHandoff
    extends LocalArticleCreationLegacyReader {
  LocalArticleCreationLegacyHandoff({
    required super.legacy,
    required super.expectedLegacyNamespace,
    required super.ownedNamespaces,
    required super.maintenance,
    required super.fingerprintLegacyDraft,
    required super.flushMarker,
    required super.isCurrentScope,
    required this.vault,
    required this.repository,
  }) {
    if (!identical(vault.maintenance, maintenance) ||
        vault.scope != repository.scope ||
        repository.collection != 'article' ||
        repository.kind != ComplexEditorKind.markdown) {
      throw ArgumentError('Owned article creation handoff required');
    }
  }
  final LocalArticleCreationVault vault;
  final ComplexNotesCreationRepository repository;
  Future<LocalArticleCreationLegacyDraft?> inspect({
    bool forceReview = false,
  }) => maintenance.exclusive(() async {
    final draft = await _candidate();
    _check();
    if (draft == null) return null;
    final copied = await vault.read();
    _check();
    final receipt = await _receipt();
    _check();
    final binding = copied?.legacyBinding;
    if (binding != null &&
        binding.legacyKey == legacyKey &&
        binding.digest == draft.digest) {
      if (receipt != null &&
          receipt.digest == draft.digest &&
          receipt.creationKey != null &&
          receipt.creationKey != copied!.key) {
        throw StateError('Legacy draft already links a different creation');
      }
      // Repair a crash after durable copy but before marking. A fresh decode
      // proved the original content even if the old native editor resealed it.
      await _mark(
        draft,
        LocalArticleCreationLegacyDisposition.restored,
        copied!.key,
      );
      return forceReview ? draft : null;
    }
    if (receipt != null && receipt.digest == draft.digest) {
      if (receipt.ciphertextSHA256 != draft.ciphertextSHA256) {
        // Same decoded original input, new native ciphertext: keep its existing
        // creation link instead of giving the same old draft a second key.
        await _mark(draft, receipt.disposition, receipt.creationKey);
      }
      if (!forceReview) return null;
    }
    return draft;
  });

  Future<LocalArticleCreationRecord> restore(
    LocalArticleCreationLegacyDraft draft, {
    String? expectedCreationKey,
  }) => maintenance.exclusive(() async {
    await _verify(draft);
    final existing = await vault.read();
    _check();
    if (existing != null) {
      if (existing.legacyBinding?.legacyKey != legacyKey ||
          existing.legacyBinding?.digest != draft.digest ||
          expectedCreationKey != null && existing.key != expectedCreationKey) {
        throw StateError('Resolve the existing new-article draft first');
      }
      final handled = await _receipt();
      _check();
      if (handled?.digest == draft.digest &&
          handled?.creationKey != null &&
          handled?.creationKey != existing.key) {
        throw StateError('Legacy draft links another creation result');
      }
      await _mark(
        draft,
        LocalArticleCreationLegacyDisposition.restored,
        existing.key,
      );
      return existing;
    }
    final receipt = await _receipt();
    _check();
    final linked = receipt?.digest == draft.digest
        ? receipt?.creationKey
        : null;
    if (linked != null &&
        expectedCreationKey != null &&
        linked != expectedCreationKey) {
      throw StateError('Legacy creation approval is stale');
    }
    final key = linked ?? expectedCreationKey ?? newComplexCreationKey();
    if (!validComplexCreationKey(key)) {
      throw const FormatException('Invalid legacy creation identity');
    }
    final committed = await repository.findCreation(key);
    _check();
    if (committed != null) {
      throw LocalArticleCreationAlreadyCommitted(committed);
    }
    final record = LocalArticleCreationRecord(
      scope: vault.scope,
      key: key,
      edit: draft.edit,
      pending: false,
      legacyBinding: draft.binding,
    );
    await vault.write(record);
    _check();
    await _mark(draft, LocalArticleCreationLegacyDisposition.restored, key);
    return record;
  });

  Future<void> skip(LocalArticleCreationLegacyDraft draft) =>
      maintenance.exclusive(() async {
        await _verify(draft);
        final copied = await vault.read();
        _check();
        final receipt = await _receipt();
        _check();
        if (copied?.legacyBinding?.legacyKey == legacyKey &&
                copied?.legacyBinding?.digest == draft.digest ||
            receipt?.digest == draft.digest && receipt?.creationKey != null) {
          throw StateError(
            'A transferred legacy draft must keep its creation link',
          );
        }
        await _mark(draft, LocalArticleCreationLegacyDisposition.skipped, null);
      });
}
