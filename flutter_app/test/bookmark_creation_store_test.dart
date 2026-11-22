import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/bookmark_creation_attempt.dart';
import 'package:bookstark_flutter/core/bookmark_creation_store.dart';
import 'package:bookstark_flutter/core/bookmark_creation_slot.dart';

void main() {
  final scope = List.filled(64, 'a').join(), key = List.filled(32, 'b').join();
  BookmarkCreationAttempt input([String url = 'https://example.test/']) =>
      BookmarkCreationAttempt(
        scope: scope,
        key: key,
        body: {
          'title': ' exact 😀',
          'url': url,
          'description': '\ufeffbody\r\n',
          'favicon': '',
          'is_public': false,
          'labels': ['comma,label', ' spaced ', ''],
        },
      );
  test(
    'strict claim is unique; unknown never authorizes another submission',
    () async {
      final data = <String, String>{};
      var flushes = 0;
      final store = BookmarkCreationStore(
        scope: scope,
        key: key,
        read: (k) async => data[k],
        write: (k, v) async {
          data[k] = v;
        },
        remove: (k) async {
          data.remove(k);
        },
        flush: () async {
          flushes++;
        },
        isCurrent: () => true,
      );
      final lease = Object();
      store.acquire(lease);
      try {
        expect(
          () => store.acquire(Object()),
          throwsA(isA<BookmarkCreationStorageUnconfirmed>()),
        );
        final pending = input();
        await store.insert(pending, lease);
        await store.claim(pending, lease);
        expect((await store.load())!.phase, BookmarkCreationPhase.unknown);
        await expectLater(
          store.claim(pending, lease),
          throwsA(isA<BookmarkCreationStorageUnconfirmed>()),
        );
        expect(flushes, 2);
        final unknown = pending.next(BookmarkCreationPhase.unknown);
        await store.end(unknown, lease);
        await expectLater(
          store.acknowledge(unknown, 91, lease),
          throwsA(isA<BookmarkCreationStorageUnconfirmed>()),
        );
        expect(data, isEmpty);
        await expectLater(
          store.insert(pending, lease),
          throwsA(isA<BookmarkCreationStorageUnconfirmed>()),
        );
      } finally {
        store.release(lease);
      }
    },
  );
  test(
    'flush failure leaves conservative unknown and requires reload',
    () async {
      final data = <String, String>{};
      var fail = false;
      final store = BookmarkCreationStore(
        scope: scope,
        key: 'd' * 32,
        read: (k) async => data[k],
        write: (k, v) async {
          data[k] = v;
        },
        remove: (k) async {
          data.remove(k);
        },
        flush: () async {
          if (fail) throw StateError('synthetic flush failure');
        },
        isCurrent: () => true,
      );
      final lease = Object();
      store.acquire(lease);
      try {
        final pending = BookmarkCreationAttempt(
          scope: scope,
          key: 'd' * 32,
          body: input().body,
        );
        await store.insert(pending, lease);
        fail = true;
        await expectLater(store.claim(pending, lease), throwsStateError);
        expect((await store.load())!.phase, BookmarkCreationPhase.unknown);
        fail = false;
        await expectLater(
          store.claim(pending, lease),
          throwsA(isA<BookmarkCreationStorageUnconfirmed>()),
        );
      } finally {
        store.release(lease);
      }
    },
  );
  test(
    'account slot survives cold instance and changed URL cannot allocate another',
    () async {
      final data = <String, String>{};
      BookmarkCreationSlot make() => BookmarkCreationSlot(
        scope: scope,
        read: (k) async => data[k],
        write: (k, v) async {
          data[k] = v;
        },
        remove: (k) async {
          data.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final first = await make().open(), cold = await make().open();
      expect(first.created, isTrue);
      expect(cold.created, isFalse);
      expect(cold.key, first.key);
      final changed = input('https://different.test/');
      expect(changed.inputDigest, isNot(input().inputDigest));
      expect((await make().open()).key, first.key);
      await make().clear(first.key);
      final fresh = await make().open();
      expect(fresh.created, isTrue);
      expect(fresh.key, isNot(first.key));
    },
  );
}
