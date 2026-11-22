import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'topic_creation_attempt.dart';
import 'topic_creation_controller.dart';

class TopicCreationHttpAdapter {
  TopicCreationHttpAdapter({
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
      throw StateError('Topic creation owner retired');
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
      throw const FormatException('Owned resource unavailable');
    }
    return Map<String, Object?>.from(root['data'] as Map);
  }

  Future<void> _owner() async {
    guard();
    final profile = _data(
      await client.boundedCurrentOwnerJson(
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (memberId <= 0 || profile['member_id'] != memberId) {
      throw const FormatException('Topic owner mismatch');
    }
  }

  void _identity(TopicCreationAttempt a) {
    guard();
    if (a.scope != scope) {
      throw const FormatException('Topic creation scope mismatch');
    }
  }

  Future<PreparedAuthenticatedJsonRequest> prepare(
    TopicCreationAttempt a,
  ) async {
    _identity(a);
    await _owner();
    _identity(a);
    final result = await client.prepareTopicCreationJson(
      a.kind.name,
      a.topicId,
      a.body,
      expectedSessionRevision: revision,
      ownerGuard: guard,
      abortTrigger: _abort.future,
    );
    try {
      _identity(a);
      return result;
    } catch (_) {
      result.retire();
      rethrow;
    }
  }

  Future<TopicCreationReview> inspect(TopicCreationAttempt a, int id) async {
    _identity(a);
    if (id <= 0) throw const FormatException('Actual ID required');
    await _owner();
    _identity(a);
    final row = _data(
      await client.readTopicCreationReviewJson(
        a.kind.name,
        id,
        expectedSessionRevision: revision,
        ownerGuard: guard,
        abortTrigger: _abort.future,
      ),
    );
    _identity(a);
    final idKey = a.kind == TopicCreationKind.topic
        ? 'topic_id'
        : a.kind == TopicCreationKind.summary
        ? 'summary_id'
        : 'comment_id';
    if (row[idKey] != id ||
        row['member_id'] != memberId ||
        (a.kind != TopicCreationKind.topic && row['topic_id'] != a.topicId)) {
      throw const FormatException('Actual resource identity differs');
    }
    final expectedKeys = a.kind == TopicCreationKind.topic
        ? {
            'topic_id',
            'member_id',
            'title',
            'question',
            'is_pinned',
            'create_time',
            'modify_time',
          }
        : a.kind == TopicCreationKind.summary
        ? {
            'summary_id',
            'topic_id',
            'member_id',
            'content',
            'summary_type',
            'order_sort',
            'comment_count',
            'create_time',
            'modify_time',
          }
        : {
            'comment_id',
            'topic_id',
            'member_id',
            'target_type',
            'target_id',
            'parent_comment_id',
            'content',
            'author_name',
            'create_time',
            'modify_time',
          };
    if (row.length != expectedKeys.length ||
        !row.keys.toSet().containsAll(expectedKeys)) {
      throw const FormatException('Complete actual metadata required');
    }
    for (final key in ['create_time', 'modify_time']) {
      if (row[key] is! String ||
          DateTime.tryParse(row[key] as String) == null) {
        throw const FormatException('Actual resource version unavailable');
      }
    }
    if (a.kind == TopicCreationKind.summary &&
        (row['comment_count'] is! int || (row['comment_count'] as int) < 0)) {
      throw const FormatException('Actual summary comments unavailable');
    }
    if (a.kind == TopicCreationKind.comment &&
        (row['author_name'] is! String ||
            utf8.encode(row['author_name'] as String).length > 800)) {
      throw const FormatException('Actual comment author unavailable');
    }
    final body = <String, Object?>{};
    for (final key in a.body.keys) {
      final value = row[key];
      if (key == 'is_pinned') {
        if (value != true && value != false && value != 0 && value != 1) {
          throw const FormatException('Invalid topic pin');
        }
        body[key] = value == true || value == 1;
      } else {
        body[key] = value;
      }
    }
    if (a.kind == TopicCreationKind.comment &&
        (row['target_type'] != a.target ||
            row['target_id'] != a.targetId ||
            row['parent_comment_id'] != 0)) {
      throw const FormatException('Actual comment target differs');
    }
    if (a.kind == TopicCreationKind.topic) {
      for (final key in ['title', 'question']) {
        final value = row[key];
        if (value is! String ||
            utf8.encode(value).length > (key == 'title' ? 800 : 8000)) {
          throw const FormatException('Bounded topic metadata required');
        }
      }
    } else {
      final text = row['content'];
      if (text is! String ||
          text.length > 80000 ||
          utf8.encode(text).length > 80000) {
        throw const FormatException('Bounded complete source required');
      }
    }
    // Canonical key order independent of JSON map insertion order.
    final keys = row.keys.toList()..sort();
    final canonical = jsonEncode({for (final key in keys) key: row[key]});
    return TopicCreationReview(
      id: id,
      fingerprint: sha256.convert(utf8.encode(canonical)).toString(),
      display: const JsonEncoder.withIndent('  ').convert(row),
      matchesFrozenInput: a.body.entries.every((e) => body[e.key] == e.value),
      wire: Map.unmodifiable(row),
    );
  }
}
