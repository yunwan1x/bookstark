import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_store.dart';

void main() {
  TaskCreationAttempt input(String scope, String key) => TaskCreationAttempt(
    scope: scope,
    key: key,
    body: {
      'content': 'Actual task',
      'due_date': '2026-11-20',
      'done': false,
      'parent_id': 7,
      'topic_id': 9,
    },
  );
  test(
    'strict claim never grants a second submission; known ID cannot retarget',
    () async {
      final scope = 'a' * 64, key = 'b' * 32;
      String? raw;
      var flushes = 0;
      final store = TaskCreationStore(
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
      final lease = Object();
      store.acquire(lease);
      try {
        final pending = input(scope, key);
        await store.insert(pending, lease);
        await store.claim(pending, lease);
        await expectLater(
          store.claim(pending, lease),
          throwsA(isA<TaskCreationStorageUnconfirmed>()),
        );
        final unknown = (await store.load())!;
        await store.acknowledge(
          unknown,
          41,
          lease,
          origin: TaskCreationOrigin.postAcknowledgement,
        );
        final known = (await store.load())!;
        await expectLater(
          store.acknowledge(
            known,
            42,
            lease,
            origin: TaskCreationOrigin.postAcknowledgement,
          ),
          throwsStateError,
        );
        expect((await store.load())!.actualId, 41);
        expect(flushes, 3);
      } finally {
        store.release(lease);
      }
    },
  );
  test(
    'failed durable claim cannot authorize request and survives cold read',
    () async {
      final scope = 'c' * 64, key = 'd' * 32;
      String? raw;
      var fail = false;
      final store = TaskCreationStore(
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
          if (fail) throw StateError('barrier');
        },
        isCurrent: () => true,
      );
      final lease = Object();
      store.acquire(lease);
      try {
        final pending = input(scope, key);
        await store.insert(pending, lease);
        fail = true;
        var sends = 0;
        try {
          await store.claim(pending, lease);
          sends++;
        } catch (_) {}
        expect(sends, 0);
        expect((await store.load())!.phase, TaskCreationPhase.unknown);
      } finally {
        store.release(lease);
      }
    },
  );
  test('retirement during fresh clear read retains recovery record', () async {
    final scope = 'e' * 64, key = 'f' * 32;
    var current = true, retireRead = false;
    String? raw;
    final store = TaskCreationStore(
      scope: scope,
      key: key,
      read: (_) async {
        if (retireRead) current = false;
        return raw;
      },
      write: (_, v) async {
        raw = v;
      },
      remove: (_) async {
        raw = null;
      },
      flush: () async {},
      isCurrent: () => current,
    );
    final lease = Object();
    store.acquire(lease);
    final pending = input(scope, key);
    try {
      await store.insert(pending, lease);
      retireRead = true;
      await expectLater(store.end(pending, lease), throwsStateError);
      expect(raw, pending.encode());
    } finally {
      store.release(lease);
    }
  });
}
