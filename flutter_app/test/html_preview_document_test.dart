import 'package:bookstark_flutter/features/html/html_preview_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'complete documents preserve doctype, scripts, custom base and CSS exactly',
    () {
      for (final source in [
        '  <!doctype html>\n<html><head><base href="https://content.example/"><style>body{color:red}</style></head><body><script>const x = "<html>";</script></body></html>',
        '\n<HTML lang="zh"><BODY>Full document</BODY></HTML>',
      ]) {
        expect(
          buildHtmlPreviewDocument(
            source,
            server: Uri.parse('https://books.example/prefix'),
          ),
          source,
        );
      }
    },
  );
  test(
    'fragments retain script and event source while only preview gets defaults',
    () {
      const source =
          '<button onclick="this.textContent=42">Run</button><script>window.x = "你好";</script>';
      final preview = buildHtmlPreviewDocument(
        source,
        server: Uri.parse('https://books.example/mount/'),
      );
      expect(preview, contains('<body>$source</body>'));
      expect(
        preview,
        contains('https://books.example/mount/static/css/modern-normalize.css'),
      );
      expect(preview, contains('name="viewport"'));
      expect(
        buildHtmlPreviewDocument(source, bare: true),
        isNot(contains('<style>')),
      );
      expect(buildHtmlPreviewDocument(source, bare: true), contains(source));
    },
  );
  test(
    'empty local source remains loadable and oversized source stays explicit',
    () {
      final preview = buildHtmlPreviewDocument('');
      expect(preview, contains('<body></body>'));
      expect(preview, isNot(contains('<link')));
      expect(
        () => buildHtmlPreviewDocument('x' * (5 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );
}
