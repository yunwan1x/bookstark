import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

class TaskActionChanged implements Exception {
  const TaskActionChanged();
}

class TaskActionRetired implements Exception {
  const TaskActionRetired();
}

class TaskActionSnapshot {
  TaskActionSnapshot({
    required this.scope,
    required this.memberId,
    required this.task,
  }) {
    if (scope.isEmpty || memberId <= 0 || task.id == null || task.id! <= 0) {
      throw const FormatException('Owned existing task required');
    }
  }

  /// Owner must come from a strict raw read, not TaskItem (which drops member_id).
  final String scope;
  final int memberId;
  final TaskItem task;
  String get fingerprint => _digest([
    scope,
    memberId,
    task.id,
    task.content,
    task.dueDate,
    task.done,
    task.parentId,
    task.topicId,
    task.childTotal,
    task.childDone,
    task.modifiedAt,
    task.completedAt,
  ]);
}

class TaskTextSuggestion {
  TaskTextSuggestion({
    required this.origin,
    required this.content,
    required this.complete,
  });
  final TaskActionSnapshot origin;
  final String content;
  final bool complete;
  TaskItem applyToDraft(TaskActionSnapshot fresh) {
    if (!complete || fresh.fingerprint != origin.fingerprint) {
      throw const TaskActionChanged();
    }
    if (content.trim().isEmpty || content.trim().runes.length > 1000) {
      throw const FormatException('Suggestion must contain 1-1000 characters');
    }
    return _copy(fresh.task, content: content);
  }
}

class TaskTopicChoice {
  const TaskTopicChoice.clear() : id = 0;
  TaskTopicChoice.select(this.id) {
    if (id <= 0) throw const FormatException('Positive topic required');
  }

  /// Null choice result means cancel/preserve; zero explicitly clears.
  final int id;
}

TaskItem applyTaskTopic(TaskItem current, TaskTopicChoice? choice) =>
    choice == null ? current : _copy(current, topicId: choice.id);
TaskItem _copy(TaskItem task, {String? content, int? topicId}) => TaskItem(
  id: task.id,
  content: content ?? task.content,
  dueDate: task.dueDate,
  done: task.done,
  parentId: task.parentId,
  topicId: topicId ?? task.topicId,
  childTotal: task.childTotal,
  childDone: task.childDone,
  modifiedAt: task.modifiedAt,
  completedAt: task.completedAt,
);

/// Actual existing TopicsRepository projection; no invented endpoint or write.
class OwnedTaskTopicSource {
  OwnedTaskTopicSource({
    required this.repository,
    required this.scope,
    required this.isCurrent,
  }) {
    if (repository.memberId <= 0 || scope.isEmpty) {
      throw const FormatException('Owned topic source required');
    }
  }
  final TopicsRepository repository;
  final String scope;
  final bool Function() isCurrent;
  int get memberId => repository.memberId;
  void _guard() {
    if (!isCurrent()) throw const TaskActionRetired();
  }

  void _topic(TopicItem topic) {
    if (topic.memberId != memberId || topic.id == null || topic.id! <= 0) {
      throw const FormatException('Foreign or invalid topic');
    }
  }

  Future<TopicPageResult> list(String keyword, int page) async {
    _guard();
    final value = await repository.list(
      TopicQuery(keyword: keyword, page: page),
    );
    _guard();
    if (value.page != page ||
        value.pageSize <= 0 ||
        value.pageSize > 100 ||
        value.total < 0 ||
        value.items.length > value.pageSize) {
      throw const FormatException('Invalid topic page');
    }
    final ids = <int>{};
    for (final topic in value.items) {
      _topic(topic);
      if (!ids.add(topic.id!)) throw const FormatException('Duplicate topic');
    }
    return value;
  }

  Future<TopicItem> inspect(int id) async {
    _guard();
    if (id <= 0) throw const FormatException('Positive topic required');
    final detail = await repository.read(id);
    _guard();
    _topic(detail.topic);
    if (detail.topic.id != id) throw const FormatException('Wrong topic ID');
    return detail.topic;
  }
}

/// Injected only for a known owned space. generateSuggestion must return text,
/// never 06 propose_task or a repository save/SQL tool. Caller owns cancellation.
class TaskEditorActionBindings {
  TaskEditorActionBindings({
    required this.scope,
    required this.memberId,
    required this.isCurrent,
    required this.verifyExistingOwner,
    this.generateSuggestion,
    this.topicSource,
  }) {
    if (scope.isEmpty ||
        memberId <= 0 ||
        topicSource != null &&
            (topicSource!.memberId != memberId ||
                topicSource!.scope != scope)) {
      throw const FormatException('Mismatched task editor action scope');
    }
  }
  final String scope;
  final int memberId;
  final bool Function() isCurrent;
  final Future<bool> Function(int taskId) verifyExistingOwner;
  final Future<TaskTextSuggestion> Function(TaskActionSnapshot origin)?
  generateSuggestion;
  final OwnedTaskTopicSource? topicSource;
  TaskEditorActionBindings guarded(bool Function() extra) =>
      TaskEditorActionBindings(
        scope: scope,
        memberId: memberId,
        isCurrent: () => isCurrent() && extra(),
        verifyExistingOwner: verifyExistingOwner,
        generateSuggestion: generateSuggestion,
        topicSource: topicSource,
      );
}
