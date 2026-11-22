import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'label_creation_attempt.dart';
import 'label_creation_store.dart';

class LabelCreationReview {
  const LabelCreationReview({
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

typedef PrepareLabelCreation =
    Future<PreparedAuthenticatedJsonRequest> Function(LabelCreationAttempt);
typedef InspectLabelCreation =
    Future<LabelCreationReview> Function(LabelCreationAttempt, int);

abstract interface class LabelCreationRecoveryController implements Listenable {
  LabelCreationAttempt? get record;
  LabelCreationReview? get reviewed;
  bool get busy;
  bool get storageUnconfirmed;
  bool get current;
  bool get hasKnownAcknowledgement;
  String? get error;
  Future<void> reload();
  Future<void> submit();
  Future<void> retryAcknowledgement();
  Future<void> review(int id);
  Future<void> adopt(LabelCreationReview selected);
  Future<bool> verifyKnown(LabelCreationReview selected);
  Future<void> end(LabelCreationAttempt captured);
}

/// Retired controllers never change a replacement owner or re-send on recovery.
class LabelCreationController extends ChangeNotifier
    implements LabelCreationRecoveryController {
  LabelCreationController({
    required this.store,
    required this.prepare,
    required this.inspect,
  }) {
    store.acquire(_lease);
  }
  final LabelCreationStore store;
  final PrepareLabelCreation prepare;
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
    if (!current) throw StateError('Label creation owner retired');
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
    // Preparation completes actual auth/CSRF before the durable claim callback.
    final request = await prepare(pending);
    try {
      _guard();
      final reply = await request.sendAfter(
        onSubmit: () async {
          _guard();
          storageUnconfirmed = true;
          await store.claim(pending, _lease);
          _guard();
          record = pending.next(LabelCreationPhase.unknown);
          storageUnconfirmed = false;
          _notify();
          _guard();
        },
      );
      _guard();
      final data = reply['data'];
      if (data is! Map) throw const FormatException('Creation receipt missing');
      final id = data['label_id'];
      if (id is! int || id <= 0) {
        throw const FormatException('Creation receipt ID required');
      }
      // Preserve the actual positive ACK even when the follow-up read fails.
      _ack = id;
      _ackOrigin = LabelCreationOrigin.postAcknowledgement;
      // Validate immutable identity and canonical input against actual receipt;
      // actual adapter performs the same strict checks for fresh reads.
      final actual = await inspect(pending, id);
      _guard();
      if (!actual.matchesFrozenInput) {
        throw const FormatException(
          'Creation receipt differs; review required',
        );
      }
      _ack = id;
      _ackOrigin = LabelCreationOrigin.postAcknowledgement;
      storageUnconfirmed = true;
      await store.acknowledge(
        record!,
        id,
        _lease,
        origin: LabelCreationOrigin.postAcknowledgement,
      );
      _guard();
      record = record!.next(
        LabelCreationPhase.knownID,
        id,
        LabelCreationOrigin.postAcknowledgement,
      );
      storageUnconfirmed = false;
    } finally {
      request.retire();
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
