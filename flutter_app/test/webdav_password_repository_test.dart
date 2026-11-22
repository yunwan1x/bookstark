import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/webdav_password_repository.dart';
import 'profile_repository_test.dart' as fixture;

const generated = 'generated-fixture-app-password';
Map<String, Object?> profile({
  bool has = true,
  String endpoint = 'https://example.test/base/dav',
}) => {
  'built_in': true,
  'account': 'profile-fixture',
  'endpoint': endpoint,
  'has_app_password': has,
};
String xml({
  String href = '/base/dav/',
  String ns = 'DAV:',
  String status = 'HTTP/1.1 200 OK',
}) =>
    '<?xml version="1.0"?><d:multistatus xmlns:d="$ns"><d:response><d:href>$href</d:href><d:propstat><d:prop><d:displayname>root</d:displayname></d:prop><d:status>$status</d:status></d:propstat></d:response></d:multistatus>';
void main() {
  test(
    'random reset has truly empty body; custom reset preserves exact spaces and Unicode',
    () async {
      var posts = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.followRedirects, false);
          expect(r.headers['cache-control'], 'no-store');
          if (r.url.path == '/base/api/profile') {
            return fixture.data(fixture.profile());
          }
          if (r.method == 'GET') {
            return fixture.data(profile());
          }
          expect(r.method, 'POST');
          expect(r.url.path, '/base/api/webdav/app-password/reset');
          expect(r.headers['x-csrf-token'], 'csrf');
          posts++;
          if (posts == 1) {
            expect(r.bodyBytes, isEmpty);
            return fixture.data({'app_password': generated});
          }
          expect(jsonDecode(r.body), {'password': ' custom 密码 '});
          return fixture.data({'app_password': ' custom 密码 '});
        }),
      )..restoreSession({'token': 'owner-session', 'csrf_token': 'csrf'});
      final repo = RemoteWebdavPasswordRepository(client, memberId: 7);
      expect((await repo.read()).hasPassword, true);
      expect(await repo.reset(), generated);
      expect(await repo.reset(password: ' custom 密码 '), ' custom 密码 ');
      expect(posts, 2);
      repo.dispose();
      client.close();
    },
  );
  test(
    'actual same-origin depth0 PROPFIND uses Basic credentials and never owner cookies or returned foreign endpoint',
    () async {
      var probes = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          if (r.url.path == '/base/api/profile') {
            return fixture.data(fixture.profile());
          }
          if (r.method == 'GET') {
            return fixture.data(
              profile(endpoint: 'https://foreign.invalid/dav'),
            );
          }
          probes++;
          expect(r.method, 'PROPFIND');
          expect(r.url.toString(), 'https://example.test/base/dav');
          expect(r.followRedirects, false);
          expect(r.headers['cookie'], isNull);
          expect(r.headers['depth'], '0');
          expect(
            utf8.decode(base64Decode(r.headers['authorization']!.substring(6))),
            'profile-fixture: custom 密码 ',
          );
          expect(r.body, contains('<d:displayname/>'));
          return http.Response(
            xml(),
            207,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }),
      )..restoreSession({'token': 'owner-session', 'csrf_token': 'csrf'});
      final repo = RemoteWebdavPasswordRepository(client, memberId: 7);
      await repo.read();
      await repo.verify(' custom 密码 ');
      expect(probes, 1);
      repo.dispose();
      client.close();
    },
  );
  test(
    'actual XML namespace, root, status and declaration are strict',
    () async {
      for (final response in [
        xml(ns: 'foreign:'),
        xml(href: '/other'),
        xml(href: 'https://foreign.invalid/base/dav/'),
        xml(status: 'HTTP/1.1 404 Not Found'),
        '<!DOCTYPE x>${xml()}',
        '<d:multistatus xmlns:d="DAV:"/>',
      ]) {
        final client = BookstarkClient(
          'https://example.test/base',
          transport: MockClient(
            (r) async => r.method == 'GET'
                ? fixture.data(fixture.profile())
                : http.Response(
                    response,
                    207,
                    headers: {'content-type': 'application/xml'},
                  ),
          ),
        );
        final repo = RemoteWebdavPasswordRepository(client, memberId: 7);
        await expectLater(repo.verify(generated), throwsFormatException);
        repo.dispose();
        client.close();
      }
    },
  );
  test(
    'wrong owner prevents writes and actual revocation has only fixed DELETE receipt',
    () async {
      for (final wrong in [true, false]) {
        var writes = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((r) async {
            if (r.method == 'GET') {
              return fixture.data(fixture.profile(id: wrong ? 8 : 7));
            }
            writes++;
            expect(r.method, 'DELETE');
            expect(r.url.path, '/api/webdav/app-password');
            expect(r.bodyBytes, isEmpty);
            return http.Response(
              '{"code":0,"message":"revoked"}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
        final repo = RemoteWebdavPasswordRepository(client, memberId: 7);
        if (wrong) {
          await expectLater(
            repo.revoke(),
            throwsA(isA<WebdavPasswordPreflightFailure>()),
          );
          expect(writes, 0);
        } else {
          await repo.revoke();
          expect(writes, 1);
        }
        repo.dispose();
        client.close();
      }
    },
  );
  test(
    'app-password8–64 Unicode characters and72 UTF8 bytes exactly match current service bounds',
    () {
      for (final value in ['abcdefgh', ' abcdef ', '中' * 24, 'a' * 64]) {
        validateWebdavAppPassword(value);
      }
      for (final value in [
        'abcdefg',
        ' ' * 8,
        '中' * 25,
        'a' * 65,
        String.fromCharCode(0xd800),
      ]) {
        expect(() => validateWebdavAppPassword(value), throwsFormatException);
      }
    },
  );
}
