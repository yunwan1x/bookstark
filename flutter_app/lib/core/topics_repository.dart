import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'tasks_repository.dart';

void _positive(int id) {
  if (id <= 0) throw const FormatException('Invalid topic resource ID');
}

DateTime? _time(Object? value) => value is String && !value.startsWith('0001-')
    ? DateTime.tryParse(value)
    : null;

class TopicItem {
  const TopicItem({
    this.id,
    required this.title,
    this.question = '',
    this.memberId = 0,
    this.isPinned = false,
    this.resourceCount = 0,
    this.summaryCount = 0,
    this.taskCount = 0,
    this.createdAt,
    this.modifiedAt,
    this.modifiedOn = '',
  });
  final int? id;
  final String title, question;
  // Preserve the server calendar day; parsing an offset timestamp alone shifts it to UTC.
  final String modifiedOn;
  final int memberId, resourceCount, summaryCount, taskCount;
  final bool isPinned;
  final DateTime? createdAt, modifiedAt;
  factory TopicItem.fromJson(Map row) => TopicItem(
    id: row['topic_id'] as int,
    title: row['title'] as String,
    question: row['question'] as String? ?? '',
    memberId: row['member_id'] as int,
    isPinned: row['is_pinned'] as bool? ?? false,
    resourceCount: row['resource_count'] as int? ?? 0,
    summaryCount: row['summary_count'] as int? ?? 0,
    taskCount: row['task_count'] as int? ?? 0,
    createdAt: _time(row['create_time']),
    modifiedAt: _time(row['modify_time']),
    modifiedOn:
        row['modify_time'] is String &&
            (row['modify_time'] as String).length >= 10 &&
            validTaskDate((row['modify_time'] as String).substring(0, 10))
        ? (row['modify_time'] as String).substring(0, 10)
        : '',
  );
  TopicItem copyWith({
    int? id,
    String? title,
    String? question,
    bool? isPinned,
    int? memberId,
  }) => TopicItem(
    id: id ?? this.id,
    title: title ?? this.title,
    question: question ?? this.question,
    memberId: memberId ?? this.memberId,
    isPinned: isPinned ?? this.isPinned,
    resourceCount: resourceCount,
    summaryCount: summaryCount,
    taskCount: taskCount,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    modifiedOn: modifiedOn,
  );
  Map<String, Object?> writeBody() {
    if (id != null) _positive(id!);
    if (title.trim().isEmpty ||
        title.trim().runes.length > 200 ||
        question.runes.length > 2000) {
      throw const FormatException(
        '主题名称必填且最多200字；问题最多2000字 / Topic title required, up to 200 characters; question up to 2000',
      );
    }
    return {
      'title': title.trim(),
      'question': question.trim(),
      'is_pinned': isPinned,
    };
  }
}

class TopicQuery {
  const TopicQuery({this.keyword = '', this.date = '', this.page = 1});
  final String keyword, date;
  final int page;
  Map<String, String> parameters() {
    if (page < 1 || (date.isNotEmpty && !validTaskDate(date))) {
      throw const FormatException('Invalid topic query');
    }
    return {
      'keyword': keyword.trim(),
      if (date.isNotEmpty) 'date': date,
      'page': '$page',
    };
  }
}

