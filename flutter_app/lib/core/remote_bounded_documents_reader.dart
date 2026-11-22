// Prepared scratch. Sender must use current authenticated session and honor
// this typed request; no generic URL or credentials are accepted from metadata.
import 'dart:async';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/article_metadata_json.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;

import 'documents_repository.dart';

class DocumentReadRequest {
  const DocumentReadRequest(this.uri, this.maxWireBytes, this.abortTrigger);
  final Uri uri;
  final int maxWireBytes;
  final Future<void> abortTrigger;
  String get method => 'GET';
  bool get followRedirects => false;
  bool get autoUncompress => false;
  bool get useCurrentAuthenticatedSession => true;
}

class DocumentWireResponse {
  const DocumentWireResponse({
    required this.requestUri,
    required this.status,
    required this.headers,
    required this.body,
    required this.isDecoded,
  });
  final Uri requestUri;
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  // Must be false: counters need wire bytes before gzip transformation.
  final bool isDecoded;
}

typedef SendDocumentRead =
    Future<DocumentWireResponse> Function(DocumentReadRequest request);
typedef DecodeDocumentGzip =
    Stream<List<int>> Function(
      Stream<List<int>> wire, {
      required int maxWireBytes,
      required int maxPlainBytes,
      required Future<void> abortTrigger,
      required Duration timeout,
    });

/// Optional capability independent of old RemoteDocumentsRepository overrides.
/// No call path here uses client.get or silently falls back to unbounded HTTP.
class RemoteBoundedDocumentsReader implements BoundedDocumentsReader {
  RemoteBoundedDocumentsReader({
    required this.baseUri,
    required this.send,
    required this.decodeGzip,
  }) {
    if (!{'http', 'https'}.contains(baseUri.scheme) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        baseUri.path.endsWith('/') ||
        baseUri.pathSegments.any((p) => p == '..' || p == '.')) {
      throw const FormatException('Canonical current server base required');
    }
  }
  final Uri baseUri;
  final SendDocumentRead send;
  final DecodeDocumentGzip decodeGzip;
  static const maxMetadataWireBytes = 128 * 1024 * 1024;
  static const maxMetadataDecodedBytes = 128 * 1024 * 1024;
  static const timeout = Duration(seconds: 20);

  Uri _endpoint(int id, {bool raw = false}) {
    if (id <= 0) throw ArgumentError('Positive document ID required');
    return baseUri.replace(
      path: '${baseUri.path}/api/docs/$id${raw ? '/content/raw' : ''}',
    );
  }

  String? _header(DocumentWireResponse response, String name) {
    final matches = response.headers.entries
        .where((e) => e.key.toLowerCase() == name)
        .toList();
    if (matches.length > 1) {
      throw const FormatException('Ambiguous HTTP header');
    }
    return matches.isEmpty ? null : matches.single.value.trim().toLowerCase();
  }

