import 'dart:async';
import 'dart:math';

/// Stable slot discovers a random attempt after cold restart. Slot allocation
/// never authorizes POST. Only newly allocated slots may initialize pending.
/// An existing slot with a missing record needs explicit end; never reinitialize.
/// One account slot covers every task content, including modified draft names.
class TaskCreationSlotHandle {
  const TaskCreationSlotHandle(this.key, this.created);
  final String key;
  final bool created;
}

class TaskCreationSlot {
  TaskCreationSlot({
    required this.scope,
    required this.read,
    required this.write,
    required this.remove,
    required this.flush,
    required this.isCurrent,
    this.local = false,
  });
  static const prefix = 'bookstark.task-create-slot.v1.';
  static const localPrefix = 'bookstark.local-task-create-slot.v1.';
  final bool local;
  static final _tails = <String, Future<void>>{};
  final String scope;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  String get metadataKey => (local ? localPrefix : prefix) + scope;
  void _guard() {
    if (!isCurrent()) throw StateError('Creation slot retired');
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

  Future<bool> hasRetained() => _ordered(() async {
    _guard();
    final key = await read(metadataKey);
    _guard();
    if (key == null) return false;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
      throw const FormatException('Invalid retained task creation slot');
    }
    return true;
  });

  Future<void> drain() => _ordered(() async {});

  Future<TaskCreationSlotHandle> open() => _ordered(() async {
    _guard();
    var key = await read(metadataKey);
    _guard();
    final created = key == null;
    if (key == null) {
      final rng = Random.secure();
      key = List.generate(
        16,
        (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await write(metadataKey, key);
      _guard();
      await flush();
      _guard();
      if (await read(metadataKey) != key) {
        throw StateError('Creation slot durability unconfirmed');
      }
      _guard();
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
      throw const FormatException('Invalid retained creation slot');
    }
    return TaskCreationSlotHandle(key, created);
  });

  /// Only after record.end exact deletion+flush. Late prior-key ACK cannot revive.
  Future<void> clear(String expected) => _ordered(() async {
    _guard();
    if (await read(metadataKey) != expected) {
      throw StateError('Creation slot changed');
    }
    _guard();
    await remove(metadataKey);
    _guard();
    await flush();
    _guard();
    if (await read(metadataKey) != null) {
      throw StateError('Creation slot deletion unconfirmed');
    }
    _guard();
  });
}
