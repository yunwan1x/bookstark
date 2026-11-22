import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'public_shares_repository_test.dart' as fixture show detail, json;

void main() {
  test(
    'owner HTML raw source also preserves an original UTF8 BOM and CRLF',
    () async {
      const source = '\ufeff<p>原文</p>\r\n';
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          expect(request.url.path, '/api/blogs/8/content/raw');
          return http.Response.bytes(
            utf8.encode(source),
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
      expect(await client.blogHtmlSource(8), source);
      client.close();
    },
  );
  test(
    'public HTML loads exact raw bytes through its own prefixed share endpoint',
    () async {
      const identify = '中文%2F+';
      const source =
          '\ufeff<!doctype html>\r\n<script>let count=0;</script>中文\r\n';
      final paths = <List<String>>[];
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          paths.add(r.url.pathSegments);
          expect(r.followRedirects, isFalse);
          expect(r.url.hasQuery, isFalse);
          if (paths.length == 1) {
            return fixture.json({
              ...fixture.detail(identify),
              'doc_type': 'html',
              'content': '',
              'content_url':
                  '/api/shares/${Uri.encodeComponent(identify)}/content/raw',
            });
          }
          expect(r.headers['accept'], 'text/html');
          return http.Response.bytes(
            utf8.encode(source),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      final loaded = await RemotePublicSharesRepository(
        client,
      ).load(PublicShareReference(client.baseUri, identify));
      expect(loaded.content, source);
      expect(loaded.html, isTrue);
      expect(paths, [
        ['base', 'api', 'shares', identify],
        ['base', 'api', 'shares', identify, 'content', 'raw'],
      ]);
      client.close();
    },
  );
  test(
    'locked HTML fetches no raw content until explicit password, preserving spaces',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls++;
          if (calls == 1) {
            return fixture.json({
              ...fixture.detail('s', locked: true),
              'doc_type': 'html',
            });
          }
          expect(r.method, 'POST');
          expect(r.url.path, '/api/shares/s/verify-password/raw');
          expect(jsonDecode(r.body), {'password': ' 密码 '});
          expect(r.headers['x-csrf-token'], 'csrf');
          return http.Response(
            '<button>保留原文</button>\r\n',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      client.restoreSession({'csrf_token': 'csrf'});
      final repo = RemotePublicSharesRepository(client);
      final locked = await repo.load(PublicShareReference(client.baseUri, 's'));
      expect(calls, 1);
      expect(locked.content, isEmpty);
      final unlocked = await repo.unlock(locked, ' 密码 ');
      expect(calls, 2);
      expect(unlocked.content, '<button>保留原文</button>\r\n');
      expect(unlocked.protected, isTrue);
      expect(unlocked.locked, isFalse);
      expect(unlocked.rawAvailable, isFalse);
      expect(locked.locked, isTrue);
      client.close();
    },
  );
  test(
    'missing or foreign public HTML raw membership fails before reading body',
    () async {
      for (final url in [
        null,
        '/api/shares/other/content/raw',
        'https://other.test/api/shares/s/content/raw',
      ]) {
        var calls = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((_) async {
            calls++;
            return fixture.json({
              ...fixture.detail('s'),
              'doc_type': 'html',
              'content': '',
              'content_url': ?url,
            });
          }),
        );
        await expectLater(
          RemotePublicSharesRepository(
            client,
          ).load(PublicShareReference(client.baseUri, 's')),
          throwsFormatException,
        );
        expect(calls, 1);
        client.close();
      }
    },
  );
  test(
    'raw public HTML rejects redirects, unexpected media and malformed UTF8',
    () async {
      for (final response in [
        http.Response(
          'redirect',
          302,
          headers: {
            'content-type': 'text/html',
            'location': 'https://other.test',
          },
        ),
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
        http.Response.bytes(
          [255],
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((r) async {
            expect(r.followRedirects, isFalse);
            return response;
          }),
        );
        await expectLater(
          client.publicShareHtmlSource(
            PublicShareReference(client.baseUri, 's'),
          ),
          throwsA(anything),
        );
        client.close();
      }
    },
  );
  test(
    'public raw HTML has exact five MiB UTF8 bound, separate from Markdown limit',
    () async {
      final maxSource = List.filled(5 * 1024 * 1024 ~/ 2, 'é').join();
      var excessive = false;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(excessive ? '${maxSource}x' : maxSource),
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      final ref = PublicShareReference(client.baseUri, 's');
      expect(await client.publicShareHtmlSource(ref), maxSource);
      excessive = true;
      await expectLater(
        client.publicShareHtmlSource(ref),
        throwsA(isA<ApiFailure>()),
      );
      client.close();
    },
  );
  test(
    'public HTML API refuses different server and password on a book chapter without HTTP',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      await expectLater(
        client.publicShareHtmlSource(
          PublicShareReference(Uri.parse('https://other.test'), 's'),
        ),
        throwsFormatException,
      );
      await expectLater(
        client.publicShareHtmlSource(
          PublicShareReference(client.baseUri, 's'),
          chapterIdentify: 'chapter',
          password: 'secret',
        ),
        throwsFormatException,
      );
      expect(calls, 0);
      client.close();
    },
  );
}
