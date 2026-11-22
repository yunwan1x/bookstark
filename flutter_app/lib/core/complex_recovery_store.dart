import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

abstract interface class ComplexRecoveryBytesStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
}

typedef ComplexRecoveryInvoke =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

/// The native implementation encrypts/authenticates bounded chunks in its own
/// no-backup directory. No plaintext file or giant preferences string is used.
class NativeComplexRecoveryStore implements ComplexRecoveryBytesStore {
  NativeComplexRecoveryStore({ComplexRecoveryInvoke? invoke})
    : _invoke =
          invoke ??
          ((method, arguments) =>
              channel.invokeMethod<Object?>(method, arguments));
  static const channel = MethodChannel('bookstark/complex_recovery');
  static const chunkBytes = 262144;
  static const maxBytes = 20 * 1024 * 1024 + 128 * 1024 + 4;
  final ComplexRecoveryInvoke _invoke;
  Future<void>? _tail;
  Future<T> _ordered<T>(Future<T> Function() action) {
    final previous = _tail;
    final next = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Object?> _call(String method, Map<String, Object?> arguments) =>
      _invoke(method, arguments).timeout(const Duration(seconds: 60));
  void _key(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const FormatException('Invalid recovery identity');
    }
  }

  String _id(Object? value) {
    if (value is! String || value.isEmpty || value.length > 128) {
      throw const FormatException('Invalid recovery transfer identity');
    }
    return value;
  }

  Map<Object?, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid recovery protocol');
    return value.cast<Object?, Object?>();
  }

  @override
  Future<void> write(String key, Uint8List input) {
    _key(key);
    if (input.isEmpty || input.length > maxBytes) {
      throw const FormatException('Recovery record exceeds byte limit');
    }
    final bytes = Uint8List.fromList(input);
    return _ordered(() async {
      final digest = sha256.convert(bytes).toString();
      final begun = _map(
        await _call('beginWrite', {
          'key': key,
          'bytes': bytes.length,
          'sha256': digest,
        }),
      );
      final id = _id(begun['id']);
      try {
        if (begun['bytes'] != bytes.length ||
            begun['chunkBytes'] != chunkBytes) {
          throw const FormatException('Invalid recovery write receipt');
        }
        for (var offset = 0, index = 0; offset < bytes.length; index++) {
          final end = (offset + chunkBytes).clamp(0, bytes.length);
          final receipt = _map(
            await _call('writeChunk', {
              'id': id,
              'index': index,
              'data': Uint8List.sublistView(bytes, offset, end),
            }),
          );
          if (receipt['id'] != id ||
              receipt['index'] != index ||
              receipt['received'] != end) {
            throw const FormatException('Invalid recovery chunk receipt');
          }
          offset = end;
        }
        final committed = _map(await _call('commitWrite', {'id': id}));
        if (committed['id'] != id ||
            committed['bytes'] != bytes.length ||
            committed['sha256'] != digest ||
            committed['committed'] != true) {
          throw const FormatException('Recovery commit was not confirmed');
        }
      } catch (_) {
        try {
          await _call('abortWrite', {'id': id});
        } catch (_) {
          /* Preserve original error. */
        }
        rethrow;
      }
    });
  }

  @override
  Future<Uint8List?> read(String key) {
    _key(key);
    return _ordered(() async {
      final result = await _call('beginRead', {'key': key});
      if (result == null) return null;
      final info = _map(result), id = _id(_map(result)['id']);
      try {
        final length = info['bytes'],
            count = info['chunks'],
            digest = info['sha256'];
        if (length is! int ||
            length < 1 ||
            length > maxBytes ||
            count is! int ||
            count != (length + chunkBytes - 1) ~/ chunkBytes ||
            digest is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          throw const FormatException('Invalid recovery read metadata');
        }
        final builder = BytesBuilder(copy: false);
        for (var index = 0; index < count; index++) {
          final chunk = _map(
            await _call('readChunk', {'id': id, 'index': index}),
          );
          final bytes = chunk['data'];
          final expected = index == count - 1
              ? length - index * chunkBytes
              : chunkBytes;
          if (chunk['id'] != id ||
              chunk['index'] != index ||
              bytes is! Uint8List ||
              bytes.length != expected) {
            throw const FormatException('Invalid recovery read chunk');
          }
          builder.add(bytes);
        }
        final bytes = builder.takeBytes();
        if (bytes.length != length ||
            sha256.convert(bytes).toString() != digest) {
          throw const FormatException('Recovery integrity mismatch');
        }
        return bytes;
      } finally {
        // A release failure must remain visible: a later write cannot safely
        // replace a record whose previous native reader is still active.
        await _call('endRead', {'id': id});
      }
    });
  }

  @override
  Future<void> remove(String key) {
    _key(key);
    return _ordered(() async {
      if (await _call('remove', {'key': key}) != true) {
        throw StateError('Recovery removal was not synchronized');
      }
    });
  }
}
