import 'owned15_save_marker_metadata.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'secure_record_store.dart';
import 'protected_owned_marker_metadata.dart';

class ProtectedComplexObservation {
  const ProtectedComplexObservation({
    required this.fingerprint,
    required this.inputDigest,
  });
  final String fingerprint, inputDigest;
}

class ProtectedComplexMarker {
  const ProtectedComplexMarker({
    required this.scope,
    required this.attempt,
    required this.baselineFingerprint,
    required this.inputDigest,
    this.knownFingerprint,
  });
  final String scope, attempt, baselineFingerprint, inputDigest;
  final String? knownFingerprint;
  bool get known => knownFingerprint != null;
  String encode() => jsonEncode({
    'v': 1,
    'scope': scope,
    'attempt': attempt,
    'baseline': baselineFingerprint,
    'input': inputDigest,
    'state': known ? 'known' : 'unknown',
    if (known) 'known': knownFingerprint,
  });
  static final _hex64 = RegExp(r'^[a-f0-9]{64}$'),
      _hex32 = RegExp(r'^[a-f0-9]{32}$');
  factory ProtectedComplexMarker.decode(String raw, String scope) {
    if (raw.length > 2048) {
      throw const FormatException('Protected marker bound');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['v'] != 1 ||
        data['scope'] != scope ||
        data.keys.toSet().difference({
          'v',
          'scope',
          'attempt',
          'baseline',
          'input',
          'state',
          'known',
        }).isNotEmpty ||
        data['attempt'] is! String ||
        !_hex32.hasMatch(data['attempt'] as String) ||
        data['baseline'] is! String ||
        !_hex64.hasMatch(data['baseline'] as String) ||
        data['input'] is! String ||
        !_hex64.hasMatch(data['input'] as String) ||
        !{'unknown', 'known'}.contains(data['state']) ||
        (data['state'] == 'known'
            ? data['known'] is! String ||
                  !_hex64.hasMatch(data['known'] as String)
            : data.containsKey('known')) ||
        data.length != (data['state'] == 'known' ? 7 : 6)) {
      throw const FormatException('Invalid protected marker');
    }
    return ProtectedComplexMarker(
      scope: scope,
      attempt: data['attempt'] as String,
      baselineFingerprint: data['baseline'] as String,
      inputDigest: data['input'] as String,
      knownFingerprint: data['known'] as String?,
    );
  }
}

