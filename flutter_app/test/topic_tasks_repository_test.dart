import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topic_tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/tasks.dart';

void main() {
  TaskFixture data() {
    final fixture = TaskFixture(sample: false, today: DateTime(2026, 11, 4));
    fixture.records.addAll({
      1: const TaskItem(
        id: 1,
        content: '当前主题',
        dueDate: '2026-11-04',
        topicId: 4,
      ),
      2: const TaskItem(
        id: 2,
        content: '其他主题',
        dueDate: '2026-11-04',
        topicId: 5,
      ),
      3: const TaskItem(id: 3, content: '无主题', dueDate: '2026-11-04'),
    });
    return fixture;
  }

  test(
    'every task query stays in topic and outside IDs cannot be edited',
    () async {
      final delegate = data();
      final scoped = TopicTasksRepository(delegate, 4);
      expect((await scoped.list(const TaskQuery())).items.single.id, 1);
      expect(delegate.queries.single.topicId, 4);
      await expectLater(scoped.read(2), throwsStateError);
      await expectLater(scoped.setDone(2, true), throwsStateError);
      expect(delegate.doneCalls, isEmpty);
      await expectLater(
        scoped.save(
          const TaskItem(
            id: 2,
            content: '不覆盖',
            dueDate: '2026-11-04',
            topicId: 4,
          ),
        ),
        throwsStateError,
      );
      expect(delegate.saved, isEmpty);
      expect(const TaskQuery(topicId: 4).parameters()['topic_id'], '4');
      expect(
        () => const TaskQuery(topicId: 0).parameters(),
        throwsFormatException,
      );
    },
  );
  test(
    'new topic tasks inherit real topic and reject foreign parent',
    () async {
      final delegate = data();
      final scoped = TopicTasksRepository(delegate, 4);
      final id = await scoped.save(
        const TaskItem(content: '新任务', dueDate: '2026-11-04'),
      );
      expect(delegate.records[id]!.topicId, 4);
      await expectLater(
        scoped.save(
          const TaskItem(content: '错误父项', dueDate: '2026-11-04', parentId: 2),
        ),
        throwsStateError,
      );
      await expectLater(
        scoped.save(
          const TaskItem(content: '错误主题', dueDate: '2026-11-04', topicId: 5),
        ),
        throwsStateError,
      );
      expect(delegate.saved.length, 1);
    },
  );
  test(
    'topic subtree deletion refuses legacy cross-topic descendants',
    () async {
      final delegate = data();
      delegate.records[4] = const TaskItem(
        id: 4,
        content: '异主题子项',
        dueDate: '2026-11-04',
        parentId: 1,
        topicId: 5,
      );
      final scoped = TopicTasksRepository(delegate, 4);
      await expectLater(scoped.remove(1), throwsStateError);
      expect(delegate.removed, isEmpty);
      expect(delegate.records.containsKey(1), isTrue);
      expect(delegate.records.containsKey(4), isTrue);
    },
  );
  test('topic task calendar counts scoped modification days only', () async {
    final delegate = data();
    final scoped = TopicTasksRepository(delegate, 4);
    final days = await scoped.dailyCounts(2026, 11);
    expect(days.single.date, '2026-11-04');
    expect(days.single.total, 1);
    expect(days.single.active, 1);
  });
}
