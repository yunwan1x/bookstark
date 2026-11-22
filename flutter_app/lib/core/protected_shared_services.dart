import 'dart:convert';
import 'native_recovery_storage.dart';
import 'protected_complex_lifetime.dart';
import 'protected_shared_marker_metadata.dart';

class ProtectedSharedServices {
  const ProtectedSharedServices({
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    required this.flush,
    required this.listKeys,
    required this.registerOwner,
    required this.unregisterOwner,
  });
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  final Future<void> Function() flush;
  final Future<List<String>> Function() listKeys;
  final void Function(ProtectedComplexOwner) registerOwner, unregisterOwner;
}

/// Existing native keys-only channel, with C44 shared prefix allowlist included.
/// No _storage.readAll or other draft values are ever requested here.
Future<List<String>> nativeProtectedSharedKeys() async {
  final raw = await NativeRecoveryStorage.channel
      .invokeMethod<Object?>('localMetadata')
      .timeout(const Duration(seconds: 30));
  const fields = {
    'format',
    'secureKeys',
    'htmlKeys',
    'overflow',
    'valuesIncluded',
  };
  if (raw is! Map ||
      raw.length != fields.length ||
      !raw.keys.every(fields.contains) ||
      raw['format'] != 1 ||
      raw['overflow'] != false ||
      raw['valuesIncluded'] != false ||
      raw['secureKeys'] is! List ||
      raw['htmlKeys'] is! List) {
    throw const FormatException('Shared keys-only inventory unavailable');
  }
  final keys = <String>[];
  var bytes = 0;
  for (final value in <Object?>[
    ...(raw['secureKeys'] as List),
    ...(raw['htmlKeys'] as List),
  ]) {
    if (value is! String || value.length > 65536) {
      throw const FormatException('Shared key bound');
    }
    bytes += utf8.encode(value).length;
    if (bytes > 1048576 || keys.length >= 4096) {
      throw const FormatException('Shared key inventory bound');
    }
    keys.add(value);
  }
  // Journal independently validates prefix canonical suffix and shared metadata.
  return keys
      .where((key) => key.startsWith(ProtectedSharedMarkerKey.prefix))
      .toList(growable: false);
}
