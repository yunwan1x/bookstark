import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import '../../core/task_action_drafts.dart';

/// Own one instance per editor. Inject .bindings, then call retire() in the
/// route's finally. This service never calls TasksRepository.save or any SQL.
class TaskEditorRemoteActions {
  TaskEditorRemoteActions({
    required this.client,
    required this.memberId,
    required this.scope,
    required this.isCurrent,
    TopicsRepository? topics,
    this.instruction =
        '改写这条待办，使行动清晰具体。只返回一条待办的正文，最多1000字，不增加日期、父任务、专题或完成状态，不执行任何操作。',
  }) : _session = jsonEncode(client.exportSession()),
       _revision = client.sessionRevision {
    if ((client.exportSession()['csrf_token'] ?? '').isEmpty ||
        memberId <= 0 ||
        scope.isEmpty ||
        instruction.trim().isEmpty ||
        instruction.runes.length > 2000) {
      throw const FormatException('Existing owned task action scope required');
    }
    final repository =
        topics ?? RemoteTopicsRepository(client, memberId: memberId);
    if (repository.memberId != memberId) {
      throw const FormatException('Wrong topic source owner');
    }
    final source = OwnedTaskTopicSource(
      repository: repository,
      scope: scope,
      isCurrent: _current,
    );
    bindings = TaskEditorActionBindings(
      scope: scope,
      memberId: memberId,
      isCurrent: _current,
      verifyExistingOwner: verifyExistingOwner,
      generateSuggestion: generateSuggestion,
      topicSource: source,
    );
  }

  /// Use for normal UI wiring: legitimate CSRF bootstrap happens BEFORE the
  /// immutable session snapshot. No AI request or resource write occurs here.
  static Future<TaskEditorRemoteActions> create({
    required BookstarkClient client,
    required int memberId,
    required String scope,
    required bool Function() isCurrent,
    TopicsRepository? topics,
    Future<void>? abortTrigger,
  }) async {
    final revision = client.sessionRevision;
    final token = client.exportSession()['token'];
    if (token == null || token.isEmpty || !isCurrent()) {
      throw const TaskActionRetired();
    }
    await client.prepareTaskCompletion(abortTrigger: abortTrigger);
    if (!isCurrent() ||
        client.sessionRevision != revision ||
        client.exportSession()['token'] != token) {
      throw const TaskActionRetired();
    }
    return TaskEditorRemoteActions(
      client: client,
      memberId: memberId,
      scope: scope,
      isCurrent: isCurrent,
      topics: topics,
    );
  }

  final BookstarkClient client;
  final int memberId, _revision;
  final String scope, instruction, _session;
  final bool Function() isCurrent;
  late final TaskEditorActionBindings bindings;
  final _stopped = Completer<void>();
  bool _retired = false, _generating = false;
  bool _current() {
    if (_retired ||
        _stopped.isCompleted ||
        client.sessionRevision != _revision ||
        jsonEncode(client.exportSession()) != _session ||
        (client.exportSession()['token'] ?? '').isEmpty) {
      return false;
    }
    try {
      return isCurrent();
    } catch (_) {
      return false;
    }
  }

  void _guard() {
    if (!_current()) throw const TaskActionRetired();
  }

  void retire() {
    _retired = true;
    if (!_stopped.isCompleted) _stopped.complete();
  }

  Future<bool> verifyExistingOwner(int taskId) async {
    _guard();
    if (taskId <= 0) throw const FormatException('Existing task ID required');
    final envelope = await client.ownedTaskMetadataJson(
      taskId,
      abortTrigger: _stopped.future,
    );
    _guard();
    final row = envelope['data'];
    if (row is! Map ||
        row['task_id'] != taskId ||
        row['member_id'] is! int ||
        row['member_id'] != memberId) {
      return false;
    }
    // Validate the ACTUAL raw row before TaskItem drops its member identity.
    final actual = TaskItem.fromJson(row);
    return actual.id == taskId;
  }

  Future<TaskTextSuggestion> generateSuggestion(
    TaskActionSnapshot origin,
  ) async {
    _guard();
    if (_generating ||
        origin.scope != scope ||
        origin.memberId != memberId ||
        origin.task.id == null ||
        origin.task.id! <= 0 ||
        origin.task.content.trim().isEmpty ||
        origin.task.content.runes.length > 1000) {
      throw const TaskActionChanged();
    }
    _generating = true;
    final stopped = Completer<void>();
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 60), () {
      timedOut = true;
      if (!stopped.isCompleted) stopped.complete();
    });
    final abort = Future.any<void>([_stopped.future, stopped.future]);
    void guard() {
      _guard();
      if (timedOut) throw TimeoutException('Task suggestion timed out');
    }

    try {
      if (!await verifyExistingOwner(origin.task.id!)) {
        throw const TaskActionRetired();
      }
      guard();
      final body = <String, Object?>{
        'scene': 'task',
        'messages': [
          {
            'role': 'system',
            'content': '你只提供可审核的待办文本建议。只返回正文，不调用工具、不生成操作提案、不执行保存、不声称已修改任务。',
          },
          {
            'role': 'user',
            'content': '当前待办原文：\n${origin.task.content}\n\n要求：\n$instruction',
          },
        ],
      };
      if (utf8.encode(jsonEncode(body)).length > 32 * 1024) {
        throw const FormatException('Task suggestion request exceeds bound');
      }
      final answer = StringBuffer();
      var runes = 0;
      await for (final event
          in client
              .postEvents(
                '/api/ai/complete',
                body,
                abortTrigger: abort,
                beforeSubmit: guard,
              )
              .timeout(const Duration(seconds: 30))) {
        guard();
        if (event.type != 'message' &&
            !(event.type == 'done' && event.data == '[DONE]')) {
          throw const FormatException(
            'Only completion text events are allowed',
          );
        }
        if (event.data == '[DONE]') {
          final text = answer.toString();
          if (text.trim().isEmpty) {
            throw const FormatException('Empty suggestion');
          }
          if (!await verifyExistingOwner(origin.task.id!)) {
            throw const TaskActionRetired();
          }
          guard();
          return TaskTextSuggestion(
            origin: origin,
            content: text,
            complete: true,
          );
        }
        final frame = jsonDecode(event.data);
        if (frame is! Map ||
            frame['error'] != null ||
            frame.containsKey('proposal') ||
            frame.containsKey('tool_calls')) {
          throw const FormatException('Invalid task text completion');
        }
        final choices = frame['choices'];
        if (choices is! List) {
          if (frame['usage'] is Map) continue;
          throw const FormatException('Invalid task completion choices');
        }
        if (choices.isEmpty) continue;
        if (choices.length != 1 || choices.single is! Map) {
          throw const FormatException('Ambiguous task completion');
        }
        final choice = choices.single as Map;
        final reason = choice['finish_reason'];
        if (reason != null && reason != 'stop') {
          throw const FormatException('Incomplete task suggestion');
        }
        final delta = choice['delta'];
        if (delta == null) continue;
        if (delta is! Map ||
            delta.containsKey('tool_calls') ||
            delta.containsKey('function_call') ||
            (delta['content'] != null && delta['content'] is! String)) {
          throw const FormatException('Only text suggestions are allowed');
        }
        final text = delta['content'] as String? ?? '';
        runes += text.runes.length;
        if (runes > 1000) {
          throw const FormatException('Task suggestion too long');
        }
        answer.write(text);
      }
      throw const FormatException('Task suggestion ended without completion');
    } finally {
      timer.cancel();
      if (!stopped.isCompleted) stopped.complete();
      _generating = false;
    }
  }
}
