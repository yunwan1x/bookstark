import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';

http.Response reply(Map<String, Object?> data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': data})),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test(
    'metadata uses actual owner identity and never guesses protection from preview',
    () async {
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/base/api/blogs/7');
          expect(r.followRedirects, isFalse);
          return reply({
            'blog_id': 7,
            'blog_title': '实际标题',
            'blog_type': 'note',
            'editor_type': 'markdown',
            'has_password': true,
            'blog_content': 'untrusted leaked content',
          });
        }),
      );
      final actual = await RemoteContentPasswordRepository(client).read(7);
      expect(actual.id, 7);
      expect(actual.title, '实际标题');
      expect(actual.protected, isTrue);
      client.close();
    },
  );
  test(
    'set change remove and verify keep raw spaces and never PUT a stale body',
    () async {
      final bodies = <Map>[];
      final methods = <String>[];
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          methods.add('${r.method} ${r.url.path}');
          expect(r.url.hasQuery, isFalse);
          expect(r.headers['cache-control'], 'no-store');
          bodies.add(jsonDecode(r.body) as Map);
          return reply(
            r.method == 'POST'
                ? {'blog_content': 'sensitive decrypted body'}
                : {},
          );
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteContentPasswordRepository(client);
      const initial = ContentProtection(id: 7, title: 'note', protected: false),
          locked = ContentProtection(id: 7, title: 'note', protected: true);
      await repo.change(initial, newPassword: ' 新 密码 ');
      await repo.change(
        locked,
        newPassword: ' replaced ',
        currentPassword: ' 新 密码 ',
      );
      await repo.verify(7, ' replaced ');
      await repo.change(locked, newPassword: '', currentPassword: ' replaced ');
      expect(methods, [
        'PUT /api/blogs/7',
        'PUT /api/blogs/7',
        'POST /api/blogs/7/verify-password',
        'PUT /api/blogs/7',
      ]);
      expect(bodies, [
        {'new_password': ' 新 密码 '},
        {'new_password': ' replaced ', 'current_password': ' 新 密码 '},
        {'password': ' replaced '},
        {'new_password': '', 'current_password': ' replaced '},
      ]);
      client.close();
    },
  );
  test(
    'reject wrong membership, non Markdown and missing protection boolean',
    () async {
      var attempt = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          attempt++;
          return reply({
            'blog_id': attempt == 1 ? 8 : 7,
            'blog_title': 'x',
            'blog_type': 'note',
            'editor_type': attempt == 2 ? 'richdoc' : 'markdown',
            if (attempt < 3) 'has_password': false,
          });
        }),
      );
      final repo = RemoteContentPasswordRepository(client);
      for (var i = 0; i < 3; i++) {
        await expectLater(repo.read(7), throwsFormatException);
      }
      client.close();
    },
  );
  test(
    'local password validation preserves spaces but rejects malformed Unicode and unsafe mutations before request',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          writes++;
          return reply({});
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteContentPasswordRepository(client);
      validateContentPassword('   ');
      validateContentPassword('中文🙂');
      for (final value in ['', String.fromCharCode(0xd800), '中' * 342]) {
        expect(() => validateContentPassword(value), throwsFormatException);
      }
      await expectLater(
        repo.change(
          const ContentProtection(id: 7, title: 'x', protected: false),
          newPassword: '',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.change(
          const ContentProtection(id: 7, title: 'x', protected: true),
          newPassword: 'next',
        ),
        throwsStateError,
      );
      expect(writes, 0);
      client.close();
    },
  );
}
