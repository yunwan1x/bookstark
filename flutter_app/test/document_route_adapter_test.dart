// Draft regression cases; not run while app/source checks are frozen.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/documents_repository.dart';

import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';

import 'package:bookstark_flutter/core/document_route_adapter.dart';

DocumentItem item(String type, String source, {int id = 7, int book = 3}) =>
    DocumentItem(
      id: id,
      bookId: book,
      name: '原文',
      type: type,
      markdown: source,
    );

Future<PreparedDocumentRoute> local(
  String type,
  String source, {
  bool writer = false,
  bool permission = true,
}) => const DocumentRouteAdapter().prepare(
  DocumentBodyMetadata.local(item(type, source)),
  bookId: 3,
  documentId: 7,
  canEdit: permission,
  reviewedWriterAvailable: writer,
);

Map<String, Object?> rawMetadata(String type) => {
  'document_id': 7,
  'book_id': 3,
  'document_name': '原文',
  'doc_type': type,
  'markdown': '',
  'content_url': '/api/docs/7/content/raw',
  'content_encoding': 'gzip',
};

void main() {
  test('all seven types dispatch exact source without format conversion', () async {
    final samples = {
      'markdown': '\ufeff# hello🙂\r\n',
      'html': '\ufeff<!doctype html><p>原文</p>',
      'spreadsheet': SpreadsheetDocument.empty(
        workbookId: 'w',
        sheetId: 's',
      ).source,
      'drawing': ' {"elements":[],"appState":{},"future":42} ',
      'mindmap': '{"nodeData":{"id":"root","topic":"原文"},"linkData":{}}',
      'richdoc':
          '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[]},"future":42}',
      'presentation':
          '{"width":1000,"height":562.5,"slides":[{"id":"s","elements":[]}],"future":42}',
    };
    for (final entry in samples.entries) {
      final route = await local(entry.key, entry.value);
      expect(route.source, entry.value);
      expect(
        route.mode,
        entry.key == 'markdown'
            ? DocumentReadingMode.markdown
            : DocumentReadingMode.complexWebView,
      );
      expect(route.editGate, DocumentEditGate.writerUnavailable);
      expect(route.canEnterEditor, false);
      if (entry.key != 'markdown') {
        expect(route.document!.kind.name, entry.key);
        expect(route.document!.source, entry.value);
      }
    }
  });

  test(
    'HTML and richdoc remote metadata require bounded raw fetch, preserve BOM',
    () async {
      for (final type in ['html', 'richdoc']) {
        final source = type == 'html'
            ? '\ufeff\ufeff<p>原文🙂</p>\r\n'
            : '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[]}}';
        final calls = <String>[];
        final adapter = DocumentRouteAdapter(
          readRaw: (path, limit) async {
            calls.add(path);
            expect(limit, 5 * 1024 * 1024);
            return utf8.encode(source);
          },
        );
        final route = await adapter.prepare(
          DocumentBodyMetadata.remote(rawMetadata(type)),
          bookId: 3,
          documentId: 7,
          canEdit: true,
          reviewedWriterAvailable: false,
        );
        expect(route.source, source);
        expect(calls, ['/api/docs/7/content/raw']);
        await expectLater(
          const DocumentRouteAdapter().prepare(
            DocumentBodyMetadata.remote(rawMetadata(type)),
            bookId: 3,
            documentId: 7,
            canEdit: true,
            reviewedWriterAvailable: false,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'raw URLs are exact owned API identity, never arbitrary browser URLs',
    () async {
      for (final path in [
        'https://other/api/docs/7/content/raw',
        '/api/docs/8/content/raw',
        '/api/docs/7/content/raw?ak=x',
        null,
      ]) {
        final meta = rawMetadata('html')..['content_url'] = path;
        var calls = 0;
        final adapter = DocumentRouteAdapter(
          readRaw: (_, _) async {
            calls++;
            return [];
          },
        );
        await expectLater(
          adapter.prepare(
            DocumentBodyMetadata.remote(meta),
            bookId: 3,
            documentId: 7,
            canEdit: true,
            reviewedWriterAvailable: false,
          ),
          throwsFormatException,
        );
        expect(calls, 0);
      }
    },
  );

  test('cross book or ID mismatch rejects before raw request', () async {
    var calls = 0;
    final adapter = DocumentRouteAdapter(
      readRaw: (_, _) async {
        calls++;
        return [];
      },
    );
    await expectLater(
      adapter.prepare(
        DocumentBodyMetadata.remote(rawMetadata('html')),
        bookId: 4,
        documentId: 7,
        canEdit: true,
        reviewedWriterAvailable: true,
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  test(
    'UTF8 editing limit is exact; source chunks do not change body',
    () async {
      final exact = '${'a' * 499996}🙂';
      final normal = await local('markdown', exact, writer: true);
      expect(normal.mode, DocumentReadingMode.markdown);
      expect(normal.canEnterEditor, true);
      final large = await local('markdown', '${exact}a', writer: true);
      expect(large.mode, DocumentReadingMode.boundedOriginal);
      expect(large.editGate, DocumentEditGate.markdownTooLarge);
      expect(large.source, '${exact}a');
    },
  );

  test(
    'unknown/invalid types keep exact source but no editor capability',
    () async {
      for (final pair in [
        ('future-kind', ' \ufefffuture raw\r\n'),
        ('drawing', '{malformed'),
        ('richdoc', '{"data":{}}'),
      ]) {
        final route = await local(pair.$1, pair.$2, writer: true);
        expect(route.mode, DocumentReadingMode.boundedOriginal);
        expect(route.source, pair.$2);
        expect(route.canEnterEditor, false);
      }
      expect(
        (await local('markdown', '', writer: true, permission: false)).editGate,
        DocumentEditGate.permissionDenied,
      );
    },
  );

  test(
    'reserved protected prefixes never reach source or WebView fallback',
    () async {
      for (final type in ['markdown', 'html', 'drawing', 'future-kind']) {
        for (final prefix in [
          'ENC:v1:',
          'ENC:v2:',
          'ENC:unknown:',
          '\ufeffENC:',
        ]) {
          await expectLater(
            local(type, prefix, writer: true),
            throwsA(isA<NoteLocked>()),
          );
        }
      }
      expect(
        (await local('markdown', '# Text\nordinary ENC:v2: in prose')).source,
        '# Text\nordinary ENC:v2: in prose',
      );
    },
  );
}
