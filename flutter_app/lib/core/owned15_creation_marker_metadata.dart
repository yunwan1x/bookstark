import 'dart:convert';

/// Keys-only presence across all generation owners; no marker values are read.
final class Owned15CreationMarkerMetadata {
  const Owned15CreationMarkerMetadata(this.ownerTag);
  static const prefix = 'bookstark.owned15-create.v1';
  static const keyPrefix = '$prefix.';
  final String ownerTag;
  static Owned15CreationMarkerMetadata parse(String key) {
    if (!key.startsWith(keyPrefix) || key.length > 512) {
      throw const FormatException('Invalid creation metadata key');
    }
    final outer = jsonDecode(
      utf8.decode(
        base64Url.decode(key.substring(keyPrefix.length)),
        allowMalformed: false,
      ),
    );
    if (outer is! List ||
        outer.length != 2 ||
        outer[0] is! String ||
        outer[1] is! int ||
        outer[1] != 0 ||
        !RegExp(
          r'^[a-f0-9]{64}'
          r'$',
        ).hasMatch(outer[0] as String)) {
      throw const FormatException('Invalid creation metadata identity');
    }
    final canonical =
        keyPrefix + base64Url.encode(utf8.encode(jsonEncode(outer)));
    if (canonical != key) {
      throw const FormatException('Noncanonical creation metadata');
    }
    return Owned15CreationMarkerMetadata(outer[0] as String);
  }
}
