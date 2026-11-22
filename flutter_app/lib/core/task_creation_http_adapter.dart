import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'task_creation_attempt.dart';
import 'task_creation_controller.dart';

class TaskCreationHttpAdapter {
  TaskCreationHttpAdapter({
    required this.client,
    required this.memberId,
    required String namespace,
    required this.isCurrent,
  }) : revision = client.sessionRevision,
       scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([client.baseUri.toString(), memberId, namespace]),
             ),
           )
           .toString();
  final BookstarkClient client;
  final int memberId, revision;
  final String scope;
  final bool Function() isCurrent;
  final _abort = Completer<void>();
  bool _closed = false;
  void guard() {
    if (_closed || !isCurrent() || client.sessionRevision != revision) {
      throw StateError('Task creation owner retired');
    }
  }

  void retire() {
    if (!_closed) {
      _closed = true;
      _abort.complete();
    }
  }

  Map<String, Object?> _data(Map<String, Object?> root) {
    if (root['code'] != 0 || root['data'] is! Map) {
      throw const FormatException('Complete actual task metadata unavailable');
    }
    return Map<String, Object?>.from(root['data'] as Map);
  }

  Future<void> _actor() async {
    guard();
    final actor = _data(
      await client.boundedCurrentOwnerJson(
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (memberId <= 0 || actor['member_id'] != memberId) {
      throw const FormatException('Initiating task account differs');
    }
  }

  void _identity(TaskCreationAttempt input) {
    guard();
    if (input.scope != scope) throw const FormatException('Task scope differs');
  }

  Future<PreparedAuthenticatedJsonRequest> prepare(
    TaskCreationAttempt input,
  ) async {
    _identity(input);
    await _actor();
    _identity(input);
    final prepared = await client.prepareTaskCreationJson(
      input.body,
      expectedSessionRevision: revision,
      ownerGuard: guard,
      abortTrigger: _abort.future,
    );
    try {
      _identity(input);
      return prepared;
    } catch (_) {
      prepared.retire();
      rethrow;
    }
  }

  Future<TaskCreationReview> inspect(TaskCreationAttempt input, int id) async {
    _identity(input);
    if (id <= 0)
      throw const FormatException('Explicit actual task ID required');
    await _actor();
    _identity(input);
    final row = _data(
      await client.readTaskCreationReviewJson(
        id,
        expectedSessionRevision: revision,
        ownerGuard: guard,
        abortTrigger: _abort.future,
      ),
    );
    _identity(input);
    const fields = {
      'task_id',
      'content',
      'due_date',
      'done',
      'parent_id',
      'topic_id',
      'member_id',
      'complete_time',
      'create_time',
      'modify_time',
      'child_total',
      'child_done',
      'comment_count',
    };
    if (!row.keys.toSet().containsAll(fields) ||
        row['task_id'] != id ||
        row['member_id'] != memberId ||
        row.keys.any((key) => !fields.contains(key) && key != 'children') ||
        (row.containsKey('children') &&
            (row['children'] is! List ||
                (row['children'] as List).isNotEmpty))) {
      throw const FormatException('Actual owned task identity required');
    }
    final body = {for (final key in input.body.keys) key: row[key]};
    // Reuse the exact Unicode/date/type/budget checks without normalizing bytes.
    final actual = TaskCreationAttempt(
      scope: scope,
      key: input.key,
      body: body,
    );
    for (final key in ['child_total', 'child_done', 'comment_count']) {
      if (row[key] is! int || (row[key] as int) < 0) {
        throw const FormatException('Complete task counters required');
      }
    }
    for (final key in ['create_time', 'modify_time']) {
      final value = row[key];
      if (value is! String ||
          value.isEmpty ||
          value.length > 128 ||
          DateTime.tryParse(value) == null) {
        throw const FormatException('Actual task version required');
      }
    }
    final complete = row['complete_time'];
    if (complete != null &&
        (complete is! String ||
            complete.length > 128 ||
            DateTime.tryParse(complete) == null)) {
      throw const FormatException('Invalid task completion metadata');
    }
    final keys = fields.toList()..sort();
    final canonical = {for (final key in keys) key: row[key]};
    return TaskCreationReview(
      id: id,
      fingerprint: sha256
          .convert(utf8.encode(jsonEncode(canonical)))
          .toString(),
      display: jsonEncode(canonical),
      matchesFrozenInput: actual.inputDigest == input.inputDigest,
      wire: Map.unmodifiable(canonical),
    );
  }
}
