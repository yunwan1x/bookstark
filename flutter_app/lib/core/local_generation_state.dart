import 'dart:convert';
import 'package:crypto/crypto.dart';

bool _id(String value) => RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool _hash(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
String localPointerSHA256(String? raw) =>
    sha256.convert(raw == null ? const <int>[] : utf8.encode(raw)).toString();

Map<String, dynamic> _object(String raw, Set<String> keys, int maxBytes) {
  if (utf8.encode(raw).length > maxBytes) {
    throw const FormatException('Oversized local activation metadata');
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic> ||
      decoded.length != keys.length ||
      !decoded.keys.toSet().containsAll(keys) ||
      jsonEncode(decoded) != raw ||
      (decoded['format'] is! int || decoded['format'] != 1)) {
    throw const FormatException(
      'Unsupported or noncanonical local activation metadata',
    );
  }
  return decoded;
}

class LocalGenerationPointer {
  LocalGenerationPointer({
    required this.generation,
    required this.epoch,
    required this.activationId,
    required this.sourceSHA256,
  }) {
    if (!_id(generation) ||
        !_id(activationId) ||
        !_hash(sourceSHA256) ||
        epoch < 1 ||
        epoch > 0x1ffffffffffffe) {
      throw const FormatException('Invalid local generation pointer');
    }
  }
  final String generation, activationId, sourceSHA256;
  final int epoch;
  String encode() => jsonEncode({
    'format': 1,
    'generation': generation,
    'epoch': epoch,
    'activationId': activationId,
    'sourceSHA256': sourceSHA256,
  });
  factory LocalGenerationPointer.parse(String raw) {
    final value = _object(raw, {
      'format',
      'generation',
      'epoch',
      'activationId',
      'sourceSHA256',
    }, 4096);
    if (value['generation'] is! String ||
        value['epoch'] is! int ||
        value['activationId'] is! String ||
        value['sourceSHA256'] is! String) {
      throw const FormatException('Invalid local generation pointer fields');
    }
    return LocalGenerationPointer(
      generation: value['generation'] as String,
      epoch: value['epoch'] as int,
      activationId: value['activationId'] as String,
      sourceSHA256: value['sourceSHA256'] as String,
    );
  }
}

class LocalRetention {
  LocalRetention({
    required this.id,
    required this.sourcePointerSHA256,
    required this.sourceGeneration,
    required this.manifestSHA256,
  }) {
    if (!_id(id) ||
        !_hash(sourcePointerSHA256) ||
        !_hash(manifestSHA256) ||
        sourceGeneration != 'legacy' && !_id(sourceGeneration)) {
      throw const FormatException('Invalid local retention metadata');
    }
  }
  final String id, sourcePointerSHA256, sourceGeneration, manifestSHA256;
  String encode() => jsonEncode({
    'format': 1,
    'id': id,
    'sourcePointerSHA256': sourcePointerSHA256,
    'sourceGeneration': sourceGeneration,
    'manifestSHA256': manifestSHA256,
  });
  factory LocalRetention.parse(String raw) {
    final value = _object(raw, {
      'format',
      'id',
      'sourcePointerSHA256',
      'sourceGeneration',
      'manifestSHA256',
    }, 4096);
    if (value['id'] is! String ||
        value['sourcePointerSHA256'] is! String ||
        value['sourceGeneration'] is! String ||
        value['manifestSHA256'] is! String) {
      throw const FormatException('Invalid local retention fields');
    }
    return LocalRetention(
      id: value['id'] as String,
      sourcePointerSHA256: value['sourcePointerSHA256'] as String,
      sourceGeneration: value['sourceGeneration'] as String,
      manifestSHA256: value['manifestSHA256'] as String,
    );
  }
}

/// A durable intent binds a new working copy and an immutable pre-restore copy.
/// It is metadata only; file/schema validation and directory fsync are separate.
class LocalRestoreIntent {
  LocalRestoreIntent({
    required this.operationId,
    required this.sourcePointerRaw,
    required this.retainedId,
    required this.retainedManifestSHA256,
    required this.targetPointerRaw,
  }) {
    final from = sourcePointerRaw == null
        ? null
        : LocalGenerationPointer.parse(sourcePointerRaw!);
    final to = LocalGenerationPointer.parse(targetPointerRaw);
    if (!_id(operationId) ||
        !_id(retainedId) ||
        !_hash(retainedManifestSHA256) ||
        to.activationId != operationId ||
        to.epoch != (from?.epoch ?? 0) + 1 ||
        to.generation == from?.generation) {
      throw const FormatException('Invalid local restore intent binding');
    }
  }
  final String operationId,
      retainedId,
      retainedManifestSHA256,
      targetPointerRaw;
  final String? sourcePointerRaw;
  String get sourcePointerSHA256 => localPointerSHA256(sourcePointerRaw);
  String encode() => jsonEncode({
    'format': 1,
    'operationId': operationId,
    'sourcePointer': sourcePointerRaw,
    'sourcePointerSHA256': sourcePointerSHA256,
    'retainedId': retainedId,
    'retainedManifestSHA256': retainedManifestSHA256,
    'targetPointer': targetPointerRaw,
  });
  factory LocalRestoreIntent.parse(String raw) {
    final value = _object(raw, {
      'format',
      'operationId',
      'sourcePointer',
      'sourcePointerSHA256',
      'retainedId',
      'retainedManifestSHA256',
      'targetPointer',
    }, 16384);
    if (value['operationId'] is! String ||
        value['sourcePointer'] != null && value['sourcePointer'] is! String ||
        value['sourcePointerSHA256'] is! String ||
        value['retainedId'] is! String ||
        value['retainedManifestSHA256'] is! String ||
        value['targetPointer'] is! String) {
      throw const FormatException('Invalid local restore intent fields');
    }
    final result = LocalRestoreIntent(
      operationId: value['operationId'] as String,
      sourcePointerRaw: value['sourcePointer'] as String?,
      retainedId: value['retainedId'] as String,
      retainedManifestSHA256: value['retainedManifestSHA256'] as String,
      targetPointerRaw: value['targetPointer'] as String,
    );
    if (result.sourcePointerSHA256 != value['sourcePointerSHA256']) {
      throw const FormatException('Local restore baseline pointer changed');
    }
    return result;
  }
}

enum LocalGenerationPhase { ready, retained, prepared, switched, inconsistent }

class LocalGenerationObservation {
  LocalGenerationObservation._({
    required this.phase,
    required this.pointer,
    required this.intent,
    required this.currentRetention,
    required this.sourceRetention,
  });
  final LocalGenerationPhase phase;
  final LocalGenerationPointer? pointer;
  final LocalRestoreIntent? intent;
  final LocalRetention? currentRetention, sourceRetention;
  bool get needsReview => phase != LocalGenerationPhase.ready;
  bool get canAcknowledgeApplied => phase == LocalGenerationPhase.switched;
  bool get canFinishUnapplied => phase == LocalGenerationPhase.prepared;
  bool get canReenterUnchangedSource => phase == LocalGenerationPhase.retained;

  factory LocalGenerationObservation.inspect({
    required String? pointerRaw,
    required String? intentRaw,
    required String? currentRetentionRaw,
    required String? sourceRetentionRaw,
  }) {
    final pointer = pointerRaw == null
        ? null
        : LocalGenerationPointer.parse(pointerRaw);
    final intent = intentRaw == null
        ? null
        : LocalRestoreIntent.parse(intentRaw);
    final current = currentRetentionRaw == null
        ? null
        : LocalRetention.parse(currentRetentionRaw);
    final source = sourceRetentionRaw == null
        ? null
        : LocalRetention.parse(sourceRetentionRaw);
    bool matches(
      LocalRetention? retention,
      String? raw, {
      String? id,
      String? manifest,
    }) {
      final generation = raw == null
          ? 'legacy'
          : LocalGenerationPointer.parse(raw).generation;
      return retention != null &&
          retention.sourcePointerSHA256 == localPointerSHA256(raw) &&
          retention.sourceGeneration == generation &&
          (id == null || retention.id == id) &&
          (manifest == null || retention.manifestSHA256 == manifest);
    }

    var phase = LocalGenerationPhase.inconsistent;
    if (intent == null) {
      if (source == null) {
        if (current == null) {
          phase = LocalGenerationPhase.ready;
        } else if (matches(current, pointerRaw)) {
          phase = LocalGenerationPhase.retained;
        }
      }
    } else {
      final sourceValid = matches(
        source,
        intent.sourcePointerRaw,
        id: intent.retainedId,
        manifest: intent.retainedManifestSHA256,
      );
      if (sourceValid &&
          pointerRaw == intent.sourcePointerRaw &&
          matches(
            current,
            pointerRaw,
            id: intent.retainedId,
            manifest: intent.retainedManifestSHA256,
          )) {
        phase = LocalGenerationPhase.prepared;
      } else if (sourceValid &&
          pointerRaw == intent.targetPointerRaw &&
          current == null) {
        phase = LocalGenerationPhase.switched;
      }
    }
    return LocalGenerationObservation._(
      phase: phase,
      pointer: pointer,
      intent: intent,
      currentRetention: current,
      sourceRetention: source,
    );
  }
}
