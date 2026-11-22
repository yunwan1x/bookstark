// Prepared outside the frozen app. Not integrated or tested.
import 'package:bookstark_flutter/core/complex_editor_document.dart';

import 'documents_repository.dart';

import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';

enum DocumentReadingMode { markdown, complexWebView, boundedOriginal }

enum DocumentEditGate {
  permitted,
  permissionDenied,
  writerUnavailable,
  markdownTooLarge,
  unsupportedType,
  invalidFormat,
}

/// This DTO preserves raw-content metadata lost by current DocumentItem.
/// Presence is significant: missing body must never become an empty document.
class DocumentBodyMetadata {
  const DocumentBodyMetadata({
    required this.item,
    required this.inlineSource,
    required this.remote,
    this.contentPath,
    this.contentEncoding,
  });
  final DocumentItem item;
  final String? inlineSource;
  final bool remote;
  final String? contentPath, contentEncoding;

  factory DocumentBodyMetadata.local(DocumentItem item) => DocumentBodyMetadata(
    item: item,
    inlineSource: item.markdown,
    remote: false,
  );

  factory DocumentBodyMetadata.remote(Map<String, Object?> row) {
    if (row['document_id'] is! int ||
        (row['document_id'] as int) <= 0 ||
        row['book_id'] is! int ||
        (row['book_id'] as int) <= 0 ||
        row['doc_type'] is! String ||
        row['document_name'] is! String ||
        (row['markdown'] != null && row['markdown'] is! String)) {
      throw const FormatException('Invalid document metadata');
    }
    final item = DocumentItem.fromJson(row);
    return DocumentBodyMetadata(
      item: item,
      inlineSource: row['markdown'] as String?,
      remote: true,
      contentPath: row['content_url'] as String?,
      contentEncoding: row['content_encoding'] as String?,
    );
  }
}

/// Must enforce byte limit while consuming HTTP, preserve original UTF8 bytes,
/// use the configured authenticated client/prefix, reject redirects, and return
/// the HTTP-decoded body. Do not gzip-decode a second time from metadata alone.
typedef ReadDocumentRaw =
    Future<List<int>> Function(String apiPath, int maxBytes);

class PreparedDocumentRoute {
  const PreparedDocumentRoute({
    required this.item,
    required this.mode,
    required this.source,
    required this.editGate,
    this.document,
  });
  final DocumentItem item;
  final DocumentReadingMode mode;
  final String source;
  final ComplexEditorDocument? document;
  final DocumentEditGate editGate;
  bool get canEnterEditor => editGate == DocumentEditGate.permitted;
}

/// Pure dispatch/read preparation. This is deliberately not a writer and does
/// not grant save permission or replace a fresh transactional save baseline.
class DocumentRouteAdapter {
  const DocumentRouteAdapter({this.readRaw});
  final ReadDocumentRaw? readRaw;
  static const markdownEditBytes = 500000;
  static const maxOriginalBytes = 20 * 1024 * 1024;

  Future<PreparedDocumentRoute> prepareRead(
    TypedDocumentRead read, {
    required int bookId,
    required int documentId,
    required bool canEdit,
    required bool reviewedWriterAvailable,
  }) => prepare(
    DocumentBodyMetadata.local(
      DocumentItem(
        id: read.item.id,
        bookId: read.item.bookId,
        name: read.item.name,
        parentId: read.item.parentId,
        markdown: read.source,
        type: read.item.type,
        previousId: read.item.previousId,
        nextId: read.item.nextId,
        modifiedAt: read.item.modifiedAt,
        contentUrl: read.item.contentUrl,
        contentEncoding: read.item.contentEncoding,
        contentCompressed: read.item.contentCompressed,
      ),
    ),
    bookId: bookId,
    documentId: documentId,
    canEdit: canEdit,
    reviewedWriterAvailable: reviewedWriterAvailable,
  );

  Future<PreparedDocumentRoute> prepare(
    DocumentBodyMetadata metadata, {
    required int bookId,
    required int documentId,
    required bool canEdit,
    required bool reviewedWriterAvailable,
  }) async {
    final item = metadata.item;
    if (bookId <= 0 ||
        documentId <= 0 ||
        item.bookId != bookId ||
        item.id != documentId) {
      throw const FormatException('Document identity or book changed');
    }
    ComplexEditorKind? kind;
    for (final value in ComplexEditorKind.values) {
      if (value.name == item.type) kind = value;
    }
    final rawType = item.type == 'html' || item.type == 'richdoc';
    final maxBytes = kind?.maxBytes ?? maxOriginalBytes;
    String source;
    if (metadata.remote && rawType) {
      final expected = '/api/docs/$documentId/content/raw';
      if (metadata.contentPath != expected ||
          metadata.contentEncoding != 'gzip' ||
          readRaw == null) {
        throw const FormatException('Verified raw-content reader required');
      }
      final bytes = await readRaw!(expected, maxBytes);
      if (bytes.length > maxBytes) {
        throw const FormatException('Document body exceeds byte limit');
      }
      // Existing parser preserves every leading UTF8 BOM, strict Unicode.
      // Markdown branch performs text validation without JSON coercion.
      source = ComplexEditorDocument.fromBytes(
        ComplexEditorKind.markdown,
        bytes,
      ).source;
    } else {
      if (metadata.inlineSource == null) {
        throw const FormatException('Document body missing');
      }
      source = metadata.inlineSource!;
    }
    // Fail closed before any body can enter a widget or fallback source pane.
    if (isLocalProtectedEnvelopePrefix(source)) throw NoteLocked(documentId);
    ComplexEditorDocument.validateText(source);
    final byteLength = SourceChunks.utf8ByteLength(source);
    if (byteLength > maxBytes) {
      throw const FormatException('Document body exceeds byte limit');
    }
    final baseGate = !canEdit
        ? DocumentEditGate.permissionDenied
        : !reviewedWriterAvailable
        ? DocumentEditGate.writerUnavailable
        : DocumentEditGate.permitted;
    if (kind == null) {
      return PreparedDocumentRoute(
        item: item,
        mode: DocumentReadingMode.boundedOriginal,
        source: source,
        editGate: DocumentEditGate.unsupportedType,
      );
    }
    if (kind == ComplexEditorKind.markdown) {
      final large = byteLength > markdownEditBytes;
      return PreparedDocumentRoute(
        item: item,
        mode: large
            ? DocumentReadingMode.boundedOriginal
            : DocumentReadingMode.markdown,
        source: source,
        editGate: large ? DocumentEditGate.markdownTooLarge : baseGate,
      );
    }
    try {
      final document = ComplexEditorDocument.parse(kind, source);
      return PreparedDocumentRoute(
        item: item,
        mode: DocumentReadingMode.complexWebView,
        source: source,
        document: document,
        editGate: baseGate,
      );
    } on FormatException {
      return PreparedDocumentRoute(
        item: item,
        mode: DocumentReadingMode.boundedOriginal,
        source: source,
        editGate: DocumentEditGate.invalidFormat,
      );
    }
  }
}
