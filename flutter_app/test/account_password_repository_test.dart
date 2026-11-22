import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';
import 'package:bookstark_flutter/core/account_password_repository.dart';

const member = MemberProfile(
  id: 7,
  account: 'fixture-account',
  email: 'fixture@example.test',
  role: 1,
  defaultHome: 'home',
);
http.Response data(
  Map<String, Object?> value, {
  Map<String, String> headers = const {},
}) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': value})),
  200,
  headers: {'content-type': 'application/json', ...headers},
);
Map<String, Object?> profile({int id = 7}) => {
  'member_id': id,
  'account': 'fixture-account',
  'email': 'fixture@example.test',
  'role': 1,
  'default_home': 'home',
};
void main() {
  test(
    'account change uses bounded fixed owner endpoint, actual identity and raw spaces, never body password API',
    () async {
      final paths = <String>[];
      Map? body;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          paths.add('${r.method} ${r.url.path}');
          expect(r.followRedirects, isFalse);
          expect(r.url.hasQuery, isFalse);
          if (r.method == 'GET') {
            return data(profile());
          }
          body = jsonDecode(r.body) as Map;
          return http.Response(
            '{"code":0,"message":"changed"}',
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'token=changed-fixture; Path=/; HttpOnly',
            },
          );
        }),
      )..restoreSession({'token': 'old-fixture', 'csrf_token': 'csrf'});
      final repo = RemoteAccountPasswordRepository(
        client,
        member: member,
        saveSession: () async => true,
      );
      await repo.change(' old raw ', ' 新登录密码🙂 ');
      expect(paths, ['GET /base/api/profile', 'PUT /base/api/password']);
      expect(body, {'old_password': ' old raw ', 'new_password': ' 新登录密码🙂 '});
      expect(client.exportSession()['token'], 'changed-fixture');
      client.close();
    },
  );
  test(
    'verification uses isolated actual login then member GET, adopts returned cookie and persists separately',
    () async {
      var saves = 0;
      final seen = <String>[];
      final active = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((_) async => data(profile())),
      )..restoreSession({'token': 'old-fixture', 'csrf_token': 'csrf'});
      final repo = RemoteAccountPasswordRepository(
        active,
        member: member,
        saveSession: () async {
          saves++;
          return true;
        },
        verifierFactory: (server) => BookstarkClient(
          server,
          transport: MockClient((r) async {
            seen.add('${r.method} ${r.url.path}');
            expect(r.followRedirects, isFalse);
            expect(r.url.hasQuery, isFalse);
            if (r.url.path.endsWith('/login')) {
              expect(jsonDecode(r.body), {
                'account': 'fixture-account',
                'password': ' raw new ',
              });
              expect(r.headers.containsKey('x-csrf-token'), isFalse);
              return data(
                {
                  'member': {'member_id': 7},
                },
                headers: {
                  'set-cookie': 'token=verified-fixture; Path=/; HttpOnly',
                },
              );
            }
            expect(r.headers['cookie'], contains('token=verified-fixture'));
            return data(profile());
          }),
        ),
      );
      await repo.verifyAndAdopt(' raw new ');
      expect(seen, ['POST /base/api/login', 'GET /base/api/profile']);
      expect(active.exportSession()['token'], 'verified-fixture');
      expect(saves, 0);
      expect(await repo.persistSession(), isTrue);
      expect(saves, 1);
      active.close();
    },
  );
  test(
    'foreign verified member and missing login cookie never replace current session',
    () async {
      for (final missingCookie in [false, true]) {
        final active = BookstarkClient(
          'https://example.test',
          transport: MockClient((_) async => data(profile())),
        )..restoreSession({'token': 'old-fixture'});
        final repo = RemoteAccountPasswordRepository(
          active,
          member: member,
          saveSession: () async => true,
          verifierFactory: (server) => BookstarkClient(
            server,
            transport: MockClient(
              (r) async => r.url.path.endsWith('/login')
                  ? data(
                      {},
                      headers: missingCookie
                          ? {}
                          : {'set-cookie': 'token=foreign-fixture; HttpOnly'},
                    )
                  : data(profile(id: 8)),
            ),
          ),
        );
        await expectLater(
          repo.verifyAndAdopt('new-pass'),
          throwsFormatException,
        );
        expect(active.exportSession()['token'], 'old-fixture');
        active.close();
      }
    },
  );
  test(
    'failed preflight and foreign verification origin do not issue password writes or logins',
    () async {
      var puts = 0, foreignCalls = 0;
      final active = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.method == 'PUT') {
            puts++;
          }
          return data(profile(id: 8));
        }),
      )..restoreSession({'token': 'old-fixture', 'csrf_token': 'csrf'});
      final repo = RemoteAccountPasswordRepository(
        active,
        member: member,
        saveSession: () async => true,
        verifierFactory: (_) => BookstarkClient(
          'https://foreign.test',
          transport: MockClient((_) async {
            foreignCalls++;
            return data({});
          }),
        ),
      );
      await expectLater(
        repo.change('current', 'new-pass'),
        throwsA(isA<AccountPasswordPreflightFailure>()),
      );
      expect(puts, 0);
      await expectLater(repo.verifyAndAdopt('new-pass'), throwsStateError);
      expect(foreignCalls, 0);
      expect(active.exportSession()['token'], 'old-fixture');
      active.close();
    },
  );
  test(
    'malformed change receipt stays unconfirmed even when HTTP200',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => r.method == 'GET' ? data(profile()) : data({}),
        ),
      )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
      await expectLater(
        RemoteAccountPasswordRepository(
          client,
          member: member,
          saveSession: () async => true,
        ).change('current', 'new-pass'),
        throwsFormatException,
      );
      client.close();
    },
  );
  test(
    'new password bounds match six Unicode runes and72 UTF8 bytes; all raw spaces preserved',
    () {
      for (final password in ['      ', '中' * 24, '🙂' * 18]) {
        validateLoginPassword(password, newPassword: true);
      }
      validateLoginPassword('x');
      for (final password in [
        '12345',
        '中' * 25,
        '🙂' * 19,
        String.fromCharCode(0xd800),
      ]) {
        expect(
          () => validateLoginPassword(password, newPassword: true),
          throwsFormatException,
        );
      }
    },
  );
}
