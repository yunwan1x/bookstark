import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> row(int id, String url) => {
  'bookmark_id': id,
  'member_id': 7,
  'title': '书签',
  'url': url,
  'labels': ['a,b', ' 空格 '],
  'is_pinned': true,
  'nav_visible': true,
};
BookstarkClient clientWith(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = BookstarkClient(
    'https://example.test/base',
    transport: MockClient((request) async {
      if (request.url.path.endsWith('/csrf-token')) {
        return http.Response(
          '{}',
          200,
          headers: {'set-cookie': 'csrf_token=test'},
        );
      }
      return handler(request);
    }),
  );
  addTearDown(client.close);
  return client;
}

void main() {
  test(
    'source read resolves canonical ID and preserves navigation metadata',
    () async {
      final methods = <String>[];
      final client = clientWith((request) async {
        methods.add(request.method);
        if (request.url.path.endsWith('/9/')) {
          return reply({
            'url': 'https://same.test/',
            'title': 'compatibility title',
          });
        }
        expect(request.url.queryParameters['scope'], 'mine');
        return reply({
          'data': [
            row(8, 'https://same.test/'),
            {
              ...row(9, 'https://same.test/'),
              'title': 'canonical',
              'order_sort': 12,
            },
          ],
          'total': 2,
          'page': 1,
          'page_size': 20,
        });
      });
      final value = await RemoteBookmarksRepository(
        client,
        memberId: 7,
      ).read(9);
      expect(value.id, 9);
      expect(value.title, 'canonical');
      expect(value.navVisible, isTrue);
      expect(value.isPinned, isTrue);
      expect(value.labels, ['a,b', ' 空格 ']);
      expect(methods, ['GET', 'GET']);
    },
  );

  test('URL and byte validation preserve original URL identities', () {
    const value = 'https://example.test:54321/a?x=1&x=2#片段';
    expect(
      const BookmarkItem(title: '书签', url: value).writeBody()['url'],
      value,
    );
    for (final url in [
      'javascript:alert(1)',
      'https://',
      'https://a.test:99999',
      'https://a.test/a b',
    ]) {
      expect(() => bookmarkUri(url), throwsFormatException);
    }
    expect(
      () => BookmarkItem(
        title: List.filled(167, '书').join(),
        url: value,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => BookmarkItem(
        title: '书',
        url: value,
        description: List.filled(501, '📖').join(),
      ).validate(),
      throwsFormatException,
    );
    expect(
      BookmarkItem.fromJson({
        ...row(1, value),
        'create_time': '0001-01-01T00:00:00Z',
      }).createdAt,
      isNull,
    );
  });
  test('query uses repeated exact AND names and naive server dates', () {
    final parameters = BookmarkQuery(
      labels: ['a,b', ' 空格 '],
      start: DateTime(2026, 11, 4, 8, 9),
      modified: true,
    ).parameters();
    final uri = Uri(queryParameters: parameters);
    expect(uri.queryParametersAll['label'], ['a,b', ' 空格 ']);
    expect(uri.queryParameters['start_time'], '2026-11-04T08:09:00');
    expect(uri.queryParameters['time_field'], 'modify');
    expect(
      () => const BookmarkQuery(labelsOr: [' 空格 ']).parameters(),
      throwsFormatException,
    );
    expect(
      () => const BookmarkQuery(labelsOr: ['a,b']).parameters(),
      throwsFormatException,
    );
    expect(
      () => const BookmarkQuery(site: 'example.test/path').parameters(),
      throwsFormatException,
    );
    expect(
      () => const BookmarkQuery(page: 0).parameters(),
      throwsFormatException,
    );
  });
  test(
    'duplicate preflight paginates own rows without metadata or mutation',
    () async {
      final methods = <String>[];
      final client = clientWith((request) async {
        methods.add(request.method);
        expect(request.url.path, '/base/api/bookmarks');
        expect(request.url.queryParameters['scope'], 'mine');
        final page = int.parse(request.url.queryParameters['page']!);
        return reply({
          'data': [
            row(page, page == 1 ? 'https://other.test/' : 'https://same.test/'),
          ],
          'total': 2,
          'page': page,
          'page_size': 1,
        });
      });
      await expectLater(
        RemoteBookmarksRepository(
          client,
          memberId: 7,
        ).save(const BookmarkItem(title: '新标题', url: 'https://same.test/')),
        throwsA(
          isA<BookmarkAlreadyExists>().having(
            (e) => e.bookmark.id,
            'existing ID',
            2,
          ),
        ),
      );
      expect(methods, ['GET', 'GET']);
    },
  );
  test('editing unchanged URL preserves favicon and unrelated flags', () async {
    const original = BookmarkItem(
      id: 9,
      memberId: 7,
      title: '旧',
      url: 'https://keep.test/',
      favicon: 'keep.ico',
      isPinned: true,
      navVisible: true,
      order: 18,
    );
    final client = clientWith((request) async {
      if (request.url.path.endsWith('/bookmarks/9')) {
        final body = jsonDecode(request.body) as Map;
        expect(
          body.keys,
          unorderedEquals(['title', 'description', 'is_public', 'labels']),
        );
        expect(body['title'], '新');
      }
      return reply(
        request.method == 'GET'
            ? {
                'data': ['阅读'],
              }
            : {},
      );
    });
    final repo = RemoteBookmarksRepository(client, memberId: 7);
    expect(
      await repo.save(
        original.copyWith(title: '新', labels: ['阅读']),
        original: original,
      ),
      9,
    );
    expect(repo.canEdit(original.copyWith(memberId: 8)), isFalse);
    await expectLater(
      repo.save(original.copyWith(memberId: 8)),
      throwsStateError,
    );
  });
  test(
    'comma and whitespace names use exact array batches and verify',
    () async {
      final names = ['a,b', ' 空格 ', '', for (var i = 0; i < 51; i++) '标签$i'];
      final chunks = <List<String>>[];
      final client = clientWith((request) async {
        if (request.url.path.endsWith('/bookmarks/9')) {
          expect((jsonDecode(request.body) as Map)['labels'], '');
        } else if (request.url.path.endsWith('/batch-add-labels')) {
          final body = jsonDecode(request.body) as Map;
          expect(body['ids'], [9]);
          chunks.add((body['tags'] as List).cast<String>());
          return reply({'count': 1});
        } else {
          expect(request.method, 'GET');
          return reply({'data': names});
        }
        return reply({});
      });
      await RemoteBookmarksRepository(client, memberId: 7).save(
        BookmarkItem(
          id: 9,
          memberId: 7,
          title: '书',
          url: 'https://a.test/',
          labels: names,
        ),
      );
      expect(chunks.map((chunk) => chunk.length), [50, 4]);
      expect(chunks.expand((chunk) => chunk), names);
    },
  );
  test('verification failure preserves created ID for retry', () async {
    var creates = 0;
    final client = clientWith((request) async {
      if (request.url.path.endsWith('/bookmarks')) {
        if (request.method == 'POST') {
          creates++;
          return reply({'bookmark_id': 21});
        }
        return reply({'data': null, 'total': 0, 'page': 1, 'page_size': 20});
      }
      return reply(request.method == 'GET' ? {'data': []} : {});
    });
    await expectLater(
      RemoteBookmarksRepository(client, memberId: 7).save(
        const BookmarkItem(title: '书', url: 'https://a.test/', labels: ['阅读']),
      ),
      throwsA(
        isA<BookmarkSaveFailure>().having((e) => e.savedId, 'saved ID', 21),
      ),
    );
    expect(creates, 1);
  });
  test('batch rejects invalid IDs and checks actual affected count', () async {
    var calls = 0;
    final client = clientWith((request) async {
      calls++;
      return reply({'count': 1});
    });
    final repo = RemoteBookmarksRepository(client, memberId: 7);
    for (final ids in <List<int>>[
      [],
      [1, 1],
      [0],
      List.generate(201, (i) => i + 1),
    ]) {
      await expectLater(
        repo.batch(BookmarkBatch.delete, ids),
        throwsFormatException,
      );
    }
    expect(calls, 0);
    await expectLater(
      repo.batch(BookmarkBatch.share, [1, 2]),
      throwsStateError,
    );
    expect(calls, 1);
  });
  test(
    'metadata is explicit and retains provider error inside HTTP 200',
    () async {
      final client = clientWith((request) async {
        expect(request.url.path, '/base/api/fetch-meta');
        expect(jsonDecode(request.body), {'url': 'https://a.test/'});
        return reply({'error': '获取失败', 'title': ''});
      });
      expect(
        (await RemoteBookmarksRepository(
          client,
          memberId: 7,
        ).metadata('https://a.test/')).error,
        '获取失败',
      );
    },
  );
}
