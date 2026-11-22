import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'fixed same-origin raw endpoint preserves decoded source and gzip header',
    () async {
      const source = '<!doctype html>\n<script>window.x = "你好";</script>\n';
      final client = BookstarkClient(
        'https://books.example/prefix',
        transport: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://books.example/prefix/api/blogs/7/content/raw',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], contains('token=owned'));
          expect(request.headers['cache-control'], 'no-store');
          return http.Response.bytes(
            utf8.encode(source),
            200,
            headers: {
              'content-type': 'text/html; charset=utf-8',
              'content-encoding': 'gzip',
            },
          );
        }),
      );
      client.restoreSession({'token': 'owned'});
      expect(await client.blogHtmlSource(7), source);
      client.close();
    },
  );
  test(
    'protected source uses CSRF POST and preserves password spaces',
    () async {
      var count = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((request) async {
          count++;
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/api/blogs/8/verify-password/raw');
          expect(request.headers['x-csrf-token'], 'csrf');
          expect(jsonDecode(request.body), {'password': ' 你好 '});
          return http.Response(
            '<b>secret</b>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
      expect(await client.blogHtmlSource(8, password: ' 你好 '), '<b>secret</b>');
      expect(count, 2);
      client.close();
    },
  );
  test('accepts full 5MiB HTML and rejects a decoded byte beyond it', () async {
    var oversized = false;
    final source = 'x' * (5 * 1024 * 1024);
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient(
        (_) async => http.Response(
          source + (oversized ? 'x' : ''),
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    expect((await client.blogHtmlSource(1)).length, source.length);
    oversized = true;
    await expectLater(
      client.blogHtmlSource(1),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 413)),
    );
    client.close();
  });
  test(
    'rejects error, redirect, wrong MIME, charset and malformed UTF-8',
    () async {
      for (final response in [
        http.Response('private error', 403),
        http.Response(
          '',
          302,
          headers: {'location': 'https://elsewhere.example'},
        ),
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
        http.Response(
          'x',
          200,
          headers: {'content-type': 'text/html; charset=latin1'},
        ),
        http.Response.bytes(
          [0xff],
          200,
          headers: {'content-type': 'text/html'},
        ),
      ]) {
        final client = BookstarkClient(
          'https://books.example',
          transport: MockClient((_) async => response),
        );
        await expectLater(client.blogHtmlSource(1), throwsA(isA<Exception>()));
        client.close();
      }
    },
  );
  test('invalid identifiers and passwords perform no request', () async {
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient(
        (_) async => throw StateError('Unexpected request'),
      ),
    );
    await expectLater(client.blogHtmlSource(0), throwsFormatException);
    await expectLater(
      client.blogHtmlSource(1, password: ''),
      throwsFormatException,
    );
    await expectLater(
      client.blogHtmlSource(1, password: '中' * 342),
      throwsFormatException,
    );
    client.close();
  });
}