  Future<Stream<List<int>>> _get(
    Uri uri,
    int wireLimit,
    int decodedLimit, {
    String? expectedMime,
    int? documentId,
    String? documentType,
  }) async {
    final abort = Completer<void>();
    DocumentWireResponse response;
    try {
      response = await send(
        DocumentReadRequest(uri, wireLimit, abort.future),
      ).timeout(timeout);
    } catch (_) {
      abort.complete();
      rethrow;
    }
    try {
      if (response.requestUri != uri ||
          response.status != 200 ||
          response.isDecoded) {
        // A sender that followed a redirect must retain the final request URI.
        // HTTP 3xx is rejected here before consuming any body.
        throw const FormatException(
          'Owned raw HTTP response required; no redirect',
        );
      }
      final lengthHeader = _header(response, 'content-length');
      int? expectedWireLength;
      if (lengthHeader != null) {
        final length = int.tryParse(lengthHeader);
        expectedWireLength = length;
        if (length == null || length < 0 || length > wireLimit) {
          throw const FormatException('Document HTTP wire byte limit');
        }
      }
      if (expectedMime != null) {
        final contentType = _header(response, 'content-type');
        if (contentType == null ||
            contentType.split(';').first.trim() != expectedMime ||
            (contentType.contains('charset=') &&
                !contentType.contains('charset=utf-8'))) {
          throw const FormatException('Unexpected document content type');
        }
      }
      final encoding = _header(response, 'content-encoding');
      if (encoding != null &&
          encoding != '' &&
          encoding != 'identity' &&
          encoding != 'gzip') {
        throw const FormatException('Unsupported document transfer encoding');
      }
      var wireCount = 0, decodedCount = 0;
      final started = Stopwatch()..start();
      final wire = response.body.timeout(timeout).map((chunk) {
        wireCount += chunk.length;
        if (wireCount > wireLimit || started.elapsed > timeout) {
          throw const FormatException('Document wire byte/deadline limit');
        }
        return chunk;
      });
      final decoded = encoding == 'gzip'
          ? decodeGzip(
              wire,
              maxWireBytes: wireLimit,
              maxPlainBytes: decodedLimit,
              abortTrigger: abort.future,
              timeout: timeout,
            )
          : wire;
      Stream<List<int>> consume() async* {
        try {
          await for (final chunk in decoded.timeout(timeout)) {
            decodedCount += chunk.length;
            if (decodedCount > decodedLimit &&
                documentId != null &&
                documentType != null) {
              throw DocumentReadLimit(
                documentId,
                documentType,
                decodedCount,
                decodedLimit,
              );
            }
            if (decodedCount > decodedLimit || started.elapsed > timeout) {
              throw const FormatException(
                'Document decoded byte/deadline limit',
              );
            }
            yield chunk;
          }
          if (expectedWireLength != null && wireCount != expectedWireLength) {
            throw const FormatException(
              'Truncated or extra document wire bytes',
            );
          }
        } finally {
          if (!abort.isCompleted) abort.complete();
        }
      }

      return consume();
    } catch (_) {
      if (!abort.isCompleted) abort.complete();
      await response.body.listen((_) {}, onError: (Object _) {}).cancel();
      rethrow;
    }
  }

  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) {
    if (bookId <= 0) throw ArgumentError('Positive book ID required');
    return _readBounded(id, bookId, maxMarkdownReadBytes);
  }

  /// Deep-link identity discovery still consumes the exact bounded owned source.
  /// The actual reader rechecks the discovered book ID on its next fresh read.
  Future<TypedDocumentRead> discoverBounded(
    int id, {
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) => _readBounded(id, null, maxMarkdownReadBytes);

  Future<TypedDocumentRead> _readBounded(
    int id,
    int? bookId,
    int maxMarkdownReadBytes,
  ) async {
    documentBodyBudget('markdown', maxMarkdownReadBytes);
    final stream = await _get(
      _endpoint(id),
      maxMetadataWireBytes,
      maxMetadataDecodedBytes,
      expectedMime: 'application/json',
    );
    // Reuse the existing streaming strict JSON/UTF8/depth/duplicate-key parser.
    // It only discards unrelated blog_content/blog_desc fields, not markdown.
    final envelope = await readArticleMetadataJson(
      stream,
      maxBytes: maxMetadataDecodedBytes,
      maxMetadataChars: maxMetadataDecodedBytes,
    );
    if (envelope['code'] is! int ||
        envelope['code'] != 0 ||
        envelope['data'] is! Map) {
      throw const FormatException('Document response envelope invalid');
    }
    final row = Map<String, Object?>.from(envelope['data'] as Map);
    if (row['document_id'] != id ||
        (bookId != null && row['book_id'] != bookId) ||
        row['document_id'] is! int ||
        row['book_id'] is! int ||
        (row['book_id'] as int) <= 0 ||
        row['doc_type'] is! String ||
        (row['doc_type'] as String).length > 64 ||
        (row['doc_type'] as String).isEmpty ||
        row['document_name'] is! String ||
        (row['document_name'] as String).length > 4096 ||
        row['markdown'] is! String) {
      throw const FormatException(
        'Document identity/type/body metadata invalid',
      );
    }
    final item = DocumentItem.fromJson(row);
    final raw = item.type == 'html' || item.type == 'richdoc';
    final limit = documentBodyBudget(item.type, maxMarkdownReadBytes);
    String source;
    if (raw) {
      if (item.contentUrl != '/api/docs/$id/content/raw' ||
          item.contentEncoding != 'gzip' ||
          item.contentCompressed == null ||
          item.markdown.isNotEmpty) {
        throw const FormatException(
          'Verified document raw-content metadata required',
        );
      }
      // Gzip worst-case overhead is small; explicit 1MiB wire allowance supports
      // incompressible 5MiB valid sources without removing the wire byte cap.
      final body = await _get(
        _endpoint(id, raw: true),
        limit + 1024 * 1024,
        limit,
        expectedMime: item.type == 'html' ? 'text/html' : 'application/json',
        documentId: id,
        documentType: item.type,
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body) {
        bytes.add(chunk);
      }
      source = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes.takeBytes());
    } else {
      source = item.markdown;
    }
    if (isLocalProtectedEnvelopePrefix(source)) throw NoteLocked(id);
    ComplexEditorDocument.validateText(source);
    // Check original UTF8 bytes; never normalize BOM/CRLF or source JSON.
    final byteLength = _utf8Length(source);
    if (byteLength > limit) {
      throw DocumentReadLimit(id, item.type, byteLength, limit);
    }
    return TypedDocumentRead(
      item: item,
      byteLength: byteLength,
      source: source,
    );
  }

  int _utf8Length(String source) {
    var bytes = 0;
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit <= 0x7f) {
        bytes++;
      } else if (unit <= 0x7ff) {
        bytes += 2;
      } else if (unit >= 0xd800 && unit <= 0xdbff) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}
