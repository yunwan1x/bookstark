import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/api_tokens_repository.dart';
import 'profile_repository_test.dart' as fixture;

const secret =
    '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
Map<String, Object?> entry({
  int id = 1,
  int owner = 7,
  String name = 'fixture',
}) => {
  'token_id': id,
  'member_id': owner,
  'name': name,
  'masked_token': maskApiToken(secret),
  'create_time': '2026-11-05T07:00:00Z',
};
http.Response list(List<Object?> rows) => http.Response(
  jsonEncode({'code': 0, 'data': rows}),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test(
    'fixed owner list, nested one-time create receipt and known ID DELETE have actual fields only',
    () async {
      var writes = 0, deletes = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.followRedirects, false);
          expect(r.headers['cache-control'], 'no-store');
          if (r.url.path == '/base/api/profile') {
            return fixture.data(fixture.profile());
          }
          if (r.method == 'GET') {
            expect(r.url.path, '/base/api/api-tokens');
            return list([entry()]);
          }
          expect(r.headers['x-csrf-token'], 'csrf');
          if (r.method == 'POST') {
            writes++;
            expect(jsonDecode(r.body), {'name': ' new 名称 '});
            return fixture.data({
              'data': entry(id: 2, name: ' new 名称 '),
              'token': secret,
            });
          }
          deletes++;
          expect(r.method, 'DELETE');
          expect(r.url.path, '/base/api/api-tokens/2');
          return http.Response(
            '{"code":0,"message":"revoked"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..restoreSession({'token': 'owner', 'csrf_token': 'csrf'});
      final repo = RemoteApiTokensRepository(client, memberId: 7);
      expect((await repo.read()).entries.single.name, 'fixture');
      final created = await repo.create(' new 名称 ');
      expect(created.entry.id, 2);
      expect(created.secret, secret);
      expect(created.toString(), isNot(contains(secret)));
      await repo.revoke(created.entry);
      expect([writes, deletes], [1, 1]);
      repo.dispose();
      client.close();
    },
  );
  test(
    'wrong owner metadata, unordered, duplicate and oversized lists are rejected',
    () async {
      for (final rows in [
        [entry(owner: 8)],
        [entry(id: 2), entry(id: 1)],
        [entry(), entry()],
        List.generate(101, (i) => entry(id: i + 1)),
      ]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient(
            (r) async => r.url.path == '/api/profile'
                ? fixture.data(fixture.profile())
                : list(rows),
          ),
        );
        final repo = RemoteApiTokensRepository(client, memberId: 7);
        await expectLater(repo.read(), throwsFormatException);
        repo.dispose();
        client.close();
      }
    },
  );
  test('unknown IDs and changed metadata cannot issue a revocation', () async {
    var deletes = 0;
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((r) async {
        if (r.method == 'DELETE') {
          deletes++;
        }
        return r.url.path == '/api/profile'
            ? fixture.data(fixture.profile())
            : list([entry()]);
      }),
    );
    final repo = RemoteApiTokensRepository(client, memberId: 7);
    await repo.read();
    for (final row in [entry(id: 3), entry(name: 'forged')]) {
      await expectLater(
        repo.revoke(ApiTokenEntry.fromJson(row, 7)),
        throwsA(isA<ApiTokenPreflightFailure>()),
      );
    }
    expect(deletes, 0);
    repo.dispose();
    client.close();
  });
  test(
    'create receipt requires exact requested name, own metadata and matching mask',
    () async {
      for (final mode in [0, 1, 2, 3]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((r) async {
            if (r.method == 'GET') {
              return fixture.data(fixture.profile());
            }
            return fixture.data({
              'data':
                  entry(
                      owner: mode == 0 ? 8 : 7,
                      name: mode == 1 ? 'wrong' : 'fixture',
                    )
                    ..['masked_token'] = mode == 2
                        ? 'abcd****0000'
                        : maskApiToken(secret),
              'token': mode == 3 ? 'not-a-real-secret' : secret,
            });
          }),
        )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
        final repo = RemoteApiTokensRepository(client, memberId: 7);
        await expectLater(repo.create('fixture'), throwsFormatException);
        repo.dispose();
        client.close();
      }
    },
  );
  test(
    'capped ascending list does not pretend IDs above returned range were revoked',
    () {
      final page = ApiTokensPage(
        List.generate(100, (i) => ApiTokenEntry.fromJson(entry(id: i + 2), 7)),
      );
      expect(page.truncated, true);
      expect(page.provesAbsent(1), true);
      expect(page.provesAbsent(50), false);
      expect(page.provesAbsent(102), false);
      expect(ApiTokensPage([]).provesAbsent(102), true);
    },
  );
  test(
    'name limit counts100 UTF8 bytes, preserves raw spaces and rejects malformed Unicode',
    () {
      validateApiTokenName('');
      validateApiTokenName(' raw name ');
      validateApiTokenName('中' * 33);
      validateApiTokenName('a' * 100);
      for (final bad in ['中' * 34, 'a' * 101, String.fromCharCode(0xd800)]) {
        expect(() => validateApiTokenName(bad), throwsFormatException);
      }
    },
  );
}
