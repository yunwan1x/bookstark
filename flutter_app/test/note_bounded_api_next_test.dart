import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const body = <String, Object?>{
    'blog_type': 'note',
    'editor_type': 'markdown',
    'visibility': 0,
    'blog_title': 'Draft',
    'blog_content': '# Original',
  };
  http.Response ok(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  test('create callback follows csrf and precedes exactly one POST', () async {
    final events = <String>[];
    final api = BookstarkClient(
      'https://example.test/mount',
      transport: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['cookie'], contains('token=session'));
        if (request.url.path.endsWith('/csrf-token')) {
          events.add('csrf');
          return http.Response(
            '{}',
            200,
            headers: {'set-cookie': 'csrf_token=c; Path=/'},
          );
        }
        events.add('POST');
        expect(request.url.path, '/mount/api/blogs');
        expect(request.headers['x-csrf-token'], 'c');
        expect(jsonDecode(request.body), body);
        return ok({'blog_id': 7});
      }),
    )..restoreSession({'token': 'session'});
    final result = await api.createMarkdownNoteJson(
      body,
      onSubmit: () => events.add('submit'),
    );
    expect(events, ['csrf', 'submit', 'POST']);
    expect(result['data'], {'blog_id': 7});
    api.close();
  });
  test('csrf failure never crosses submission boundary', () async {
    var submits = 0;
    final api = BookstarkClient(
      'https://example.test',
      transport: MockClient((_) async => http.Response('{}', 403)),
    );
    await expectLater(
      api.createMarkdownNoteJson(body, onSubmit: () => submits++),
      throwsA(anything),
    );
    expect(submits, 0);
    api.close();
  });
  test('full source stays full and envelope stays wrapped', () async {
    final api = BookstarkClient(
      'https://example.test',
      transport: MockClient(
        (r) async => ok({'blog_id': 7, 'blog_content': '# Original'}),
      ),
    );
    final result = await api.boundedOwnedMarkdownJson(7);
    expect((result['data'] as Map)['blog_content'], '# Original');
    api.close();
  });
  test('list projects content without full body in result', () async {
    final api = BookstarkClient(
      'https://example.test',
      transport: MockClient(
        (r) async => ok([
          {
            'blog_id': 7,
            'blog_content': 'private full body',
            'content_preview': 'preview',
          },
        ]),
      ),
    );
    final result = await api.noteListPageMetadata(
      '/api/blogs?type=note&page=1',
    );
    expect(((result['data'] as List).single as Map)['blog_content'], isNull);
    api.close();
  });
  test('redirect and non-JSON source replies fail closed', () async {
    for (final status in [200, 302]) {
      final api = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          expect(r.followRedirects, isFalse);
          return http.Response(
            '{"code":0,"data":{}}',
            status,
            headers: {
              'content-type': 'text/html',
              'location': 'https://elsewhere.test',
            },
          );
        }),
      );
      await expectLater(api.boundedOwnedMarkdownJson(7), throwsA(anything));
      api.close();
    }
  });
  test('invalid list endpoint fails before transport', () async {
    var sends = 0;
    final api = BookstarkClient(
      'https://example.test',
      transport: MockClient((_) async {
        sends++;
        return ok([]);
      }),
    );
    expect(
      () => api.noteListPageMetadata('https://elsewhere.test/api/blogs'),
      throwsFormatException,
    );
    expect(sends, 0);
    api.close();
  });
}
