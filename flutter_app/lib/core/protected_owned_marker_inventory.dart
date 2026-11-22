import 'dart:convert';
import 'protected_owned_marker_metadata.dart';

/// Article WebView is a whole authenticated module, so its internal navigation
/// cannot bypass an unresolved same-owner resource. Keys only; no phase/body
/// or historical server receipt is inferred from the metadata channel.
List<ProtectedOwnedMarkerMetadata> protectedOwnedMarkersForOwner(
  Object? response,
  String ownerTag,
) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(ownerTag)) {
    throw const FormatException('Opaque owner tag required');
  }
  const fields = {
    'format',
    'secureKeys',
    'htmlKeys',
    'overflow',
    'valuesIncluded',
  };
  if (response is! Map ||
      response.length != fields.length ||
      response.keys.toSet().difference(fields).isNotEmpty ||
      response['format'] is! int ||
      response['format'] != 1 ||
      response['valuesIncluded'] != false ||
      response['overflow'] != false ||
      response['secureKeys'] is! List ||
      response['htmlKeys'] is! List) {
    throw const FormatException('Recovery metadata unavailable or overbound');
  }
  final secure = response['secureKeys'] as List,
      html = response['htmlKeys'] as List;
  if (secure.length + html.length > 4096) {
    throw const FormatException('Recovery key count bound');
  }
  var bytes = 0;
  final result = <ProtectedOwnedMarkerMetadata>[];
  for (final entry in {'secure': secure, 'html': html}.entries) {
    for (final value in entry.value) {
      if (value is! String) throw const FormatException('Invalid metadata key');
      bytes += utf8.encode(value).length;
      if (bytes > 1024 * 1024) {
        throw const FormatException('Recovery key byte bound');
      }
      if (!value.startsWith(ProtectedOwnedMarkerMetadata.keyPrefix)) continue;
      if (entry.key != 'secure') {
        throw const FormatException('Protected marker storage mismatch');
      }
      final marker = ProtectedOwnedMarkerMetadata.parse(value);
      if (marker.ownerTag == ownerTag) result.add(marker);
    }
  }
  return List.unmodifiable(result);
}