class TopicPageResult {
  const TopicPageResult(this.items, this.total, this.page, this.pageSize);
  final List<TopicItem> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

class TopicSummary {
  const TopicSummary({
    this.id,
    required this.topicId,
    required this.content,
    this.type = 'manual',
    this.order = 0,
    this.commentCount = 0,
    this.createdAt,
    this.modifiedAt,
  });
  final int? id;
  final int topicId, order, commentCount;
  final String content, type;
  final DateTime? createdAt, modifiedAt;
  factory TopicSummary.fromJson(Map row) => TopicSummary(
    id: row['summary_id'] as int,
    topicId: row['topic_id'] as int,
    content: row['content'] as String,
    type: row['summary_type'] as String? ?? 'manual',
    order: row['order_sort'] as int? ?? 0,
    commentCount: row['comment_count'] as int? ?? 0,
    createdAt: _time(row['create_time']),
    modifiedAt: _time(row['modify_time']),
  );
  Map<String, Object?> writeBody() {
    _positive(topicId);
    if (id != null) _positive(id!);
    if (content.trim().isEmpty ||
        content.trim().runes.length > 20000 ||
        !{'manual', 'ai'}.contains(type)) {
      throw const FormatException(
        '小结不能为空且最多20000字 / Summary required, up to 20000 characters',
      );
    }
    return {
      'content': content.trim(),
      'summary_type': type,
      'order_sort': order,
    };
  }
}

enum TopicResourceType { document, note, article, bookmark, task }

class TopicResource {
  const TopicResource({
    this.id,
    required this.topicId,
    required this.type,
    required this.targetId,
    this.title = '',
    this.description = '',
    this.order = 0,
    this.commentCount = 0,
    this.missing = false,
    this.openUrl = '',
    this.createdAt,
  });
  final int? id;
  final int topicId, targetId, order, commentCount;
  final TopicResourceType type;
  final String title, description, openUrl;
  final bool missing;
  final DateTime? createdAt;
  factory TopicResource.fromJson(Map row) => TopicResource(
    id: row['topic_resource_id'] as int,
    topicId: row['topic_id'] as int,
    type: TopicResourceType.values.byName(row['resource_type'] as String),
    targetId: row['target_id'] as int,
    title: row['title_snapshot'] as String? ?? '',
    description: row['desc_snapshot'] as String? ?? '',
    order: row['order_sort'] as int? ?? 0,
    commentCount: row['comment_count'] as int? ?? 0,
    missing: row['resource_missing'] as bool? ?? false,
    openUrl: row['open_url'] as String? ?? '',
    createdAt: _time(row['create_time']),
  );
  Map<String, Object?> writeBody() {
    _positive(topicId);
    _positive(targetId);
    if (title.trim().runes.length > 500 ||
        description.trim().runes.length > 2000) {
      throw const FormatException(
        '资料标题最多500字；说明最多2000字 / Resource title up to 500 characters; description up to 2000',
      );
    }
    return {
      'resource_type': type.name,
      'target_id': targetId,
      'title_snapshot': title.trim(),
      'desc_snapshot': description.trim(),
      'order_sort': order,
    };
  }
}

class TopicDetail {
  const TopicDetail({
    required this.topic,
    required this.summaries,
    required this.resources,
    required this.loadedTasks,
    required this.commentCount,
  });
  final TopicItem topic;
  final List<TopicSummary> summaries;
  final List<TopicResource> resources;

