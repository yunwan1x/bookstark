import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> data() => {
  'counts': {for (final key in searchGroupKeys.values) key: 0},
  for (final key in searchGroupKeys.values) key: null,
};
void main() {
  test(
    'UTF8 query boundary preserves complete Unicode and rejects before HTTP',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      expect(normalizeSearchQuery(' 阅读 '), '阅读');
      expect(
        normalizeSearchQuery(List.filled(25, '📚').join()).runes.length,
        25,
      );
      await expectLater(
        RemoteSearchRepository(client).search(List.filled(26, '📚').join()),
        throwsFormatException,
      );
      await expectLater(
        RemoteSearchRepository(client).search(' '),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'real protocol retains type-keyed identical IDs and loaded counts',
    () async {
      final body = data();
      body['documents'] = [
        {'id': 1, 'name': '文档', 'book_name': '书籍', 'snippet': '正文'},
      ];
      body['blogs'] = [
        {'id': 1, 'title': '文章', 'blog_type': 'article', 'snippet': '摘要'},
      ];
      body['tasks'] = [
        {
          'id': 1,
          'content': '待办',
          'done': false,
          'due_date': '2026-11-08',
          'parent_id': 0,
        },
      ];
      (body['counts'] as Map).addAll(<String, int>{
        'documents': 1,
        'blogs': 1,
        'tasks': 1,
      });
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((request) async {
          expect(request.url.path, '/base/api/search');
          expect(request.url.queryParameters['q'], '100%_阅读\\');
          return http.Response(
            jsonEncode({'code': 0, 'data': body}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      client.restoreSession({'token':'synthetic-search-fixture'});
      final result = await RemoteSearchRepository(client).search(' 100%_阅读\\ ');
      expect(result.loaded, 3);
      expect(result.all.map((item) => item.key).toSet().length, 3);
      expect(
        result.groups[SearchKind.blog]!.single.collection,
        NoteCollection.article,
      );
    },
  );
  test(
    'server count mismatch and per-group duplicates are not presented as successful totals',
    () {
      final body = data();
      (body['counts'] as Map)['books'] = 1;
      expect(() => SearchResults.fromJson('阅读', body), throwsFormatException);
      body['books'] = [
        {'id': 1, 'name': '书'},
        {'id': 1, 'name': '重复'},
      ];
      (body['counts'] as Map)['books'] = 2;
      expect(() => SearchResults.fromJson('阅读', body), throwsFormatException);
    },
  );
  test(
    'protected snippets are suppressed and unknown blog type is never coerced to note',
    () {
      final hit = SearchHit.fromJson(SearchKind.blog, {
        'id': 7,
        'title': '受保护',
        'snippet': 'ENC:v1:ciphertext',
        'blog_type': 'unknown',
      });
      expect(hit.snippet, isEmpty);
      expect(hit.collection, isNull);
      expect(hit.id, 7);
    },
  );
}
