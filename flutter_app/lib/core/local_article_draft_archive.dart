import 'dart:convert';
import 'complex_editor_document.dart';
import 'draft_vault.dart';
import 'local_article_draft_receipt.dart';
import 'local_complex_notes_repository.dart';
import 'local_data_maintenance.dart';
import 'local_draft_namespace.dart';

final class LocalArchivedArticle {
  const LocalArchivedArticle(this.scope, this.receipt, this.edit);
  final LocalArticleDraftReceiptScope scope;
  final LocalArticleDraftReceipt receipt;
  final ComplexNoteEdit edit;
}

/// User-confirmed metadata approval. The editor rechecks scope, digest and
/// ciphertext fingerprint; no body or password is carried in a route result.
final class LocalArticleDraftRestoreApproval {
  LocalArticleDraftRestoreApproval.fromArchive(LocalArchivedArticle archive)
    : namespace = archive.scope.namespace,
      id = archive.scope.id,
      digest = archive.receipt.digest,
      ciphertextSHA256 = archive.receipt.ciphertextSHA256!;

  final String namespace, digest, ciphertextSHA256;
  final int id;
}

/// Explicit old-draft viewing only. Inventory never uses this body reader.
final class LocalArticleDraftArchiveReader {
  LocalArticleDraftArchiveReader({
    required this.maintenance,
    required Set<String> ownedNamespaces,
    required this.readValue,
    required this.fingerprintDraft,
    required this.isCurrentScope,
  }) : ownedNamespaces = Set.unmodifiable(ownedNamespaces) {
    if (ownedNamespaces.isEmpty ||
        ownedNamespaces.any((value) => !LocalDraftNamespace.isLocal(value))) {
      throw const FormatException('Owned archive namespaces required');
    }
  }
  final LocalDataMaintenance maintenance;
  final Set<String> ownedNamespaces;
  final Future<String?> Function(String key) readValue, fingerprintDraft;
  final bool Function() isCurrentScope;
  void _check() {
    if (maintenance.retired || !isCurrentScope()) {
      throw StateError('Article draft archive scope changed');
    }
  }

  Future<LocalArchivedArticle> read(
    String legacyKey,
  ) => maintenance.exclusive(() async {
    _check();
    final local = LocalArticleDraftReceiptScope.localLegacy(legacyKey);
    final scope = LocalArticleDraftReceiptScope.parse(
      local.markerKey,
      ownedNamespaces,
    );
    final rawReceipt = await readValue(scope.markerKey);
    _check();
    if (rawReceipt == null) throw StateError('Article archive receipt missing');
    final receipt = LocalArticleDraftReceipt.parse(rawReceipt);
    if (receipt.ciphertextSHA256 == null) {
      throw StateError('Article archive receipt needs verification');
    }
    final before = await fingerprintDraft(scope.legacyKey);
    _check();
    if (before != receipt.ciphertextSHA256) {
      throw StateError('Article archive changed');
    }
    final legacy = DraftVault(
      namespace: scope.namespace,
      maintenance: maintenance,
      readValue: (key) async {
        if (key != scope.legacyKey) {
          throw StateError('Archive body scope mismatch');
        }
        final raw = await readValue(key);
        _check();
        if (raw != null && utf8.encode(raw).length > 24 * 1024 * 1024) {
          throw const FormatException(
            'Legacy draft record exceeds its byte bound',
          );
        }
        return raw;
      },
      writeValue: (_, _) async =>
          throw StateError('Archive reader is read-only'),
      deleteValue: (_) async => throw StateError('Archive reader is read-only'),
    );
    final note = await legacy.read(scope.id);
    _check();
    if (note == null) throw StateError('Article archive body missing');
    final edit = ComplexNoteEdit(
      title: note.title,
      document: ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        note.content,
      ),
      labels: note.labels,
    );
    edit.validate();
    if (LocalArticleDraftReceipt.digestOf(
          namespace: scope.namespace,
          id: scope.id,
          title: edit.title,
          source: edit.document.source,
          labels: edit.labels,
        ) !=
        receipt.digest) {
      throw StateError('Article archive content does not match its receipt');
    }
    final after = await fingerprintDraft(scope.legacyKey);
    _check();
    final currentReceipt = await readValue(scope.markerKey);
    _check();
    if (after != before || currentReceipt != rawReceipt) {
      throw StateError('Article archive changed during reading');
    }
    return LocalArchivedArticle(scope, receipt, edit);
  });
}
