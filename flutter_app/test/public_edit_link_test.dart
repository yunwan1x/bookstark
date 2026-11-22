import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';

void main() {
  final server = Uri.parse('https://example.test/base');
  final token = List.filled(64, 'a').join();
  test(
    'actual same-origin editing URL retains encoded identifier once and redacts capability from public link',
    () {
      final link = PublicEditLink.parse(
        server,
        'https://example.test/base/shares/中文%252F+?token=$token',
      );
      expect(link.reference.identify, '中文%2F+');
      expect(Uri.parse(link.requestPath).pathSegments, [
        'api',
        'shares',
        '中文%2F+',
        'edit',
      ]);
      expect(Uri.parse(link.requestPath).queryParameters['token'], token);
      expect(link.publicUri.hasQuery, isFalse);
      expect(link.publicUri.toString(), isNot(contains(token)));
      expect(link.toString(), isNot(contains(token)));
    },
  );
  test(
    'credentials, foreign origin or prefix, fragments, duplicate and unrelated query parameters are rejected',
    () {
      for (final input in [
        'http://example.test/base/shares/a?token=$token',
        'https://other.test/base/shares/a?token=$token',
        'https://user:password@example.test/base/shares/a?token=$token',
        'https://example.test/shares/a?token=$token',
        'https://example.test/base/api/shares/a/edit?token=$token',
        'https://example.test/base/shares/a?token=$token#fragment',
        'https://example.test/base/shares/a?token=$token&token=$token',
        'https://example.test/base/shares/a?token=$token&account=owner',
        'https://example.test/base/shares/a',
        'https://example.test/base/shares/%2fprivate?token=$token',
      ]) {
        try {
          PublicEditLink.parse(server, input);
          fail('Expected invalid link');
        } on FormatException catch (error) {
          expect(error.toString(), isNot(contains(token)));
        }
      }
    },
  );
}
