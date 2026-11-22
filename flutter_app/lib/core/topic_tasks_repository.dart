import 'task_draft_save_context.dart';
import 'task_draft_vault.dart';
import 'task_creation_controller.dart';
import 'tasks_repository.dart';

/// Every nested task route stays in its actual topic. Existing editors, task
/// cards and child lists keep using the same production task repository.
class TopicTasksRepository implements TasksRepository, TaskDraftSaveRepository {
  TopicTasksRepository(this.delegate, this.topicId) {
    if (topicId <= 0) throw const FormatException('Invalid task topic');
  }
  final TasksRepository delegate;
  final int topicId;
  @override
  Future<bool> hasRetainedTaskCreation() async {
    final source = delegate;
    return source is TaskDraftSaveRepository
        ? (source as TaskDraftSaveRepository).hasRetainedTaskCreation()
        : false;
  }

  @override
  TaskCreationRecoveryController? get taskCreationRecovery {
    final source = delegate;
    return source is TaskDraftSaveRepository
        ? (source as TaskDraftSaveRepository).taskCreationRecovery
        : null;
  }

  void _guard(TaskItem item) {
    if (item.topicId != topicId) {
      throw StateError('待办不在当前主题中 / Task is outside the current topic');
    }
  }

  void _validatePage(TaskPage result, int page, int size) {
    if (result.page != page ||
        result.pageSize != size ||
        result.total < 0 ||
        result.items.length !=
            (result.total - (page - 1) * size).clamp(0, size) ||
        result.items.any((row) => row.id == null || row.id! <= 0) ||
        result.items.map((row) => row.id).toSet().length !=
            result.items.length) {
      throw const FormatException('Invalid topic task page');
    }
  }

  @override
  Future<TaskPage> list(TaskQuery query) async {
    final result = await delegate.list(
      TaskQuery(
        keyword: query.keyword,
        done: query.done,
        parentId: query.parentId,
        topicId: topicId,
        dueOn: query.dueOn,
        dueBefore: query.dueBefore,
        dueAfter: query.dueAfter,
        modifiedOn: query.modifiedOn,
        page: query.page,
        pageSize: query.pageSize,
      ),
    );
    _validatePage(result, query.page, query.pageSize);
    for (final item in result.items) {
      _guard(item);
    }
    return result;
  }

  @override
  Future<TaskItem> read(int id) async {
    final item = await delegate.read(id);
    _guard(item);
    return item;
  }

  @override
  Future<int> save(TaskItem task) => saveWithDraft(task, null);

  @override
  Future<int> saveWithDraft(TaskItem task, TaskDraftVault? vault) async {
    if (task.topicId != null && task.topicId != topicId) {
      throw StateError('Cannot move a task into another topic');
    }
    if (task.id != null) await read(task.id!);
    if (task.parentId != 0) await read(task.parentId);
    final projected = TaskItem(
      id: task.id,
      content: task.content,
      dueDate: task.dueDate,
      done: task.done,
      parentId: task.parentId,
      topicId: topicId,
      childTotal: task.childTotal,
      childDone: task.childDone,
      modifiedAt: task.modifiedAt,
      completedAt: task.completedAt,
    );
    final source = delegate;
    return source is TaskDraftSaveRepository
        ? (source as TaskDraftSaveRepository).saveWithDraft(projected, vault)
        : source.save(projected);
  }

  @override
  Future<void> setDone(int id, bool done) async {
    await read(id);
    await delegate.setDone(id, done);
  }

  @override
  Future<void> remove(int id) async {
    await read(id);
    final seen = <int>{};
    Future<void> descendants(int parent, int depth) async {
      if (depth > 256 || !seen.add(parent)) {
        throw StateError('Invalid task subtree');
      }
      var page = 1;
      int? expectedTotal;
      while (true) {
        // Check all direct children, including any legacy cross-topic ones,
        // before the server's transactional whole-subtree delete.
        final result = await delegate.list(
          TaskQuery(parentId: parent, page: page, pageSize: 100),
        );
        _validatePage(result, page, 100);
        if (expectedTotal != null && result.total != expectedTotal) {
          throw const FormatException(
            'Child task total changed; reload before deleting',
          );
        }
        expectedTotal ??= result.total;
        for (final child in result.items) {
          _guard(child);
          await descendants(child.id!, depth + 1);
        }
        if (!result.hasMore) break;
        page++;
      }
    }

    await descendants(id, 0);
    await delegate.remove(id);
  }

  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) async {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw const FormatException('Invalid month');
    }
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
    final counts = <String, List<int>>{}, seen = <int>{};
    var page = 1;
    int? expectedTotal;
    while (true) {
      final result = await list(TaskQuery(page: page, pageSize: 100));
      if (expectedTotal != null && result.total != expectedTotal) {
        throw const FormatException(
          'Topic task total changed; reload calendar',
        );
      }
      expectedTotal ??= result.total;
      for (final item in result.items) {
        if (!seen.add(item.id!)) {
          throw const FormatException('Duplicate task page');
        }
        final date = item.modifiedAt;
        if (date == null || date.length < 10) continue;
        final day = date.substring(0, 10);
        if (!day.startsWith(prefix) || !validTaskDate(day)) continue;
        final count = counts.putIfAbsent(day, () => [0, 0]);
        count[item.done ? 1 : 0]++;
      }
      if (!result.hasMore) break;
      page++;
    }
    return [
      for (final entry in counts.entries)
        TaskDailyCount(
          entry.key,
          entry.value[0] + entry.value[1],
          entry.value[1],
          entry.value[0],
        ),
    ];
  }
}
