import 'dart:async';
import 'task_creation_attempt.dart';

class TaskCreationStorageUnconfirmed implements Exception {
  const TaskCreationStorageUnconfirmed();
}

class TaskCreationStore {
  TaskCreationStore({
    required this.scope,
    required this.key,
    required this.read,
    required this.write,
    required this.remove,
    required this.flush,
    required this.isCurrent,
    this.local = false,
  });
  static const prefix = 'bookstark.task-create.v1.';
  static const localPrefix = 'bookstark.local-task-create.v1.';
  final bool local;
  static final _tails = <String, Future<void>>{};
  static final _leases = <String, Object>{};
  static final _ended = <String>{};
  final String scope, key;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  String get metadataKey => '${local ? localPrefix : prefix}$scope.$key';
  void guard() {
    if (!isCurrent()) throw StateError('Task creation owner retired');
  }

  void acquire(Object lease) {
    guard();
    if (_leases.containsKey(metadataKey)) {
      throw const TaskCreationStorageUnconfirmed();
    }
    _leases[metadataKey] = lease;
  }

  void release(Object lease) {
    if (identical(_leases[metadataKey], lease)) _leases.remove(metadataKey);
  }

  void _owned(Object lease) {
    guard();
    if (!identical(_leases[metadataKey], lease)) {
      throw const TaskCreationStorageUnconfirmed();
    }
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    final prior = _tails[metadataKey];
    final next = prior == null
        ? Future<T>.sync(action)
        : prior.then((_) => action());
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[metadataKey] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[metadataKey], tail)) _tails.remove(metadataKey);
      }),
    );
    return next;
  }

  void _identity(TaskCreationAttempt a) {
    if (a.scope != scope ||
        a.key != key ||
        (a.origin != null &&
            (local
                ? a.origin != TaskCreationOrigin.localTransactionAcknowledgement
                : a.origin ==
                      TaskCreationOrigin.localTransactionAcknowledgement))) {
      throw const FormatException('Creation scope mismatch');
    }
  }

  Future<void> drain() => _ordered(() async {});

  Future<TaskCreationAttempt?> load() => _ordered(() async {
    guard();
    final raw = await read(metadataKey);
    guard();
    if (raw == null) return null;
    final a = TaskCreationAttempt.decode(raw);
    _identity(a);
    return a;
  });
  Future<void> _persist(TaskCreationAttempt a, Object lease) async {
    final raw = a.encode();
    await write(metadataKey, raw);
    _owned(lease);
    await flush();
    _owned(lease);
    if (await read(metadataKey) != raw) {
      throw const TaskCreationStorageUnconfirmed();
    }
    _owned(lease);
  }

  Future<void> insert(TaskCreationAttempt a, Object lease) =>
      _ordered(() async {
        _owned(lease);
        _identity(a);
        if (a.phase != TaskCreationPhase.pending ||
            _ended.contains(metadataKey) ||
            await read(metadataKey) != null) {
          throw const TaskCreationStorageUnconfirmed();
        }
        _owned(lease);
        await _persist(a, lease);
      });

  /// Strict single transition; idempotence must never grant another POST.
  Future<void> claim(TaskCreationAttempt a, Object lease) => _ordered(() async {
    _owned(lease);
    _identity(a);
    if (a.phase != TaskCreationPhase.pending ||
        await read(metadataKey) != a.encode()) {
      throw const TaskCreationStorageUnconfirmed();
    }
    _owned(lease);
    await _persist(a.next(TaskCreationPhase.unknown), lease);
  });

  /// Known ACK retries storage only.
  Future<void> acknowledge(
    TaskCreationAttempt expected,
    int id,
    Object lease, {
    required TaskCreationOrigin origin,
  }) => _ordered(() async {
    _owned(lease);
    _identity(expected);
    if (id <= 0 ||
        expected.phase == TaskCreationPhase.pending ||
        (expected.actualId != null && expected.actualId != id)) {
      throw StateError('Submitted attempt required');
    }
    final raw = await read(metadataKey);
    _owned(lease);
    final known = expected.next(TaskCreationPhase.knownID, id, origin);
    if (raw != expected.encode() && raw != known.encode()) {
      throw const TaskCreationStorageUnconfirmed();
    }
    await _persist(known, lease);
  });
  Future<void> end(TaskCreationAttempt expected, Object lease) =>
      _ordered(() async {
        _owned(lease);
        _identity(expected);
        if (await read(metadataKey) != expected.encode()) {
          throw const TaskCreationStorageUnconfirmed();
        }
        _owned(lease);
        _ended.add(metadataKey);
        await remove(metadataKey);
        _owned(lease);
        await flush();
        _owned(lease);
        if (await read(metadataKey) != null) {
          throw const TaskCreationStorageUnconfirmed();
        }
        _owned(lease);
      });
}
