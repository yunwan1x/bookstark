import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/topic_creation_attempt.dart';
import 'package:bookstark_flutter/core/topic_creation_store.dart';

void main() {
  final scope = List.filled(64, 'a').join(), key = List.filled(32, 'b').join();
  TopicCreationAttempt input() => TopicCreationAttempt(
    scope: scope,
    key: key,
    kind: TopicCreationKind.topic,
    topicId: 0,
    target: '',
    targetId: 0,
    body: {
      'title': 'Exact title',
      'question': '\ufeffQuestion\r\n😀',
      'is_pinned': false,
    },
  );
  test(
    'one lease and one strict claim authorizes only one submission',
    () async {
      String? raw;
      var flushes = 0;
      TopicCreationStore store() => TopicCreationStore(
        scope: scope,
        key: key,
        read: (_) async => raw,
        write: (_, v) async {
          raw = v;
        },
        remove: (_) async {
          raw = null;
        },
        flush: () async {
          flushes++;
        },
        isCurrent: () => true,
      );
      final a = store(),
          b = store(),
          lease = Object(),
          other = Object(),
          pending = input();
      a.acquire(lease);
      try {
        expect(
          () => b.acquire(other),
          throwsA(isA<TopicCreationStorageUnconfirmed>()),
        );
        await a.insert(pending, lease);
        await a.claim(pending, lease);
        await expectLater(
          a.claim(pending, lease),
          throwsA(isA<TopicCreationStorageUnconfirmed>()),
        );
        expect(
          TopicCreationAttempt.decode(raw!).phase,
          TopicCreationPhase.unknown,
        );
        expect(flushes, 2);
      } finally {
        a.release(lease);
      }
    },
  );
  test(
    'applied claim flush failure remains unknown and never grants send',
    () async {
      String? raw;
      var fail = false, grants = 0;
      final s = TopicCreationStore(
        scope: scope,
        key: key,
        read: (_) async => raw,
        write: (_, v) async {
          raw = v;
        },
        remove: (_) async {
          raw = null;
        },
        flush: () async {
          if (fail) throw StateError('held durability');
        },
        isCurrent: () => true,
      );
      final lease = Object(), pending = input();
      s.acquire(lease);
      try {
        await s.insert(pending, lease);
        fail = true;
        try {
          await s.claim(pending, lease);
          grants++;
        } catch (_) {}
        expect(grants, 0);
        expect((await s.load())!.phase, TopicCreationPhase.unknown);
        await expectLater(
          s.claim(pending, lease),
          throwsA(isA<TopicCreationStorageUnconfirmed>()),
        );
      } finally {
        s.release(lease);
      }
    },
  );
  test(
    'clear then late acknowledgement cannot resurrect a missing record',
    () async {
      // A distinct key avoids reusing the explicit ended key from any prior test.
      final pending = TopicCreationAttempt(
        scope: scope,
        key: List.filled(32, 'c').join(),
        kind: TopicCreationKind.summary,
        topicId: 9,
        target: '',
        targetId: 0,
        body: {
          'content': 'Exact\r\n😀',
          'summary_type': 'manual',
          'order_sort': 0,
        },
      );
      String? raw;
      final s = TopicCreationStore(
        scope: scope,
        key: pending.key,
        read: (_) async => raw,
        write: (_, v) async {
          raw = v;
        },
        remove: (_) async {
          raw = null;
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final lease = Object();
      s.acquire(lease);
      try {
        await s.insert(pending, lease);
        await s.claim(pending, lease);
        final unknown = pending.next(TopicCreationPhase.unknown);
        await s.end(unknown, lease);
        await expectLater(
          s.acknowledge(unknown, 42, lease),
          throwsA(isA<TopicCreationStorageUnconfirmed>()),
        );
        expect(raw, isNull);
      } finally {
        s.release(lease);
      }
    },
  );
  test(
    'owner retirement while durability held never returns send authorization',
    () async {
      String? raw;
      var active = true, hold = false;
      final entered = Completer<void>(), release = Completer<void>();
      final pending = input(), lease = Object();
      final s = TopicCreationStore(
        scope: scope,
        key: key,
        read: (_) async => raw,
        write: (_, v) async {
          raw = v;
        },
        remove: (_) async {
          raw = null;
        },
        flush: () async {
          if (hold) {
            entered.complete();
            await release.future;
          }
        },
        isCurrent: () => active,
      );
      s.acquire(lease);
      try {
        await s.insert(pending, lease);
        hold = true;
        final claim = s.claim(pending, lease);
        final checked = expectLater(claim, throwsStateError);
        await entered.future;
        active = false;
        release.complete();
        await checked;
        expect(
          TopicCreationAttempt.decode(raw!).phase,
          TopicCreationPhase.unknown,
        );
      } finally {
        s.release(lease);
      }
    },
  );
}
