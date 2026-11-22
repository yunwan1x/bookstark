import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/resource_labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('book byte limits and labels preserve exact legacy identities', () {
    expect(encodeResourceLabels([' 阅读 ', '学习', '学习']), ' 阅读 ,学习');
    expect(encodeResourceLabels([]), '');
    expect(() => encodeResourceLabels(['a,b']), throwsFormatException);
    expect(() => encodeResourceLabels(['a，b']), throwsFormatException);
    expect(BookItem(name: List.filled(66, '书').join()).writeBody(), isNotEmpty);
    expect(
      () => BookItem(name: List.filled(67, '书').join()).writeBody(),
      throwsFormatException,
    );
    expect(() => const BookItem(name: '  ').writeBody(), throwsFormatException);
    expect(
      () => BookItem(
        name: '书',
        description: List.filled(501, '📖').join(),
      ).writeBody(),
      throwsFormatException,
    );
    expect(
      () => const BookItem(name: '列表', labelsLoaded: false).writeBody(),
      throwsStateError,
    );
    expect(
      const BookItem(
        name: '书',
        identify: 'keep',
        documentCount: 12,
      ).writeBody().keys,
      unorderedEquals(['book_name', 'description', 'labels']),
    );
  });

  test(
    'unsafe remote labels fail before any HTTP writes for books and notes',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        RemoteBooksRepository(
          client,
        ).save(const BookItem(name: '书', labels: ['a,b'])),
        throwsFormatException,
      );
      await expectLater(
        RemoteNotesRepository(
          client,
        ).save(const Note(id: 1, title: '笔记', content: '保留', labels: ['a，b'])),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );

  test(
    'book list nullable data uses server pagination and detail authoritative labels',
    () async {
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/books')) {
            expect(request.url.queryParameters['keyword'], '中文 &');
            return http.Response(
              jsonEncode({
                'data': null,
                'total': 0,
                'page': 2,
                'page_size': 12,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': {
                'book_id': 7,
                'book_name': '书',
                'label': 'ambiguous,csv',
                'labels': ['ambiguous,csv'],
                'doc_count': 12,
                'modify_time': null,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final repo = RemoteBooksRepository(client);
      final page = await repo.list(keyword: '中文 &', page: 2);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      final detail = await repo.read(7);
      expect(detail.labels, ['ambiguous,csv']);
      expect(detail.documentCount, 12);
      expect(detail.modifiedAt, isNull);
    },
  );

  test(
    'created book retains ID when label verification detects silently ignored binding',
    () async {
      var creates = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          if (request.url.path.endsWith('/books') && request.method == 'POST') {
            creates++;
            return http.Response('{"data":{"book_id":42}}', 200);
          }
          if (request.method == 'GET') return http.Response('{"data":[]}', 200);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final repo = RemoteBooksRepository(client);
      await expectLater(
        repo.save(const BookItem(name: '书', labels: ['阅读'])),
        throwsA(
          isA<BookSaveFailure>().having(
            (failure) => failure.savedId,
            'saved ID',
            42,
          ),
        ),
      );
      await repo.save(const BookItem(id: 42, name: '书'));
      expect(creates, 1);
    },
  );
}
