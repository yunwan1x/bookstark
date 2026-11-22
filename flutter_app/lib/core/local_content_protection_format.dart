import 'dart:convert';
import 'local_content_crypto_limits.dart';

final _localPasswordHash = RegExp(
  r'^\$2[aby]\$(0[4-9]|1[0-4])\$[./A-Za-z0-9]{53}$',
);
bool localProtectedPlaintext(String body) =>
    body.length <= localCryptoMaxPlaintextBytes &&
    localProtectionUnicode(body) &&
    utf8.encode(body).length <= localCryptoMaxPlaintextBytes;
bool localProtectionUnicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length) return false;
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool localProtectedEnvelope(String body) {
  if (body.length > localCryptoMaxWireBytes) return false;
  final parts = body.split(':');
  if (parts.length != 5 || parts[0] != 'ENC' || parts[1] != 'v1') return false;
  try {
    final values = parts.skip(2).map(base64.decode).toList();
    return List.generate(
          3,
          (i) => base64.encode(values[i]) == parts[i + 2],
        ).every((value) => value) &&
        values[0].length == 16 &&
        values[1].length == 12 &&
        values[2].length >= 16 &&
        values[2].length <= localCryptoMaxPlaintextBytes + 16;
  } on FormatException {
    return false;
  }
}

bool localPasswordHashSupported(String hash) =>
    _localPasswordHash.hasMatch(hash);

/// Structural support only, never verifies a password or authenticates a source.
bool localProtectedRecordSupported(String hash, String body) {
  if (hash.isEmpty) {
    return !body.startsWith('ENC:') && localProtectedPlaintext(body);
  }
  if (!localPasswordHashSupported(hash)) return false;
  return body.startsWith('ENC:')
      ? localProtectedEnvelope(body)
      : localProtectedPlaintext(body);
}
