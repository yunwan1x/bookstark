import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

void main() {
  test(
    'unlock only POSTs password; subsequent save preserves encryption with password field',
    () async {
      final calls = <http.Request>[];
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls.add(r);
          Object data = {};
          if (r.method == 'GET' && r.url.path == '/api/blogs/7') {
            data = {
              'blog_id': 7,
              'blog_title': 'private',
              'blog_content': '',
              'editor_type': 'markdown',
              'has_password': true,
            };
          }
          if (r.url.path.startsWith('/api/labels/')) data = ['private'];
          if (r.url.path.endsWith('/verify-password')) {
            expect(r.method, 'POST');
            expect(jsonDecode(r.body), {'password': 'correct'});
            data = {'blog_content': 'decrypted'};
          }
          if (r.method == 'PUT' && r.url.path == '/api/blogs/7') {
            final body = jsonDecode(r.body);
            expect(body['password'], 'correct');
            expect(body.containsKey('current_password'), isFalse);
            expect(body.containsKey('new_password'), isFalse);
            expect(body['blog_content'], 'updated');
          }
          return http.Response(
            jsonEncode({'code': 0, 'data': data}),
            200,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              if (r.url.path == '/api/csrf-token')
                'set-cookie': 'csrf_token=x; Path=/',
            },
          );
        }),
      );
      final repository = RemoteNotesRepository(client);
      await expectLater(repository.read(7), throwsA(isA<NoteLocked>()));
      final note = await repository.unlock(7, 'correct');
      expect(note.content, 'decrypted');
      expect(note.isProtected, isTrue);
      await repository.save(note.copyWith(content: 'updated'));
      expect(calls.every((r) => !r.url.toString().contains('correct')), isTrue);
    },
  );
  test('wrong password cannot produce an editable note or PUT', () async {
    var puts = 0;
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((r) async {
        if (r.method == 'PUT') puts++;
        if (r.url.path.endsWith('/verify-password')) {
          return http.Response('{"code":400,"message":"incorrect"}', 400);
        }
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'blog_id': 1,
              'editor_type': 'markdown',
              'has_password': true,
            },
          }),
          200,
          headers: {'set-cookie': 'csrf_token=x'},
        );
      }),
    );
    await expectLater(
      RemoteNotesRepository(client).unlock(1, 'wrong'),
      throwsA(isA<ApiFailure>()),
    );
    expect(puts, 0);
  });
}
