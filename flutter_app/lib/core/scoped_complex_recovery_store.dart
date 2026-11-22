import 'dart:typed_data';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';

/// Fixed resource scope is encoded in the vault key. This wrapper retires
/// operations rather than looking up a potentially different current account.
class ScopedComplexRecoveryStore implements ComplexRecoveryBytesStore {
  ScopedComplexRecoveryStore(this.delegate, {required this.isCurrent});
  final ComplexRecoveryBytesStore delegate;
  final bool Function() isCurrent;
  bool _retired = false;
  void retire() {
    _retired = true;
  }

  void _check() {
    if (_retired || !isCurrent()) {
      throw StateError('Book document recovery owner retired');
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    _check();
    final value = await delegate.read(key);
    _check();
    return value;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _check();
    await delegate.write(key, bytes);
    _check();
  }

  @override
  Future<void> remove(String key) async {
    _check();
    await delegate.remove(key);
    _check();
  }
}
