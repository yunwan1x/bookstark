import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  test(
    'multipart retains prefix, authenticated cookies, CSRF, filename and actual bytes',
    () async {
      final client = BookstarkClient(
        'https://example.test/bookstark',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{"code":0}',
              200,
              headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
            );
          }
          expect(r.url.path, '/bookstark/api/uploads');
          expect(r.followRedirects, isFalse);
          expect(r.headers['cookie'], contains('token=session'));
          expect(r.headers['x-csrf-token'], 'csrf');
          expect(
            r.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(r.body, contains('name="file"; filename="image.png"'));
          expect(r.body, contains('actual-file-bytes'));
          expect(r.body, contains('name="category"'));
          return http.Response(
            '{"code":0,"data":{"url":"/upload-files/x.webp"}}',
            200,
          );
        }),
      );
      client.restoreSession({'token': 'session'});
      final bytes = utf8.encode('actual-file-bytes');
      final result = await client.upload(
        '/api/uploads',
        name: 'image.png',
        data: Stream.value(bytes),
        length: bytes.length,
        fields: {'category': 'editor'},
      );
      expect(result['url'], '/upload-files/x.webp');
    },
  );
  test(
    'binary response is bounded even without Content-Length and redirects are refused',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient.streaming(
          (request, body) async => http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
          ),
        ),
      );
      await expectLater(
        client.download('/api/webdav/files/download?path=%2Fa', maxBytes: 3),
        throwsA(isA<ApiFailure>()),
      );
      final redirect = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => http.Response(
            '',
            302,
            headers: {'location': 'https://evil.test/'},
          ),
        ),
      );
      await expectLater(
        redirect.download('/api/webdav/files/download?path=%2Fa'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}
