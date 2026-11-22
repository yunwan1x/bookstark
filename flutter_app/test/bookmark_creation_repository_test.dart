import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';

void main() {
  test(
    'recoverable create runs before legacy URL check and skips label mutations',
    () async {
      var callbacks = 0, requests = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((_) async {
          requests++;
          throw StateError('legacy endpoint must not be reached');
        }),
      );
      final input = BookmarkItem(
        title: 'Exact',
        url: 'https://example.test/',
        description: '\ufeffdescription\r\n😀',
        labels: ['comma,label', ' spaced ', ''],
      );
      final repository = RemoteBookmarksRepository(
        client,
        memberId: 7,
        isCurrent: () => true,
        createRecoverably: (frozen) async {
          callbacks++;
          expect(frozen.description, input.description);
          expect(frozen.labels, input.labels);
          return frozen.copyWith(
            id: 91,
            memberId: 7,
            isPinned: true,
            navVisible: true,
            order: 9,
          );
        },
      );
      try {
        expect(await repository.save(input), 91);
        expect(callbacks, 1);
        expect(requests, 0);
      } finally {
        client.close();
      }
    },
  );
  test(
    'duplicate callback preserves explicit existing-edit decision and zero legacy calls',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((_) async {
          requests++;
          throw StateError('legacy endpoint forbidden');
        }),
      );
      final existing = BookmarkItem(
        id: 81,
        memberId: 7,
        title: 'Previous title',
        url: 'https://example.test/',
        labels: ['previous,label'],
        isPinned: true,
        navVisible: true,
        order: 5,
      );
      final repository = RemoteBookmarksRepository(
        client,
        memberId: 7,
        isCurrent: () => true,
        createRecoverably: (_) async {
          throw BookmarkAlreadyExists(existing);
        },
      );
      try {
        await expectLater(
          repository.save(BookmarkItem(title: 'New title', url: existing.url)),
          throwsA(
            isA<BookmarkAlreadyExists>().having(
              (e) => identical(e.bookmark, existing),
              'same actual record',
              isTrue,
            ),
          ),
        );
        expect(requests, 0);
      } finally {
        client.close();
      }
    },
  );
}
