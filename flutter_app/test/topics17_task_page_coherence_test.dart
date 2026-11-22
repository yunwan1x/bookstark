import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topic_tasks_repository.dart';
import '../tool/fixtures/tasks.dart';

class PagedTasks extends TaskFixture {
  PagedTasks({
    this.changed = false,
    this.zeroSize = false,
    this.duplicate = false,
  }) : super(sample: false);
  final bool changed, zeroSize, duplicate;
  final pages = <int>[];
  @override
  Future<TaskPage> list(TaskQuery query) async {
    pages.add(query.page);
    final start = (query.page - 1) * query.pageSize + 1;
    final rows = [
      for (var id = start; id <= 101 && id < start + query.pageSize; id++)
        TaskItem(
          id: duplicate ? 1 : id,
          topicId: 4,
          dueDate: '2026-11-11',
          content: 'task $id',
          modifiedAt: '2026-11-11T12:00:00',
        ),
    ];
    return TaskPage(
      items: rows,
      total: changed && query.page > 1 ? 102 : 101,
      page: query.page,
      pageSize: zeroSize ? 0 : query.pageSize,
    );
  }
}

class ChangingChildren extends TaskFixture {
  ChangingChildren() : super(sample: false) {
    records[1] = const TaskItem(
      id: 1,
      topicId: 4,
      dueDate: '2026-11-11',
      content: 'parent',
    );
  }
  int removeCalls = 0;
  @override
  Future<TaskPage> list(TaskQuery query) async {
    if (query.parentId != 1) {
      return TaskPage(
        items: const [],
        total: 0,
        page: query.page,
        pageSize: query.pageSize,
      );
    }
    final start = (query.page - 1) * 100 + 2;
    return TaskPage(
      items: [
        for (var id = start; id <= 102 && id < start + 100; id++)
          TaskItem(
            id: id,
            topicId: 4,
            parentId: 1,
            dueDate: '2026-11-11',
            content: 'child $id',
          ),
      ],
      total: query.page == 1 ? 101 : 102,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<void> remove(int id) async {
    removeCalls++;
    await super.remove(id);
  }
}

void main() {
  test(
    'actual topic calendar traverses beyond100 and counts101 once',
    () async {
      final delegate = PagedTasks();
      final actual = TopicTasksRepository(delegate, 4);
      final counts = await actual.dailyCounts(2026, 11);
      expect(counts.single.total, 101);
      expect(delegate.pages, [1, 2]);
    },
  );
  test(
    'changed total, zero size and duplicate IDs cannot become successful task calendars',
    () async {
      for (final delegate in [
        PagedTasks(changed: true),
        PagedTasks(zeroSize: true),
        PagedTasks(duplicate: true),
      ]) {
        await expectLater(
          TopicTasksRepository(delegate, 4).dailyCounts(2026, 11),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'child page drift aborts scoped subtree preflight before any destructive delegate call',
    () async {
      final delegate = ChangingChildren();
      await expectLater(
        TopicTasksRepository(delegate, 4).remove(1),
        throwsFormatException,
      );
      expect(delegate.removeCalls, 0);
      expect(delegate.records.containsKey(1), isTrue);
    },
  );
}
