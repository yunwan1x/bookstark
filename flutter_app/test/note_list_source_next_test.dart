import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/note_list_entry.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/note_list_query.dart';
import 'package:bookstark_flutter/core/remote_note_list_source.dart';
import 'package:bookstark_flutter/core/local_note_list_source.dart';

Map<String, Object?> page({
  String preview = 'Snippet',
  bool protected = false,
}) => {
  'code': 0,
  'data': [
    {
      'blog_id': 7,
      'blog_title': 'N',
      'content_preview': preview,
      'has_password': protected,
      'is_pinned': 1,
      'visibility': 1,
      'editor_type': 'mindmap',
      'labels': ['kept'],
      'modify_time': '2026-11-11T10:00:00Z',
    },
  ],
  'total': 1,
  'page': 1,
  'page_size': 20,
  'total_pages': 1,
};

class _Local extends Fake implements NoteListRepository {
  int calls = 0;
  List<Object?>? received;
  @override
  Future<List<NoteListEntry>> listEntries({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async {
    calls++;
    received = [keyword, page, label, pinned];
    return const [
      NoteListEntry(id: 9, title: 'Local', contentPreview: 'Local snippet'),
    ];
  }
}

void main() {
  test(
    'remote typed metadata uses encoded query and preserves actual editor routing hint',
    () async {
      String? path;
      final source = RemoteNoteListSource(
        readBoundedPage: (request) async {
          path = request;
          return page();
        },
      );
      final result = await source.list(
        const NoteListQuery(keyword: 'a & 雪', label: 'exact'),
      );
      expect(Uri.parse(path!).queryParameters['keyword'], 'a & 雪');
      expect(result.items.single.editorType, 'mindmap');
      expect(result.items.single.pinned, isTrue);
      expect(result.items.single.visibility, NoteVisibilityFilter.public);
      expect(result.hasMore, isFalse);
    },
  );
  test(
    'oversized materialized previews are rejected, never treated as bounded DTO proof',
    () async {
      final source = RemoteNoteListSource(
        readBoundedPage: (_) async => page(preview: 'x' * 513),
      );
      await expectLater(
        source.list(const NoteListQuery()),
        throwsFormatException,
      );
    },
  );
  test('protected metadata never renders a supplied preview', () async {
    final source = RemoteNoteListSource(
      readBoundedPage: (_) async => page(protected: true),
    );
    expect(
      (await source.list(const NoteListQuery())).items.single.contentPreview,
      '',
    );
  });
  test('late scoped remote page does not publish into new owner', () async {
    var current = true;
    final gate = Completer<Map<String, Object?>>();
    final source = RemoteNoteListSource(
      readBoundedPage: (_) => gate.future,
      isCurrent: () => current,
    );
    final future = source.list(const NoteListQuery());
    current = false;
    gate.complete(page());
    await expectLater(future, throwsStateError);
  });
  test(
    'local adapter preserves overrides and does not pretend unsupported filters work',
    () async {
      final repo = _Local();
      final source = LocalNoteListSource(repository: repo);
      await expectLater(
        source.list(const NoteListQuery(pin: NotePinFilter.pinned)),
        throwsUnsupportedError,
      );
      expect(repo.calls, 0);
      final result = await source.list(
        const NoteListQuery(keyword: 'body', label: 'tag'),
        page: 3,
      );
      expect(repo.received, ['body', 3, 'tag', '']);
      expect(result.items.single.pinned, isNull);
      expect(result.items.single.visibility, isNull);
      expect(source.capabilities.searchHint, 'title-or-content');
    },
  );
}
