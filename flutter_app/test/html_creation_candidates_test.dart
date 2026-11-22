import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Map<String, Object?> row(int id) => {
    'blog_id': id,
    'member_id': 3,
    'blog_title': 'Same title',
    'blog_type': 'note',
    'editor_type': 'html',
    'version': id,
    'has_password': id == 8,
    'modify_time': '2026-11-06T10:20:30+08:00',
  };
  late BookstarkClient client;
  late RemoteHtmlCreationRepository repo;
  late Map<String, Object?> response;
  var listReads = 0, owner = 3;
  setUp(() {
    listReads = 0;
    owner = 3;
    response = {
      'code': 0,
      'data': [row(7), row(8)],
      'total': 4,
      'page': 1,
      'page_size': 2,
      'total_pages': 2,
    };
    client = BookstarkClient(
      'https://books.example/mount',
      transport: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        if (request.url.path == '/mount/api/profile') {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'member_id': owner},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        listReads++;
        expect(request.url.path, '/mount/api/blogs');
        expect(request.url.queryParameters, {
          'type': 'note',
          'editor_type': 'html',
          'page': '1',
          'keyword': 'Same & 中文',
        });
        return http.Response.bytes(
          utf8.encode(jsonEncode(response)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
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
    'duplicate titles remain distinct ID/version hints with pagination and protection',
    () async {
      final result = await repo.candidates(keyword: 'Same & 中文');
      expect(result.candidates.map((e) => e.id), [7, 8]);
      expect(result.totalPages, 2);
      expect(result.candidates.last.protected, isTrue);
      expect(result.total, 4);
      expect(listReads, 1);
    },
  );
  for (final field in [
    'member_id',
    'blog_type',
    'editor_type',
    'blog_id',
    'version',
    'modify_time',
  ]) {
    test(
      'invalid candidate $field rejects entire list before any resource read',
      () async {
        final data = row(7);
        data[field] = switch (field) {
          'member_id' => 4,
          'blog_id' => -1,
          'version' => -1,
          _ => 'invalid',
        };
        response['data'] = [data];
        await expectLater(
          repo.candidates(keyword: 'Same & 中文'),
          throwsFormatException,
        );
        expect(listReads, 1);
      },
    );
  }
  test('wrong owner blocks even candidate list request', () async {
    owner = 4;
    await expectLater(repo.candidates(keyword: 'Same & 中文'), throwsStateError);
    expect(listReads, 0);
  });
  test(
    'empty page remains observation, with no creation or implicit failure inference',
    () async {
      response = {
        'code': 0,
        'data': null,
        'total': 0,
        'page': 1,
        'page_size': 12,
        'total_pages': 0,
      };
      final result = await repo.candidates(keyword: 'Same & 中文');
      expect(result.candidates, isEmpty);
      expect(listReads, 1);
    },
  );
}
