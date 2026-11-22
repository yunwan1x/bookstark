import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/public_shares/public_html_preview_document.dart';

void main() {
  final server = Uri.parse('https://example.test/base');
  test(
    'public fragment and full HTML receive one earlier server base without changing script strings',
    () {
      const source =
          '\ufeff<!doctype html>\r\n<html data-quote=">"><head><base href="https://other.test/"><script>const text="<head>keep</head>";</script></head><body>body</body></html>';
      final result = publicHtmlPreviewDocument(source, server);
      expect(
        result.replaceFirst('<base href="https://example.test/base/">', ''),
        source,
      );
      expect(
        result.indexOf('https://example.test/base/'),
        lessThan(result.indexOf('https://other.test/')),
      );
      expect(
        publicHtmlPreviewDocument('<h1>fragment</h1>', server),
        contains('<head><base href="https://example.test/base/">'),
      );
    },
  );
  test(
    'implicit head insertion keeps source and does not match a head tag inside script',
    () {
      const source =
          '<!doctype html><html><script>let text="<head>literal</head>"</script><p>body</p></html>';
      final result = publicHtmlPreviewDocument(source, server);
      expect(
        result.replaceFirst(
          '<head><base href="https://example.test/base/"></head>',
          '',
        ),
        source,
      );
    },
  );
  test(
    'public preview preserves original source limit and escapes presentation URL',
    () {
      expect(
        publicHtmlPreviewDocument(
          '<p>x</p>',
          Uri.parse('https://example.test/a&b'),
        ),
        contains('/a&amp;b/'),
      );
      expect(
        () => publicHtmlPreviewDocument('x' * (5 * 1024 * 1024 + 1), server),
        throwsFormatException,
      );
    },
  );
}
