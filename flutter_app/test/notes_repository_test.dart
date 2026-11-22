import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

http.Response response(String body, int code, {Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(body), code, headers: headers ?? {});

void main() {
  test(
    'clearing all labels uses the replacement endpoint, and partial creation preserves ID',
    () async {
      var clears = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.url.path == '/api/csrf-token') {
            return response(
              '{"code":0}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          if (r.url.path == '/api/labels/resource/blog/7') {
            expect(jsonDecode(r.body), {'labels': ''});
            clears++;
            return response('{"code":0,"data":null}', 200);
          }
          if (r.url.path == '/api/blogs' && r.method == 'POST') {
            return response('{"code":0,"data":{"blog_id":42}}', 200);
          }
          if (r.url.path == '/api/labels/resource/blog/42') {
            return response('{"code":403,"message":"labels failed"}', 403);
          }
          return response('{"code":0}', 200);
        }),
      );
      final repository = RemoteNotesRepository(client);
      await repository.save(
        const Note(id: 7, title: 'note', content: '', labels: []),
      );
      expect(clears, 1);
      await expectLater(
        repository.save(const Note(title: 'new', content: 'content')),
        throwsA(
          isA<NoteSaveFailure>().having(
            (error) => error.savedId,
            'savedId',
            42,
          ),
        ),
      );
    },
  );

  test('remote save preserves fetched labels and uses CSRF PUT', () async {
    final calls = <http.Request>[];
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((r) async {
        calls.add(r);
        if (r.url.path == '/api/labels/resource/blog/7') {
          return response('{"code":0,"data":["\u8bfb\u4e66"]}', 200);
        }
        if (r.url.path == '/api/blogs/7' && r.method == 'GET') {
          return response(
            '{"code":0,"data":{"blog_id":7,"blog_title":"\u539f\u6587","blog_content":"# \u5185\u5bb9","editor_type":"markdown"}}',
            200,
          );
        }
        if (r.url.path == '/api/csrf-token') {
          return response(
            '{"code":0}',
            200,
            headers: {'set-cookie': 'csrf_token=test; Path=/'},
          );
        }
        expect(r.method, 'PUT');
        expect(r.headers['x-csrf-token'], 'test');
        expect(jsonDecode(r.body)['labels'], '\u8bfb\u4e66');
        return response('{"code":0}', 200);
      }),
    );
    final repository = RemoteNotesRepository(client);
    final note = await repository.read(7);
    await repository.save(note.copyWith(content: '**\u66f4\u65b0**'));
    expect(
      calls
          .where((r) => r.method == 'PUT' && r.url.path == '/api/blogs/7')
          .length,
      1,
    );
    expect(calls.last.url.path, '/api/labels/resource/blog/7');
  });
  test('server null labels represent an unlabeled note', () async {
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient(
        (r) async => response(
          r.url.path.startsWith('/api/labels/')
              ? '{"code":0,"data":null}'
              : '{"code":0,"data":{"blog_id":1,"blog_content":"text","editor_type":"markdown"}}',
          200,
        ),
      ),
    );
    expect((await RemoteNotesRepository(client).read(1)).labels, isEmpty);
  });
  test(
    'protected or unsupported content cannot be opened as empty markdown',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => response(
            '{"code":0,"data":{"blog_id":1,"has_password":true,"blog_content":""}}',
            200,
          ),
        ),
      );
      expect(RemoteNotesRepository(client).read(1), throwsA(isA<NoteLocked>()));
    },
  );
}
