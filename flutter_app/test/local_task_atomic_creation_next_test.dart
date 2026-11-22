import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/local_task_atomic_creation.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
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
  const scope =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  TaskCreationAttempt input(String key, {int parent = 0, bool done = true}) =>
      TaskCreationAttempt(
        scope: scope,
        key: key,
        body: {
          'content': 'Ordinary full task',
          'due_date': '2026-11-20',
          'done': done,
          'parent_id': parent,
          'topic_id': 9,
        },
      );
  Future<LocalStore> fresh() async {
    final dir = await Directory.systemTemp.createTemp('task10-atomic-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStore(
      path: dir.path + '/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    await store.database;
    return store;
  }

  Future<List<Object?>> exact(LocalStore store) async {
    final db = await store.database;
    return [
      await db.rawQuery('SELECT * FROM tasks ORDER BY task_id'),
      await db.rawQuery(
        'SELECT * FROM assistant_creation_receipts ORDER BY creation_key',
      ),
      await db.rawQuery('SELECT * FROM sqlite_sequence ORDER BY name'),
    ];
  }

  test(
    'receipt insert trigger failure rolls task and every sequence back',
    () async {
      final store = await fresh();
      final db = await store.database;
      final parent = await LocalTasksRepository(store).save(
        const TaskItem(content: 'Untouched parent', dueDate: '2026-11-19'),
      );
      final before = await exact(store);
      await db.execute(
        "CREATE TRIGGER task10_receipt_fail BEFORE INSERT ON assistant_creation_receipts BEGIN SELECT RAISE(ABORT,'TASK10_CONTROLLED'); END",
      );
      final creator = LocalTaskAtomicCreation(
        store,
        scope: scope,
        isCurrent: () => true,
      );
      var claims = 0;
      await expectLater(
        creator.create(
          input('b' * 32, parent: parent),
          onSubmit: () async {
            claims++;
          },
        ),
        throwsA(anything),
      );
      expect(claims, 1);
      expect(await exact(store), before);
      await db.execute('DROP TRIGGER task10_receipt_fail');
    },
  );
  test(
    'task INSERT failure and owner retirement after claim both make no changes',
    () async {
      final store = await fresh();
      final db = await store.database;
      var active = true;
      final creator = LocalTaskAtomicCreation(
        store,
        scope: scope,
        isCurrent: () => active,
      );
      final before = await exact(store);
      await db.execute(
        "CREATE TRIGGER task10_task_fail BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT,'TASK10_TASK'); END",
      );
      await expectLater(
        creator.create(input('c' * 32), onSubmit: () async {}),
        throwsA(anything),
      );
      expect(await exact(store), before);
      await db.execute('DROP TRIGGER task10_task_fail');
      await expectLater(
        creator.create(
          input('d' * 32),
          onSubmit: () async {
            active = false;
          },
        ),
        throwsStateError,
      );
      active = true;
      expect(await exact(store), before);
    },
  );
  test(
    'commit ACK failure cold inspect uses exact receipt and never repeats INSERT',
    () async {
      final store = await fresh();
      final parent = await LocalTasksRepository(store).save(
        const TaskItem(content: 'Parent remains exact', dueDate: '2026-11-19'),
      );
      final creator = LocalTaskAtomicCreation(
        store,
        scope: scope,
        isCurrent: () => true,
      );
      final frozen = input('e' * 32, parent: parent);
      await expectLater(
        creator.create(
          frozen,
          onSubmit: () async {},
          afterCommit: (_) async {
            throw StateError('ACK lost after commit');
          },
        ),
        throwsStateError,
      );
      final committed = await exact(store);
      final cold = LocalTaskAtomicCreation(
        store,
        scope: scope,
        isCurrent: () => true,
      );
      final review = await cold.inspect(frozen);
      expect(review.state, LocalTaskCreationState.matching);
      expect(review.row!['parent_id'], parent);
      expect(review.row!['topic_id'], 9);
      expect(review.row!['done'], 1);
      expect(review.row!['complete_time'], isNotNull);
      await expectLater(
        cold.create(frozen, onSubmit: () async {}),
        throwsStateError,
      );
      expect(await exact(store), committed);
      // A genuine later edit changes the full tuple/fingerprint without re-creating.
      final db = await store.database;
      await db.update(
        'tasks',
        {'modify_time': '2099-01-01T00:00:00Z'},
        where: 'task_id=?',
        whereArgs: [review.id],
      );
      final changed = await cold.inspect(frozen);
      expect(changed.fingerprint, isNot(review.fingerprint));
    },
  );
  test(
    'wrong captured generation scope cannot claim or inspect receipt',
    () async {
      final store = await fresh();
      var claims = 0;
      final creator = LocalTaskAtomicCreation(
        store,
        scope: 'f' * 64,
        isCurrent: () => true,
      );
      await expectLater(
        creator.create(
          input('f' * 32),
          onSubmit: () async {
            claims++;
          },
        ),
        throwsFormatException,
      );
      await expectLater(
        creator.inspect(input('f' * 32)),
        throwsFormatException,
      );
      expect(claims, 0);
    },
  );
  test(
    'legacy version refuses before receipt query or durable claim, never migrates',
    () async {
      final store = await fresh();
      final db = await store.database;
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.execute('PRAGMA user_version=14');
      final rows = await db.rawQuery('SELECT * FROM tasks');
      var claims = 0;
      final creator = LocalTaskAtomicCreation(
        store,
        scope: scope,
        isCurrent: () => true,
      );
      await expectLater(
        creator.create(
          input('0' * 32),
          onSubmit: () async {
            claims++;
          },
        ),
        throwsFormatException,
      );
      await expectLater(
        creator.inspect(input('0' * 32)),
        throwsFormatException,
      );
      expect(claims, 0);
      expect(await db.getVersion(), 14);
      expect(await db.rawQuery('SELECT * FROM tasks'), rows);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='assistant_creation_receipts'",
        ),
        isEmpty,
      );
    },
  );
}
