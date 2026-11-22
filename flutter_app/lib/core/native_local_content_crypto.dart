import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'attachments.dart';
import 'local_content_crypto_limits.dart';
import 'local_content_protection_format.dart';

enum LocalContentCryptoReason {
  unsupported,
  wrongPassword,
  invalidContent,
  cancelled,
  unavailable,
  busy,
}

final class LocalContentCryptoFailure implements Exception {
  const LocalContentCryptoFailure(this.reason);
  final LocalContentCryptoReason reason;
  @override
  String toString() => 'Local content crypto: ${reason.name}';
}

final class LocalProtectedBody {
  const LocalProtectedBody({required this.passwordHash, required this.body});
  final String passwordHash;
  final String body;
}

/// Ephemeral computation only; no password/plaintext cache or serialization.
final class NativeLocalContentCrypto {
  NativeLocalContentCrypto({
    MethodChannel? channel,
    this.deadline = const Duration(minutes: 2),
  }) : _channel =
           channel ?? const MethodChannel('bookstark/local_content_crypto') {
    if (deadline <= Duration.zero) {
      throw ArgumentError('Positive crypto deadline required');
    }
  }
  final MethodChannel _channel;
  final Duration deadline;

  /// Native cancellation resolves a request before slow bcrypt necessarily
  /// exits. Only this separate process-wide worker barrier proves completion.
  Future<void> drain() async {
    try {
      final value = await _channel
          .invokeMethod<Object?>('drain')
          .timeout(deadline);
      if (value is! Map ||
          value.length != 2 ||
          value['format'] != 1 ||
          value['drained'] != true) {
        throw const LocalContentCryptoFailure(
          LocalContentCryptoReason.unavailable,
        );
      }
    } catch (_) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unavailable,
      );
    }
  }

  Future<String> unlock({
    required String password,
    required String passwordHash,
    required String body,
    AttachmentCancellation? cancellation,
  }) async {
    final value = await _invoke(
      'unlock',
      password,
      body,
      hash: passwordHash,
      cancellation: cancellation,
    );
    final plain = _decodeWire(value['body'] as Uint8List);
    if (!localProtectedPlaintext(plain)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return plain;
  }

  Future<String> encryptExisting({
    required String password,
    required String passwordHash,
    required String plaintext,
    AttachmentCancellation? cancellation,
  }) async {
    final value = await _invoke(
      'encryptExisting',
      password,
      plaintext,
      hash: passwordHash,
      cancellation: cancellation,
    );
    final encrypted = _decodeWire(value['body'] as Uint8List);
    if (!localProtectedEnvelope(encrypted)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return encrypted;
  }

  /// Ordinary local schema has no hash column; authenticate only exact ENC:v1.
  Future<String> unlockEnvelope({
    required String password,
    required String body,
    AttachmentCancellation? cancellation,
  }) async {
    if (!localProtectedEnvelope(body)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unsupported,
      );
    }
    final value = await _invoke(
      'unlockEnvelope',
      password,
      body,
      cancellation: cancellation,
    );
    final plain = _decodeWire(value['body'] as Uint8List);
    if (!localProtectedPlaintext(plain)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return plain;
  }

  Future<String> encryptEnvelope({
    required String password,
    required String plaintext,
    AttachmentCancellation? cancellation,
  }) async {
    final value = await _invoke(
      'encryptEnvelope',
      password,
      plaintext,
      cancellation: cancellation,
    );
    final body = _decodeWire(value['body'] as Uint8List);
    if (!localProtectedEnvelope(body)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return body;
  }

  Future<LocalProtectedBody> protectNew({
    required String password,
    required String plaintext,
    AttachmentCancellation? cancellation,
  }) async {
    final value = await _invoke(
      'protectNew',
      password,
      plaintext,
      cancellation: cancellation,
    );
    final encrypted = _decodeWire(value['body'] as Uint8List);
    final hash = value['hash'];
    if (hash is! String ||
        !localPasswordHashSupported(hash) ||
        !hash.startsWith(r'$2a$10$') ||
        !localProtectedEnvelope(encrypted)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return LocalProtectedBody(passwordHash: hash, body: encrypted);
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    String password,
    String body, {
    String? hash,
    AttachmentCancellation? cancellation,
  }) async {
    void check() {
      if (cancellation?.cancelled == true) {
        throw const LocalContentCryptoFailure(
          LocalContentCryptoReason.cancelled,
        );
      }
    }

    check();
    if (password.isEmpty ||
        !localProtectionUnicode(password) ||
        utf8.encode(password).length > 4096 ||
        (method == 'protectNew' && utf8.encode(password).length > 72) ||
        (hash != null && !localPasswordHashSupported(hash)) ||
        ((method == 'unlock' || method == 'unlockEnvelope')
            ? body.length > localCryptoMaxWireBytes ||
                  !localProtectionUnicode(body) ||
                  utf8.encode(body).length > localCryptoMaxWireBytes
            : !localProtectedPlaintext(body))) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unsupported,
      );
    }
    final id = attachmentId();
    final finished = Completer<void>();
    // Finish this branch on ordinary exit too: a long-lived cancellation
    // signal must not retain a completed plaintext result.
    final abort = cancellation == null
        ? null
        : Future.any<bool>([
            cancellation.signal.then((_) => true),
            finished.future.then((_) => false),
          ]).then<Object?>((cancelled) async {
            if (cancelled) {
              unawaited(_cancel(id));
              throw const LocalContentCryptoFailure(
                LocalContentCryptoReason.cancelled,
              );
            }
            return null;
          });
    try {
      final pending = _channel.invokeMethod<Object?>(method, {
        'id': id,
        'password': password,
        'body': Uint8List.fromList(utf8.encode(body)),
        'hash': ?hash,
      });
      final value = await Future.any<Object?>([
        pending,
        ?abort,
      ]).timeout(deadline);
      check();
      final keys = {'format', 'id', 'body', if (method == 'protectNew') 'hash'};
      if (value is! Map ||
          value.length != keys.length ||
          !value.keys.toSet().containsAll(keys) ||
          value['format'] is! int ||
          value['format'] != 1 ||
          value['id'] != id ||
          value['body'] is! Uint8List) {
        throw const LocalContentCryptoFailure(
          LocalContentCryptoReason.invalidContent,
        );
      }
      return value.cast<Object?, Object?>();
    } on TimeoutException {
      unawaited(_cancel(id));
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unavailable,
      );
    } on PlatformException catch (error) {
      throw LocalContentCryptoFailure(switch (error.code) {
        'UNSUPPORTED' => LocalContentCryptoReason.unsupported,
        'WRONG_PASSWORD' => LocalContentCryptoReason.wrongPassword,
        'INVALID_CONTENT' => LocalContentCryptoReason.invalidContent,
        'CANCELLED' => LocalContentCryptoReason.cancelled,
        'BUSY' => LocalContentCryptoReason.busy,
        _ => LocalContentCryptoReason.unavailable,
      });
    } on MissingPluginException {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unavailable,
      );
    } finally {
      finished.complete();
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await _channel
          .invokeMethod<Object?>('cancel', {'id': id})
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // No persistence, retry or implicit unlock.
    }
  }
}

String _decodeWire(Uint8List bytes) {
  if (bytes.length > localCryptoMaxWireBytes) {
    throw const LocalContentCryptoFailure(
      LocalContentCryptoReason.invalidContent,
    );
  }
  try {
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    final text = utf8.decode(bytes, allowMalformed: false);
    return bom ? '\uFEFF$text' : text;
  } on FormatException {
    throw const LocalContentCryptoFailure(
      LocalContentCryptoReason.invalidContent,
    );
  }
}
