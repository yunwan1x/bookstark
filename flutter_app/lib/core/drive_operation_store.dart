import 'dart:async';
import 'dart:convert';
import 'drive_operation_record.dart';

class DriveOperationRetired implements Exception {
  const DriveOperationRetired();
}

class DriveOperationStorageUnconfirmed implements Exception {
  const DriveOperationStorageUnconfirmed();
}

/// A fixed single slot per scope; no key enumeration or dynamic account lookup.
class DriveOperationStore {
  DriveOperationStore({
    required this.scope,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    required this.flush,
    required this.isCurrent,
  });
  final DriveOperationScope scope;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  static final _tails = <String, Future<void>>{};
  static final _leases = <String, Object>{};
  static final _retiredOperations = <String>{};
  String get metadataKey =>
      'bookstark.drive-operation.v1.${base64Url.encode(utf8.encode(scope.identity))}';
  String _operationKey(DriveOperationRecord record) =>
      '$metadataKey/${record.key}';
  void guard() {
    if (!isCurrent()) throw const DriveOperationRetired();
  }

  void acquire(Object token) {
    guard();
    if (_leases.containsKey(metadataKey)) {
      throw const DriveOperationStorageUnconfirmed();
    }
    _leases[metadataKey] = token;
  }

  void release(Object token) {
    if (identical(_leases[metadataKey], token)) _leases.remove(metadataKey);
  }

  void _lease(Object token) {
    guard();
    if (!identical(_leases[metadataKey], token)) {
      throw const DriveOperationStorageUnconfirmed();
    }
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    final previous = _tails[metadataKey];
    Future<T> run() async {
      guard();
      return action();
    }

    final result = previous == null
        ? Future<T>.sync(run)
        : previous.then((_) => run());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[metadataKey] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[metadataKey], tail)) _tails.remove(metadataKey);
      }),
    );
    return result;
  }

  void _identity(DriveOperationRecord r) {
    if (r.scope.identity != scope.identity) {
      throw const FormatException('Scope mismatch');
    }
  }

  Future<void> _persist(DriveOperationRecord record) async {
    _identity(record);
    await writeValue(metadataKey, record.encode());
    guard();
    await flush();
    guard();
    if (await readValue(metadataKey) != record.encode()) {
      throw const DriveOperationStorageUnconfirmed();
    }
    guard();
  }

  Future<DriveOperationRecord?> read() => _ordered(() async {
    // A missing slot only unlocks after a real durability barrier, including
    // a prior deletion whose callback failed after applying the delete.
    await flush();
    guard();
    final raw = await readValue(metadataKey);
    guard();
    if (raw == null) return null;
    final r = DriveOperationRecord.decode(raw);
    _identity(r);
    return r;
  });
  Future<void> insert(DriveOperationRecord record) => _ordered(() async {
    _identity(record);
    if (record.state != DriveOperationState.pending ||
        _retiredOperations.contains(_operationKey(record))) {
      throw const DriveOperationStorageUnconfirmed();
    }
    if (await readValue(metadataKey) != null) {
      throw const DriveOperationStorageUnconfirmed();
    }
    guard();
    await _persist(record);
  });

  /// Strict CAS, never idempotent authorization. Only this successful call may grant send.
  Future<void> claim(DriveOperationRecord pending, Object token) =>
      _ordered(() async {
        _lease(token);
        _identity(pending);
        if (pending.state != DriveOperationState.pending ||
            _retiredOperations.contains(_operationKey(pending)) ||
            await readValue(metadataKey) != pending.encode()) {
          throw const DriveOperationStorageUnconfirmed();
        }
        _lease(token);
        await _persist(pending.withState(DriveOperationState.unknown));
        _lease(token);
      });

  /// Idempotency is allowed ONLY for recording an already received server acknowledgment.
  Future<void> acknowledge(DriveOperationRecord unknown) => _ordered(() async {
    _identity(unknown);
    if (unknown.state != DriveOperationState.unknown ||
        _retiredOperations.contains(_operationKey(unknown))) {
      throw const DriveOperationStorageUnconfirmed();
    }
    final raw = await readValue(metadataKey);
    guard();
    final ack = unknown.withState(DriveOperationState.acknowledged);
    if (raw != unknown.encode() && raw != ack.encode()) {
      throw const DriveOperationStorageUnconfirmed();
    }
    await _persist(ack);
  });

  /// Ending tracking is not a rollback, nor proof that mutation did not execute.
  Future<void> end(DriveOperationRecord expected) => _ordered(() async {
    _identity(expected);
    final raw = await readValue(metadataKey);
    guard();
    if (raw != expected.encode() &&
        !(raw == null &&
            _retiredOperations.contains(_operationKey(expected)))) {
      throw const DriveOperationStorageUnconfirmed();
    }
    _retiredOperations.add(_operationKey(expected));
    if (raw != null) {
      await deleteValue(metadataKey);
      guard();
    }
    await flush();
    guard();
    if (await readValue(metadataKey) != null) {
      throw const DriveOperationStorageUnconfirmed();
    }
    guard();
  });
}
