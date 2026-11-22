import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_json.dart';

enum TaskCreationOrigin {
  postAcknowledgement,
  manualExisting,
  localTransactionAcknowledgement,
}

enum TaskCreationPhase { pending, unknown, knownID }

class TaskCreationAttempt {
  TaskCreationAttempt({
    required this.scope,
    required this.key,
    required Map<String, Object?> body,
    this.phase = TaskCreationPhase.pending,
    this.actualId,
    this.origin,
    this.draftNamespace,
  }) : body = Map.unmodifiable({
         for (final key in const [
           'content',
           'due_date',
           'done',
           'parent_id',
           'topic_id',
         ])
           if (body.containsKey(key)) key: body[key],
       }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        (phase == TaskCreationPhase.knownID
            ? ((actualId ?? 0) <= 0 || origin == null)
            : (actualId != null || origin != null))) {
      throw const FormatException('Invalid task creation identity');
    }
    final namespace = draftNamespace;
    if (namespace != null) {
      _unicode(namespace);
      if (namespace.isEmpty ||
          utf8.encode(namespace).length > 8192 ||
          namespace.codeUnits.any((unit) => unit < 32 || unit == 127)) {
        throw const FormatException('Invalid task draft namespace');
      }
    }
    const fields = {'content', 'due_date', 'done', 'parent_id', 'topic_id'};
    if (body.length != fields.length ||
        !body.keys.toSet().containsAll(fields) ||
        body['content'] is! String ||
        body['due_date'] is! String ||
        body['done'] is! bool ||
        body['parent_id'] is! int ||
        body['topic_id'] is! int) {
      throw const FormatException('Exact frozen task input required');
    }
    final content = body['content'] as String;
    final date = body['due_date'] as String;
    _unicode(content);
    if (content != content.trim() ||
        content.isEmpty ||
        content.runes.length > 1000 ||
        (body['parent_id'] as int) < 0 ||
        (body['topic_id'] as int) < 0 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw const FormatException('Invalid frozen task input');
    }
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        parsed.year < 1 ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Actual task date required');
    }
  }

  final String scope, key;
  final String? draftNamespace;
  final Map<String, Object?> body;
  final TaskCreationPhase phase;
  final int? actualId;
  final TaskCreationOrigin? origin;
  static void _unicode(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length ||
            value.codeUnitAt(i) < 0xdc00 ||
            value.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Invalid task Unicode');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid task Unicode');
      }
    }
  }

  String get inputDigest =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();
  TaskCreationAttempt next(
    TaskCreationPhase value, [
    int? id,
    TaskCreationOrigin? origin,
  ]) => TaskCreationAttempt(
    scope: scope,
    key: key,
    body: body,
    phase: value,
    actualId: id,
    origin: origin,
    draftNamespace: draftNamespace,
  );
  String encode() => jsonEncode({
    'version': 2,
    'scope': scope,
    'key': key,
    'body': body,
    'phase': phase.name,
    'actualId': actualId,
    'origin': origin?.name,
    'draftNamespace': draftNamespace,
  });
  static TaskCreationAttempt decode(String raw) {
    if (raw.length > 32768) {
      throw const FormatException('Task record exceeds budget');
    }
    _unicode(raw);
    final r = decodeLegacyJson(
      utf8.encode(raw),
      limits: const LegacyJsonLimits(
        maxBytes: 32768,
        maxStringBytes: 8192,
        maxEncodedStringCharacters: 32768,
        maxDepth: 6,
        maxNodes: 64,
        maxObjectMembers: 8,
        maxArrayLength: 8,
      ),
    );
    const fields = {
      'version',
      'scope',
      'key',
      'body',
      'phase',
      'actualId',
      'origin',
      'draftNamespace',
    };
    final legacy = r is Map && r['version'] == 1;
    final expected = legacy ? fields.difference({'draftNamespace'}) : fields;
    if (r is! Map ||
        r.length != expected.length ||
        !r.keys.toSet().containsAll(expected) ||
        (r['version'] != 1 && r['version'] != 2)) {
      throw const FormatException('Invalid task creation record');
    }
    return TaskCreationAttempt(
      draftNamespace: legacy ? null : r['draftNamespace'] as String?,
      scope: r['scope'] as String,
      key: r['key'] as String,
      body: Map<String, Object?>.from(r['body'] as Map),
      phase: TaskCreationPhase.values.byName(r['phase'] as String),
      actualId: r['actualId'] as int?,
      origin: r['origin'] == null
          ? null
          : TaskCreationOrigin.values.byName(r['origin'] as String),
    );
  }
}
