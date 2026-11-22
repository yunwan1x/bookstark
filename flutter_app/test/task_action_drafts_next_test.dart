import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

import 'package:bookstark_flutter/core/task_action_drafts.dart';

class FakeTopics implements TopicsRepository {
  @override
  int get memberId => 7;
  int reads = 0;
  List<TopicItem> items = [
    const TopicItem(id: 9, title: 'Launch', memberId: 7),
  ];
  @override
  Future<TopicPageResult> list(TopicQuery query) async =>
      TopicPageResult(items, items.length, query.page, 20);
  @override
  Future<TopicDetail> read(int id) async {
    reads++;
    return TopicDetail(
      topic: items.first,
      summaries: [],
      resources: [],
      loadedTasks: [],
      commentCount: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No writes allowed');
}

TaskItem task() => const TaskItem(
  id: 42,
  content: '\ufeffOriginal😀\r\n',
  dueDate: '2026-12-04',
  done: true,
  parentId: 11,
  topicId: 9,
  childTotal: 3,
  childDone: 2,
  modifiedAt: '2026-11-11T09:00:00+08:00',
  completedAt: '2026-11-10T09:00:00+08:00',
);
TaskActionSnapshot snap(TaskItem item) =>
    TaskActionSnapshot(scope: 'demo/member7', memberId: 7, task: item);
void main() {
  test(
    'AI draft content changes only; every identity/context field preserved',
    () {
      final original = task(), origin = snap(task());
      final proposal = TaskTextSuggestion(
        origin: origin,
        content: 'Edited😀',
        complete: true,
      );
      final next = proposal.applyToDraft(snap(original));
      expect(next.content, 'Edited😀');
      expect(next.id, 42);
      expect(next.parentId, 11);
      expect(next.topicId, 9);
      expect(next.done, true);
      expect(next.dueDate, original.dueDate);
      expect(next.completedAt, original.completedAt);
      expect(next.modifiedAt, original.modifiedAt);
      expect(next.childTotal, 3);
      expect(next.childDone, 2);
    },
  );
  test('stale full editor snapshot or unfinished AI cannot apply', () {
    final original = snap(task());
    final proposal = TaskTextSuggestion(
      origin: original,
      content: 'New',
      complete: true,
    );
    expect(
      () => proposal.applyToDraft(snap(task().copyWith(dueDate: '2026-12-05'))),
      throwsA(isA<TaskActionChanged>()),
    );
    expect(
      () => TaskTextSuggestion(
        origin: original,
        content: 'Partial',
        complete: false,
      ).applyToDraft(original),
      throwsA(isA<TaskActionChanged>()),
    );
    expect(
      () => proposal.applyToDraft(
        TaskActionSnapshot(scope: 'another/member7', memberId: 7, task: task()),
      ),
      throwsA(isA<TaskActionChanged>()),
    );
  });
  test(
    'topic cancel retains exact object, clear zero and select preserve other fields',
    () {
      final original = task();
      expect(identical(applyTaskTopic(original, null), original), true);
      final clear = applyTaskTopic(original, const TaskTopicChoice.clear());
      expect(clear.topicId, 0);
      expect(clear.id, 42);
      expect(clear.parentId, 11);
      expect(clear.content, original.content);
      final selected = applyTaskTopic(original, TaskTopicChoice.select(12));
      expect(selected.topicId, 12);
      expect(selected.done, true);
      expect(selected.dueDate, original.dueDate);
    },
  );
  test(
    'empty and >1000 rune suggestions are rejected without touching task',
    () {
      final origin = snap(task());
      for (final text in ['', List.filled(1001, '😀').join()]) {
        expect(
          () => TaskTextSuggestion(
            origin: origin,
            content: text,
            complete: true,
          ).applyToDraft(origin),
          throwsFormatException,
        );
      }
      expect(origin.task.content, task().content);
    },
  );
  test('real topic source validates list and fresh selected own ID', () async {
    final repo = FakeTopics(),
        source = OwnedTaskTopicSource(
          repository: FakeTopics(),
          scope: 'owned',
          isCurrent: () => true,
        );
    expect((await source.list('', 1)).items.single.id, 9);
    final own = OwnedTaskTopicSource(
      repository: repo,
      scope: 'owned',
      isCurrent: () => true,
    );
    expect((await own.inspect(9)).title, 'Launch');
    expect(repo.reads, 1);
    repo.items = [const TopicItem(id: 9, title: 'Foreign', memberId: 8)];
    await expectLater(own.list('', 1), throwsFormatException);
    await expectLater(own.inspect(9), throwsFormatException);
  });
  test(
    'source retirement rejects all callback results and invalid topic choice',
    () async {
      final repo = FakeTopics();
      var current = true;
      final source = OwnedTaskTopicSource(
        repository: repo,
        scope: 'owned',
        isCurrent: () => current,
      );
      current = false;
      await expectLater(source.inspect(9), throwsA(isA<TaskActionRetired>()));
      expect(repo.reads, 0);
      expect(() => TaskTopicChoice.select(0), throwsFormatException);
    },
  );
}
