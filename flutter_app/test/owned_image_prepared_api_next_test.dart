import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=',
    ),
  );
  String getHash() => sha256.convert(bytes).toString();
  http.Response root(Object data, {Map<String, String> headers = const {}}) =>
      http.Response(
        jsonEncode({'code': 0, 'data': data}),
        200,
        headers: {'content-type': 'application/json', ...headers},
      );
  test(
    'actual multipart is prepared before durable marker; one explicit send uses original owner and prefix',
    () async {
      var profiles = 0, csrf = 0, posts = 0, boundaries = 0;
      final client = BookstarkClient(
        'https://owned.test/prefix',
        transport: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/prefix/api/profile') {
            profiles++;
            return root({'member_id': 7});
          }
          if (request.method == 'GET' &&
              request.url.path == '/prefix/api/csrf-token') {
            csrf++;
            return http.Response(
              jsonEncode({'code': 0, 'csrf_token': 'fixture-csrf'}),
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=fixture-csrf; Path=/',
              },
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/prefix/api/uploads');
          expect(boundaries, 1);
          expect(request.headers['cookie'], contains('token=fixture-only'));
          expect(request.headers['x-csrf-token'], 'fixture-csrf');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data;'),
          );
          expect(request.bodyBytes.length, greaterThan(bytes.length));
          posts++;
          return root({
            'id': 208,
            'url': '/upload-files/tiny.png',
            'thumb_url': '',
            'file_name': 'tiny.png',
            'width': 1,
            'height': 1,
            'file_size': bytes.length,
          });
        }),
      );
      client.restoreSession({'token': 'fixture-only'});
      addTearDown(client.close);
      final prepared = await client.prepareOwnedImageUpload(
        imageBytes: bytes,
        fileName: 'tiny.png',
        inputSHA256: getHash(),
        expectedMemberId: 7,
        expectedSessionRevision: client.sessionRevision,
        ownerGuard: () {},
      );
      expect(profiles, 1);
      expect(csrf, 1);
      expect(posts, 0);
      final marker = Completer<void>();
      final work = prepared.sendAfter(
        onSubmit: () async {
          boundaries++;
          await marker.future;
        },
      );
      await Future<void>.value();
      expect(posts, 0);
      marker.complete();
      final result = await work;
      expect((result['data'] as Map)['id'], 208);
      expect(posts, 1);
      expect(boundaries, 1);
      await expectLater(
        prepared.sendAfter(
          onSubmit: () async {
            boundaries++;
          },
        ),
        throwsStateError,
      );
      expect(posts, 1);
      expect(boundaries, 1);
    },
  );
  test(
    'owner retires while legitimate CSRF is held: no prepared mutation or durable marker',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var current = true, posts = 0;
      final client = BookstarkClient(
        'https://owned.test',
        transport: MockClient((request) async {
          if (request.url.path == '/api/profile') return root({'member_id': 7});
          if (request.method == 'GET') {
            entered.complete();
            await release.future;
            return http.Response(
              jsonEncode({'code': 0, 'csrf_token': 'fixture-csrf'}),
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=fixture-csrf; Path=/',
              },
            );
          }
          posts++;
          return root({});
        }),
      );
      client.restoreSession({'token': 'fixture-only'});
      addTearDown(client.close);
      final preparing = client.prepareOwnedImageUpload(
        imageBytes: bytes,
        fileName: 'tiny.png',
        inputSHA256: getHash(),
        expectedMemberId: 7,
        expectedSessionRevision: client.sessionRevision,
        ownerGuard: () {
          if (!current) throw StateError('Owner retired');
        },
      );
      final failure = expectLater(preparing, throwsStateError);
      await entered.future;
      current = false;
      release.complete();
      await failure;
      expect(posts, 0);
    },
  );
  for (final retirement in ['same-token', 'abort']) {
    test(
      'prepared upload $retirement while durable marker awaits cannot send',
      () async {
        var posts = 0, boundaries = 0;
        final abort = Completer<void>(), marker = Completer<void>();
        final client = BookstarkClient(
          'https://owned.test',
          transport: MockClient((request) async {
            if (request.method == 'GET') return root({'member_id': 7});
            posts++;
            return root({});
          }),
        );
        client.restoreSession({
          'token': 'fixture-only',
          'csrf_token': 'fixture-csrf',
        });
        addTearDown(client.close);
        final prepared = await client.prepareOwnedImageUpload(
          imageBytes: bytes,
          fileName: 'tiny.png',
          inputSHA256: getHash(),
          expectedMemberId: 7,
          expectedSessionRevision: client.sessionRevision,
          ownerGuard: () {},
          abortTrigger: abort.future,
        );
        final work = prepared.sendAfter(
          onSubmit: () async {
            boundaries++;
            await marker.future;
          },
        );
        final failure = expectLater(
          work,
          throwsA(
            isA<ApiFailure>().having((e) => e.status, 'scope retired', 499),
          ),
        );
        if (retirement == 'same-token') {
          client.restoreSession({
            'token': 'fixture-only',
            'csrf_token': 'fixture-csrf',
          });
        } else {
          abort.complete();
        }
        await Future<void>.value();
        marker.complete();
        await failure;
        expect(boundaries, 1);
        expect(posts, 0);
      },
    );
  }
  test('wrong authenticated member fails before CSRF and any upload', () async {
    var requests = 0;
    final client = BookstarkClient(
      'https://owned.test',
      transport: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/profile');
        return root({'member_id': 99});
      }),
    );
    client.restoreSession({'token': 'fixture-only'});
    addTearDown(client.close);
    await expectLater(
      client.prepareOwnedImageUpload(
        imageBytes: bytes,
        fileName: 'tiny.png',
        inputSHA256: getHash(),
        expectedMemberId: 7,
        expectedSessionRevision: client.sessionRevision,
        ownerGuard: () {},
      ),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'foreign member', 403)),
    );
    expect(requests, 1);
  });
}
