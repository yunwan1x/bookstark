import 'api_client.dart';

String taskDate(DateTime value) {
  if (value.year < 1 || value.year > 9999) throw ArgumentError.value(value);
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

bool validTaskDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8));
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

/// Content has committed; only acknowledgement/metadata remains incomplete.
class TaskSaveFailure implements Exception {
  const TaskSaveFailure(this.savedId, this.message) : assert(savedId > 0);
  final int savedId;
  final String message;
  @override
  String toString() => message;
}

class TaskItem {
  const TaskItem({
    this.id,
    required this.content,
    required this.dueDate,
    this.done = false,
    this.parentId = 0,
    this.topicId,
    this.childTotal = 0,
    this.childDone = 0,
    this.modifiedAt,
    this.completedAt,
  });
  factory TaskItem.fromJson(Map row) {
    final id = row['task_id'];
    if (id is! int ||
        id <= 0 ||
        row['content'] is! String ||
        row['done'] is! bool) {
      throw const FormatException('Invalid task response');
    }
    return TaskItem(
      id: id,
      content: row['content'] as String,
      dueDate: row['due_date'] as String? ?? '',
      done: row['done'] as bool,
      parentId: row['parent_id'] as int? ?? 0,
      topicId: row['topic_id'] as int?,
      childTotal: row['child_total'] as int? ?? 0,
      childDone: row['child_done'] as int? ?? 0,
      modifiedAt: row['modify_time'] as String?,
      completedAt: row['complete_time'] as String?,
    );
  }
  final int? id, topicId;
  final int parentId, childTotal, childDone;
  final String content, dueDate;
  // Preserve server calendar dates: do not convert modify_time to device time
  // before filtering the server's substr(modify_time, 1, 10) calendar.
  final String? modifiedAt, completedAt;
  final bool done;
  TaskItem copyWith({int? id, String? content, String? dueDate, bool? done}) =>
      TaskItem(
        id: id ?? this.id,
        content: content ?? this.content,
        dueDate: dueDate ?? this.dueDate,
        done: done ?? this.done,
        parentId: parentId,
        topicId: topicId,
        childTotal: childTotal,
        childDone: childDone,
        modifiedAt: modifiedAt,
        completedAt: completedAt,
      );
  Map<String, Object?> writeBody() {
    final body = content.trim();
    if (body.isEmpty || body.runes.length > 1000) {
      throw const FormatException(
        '请输入1—1000个字符的待办内容 / Enter 1–1000 characters',
      );
    }
    if (!validTaskDate(dueDate)) {
      throw const FormatException('请选择有效截止日期 / Choose a valid due date');
    }
    if (parentId < 0 ||
        (id != null && (id! <= 0 || parentId == id)) ||
        (topicId != null && topicId! < 0)) {
      throw const FormatException('Invalid task identity or parent');
    }
    return {
      'content': body,
      'due_date': dueDate,
      'done': done,
      'parent_id': parentId,
      if (topicId != null) 'topic_id': topicId,
    };
  }
}

class TaskQuery {
  const TaskQuery({
    this.keyword = '',
    this.done,
    this.parentId,
    this.topicId,
    this.dueOn = '',
    this.dueBefore = '',
    this.dueAfter = '',
    this.modifiedOn = '',
    this.page = 1,
    this.pageSize = 30,
  });
  final String keyword, dueOn, dueBefore, dueAfter, modifiedOn;
  final bool? done;
  final int? parentId, topicId;
  final int page, pageSize;
  Map<String, String> parameters() {
    if (page < 1 ||
        pageSize < 1 ||
        pageSize > 100 ||
        (parentId != null && parentId! < 0) ||
        (topicId != null && topicId! <= 0)) {
      throw const FormatException('Invalid task query');
    }
    for (final date in [dueOn, dueBefore, dueAfter, modifiedOn]) {
      if (date.isNotEmpty && !validTaskDate(date)) {
        throw const FormatException('Invalid task filter date');
      }
    }
    return {
      'page': '$page',
      'page_size': '$pageSize',
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      if (done != null) 'done': done! ? '1' : '0',
      if (parentId != null) 'parent_id': '$parentId',
      if (topicId != null) 'topic_id': '$topicId',
      if (dueOn.isNotEmpty) 'due_on': dueOn,
      if (dueBefore.isNotEmpty) 'due_before': dueBefore,
      if (dueAfter.isNotEmpty) 'due_after': dueAfter,
      if (modifiedOn.isNotEmpty) 'date': modifiedOn,
    };
  }
}

