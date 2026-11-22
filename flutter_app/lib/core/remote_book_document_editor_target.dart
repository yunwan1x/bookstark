import 'package:bookstark_flutter/core/complex_editor_document.dart';

class VerifiedRemoteBookDocument {
  VerifiedRemoteBookDocument({
    required this.server,
    required this.bookId,
    required this.documentId,
    required this.bookIdentify,
    required this.kind,
    required this.ownerBinding,
    required this.documentFingerprint,
  }) {
    final base = Uri.parse(server);
    if (!{'https', 'http'}.contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        server.endsWith('/') ||
        bookId <= 0 ||
        documentId <= 0 ||
        kind == ComplexEditorKind.markdown ||
        !RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(bookIdentify) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(documentFingerprint) ||
        ownerBinding.isEmpty) {
      throw const FormatException(
        'Verified complex book document identity required',
      );
    }
  }
  final String server, bookIdentify, ownerBinding, documentFingerprint;
  final int bookId, documentId;
  final ComplexEditorKind kind;
  Uri get editorUri {
    final base = Uri.parse(server);
    return base.replace(
      path: '${base.path}/books/$bookIdentify/edit',
      queryParameters: {'doc': '$documentId'},
    );
  }
}

/// Root must create this only after strict current-owner book/detail/tree/raw
/// checks. URL ?doc is supported by real editor.js, but a missing tree member
/// silently falls back to first leaf, so no URL-only adapter may enable saves.
abstract interface class RemoteBookDocumentEditorBridge {
  /// Must wait for actual server editor ready identity (book ID/document ID/type),
  /// reject fallback, pin same configured origin/path prefix/auth epoch, retire
  /// cookies/resources/callbacks on scope exit, and use the real document save UI.
  /// No notes/blogs IDs or synthetic API save receipts.
  Future<void> openVerified(VerifiedRemoteBookDocument target);
}
