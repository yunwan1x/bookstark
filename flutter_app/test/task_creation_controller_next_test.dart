import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_store.dart';
import 'package:bookstark_flutter/core/task_creation_controller.dart';

void main() {
  test('cold pending is readonly and cannot even prepare HTTP', () async {
    final scope = '1' * 64, key = '2' * 32;
    final pending = TaskCreationAttempt(
      scope: scope,
      key: key,
      body: {
        'content': 'Frozen full body',
        'due_date': '2026-11-20',
        'done': false,
        'parent_id': 7,
        'topic_id': 9,
      },
    );
    String? raw = pending.encode();
    var prepares = 0;
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
      flush: () async {},
      isCurrent: () => true,
    );
    final c = TaskCreationController(
      store: store,
      prepare: (_) async {
        prepares++;
        throw StateError('must not prepare');
      },
      inspect: (_, _) async => throw StateError('not requested'),
    );
    try {
      await c.reload();
      await c.submit();
      await c.submit();
      expect(prepares, 0);
      expect(raw, pending.encode());
      expect(c.record!.body['content'], 'Frozen full body');
    } finally {
      c.dispose();
    }
  });
  test(
    'manual association fresh change retains unknown and full snapshot',
    () async {
      final scope = '3' * 64, key = '4' * 32;
      final unknown = TaskCreationAttempt(
        scope: scope,
        key: key,
        phase: TaskCreationPhase.unknown,
        body: {
          'content': 'Original',
          'due_date': '2026-11-20',
          'done': true,
          'parent_id': 7,
          'topic_id': 9,
        },
      );
      String? raw = unknown.encode();
      var reads = 0;
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
        flush: () async {},
        isCurrent: () => true,
      );
      final c = TaskCreationController(
        store: store,
        prepare: (_) async => throw StateError('no POST'),
        inspect: (_, id) async => TaskCreationReview(
          id: id,
          fingerprint: (++reads).toString(),
          display: 'Actual',
          matchesFrozenInput: true,
          wire: {'task_id': id},
        ),
      );
      try {
        await c.reload();
        await c.review(41);
        await c.adopt(c.reviewed!);
        expect(raw, unknown.encode());
        expect(c.record!.actualId, isNull);
        expect(c.record!.body['done'], true);
        expect(reads, 2);
      } finally {
        c.dispose();
      }
    },
  );
}