  /// Go detail returns at most 100 tasks. Use tasks() for authoritative pagination.
  final List<TaskItem> loadedTasks;
  final int commentCount;
  factory TopicDetail.fromJson(Map row) {
    final topic = TopicItem.fromJson(row['topic'] as Map);
    final result = TopicDetail(
      topic: topic,
      summaries: List.unmodifiable(
        (row['summaries'] as List? ?? []).map(
          (value) => TopicSummary.fromJson(value as Map),
        ),
      ),
      resources: List.unmodifiable(
        (row['resources'] as List? ?? []).map(
          (value) => TopicResource.fromJson(value as Map),
        ),
      ),
      loadedTasks: List.unmodifiable(
        (row['tasks'] as List? ?? []).map(
          (value) => TaskItem.fromJson(value as Map),
        ),
      ),
      commentCount: (row['stats'] as Map?)?['comment_count'] as int? ?? 0,
    );
    if (result.summaries.any((item) => item.topicId != topic.id) ||
        result.resources.any((item) => item.topicId != topic.id) ||
        result.loadedTasks.any((item) => item.topicId != topic.id)) {
      throw const FormatException('Mismatched topic detail');
    }
    return result;
  }
}

enum TopicCommentTarget { resource, summary, task }

class TopicComment {
  const TopicComment({
    this.id,
    required this.topicId,
    required this.target,
    required this.targetId,
    required this.content,
    this.memberId = 0,
    this.author = '',
    this.createdAt,
    this.modifiedAt,
  });
  final int? id;
  final int topicId, targetId, memberId;
  final TopicCommentTarget target;
  final String content, author;
  final DateTime? createdAt, modifiedAt;
  factory TopicComment.fromJson(Map row) => TopicComment(
    id: row['comment_id'] as int,
    topicId: row['topic_id'] as int,
    target: TopicCommentTarget.values.byName(row['target_type'] as String),
    targetId: row['target_id'] as int,
    content: row['content'] as String,
    memberId: row['member_id'] as int,
    author: row['author_name'] as String? ?? '',
    createdAt: _time(row['create_time']),
    modifiedAt: _time(row['modify_time']),
  );
  Map<String, Object?> writeBody({bool updating = false}) {
    _positive(topicId);
    _positive(targetId);
    if (id != null) _positive(id!);
    if (content.trim().isEmpty || content.trim().runes.length > 20000) {
      throw const FormatException(
        '评论不能为空且最多20000字 / Comment required, up to 20000 characters',
      );
    }
    final body = <String, Object?>{
      'content': content.trim(),
      if (!updating) ...{
        'target_type': target.name,
        'target_id': targetId,
        'parent_comment_id': 0,
      },
    };
    if (utf8.encode(jsonEncode(body)).length > 256 * 1024) {
      throw const FormatException('评论请求过大 / Comment request too large');
    }
    return body;
  }
}

class TopicCommentPage {
  const TopicCommentPage(this.items, this.total, this.page, this.pageSize);
  final List<TopicComment> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

class TopicDailyCount {
  const TopicDailyCount(
    this.date,
    this.total,
    this.topics,
    this.summaries,
    this.resources,
    this.tasks,
  );
  final String date;
  final int total, topics, summaries, resources, tasks;
  factory TopicDailyCount.fromJson(Map row) {
    final result = TopicDailyCount(
      row['date'] as String,
      row['count'] as int,
      row['topic_count'] as int,
      row['summary_count'] as int,
      row['resource_count'] as int,
      row['task_count'] as int,
    );
    if (!validTaskDate(result.date) ||
        [
          result.total,
          result.topics,
          result.summaries,
          result.resources,
          result.tasks,
        ].any((count) => count < 0) ||
        result.total !=
            result.topics +
                result.summaries +
                result.resources +
                result.tasks) {
      throw const FormatException('Invalid topic activity counts');
    }
    return result;
  }
}

abstract interface class TopicsRepository {
  int get memberId;
  Future<TopicPageResult> list(TopicQuery query);
  Future<TopicDetail> read(int id);
  Future<int> save(TopicItem topic);
  Future<void> setPinned(int id, bool value);
  Future<void> remove(int id);
  Future<TopicSummary> saveSummary(TopicSummary summary);
  Future<void> removeSummary(int topicId, int summaryId);
  Future<void> sortSummaries(int topicId, Map<int, int> order);
  Future<TopicResource> addResource(TopicResource resource);
  Future<void> removeResource(int topicId, int resourceId);
  Future<void> sortResources(int topicId, Map<int, int> order);
  Future<TaskPage> tasks(int topicId, {int page = 1});
  Future<TopicCommentPage> comments(
    int topicId, {
    TopicCommentTarget? target,
    int? targetId,
    int page = 1,
  });
  Future<TopicComment> saveComment(TopicComment comment);
  Future<void> removeComment(int topicId, int commentId);
  Future<List<TopicDailyCount>> dailyCounts(int year, int month);
}

/// Actual source-only editing capability; legacy repository overrides remain compatible.
abstract interface class SummaryContentWriter {
  Future<TopicSummary> readSummaryForEditing(int topicId, int summaryId);
  Future<TopicSummary> saveSummaryContent(
    TopicSummary baseline,
    String content,
  );
}

class RemoteTopicsRepository implements TopicsRepository, SummaryContentWriter {
  RemoteTopicsRepository(
    this.client, {
    required this.memberId,
    this.isCurrent,
    this.createRecoverably,
  }) : _sessionRevision = client.sessionRevision {
    _positive(memberId);
  }
  final BookstarkClient client;
  final Future<Map<String, Object?>> Function(
    String kind,
    int topicId,
    Map<String, Object?> body,
  )?
  createRecoverably;
  final bool Function()? isCurrent;
  final int _sessionRevision;
  void _assertCurrent() {
    if (client.sessionRevision != _sessionRevision ||
        !(isCurrent?.call() ?? true)) {
      throw StateError('Topic owner changed; request was not replayed');
    }
  }

  Future<Map<String, Object?>> _get(String path) async {
    _assertCurrent();
    final result = await client.get(path);
    _assertCurrent();
    return result;
  }

  Future<Map<String, Object?>> _write(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    _assertCurrent();
    final result = await client.mutate(
      method,
      path,
      body,
      beforeSubmit: _assertCurrent,
    );
    _assertCurrent();
    return result;
  }

  Future<Map<String, Object?>> _create(
    String kind,
    int topicId,
    Map<String, Object?> body,
  ) async {
    _assertCurrent();
    final callback = createRecoverably;
    final row = callback == null
        ? await _write(
            'POST',
            kind == 'topic'
                ? '/api/topics'
                : '/api/topics/$topicId/${kind == 'summary' ? 'summaries' : 'comments'}',
            body,
          )
        : await callback(kind, topicId, Map.unmodifiable(body));
    _assertCurrent();
    return row;
  }

  @override
  final int memberId;
  void _owner(TopicItem topic) {
    if (topic.memberId != memberId) {
      throw StateError('无权访问此主题 / Cannot access this topic');
    }
  }

