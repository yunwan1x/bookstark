import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_json.dart';

enum LabelCreationOrigin {
  postAcknowledgement,
  manualExisting,
  localTransactionAcknowledgement,
}

enum LabelCreationPhase { pending, unknown, knownID }

class LabelCreationAttempt {
  LabelCreationAttempt({
    required this.scope,
    required this.key,
    required Map<String, Object?> body,
    this.phase = LabelCreationPhase.pending,
    this.actualId,
    this.origin,
  }) : body = Map.unmodifiable(body) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        (phase == LabelCreationPhase.knownID
            ? ((actualId ?? 0) <= 0 || origin == null)
            : (actualId != null || origin != null))) {
      throw const FormatException('Invalid label creation identity');
    }
    if (body.length != 1 || body['label_name'] is! String) {
      throw const FormatException('Exact label input required');
    }
    final name = body['label_name'] as String;
    _unicode(name);
    if (name.trim().isEmpty || utf8.encode(name).length > 100) {
      throw const FormatException('Label name must use 1–100 UTF-8 bytes');
    }
  }
  final String scope, key;
  final Map<String, Object?> body;
  final LabelCreationPhase phase;
  final int? actualId;
  final LabelCreationOrigin? origin;
  static void _unicode(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length ||
            value.codeUnitAt(i) < 0xdc00 ||
            value.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Invalid label Unicode');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid label Unicode');
      }
    }
  }

  String get inputDigest =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();
  LabelCreationAttempt next(
    LabelCreationPhase value, [
    int? id,
    LabelCreationOrigin? origin,
  ]) => LabelCreationAttempt(
    scope: scope,
    key: key,
    body: body,
    phase: value,
    actualId: id,
    origin: origin,
  );
  String encode() => jsonEncode({
    'version': 1,
    'scope': scope,
    'key': key,
    'body': body,
    'phase': phase.name,
    'actualId': actualId,
    'origin': origin?.name,
  });
  static LabelCreationAttempt decode(String raw) {
    if (raw.length > 32768) {
      throw const FormatException('Label record exceeds budget');
    }
    _unicode(raw);
    final r = decodeLegacyJson(
      utf8.encode(raw),
      limits: const LegacyJsonLimits(
        maxBytes: 32768,
        maxStringBytes: 4096,
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
    };
    if (r is! Map ||
        r.length != fields.length ||
        !r.keys.toSet().containsAll(fields) ||
        r['version'] != 1) {
      throw const FormatException('Invalid label creation record');
    }
    return LabelCreationAttempt(
      scope: r['scope'] as String,
      key: r['key'] as String,
      body: Map<String, Object?>.from(r['body'] as Map),
      phase: LabelCreationPhase.values.byName(r['phase'] as String),
      actualId: r['actualId'] as int?,
      origin: r['origin'] == null
          ? null
          : LabelCreationOrigin.values.byName(r['origin'] as String),
    );
  }
}
