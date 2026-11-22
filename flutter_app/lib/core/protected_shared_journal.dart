import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'protected_shared_marker_metadata.dart';

class ProtectedSharedObservation {
  const ProtectedSharedObservation({
    required this.identity,
    required this.sourceDigest,
    required this.fingerprint,
    required this.modified,
  });
  final String identity, sourceDigest, fingerprint, modified;
}

/// Hash-only journal. The source/body/password/capability token is never accepted.
class ProtectedSharedJournal {
  ProtectedSharedJournal({
    required this.capabilityPrincipal,
    required this.identity,
    required this.isCurrent,
    required this._listKeys,
    required Future<String?> Function(String) readValue,
    required Future<void> Function(String, String) writeValue,
    required Future<void> Function(String) deleteValue,
    required this.flush,
  }) : _read = readValue,
       _write = writeValue,
       _delete = deleteValue {
    if (![
      capabilityPrincipal,
      identity,
    ].every((v) => RegExp(r'^[a-f0-9]{64}$').hasMatch(v))) {
      throw const FormatException('Invalid shared principal');
    }
    if (_leases.containsKey(capabilityPrincipal)) {
      throw StateError('Shared capability already open');
    }
    _leases[capabilityPrincipal] = _lease;
  }
  static String capabilityFor({
    required String server,
    required int shareId,
    required String capabilityHash,
  }) {
    final uri = Uri.parse(server);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        shareId <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(capabilityHash)) {
      throw const FormatException('Invalid shared capability principal');
    }
    // The capability URL/token hash is the group. shareId is validated here,
    // but belongs to the full identity hash: deleting/recreating a link with the
    // same capability must not silently bypass the old submission's record.
    return sha256
        .convert(
          utf8.encode(
            jsonEncode(['protected-shared-cap-v1', server, capabilityHash]),
          ),
        )
        .toString();
  }

  final String capabilityPrincipal, identity;
  final bool Function() isCurrent;
  final Future<List<String>> Function() _listKeys;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _delete;
  final Future<void> Function() flush;
  static final _leases = <String, Object>{}, _tails = <String, Future<void>>{};
  final _lease = Object();
  bool _closed = false;
  Future<void>? _closeFuture;
  ProtectedSharedMarkerMetadata? _claimed, _known;
  final _ending = <String>{};
  ProtectedSharedMarkerKey get key => ProtectedSharedMarkerKey(
    ProtectedSharedMarkerMetadata.principalFor(capabilityPrincipal, identity),
  );
  bool get hasAttempt => _claimed != null;
  bool get hasKnown => _known != null;
  void _guard() {
    bool current;
    try {
      current = isCurrent();
    } catch (_) {
      current = false;
    }
    if (_closed ||
        !current ||
        !identical(_leases[capabilityPrincipal], _lease)) {
      throw StateError('Shared marker owner retired');
    }
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    final previous = _tails[capabilityPrincipal];
    final next = (previous ?? Future<void>.value()).then((_) async {
      _guard();
      return action();
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[capabilityPrincipal] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[capabilityPrincipal], tail)) {
          _tails.remove(capabilityPrincipal);
        }
      }),
    );
    return next;
  }

  Future<String?> _raw(ProtectedSharedMarkerKey key) async {
    _guard();
    final raw = await _read(key.storageKey);
    _guard();
    if (raw != null && utf8.encode(raw).length > 4096) {
      throw const FormatException('Shared marker exceeds bound');
    }
    return raw;
  }

  Future<List<ProtectedSharedMarkerMetadata>> _scan() async {
    _guard();
    final all = await _listKeys();
    _guard();
    if (all.length > 4096 ||
        all.any((key) => key.length > 4096) ||
        all.toSet().length != all.length) {
      throw StateError('Shared key inventory exceeds bound');
    }
    final selected = all
        .where((key) => key.startsWith(ProtectedSharedMarkerKey.prefix))
        .toList();
    if (selected.length > 128) {
      throw StateError('Shared marker inventory exceeds bound');
    }
    final matches = <ProtectedSharedMarkerMetadata>[];
    for (final rawKey in selected) {
      final key = ProtectedSharedMarkerKey.tryParse(rawKey);
      if (key == null) {
        throw const FormatException('Unrecognized shared marker key');
      }
      final raw = await _raw(key);
      if (raw == null) {
        throw StateError('Shared marker changed during inventory');
      }
      // Only shared metadata values are read. Malformed/unknown records are retained
      // and block writes conservatively; no other editor draft value is loaded.
      final value = ProtectedSharedMarkerMetadata.parse(key, raw);
      if (value.capabilityPrincipal == capabilityPrincipal) matches.add(value);
      if (matches.length > 16) {
        throw StateError('Shared capability has too many records');
      }
    }
    _guard();
    return List.unmodifiable(matches);
  }

  Future<List<ProtectedSharedMarkerMetadata>> loadGroup() => _ordered(() async {
    await flush();
    _guard();
    final records = await _scan();
    final claimed = _claimed;
    if (claimed != null &&
        _ending.contains(claimed.key.principal) &&
        !records.any(
          (record) => record.key.principal == claimed.key.principal,
        ) &&
        await _raw(claimed.key) == null) {
      // Ending was already explicitly authorized, but delete/flush ACK was lost.
      // A fresh storage-only flush + absence check may finish that same cleanup;
      // it does not authorize another send or invent a server outcome.
      _ending.remove(claimed.key.principal);
      _claimed = null;
      _known = null;
    }
    return records;
  });
  Future<void> _writeExact(
    ProtectedSharedMarkerMetadata value, {
    required String? expected,
  }) async {
    if (await _raw(value.key) != expected) {
      throw StateError('Shared marker changed');
    }
    _guard();
    await _write(value.key.storageKey, value.encode());
    _guard();
    await flush();
    _guard();
    if (await _raw(value.key) != value.encode()) {
      throw StateError('Shared marker durability unconfirmed');
    }
  }

  Future<void> claimUnknown({
    required String expectedSource,
    required String submittedSource,
  }) => _ordered(() async {
    await flush();
    _guard();
    if (_claimed != null || (await _scan()).isNotEmpty) {
      throw StateError('Previous shared submission needs review');
    }
    final value = ProtectedSharedMarkerMetadata(
      key: key,
      capabilityPrincipal: capabilityPrincipal,
      identity: identity,
      operation: List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      expectedSource: expectedSource,
      submittedSource: submittedSource,
      phase: ProtectedSharedMarkerPhase.unknown,
    );
    _claimed =
        value; // Failed flush is conservative unknown; cannot grant another send.
    await _writeExact(value, expected: null);
  });
  void rememberKnown({required String sourceDigest, required String modified}) {
    _guard();
    final previous = _claimed;
    if (previous == null || sourceDigest != previous.submittedSource) {
      throw StateError('Unverified shared receipt');
    }
    _known = ProtectedSharedMarkerMetadata(
      key: previous.key,
      capabilityPrincipal: capabilityPrincipal,
      identity: identity,
      operation: previous.operation,
      expectedSource: previous.expectedSource,
      submittedSource: previous.submittedSource,
      phase: ProtectedSharedMarkerPhase.known,
      modified: modified,
    );
  }

  Future<void> _deleteExact(ProtectedSharedMarkerMetadata record) async {
    final raw = await _raw(record.key);
    if (raw == null) {
      if (!_ending.contains(record.key.principal)) {
        throw StateError('Shared marker unexpectedly missing');
      }
    } else {
      if (raw != record.encode()) throw StateError('Shared marker changed');
      _ending.add(record.key.principal);
      _guard();
      await _delete(record.key.storageKey);
      _guard();
    }
    await flush();
    _guard();
    if (await _raw(record.key) != null) {
      throw StateError('Shared marker cleanup unconfirmed');
    }
    _ending.remove(record.key.principal);
  }

  Future<void> _persistKnown() async {
    final known = _known, claimed = _claimed;
    if (known == null || claimed == null) {
      throw StateError('No known shared receipt');
    }
    final raw = await _raw(known.key);
    if (raw == null) {
      if (!_ending.contains(known.key.principal)) {
        throw StateError('Known shared marker missing');
      }
    } else if (raw == claimed.encode()) {
      await _writeExact(known, expected: raw);
    } else if (raw != known.encode()) {
      throw StateError('Shared marker changed');
    }
    // A preceding write may have applied while its flush ACK failed. Observing
    // equal bytes alone is not durability; storage-only retry must flush again.
    await flush();
    _guard();
    final confirmed = await _raw(known.key);
    if (confirmed != known.encode() &&
        !(confirmed == null && _ending.contains(known.key.principal))) {
      throw StateError('Known shared marker durability unconfirmed');
    }
  }

  /// Retry only known receipt storage. No source/body reconstruction or send.
  Future<void> persistKnown() => _ordered(_persistKnown);

  /// Cleanup follows a verified actual save/review. It never performs a PUT.
  Future<void> finishKnown() => _ordered(() async {
    await _persistKnown();
    final known = _known!;
    await _deleteExact(known);
    _known = null;
    _claimed = null;
  });

  /// Explicit UI consent. Identity changes may be ended only as unverifiable,
  /// never as proof that the earlier request saved or did not execute.
  Future<void> endReviewed(
    ProtectedSharedMarkerMetadata record, {
    required String reviewedFingerprint,
    required bool allowUnverifiable,
    required Future<ProtectedSharedObservation> Function() fresh,
  }) => _ordered(() async {
    if (record.capabilityPrincipal != capabilityPrincipal) {
      throw StateError('Wrong shared marker group');
    }
    final current = await _raw(record.key);
    if (current != record.encode() &&
        !(current == null && _ending.contains(record.key.principal))) {
      throw StateError('Shared marker changed');
    }
    final actual = await fresh();
    _guard();
    if (actual.fingerprint != reviewedFingerprint ||
        (!allowUnverifiable && actual.identity != record.identity)) {
      throw StateError('Shared source changed after review');
    }
    await _deleteExact(record);
    _claimed = null;
    _known = null;
  });
  Future<void> retire() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    final tail = _tails[capabilityPrincipal];
    if (tail != null) await tail;
    if (identical(_leases[capabilityPrincipal], _lease)) {
      _leases.remove(capabilityPrincipal);
    }
  }
}
