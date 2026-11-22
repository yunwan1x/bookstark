import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'topic_creation_attempt.dart';
import 'topic_creation_store.dart';

class TopicCreationReview {
  const TopicCreationReview({
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

typedef PrepareTopicCreation =
    Future<PreparedAuthenticatedJsonRequest> Function(TopicCreationAttempt);
typedef InspectTopicCreation =
    Future<TopicCreationReview> Function(TopicCreationAttempt, int);

/// Retired controllers never change a replacement owner or re-send on recovery.
class TopicCreationController extends ChangeNotifier {
  TopicCreationController({
    required this.store,
    required this.prepare,
    required this.inspect,
  }) {
    store.acquire(_lease);
  }
  final TopicCreationStore store;
  final PrepareTopicCreation prepare;
  final InspectTopicCreation inspect;
  final Object _lease = Object();
  TopicCreationAttempt? record;
  TopicCreationReview? reviewed;
  int? _ack;
  bool endedDurably = false;
  bool busy = false, storageUnconfirmed = false, _closed = false;
  String? error;
  bool get hasKnownAcknowledgement => _ack != null;
  bool get current => !_closed && store.isCurrent();
  void _guard() {
    if (!current) throw StateError('Topic creation owner retired');
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

  Future<void> reload() => _run(() async {
    final a = await store.load();
    _guard();
    record = a;
    reviewed = null;
    storageUnconfirmed = false;
  });
  Future<void> begin(TopicCreationAttempt input) => _run(() async {
    storageUnconfirmed = true;
    await store.insert(input, _lease);
    _guard();
    record = input;
    storageUnconfirmed = false;
  });
  Future<void> submit() => _run(() async {
    final pending = record;
    if (storageUnconfirmed ||
        pending == null ||
        pending.phase != TopicCreationPhase.pending) {
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
          record = pending.next(TopicCreationPhase.unknown);
          storageUnconfirmed = false;
          _notify();
          _guard();
        },
      );
      _guard();
      final data = reply['data'];
      if (data is! Map) throw const FormatException('Creation receipt missing');
      final id =
          data[pending.kind == TopicCreationKind.topic
              ? 'topic_id'
              : pending.kind == TopicCreationKind.summary
              ? 'summary_id'
              : 'comment_id'];
      if (id is! int || id <= 0) {
        throw const FormatException('Creation receipt ID required');
      }
      // Positive server ACK remains known even if a later read fails.
      _ack = id;
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
      storageUnconfirmed = true;
      await store.acknowledge(record!, id, _lease);
      _guard();
      record = record!.next(TopicCreationPhase.knownID, id);
      storageUnconfirmed = false;
    } finally {
      request.retire();
    }
  });
  Future<void> retryAcknowledgement() => _run(() async {
    final a = record, id = _ack;
    if (a == null || id == null) throw StateError('Known receipt required');
    storageUnconfirmed = true;
    await store.acknowledge(a, id, _lease);
    _guard();
    record = a.next(TopicCreationPhase.knownID, id);
    storageUnconfirmed = false;
  });
  Future<void> review(int id) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase == TopicCreationPhase.pending ||
        id <= 0) {
      throw StateError('Unknown record required');
    }
    final result = await inspect(a, id);
    _guard();
    reviewed = result;
  });
  Future<bool> verifyKnown(TopicCreationReview selected) async {
    if (busy || !current || storageUnconfirmed) return false;
    final a = record;
    if (a == null ||
        a.phase != TopicCreationPhase.knownID ||
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

  Future<void> adopt(TopicCreationReview selected) => _run(() async {
    final a = record;
    if (storageUnconfirmed ||
        a == null ||
        a.phase != TopicCreationPhase.unknown ||
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
    storageUnconfirmed = true;
    await store.acknowledge(a, fresh.id, _lease);
    _guard();
    record = a.next(TopicCreationPhase.knownID, fresh.id);
    storageUnconfirmed = false;
  });
  Future<void> end(TopicCreationAttempt captured) => _run(() async {
    if (storageUnconfirmed || !identical(record, captured)) {
      throw StateError('Fresh record required');
    }
    storageUnconfirmed = true;
    await store.end(captured, _lease);
    _guard();
    endedDurably = true;
    record = null;
    reviewed = null;
    storageUnconfirmed = false;
  });
  @override
  void dispose() {
    _closed = true;
    store.release(_lease);
    super.dispose();
  }
}
