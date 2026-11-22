// Test/visual fixture only. No production entry point imports this file.
import 'dart:async';
import 'package:bookstark_flutter/core/tasks_repository.dart';

class TaskFixture implements TasksRepository {
  TaskFixture({bool sample = true, DateTime? today})
    : now = today ?? DateTime.now() {
    if (sample) {
      final due = taskDate(now);
      records.addAll({
        1: TaskItem(id: 1, content: '每天阅读20分钟', dueDate: due),
        2: TaskItem(id: 2, content: '记录一个可执行的观点', dueDate: due, parentId: 1),
        3: TaskItem(id: 3, content: '整理本周的学习笔记', dueDate: due),
        4: TaskItem(
          id: 4,
          content: '完成 Flutter 阅读器设计',
          dueDate: taskDate(DateTime(now.year, now.month, now.day + 4)),
        ),
      });
    }
  }
  final DateTime now;
  final records = <int, TaskItem>{};
  final queries = <TaskQuery>[];
  final doneCalls = <(int, bool)>[];
  final removed = <int>[];
  final countQueries = <(int, int)>[];
  final saved = <TaskItem>[];
  Completer<void>? doneGate;
  Completer<TaskPage>? delayedSearch;
  bool failDone = false, failList = false, failCounts = false;
  TaskItem _fresh(TaskItem item) {
    final children = records.values
        .where((child) => child.parentId == item.id)
        .toList();
    return TaskItem(
      id: item.id,
      content: item.content,
      dueDate: item.dueDate,
      done: item.done,
      parentId: item.parentId,
      topicId: item.topicId,
      childTotal: children.length,
      childDone: children.where((child) => child.done).length,
      modifiedAt: item.modifiedAt ?? now.toIso8601String(),
      completedAt: item.completedAt,
    );
  }

  @override
  Future<TaskPage> list(TaskQuery query) async {
    queries.add(query);
    if (failList) throw StateError('测试读取失败');
    if (query.keyword == '旧' && delayedSearch != null) {
      return delayedSearch!.future;
    }
    final items = records.values
        .map(_fresh)
        .where(
          (item) =>
              (query.done == null || item.done == query.done) &&
              (query.parentId == null || item.parentId == query.parentId) &&
              (query.topicId == null || item.topicId == query.topicId) &&
              (query.keyword.isEmpty || item.content.contains(query.keyword)) &&
              (query.dueOn.isEmpty || item.dueDate == query.dueOn) &&
              (query.dueBefore.isEmpty ||
                  (item.dueDate.isNotEmpty &&
                      item.dueDate.compareTo(query.dueBefore) <= 0)) &&
              (query.dueAfter.isEmpty ||
                  item.dueDate.isEmpty ||
                  item.dueDate.compareTo(query.dueAfter) > 0) &&
              (query.modifiedOn.isEmpty ||
                  item.modifiedAt!.startsWith(query.modifiedOn)),
        )
        .toList();
    items.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final date = a.dueDate.compareTo(b.dueDate);
      return date != 0 ? date : a.id!.compareTo(b.id!);
    });
    return TaskPage(
      items: items
          .skip((query.page - 1) * query.pageSize)
          .take(query.pageSize)
          .toList(),
      total: items.length,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<TaskItem> read(int id) async {
    final item = records[id];
    if (item == null) throw StateError('找不到测试待办');
    return _fresh(item);
  }

  @override
  Future<int> save(TaskItem task) async {
    final body = task.writeBody();
    saved.add(task);
    final id =
        task.id ?? (records.keys.fold<int>(0, (a, b) => a > b ? a : b) + 1);
    records[id] = TaskItem(
      id: id,
      content: body['content'] as String,
      dueDate: task.dueDate,
      done: task.done,
      parentId: task.parentId,
      topicId: task.topicId ?? records[id]?.topicId,
      modifiedAt: now.toIso8601String(),
      completedAt: task.done ? now.toIso8601String() : null,
    );
    return id;
  }

  @override
  Future<void> setDone(int id, bool done) async {
    doneCalls.add((id, done));
    await doneGate?.future;
    if (failDone) throw StateError('测试更新失败');
    final item = await read(id);
    records[id] = TaskItem(
      id: id,
      content: item.content,
      dueDate: item.dueDate,
      done: done,
      parentId: item.parentId,
      topicId: item.topicId,
      modifiedAt: now.toIso8601String(),
      completedAt: done ? now.toIso8601String() : null,
    );
  }

  @override
  Future<void> remove(int id) async {
    removed.add(id);
    final ids = <int>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final item in records.values) {
        if (ids.contains(item.parentId) && ids.add(item.id!)) changed = true;
      }
    }
    for (final id in ids) {
      records.remove(id);
    }
  }

  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) async {
    countQueries.add((year, month));
    if (failCounts) throw StateError('测试日历读取失败');
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final counts = <String, List<int>>{};
    for (final record in records.values.map(_fresh)) {
      final date = record.modifiedAt!.substring(0, 10);
      if (!date.startsWith(prefix)) continue;
      final count = counts.putIfAbsent(date, () => [0, 0, 0]);
      count[0]++;
      count[record.done ? 1 : 2]++;
    }
    final dates = counts.keys.toList()..sort();
    return [
      for (final date in dates)
        TaskDailyCount(
          date,
          counts[date]![0],
          counts[date]![1],
          counts[date]![2],
        ),
    ];
  }
}
