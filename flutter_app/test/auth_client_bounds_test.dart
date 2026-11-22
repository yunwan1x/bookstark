import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response csrf() => http.Response(
  '{"code":0,"data":{}}',
  200,
  headers: {
    'set-cookie': 'csrf_token=nonce; Path=/',
    'content-type': 'application/json; charset=utf-8',
  },
);
http.Response success() => http.Response(
  '{"code":0,"message":"注册成功，请等待管理员审批"}',
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('auth preserves prefix, CSRF cookie and configuration result', () async {
    final paths = <String>[];
    final client = BookstarkClient(
      'https://books.example/team',
      transport: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.followRedirects, false);
        expect(request.headers['cache-control'], 'no-store');
        if (request.url.path.endsWith('/register-config')) {
          return http.Response(
            '{"code":0,"data":{"invite_code_enabled":true}}',
            200,
          );
        }
        if (request.url.path.endsWith('/csrf-token')) return csrf();
        expect(request.url.path, '/team/api/register');
        expect(request.headers['cookie'], contains('csrf_token=nonce'));
        expect(request.headers['x-csrf-token'], 'nonce');
        return success();
      }),
    );
    addTearDown(client.close);
    expect(
      (await client.accountFormConfiguration())['invite_code_enabled'],
      true,
    );
    var submitted = 0;
    final result = await client.submitAccountForm('/api/register', {
      'account': 'reader',
    }, onSubmitted: () => submitted++);
    expect(result['message'], '注册成功，请等待管理员审批');
    expect(submitted, 1);
    expect(paths, [
      '/team/api/register-config',
      '/team/api/csrf-token',
      '/team/api/register',
    ]);
  });

  test('unsupported account path is refused before any HTTP', () async {
    var requests = 0;
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((_) async {
        requests++;
        return success();
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.submitAccountForm('/api/admin/settings', {}),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test('missing CSRF cookie cannot mark a form submitted', () async {
    var requests = 0, submitted = 0;
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((_) async {
        requests++;
        return http.Response('{"code":0,"data":{}}', 200);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.submitAccountForm('/api/password/reset', {
        'token': 'example',
      }, onSubmitted: () => submitted++),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)),
    );
    expect(requests, 1);
    expect(submitted, 0);
  });

  test('oversized form body is refused before submission', () async {
    var posts = 0, submitted = 0;
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((request) async {
        if (request.method == 'GET') return csrf();
        posts++;
        return success();
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.submitAccountForm('/api/password/reset', {
        'token': 'x' * 16385,
      }, onSubmitted: () => submitted++),
      throwsFormatException,
    );
    expect(posts, 0);
    expect(submitted, 0);
  });

  test(
    'oversized authentication response is not an HTTP rejection receipt',
    () async {
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((_) async => http.Response('x' * 65537, 200)),
      );
      addTearDown(client.close);
      await expectLater(
        client.login('reader', 'fixture-password'),
        throwsFormatException,
      );
    },
  );

  test('exact 64KiB valid authentication response remains supported', () async {
    final envelope = {
      'code': 0,
      'data': {
        'member': {'member_id': 1},
        'padding': '',
      },
    };
    final original = jsonEncode(envelope);
    (envelope['data'] as Map<String, Object>)['padding'] =
        'x' * (65536 - utf8.encode(original).length);
    final body = jsonEncode(envelope);
    expect(utf8.encode(body).length, 65536);
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((_) async => http.Response(body, 200)),
    );
    addTearDown(client.close);
    expect((await client.login('reader', 'fixture-password'))['member'], {
      'member_id': 1,
    });
  });

  testWidgets(
    'CSRF deadline does not submit and late reply cannot populate retired cookies',
    (tester) async {
      final pending = Completer<http.Response>();
      var gets = 0, posts = 0, submitted = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((request) async {
          if (request.method == 'GET') {
            gets++;
            if (gets == 1) return pending.future;
            return csrf();
          }
          posts++;
          return success();
        }),
      );
      addTearDown(client.close);
      final failed = expectLater(
        client.submitAccountForm(
          '/api/register',
          {},
          onSubmitted: () => submitted++,
        ),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await failed;
      expect(submitted, 0);
      expect(posts, 0);
      pending.complete(csrf());
      await tester.pump();
      await client.submitAccountForm(
        '/api/register',
        {},
        onSubmitted: () => submitted++,
      );
      expect(
        gets,
        2,
        reason:
            'Late CSRF response must not update a retired request cookie jar',
      );
      expect(posts, 1);
      expect(submitted, 1);
    },
  );

  testWidgets('post deadline records one submission and never retries', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var posts = 0, submitted = 0;
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((request) async {
        if (request.method == 'GET') return csrf();
        posts++;
        return pending.future;
      }),
    );
    addTearDown(client.close);
    final failed = expectLater(
      client.submitAccountForm('/api/password/reset', {
        'token': 'example',
      }, onSubmitted: () => submitted++),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    expect(submitted, 1);
    expect(posts, 1);
    await tester.pump(const Duration(seconds: 16));
    await failed;
    expect(submitted, 1);
    expect(posts, 1);
    pending.complete(success());
    await tester.pump();
    expect(posts, 1);
  });
}
