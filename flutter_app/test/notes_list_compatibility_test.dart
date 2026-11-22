import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'DTO lists honor existing filtered repository overrides without network',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((_) async {
          calls++;
          throw StateError(
            'An overridden repository must not fetch the network',
          );
        }),
      );
      final repo = _OverrideRepository(client);
      final entries = await repo.listEntries(
        keyword: 'needle',
        page: 3,
        label: 'tag',
        pinned: '1',
      );
      expect(repo.filters, ['needle', 3, 'tag', '1']);
      expect(calls, 0);
      final entry = entries.single;
      expect(entry.id, 7);
      expect(entry.title, repo.note.title);
      expect(entry.contentPreview, '😀' * 512);
      expect(entry.isProtected, isTrue);
      expect(entry.labels, ['tag']);
      expect(repo.note.content.runes.length, 700);
    },
  );

  test(
    'remote protected list metadata and bounded Unicode preview survive DTO mapping',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          expect(request.url.path, '/api/blogs');
          expect(request.url.queryParameters['type'], 'article');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'blog_id': 8,
                    'blog_title': 'Protected article',
                    'content_preview': '📚' * 600,
                    'labels': ['private'],
                    'has_password': true,
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      final entry = (await RemoteNotesRepository(
        client,
        collection: NoteCollection.article,
      ).listEntries()).single;
      expect(entry.isProtected, isTrue);
      expect(entry.id, 8);
      expect(entry.contentPreview, '📚' * 512);
      expect(entry.labels, ['private']);
    },
  );
}

class _OverrideRepository extends RemoteNotesRepository {
  _OverrideRepository(super.client);
  List<Object?>? filters;
  final note = Note(
    id: 7,
    title: 'Fixture',
    content: '😀' * 700,
    labels: const ['tag'],
    isProtected: true,
  );
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async {
    filters = [keyword, page, label, pinned];
    return [note];
  }
}
