import 'dart:convert';

/// This key contains opaque ownership identifiers only. Never decode a value
/// through metadata inspection or infer that a missing key proves no SQL write.
class ProtectedOwnedMarkerMetadata {
  const ProtectedOwnedMarkerMetadata({
    required this.ownerTag,
    required this.scope,
  });
  static const prefix = 'bookstark.protected-owned-marker.v1';
  static const keyPrefix = '$prefix.';
  final String ownerTag, scope;
  static final _hex = RegExp(r'^[a-f0-9]{64}$');
  static ProtectedOwnedMarkerMetadata parse(String key) {
    if (!key.startsWith(keyPrefix) || key.length > 1024) {
      throw const FormatException('Invalid protected metadata key');
    }
    final tail = key.substring(keyPrefix.length);
    final outer = jsonDecode(
      utf8.decode(base64Url.decode(tail), allowMalformed: false),
    );
    if (outer is! List ||
        outer.length != 2 ||
        outer[0] is! String ||
        outer[1] is! int ||
        outer[1] != 0) {
      throw const FormatException('Invalid protected metadata identity');
    }
    final inner = jsonDecode(outer[0] as String);
    if (inner is! List ||
        inner.length != 2 ||
        inner.any((v) => v is! String || !_hex.hasMatch(v))) {
      throw const FormatException('Invalid protected owner');
    }
    final namespace = jsonEncode(inner);
    final canonical =
        keyPrefix + base64Url.encode(utf8.encode(jsonEncode([namespace, 0])));
    if (namespace != outer[0] || canonical != key) {
      throw const FormatException('Noncanonical protected metadata');
    }
    return ProtectedOwnedMarkerMetadata(
      ownerTag: inner[0] as String,
      scope: inner[1] as String,
    );
  }
}
