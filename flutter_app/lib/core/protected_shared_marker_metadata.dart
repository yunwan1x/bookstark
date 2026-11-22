import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Keys-only inventory may parse this key without loading a marker value.
/// It must never report a marker phase or resource content from key existence.
class ProtectedSharedMarkerKey {
  const ProtectedSharedMarkerKey._(this.principal);
  static const prefix = 'bookstark.protectedSharedOp.v1.';
  final String principal;
  String get storageKey => prefix + principal;
  static ProtectedSharedMarkerKey? tryParse(String key) {
    if (!key.startsWith(prefix)) return null;
    final suffix = key.substring(prefix.length);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(suffix)) return null;
    return ProtectedSharedMarkerKey._(suffix);
  }

  factory ProtectedSharedMarkerKey(String principal) {
    final key = tryParse(prefix + principal);
    if (key == null) {
      throw const FormatException('Invalid shared marker principal');
    }
    return key;
  }
}

enum ProtectedSharedMarkerPhase { unknown, known }

class ProtectedSharedMarkerMetadata {
  ProtectedSharedMarkerMetadata({
    required this.key,
    required this.operation,
    required this.capabilityPrincipal,
    required this.identity,
    required this.expectedSource,
    required this.submittedSource,
    required this.phase,
    this.modified,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(operation) ||
        ![
          capabilityPrincipal,
          identity,
          expectedSource,
          submittedSource,
        ].every((v) => RegExp(r'^[a-f0-9]{64}$').hasMatch(v)) ||
        (phase == ProtectedSharedMarkerPhase.unknown && modified != null) ||
        (phase == ProtectedSharedMarkerPhase.known &&
            (modified == null ||
                modified!.isEmpty ||
                modified!.length > 128 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(modified!)))) {
      throw const FormatException('Invalid shared marker metadata');
    }
    if (key.principal != principalFor(capabilityPrincipal, identity)) {
      throw const FormatException('Shared marker identity/key mismatch');
    }
  }
  final ProtectedSharedMarkerKey key;
  final String operation,
      capabilityPrincipal,
      identity,
      expectedSource,
      submittedSource;
  final ProtectedSharedMarkerPhase phase;
  final String? modified;
  static String principalFor(String capabilityPrincipal, String identity) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'protected-shared-v1',
                capabilityPrincipal,
                identity,
              ]),
            ),
          )
          .toString();
  Map<String, Object?> toJson() => {
    'version': 1,
    'principal': key.principal,
    'operation': operation,
    'capabilityPrincipal': capabilityPrincipal,
    'identity': identity,
    'expectedSource': expectedSource,
    'submittedSource': submittedSource,
    'phase': phase.name,
    'modified': modified,
  };
  String encode() => jsonEncode(toJson());
  factory ProtectedSharedMarkerMetadata.parse(
    ProtectedSharedMarkerKey key,
    String raw,
  ) {
    if (utf8.encode(raw).length > 4096) {
      throw const FormatException('Shared marker exceeds bound');
    }
    final value = jsonDecode(raw);
    const keys = {
      'version',
      'principal',
      'operation',
      'capabilityPrincipal',
      'identity',
      'expectedSource',
      'submittedSource',
      'phase',
      'modified',
    };
    if (value is! Map ||
        value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['version'] != 1 ||
        value['principal'] != key.principal ||
        value['operation'] is! String ||
        value['capabilityPrincipal'] is! String ||
        value['identity'] is! String ||
        value['expectedSource'] is! String ||
        value['submittedSource'] is! String ||
        !{'unknown', 'known'}.contains(value['phase']) ||
        (value['modified'] != null && value['modified'] is! String)) {
      throw const FormatException('Invalid shared marker metadata');
    }
    final parsed = ProtectedSharedMarkerMetadata(
      key: key,
      operation: value['operation'] as String,
      capabilityPrincipal: value['capabilityPrincipal'] as String,
      identity: value['identity'] as String,
      expectedSource: value['expectedSource'] as String,
      submittedSource: value['submittedSource'] as String,
      phase: ProtectedSharedMarkerPhase.values.byName(value['phase'] as String),
      modified: value['modified'] as String?,
    );
    if (parsed.encode() != raw) {
      throw const FormatException('Shared marker must be canonical');
    }
    return parsed;
  }
}
