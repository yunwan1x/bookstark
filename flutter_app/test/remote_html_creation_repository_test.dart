import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final edit = HtmlNoteEdit(
    title: 'New',
    source: '<p>原文</p>\r\n',
    labels: ['one'],
  );
  var posts = 0, reads = 0;
  var owner = 3;
  var drop = false;
  void Function()? afterPost;
  late BookstarkClient client;
  late RemoteHtmlCreationRepository repo;
  setUp(() {
    posts = 0;
    reads = 0;
    owner = 3;
    drop = false;
    afterPost = null;
    client = BookstarkClient(
      'https://books.example',
      transport: MockClient((request) async {
        if (request.url.path == '/api/profile') {
          reads++;
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'member_id': owner},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/csrf-token') {
          return http.Response(
            '{}',
            200,
            headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
          );
        }
        expect(request.url.path, '/api/blogs');
        expect(request.method, 'POST');
        posts++;
        afterPost?.call();
        if (drop) throw http.ClientException('Applied but receipt dropped');
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'blog_id': 7,
              'member_id': 3,
              'blog_type': 'note',
              'editor_type': 'html',
              'blog_title': 'New',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..restoreSession({'token': 'session'});
    repo = RemoteHtmlCreationRepository(
      client,
      memberId: 3,
      collection: 'note',
    );
  });
  tearDown(() {
    repo.dispose();
    client.close();
  });
  test(
    'one POST persists receipt before returning with no followup resource writes',
    () async {
      var stored = false;
      expect(
        await repo.submit(
          edit,
          persistReceipt: (id) async {
            expect(id, 7);
            expect(posts, 1);
            expect(reads, 1);
            stored = true;
          },
        ),
        7,
      );
      expect(stored, isTrue);
      expect(posts, 1);
    },
  );
  test(
    'lost POST receipt remains submitted unknown without automatic retry',
    () async {
      drop = true;
      await expectLater(
        repo.submit(edit, persistReceipt: (_) async => fail('No receipt')),
        throwsA(
          isA<HtmlCreationUnresolved>()
              .having((e) => e.submitted, 'submitted', true)
              .having((e) => e.receiptId, 'receiptId', isNull),
        ),
      );
      expect(posts, 1);
    },
  );
  test(
    'durable receipt failure retains ID and never issues another POST',
    () async {
      await expectLater(
        repo.submit(
          edit,
          persistReceipt: (_) async => throw StateError('Storage failed'),
        ),
        throwsA(
          isA<HtmlCreationUnresolved>()
              .having((e) => e.receiptId, 'receiptId', 7)
              .having((e) => e.submitted, 'submitted', true),
        ),
      );
      expect(posts, 1);
    },
  );
  test('wrong owner prevents POST and receipt persistence', () async {
    owner = 4;
    await expectLater(
      repo.submit(edit, persistReceipt: (_) async => fail('No receipt')),
      throwsA(
        isA<HtmlCreationUnresolved>().having(
          (e) => e.submitted,
          'submitted',
          false,
        ),
      ),
    );
    expect(posts, 0);
  });
  test(
    'logout during response cannot recreate cleared durable journal',
    () async {
      afterPost = () => client.restoreSession({'token': 'different-owner'});
      await expectLater(
        repo.submit(edit, persistReceipt: (_) async => fail('No late storage')),
        throwsA(
          isA<HtmlCreationUnresolved>().having(
            (e) => e.receiptId,
            'receiptId',
            7,
          ),
        ),
      );
      expect(posts, 1);
    },
  );
}
