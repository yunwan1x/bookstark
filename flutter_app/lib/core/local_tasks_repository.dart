import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'local_store.dart';
import 'tasks_repository.dart';

class LocalTasksRepository implements TasksRepository {
  LocalTasksRepository(this.store);
  final LocalStore store;
  static const _columns = '''SELECT t.*,
    (SELECT COUNT(*) FROM tasks child WHERE child.parent_id = t.task_id AND child.deleted = 0) AS child_total,
    (SELECT COUNT(*) FROM tasks child WHERE child.parent_id = t.task_id AND child.deleted = 0 AND child.done = 1) AS child_done
    FROM tasks t''';
  TaskItem _item(Map<String, Object?> row) =>
      TaskItem.fromJson({...row, 'done': row['done'] == 1});
  void _id(int id) {
    if (id <= 0) throw ArgumentError.value(id);
  }

  Future<Map<String, Object?>> _read(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        _id(id);
        final rows = await db.rawQuery(
          '$_columns WHERE t.task_id = ? AND t.deleted = 0',
          [id],
        );
        if (rows.isEmpty) throw StateError('待办不存在 / Task no longer exists');
        return rows.single;
      });

  @override
  Future<TaskItem> read(int id) => store.maintenance.use(
    () async => _item(await _read(await store.database, id)),
  );
  @override
  Future<TaskPage> list(TaskQuery query) => store.maintenance.use(() async {
    query.parameters();
    final where = ['t.deleted = 0'];
    final args = <Object?>[];
    if (query.keyword.trim().isNotEmpty) {
      where.add("t.content LIKE ? ESCAPE '\\'");
      final keyword = query.keyword
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      args.add('%$keyword%');
    }
    if (query.done != null) {
      where.add('t.done = ?');
      args.add(query.done! ? 1 : 0);
    }
    if (query.parentId != null) {
      where.add('t.parent_id = ?');
      args.add(query.parentId);
    }
    if (query.topicId != null) {
      where.add('t.topic_id = ?');
      args.add(query.topicId);
    }
    if (query.dueOn.isNotEmpty) {
      where.add('t.due_date = ?');
      args.add(query.dueOn);
    }
    if (query.dueBefore.isNotEmpty) {
      where.add("t.due_date != '' AND t.due_date <= ?");
      args.add(query.dueBefore);
    }
    if (query.dueAfter.isNotEmpty) {
      where.add("(t.due_date = '' OR t.due_date > ?)");
      args.add(query.dueAfter);
    }
    if (query.modifiedOn.isNotEmpty) {
      where.add('substr(t.modify_time, 1, 10) = ?');
      args.add(query.modifiedOn);
    }
    final conditions = where.join(' AND ');
    return (await store.database).transaction((tx) async {
      final total = Sqflite.firstIntValue(
        await tx.rawQuery(
          'SELECT COUNT(*) FROM tasks t WHERE $conditions',
          args,
        ),
      )!;
      final rows = await tx.rawQuery(
        "$_columns WHERE $conditions ORDER BY t.done ASC, CASE WHEN t.due_date = '' THEN 1 ELSE 0 END, t.due_date ASC, t.modify_time DESC, t.task_id DESC LIMIT ? OFFSET ?",
        [...args, query.pageSize, (query.page - 1) * query.pageSize],
      );
      return TaskPage(
        items: rows.map(_item).toList(),
        total: total,
        page: query.page,
        pageSize: query.pageSize,
      );
    });
  });

  @override
  Future<int> save(TaskItem task) => store.maintenance.use(() async {
    final body = task.writeBody();
    return (await store.database).transaction((tx) async {
      Map<String, Object?>? old;
      if (task.id != null) old = await _read(tx, task.id!);
      final visited = <int>{if (task.id != null) task.id!};
      var parent = task.parentId;
      while (parent != 0) {
        if (!visited.add(parent)) {
          throw StateError(
            '父待办不能形成循环 / Parent relationship would form a cycle',
          );
        }
        parent = (await _read(tx, parent))['parent_id'] as int;
      }
      final now = DateTime.now().toIso8601String();
      final values = <String, Object?>{
        'content': body['content'],
        'due_date': task.dueDate,
        'done': task.done ? 1 : 0,
        'parent_id': task.parentId,
        'topic_id': task.topicId ?? old?['topic_id'] ?? 0,
        'modify_time': now,
        'complete_time': task.done ? (old?['complete_time'] ?? now) : null,
      };
      if (task.id == null) {
        return tx.insert('tasks', {...values, 'create_time': now});
      }
      final count = await tx.update(
        'tasks',
        values,
        where: 'task_id = ? AND deleted = 0',
        whereArgs: [task.id],
      );
      if (count != 1) throw StateError('待办不存在 / Task no longer exists');
      return task.id!;
    });
  });

  @override
  Future<void> setDone(int id, bool done) => store.maintenance.use(() async {
    _id(id);
    final now = DateTime.now().toIso8601String();
    final count = await (await store.database).update(
      'tasks',
      {
        'done': done ? 1 : 0,
        'modify_time': now,
        'complete_time': done ? now : null,
      },
      where: 'task_id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('待办不存在 / Task no longer exists');
  });

  @override
  Future<void> remove(int id) => store.maintenance.use(() async {
    _id(id);
    await (await store.database).transaction((tx) async {
      final root = await _read(tx, id);
      const subtree = '''WITH RECURSIVE subtree(task_id) AS (
        SELECT task_id FROM tasks WHERE task_id = ? AND deleted = 0
        UNION SELECT child.task_id FROM tasks child JOIN subtree parent ON child.parent_id = parent.task_id WHERE child.deleted = 0
      )''';
      final rows = await tx.rawQuery(
        '$subtree SELECT t.* FROM tasks t JOIN subtree ON t.task_id = subtree.task_id ORDER BY t.task_id',
        [id],
      );
      await tx.insert('trash_entries', {
        'resource_type': 'task',
        'resource_id': id,
        'name': String.fromCharCodes(
          (root['content'] as String).split('\n').first.runes.take(80),
        ),
        'payload': jsonEncode({'version': 1, 'root_id': id, 'items': rows}),
        'deleted_at': DateTime.now().toIso8601String(),
      });
      await tx.rawUpdate(
        '$subtree UPDATE tasks SET deleted = 1 WHERE task_id IN (SELECT task_id FROM subtree)',
        [id],
      );
    });
  });

  @override
  Future<List<TaskDailyCount>> dailyCounts(
    int year,
    int month,
  ) => store.maintenance.use(() async {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw ArgumentError('Invalid month');
    }
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final rows = await (await store.database).rawQuery(
      '''SELECT substr(modify_time, 1, 10) AS date,
      COUNT(*) AS count, SUM(done) AS done_count, SUM(1-done) AS active_count
      FROM tasks WHERE deleted = 0 AND substr(modify_time, 1, 7) = ?
      GROUP BY substr(modify_time, 1, 10) ORDER BY date''',
      [prefix],
    );
    return rows.map(TaskDailyCount.fromJson).toList();
  });
}
