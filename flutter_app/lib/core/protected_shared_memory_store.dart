import 'dart:typed_data';
import 'complex_recovery_store.dart';
import 'protected_shared_journal.dart';

class ProtectedSharedMemoryStore implements ComplexRecoveryBytesStore {
  ProtectedSharedMemoryStore(this.journal);
  final ProtectedSharedJournal journal;
  final _values = <String, Uint8List>{};
  bool _closed = false;
  void _guard() {
    if (_closed) throw StateError('Protected shared memory retired');
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
      throw const FormatException('Protected shared memory bound');
    }
    final previous = _values.remove(key);
    if (previous != null) previous.fillRange(0, previous.length, 0);
    _values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    _guard();
    if (journal.hasKnown) {
      await journal.finishKnown();
    } else if (journal.hasAttempt) {
      throw StateError('Protected shared save needs explicit review');
    }
    _guard();
    final previous = _values.remove(key);
    if (previous != null) previous.fillRange(0, previous.length, 0);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final bytes in _values.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _values.clear();
  }
}
