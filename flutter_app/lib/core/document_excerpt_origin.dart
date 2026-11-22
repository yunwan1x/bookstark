import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';

/// Immutable provenance of a selected readable excerpt, not a save receipt.
class DocumentExcerptOrigin {
  DocumentExcerptOrigin({
    required this.bookId,
    required this.documentId,
    required this.kind,
    required this.sourceDigest,
    required this.selectionDigest,
    required this.selectionBytes,
    required this.selectionKind,
    this.fullFingerprint,
  }) {
    if (bookId <= 0 ||
        documentId <= 0 ||
        selectionBytes <= 0 ||
        selectionBytes > 128 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(selectionDigest) ||
        fullFingerprint != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(fullFingerprint!) ||
        kind != ComplexEditorKind.markdown && fullFingerprint == null ||
        !{
          'text',
          'part',
          'cells',
          'elements',
          'nodes',
          'slide',
        }.contains(selectionKind) ||
        (kind == ComplexEditorKind.spreadsheet && selectionKind != 'cells') ||
        (kind == ComplexEditorKind.drawing && selectionKind != 'elements') ||
        (kind == ComplexEditorKind.mindmap && selectionKind != 'nodes') ||
        (kind == ComplexEditorKind.presentation && selectionKind != 'slide') ||
        ({ComplexEditorKind.html, ComplexEditorKind.richdoc}.contains(kind) &&
            selectionKind != 'text') ||
        (kind == ComplexEditorKind.markdown &&
            !{'text', 'part'}.contains(selectionKind))) {
      throw const FormatException('Invalid excerpt source identity');
    }
  }
  final int bookId, documentId, selectionBytes;
  final ComplexEditorKind kind;
  final String sourceDigest, selectionDigest, selectionKind;
  final String? fullFingerprint;
  Map<String, Object?> toJson() => {
    'version': 1,
    'bookId': bookId,
    'documentId': documentId,
    'kind': kind.name,
    'sourceDigest': sourceDigest,
    'fullFingerprint': fullFingerprint,
    'selectionDigest': selectionDigest,
    'selectionBytes': selectionBytes,
    'selectionKind': selectionKind,
  };
  bool same(DocumentExcerptOrigin other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
  factory DocumentExcerptOrigin.parse(Object? raw) {
    const keys = {
      'version',
      'bookId',
      'documentId',
      'kind',
      'sourceDigest',
      'fullFingerprint',
      'selectionDigest',
      'selectionBytes',
      'selectionKind',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.toSet().difference(keys).isNotEmpty ||
        raw['version'] != 1 ||
        raw['bookId'] is! int ||
        raw['documentId'] is! int ||
        raw['kind'] is! String ||
        raw['sourceDigest'] is! String ||
        raw['selectionDigest'] is! String ||
        raw['selectionBytes'] is! int ||
        raw['selectionKind'] is! String ||
        raw['fullFingerprint'] != null && raw['fullFingerprint'] is! String) {
      throw const FormatException('Invalid excerpt source metadata');
    }
    return DocumentExcerptOrigin(
      bookId: raw['bookId'] as int,
      documentId: raw['documentId'] as int,
      kind: ComplexEditorKind.parse(raw['kind'] as String),
      sourceDigest: raw['sourceDigest'] as String,
      selectionDigest: raw['selectionDigest'] as String,
      selectionBytes: raw['selectionBytes'] as int,
      selectionKind: raw['selectionKind'] as String,
      fullFingerprint: raw['fullFingerprint'] as String?,
    );
  }
  static String digest(String text) {
    ComplexEditorDocument.validateText(text);
    return sha256.convert(utf8.encode(text)).toString();
  }
}