  void _page(Map result) {
    if (result['total'] is! int ||
        (result['total'] as int) < 0 ||
        result['page'] is! int ||
        (result['page'] as int) < 1 ||
        result['page_size'] is! int ||
        (result['page_size'] as int) < 1) {
      throw const FormatException('Invalid topic pagination');
    }
  }

  @override
  Future<TopicPageResult> list(TopicQuery query) async {
    final result = await _get(
      '/api/topics?${Uri(queryParameters: query.parameters()).query}',
    );
    _page(result);
    final items = (result['data'] as List? ?? [])
        .map((row) => TopicItem.fromJson(row as Map))
        .toList();
    for (final topic in items) {
      _owner(topic);
    }
    return TopicPageResult(
      List.unmodifiable(items),
      result['total'] as int,
      result['page'] as int,
      result['page_size'] as int,
    );
  }

  @override
  Future<TopicDetail> read(int id) async {
    _positive(id);
    final result = TopicDetail.fromJson(await _get('/api/topics/$id'));
    if (result.topic.id != id) throw const FormatException('Topic ID mismatch');
    _owner(result.topic);
    return result;
  }

  @override
  Future<int> save(TopicItem topic) async {
    final body = topic.writeBody();
    if (topic.id != null) _owner(topic);
    final result = topic.id == null
        ? await _create('topic', 0, body)
        : await _write('PUT', '/api/topics/${topic.id}', body);
    final saved = TopicItem.fromJson(result);
    _positive(saved.id!);
    _owner(saved);
    if (topic.id != null && saved.id != topic.id) {
      throw const FormatException('Topic ID mismatch');
    }
    return saved.id!;
  }

  @override
  Future<void> setPinned(int id, bool value) async {
    _positive(id);
    await _write('PATCH', '/api/topics/$id/pin', {'is_pinned': value});
  }

  @override
  Future<void> remove(int id) async {
    _positive(id);
    await _write('DELETE', '/api/topics/$id', {});
  }

  @override
  Future<TopicSummary> readSummaryForEditing(int topicId, int summaryId) async {
    _positive(topicId);
    _positive(summaryId);
    final actual = TopicSummary.fromJson(
      await client.readTopicSummaryContent(
        topicId,
        summaryId,
        expectedSessionRevision: _sessionRevision,
        isCurrent: () =>
            client.sessionRevision == _sessionRevision &&
            (isCurrent?.call() ?? true),
      ),
    );
    if (actual.topicId != topicId || actual.id != summaryId) {
      throw const FormatException('Summary source identity changed');
    }
    return actual;
  }

  @override
  Future<TopicSummary> saveSummaryContent(
    TopicSummary baseline,
    String content,
  ) async {
    final id = baseline.id;
    if (id == null) throw const FormatException('Existing summary required');
    _positive(id);
    _positive(baseline.topicId);
    final canonical =
        TopicSummary(
              topicId: baseline.topicId,
              content: content,
            ).writeBody()['content']
            as String;
    final row = await client.updateTopicSummaryContent(
      baseline.topicId,
      id,
      content: canonical,
      expectedSourceSHA: sha256
          .convert(utf8.encode(baseline.content))
          .toString(),
      expectedSessionRevision: _sessionRevision,
      isCurrent: () =>
          client.sessionRevision == _sessionRevision &&
          (isCurrent?.call() ?? true),
    );
    final actual = TopicSummary.fromJson(row);
    if (actual.id != id ||
        actual.topicId != baseline.topicId ||
        actual.content != canonical) {
      throw const FormatException(
        'Summary body receipt mismatch; review current version',
      );
    }
    return actual;
  }

  @override
  Future<TopicSummary> saveSummary(TopicSummary summary) async {
    final body = summary.writeBody();
    final result = summary.id == null
        ? await _create('summary', summary.topicId, body)
        : await _write(
            'PUT',
            '/api/topics/${summary.topicId}/summaries/${summary.id}',
            body,
          );
    final saved = TopicSummary.fromJson(result);
    if (saved.topicId != summary.topicId ||
        saved.id == null ||
        saved.id! <= 0 ||
        (summary.id != null && saved.id != summary.id)) {
      throw const FormatException('Summary ID mismatch');
    }
    return saved;
  }

  @override
  Future<void> removeSummary(int topicId, int summaryId) async {
    _positive(topicId);
    _positive(summaryId);
    await _write('DELETE', '/api/topics/$topicId/summaries/$summaryId', {});
  }

