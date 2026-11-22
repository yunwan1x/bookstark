import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_html_resources.dart';

void main() {
  test(
    'root-relative resources stay inside the configured mount and share a canonical cache key',
    () async {
      var calls = 0;
      final server = Uri.parse('https://example.test/reader');
      final repo = PublicHtmlResources(
        server,
        transport: MockClient((request) async {
          calls++;
          expect(request.url.pathSegments, ['reader', 'static', '模块%2F.js']);
          expect(request.url.queryParameters, {'v': 'abc'});
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response(
            'window.test=1',
            200,
            headers: {'content-type': 'application/javascript'},
          );
        }),
      );
      final root = Uri.parse('https://example.test/static/模块%252F.js?v=abc');
      final mounted = server.replace(
        pathSegments: ['reader', 'static', '模块%2F.js'],
        queryParameters: {'v': 'abc'},
      );
      final first = await repo.read(root), second = await repo.read(mounted);
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      expect(
        repo.allows(Uri.parse('https://example.test/other/static/a.js')),
        isFalse,
      );
      repo.close();
    },
  );
  final server = Uri.parse('https://example.test/base');
  test(
    'public HTML resources only allow exact server static/uploads and safe versions',
    () {
      final repo = PublicHtmlResources(server);
      expect(repo.allows(Uri.parse('$server/static/app.js?v=a1_2')), isTrue);
      expect(
        repo.allows(Uri.parse('$server/upload-files/picture.png')),
        isTrue,
      );
      for (final raw in [
        'https://other.test/base/static/a.js',
        'https://example.test/base2/static/a.js',
        '$server/api/profile',
        '$server/upload-files/a.png?v=1',
        '$server/static/a.js?token=secret',
        '$server/static/a.js?v=1&v=2',
        '$server/static/a.js#fragment',
        'https://user@example.test/base/static/a.js',
        '$server/static/a%2fb.js',
        '$server/static/../private.js',
        'ftp://example.test/base/static/a.js',
      ]) {
        expect(repo.allows(Uri.parse(raw)), isFalse, reason: raw);
      }
      repo.close();
    },
  );
  test(
    'public renderer fetches bytes without account cookies or redirects and caches exactly once',
    () async {
      var calls = 0;
      final repo = PublicHtmlResources(
        server,
        transport: MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('x-csrf-token'), isFalse);
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'text/javascript'},
          );
        }),
      );
      final uri = Uri.parse('$server/static/app.js');
      final first = await repo.read(uri);
      final again = await repo.read(uri);
      expect(identical(first, again), isTrue);
      expect(calls, 1);
      expect(repo.loaded, 1);
      expect(first.mime, 'application/javascript');
      expect(() => first.bytes[0] = 99, throwsUnsupportedError);
      repo.close();
      await expectLater(repo.read(uri), throwsStateError);
    },
  );
  test(
    'concurrent public resource requests are serialized before transport allocation',
    () async {
      final release = Completer<http.StreamedResponse>();
      var calls = 0;
      final repo = PublicHtmlResources(
        server,
        transport: MockClient.streaming((request, _) async {
          calls++;
          if (calls == 1) return release.future;
          return http.StreamedResponse(
            Stream.value([2]),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final first = repo.read(Uri.parse('$server/upload-files/a.png'));
      final second = repo.read(Uri.parse('$server/upload-files/b.png'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      release.complete(
        http.StreamedResponse(
          Stream.value([1]),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await first;
      await second;
      expect(calls, 2);
      expect(repo.loaded, 2);
      repo.close();
    },
  );
  test(
    'public resource scope, MIME and redirect failures never become bytes or repeat automatically',
    () async {
      for (final status in [200, 302]) {
        var calls = 0;
        final repo = PublicHtmlResources(
          server,
          transport: MockClient((_) async {
            calls++;
            return http.Response(
              'not a public asset',
              status,
              headers: {
                'content-type': status == 200 ? 'text/html' : 'text/css',
                'location': 'https://other.test',
              },
            );
          }),
        );
        await expectLater(
          repo.read(Uri.parse('$server/api/profile')),
          throwsFormatException,
        );
        expect(calls, 0);
        final uri = Uri.parse('$server/static/a.css');
        await expectLater(repo.read(uri), throwsFormatException);
        await expectLater(repo.read(uri), throwsFormatException);
        expect(calls, 1);
        expect(repo.loaded, 0);
        repo.close();
      }
    },
  );
  test(
    'resource bytes stay within individual and total caps and stop before fifth allocation',
    () async {
      var calls = 0;
      final bytes = Uint8List(PublicHtmlResources.maxResourceBytes);
      final repo = PublicHtmlResources(
        server,
        transport: MockClient.streaming((_, _) async {
          calls++;
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      for (var index = 0; index < 4; index++) {
        await repo.read(Uri.parse('$server/upload-files/$index.png'));
      }
      await expectLater(
        repo.read(Uri.parse('$server/upload-files/extra.png')),
        throwsFormatException,
      );
      expect(calls, 4);
      expect(repo.loaded, 4);
      repo.close();
      final large = PublicHtmlResources(
        server,
        transport: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            const Stream.empty(),
            200,
            contentLength: PublicHtmlResources.maxResourceBytes + 1,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      await expectLater(
        large.read(Uri.parse('$server/upload-files/too-large.png')),
        throwsA(anything),
      );
      large.close();
    },
  );
  test(
    'resource count includes empty files and blocks the thirty-third request',
    () async {
      var calls = 0;
      final repo = PublicHtmlResources(
        server,
        transport: MockClient((_) async {
          calls++;
          return http.Response('', 200, headers: {'content-type': 'text/css'});
        }),
      );
      for (var index = 0; index < 32; index++) {
        await repo.read(Uri.parse('$server/static/$index.css'));
      }
      await expectLater(
        repo.read(Uri.parse('$server/static/extra.css')),
        throwsFormatException,
      );
      expect(calls, 32);
      repo.close();
    },
  );
  test(
    'closing public resource scope aborts in-flight transport and discards late bytes',
    () async {
      final response = Completer<http.StreamedResponse>();
      var aborted = false;
      final repo = PublicHtmlResources(
        server,
        transport: MockClient.streaming((request, _) async {
          (request as http.AbortableRequest).abortTrigger!.then(
            (_) => aborted = true,
          );
          return response.future;
        }),
      );
      final reading = repo.read(Uri.parse('$server/static/app.js'));
      await Future<void>.delayed(Duration.zero);
      repo.close();
      await Future<void>.delayed(Duration.zero);
      expect(aborted, isTrue);
      response.complete(
        http.StreamedResponse(
          Stream.value([1]),
          200,
          headers: {'content-type': 'application/javascript'},
        ),
      );
      await expectLater(reading, throwsStateError);
      expect(repo.loaded, 0);
    },
  );
  test(
    'stalled public resources have a deadline even if the transport ignores abort',
    () async {
      final response = Completer<http.StreamedResponse>();
      final repo = PublicHtmlResources(
        server,
        timeout: const Duration(milliseconds: 20),
        transport: MockClient.streaming((_, _) => response.future),
      );
      await expectLater(
        repo.read(Uri.parse('$server/static/stalled.js')),
        throwsA(isA<TimeoutException>()),
      );
      repo.close();
      response.complete(
        http.StreamedResponse(
          const Stream.empty(),
          200,
          headers: {'content-type': 'application/javascript'},
        ),
      );
    },
  );
}
