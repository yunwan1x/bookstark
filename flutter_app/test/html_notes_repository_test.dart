import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> metadata() => {
  'blog_id': 7,
  'member_id': 3,
  'blog_type': 'note',
  'editor_type': 'html',
  'blog_title': 'HTML 原文',
  'blog_content': '',
  'version': 4,
  'modify_at': 1234,
  'has_password': false,
};

http.Response jsonResponse(Object? data) => http.Response(
  jsonEncode({'code': 0, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  Fixture() {
    client = BookstarkClient(
      'https://books.example/mount',
      transport: MockClient(handle),
    )..restoreSession({'token': 'session'});
    repo = RemoteHtmlNotesRepository(client, memberId: 3);
  }
  late BookstarkClient client;
  late RemoteHtmlNotesRepository repo;
  final seen = <http.Request>[];
  Map<String, Object?> row = metadata();
  var metadataReads = 0;
  var labelReads = 0;
  bool changeVersion = false, changeLabels = false, nullLabels = false;
  Future<http.Response> handle(http.Request request) async {
    seen.add(request);
    expect(request.url.origin, 'https://books.example');
    expect(request.headers['cookie'], contains('token=session'));
    final path = request.url.path;
    if (path == '/mount/api/profile') return jsonResponse({'member_id': 3});
    if (path == '/mount/api/csrf-token') {
      return http.Response(
        '{}',
        200,
        headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
      );
    }
    if (path == '/mount/api/blogs/7') {
      metadataReads++;
      return jsonResponse({
        ...row,
        if (changeVersion && metadataReads > 1) 'version': 5,
        // This untrusted field must never determine the authenticated URL.
        'content_url': 'https://elsewhere.example/private',
      });
    }
    if (path == '/mount/api/labels/resource/blog/7') {
      labelReads++;
      if (nullLabels) return jsonResponse(null);
      return jsonResponse([changeLabels && labelReads > 1 ? 'changed' : '读书']);
    }
    if (path == '/mount/api/blogs/7/content/raw' ||
        path == '/mount/api/blogs/7/verify-password/raw') {
      if (row['has_password'] == true) {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'password': ' raw password '});
      }
      return http.Response.bytes(
        utf8.encode('<h1>你好</h1><script>run()</script>'),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    throw StateError('Unexpected HTML fixture endpoint');
  }

  void close() {
    repo.dispose();
    client.close();
  }
}

void main() {
  test(
    'owner read retains full HTML and ignores foreign metadata source URL',
    () async {
      final f = Fixture();
      final note = await f.repo.read(7);
      expect(note.source, '<h1>你好</h1><script>run()</script>');
      expect(note.metadata.id, 7);
      expect(note.metadata.version, 4);
      expect(note.labels, ['读书']);
      expect(note.unlockPassword, isNull);
      expect(f.metadataReads, 2);
      expect(f.labelReads, 2);
      expect(() => note.labels.add('mutate'), throwsUnsupportedError);
      f.close();
    },
  );

  test('Go null labels are an explicit successful empty list', () async {
    final f = Fixture()..nullLabels = true;
    final note = await f.repo.read(7);
    expect(note.labels, isEmpty);
    f.close();
  });

  test(
    'foreign owner, format, collection and invalid version fail before raw read',
    () async {
      for (final patch in <Map<String, Object?>>[
        {'member_id': 4},
        {'editor_type': 'markdown'},
        {'blog_type': 'article'},
        {'version': -1},
        {'has_password': 'false'},
        {'blog_id': 8},
      ]) {
        final f = Fixture()..row.addAll(patch);
        await expectLater(f.repo.read(7), throwsFormatException);
        expect(f.seen.length, 2);
        f.close();
      }
    },
  );

  test(
    'protected metadata asks for explicit unlock before fetching body',
    () async {
      final f = Fixture()..row['has_password'] = true;
      await expectLater(f.repo.read(7), throwsA(isA<HtmlNoteLocked>()));
      expect(f.seen.length, 2);
      final note = await f.repo.read(7, password: ' raw password ');
      expect(note.unlockPassword, ' raw password ');
      expect(note.metadata.protected, isTrue);
      f.close();
    },
  );

  test(
    'changed version or independently changed labels rejects mixed baseline',
    () async {
      for (final version in [true, false]) {
        final f = Fixture();
        f.changeVersion = version;
        f.changeLabels = !version;
        await expectLater(f.repo.read(7), throwsA(isA<HtmlNoteChanged>()));
        f.close();
      }
    },
  );

  test(
    'disposal or session change while profile waits prevents later source access',
    () async {
      for (final dispose in [true, false]) {
        final pending = Completer<http.Response>();
        var calls = 0;
        final requests = <http.Request>[];
        final client = BookstarkClient(
          'https://books.example',
          transport: MockClient((request) {
            requests.add(request);
            calls++;
            return pending.future;
          }),
        )..restoreSession({'token': 'session'});
        final repo = RemoteHtmlNotesRepository(client, memberId: 3);
        final read = repo.read(7);
        final failure = expectLater(
          read,
          dispose
              ? throwsA(
                  isA<ApiFailure>().having(
                    (e) => e.status,
                    'explicit owner abort',
                    499,
                  ),
                )
              : throwsA(
                  isA<StateError>().having(
                    (e) => e.message,
                    'post-await owner guard',
                    'HTML owner session ended',
                  ),
                ),
        );
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          repo.dispose();
        } else {
          client.restoreSession({'token': 'another'});
        }
        pending.complete(jsonResponse({'member_id': 3}));
        await failure;
        // Only the already-started profile GET was allowed. No resource-body,
        // labels, or write request may begin after owner retirement.
        await Future<void>.delayed(Duration.zero);
        expect(calls, 1);
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/profile');
        expect(requests.single.bodyBytes, isEmpty);
        expect(
          client.exportSession()['token'],
          dispose ? 'session' : 'another',
        );
        repo.dispose();
        client.close();
      }
    },
  );

  test('invalid ID or malformed password performs no request', () async {
    final f = Fixture();
    await expectLater(f.repo.read(0), throwsFormatException);
    await expectLater(
      f.repo.read(7, password: String.fromCharCode(0xd800)),
      throwsFormatException,
    );
    expect(f.seen, isEmpty);
    f.close();
  });
}
