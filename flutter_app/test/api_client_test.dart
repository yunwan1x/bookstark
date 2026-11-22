import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects embedded credentials, query parameters and unsafe schemes', () {
    for (final url in [
      'javascript:alert(1)',
      'https://user:pass@example.com',
      'https://example.com?token=secret',
      'https://example.com#fragment',
    ]) {
      expect(() => BookstarkClient(url), throwsFormatException);
    }
  });

  test(
    'login cookie and CSRF are sent to the same server for a mutation',
    () async {
      final seen = <http.Request>[];
      final client = BookstarkClient(
        'https://books.example/prefix/',
        transport: MockClient((request) async {
          seen.add(request);
          expect(request.url.origin, 'https://books.example');
          if (request.url.path == '/prefix/api/login') {
            expect(jsonDecode(request.body), {
              'account': 'reader',
              'password': 'secret',
            });
            return http.Response(
              '{"code":0,"data":{"member":{"account":"reader"}}}',
              200,
              headers: {
                'set-cookie': 'token=session; HttpOnly; Path=/; Secure',
              },
            );
          }
          if (request.url.path == '/prefix/api/csrf-token') {
            expect(request.headers['cookie'], contains('token=session'));
            return http.Response(
              '{"csrf_token":"csrf-value"}',
              200,
              headers: {'set-cookie': 'csrf_token=csrf-value; Path=/; Secure'},
            );
          }
          expect(request.url.path, '/prefix/api/blogs');
          expect(request.headers['cookie'], contains('csrf_token=csrf-value'));
          expect(request.headers['x-csrf-token'], 'csrf-value');
          return http.Response('{"code":0,"data":{"blog_id":7}}', 200);
        }),
      );
      await client.login('reader', 'secret');
      expect(await client.post('/api/blogs', {'title': 'A'}), {'blog_id': 7});
      expect(seen.length, 3);
      client.close();
    },
  );

  test(
    'does not leak session cookies to an absolute external request',
    () async {
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient(
          (_) async => http.Response('{"code":0,"data":{}}', 200),
        ),
      );
      await expectLater(
        client.get('https://other.example/api/profile'),
        throwsFormatException,
      );
      client.close();
    },
  );

  test(
    'reports service errors without accepting an unsuccessful login',
    () async {
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient(
          (_) async => http.Response(
            '{"code":401,"message":"账号或密码错误"}',
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        client.login('reader', 'wrong'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('账号或密码错误'),
          ),
        ),
      );
      client.close();
    },
  );
}
