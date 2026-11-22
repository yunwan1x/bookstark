import 'dart:convert';
import 'document_excerpt_origin.dart';
import 'document_excerpt.dart';
import 'documents_repository.dart';
import 'complex_editor_document.dart';
import 'notes_repository.dart';

class DocumentExcerptRequest {
  DocumentExcerptRequest._({
    required this.origin,
    required this.note,
    required this.isCurrentSource,
    required this.verifyCurrentSource,
  });
  final DocumentExcerptOrigin origin;
  final Note note;
  final bool Function() isCurrentSource;
  final Future<bool> Function() verifyCurrentSource;
  factory DocumentExcerptRequest.snapshot({
    required int bookId,
    required DocumentItem item,
    required String source,
    required String selected,
    required String path,
    required String bookIdentify,
    required bool Function() isCurrentSource,
    required Future<bool> Function() verifyCurrentSource,
    String? fullFingerprint,
    String selectionKind = 'text',
    Uri? server,
    bool english = false,
  }) {
    if (!isCurrentSource() || item.bookId != bookId || item.id <= 0) {
      throw StateError('Excerpt source owner changed');
    }
    final kind = ComplexEditorKind.parse(item.type);
    ComplexEditorDocument.validateText(selected);
    final origin = DocumentExcerptOrigin(
      bookId: bookId,
      documentId: item.id,
      kind: kind,
      sourceDigest: DocumentExcerptOrigin.digest(source),
      selectionDigest: DocumentExcerptOrigin.digest(selected),
      selectionBytes: utf8.encode(selected).length,
      selectionKind: selectionKind,
      fullFingerprint: fullFingerprint,
    );
    final note = documentExcerpt(
      quote: selected,
      name: item.name,
      path: path,
      bookIdentify: bookIdentify,
      documentId: item.id,
      server: server,
      english: english,
    );
    return DocumentExcerptRequest._(
      origin: origin,
      note: note,
      isCurrentSource: isCurrentSource,
      verifyCurrentSource: verifyCurrentSource,
    );
  }
}
