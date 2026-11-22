// In-memory fixture only. Production lib/ never imports this file.
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'tasks.dart';

class TopicsFixture implements TopicsRepository {
  TopicsFixture() {
    records.addAll({
      1: TopicItem(
        id: 1,
        memberId: 7,
        title: '阅读与知识整理',
        question: '如何把阅读转化为可执行的知识？',
        isPinned: true,
        modifiedAt: now,
        modifiedOn: '2026-11-04',
      ),
      2: TopicItem(
        id: 2,
        memberId: 7,
        title: 'Flutter 学习',
        question: '如何完成一个原生应用？',
        modifiedAt: DateTime(2026, 11, 3),
        modifiedOn: '2026-11-03',
      ),
    });
    summaries.addAll({
      31: TopicSummary(
        id: 31,
        topicId: 1,
        content:
            '# 从记录走向行动\n\n阅读之后，用自己的语言留下一个观点，再写下下一步行动。\n\n- 关联已有笔记\n- 每周回顾一次',
        modifiedAt: now,
      ),
      32: TopicSummary(
        id: 32,
        topicId: 1,
        content: '# 建立可持续的阅读循环\n\n选择问题、收集资料、形成小结，并通过行动检验理解。',
        type: 'ai',
        order: 1,
        modifiedAt: now,
      ),
      33: TopicSummary(
        id: 33,
        topicId: 2,
        content: '# Flutter 学习记录',
        modifiedAt: DateTime(2026, 11, 3),
      ),
    });
    resources.addAll({
      51: TopicResource(
        id: 51,
        topicId: 1,
        type: TopicResourceType.note,
        targetId: 1,
        title: '阅读的意义',
        description: '把阅读变成理解，再把理解变成行动。',
        createdAt: now,
      ),
      52: TopicResource(
        id: 52,
        topicId: 1,
        type: TopicResourceType.article,
        targetId: 1,
        title: '如何建立自己的知识体系',
        createdAt: now,
      ),
      53: TopicResource(
        id: 53,
        topicId: 1,
        type: TopicResourceType.bookmark,
        targetId: 1,
        title: 'Flutter 开发文档',
        createdAt: now,
      ),
      54: TopicResource(
        id: 54,
        topicId: 2,
        type: TopicResourceType.document,
        targetId: 1,
        title: '阅读的起点',
        createdAt: DateTime(2026, 11, 3),
      ),
      55: TopicResource(
        id: 55,
        topicId: 2,
        type: TopicResourceType.bookmark,
        targetId: 2,
        title: 'Dart 语言指南',
        createdAt: DateTime(2026, 11, 3),
      ),
    });
    taskRepository.records.addAll({
      71: TaskItem(
        id: 71,
        topicId: 1,
        content: '每周回顾一次',
        dueDate: '2026-11-08',
        modifiedAt: now.toIso8601String(),
      ),
      for (var i = 72; i <= 74; i++)
        i: TaskItem(
          id: i,
          topicId: 2,
          content: 'Flutter 实践任务${i - 71}',
          dueDate: '2026-11-08',
          modifiedAt: '2026-11-03T10:00:00',
        ),
    });
    commentRecords.addAll({
      81: TopicComment(
        id: 81,
        topicId: 1,
        target: TopicCommentTarget.summary,
        targetId: 31,
        content: '这条小结值得保留，下周回顾时继续补充。\n\n**先行动，再整理。**',
        memberId: 7,
        author: '本地用户',
        createdAt: now,
      ),
      82: TopicComment(
        id: 82,
        topicId: 1,
        target: TopicCommentTarget.resource,
        targetId: 51,
        content: '这篇笔记和当前问题很相关。',
        memberId: 7,
        author: '本地用户',
        createdAt: now,
      ),
    });
  }
  final now = DateTime(2026, 11, 4, 10, 20);
  final records = <int, TopicItem>{};
  final summaries = <int, TopicSummary>{};
  final resources = <int, TopicResource>{};
  final commentRecords = <int, TopicComment>{};
  final taskRepository = TaskFixture(
    sample: false,
    today: DateTime(2026, 11, 4, 10, 20),
  );
  int nextId = 100, saveCalls = 0;
  bool failCounts = false;
  Future<TopicPageResult> Function(TopicQuery)? listOverride;
  Future<List<TopicDailyCount>> Function(int year, int month)? countsOverride;
  @override
  int get memberId => 7;
  TopicItem _item(TopicItem row) => TopicItem(
    id: row.id,
    memberId: memberId,
    title: row.title,
    question: row.question,
    isPinned: row.isPinned,
    summaryCount: summaries.values
        .where((value) => value.topicId == row.id)
        .length,
    resourceCount: resources.values
        .where((value) => value.topicId == row.id)
        .length,
    taskCount: taskRepository.records.values
        .where((value) => value.topicId == row.id)
        .length,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
    modifiedOn: row.modifiedOn,
  );
  @override
  Future<TopicPageResult> list(TopicQuery query) async {
    if (listOverride != null) return listOverride!(query);
    final rows = records.values
        .map(_item)
        .where(
          (row) =>
              '${row.title} ${row.question}'.contains(query.keyword) &&
              (query.date.isEmpty || row.modifiedOn == query.date),
        )
        .toList();
    return TopicPageResult(
      rows.skip((query.page - 1) * 20).take(20).toList(),
      rows.length,
      query.page,
      20,
    );
  }

