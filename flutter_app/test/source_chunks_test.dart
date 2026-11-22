import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';

void main() {
  test(
    'large BOM/CRLF source reconstructs exactly across surrogate boundaries',
    () {
      final source = '\uFEFF\r\n${'😀x中\r\n' * 500000}';
      expect(utf8.encode(source).length, greaterThan(3 * 1024 * 1024));

      final chunks = SourceChunks(source);
      expect(chunks.length, greaterThan(300));
      expect(List.generate(chunks.length, chunks.at).join(), source);
      expect(chunks.at(0), startsWith('\uFEFF\r\n'));
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks.at(i).length, lessThanOrEqualTo(4096));
        if (i + 1 < chunks.length) {
          final boundary = chunks.boundaries[i + 1];
          final left = source.codeUnitAt(boundary - 1);
          final right = source.codeUnitAt(boundary);
          expect(
            left >= 0xd800 &&
                left <= 0xdbff &&
                right >= 0xdc00 &&
                right <= 0xdfff,
            isFalse,
          );
        }
      }
    },
  );

  test('editor threshold uses UTF-8 bytes for multilingual source', () {
    expect(SourceChunks.utf8ByteLength('a' * 500000), 500000);
    expect(SourceChunks.utf8ByteLength('a' * 500001), 500001);
    expect(SourceChunks.utf8ByteLength('中' * 166666), 499998);
    expect(SourceChunks.utf8ByteLength('😀' * 125000), 500000);
    expect(SourceChunks.utf8ByteLength('😀' * 125001), 500004);
  });

  test(
    'streaming UTF-8 byte count matches encoder for deterministic Unicode',
    () {
      final samples = <String>[
        '',
        'ascii',
        '中',
        '😀',
        '\uFEFF\r\n',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        for (var i = 0; i < 100; i++) 'row $i · 中文 · 😀\r\n',
      ];
      for (final source in samples) {
        expect(
          SourceChunks.utf8ByteLength(source),
          utf8.encode(source).length,
          reason: 'byte count for sample: $source',
        );
      }
    },
  );
}
