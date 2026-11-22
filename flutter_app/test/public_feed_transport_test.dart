import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_feed_models.dart';

void main() {
  test(
    'discovery uses fixed prefixed origin with encoded filters and refuses redirects',
    () async {
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.origin, 'https://example.test');
          expect(request.url.path, '/base/shares');
          expect(request.url.queryParameters['label'], 'a&b%2F中文');
          expect(request.headers['accept'], 'text/html');
          expect(request.headers['cookie'], contains('token=session'));
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            utf8.encode('<html>公开</html>'),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      client.restoreSession({'token': 'session'});
      expect(
        await client.publicFeedHtml(PublicFeedQuery(label: 'a&b%2F中文')),
        '<html>公开</html>',
      );
      client.close();
    },
  );
  test(
    'unexpected media, invalid UTF8 and redirection are errors rather than empty content',
    () async {
      for (final response in [
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
        http.Response(
          'html',
          200,
          headers: {'content-type': 'text/html; charset=gbk'},
        ),
        http.Response.bytes(
          [0xff],
          200,
          headers: {'content-type': 'text/html'},
        ),
        http.Response('', 302, headers: {'location': 'https://evil.test'}),
      ]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((_) async => response),
        );
        await expectLater(
          client.publicFeedHtml(PublicFeedQuery()),
          throwsA(anything),
        );
        client.close();
      }
    },
  );
}
