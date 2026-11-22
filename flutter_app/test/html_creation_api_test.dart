import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const source = '<!doctype html>\r\n<p>中文</p>\n<script>window.x=1</script>';
  Map<String, dynamic> row() => {
    'blog_id': 71,
    'member_id': 3,
    'blog_type': 'note',
    'editor_type': 'html',
    'blog_title': '新建 HTML',
  };
  BookstarkClient client(Future<http.Response> Function(http.Request) post) =>
      BookstarkClient(
        'https://books.example/mount',
        transport: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], contains('token=session'));
          if (request.url.path == '/mount/api/csrf-token') {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
            );
          }
          expect(
            request.url.toString(),
            'https://books.example/mount/api/blogs',
          );
          expect(request.method, 'POST');
          expect(request.headers['x-csrf-token'], 'csrf');
          return post(request);
        }),
      )..restoreSession({'token': 'session'});
  Future<int> create(BookstarkClient api, {void Function()? submitted}) =>
      api.createHtmlNote(
        memberId: 3,
        collection: 'note',
        title: '新建 HTML',
        source: source,
        labels: '标签,second',
        onSubmit: submitted,
      );

  test(
    'full Blog echo above 128KiB preserves exact request and accepts owned receipt',
    () async {
      var calls = 0, submissions = 0;
      final api = client((request) async {
        calls++;
        expect(jsonDecode(request.body), {
          'blog_title': '新建 HTML',
          'blog_content': source,
          'blog_type': 'note',
          'editor_type': 'html',
          'labels': '标签,second',
          'visibility': 0,
        });
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {...row(), 'blog_content': List.filled(150000, 'x').join()},
          }),
          200,
          headers: {'content-type': 'application/json; charset="utf-8"'},
        );
      });
      expect(await create(api, submitted: () => submissions++), 71);
      expect(calls, 1);
      expect(submissions, 1);
      api.close();
    },
  );

  for (final field in [
    'blog_id',
    'member_id',
    'blog_type',
    'editor_type',
    'blog_title',
  ]) {
    test(
      'mismatched $field never becomes a creation receipt or retries',
      () async {
        var calls = 0;
        final api = client((request) async {
          calls++;
          final data = row();
          data[field] = field == 'blog_id'
              ? 0
              : field == 'member_id'
              ? 4
              : 'different';
          return http.Response(
            jsonEncode({'code': 0, 'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        await expectLater(create(api), throwsFormatException);
        expect(calls, 1);
        api.close();
      },
    );
  }
  test(
    'missing success code and non UTF8 JSON cannot fabricate a receipt',
    () async {
      for (final media in [
        'application/json',
        'application/json; charset=latin1',
        'text/html',
      ]) {
        final api = client(
          (request) async => http.Response.bytes(
            utf8.encode(jsonEncode({'data': row()})),
            200,
            headers: {'content-type': media},
          ),
        );
        await expectLater(create(api), throwsFormatException);
        api.close();
      }
    },
  );
  test(
    'invalid creation input fails before csrf lookup or submission',
    () async {
      var requests = 0, submissions = 0;
      final api = BookstarkClient(
        'https://books.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('No request permitted');
        }),
      );
      await expectLater(
        api.createHtmlNote(
          memberId: 3,
          collection: 'note',
          title: ' ',
          source: source,
          onSubmit: () => submissions++,
        ),
        throwsFormatException,
      );
      expect(requests, 0);
      expect(submissions, 0);
      api.close();
    },
  );
  test(
    'oversized successful POST receipt remains unknown and is not retried',
    () async {
      var calls = 0;
      final api = client((request) async {
        calls++;
        return http.Response.bytes(
          List.filled(8 * 1024 * 1024 + 1, 32),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await expectLater(create(api), throwsFormatException);
      expect(calls, 1);
      api.close();
    },
  );
  test('csrf lookup failure never reports submission or sends POST', () async {
    var calls = 0, submissions = 0;
    final api = BookstarkClient(
      'https://books.example',
      transport: MockClient((request) async {
        calls++;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/csrf-token');
        return http.Response(
          '{}',
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await expectLater(
      create(api, submitted: () => submissions++),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 1);
    expect(submissions, 0);
    api.close();
  });
}
