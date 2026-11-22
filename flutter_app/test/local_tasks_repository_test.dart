import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  Future<LocalStore> storeForTest() async {
    final directory = await Directory.systemTemp.createTemp('bookstark-tasks-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    return store;
  }

  test(
    'v3 notes upgrade adds tasks without changing existing IDs or article content',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-tasks-upgrade-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/data.db';
      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(
              "CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, labels TEXT NOT NULL DEFAULT '[]', collection TEXT NOT NULL DEFAULT 'note')",
            );
            await db.execute(
              "CREATE UNIQUE INDEX notes_article_title ON notes(title) WHERE collection = 'article' AND deleted = 0",
            );
          },
        ),
      );
      final id = await old.insert('notes', {
        'title': '已有文章',
        'content': '# 需要保留的正文',
        'updated_at': 123,
        'collection': 'article',
      });
      await old.close();
      var store = LocalStore(path: path, factory: databaseFactoryFfiNoIsolate);
      var repository = LocalTasksRepository(store);
      final taskId = await repository.save(
        const TaskItem(
          content: '**真实本地待办**',
          dueDate: '2026-11-08',
          done: true,
        ),
      );
      await store.close();
      store = LocalStore(path: path, factory: databaseFactoryFfiNoIsolate);
      addTearDown(store.close);
      repository = LocalTasksRepository(store);
      expect(
        (await store.readNote(id, collection: 'article'))['content'],
        '# 需要保留的正文',
      );
      final task = await repository.read(taskId);
      expect(task.content, '**真实本地待办**');
      expect(task.done, isTrue);
      expect(task.completedAt, isNotNull);
      await repository.setDone(taskId, false);
      expect((await repository.read(taskId)).completedAt, isNull);
    },
  );
  test(
    'parent validation prevents cycles/orphans; deletion snapshots exactly the child subtree',
    () async {
      final store = await storeForTest();
      final repository = LocalTasksRepository(store);
      final root = await repository.save(
        const TaskItem(content: '根', dueDate: '2026-11-08'),
      );
      final child = await repository.save(
        TaskItem(content: '子', dueDate: '2026-11-08', parentId: root),
      );
      final grandchild = await repository.save(
        TaskItem(content: '孙', dueDate: '2026-11-08', parentId: child),
      );
      await expectLater(
        repository.save(
          TaskItem(
            id: root,
            content: '错误循环',
            dueDate: '2026-11-08',
            parentId: grandchild,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        repository.save(
          const TaskItem(content: '孤儿', dueDate: '2026-11-08', parentId: 9999),
        ),
        throwsStateError,
      );
      expect((await repository.list(const TaskQuery())).total, 3);
      expect((await repository.read(root)).childTotal, 1);
      await repository.setDone(child, true);
      expect((await repository.read(root)).childDone, 1);
      await repository.remove(child);
      expect((await repository.list(const TaskQuery())).items.single.id, root);
      expect((await repository.read(root)).childTotal, 0);
      await expectLater(repository.read(grandchild), throwsStateError);
      final db = await store.database;
      final trash = (await db.query('trash_entries')).single;
      final payload = jsonDecode(trash['payload'] as String) as Map;
      expect(payload['root_id'], child);
      expect((payload['items'] as List).map((row) => row['task_id']), [
        child,
        grandchild,
      ]);
      expect((await db.query('tasks', where: 'deleted = 1')).length, 2);
      await expectLater(
        repository.save(
          TaskItem(content: '已删父级', dueDate: '2026-11-08', parentId: child),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'local task pagination and literal search apply before limit with exact totals',
    () async {
      final repository = LocalTasksRepository(await storeForTest());
      for (var i = 0; i < 35; i++) {
        await repository.save(
          TaskItem(
            content: i == 0 ? '100% 阅读' : '待办 $i',
            dueDate: '2026-11-08',
            done: i % 3 == 0,
          ),
        );
      }
      await repository.save(
        const TaskItem(content: '100x 阅读', dueDate: '2026-11-09'),
      );
      final third = await repository.list(
        const TaskQuery(page: 3, pageSize: 10),
      );
      expect(third.total, 36);
      expect(third.items.length, 10);
      expect(third.hasMore, isTrue);
      final last = await repository.list(
        const TaskQuery(page: 4, pageSize: 10),
      );
      expect(last.items.length, 6);
      expect(last.hasMore, isFalse);
      expect(
        (await repository.list(const TaskQuery(keyword: '100%'))).total,
        1,
      );
      expect((await repository.list(const TaskQuery(done: true))).total, 12);
      expect(
        (await repository.list(const TaskQuery(dueOn: '2026-11-08'))).total,
        35,
      );
    },
  );
  test(
    'calendar groups stored modification dates independently of due dates and time zones',
    () async {
      final store = await storeForTest();
      final repository = LocalTasksRepository(store);
      final id = await repository.save(
        const TaskItem(content: '跨时区修改记录', dueDate: '2027-01-08', done: true),
      );
      final db = await store.database;
      await db.update(
        'tasks',
        {'modify_time': '2026-11-01T00:10:00+14:00'},
        where: 'task_id = ?',
        whereArgs: [id],
      );
      final counts = await repository.dailyCounts(2026, 11);
      expect(counts.single.date, '2026-11-01');
      expect(counts.single.total, 1);
      expect(counts.single.done, 1);
      expect((await repository.dailyCounts(2026, 10)), isEmpty);
      expect(
        (await repository.list(
          const TaskQuery(modifiedOn: '2026-11-01'),
        )).items.single.id,
        id,
      );
      expect(
        (await repository.list(const TaskQuery(dueOn: '2026-11-01'))).items,
        isEmpty,
      );
    },
  );
}