  TopicSummary _summary(TopicSummary row) => TopicSummary(
    id: row.id,
    topicId: row.topicId,
    content: row.content,
    type: row.type,
    order: row.order,
    commentCount: commentRecords.values
        .where(
          (comment) =>
              comment.target == TopicCommentTarget.summary &&
              comment.targetId == row.id,
        )
        .length,
    createdAt: row.createdAt,
    modifiedAt: row.modifiedAt,
  );
  TopicResource _resource(TopicResource row) => TopicResource(
    id: row.id,
    topicId: row.topicId,
    type: row.type,
    targetId: row.targetId,
    title: row.title,
    description: row.description,
    order: row.order,
    commentCount: commentRecords.values
        .where(
          (comment) =>
              comment.target == TopicCommentTarget.resource &&
              comment.targetId == row.id,
        )
        .length,
    createdAt: row.createdAt,
    missing: row.missing,
    openUrl: row.openUrl,
  );
  @override
  Future<TopicDetail> read(int id) async {
    final row = records[id];
    if (row == null) throw StateError('主题不存在');
    final summaryRows =
        summaries.values
            .where((row) => row.topicId == id)
            .map(_summary)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final resourceRows =
        resources.values
            .where((row) => row.topicId == id)
            .map(_resource)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return TopicDetail(
      topic: _item(row),
      summaries: summaryRows,
      resources: resourceRows,
      loadedTasks: (await tasks(id)).items,
      commentCount: commentRecords.values
          .where((row) => row.topicId == id)
          .length,
    );
  }

  @override
  Future<int> save(TopicItem item) async {
    final body = item.writeBody();
    saveCalls++;
    final id = item.id ?? nextId++;
    records[id] = TopicItem(
      id: id,
      memberId: 7,
      title: body['title'] as String,
      question: body['question'] as String,
      isPinned: item.isPinned,
      modifiedAt: now,
      modifiedOn: '2026-11-04',
    );
    return id;
  }

  @override
  Future<void> setPinned(int id, bool value) async {
    records[id] = records[id]!.copyWith(isPinned: value);
  }

  @override
  Future<void> remove(int id) async {
    records.remove(id);
    summaries.removeWhere((_, row) => row.topicId == id);
    resources.removeWhere((_, row) => row.topicId == id);
    commentRecords.removeWhere((_, row) => row.topicId == id);
    taskRepository.records.removeWhere((_, row) => row.topicId == id);
  }

  @override
  Future<TopicSummary> saveSummary(TopicSummary item) async {
    item.writeBody();
    final id = item.id ?? nextId++;
    return summaries[id] = TopicSummary(
      id: id,
      topicId: item.topicId,
      content: item.content.trim(),
      type: item.type,
      order: item.order,
      modifiedAt: now,
    );
  }

  @override
  Future<void> removeSummary(int topicId, int summaryId) async {
    summaries.remove(summaryId);
    commentRecords.removeWhere(
      (_, row) =>
          row.topicId == topicId &&
          row.target == TopicCommentTarget.summary &&
          row.targetId == summaryId,
    );
  }

