import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';

void main() {
  final samples = <ComplexEditorKind, String>{
    ComplexEditorKind.markdown: '\ufeff# 原文😀\r\n\r\n**保留 Markdown**\r\n',
    ComplexEditorKind.html: '\ufeff<!doctype html>\r\n<p>原文😀</p>\r\n',
    ComplexEditorKind.spreadsheet: SpreadsheetDocument.empty(
      workbookId: 'w',
      sheetId: 's',
    ).source,
    ComplexEditorKind.drawing:
        ' {"elements":[],"appState":{},"future":{"keep":true}} ',
    ComplexEditorKind.mindmap:
        '{"nodeData":{"id":"root","topic":"阅读","children":[]},"future":true}',
    ComplexEditorKind.richdoc:
        '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"原文"}]},"future":true}',
    ComplexEditorKind.presentation:
        '{"width":1000,"height":562.5,"slides":[{"id":"s","elements":[]}],"future":true}',
  };
  test(
    'all seven explicit WebView document kinds preserve exact original source',
    () {
      for (final entry in samples.entries) {
        final doc = ComplexEditorDocument.parse(entry.key, entry.value);
        expect(doc.source, entry.value);
        expect(doc.byteLength, utf8.encode(entry.value).length);
        expect(identical(doc.withSource(entry.value), doc), isTrue);
        expect(
          doc.same(ComplexEditorDocument.parse(entry.key, entry.value)),
          isTrue,
        );
      }
      expect(ComplexEditorKind.parse('markdown'), ComplexEditorKind.markdown);
      expect(() => ComplexEditorKind.parse('unknown'), throwsFormatException);
    },
  );
  test('Markdown is plain source, never JSON or HTML identity', () {
    for (final raw in [
      '',
      '{bad',
      'null',
      '<script>not executed here</script>',
    ]) {
      final doc = ComplexEditorDocument.parse(ComplexEditorKind.markdown, raw);
      expect(doc.source, raw);
      expect(
        doc.same(ComplexEditorDocument.parse(ComplexEditorKind.html, raw)),
        isFalse,
      );
    }
    expect(ComplexEditorKind.markdown.maxBytes, 20 * 1024 * 1024);
    expect(ComplexEditorKind.html.maxBytes, 5 * 1024 * 1024);
    expect(
      () => ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        String.fromCharCode(0xd800),
      ),
      throwsFormatException,
    );
    expect(
      () => ComplexEditorDocument.fromBytes(ComplexEditorKind.markdown, [
        0xc3,
        0x28,
      ]),
      throwsFormatException,
    );
  });
  test('Markdown byte budget counts UTF8 instead of code units', () {
    final limit = ComplexEditorKind.markdown.maxBytes;
    final source = '中' * (limit ~/ 3);
    final doc = ComplexEditorDocument.parse(ComplexEditorKind.markdown, source);
    expect(doc.byteLength, limit - limit % 3);
    expect(() => doc.withSource([source, '中'].join()), throwsFormatException);
  });
  test('invalid engine snapshots never fall back to an empty document', () {
    for (final kind in ComplexEditorKind.values.where(
      (k) => k != ComplexEditorKind.html && k != ComplexEditorKind.markdown,
    )) {
      for (final raw in ['', '{}', 'null', '{bad']) {
        expect(
          () => ComplexEditorDocument.parse(kind, raw),
          throwsFormatException,
        );
      }
    }
    expect(
      () => ComplexEditorDocument.parse(
        ComplexEditorKind.mindmap,
        '{"nodeData":{"topic":"missing id"}}',
      ),
      throwsFormatException,
    );
    expect(
      () => ComplexEditorDocument.parse(
        ComplexEditorKind.presentation,
        '{"width":1,"height":1,"slides":[{"id":"s","elements":[]},{"id":"s","elements":[]}]}',
      ),
      throwsFormatException,
    );
    expect(
      ComplexEditorDocument.parse(ComplexEditorKind.drawing, '[]').source,
      '[]',
    );
  });
  test(
    'fromBytes retains repeated leading BOMs and rejects malformed UTF-8',
    () {
      for (final count in [0, 1, 2, 3]) {
        final source =
            '${List<String>.filled(count, '\ufeff').join()}<!doctype html>';
        final bytes = utf8.encode(source);
        expect(
          ComplexEditorDocument.fromBytes(ComplexEditorKind.html, bytes).source,
          source,
          reason: 'leading BOM count $count',
        );
        expect(
          utf8.encode(
            ComplexEditorDocument.fromBytes(
              ComplexEditorKind.html,
              bytes,
            ).source,
          ),
          bytes,
        );
      }
      final bomOnly = List<int>.filled(9, 0).toList();
      for (var i = 0; i < bomOnly.length; i += 3) {
        bomOnly[i] = 0xef;
        bomOnly[i + 1] = 0xbb;
        bomOnly[i + 2] = 0xbf;
      }
      expect(
        ComplexEditorDocument.fromBytes(ComplexEditorKind.html, bomOnly).source,
        List<String>.filled(3, '\ufeff').join(),
      );
      expect(
        () => ComplexEditorDocument.fromBytes(ComplexEditorKind.html, [
          0xc3,
          0x28,
        ]),
        throwsFormatException,
      );
    },
  );

  test(
    'byte limits distinguish HTML5MiB and presentation20MiB without rewriting boundaries',
    () {
      final html = 'x' * (5 * 1024 * 1024);
      expect(
        ComplexEditorDocument.parse(ComplexEditorKind.html, html).byteLength,
        5 * 1024 * 1024,
      );
      expect(
        () => ComplexEditorDocument.parse(ComplexEditorKind.html, '$html中'),
        throwsFormatException,
      );
      final json = jsonEncode({
        'width': 1000,
        'height': 562.5,
        'slides': [
          {'id': 's', 'elements': []},
        ],
        'future': 'x' * (6 * 1024 * 1024),
      });
      expect(
        ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          json,
        ).byteLength,
        greaterThan(5 * 1024 * 1024),
      );
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          'x' * (20 * 1024 * 1024 + 1),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'escaped invalid Unicode, excessive depth and nonfinite decoded numbers are rejected',
    () {
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          String.fromCharCode(0xd800),
        ),
        throwsFormatException,
      );
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.mindmap,
          r'{"nodeData":{"id":"s","topic":"\ud800"}}',
        ),
        throwsFormatException,
      );
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          '{"elements":[],"future":${'[' * 65}0${']' * 65}}',
        ),
        throwsFormatException,
      );
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          '{"width":1e999,"height":1,"slides":[{"id":"s","elements":[]}]}',
        ),
        throwsFormatException,
      );
    },
  );
}
