import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'task_creation_attempt.dart';
import 'task_creation_store.dart';

class TaskCreationReview {
  const TaskCreationReview({
    required this.id,
    required this.fingerprint,
    required this.display,
    required this.matchesFrozenInput,
    required this.wire,
  });
  final int id;
  final String fingerprint, display;
  final bool matchesFrozenInput;
  final Map<String, Object?> wire;
}

typedef PrepareTaskCreation =
    Future<PreparedAuthenticatedJsonRequest> Function(TaskCreationAttempt);
typedef InspectTaskCreation =
    Future<TaskCreationReview> Function(TaskCreationAttempt, int);

abstract interface class TaskCreationRecoveryController implements Listenable {
  TaskCreationAttempt? get record;
  TaskCreationReview? get reviewed;
  bool get busy;
  bool get storageUnconfirmed;
  bool get current;
  bool get hasKnownAcknowledgement;
  String? get error;
  Future<void> reload();
  Future<void> submit();
  Future<void> retryAcknowledgement();
  Future<void> review(int id);
  Future<void> adopt(TaskCreationReview selected);
  Future<bool> verifyKnown(TaskCreationReview selected);
  Future<void> end(TaskCreationAttempt captured);
}

/// Retired controllers never change a replacement owner or re-send on recovery.
class TaskCreationController extends ChangeNotifier
    implements TaskCreationRecoveryController {
  TaskCreationController({
    required this.store,
    this.prepare,
    this.localSubmit,
    this.local = false,
    this.beforeEnd,
    required this.inspect,
  }) {
    if (local != store.local ||
        local != (localSubmit != null) ||
        (!local && prepare == null) ||
        (local && prepare != null)) {
      throw const FormatException('Task transport/store domain differs');
    }
    store.acquire(_lease);
  }
  final TaskCreationStore store;
  final PrepareTaskCreation? prepare;
  final Future<int> Function(TaskCreationAttempt, Future<void> Function())?
  localSubmit;
  final bool local;
  final Future<void> Function(TaskCreationAttempt)? beforeEnd;
  TaskCreationOrigin get _submissionOrigin => local
      ? TaskCreationOrigin.localTransactionAcknowledgement
      : TaskCreationOrigin.postAcknowledgement;
  final InspectTaskCreation inspect;
  final Object _lease = Object();
  @override
  TaskCreationAttempt? record;
  @override
  TaskCreationReview? reviewed;
  int? _ack;
  TaskCreationOrigin? _ackOrigin;
  bool endedDurably = false;
  @override
  bool busy = false;
  @override
  bool storageUnconfirmed = false;
  bool _closed = false;
  bool _livePending = false;
  @override
  String? error;
  @override
  bool get hasKnownAcknowledgement => _ack != null;
  @override
  bool get current => !_closed && store.isCurrent();
  void _guard() {
    if (!current) throw StateError('Task creation owner retired');
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void>? _active;
  Future<void> drain() async {
    await _active;
    await store.drain();
  }

  Future<void> _run(Future<void> Function() body) {
    if (busy || !current) return Future<void>.value();
    final work = _runImpl(body);
    _active = work;
    return work;
  }

  Future<void> _runImpl(Future<void> Function() body) async {
    if (busy || !current) return;
    busy = true;
    error = null;
    _notify();
    try {
      await body();
    } catch (_) {
      if (current) error = '操作未完成，请重新核对恢复记录 / Review the recovery record again';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  Future<void> reload() => _run(() async {
    final a = await store.load();
    _guard();
    record = a;
    _livePending = false;
    reviewed = null;
    storageUnconfirmed = false;
  });
  Future<void> begin(TaskCreationAttempt input) => _run(() async {
    storageUnconfirmed = true;
    await store.insert(input, _lease);
    _guard();
    record = input;
    _livePending = true;
    storageUnconfirmed = false;
  });
  @override
  Future<void> submit() => _run(() async {
    final pending = record;
    if (!_livePending ||
        storageUnconfirmed ||
        pending == null ||
        pending.phase != TaskCreationPhase.pending) {
      throw StateError('Fresh pending record required');
    }
    if (local != (localSubmit != null) || (!local && prepare == null)) {
      throw StateError('Typed task creation transport missing');
    }
    Future<void> claim() async {
      _guard();
      _livePending = false;
      storageUnconfirmed = true;
      await store.claim(pending, _lease);
      _guard();
      record = pending.next(TaskCreationPhase.unknown);
      storageUnconfirmed = false;
      _notify();
      _guard();
    }

    final request = local ? null : await prepare!(pending);
    try {
      _guard();
      final int id;
      if (local) {
        id = await localSubmit!(pending, claim);
        _guard();
      } else {
        final reply = await request!.sendAfter(onSubmit: claim);
        _guard();
        final data = reply['data'];
        if (data is! Map ||
            data['task_id'] is! int ||
            (data['task_id'] as int) <= 0) {
          throw const FormatException('Actual task POST ID required');
        }
        id = data['task_id'] as int;
      }
      // Preserve the actual positive ACK even when the follow-up read fails.
      _ack = id;
      _ackOrigin = _submissionOrigin;
      // Validate immutable identity and canonical input against actual receipt;
      // actual adapter performs the same strict checks for fresh reads.
      final actual = await inspect(pending, id);
      _guard();
      reviewed = actual;
      if (!actual.matchesFrozenInput) {
        throw const FormatException(
          'Creation receipt differs; review required',
        );
      }
      _ack = id;
      _ackOrigin = _submissionOrigin;
      storageUnconfirmed = true;
      await store.acknowledge(record!, id, _lease, origin: _submissionOrigin);
      _guard();
      record = record!.next(TaskCreationPhase.knownID, id, _submissionOrigin);
      storageUnconfirmed = false;
    } finally {
      request?.retire();
    }
  });
  @override
  Future<void> retryAcknowledgement() => _run(() async {
    final a = record, id = _ack;
    if (a == null || id == null || _ackOrigin == null) {
      throw StateError('Known receipt required');
    }
    storageUnconfirmed = true;
    await store.acknowledge(a, id, _lease, origin: _ackOrigin!);
    _guard();
    record = a.next(TaskCreationPhase.knownID, id, _ackOrigin!);
    storageUnconfirmed = false;
  });
  @override
  Future<void> review(int id) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase == TaskCreationPhase.pending ||
        (local ? id < 0 : id <= 0)) {
      throw StateError('Unknown record required');
    }
    final result = await inspect(a, id);
    _guard();
    reviewed = result;
  });
  @override
  Future<bool> verifyKnown(TaskCreationReview selected) async {
    var verified = false;
    await _run(() async {
      final a = record;
      if (storageUnconfirmed ||
          a == null ||
          a.phase != TaskCreationPhase.knownID ||
          a.actualId != selected.id ||
          !identical(reviewed, selected) ||
          !selected.matchesFrozenInput)
        return;
      final fresh = await inspect(a, selected.id);
      _guard();
      verified =
          fresh.matchesFrozenInput && fresh.fingerprint == selected.fingerprint;
    });
    return verified;
  }

  @override
  Future<void> adopt(TaskCreationReview selected) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase != TaskCreationPhase.unknown ||
        !identical(reviewed, selected) ||
        !selected.matchesFrozenInput) {
      throw StateError('Read-only review required');
    }
    final fresh = await inspect(a, selected.id);
    _guard();
    if (!fresh.matchesFrozenInput ||
        fresh.fingerprint != selected.fingerprint) {
      throw StateError('Actual resource changed; review again');
    }
    _ack = fresh.id;
    _ackOrigin = local ? _submissionOrigin : TaskCreationOrigin.manualExisting;
    storageUnconfirmed = true;
    await store.acknowledge(
      a,
      fresh.id,
      _lease,
      origin: local ? _submissionOrigin : TaskCreationOrigin.manualExisting,
    );
    _guard();
    record = a.next(
      TaskCreationPhase.knownID,
      fresh.id,
      local ? _submissionOrigin : TaskCreationOrigin.manualExisting,
    );
    storageUnconfirmed = false;
  });
  @override
  Future<void> end(TaskCreationAttempt captured) => _run(() async {
    if (storageUnconfirmed || !identical(record, captured)) {
      throw StateError('Fresh record required');
    }
    if (beforeEnd != null) {
      await beforeEnd!(captured);
      _guard();
    }
    storageUnconfirmed = true;
    await store.end(captured, _lease);
    _guard();
    endedDurably = true;
    record = null;
    reviewed = null;
    _ack = null;
    _ackOrigin = null;
    storageUnconfirmed = false;
  });
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    store.release(_lease);
    super.dispose();
  }
}
