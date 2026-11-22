import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  late BookstarkClient client;
  final requests = <http.Request>[];
  BookstarkClient create(Future<http.Response> Function(http.Request) handle) {
    requests.clear();
    final value = BookstarkClient(
      'https://owned.invalid/prefix',
      transport: MockClient((request) async {
        requests.add(request);
        return handle(request);
      }),
    );
    value.restoreSession({
      'token': 'owned-transfer-token',
      'csrf_token': 'owned-transfer-csrf',
    });
    return value;
  }

  tearDown(() => client.close());
  test(
    'Download retains prefix and exact quoted Unicode path with no redirect',
    () async {
      client = create(
        (request) async => http.Response.bytes(
          [0, 255, 13, 10],
          200,
          headers: {'content-type': 'application/octet-stream'},
        ),
      );
      const path = "/work/中文 '#?.bin";
      final result = await client.adminDownloadRemoteFile<List<int>>(
        17,
        path,
        consume: (response, abort) => response.stream.fold<List<int>>(
          [],
          (all, data) => all..addAll(data),
        ),
      );
      expect(result, [0, 255, 13, 10]);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(
        request.url.path,
        '/prefix/api/admin/assets/ssh-hosts/17/files/download',
      );
      expect(request.url.queryParameters, {'path': path});
      expect(request.followRedirects, false);
      expect(request.headers['cookie'], contains('token=owned-transfer-token'));
    },
  );
  for (final status in [302, 401, 403, 500]) {
    test(
      'Download status $status is refused without invoking binary consumer',
      () async {
        client = create(
          (request) async => http.Response(
            'owned private failure',
            status,
            headers: {
              'location': 'https://external.invalid/',
              'content-type': 'application/octet-stream',
            },
          ),
        );
        var consumed = false;
        await expectLater(
          client.adminDownloadRemoteFile<int>(
            17,
            '/work/a',
            consume: (response, abort) async {
              consumed = true;
              return 0;
            },
          ),
          throwsA(isA<ApiFailure>()),
        );
        expect(consumed, false);
        expect(requests, hasLength(1));
        expect(requests.single.followRedirects, false);
      },
    );
  }
  test(
    'JSON errors cannot masquerade as successful binary downloads',
    () async {
      client = create(
        (request) async => http.Response(
          '{"code":1}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      var consumed = false;
      await expectLater(
        client.adminDownloadRemoteFile<int>(
          17,
          '/work/a',
          consume: (response, abort) async {
            consumed = true;
            return 0;
          },
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(consumed, false);
    },
  );
  test(
    'Multipart upload sends CSRF and exact bytes; sent is independent of receipt',
    () async {
      final progress = <(int, int)>[];
      var submitted = false;
      client = create((request) async {
        expect(submitted, true);
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/prefix/api/admin/assets/ssh-hosts/17/files/upload',
        );
        expect(request.url.queryParameters, {'path': '/work'});
        expect(request.headers['x-csrf-token'], 'owned-transfer-csrf');
        expect(request.followRedirects, false);
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('filename="new.txt"'));
        expect(body, contains(latin1.decode([0, 1, 255, 13, 10])));
        return http.Response(
          '{"code":0,"data":{"path":"/work/new.txt"}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final result = await client.adminUploadRemoteFile(
        17,
        '/work',
        filename: 'new.txt',
        length: 5,
        bytes: Stream.fromIterable([
          [0, 1],
          [255, 13, 10],
        ]),
        onSubmitted: () {
          submitted = true;
        },
        onSent: (sent, total) => progress.add((sent, total)),
      );
      expect(result['path'], '/work/new.txt');
      expect(progress, [(2, 5), (5, 5)]);
    },
  );
  for (final body in ['{"code":1,"data":{}}', '<html>bad</html>']) {
    test(
      'Unsuccessful or malformed upload receipt never means confirmed: $body',
      () async {
        client = create(
          (request) async => http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await expectLater(
          client.adminUploadRemoteFile(
            17,
            '/work',
            filename: 'new.txt',
            length: 1,
            bytes: Stream.value([1]),
          ),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'Upload source changing length fails rather than confirming partial content',
    () async {
      client = create(
        (request) async => http.Response(
          '{"code":0,"data":{}}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        client.adminUploadRemoteFile(
          17,
          '/work',
          filename: 'new.txt',
          length: 1,
          bytes: Stream.value([1, 2]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Invalid targets and multiline upload filename are rejected before network',
    () {
      client = create(
        (request) async => throw StateError('Unexpected network'),
      );
      expect(
        () => client.adminDownloadRemoteFile<int>(
          0,
          '/work/a',
          consume: (r, a) async => 0,
        ),
        throwsFormatException,
      );
      for (final name in ['a\nb', 'a/b', 'a\\b']) {
        expect(
          () => client.adminUploadRemoteFile(
            17,
            '/work',
            filename: name,
            length: 0,
            bytes: const Stream.empty(),
          ),
          throwsFormatException,
        );
      }
      expect(requests, isEmpty);
    },
  );
}
