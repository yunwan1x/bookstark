import 'dart:convert';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/local_content_protection_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_content_crypto_limits.dart';

String hash(int cost, [String version = '2a']) =>
    r'$' + version + r'$' + cost.toString().padLeft(2, '0') + r'$' + 'A' * 53;
String envelope({int salt = 16, int nonce = 12, int cipher = 16}) =>
    'ENC:v1:${base64.encode(Uint8List(salt))}:'
    '${base64.encode(Uint8List(nonce))}:${base64.encode(Uint8List(cipher))}';

void main() {
  test(
    'bcrypt bounds exactly match the Android worker, including all Go variants',
    () {
      for (final version in ['2a', '2b', '2y']) {
        for (final cost in [4, 10, 14]) {
          expect(localPasswordHashSupported(hash(cost, version)), isTrue);
        }
        for (final cost in [3, 15, 31]) {
          expect(localPasswordHashSupported(hash(cost, version)), isFalse);
        }
      }
      expect(localPasswordHashSupported(hash(10, '2x')), isFalse);
      expect(localPasswordHashSupported(' ${hash(10)}'), isFalse);
    },
  );
  test('an encrypted source without its original hash cannot be admitted', () {
    expect(localProtectedEnvelope(envelope()), isTrue);
    expect(localProtectedRecordSupported('', envelope()), isFalse);
    expect(localProtectedRecordSupported(hash(10), envelope()), isTrue);
  });
  test(
    'legacy password-only plaintext and ordinary plaintext keep original shape',
    () {
      const body = '\uFEFF# exact\r\n';
      expect(localProtectedRecordSupported(hash(10), body), isTrue);
      expect(localProtectedRecordSupported('', body), isTrue);
      expect(body, '\uFEFF# exact\r\n');
      expect(localProtectedRecordSupported('unrecognized-hash', body), isFalse);
    },
  );
  test(
    'unsupported cost blocks encrypted and plaintext protected records equally',
    () {
      expect(localProtectedRecordSupported(hash(15), envelope()), isFalse);
      expect(localProtectedRecordSupported(hash(15), 'legacy plain'), isFalse);
    },
  );
  test('envelopes require exact dimensions, version and canonical base64', () {
    for (final body in [
      envelope(salt: 15),
      envelope(nonce: 11),
      envelope(cipher: 15),
      envelope().replaceFirst('v1', 'v2'),
      envelope().replaceFirst('==', ''),
      'ENC:v1:provider-source-secret',
    ]) {
      expect(localProtectedEnvelope(body), isFalse);
    }
    expect(localProtectedRecordSupported(hash(10), 'ENC:v9:opaque'), isFalse);
  });
  test(
    'plain Unicode byte limit is measured with preserved BOM and surrogate checks',
    () {
      expect(
        localProtectedPlaintext('a' * (localCryptoMaxPlaintextBytes)),
        isTrue,
      );
      expect(
        localProtectedPlaintext('a' * (localCryptoMaxPlaintextBytes + 1)),
        isFalse,
      );
      expect(
        localProtectedPlaintext('中' * (localCryptoMaxPlaintextBytes ~/ 3 + 1)),
        isFalse,
      );
      expect(localProtectionUnicode(String.fromCharCode(0xd800)), isFalse);
      expect(
        localProtectedRecordSupported('', String.fromCharCode(0xdc00)),
        isFalse,
      );
    },
  );
  test(
    'cipher byte limit retains the GCM tag allowance and rejects excess',
    () {
      expect(
        localProtectedEnvelope(
          envelope(cipher: localCryptoMaxPlaintextBytes + 16),
        ),
        isTrue,
      );
      expect(
        localProtectedEnvelope(
          envelope(cipher: localCryptoMaxPlaintextBytes + 17),
        ),
        isFalse,
      );
      expect(
        localProtectedEnvelope("ENC:${'A' * (localCryptoMaxWireBytes)}"),
        isFalse,
      );
    },
  );
  test(
    'a valid tag-sized envelope is structural support, never password verification',
    () {
      final body = envelope();
      expect(localProtectedRecordSupported(hash(10), body), isTrue);
      // No password or crypto provider is used: zeros are not asserted decryptable.
      expect(localProtectedRecordSupported('', 'ordinary'), isTrue);
    },
  );
}