  @override
  Future<void> sortSummaries(int topicId, Map<int, int> order) async {
    for (final entry in order.entries) {
      final row = summaries[entry.key]!;
      summaries[entry.key] = TopicSummary(
        id: row.id,
        topicId: topicId,
        content: row.content,
        type: row.type,
        order: entry.value,
        modifiedAt: row.modifiedAt,
      );
    }
  }

  @override
  Future<TopicResource> addResource(TopicResource item) async {
    item.writeBody();
    if (resources.values.any(
      (row) =>
          row.topicId == item.topicId &&
          row.type == item.type &&
          row.targetId == item.targetId,
    )) {
      throw StateError('已在主题中');
    }
    final id = nextId++;
    return resources[id] = TopicResource(
      id: id,
      topicId: item.topicId,
      type: item.type,
      targetId: item.targetId,
      title: item.title,
      description: item.description,
      order: item.order,
      createdAt: now,
    );
  }

  @override
  Future<void> removeResource(int topicId, int resourceId) async {
    resources.remove(resourceId);
    commentRecords.removeWhere(
      (_, row) =>
          row.topicId == topicId &&
          row.target == TopicCommentTarget.resource &&
          row.targetId == resourceId,
    );
  }

  @override
  Future<void> sortResources(int topicId, Map<int, int> order) async {
    for (final entry in order.entries) {
      final row = resources[entry.key]!;
      resources[entry.key] = TopicResource(
        id: row.id,
        topicId: topicId,
        type: row.type,
        targetId: row.targetId,
        title: row.title,
        description: row.description,
        order: entry.value,
        createdAt: row.createdAt,
      );
    }
  }

  @override
  Future<TaskPage> tasks(int topicId, {int page = 1}) async {
    final rows = taskRepository.records.values
        .where((row) => row.topicId == topicId)
        .toList();
    return TaskPage(
      items: rows.skip((page - 1) * 100).take(100).toList(),
      total: rows.length,
      page: page,
      pageSize: 100,
    );
  }

  @override
  Future<TopicCommentPage> comments(
    int topicId, {
    TopicCommentTarget? target,
    int? targetId,
    int page = 1,
  }) async {
    final rows = commentRecords.values
        .where(
          (row) =>
              row.topicId == topicId &&
              (target == null ||
                  (row.target == target && row.targetId == targetId)),
        )
        .toList();
    return TopicCommentPage(
      rows.skip((page - 1) * 100).take(100).toList(),
      rows.length,
      page,
      100,
    );
  }

  @override
  Future<TopicComment> saveComment(TopicComment item) async {
    item.writeBody();
    final id = item.id ?? nextId++;
    return commentRecords[id] = TopicComment(
      id: id,
      topicId: item.topicId,
      target: item.target,
      targetId: item.targetId,
      content: item.content.trim(),
      memberId: 7,
      author: '本地用户',
      createdAt: now,
      modifiedAt: now,
    );
  }

  @override
  Future<void> removeComment(int topicId, int commentId) async {
    commentRecords.remove(commentId);
  }

  @override
  Future<List<TopicDailyCount>> dailyCounts(int year, int month) async {
    if (countsOverride != null) return countsOverride!(year, month);
    if (failCounts) throw StateError('活动计数读取失败');
    final counts = <String, List<int>>{};
    void event(String day, int kind) {
      if (day.startsWith(
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-',
      )) {
        counts.putIfAbsent(day, () => [0, 0, 0, 0])[kind]++;
      }
    }

    for (final row in records.values) {
      event(row.modifiedOn, 0);
    }
    for (final row in summaries.values) {
      if (row.modifiedAt != null) event(taskDate(row.modifiedAt!), 1);
    }
    for (final row in resources.values) {
      if (row.createdAt != null) event(taskDate(row.createdAt!), 2);
    }
    for (final row in taskRepository.records.values) {
      if (row.modifiedAt != null) event(row.modifiedAt!.substring(0, 10), 3);
    }
    return [
      for (final entry in counts.entries)
        TopicDailyCount(
          entry.key,
          entry.value.fold(0, (a, b) => a + b),
          entry.value[0],
          entry.value[1],
          entry.value[2],
          entry.value[3],
        ),
    ];
  }
}