/// Metadata only. No password, body, title, labels, server URL or response body.
class ProtectedOwnedComplexJournal {
  ProtectedOwnedComplexJournal({
    required this.scope,
    required this.ownerTag,
    required this.isCurrent,
    required Future<String?> Function(String) readValue,
    required Future<void> Function(String, String) writeValue,
    required Future<void> Function(String) deleteValue,
    required this.flush,
    String recordPrefix = ProtectedOwnedMarkerMetadata.prefix,
  }) : _records = SecureRecordStore(
         prefix: recordPrefix,
         namespace: jsonEncode([ownerTag, scope]),
         readValue: readValue,
         writeValue: writeValue,
         deleteValue: deleteValue,
       ) {
    if (!const {
      ProtectedOwnedMarkerMetadata.prefix,
      Owned15SaveMarkerMetadata.prefix,
    }.contains(recordPrefix)) {
      throw ArgumentError('Unsupported no-body journal prefix');
    }
    if (!ProtectedComplexMarker._hex64.hasMatch(scope) ||
        !ProtectedComplexMarker._hex64.hasMatch(ownerTag)) {
      throw ArgumentError('Opaque protected scope required');
    }
    if (_leases.containsKey(scope)) {
      throw StateError('Protected resource already open');
    }
    _leases[scope] = _lease;
  }
  static String ownerTagFor({
    required String server,
    required int memberId,
    required String namespace,
  }) {
    if (memberId <= 0 || server.isEmpty || namespace.isEmpty) {
      throw ArgumentError('Owned principal required');
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned-protected-owner-v1',
              server,
              memberId,
              namespace,
            ]),
          ),
        )
        .toString();
  }

  // The slot follows the owned resource across kind/protection changes.
  // Baseline fingerprint and input digest still bind the full actual kind.
  // A changed kind can never hide the prior resource's unknown marker.
  static String scopeFor({
    required String server,
    required int memberId,
    required String namespace,
    required int resourceId,
    required String kind,
  }) {
    if (memberId <= 0 ||
        resourceId <= 0 ||
        namespace.isEmpty ||
        !{
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(kind)) {
      throw ArgumentError('Owned protected note identity required');
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned-protected-resource-v1',
              server,
              memberId,
              namespace,
              resourceId,
            ]),
          ),
        )
        .toString();
  }

  final String scope, ownerTag;
  final bool Function() isCurrent;
  final Future<void> Function() flush;
  final SecureRecordStore _records;
  final Object _lease = Object();
  bool _closed = false;
  ProtectedComplexMarker? _claimed, _known;
  String? _endingReviewedFingerprint;
  static final _leases = <String, Object>{};
  static final _tails = <String, Future<void>>{};
  bool get hasKnownReceipt => _known != null;
  bool get hasWarmAttempt => _claimed != null;
  void _guard() {
    bool current;
    try {
      current = isCurrent();
    } catch (_) {
      current = false;
    }
    if (_closed || !current || !identical(_leases[scope], _lease)) {
      throw StateError('Protected owner retired');
    }
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    final previous = _tails[scope];
    final next = (previous ?? Future<void>.value()).then((_) async {
      _guard();
      return action();
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[scope] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[scope], tail)) _tails.remove(scope);
      }),
    );
    return next;
  }

  Future<String?> _raw() async {
    _guard();
    final raw = await _records.readRecord(0);
    _guard();
    return raw;
  }

  Future<ProtectedComplexMarker?> load() => _ordered(() async {
    await flush();
    _guard();
    final raw = await _raw();
    return raw == null ? null : ProtectedComplexMarker.decode(raw, scope);
  });
  Future<void> _writeExact(String raw) async {
    _guard();
    await _records.writeRecord(0, raw);
    _guard();
    await flush();
    _guard();
    if (await _raw() != raw) {
      throw StateError('Protected marker durability unconfirmed');
    }
  }

  Future<void> claimUnknown({
    required String baselineFingerprint,
    required String inputDigest,
  }) => _ordered(() async {
    await flush();
    _guard();
    if (_claimed != null || await _raw() != null) {
      throw StateError('Protected save still needs review');
    }
    final record = ProtectedComplexMarker(
      scope: scope,
      attempt: List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      baselineFingerprint: baselineFingerprint,
      inputDigest: inputDigest,
    );
    ProtectedComplexMarker.decode(record.encode(), scope);
    _claimed =
        record; // Even failed durable claim must never authorize a retry.
    await _writeExact(record.encode());
  });
  void rememberKnownReceipt(String fingerprint) {
    _guard();
    if (_claimed == null ||
        !ProtectedComplexMarker._hex64.hasMatch(fingerprint)) {
      throw StateError('No protected save claim');
    }
    final old = _claimed!;
    _known = ProtectedComplexMarker(
      scope: scope,
      attempt: old.attempt,
      baselineFingerprint: old.baselineFingerprint,
      inputDigest: old.inputDigest,
      knownFingerprint: fingerprint,
    );
  }

  Future<void> _deleteExact(String expected) async {
    if (await _raw() != expected) throw StateError('Protected marker changed');
    await _records.removeRecord(0);
    _guard();
    await flush();
    _guard();
    if (await _raw() != null) throw StateError('Protected cleanup unconfirmed');
  }

  Future<void> finishKnown() => _ordered(() async {
    final known = _known;
    if (known == null) throw StateError('No confirmed protected receipt');
    final raw = await _raw();
    if (raw == null) {
      await flush();
      _guard();
      if (await _raw() != null) throw StateError('Cleanup changed');
    } else {
      final current = ProtectedComplexMarker.decode(raw, scope);
      if (current.attempt != known.attempt ||
          current.inputDigest != known.inputDigest ||
          current.baselineFingerprint != known.baselineFingerprint ||
          current.known && current.knownFingerprint != known.knownFingerprint) {
        throw StateError('Protected marker changed');
      }
      if (raw != known.encode()) await _writeExact(known.encode());
      await _deleteExact(known.encode());
    }
    _claimed = null;
    _known = null;
  });
  Future<void> confirmColdKnown(ProtectedComplexObservation actual) =>
      _ordered(() async {
        final raw = await _raw();
        if (raw == null) throw StateError('Protected marker missing');
        final record = ProtectedComplexMarker.decode(raw, scope);
        if (!record.known ||
            actual.fingerprint != record.knownFingerprint ||
            actual.inputDigest != record.inputDigest) {
          throw StateError('Protected receipt no longer matches');
        }
        _claimed = record;
        _known = record;
      });

  /// Explicit user review only; matching content is not historical request proof.
  Future<void> endReviewed({
    required String reviewedFingerprint,
    required Future<ProtectedComplexObservation> Function() fresh,
  }) => _ordered(() async {
    if (!ProtectedComplexMarker._hex64.hasMatch(reviewedFingerprint)) {
      throw const FormatException('Fresh protected fingerprint required');
    }
    final raw = await _raw();
    if (raw == null) {
      if (_endingReviewedFingerprint != reviewedFingerprint) {
        throw StateError('Protected marker unexpectedly missing');
      }
      final actual = await fresh();
      _guard();
      if (actual.fingerprint != reviewedFingerprint) {
        throw StateError('Protected source changed after review');
      }
      await flush();
      _guard();
      if (await _raw() != null) throw StateError('Protected cleanup changed');
      _claimed = null;
      _known = null;
      _endingReviewedFingerprint = null;
      return;
    }
    ProtectedComplexMarker.decode(raw, scope);
    final actual = await fresh();
    _guard();
    if (!ProtectedComplexMarker._hex64.hasMatch(actual.fingerprint) ||
        !ProtectedComplexMarker._hex64.hasMatch(actual.inputDigest) ||
        actual.fingerprint != reviewedFingerprint) {
      throw StateError('Protected source changed after review');
    }
    _endingReviewedFingerprint = reviewedFingerprint;
    await _deleteExact(raw);
    _claimed = null;
    _known = null;
    _endingReviewedFingerprint = null;
  });
  // Root joins already-started secure writes before keys-only migration scan.
  Future<void> drain() => _tails[scope] ?? Future<void>.value();
  void retire() {
    _closed = true;
    if (identical(_leases[scope], _lease)) _leases.remove(scope);
  }
}
