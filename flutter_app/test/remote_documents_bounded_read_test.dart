// Bounded HTTP callback contract drafts. NOT RUN; no real network/provider.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/remote_bounded_documents_reader.dart';
import 'package:bookstark_flutter/core/document_gzip_io.dart';

Map<String, Object?> metadata(String type, {String source = ''}) => {
  'document_id': 7,
  'book_id': 3,
  'document_name': '原文',
  'doc_type': type,
  'markdown': source,
  'modify_time': 't',
  if (type == 'html' || type == 'richdoc') ...{
    'content_url': '/api/docs/7/content/raw',
    'content_encoding': 'gzip',
    'content_compressed': true,
  },
};
DocumentWireResponse response(
  DocumentReadRequest request,
  List<int> bytes, {
  String mime = 'application/json',
  String? encoding,
  int status = 200,
  Uri? finalUri,
  bool decoded = false,
}) => DocumentWireResponse(
  requestUri: finalUri ?? request.uri,
  status: status,
  headers: {
    'content-type': '$mime; charset=utf-8',
    'content-length': '${bytes.length}',
    'content-encoding': ?encoding,
  },
  body: Stream.fromIterable([
    for (var i = 0; i < bytes.length; i += 3)
      bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3),
  ]),
  isDecoded: decoded,
);

void main() {
  final base = Uri.parse('https://example.test/mount');

  test(
    'authenticated fixed GET metadata/raw uses prefix, limits, gzip and exact BOM',
    () async {
      const source = '\ufeff\ufeff<!doctype html>\r\n<p>原文🙂</p>\r\n';
      final requests = <DocumentReadRequest>[];
      final reader = RemoteBoundedDocumentsReader(
        baseUri: base,
        decodeGzip: decodeDocumentGzipIO,
        send: (request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.followRedirects, false);
          expect(request.autoUncompress, false);
          expect(request.useCurrentAuthenticatedSession, true);
          if (request.uri.path.endsWith('/content/raw')) {
            expect(
              request.uri,
              Uri.parse('https://example.test/mount/api/docs/7/content/raw'),
            );
            return response(
              request,
              gzip.encode(utf8.encode(source)),
              mime: 'text/html',
              encoding: 'gzip',
            );
          }
          return response(
            request,
            utf8.encode(jsonEncode({'code': 0, 'data': metadata('html')})),
          );
        },
      );
      final result = await reader.readBounded(7, bookId: 3);
      expect(result.source, source);
      expect(result.byteLength, utf8.encode(source).length);
      expect(result.item.contentUrl, '/api/docs/7/content/raw');
      expect(result.item.contentEncoding, 'gzip');
      expect(result.item.contentCompressed, true);
      expect(requests.length, 2);
    },
  );

  test(
    'inline nonraw source stays exact and never triggers raw endpoint',
    () async {
      const source = '\ufeff# 原文🙂\r\nA\u0000B';
      var requests = 0;
      final reader = RemoteBoundedDocumentsReader(
        baseUri: base,
        decodeGzip: decodeDocumentGzipIO,
        send: (request) async {
          requests++;
          expect(request.uri.path, '/mount/api/docs/7');
          return response(
            request,
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': metadata('markdown', source: source),
              }),
            ),
          );
        },
      );
      expect((await reader.readBounded(7, bookId: 3)).source, source);
      expect(requests, 1);
    },
  );

  test('wrong book or foreign raw URL rejects before any raw fetch', () async {
    for (final bad in [
      metadata('html')..['book_id'] = 4,
      metadata('html')
        ..['content_url'] = 'https://evil.test/api/docs/7/content/raw',
      metadata('html')..['content_url'] = '/api/docs/8/content/raw',
      metadata('html')..['content_compressed'] = null,
    ]) {
      var calls = 0;
      final reader = RemoteBoundedDocumentsReader(
        baseUri: base,
        decodeGzip: decodeDocumentGzipIO,
        send: (request) async {
          calls++;
          return response(
            request,
            utf8.encode(jsonEncode({'code': 0, 'data': bad})),
          );
        },
      );
      await expectLater(
        reader.readBounded(7, bookId: 3),
        throwsFormatException,
      );
      expect(calls, 1);
    }
  });

  test(
    'redirects and already-decoded wire are rejected, not decoded twice',
    () async {
      for (final flag in [0, 1, 2]) {
        final reader = RemoteBoundedDocumentsReader(
          baseUri: base,
          decodeGzip: decodeDocumentGzipIO,
          send: (request) async => response(
            request,
            [],
            status: flag == 0 ? 302 : 200,
            finalUri: flag == 1 ? Uri.parse('https://evil.test/x') : null,
            decoded: flag == 2,
          ),
        );
        await expectLater(
          reader.readBounded(7, bookId: 3),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'gzip decompression bomb stops at source cap, malformed gzip/UTF8 reject',
    () async {
      for (final body in [
        gzip.encode(List<int>.filled(5 * 1024 * 1024 + 1, 65)),
        [31, 139, 8, 0, 0],
        gzip.encode([0xc3, 0x28]),
      ]) {
        final reader = RemoteBoundedDocumentsReader(
          baseUri: base,
          decodeGzip: decodeDocumentGzipIO,
          send: (request) async {
            if (request.uri.path.endsWith('/content/raw')) {
              return response(
                request,
                body,
                mime: 'text/html',
                encoding: 'gzip',
              );
            }
            return response(
              request,
              utf8.encode(jsonEncode({'code': 0, 'data': metadata('html')})),
            );
          },
        );
        await expectLater(
          reader.readBounded(7, bookId: 3),
          throwsA(anyOf(isA<FormatException>(), isA<DocumentReadLimit>())),
        );
      }
    },
  );

  test(
    'header byte limit rejects before reading and signals owned request abort',
    () async {
      var canceled = false, aborted = false;
      final reader = RemoteBoundedDocumentsReader(
        baseUri: base,
        decodeGzip: decodeDocumentGzipIO,
        send: (request) async {
          if (!request.uri.path.endsWith('/content/raw')) {
            return response(
              request,
              utf8.encode(jsonEncode({'code': 0, 'data': metadata('html')})),
            );
          }
          request.abortTrigger.then((_) => aborted = true);
          final controller = StreamController<List<int>>(
            onCancel: () => canceled = true,
          );
          return DocumentWireResponse(
            requestUri: request.uri,
            status: 200,
            isDecoded: false,
            headers: {
              'content-type': 'text/html',
              'content-length': '${7 * 1024 * 1024}',
            },
            body: controller.stream,
          );
        },
      );
      await expectLater(
        reader.readBounded(7, bookId: 3),
        throwsFormatException,
      );
      await Future<void>.delayed(Duration.zero);
      expect(canceled, true);
      expect(aborted, true);
    },
  );
}
