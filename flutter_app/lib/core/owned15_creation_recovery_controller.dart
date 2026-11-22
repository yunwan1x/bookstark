import 'owned_writable_generation15.dart';
import 'owned15_creation_journal.dart';

final class Owned15CreationReview {
  const Owned15CreationReview({
    required this.marker,
    required this.observation,
  });
  final Owned15CreationMarker marker;
  final Owned15CreationObservation? observation;
  bool get noReceipt => observation == null;
  bool get matching =>
      observation?.state == Owned15CreationResourceState.matching;
  String get fingerprint => [
    marker.encode(),
    observation?.receipt.id,
    observation?.receipt.inputHash,
    observation?.state.name,
    observation?.kind?.name,
    observation?.currentFingerprint,
  ].join('\n');
}

/// Coordinates the one real INSERT with body-free storage. Recovery has no
/// replay method. This owner must be retired/drained before generation switch.
final class Owned15CreationRecoveryController {
  Owned15CreationRecoveryController({
    required this.creator,
    required this.journal,
    required this.isCurrent,
  });
  final Owned15GenerationCreator creator;
  final Owned15CreationJournal journal;
  final bool Function() isCurrent;
  bool _closed = false, _started = false;
  Future<void>? _closing;
  Future<void>? _origin;
  Owned15CreationReview? _cleanup;
  Owned15CreationReview? _cancelCleanup;
  bool get current {
    try {
      return !_closed && creator.current && journal.current && isCurrent();
    } catch (_) {
      return false;
    }
  }

  void _guard() {
    if (!current) throw StateError('Creation scope retired');
  }

  Future<Owned15CreationReceipt> submit(Owned15PreparedCreation input) {
    _guard();
    if (_started) throw StateError('Creation result must be reviewed');
    _started = true;
    final done = _submit(input);
    _origin = done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return done;
  }

  Future<Owned15CreationReceipt> _submit(Owned15PreparedCreation input) async {
    final marker = Owned15CreationMarker(
      owner: journal.owner,
      operation: input.creationKey,
      collection: input.collection,
      kind: input.kind.name,
      inputHash: input.inputHash,
    );
    final receipt = await creator.submit(
      input,
      beforeInsert: (digest) async {
        _guard();
        if (digest != marker.inputHash) {
          throw StateError('Creation input changed');
        }
        await journal.claim(marker);
        _guard();
      },
    );
    _guard();
    _bind(marker, receipt);
    // A failure here is storage-only uncertainty. The SQL receipt remains the
    // authority, and the caller must replace its editor with read-only review.
    await journal.acknowledge(marker, receipt.id);
    _guard();
    return receipt;
  }

  void _bind(Owned15CreationMarker marker, Owned15CreationReceipt receipt) {
    if (receipt.creationKey != marker.operation ||
        receipt.collection != marker.collection ||
        receipt.inputHash != marker.inputHash ||
        marker.knownId != null && marker.knownId != receipt.id) {
      throw const FormatException('Creation receipt identity changed');
    }
  }

  Future<Owned15CreationReview> inspect() async {
    _guard();
    await _origin;
    _guard();
    final marker = await journal.load();
    _guard();
    if (marker == null) {
      throw StateError('Creation record missing; no retry authorized');
    }
    final actual = await creator.inspect(marker.operation);
    _guard();
    if (actual != null) {
      _bind(marker, actual.receipt);
      // A changed actual format may be honestly reviewed but never treated as
      // matching the original input or opened through the original engine.
      if (actual.state == Owned15CreationResourceState.matching &&
          actual.kind?.name != marker.kind) {
        throw const FormatException('Creation format identity changed');
      }
    } else if (marker.knownId != null) {
      throw const FormatException('Known creation receipt missing');
    }
    return Owned15CreationReview(marker: marker, observation: actual);
  }

  /// Explicit confirmation after reading the actual current resource. Changed,
  /// deleted or missing resources retain their operation record.
  Future<void> confirmSaved(Owned15CreationReview reviewed) async {
    _guard();
    if (_cancelCleanup != null) {
      throw StateError('Creation cancellation cleanup pending');
    }
    final previous = _cleanup;
    final fresh = previous ?? await inspect();
    if (!fresh.matching ||
        fresh.fingerprint != reviewed.fingerprint ||
        previous != null && previous.fingerprint != reviewed.fingerprint) {
      throw StateError('Creation review changed');
    }
    // Retain exact storage-only retry identity if removal succeeded but its
    // durability acknowledgement failed. Fresh SQL validation still runs.
    _cleanup = fresh;
    await journal.clearReviewed(
      fresh.marker,
      revalidate: () async {
        final actual = await creator.inspect(fresh.marker.operation);
        _guard();
        if (actual == null) return false;
        _bind(fresh.marker, actual.receipt);
        return actual.state == Owned15CreationResourceState.matching &&
            actual.kind?.name == fresh.marker.kind &&
            actual.currentFingerprint == fresh.observation!.currentFingerprint;
      },
    );
  }

  /// Explicitly abandon only the operation metadata after origin drain and a
  /// fresh absent receipt. It never creates/deletes a resource or draft body.
  Future<void> cancelUnsubmitted(Owned15CreationReview reviewed) async {
    _guard();
    await _origin;
    _guard();
    if (_cleanup != null) throw StateError('Known creation cleanup pending');
    final fresh = _cancelCleanup ?? await inspect();
    if (!fresh.noReceipt ||
        fresh.marker.knownId != null ||
        fresh.fingerprint != reviewed.fingerprint) {
      throw StateError('Creation cancellation evidence changed');
    }
    _cancelCleanup = fresh;
    await journal.clearReviewed(
      fresh.marker,
      revalidate: () async {
        final actual = await creator.inspect(fresh.marker.operation);
        _guard();
        return actual == null;
      },
    );
  }

  Future<void> retire() {
    _closed = true;
    return _closing ??= () async {
      // Cancellation is synchronous; draining is genuine, not merely UI close.
      final creatorDrain = creator.retire();
      await Future.wait<void>([creatorDrain, ?_origin]);
      await journal.retire();
    }();
  }
}