  Future<void> _sort(int topicId, String kind, Map<int, int> order) async {
    _positive(topicId);
    if (order.isEmpty || order.keys.any((id) => id <= 0)) {
      throw const FormatException('Invalid topic sort');
    }
    await _write('PATCH', '/api/topics/$topicId/$kind/sort', {
      'items': [
        for (final entry in order.entries)
          {'id': entry.key, 'order_sort': entry.value},
      ],
    });
  }

  @override
  Future<void> sortSummaries(int topicId, Map<int, int> order) =>
      _sort(topicId, 'summaries', order);
  @override
  Future<void> sortResources(int topicId, Map<int, int> order) =>
      _sort(topicId, 'resources', order);
  @override
  Future<TopicResource> addResource(TopicResource resource) async {
    if (resource.id != null) {
      throw const FormatException(
        'Resource references cannot be updated by this API',
      );
    }
    final result = TopicResource.fromJson(
      await _write(
        'POST',
        '/api/topics/${resource.topicId}/resources',
        resource.writeBody(),
      ),
    );
    if (result.topicId != resource.topicId ||
        result.targetId != resource.targetId ||
        result.type != resource.type) {
      throw const FormatException('Resource reference mismatch');
    }
    return result;
  }

  @override
  Future<void> removeResource(int topicId, int resourceId) async {
    _positive(topicId);
    _positive(resourceId);
    await _write('DELETE', '/api/topics/$topicId/resources/$resourceId', {});
  }

  @override
  Future<TaskPage> tasks(int topicId, {int page = 1}) async {
    _positive(topicId);
    if (page < 1) throw const FormatException('Invalid page');
    final result = await _get(
      '/api/tasks?${Uri(queryParameters: {'topic_id': '$topicId', 'page': '$page', 'page_size': '100'}).query}',
    );
    _page(result);
    final items = (result['data'] as List? ?? [])
        .map((row) => TaskItem.fromJson(row as Map))
        .toList();
    if (items.any((item) => item.topicId != topicId)) {
      throw const FormatException('Task topic mismatch');
    }
    return TaskPage(
      items: items,
      total: result['total'] as int,
      page: result['page'] as int,
      pageSize: result['page_size'] as int,
    );
  }

  @override
  Future<TopicCommentPage> comments(
    int topicId, {
    TopicCommentTarget? target,
    int? targetId,
    int page = 1,
  }) async {
    _positive(topicId);
    if (page < 1 || ((target == null) != (targetId == null))) {
      throw const FormatException('Invalid topic comments query');
    }
    if (targetId != null) _positive(targetId);
    final result = await _get(
      '/api/topics/$topicId/comments?${Uri(queryParameters: {'page': '$page', 'page_size': '100', if (target != null) 'target_type': target.name, if (targetId != null) 'target_id': '$targetId'}).query}',
    );
    _page(result);
    final rows = (result['data'] as List? ?? [])
        .map((row) => TopicComment.fromJson(row as Map))
        .toList();
    if (rows.any(
      (item) =>
          item.topicId != topicId ||
          (target != null &&
              (item.target != target || item.targetId != targetId)),
    )) {
      throw const FormatException('Comment target mismatch');
    }
    return TopicCommentPage(
      List.unmodifiable(rows),
      result['total'] as int,
      result['page'] as int,
      result['page_size'] as int,
    );
  }

  @override
  Future<TopicComment> saveComment(TopicComment comment) async {
    final body = comment.writeBody(updating: comment.id != null);
    final row = comment.id == null
        ? await _create('comment', comment.topicId, body)
        : await _write(
            'PUT',
            '/api/topics/${comment.topicId}/comments/${comment.id}',
            body,
          );
    final saved = TopicComment.fromJson(row);
    if (saved.topicId != comment.topicId ||
        saved.target != comment.target ||
        saved.targetId != comment.targetId ||
        saved.memberId != memberId ||
        (comment.id != null && saved.id != comment.id)) {
      throw const FormatException('Comment ID mismatch');
    }
    return saved;
  }

  @override
  Future<void> removeComment(int topicId, int commentId) async {
    _positive(topicId);
    _positive(commentId);
    await _write('DELETE', '/api/topics/$topicId/comments/$commentId', {});
  }

  @override
  Future<List<TopicDailyCount>> dailyCounts(int year, int month) async {
    if (year < 1970 || year > 9999 || month < 1 || month > 12) {
      throw const FormatException('Invalid topic calendar month');
    }
    final result = await _get(
      '/api/topics/daily-counts?year=$year&month=$month',
    );
    return List.unmodifiable(
      (result['data'] as List? ?? []).map(
        (row) => TopicDailyCount.fromJson(row as Map),
      ),
    );
  }
}
