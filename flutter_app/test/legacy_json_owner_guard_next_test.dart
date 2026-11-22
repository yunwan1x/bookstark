import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

Matcher retired() =>
    throwsA(isA<ApiFailure>().having((e) => e.status, 'retired status', 499));
http.Response reply({Map<String, String> headers = const {}}) =>
    http.Response('{"code":0,"data":{"ok":true}}', 200, headers: headers);
void main() {
  for (final upload in [false, true]) {
    test(
      'cached CSRF await cannot switch token before actual ${upload ? 'multipart' : 'JSON'} send',
      () async {
        var sends = 0, sourceReads = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((request) async {
            sends++;
            return reply();
          }),
        );
        client.restoreSession({'token': 'A', 'csrf_token': 'A-csrf'});
        Stream<List<int>> source() async* {
          sourceReads++;
          yield [1, 2, 3];
        }

        final work = upload
            ? client.upload(
                '/api/uploads',
                name: '原图😀.png',
                data: source(),
                length: 3,
              )
            : client.mutate('PUT', '/api/bookmarks/1', {'title': 'A'});
        final rejected = expectLater(work, retired());
        client.restoreSession({'token': 'B', 'csrf_token': 'B-csrf'});
        await rejected;
        expect(sends, 0);
        expect(sourceReads, 0);
        expect(client.exportSession(), {'token': 'B', 'csrf_token': 'B-csrf'});
        client.close();
      },
    );
    test(
      'network CSRF late Set-Cookie cannot contaminateB or authorize ${upload ? 'upload' : 'mutation'}',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        var writes = 0, csrf = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((request) async {
            if (request.url.path == '/api/csrf-token') {
              csrf++;
              expect(request.headers['cookie'], contains('token=A'));
              entered.complete();
              await release.future;
              return reply(
                headers: {
                  'set-cookie': 'csrf_token=OLD; Path=/, token=OLD-A; Path=/',
                },
              );
            }
            writes++;
            return reply();
          }),
        );
        client.restoreSession({'token': 'A'});
        final work = upload
            ? client.upload(
                '/api/uploads',
                name: 'test.png',
                data: Stream.value([1, 2, 3]),
                length: 3,
              )
            : client.mutate('POST', '/api/bookmarks', {'title': 'A'});
        final rejected = expectLater(work, retired());
        await entered.future;
        client.restoreSession({'token': 'B', 'csrf_token': 'B-csrf'});
        release.complete();
        await rejected;
        expect(csrf, 1);
        expect(writes, 0);
        expect(client.exportSession(), {'token': 'B', 'csrf_token': 'B-csrf'});
        client.close();
      },
    );
  }
  for (final method in ['GET', 'PUT']) {
    test(
      'already sentA $method response cannot merge its token orcsrf intoB',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        var sends = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((request) async {
            sends++;
            expect(request.headers['cookie'], contains('token=A'));
            entered.complete();
            await release.future;
            return reply(
              headers: {
                'set-cookie':
                    'token=OLD-A; Path=/, csrf_token=OLD-CSRF; Path=/',
              },
            );
          }),
        );
        client.restoreSession({'token': 'A', 'csrf_token': 'A-csrf'});
        final rejected = expectLater(
          method == 'GET'
              ? client.get('/api/profile')
              : client.mutate('PUT', '/api/bookmarks/7', {'title': 'A'}),
          retired(),
        );
        await entered.future;
        client.restoreSession({'token': 'B', 'csrf_token': 'B-csrf'});
        release.complete();
        await rejected;
        expect(sends, 1);
        expect(client.exportSession(), {'token': 'B', 'csrf_token': 'B-csrf'});
        client.close();
      },
    );
  }
  test('business beforeSubmit retirement is rechecked before send', () async {
    var sends = 0;
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((request) async {
        sends++;
        return reply();
      }),
    );
    client.restoreSession({'token': 'A', 'csrf_token': 'A-csrf'});
    await expectLater(
      client.mutate(
        'DELETE',
        '/api/bookmarks/7',
        {},
        beforeSubmit: () {
          client.restoreSession({'token': 'B', 'csrf_token': 'B-csrf'});
        },
      ),
      retired(),
    );
    expect(sends, 0);
    client.close();
  });
  test(
    'normal auth login and networkCSRF stayvalid across UI language change',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var csrf = 0, writes = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.url.path == '/api/login') {
            expect(jsonDecode(request.body), {
              'account': 'reader',
              'password': 'synthetic',
            });
            return reply(headers: {'set-cookie': 'token=A; Path=/'});
          }
          if (request.url.path == '/api/csrf-token') {
            csrf++;
            entered.complete();
            await release.future;
            return reply(headers: {'set-cookie': 'csrf_token=normal; Path=/'});
          }
          writes++;
          expect(request.headers['cookie'], contains('token=A'));
          expect(request.headers['cookie'], contains('csrf_token=normal'));
          expect(request.headers['cookie'], contains('lang=en'));
          expect(request.headers['x-csrf-token'], 'normal');
          return reply();
        }),
      );
      await client.login('reader', 'synthetic');
      final result = client.post('/api/bookmarks', {'title': 'normal'});
      await entered.future;
      client.language = 'en';
      release.complete();
      expect(await result, {'ok': true});
      expect(csrf, 1);
      expect(writes, 1);
      expect(client.exportSession(), {'token': 'A', 'csrf_token': 'normal'});
      client.close();
    },
  );
}
