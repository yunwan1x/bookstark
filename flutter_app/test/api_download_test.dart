import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  test(
    'authenticated range downloads preserve mount path and literal file names without redirects',
    () async {
      final transport = MockClient((request) async {
        expect(request.url.path, '/mount/api/webdav/files/download');
        expect(request.url.queryParameters['path'], '资料/a%2Fb?.txt');
        expect(request.headers['cookie'], contains('token=fixture-only'));
        expect(request.headers['range'], 'bytes=2-6');
        expect(request.headers['if-range'], '"actual-hash"');
        expect(request.followRedirects, isFalse);
        return http.Response(
          '23456',
          206,
          headers: {'content-range': 'bytes 2-6/10', 'etag': '"actual-hash"'},
        );
      });
      final client = BookstarkClient(
        'https://server.test/mount',
        transport: transport,
      )..restoreSession({'token': 'fixture-only'});
      addTearDown(client.close);
      final result = await client.downloadResponse(
        '/api/webdav/files/download?${Uri(queryParameters: {'path': '资料/a%2Fb?.txt'}).query}',
        range: 'bytes=2-6',
        ifRange: '"actual-hash"',
      );
      expect(result.statusCode, 206);
      expect(result.headers['content-range'], 'bytes 2-6/10');
      expect(
        utf8.decode(await readBoundedResponse(result, maxBytes: 5)),
        '23456',
      );
    },
  );
  test(
    'invalid ranges, header controls and non-API endpoints are rejected before sending credentials',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://server.test',
        transport: MockClient((_) async {
          calls++;
          return http.Response('x', 200);
        }),
      );
      addTearDown(client.close);
      for (final range in [
        'bytes=0-1,5-8',
        'x=0-1',
        'bytes=-',
        'bytes=0-1\r\nCookie:x',
      ]) {
        await expectLater(
          client.downloadResponse('/api/webdav/files/download', range: range),
          throwsFormatException,
        );
      }
      await expectLater(
        client.downloadResponse(
          '/api/webdav/files/download',
          ifRange: 'x\r\nCookie:x',
        ),
        throwsFormatException,
      );
      await expectLater(
        client.downloadResponse('https://elsewhere.test/api/data'),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'binary bounds and server rejection remain observable to the caller',
    () async {
      final client = BookstarkClient(
        'https://server.test',
        transport: MockClient(
          (request) async => request.url.queryParameters['deny'] == '1'
              ? http.Response(
                  jsonEncode({'code': 403, 'message': 'private'}),
                  403,
                  headers: {'content-type': 'application/json'},
                )
              : http.Response('too many bytes', 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.download('/api/webdav/files/download', maxBytes: 3),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 413),
        ),
      );
      await expectLater(
        client.download('/api/webdav/files/download?deny=1'),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 403),
        ),
      );
    },
  );
  test(
    'read and mutation cancellation signal reaches the transport including CSRF acquisition',
    () async {
      final abort = Completer<void>();
      final seen = <http.AbortableRequest>[];
      final transport = MockClient.streaming((request, body) async {
        expect(request, isA<http.AbortableRequest>());
        seen.add(request as http.AbortableRequest);
        expect(request.abortTrigger, same(abort.future));
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': {'ok': true},
              }),
            ),
          ),
          200,
          headers: request.url.path.endsWith('/csrf-token')
              ? {'set-cookie': 'csrf_token=fixture-only; Path=/'}
              : {},
        );
      });
      final client = BookstarkClient(
        'https://server.test',
        transport: transport,
      );
      addTearDown(client.close);
      await client.get('/api/webdav/profile', abortTrigger: abort.future);
      await client.post('/api/webdav/files/mkdir', {
        'path': '',
        'name': 'a',
      }, abortTrigger: abort.future);
      expect(seen.length, 3);
      abort.complete();
    },
  );
}
