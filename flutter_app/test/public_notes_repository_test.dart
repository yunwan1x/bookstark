import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_notes_repository.dart';

final server = Uri.parse('https://example.test/base');
Map<String, Object?> note({
  int id = 7,
  String identify = 'literal%2F+',
  bool locked = false,
}) => {
  'blog_id': id,
  'blog_identify': identify,
  'blog_title': 'Actual public title',
  'blog_type': 'note',
  'editor_type': 'markdown',
  'visibility': 1,
  'has_password': locked,
  'is_pinned': 0,
  'modify_time': '2026-11-05T10:20:30Z',
  'content_preview': 'Actual preview',
  'labels': ['阅读', '标签,整体'],
};
String source(Object? rows) =>
    '<div id="publicTimeline"></div><script>var blogs = ${jsonEncode(rows)};\nvar container = document.getElementById(\'publicTimeline\');</script>';
void main() {
  test(
    'parse actual inert template, escaped script markers and raw identifiers without guessing complete body',
    () {
      final row = note()
        ..['content_preview'] =
            'quoted " }; var container = text; [()] <img src=x>'
        ..['editor_type'] = 'unknown-format';
      final data = parsePublicNotes(source([row]), server: server, page: 3);
      expect(data.page, 3);
      expect(data.items.single.preview, row['content_preview']);
      expect(data.items.single.format, 'unknown-format');
      expect(
        data.items.single.reference.canonicalUri.toString(),
        'https://example.test/base/shares/literal%252F%2B',
      );
      expect(data.items.single.labels, ['阅读', '标签,整体']);
      expect(data.labels, {'阅读', '标签,整体'});
    },
  );
  test(
    'locked legacy leaks are discarded even when malformed; position is never retained',
    () {
      final row = note(locked: true)
        ..['content_preview'] = {'malformed': 'secret'}
        ..['labels'] = {'malformed': 'leaked'}
        ..['blog_desc'] = 'secret'
        ..['latitude'] = 123;
      final item = parsePublicNotes(
        source([row]),
        server: server,
        page: 1,
      ).items.single;
      expect(item.locked, isTrue);
      expect(item.preview, isEmpty);
      expect(item.labels, isEmpty);
      expect(item.title, 'Actual public title');
    },
  );
  test(
    'reject duplicate identities, private/article mixing, invalid protection and ambiguous scripts',
    () {
      for (final rows in [
        [note(), note(id: 8)],
        [note(), note(identify: 'other')],
        [note()..['visibility'] = 0],
        [note()..['blog_type'] = 'article'],
        [note()..['has_password'] = 'false'],
        [note()..['blog_identify'] = '../private'],
      ]) {
        expect(
          () => parsePublicNotes(source(rows), server: server, page: 1),
          throwsFormatException,
        );
      }
      expect(
        () =>
            parsePublicNotes(source([]) + source([]), server: server, page: 1),
        throwsFormatException,
      );
      expect(
        () => parsePublicNotes(
          source(
            [],
          ).replaceFirst(';\nvar container', ';execute();\nvar container'),
          server: server,
          page: 1,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'null data is a legitimate empty page and never fabricates totals or next records',
    () {
      final data = parsePublicNotes(source(null), server: server, page: 2);
      expect(data.items, isEmpty);
      expect(data.canRequestNext, isFalse);
      expect(data.page, 2);
    },
  );
  test(
    'real request fixes same origin public path, explicit server-supported page size, and never owner APIs',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        server.toString(),
        transport: MockClient((r) async {
          calls++;
          expect(r.method, 'GET');
          expect(r.url.path, '/base/notes/public');
          expect(r.url.queryParameters, {'page': '4', 'page_size': '20'});
          expect(r.followRedirects, isFalse);
          return http.Response.bytes(
            utf8.encode(source([note()])),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      final page = await RemotePublicNotesRepository(client).load(4);
      expect(page.page, 4);
      expect(page.items.single.id, 7);
      await expectLater(
        RemotePublicNotesRepository(client).load(0),
        throwsFormatException,
      );
      expect(calls, 1);
      client.close();
    },
  );
  test('reject non UTF8, invalid MIME and redirect bodies as data', () async {
    for (final response in [
      http.Response.bytes(
        [0xff],
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
      http.Response(
        source([]),
        200,
        headers: {'content-type': 'application/json'},
      ),
      http.Response(
        source([]),
        302,
        headers: {
          'location': 'https://foreign.test',
          'content-type': 'text/html',
        },
      ),
    ]) {
      final client = BookstarkClient(
        server.toString(),
        transport: MockClient((r) async => response),
      );
      await expectLater(
        RemotePublicNotesRepository(client).load(1),
        throwsA(anyOf(isA<FormatException>(), isA<ApiFailure>())),
      );
      client.close();
    }
  });
}
