import 'dart:typed_data';
import 'complex_recovery_store.dart';
import 'protected_owned_complex_journal.dart';

/// Full protected snapshots exist only in this route's process memory.
/// Native storage receives the separate opaque no-body journal only.
class ProtectedComplexMemoryStore implements ComplexRecoveryBytesStore {
  ProtectedComplexMemoryStore(this.journal);
  final ProtectedOwnedComplexJournal journal;
  final _values = <String, Uint8List>{};
  bool _closed = false;
  void _guard() {
    if (_closed) throw StateError('Protected memory owner retired');
  }

  @override
  Future<Uint8List?> read(String key) async {
    _guard();
    final value = _values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _guard();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
        bytes.length > 20 * 1024 * 1024 + 128 * 1024 + 4) {
      throw const FormatException('Protected memory snapshot bound');
    }
    final old = _values.remove(key);
    if (old != null) old.fillRange(0, old.length, 0);
    _values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    _guard();
    if (journal.hasKnownReceipt) {
      await journal.finishKnown();
    } else if (journal.hasWarmAttempt) {
      throw StateError('Protected save needs explicit review');
    }
    _guard();
    final old = _values.remove(key);
    if (old != null) old.fillRange(0, old.length, 0);
  }

  void close() {
    _closed = true;
    for (final value in _values.values) {
      value.fillRange(0, value.length, 0);
    }
    _values.clear();
  }
}
