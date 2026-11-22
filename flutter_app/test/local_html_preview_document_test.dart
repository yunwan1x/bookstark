import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_html_preview_document.dart';

void main() {
  test('passive mode participates in native configuration and identity', () {
    final active = LocalHtmlPreviewDocument('<script>x()</script>', const []);
    final passive = LocalHtmlPreviewDocument(
      active.source,
      const [],
      scriptsEnabled: false,
    );
    expect(active.toNative('a', english: true)['scriptsEnabled'], isTrue);
    expect(passive.toNative('a', english: true)['scriptsEnabled'], isFalse);
    expect(passive.fingerprint, isNot(active.fingerprint));
    expect(passive.source, active.source);
  });
  test('raster response owns immutable bytes and rejects active MIME', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final response = LocalHtmlRasterResponse(mime: 'image/png', bytes: bytes);
    bytes[0] = 9;
    expect(response.bytes, [1, 2, 3]);
    expect(() => response.bytes[0] = 9, throwsUnsupportedError);
    for (final mime in [
      'image/svg+xml',
      'text/html',
      'text/css',
      'application/javascript',
    ]) {
      expect(
        () => LocalHtmlRasterResponse(mime: mime, bytes: bytes),
        throwsFormatException,
      );
    }
    expect(
      () => LocalHtmlRasterResponse(
        mime: 'image/png',
        bytes: Uint8List(5 * 1024 * 1024 + 1),
      ),
      throwsFormatException,
    );
  });

  test(
    'source is preview-only and resource bytes cannot change after validation',
    () {
      const source =
          '<!doctype html>\r\n<html><script>window.x=1</script></html>\n';
      final bytes = Uint8List.fromList([1, 2, 3]);
      final resource = LocalHtmlPreviewResource(
        path: 'images/cover.png',
        mime: 'image/png',
        bytes: bytes,
      );
      final document = LocalHtmlPreviewDocument(source, [resource]);
      bytes[0] = 99;
      expect(resource.bytes, [1, 2, 3]);
      expect(() => resource.bytes[0] = 99, throwsUnsupportedError);
      expect(document.source, source);
      final native = document.toNative('local-lease', english: false);
      expect(native.keys.toSet(), {
        'lease',
        'source',
        'resources',
        'english',
        'scriptsEnabled',
      });
      expect(native.containsKey('cookies'), isFalse);
      expect(native.containsKey('server'), isFalse);
      expect(
        document.fingerprint,
        LocalHtmlPreviewDocument(source, [resource]).fingerprint,
      );
      expect(
        document.fingerprint,
        isNot(LocalHtmlPreviewDocument('$source ', [resource]).fingerprint),
      );
    },
  );
  test(
    'invalid relative paths, reserved document and unsupported MIME fail before native creation',
    () {
      for (final path in [
        '',
        '/',
        '../cover.png',
        'a/../b.js',
        './b.js',
        'a//b.js',
        'a\\b.js',
        'a/\u0000b',
        'index.html',
      ]) {
        expect(
          () => LocalHtmlPreviewResource(
            path: path,
            mime: 'text/css',
            bytes: Uint8List(0),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => LocalHtmlPreviewResource(
          path: 'theme.css',
          mime: 'text/css\r\nX: unsafe',
          bytes: Uint8List(0),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'duplicate mappings and bounded resource counts cannot create ambiguous documents',
    () {
      final resource = LocalHtmlPreviewResource(
        path: 'theme.css',
        mime: 'text/css',
        bytes: Uint8List(1),
      );
      expect(
        () => LocalHtmlPreviewDocument('<p>test</p>', [resource, resource]),
        throwsFormatException,
      );
      expect(
        () => LocalHtmlPreviewDocument(
          '<p>test</p>',
          List.generate(
            33,
            (i) => LocalHtmlPreviewResource(
              path: '$i.css',
              mime: 'text/css',
              bytes: Uint8List(0),
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => LocalHtmlPreviewResource(
          path: 'large.js',
          mime: 'application/javascript',
          bytes: Uint8List(5 * 1024 * 1024 + 1),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'maximum raw fragment remains previewable with a bounded presentation wrapper',
    () {
      final fragment = 'x' * (5 * 1024 * 1024);
      final document = LocalHtmlPreviewDocument(fragment, []);
      expect(document.source.length, greaterThan(fragment.length));
      expect(
        document.source.length,
        lessThanOrEqualTo(fragment.length + 16 * 1024),
      );
      expect(
        () => LocalHtmlPreviewDocument('${fragment}x', []),
        throwsFormatException,
      );
    },
  );
}
