import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Callers must await acquisition before exposing any secret input or value.
/// A fresh lease is required after release; route disposal is irreversible.
abstract interface class AdminAssetWindowGuard {
  Future<void> acquire();
  Future<void> close();
}

final class AdminAssetSecureWindow implements AdminAssetWindowGuard {
  AdminAssetSecureWindow({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('bookstark/asset_secure_window');
  final MethodChannel _channel;
  String? _lease;
  Future<void>? _acquisition;
  bool _closed = false;

  @override
  Future<void> acquire() {
    if (_closed) return Future.error(StateError('Secure window was closed'));
    return _acquisition ??= _acquire();
  }

  Future<void> _acquire() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Secure asset input requires Android');
    }
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // Set before invoking: disposal must release even a pending acquisition.
    _lease = id;
    final result = await _channel.invokeMethod<bool>('acquire', {'lease': id});
    if (result != true) {
      await close();
      throw StateError('Secure window could not be enabled');
    }
    if (_closed) throw StateError('Secure window was closed');
  }

  @override
  Future<void> close() async {
    _closed = true;
    final id = _lease;
    _lease = null;
    if (id != null) {
      await _channel.invokeMethod<bool>('release', {'lease': id});
    }
  }
}
