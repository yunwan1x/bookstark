import 'package:flutter/foundation.dart';
import 'label_creation_attempt.dart';
import 'local_label_creation_store.dart';
import 'label_management_repository.dart';
import 'label_creation_controller.dart';

/// Retired controllers never change a replacement owner or re-send on recovery.
class LocalLabelCreationController extends ChangeNotifier
    implements LabelCreationRecoveryController {
  LocalLabelCreationController({
    required this.store,
    required this.create,
    required this.inspect,
  }) {
    store.acquire(_lease);
  }
  final LocalLabelCreationStore store;
  final Future<ManagedLabel> Function(String name) create;
  final InspectLabelCreation inspect;
  final Object _lease = Object();
  @override
  LabelCreationAttempt? record;
  @override
  LabelCreationReview? reviewed;
  int? _ack;
  LabelCreationOrigin? _ackOrigin;
  bool endedDurably = false;
  @override
  bool busy = false;
  @override
  bool storageUnconfirmed = false;
  bool _closed = false;
  @override
  String? error;
  @override
  bool get hasKnownAcknowledgement => _ack != null;
  @override
  bool get current => !_closed && store.isCurrent();
  void _guard() {
    if (!current) throw StateError('Local label creation owner retired');
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() body) async {
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
    reviewed = null;
    storageUnconfirmed = false;
  });
  Future<void> begin(LabelCreationAttempt input) => _run(() async {
    storageUnconfirmed = true;
    await store.insert(input, _lease);
    _guard();
    record = input;
    storageUnconfirmed = false;
  });
  @override
  Future<void> submit() => _run(() async {
    final pending = record;
    if (storageUnconfirmed ||
        pending == null ||
        pending.phase != LabelCreationPhase.pending) {
      throw StateError('Fresh pending record required');
    }
    // Conservative durable authorization is before the real SQL transaction.
    // A crash here may mean SQL never started; unknown never auto-replays it.
    storageUnconfirmed = true;
    await store.claim(pending, _lease);
    _guard();
    record = pending.next(LabelCreationPhase.unknown);
    storageUnconfirmed = false;
    _notify();
    final actual = await create(pending.body['label_name'] as String);
    _guard();
    if (actual.id <= 0 || actual.name != pending.body['label_name']) {
      throw const FormatException('Local transaction acknowledgement differs');
    }
    _ack = actual.id;
    _ackOrigin = LabelCreationOrigin.localTransactionAcknowledgement;
    storageUnconfirmed = true;
    await store.acknowledge(record!, actual.id, _lease, origin: _ackOrigin!);
    _guard();
    record = record!.next(LabelCreationPhase.knownID, actual.id, _ackOrigin!);
    storageUnconfirmed = false;
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
    record = a.next(LabelCreationPhase.knownID, id, _ackOrigin!);
    storageUnconfirmed = false;
  });
  @override
  Future<void> review(int id) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase == LabelCreationPhase.pending ||
        id <= 0) {
      throw StateError('Unknown record required');
    }
    final result = await inspect(a, id);
    _guard();
    reviewed = result;
  });
  @override
  Future<bool> verifyKnown(LabelCreationReview selected) async {
    if (busy || !current || storageUnconfirmed) return false;
    final a = record;
    if (a == null ||
        a.phase != LabelCreationPhase.knownID ||
        a.actualId != selected.id ||
        !identical(reviewed, selected) ||
        !selected.matchesFrozenInput) {
      return false;
    }
    final fresh = await inspect(a, selected.id);
    _guard();
    return fresh.matchesFrozenInput &&
        fresh.fingerprint == selected.fingerprint;
  }

  @override
  Future<void> adopt(LabelCreationReview selected) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase != LabelCreationPhase.unknown ||
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
    _ackOrigin = LabelCreationOrigin.manualExisting;
    storageUnconfirmed = true;
    await store.acknowledge(
      a,
      fresh.id,
      _lease,
      origin: LabelCreationOrigin.manualExisting,
    );
    _guard();
    record = a.next(
      LabelCreationPhase.knownID,
      fresh.id,
      LabelCreationOrigin.manualExisting,
    );
    storageUnconfirmed = false;
  });
  @override
  Future<void> end(LabelCreationAttempt captured) => _run(() async {
    if (storageUnconfirmed || !identical(record, captured)) {
      throw StateError('Fresh record required');
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
    _closed = true;
    store.release(_lease);
    super.dispose();
  }
}
