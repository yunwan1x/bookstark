import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/local_task_creation_session.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_guarded_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux)
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
  });
  Future<LocalStore> fresh() async {
    final dir = await Directory.systemTemp.createTemp('task10-session-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStore(
      path: dir.path + '/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    await store.database;
    return store;
  }

  Future<List<Object?>> snapshot(LocalStore store) async {
    final db = await store.database;
    return [
      await db.rawQuery('SELECT * FROM tasks ORDER BY task_id'),
      await db.rawQuery(
        'SELECT * FROM assistant_creation_receipts ORDER BY creation_key',
      ),
      await db.rawQuery('SELECT * FROM sqlite_sequence ORDER BY name'),
    ];
  }

  const draft = TaskItem(
    content: 'Local ordinary task',
    dueDate: '2026-11-20',
    done: true,
    topicId: 9,
  );
  test(
    'committed receipt cold recovery never inserts again and preserves all tuples',
    () async {
      final store = await fresh(), values = <String, String>{};
      LocalTaskCreationSession create({bool loseAck = false}) =>
          LocalTaskCreationSession(
            store: store,
            namespace: 'local-generation:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            isCurrent: () => true,
            read: (k) async => values[k],
            write: (k, v) async {
              values[k] = v;
            },
            remove: (k) async {
              values.remove(k);
            },
            flush: () async {},
            afterCommit: loseAck
                ? (_) async {
                    throw StateError('ACK lost');
                  }
                : null,
          );
      var owner = create(loseAck: true);
      try {
        await expectLater(
          owner.wrap(LocalTasksRepository(store)).save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        final committed = await snapshot(store);
        expect((committed[0] as List).length, 1);
        expect((committed[1] as List).length, 1);
        await owner.retire();
        owner = create();
        final c = await owner.open();
        expect(c.record!.phase, TaskCreationPhase.unknown);
        await expectLater(
          owner.wrap(LocalTasksRepository(store)).save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        expect(await snapshot(store), committed);
        await c.review(0);
        expect(c.reviewed!.id, greaterThan(0));
        expect(c.reviewed!.matchesFrozenInput, true);
        await c.adopt(c.reviewed!);
        expect(
          c.record!.origin,
          TaskCreationOrigin.localTransactionAcknowledgement,
        );
        expect(await snapshot(store), committed);
        await c.end(c.record!);
        await owner.clearEndedSlot();
        expect(values, isEmpty);
        expect(await snapshot(store), committed);
      } finally {
        await owner.retire();
      }
    },
  );
  test(
    'known local ACK flush retry is storage-only with zero extra UPDATE/INSERT',
    () async {
      final store = await fresh(), values = <String, String>{};
      var failKnown = true;
      final owner = LocalTaskCreationSession(
        store: store,
        namespace: 'local-generation:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {
          if (failKnown &&
              values.values.any((v) => v.contains('"phase":"knownID"'))) {
            throw StateError('controlled known metadata barrier');
          }
        },
      );
      try {
        await expectLater(
          owner.wrap(LocalTasksRepository(store)).save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        final before = await snapshot(store);
        final c = owner.controller!;
        expect(c.hasKnownAcknowledgement, true);
        failKnown = false;
        await c.retryAcknowledgement();
        expect(
          c.record!.origin,
          TaskCreationOrigin.localTransactionAcknowledgement,
        );
        expect(await snapshot(store), before);
      } finally {
        await owner.retire();
      }
    },
  );
  test(
    'owner retired at durable claim leaves full journal but zero local mutations',
    () async {
      final store = await fresh(), values = <String, String>{};
      var active = true;
      final before = await snapshot(store);
      final owner = LocalTaskCreationSession(
        store: store,
        namespace: 'local-generation:cccccccccccccccccccccccccccccccc',
        isCurrent: () => active,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {
          if (values.values.any((v) => v.contains('"phase":"unknown"')))
            active = false;
        },
      );
      try {
        await expectLater(
          owner.wrap(LocalTasksRepository(store)).save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        expect(await snapshot(store), before);
        expect(
          values.values.any((v) => v.contains('Local ordinary task')),
          true,
        );
      } finally {
        await owner.retire();
      }
    },
  );
}
