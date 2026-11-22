import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/note_list_query.dart';
import 'package:bookstark_flutter/core/remote_note_list_source.dart';
import 'package:bookstark_flutter/features/notes/owned_note_list_scope.dart';

Map<String, Object?> ownedPage() => {
  'code': 0,
  'total': 1,
  'page': 1,
  'page_size': 20,
  'total_pages': 1,
  'data': [
    {
      'blog_id': 1,
      'blog_title': 'Owned',
      'member_id': 7,
      'blog_type': 'note',
      'editor_type': 'markdown',
      'visibility': 0,
      'is_pinned': 0,
      'has_password': false,
      'labels': <String>[],
      'content_preview': 'bounded',
      'modify_time': '2026-11-11T10:00:00Z',
    },
  ],
};
void main() {
  test(
    'production source opts in and refuses wrong owner/collection or missing flags',
    () async {
      for (final change in <void Function(Map<String, Object?>)>[
        (row) {
          row['member_id'] = 8;
        },
        (row) {
          row['blog_type'] = 'article';
        },
        (row) {
          row.remove('is_pinned');
        },
        (row) {
          row.remove('visibility');
        },
        (row) {
          row.remove('editor_type');
        },
        (row) {
          row.remove('member_id');
        },
      ]) {
        final envelope = ownedPage();
        change((envelope['data'] as List).single as Map<String, Object?>);
        final source = RemoteNoteListSource(
          expectedMemberId: 7,
          readBoundedPage: (path) async {
            expect(Uri.parse(path).queryParameters['metadata_only'], '1');
            return envelope;
          },
        );
        await expectLater(
          source.list(const NoteListQuery()),
          throwsFormatException,
        );
      }
      final source = RemoteNoteListSource(
        expectedMemberId: 7,
        readBoundedPage: (_) async => ownedPage(),
      );
      expect((await source.list(const NoteListQuery())).items.single.id, 1);
    },
  );
  testWidgets(
    'stable mounted identity preserves source repository and actions; identity retires old owner',
    (tester) async {
      final client = BookstarkClient('https://example.invalid/prefix');
      client.restoreSession({'token': 'host-fixture-only'});
      addTearDown(client.close);
      var creates = 0;
      OwnedNoteListBinding? visible;
      Widget page(int identity) => MaterialApp(
        home: OwnedNoteListScope(
          identity: identity,
          isCurrent: () => true,
          create: (current) {
            creates++;
            return OwnedNoteListBinding.remote(
              client: client,
              memberId: 7,
              collection: NoteCollection.note,
              scope: 'list-$identity',
              isCurrent: current,
            );
          },
          builder: (context, binding) {
            visible = binding;
            return const Text('list');
          },
        ),
      );
      await tester.pumpWidget(page(1));
      final first = visible!;
      await tester.pumpWidget(page(1));
      await tester.pump();
      expect(creates, 1);
      expect(identical(visible, first), true);
      expect(identical(visible!.source, first.source), true);
      expect(identical(visible!.actions, first.actions), true);
      await tester.pumpWidget(page(2));
      await tester.pump();
      expect(creates, 2);
      expect(identical(visible, first), false);
      // Guard must reject before any HTTP. No real network in this test.
      await expectLater(
        first.source.list(const NoteListQuery()),
        throwsStateError,
      );
      final second = visible!;
      await tester.pumpWidget(const SizedBox());
      await expectLater(
        second.source.list(const NoteListQuery()),
        throwsStateError,
      );
    },
  );
  test(
    'same-token restore invalidates the captured revision without a request',
    () async {
      final client = BookstarkClient('https://example.invalid');
      client.restoreSession({'token': 'host-fixture-only'});
      addTearDown(client.close);
      final binding = OwnedNoteListBinding.remote(
        client: client,
        memberId: 7,
        collection: NoteCollection.note,
        scope: 'scope',
        isCurrent: () => true,
      );
      addTearDown(binding.retire);
      client.restoreSession({'token': 'host-fixture-only'});
      await expectLater(
        binding.source.list(const NoteListQuery()),
        throwsStateError,
      );
    },
  );
}