class TaskPage {
  TaskPage({
    required List<TaskItem> items,
    required this.total,
    required this.page,
    required this.pageSize,
  }) : items = List.unmodifiable(items);
  final List<TaskItem> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

class TaskDailyCount {
  const TaskDailyCount(this.date, this.total, this.done, this.active);
  factory TaskDailyCount.fromJson(Map row) {
    final date = row['date'],
        total = row['count'],
        done = row['done_count'],
        active = row['active_count'];
    if (date is! String ||
        !validTaskDate(date) ||
        total is! int ||
        done is! int ||
        active is! int ||
        total < 0 ||
        done < 0 ||
        active < 0 ||
        done + active != total) {
      throw const FormatException('Invalid task calendar counts');
    }
    return TaskDailyCount(date, total, done, active);
  }
  final String date;
  final int total, done, active;
}

abstract interface class TasksRepository {
  Future<TaskPage> list(TaskQuery query);
  Future<TaskItem> read(int id);
  Future<int> save(TaskItem task);
  Future<void> setDone(int id, bool done);
  Future<void> remove(int id);
  Future<List<TaskDailyCount>> dailyCounts(int year, int month);
}

class RemoteTasksRepository implements TasksRepository {
  RemoteTasksRepository(this.client, {this.isCurrent})
    : _revision = client.sessionRevision,
      _token = client.exportSession()['token'];
  final bool Function()? isCurrent;
  final int _revision;
  final String? _token;
  void _guard() {
    if (isCurrent != null &&
        (!isCurrent!() ||
            client.sessionRevision != _revision ||
            _token == null ||
            _token.isEmpty ||
            client.exportSession()['token'] != _token)) {
      throw StateError('Task owner retired');
    }
  }

  final BookstarkClient client;
  void _id(int id) {
    if (id <= 0) throw ArgumentError.value(id);
  }

  @override
  Future<TaskPage> list(TaskQuery query) async {
    final path = Uri(
      path: '/api/tasks',
      queryParameters: query.parameters(),
    ).toString();
    _guard();
    final result = await client.get(path);
    _guard();
    final total = result['total'],
        page = result['page'],
        size = result['page_size'];
    if (total is! int ||
        total < 0 ||
        page is! int ||
        page <= 0 ||
        size is! int ||
        size <= 0) {
      throw const FormatException('Invalid task pagination');
    }
    return TaskPage(
      items: [
        for (final row in result['data'] as List? ?? const [])
          TaskItem.fromJson(row as Map),
      ],
      total: total,
      page: page,
      pageSize: size,
    );
  }

  @override
  Future<TaskItem> read(int id) async {
    _guard();
    _id(id);
    final item = TaskItem.fromJson(await client.get('/api/tasks/$id'));
    _guard();
    if (item.id != id) throw const FormatException('Mismatched task response');
    return item;
  }

  @override
  Future<int> save(TaskItem task) async {
    _guard();
    final body = task.writeBody();
    if (task.id != null) {
      _id(task.id!);
      await client.mutate(
        'PUT',
        '/api/tasks/${task.id}',
        body,
        beforeSubmit: _guard,
      );
      _guard();
      return task.id!;
    }
    final created = TaskItem.fromJson(
      await client.mutate('POST', '/api/tasks', body, beforeSubmit: _guard),
    );
    _guard();
    return created.id!;
  }

  @override
  Future<void> setDone(int id, bool done) async {
    _id(id);
    _guard();
    await client.mutate('PATCH', '/api/tasks/$id/done', {
      'done': done,
    }, beforeSubmit: _guard);
    _guard();
  }

  @override
  Future<void> remove(int id) async {
    _id(id);
    _guard();
    await client.mutate('DELETE', '/api/tasks/$id', {}, beforeSubmit: _guard);
    _guard();
  }

  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) async {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw ArgumentError('Invalid month');
    }
    _guard();
    final result = await client.get(
      '/api/tasks/daily-counts?year=$year&month=$month',
    );
    _guard();
    return [
      for (final row in result['data'] as List? ?? const [])
        TaskDailyCount.fromJson(row as Map),
    ];
  }
}
