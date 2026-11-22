import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_json.dart';

enum TopicCreationKind { topic, summary, comment }

enum TopicCreationPhase { pending, unknown, knownID }

class TopicCreationAttempt {
  TopicCreationAttempt({
    required this.scope,
    required this.key,
    required this.kind,
    required this.topicId,
    required this.target,
    required this.targetId,
    required Map<String, Object?> body,
    this.phase = TopicCreationPhase.pending,
    this.actualId,
  }) : body = Map.unmodifiable(body) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        (kind == TopicCreationKind.topic ? topicId != 0 : topicId <= 0) ||
        (kind == TopicCreationKind.comment
            ? !{'summary', 'resource', 'task'}.contains(target) || targetId <= 0
            : target.isNotEmpty || targetId != 0) ||
        (phase == TopicCreationPhase.knownID
            ? (actualId ?? 0) <= 0
            : actualId != null)) {
      throw const FormatException('Invalid topic creation identity');
    }
    final Set<String> keys;
    if (kind == TopicCreationKind.topic) {
      keys = {'title', 'question', 'is_pinned'};
      if (body['title'] is! String ||
          body['question'] is! String ||
          body['is_pinned'] is! bool ||
          (body['title'] as String).trim().isEmpty ||
          (body['title'] as String).runes.length > 200 ||
          (body['question'] as String).runes.length > 2000) {
        throw const FormatException('Invalid frozen topic input');
      }
    } else {
      keys = kind == TopicCreationKind.summary
          ? {'content', 'summary_type', 'order_sort'}
          : {'content', 'target_type', 'target_id', 'parent_comment_id'};
      if (body['content'] is! String ||
          (body['content'] as String).trim().isEmpty ||
          (body['content'] as String).runes.length > 20000) {
        throw const FormatException('Invalid frozen source');
      }
      if (kind == TopicCreationKind.summary) {
        if (!{'manual', 'ai'}.contains(body['summary_type']) ||
            body['order_sort'] is! int) {
          throw const FormatException('Invalid summary metadata');
        }
      } else if (body['target_type'] != target ||
          body['target_id'] != targetId ||
          body['parent_comment_id'] != 0) {
        throw const FormatException('Frozen comment target differs');
      }
    }
    if (body.length != keys.length || !body.keys.toSet().containsAll(keys)) {
      throw const FormatException('Unexpected frozen input fields');
    }
    for (final value in body.values.whereType<String>()) {
      for (var i = 0; i < value.length; i++) {
        final c = value.codeUnitAt(i);
        if (c >= 0xd800 && c <= 0xdbff) {
          if (i + 1 >= value.length ||
              value.codeUnitAt(++i) < 0xdc00 ||
              value.codeUnitAt(i) > 0xdfff) {
            throw const FormatException('Invalid source Unicode');
          }
        } else if (c >= 0xdc00 && c <= 0xdfff) {
          throw const FormatException('Invalid source Unicode');
        }
      }
    }
    if (utf8.encode(jsonEncode(body)).length > 256 * 1024) {
      throw const FormatException('Creation input exceeds bound');
    }
  }
  final String scope, key, target;
  final TopicCreationKind kind;
  final int topicId, targetId;
  final Map<String, Object?> body;
  final TopicCreationPhase phase;
  final int? actualId;
  String get inputDigest =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();
  String get path => kind == TopicCreationKind.topic
      ? '/api/topics'
      : '/api/topics/$topicId/${kind == TopicCreationKind.summary ? 'summaries' : 'comments'}';
  TopicCreationAttempt next(TopicCreationPhase phase, [int? id]) =>
      TopicCreationAttempt(
        scope: scope,
        key: key,
        kind: kind,
        topicId: topicId,
        target: target,
        targetId: targetId,
        body: body,
        phase: phase,
        actualId: id,
      );
  String encode() => jsonEncode({
    'version': 1,
    'scope': scope,
    'key': key,
    'kind': kind.name,
    'topicId': topicId,
    'target': target,
    'targetId': targetId,
    'body': body,
    'phase': phase.name,
    'actualId': actualId,
  });
  static TopicCreationAttempt decode(String raw) {
    if (raw.length > 512 * 1024 || utf8.encode(raw).length > 512 * 1024) {
      throw const FormatException('Bounded creation record required');
    }
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= raw.length ||
            raw.codeUnitAt(i) < 0xdc00 ||
            raw.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Invalid creation record Unicode');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid creation record Unicode');
      }
    }
    final r = decodeLegacyJson(
      utf8.encode(raw),
      limits: const LegacyJsonLimits(
        maxBytes: 512 * 1024,
        maxStringBytes: 80000,
        maxEncodedStringCharacters: 512 * 1024,
        maxDepth: 8,
        maxNodes: 1024,
        maxObjectMembers: 16,
        maxArrayLength: 16,
      ),
    );
    if (r is! Map || r['version'] != 1 || r.length != 10) {
      throw const FormatException('Invalid creation record');
    }
    return TopicCreationAttempt(
      scope: r['scope'] as String,
      key: r['key'] as String,
      kind: TopicCreationKind.values.byName(r['kind'] as String),
      topicId: r['topicId'] as int,
      target: r['target'] as String,
      targetId: r['targetId'] as int,
      body: Map<String, Object?>.from(r['body'] as Map),
      phase: TopicCreationPhase.values.byName(r['phase'] as String),
      actualId: r['actualId'] as int?,
    );
  }
}
