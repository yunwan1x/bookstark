import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';

Map<String, Object?> detail(String identify, {bool locked = false}) => {
  'share_type': 'blog',
  'share_id': -8,
  'target_id': 8,
  'share_identify': identify,
  'has_password': locked,
  'doc_type': 'markdown',
  'title': '实际标题',
  'content': locked ? 'must not leak' : '# 正文\r\n',
  'labels': ['public-label'],
};
http.Response json(Map<String, Object?> data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': data})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'fixed public endpoints encode literal percent once and preserve password spaces',
    () async {
      const identify = '中文%2F+';
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          calls++;
          expect(r.followRedirects, isFalse);
          expect(
            r.url.pathSegments,
            r.method == 'GET'
                ? ['base', 'api', 'shares', identify]
                : ['base', 'api', 'shares', identify, 'verify-password'],
          );
          expect(r.headers['cookie'], contains('csrf_token=csrf'));
          if (r.method == 'POST') {
            expect(jsonDecode(r.body), {'password': ' 真实密码 '});
            expect(r.url.hasQuery, isFalse);
            return json({'content': '\ufeff# 解锁\r\n'});
          }
          return json(detail(identify, locked: true));
        }),
      );
      client.restoreSession({'csrf_token': 'csrf'});
      final repo = RemotePublicSharesRepository(client);
      final locked = await repo.load(
        PublicShareReference(client.baseUri, identify),
      );
      expect(locked.content, isEmpty);
      expect(locked.labels, isEmpty);
      final unlocked = await repo.unlock(locked, ' 真实密码 ');
      expect(unlocked.content, '\ufeff# 解锁\r\n');
      expect(unlocked.protected, isTrue);
      expect(unlocked.locked, isFalse);
      expect(calls, 2);
      await expectLater(
        repo.load(
          PublicShareReference(Uri.parse('https://other.test'), identify),
        ),
        throwsFormatException,
      );
      expect(calls, 2);
      client.close();
    },
  );
  test(
    'wrong password propagates and does not mutate locked detail or retry',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls++;
          return http.Response(
            '{"code":400,"message":"密码不正确"}',
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      client.restoreSession({'csrf_token': 'csrf'});
      final locked = PublicShareDetail.fromJson(
        PublicShareReference(client.baseUri, 'share'),
        detail('share', locked: true),
      );
      await expectLater(
        RemotePublicSharesRepository(client).unlock(locked, 'wrong'),
        throwsA(isA<ApiFailure>()),
      );
      expect(locked.locked, isTrue);
      expect(locked.content, isEmpty);
      expect(calls, 1);
      client.close();
    },
  );
  test(
    'actual public tree membership required and returned chapter format wins',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls++;
          if (r.url.path.endsWith('/content/raw')) {
            expect(r.url.path, '/api/shares/book/docs/real/content/raw');
            return http.Response(
              '<p>chapter raw</p>',
              200,
              headers: {'content-type': 'text/html'},
            );
          }
          expect(r.url.path, '/api/shares/book/docs/real');
          return json({
            'title': '当前标题',
            'content': '',
            'doc_type': 'html',
            'content_url': '/api/shares/book/docs/real/content/raw',
          });
        }),
      );
      final ref = PublicShareReference(client.baseUri, 'book');
      final book = PublicShareDetail.fromJson(ref, {
        ...detail('book'),
        'share_type': 'book',
        'share_id': 9,
        'target_id': 4,
        'doc_tree': [
          {
            'document_id': 12,
            'parent_id': 0,
            'identify': 'real',
            'document_name': '旧标题',
            'doc_type': 'markdown',
            'children': [],
          },
        ],
      });
      final repo = RemotePublicSharesRepository(client);
      await expectLater(repo.chapter(book, 'other'), throwsFormatException);
      expect(calls, 0);
      final chapter = await repo.chapter(book, 'real');
      expect(chapter.node.id, 12);
      expect(chapter.title, '当前标题');
      expect(chapter.format, 'html');
      expect(chapter.rawAvailable, isTrue);
      expect(chapter.content, '<p>chapter raw</p>');
      expect(calls, 2);
      client.close();
    },
  );
  test(
    'JSON media, UTF8, oversized streams, redirect and private paths fail',
    () async {
      for (final response in [
        http.Response('{}', 200, headers: {'content-type': 'text/html'}),
        http.Response.bytes(
          [255],
          200,
          headers: {'content-type': 'application/json'},
        ),
        http.Response(
          '{}',
          302,
          headers: {
            'content-type': 'application/json',
            'location': 'https://evil.test',
          },
        ),
      ]) {
        final c = BookstarkClient(
          'https://example.test',
          transport: MockClient((_) async => response),
        );
        await expectLater(
          c.publicShareJson('/api/shares/s'),
          throwsA(anything),
        );
        c.close();
      }
      final c = BookstarkClient(
        'https://example.test',
        transport: MockClient.streaming(
          (r, _) async => http.StreamedResponse(
            const Stream.empty(),
            200,
            contentLength: 27 * 1024 * 1024,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        c.publicShareJson('/api/shares/s'),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        c.publicShareJson('/api/docs/8'),
        throwsFormatException,
      );
      await expectLater(
        c.publicShareJson('/api/shares/s?token=secret'),
        throwsFormatException,
      );
      c.close();
    },
  );
  test(
    'public Markdown images never fetch personal endpoints, including encoded paths',
    () async {
      final visited = <Uri>[];
      final repo = PublicShareAttachments(
        Uri.parse('https://example.test/base'),
        publicTransport: MockClient((r) async {
          visited.add(r.url);
          expect(r.headers.containsKey('cookie'), isFalse);
          expect(r.followRedirects, isFalse);
          return http.Response.bytes([1, 2], 200);
        }),
      );
      for (final path in [
        '/api/webdav/files/download?path=/private.png',
        '/base/api/webdav/files/preview?path=/private.png',
        '/base/upload-files/%2e%2e/api/private',
        '/base/upload-files/%2Fapi/private',
        'https://name:secret@other.test/x.png',
      ]) {
        await expectLater(
          repo.readPublic(Uri.parse(path), maxBytes: 10),
          throwsA(anything),
        );
      }
      expect(visited, isEmpty);
      expect(
        await repo.readPublic(
          Uri.parse('/upload-files/image.png'),
          maxBytes: 10,
        ),
        [1, 2],
      );
      expect(
        await repo.readPublic(
          Uri.parse('https://images.test/a.png'),
          maxBytes: 10,
        ),
        [1, 2],
      );
      expect(visited.length, 2);
      repo.close();
    },
  );
  testWidgets(
    'stalled public reading has a bounded deadline and aborts its HTTP request',
    (tester) async {
      final stream = StreamController<List<int>>();
      Future<void>? abort;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient.streaming((request, _) async {
          if (request is http.AbortableRequest) abort = request.abortTrigger;
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = client.publicShareJson('/api/shares/stalled');
      final done = expectLater(result, throwsA(isA<TimeoutException>()));
      await tester.pump();
      expect(abort, isNotNull);
      var aborted = false;
      abort!.then((_) => aborted = true);
      await tester.pump(const Duration(seconds: 46));
      await done;
      expect(aborted, isTrue);
      await stream.close();
      client.close();
    },
  );
}
