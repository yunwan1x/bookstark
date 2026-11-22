import 'dart:async';
import 'dart:convert';
import 'secure_record_store.dart';
import 'owned15_creation_marker_metadata.dart';

/// No draft contents, password, title, labels or resource URLs are persisted.
final class Owned15CreationMarker {
  const Owned15CreationMarker({
    required this.owner,
    required this.operation,
    required this.collection,
    required this.kind,
    required this.inputHash,
    this.knownId,
  });
  final String owner, operation, collection, kind, inputHash;
  final int? knownId;
  static final hex64 = RegExp(r'^[a-f0-9]{64}$');
  static final hex32 = RegExp(r'^[a-f0-9]{32}$');
  static const kinds = {
    'markdown',
    'html',
    'spreadsheet',
    'drawing',
    'mindmap',
    'richdoc',
    'presentation',
  };
  String encode() => jsonEncode({
    'v': 1,
    'owner': owner,
    'operation': operation,
    'collection': collection,
    'kind': kind,
    'input': inputHash,
    'phase': knownId == null ? 'unknown' : 'known',
    'id': knownId,
  });
  factory Owned15CreationMarker.decode(String raw, String owner) {
    if (utf8.encode(raw).length > 2048) {
      throw const FormatException('Creation marker bound');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v.length != 8 ||
        v.keys.toSet().difference({
          'v',
          'owner',
          'operation',
          'collection',
          'kind',
          'input',
          'phase',
          'id',
        }).isNotEmpty ||
        v['v'] != 1 ||
        v['owner'] != owner ||
        !hex64.hasMatch(owner) ||
        v['operation'] is! String ||
        !hex32.hasMatch(v['operation'] as String) ||
        !{'note', 'article'}.contains(v['collection']) ||
        !kinds.contains(v['kind']) ||
        v['input'] is! String ||
        !hex64.hasMatch(v['input'] as String) ||
        !(v['phase'] == 'unknown' && v['id'] == null ||
            v['phase'] == 'known' && v['id'] is int && (v['id'] as int) > 0)) {
      throw const FormatException('Invalid creation marker');
    }
    final result = Owned15CreationMarker(
      owner: owner,
      operation: v['operation'] as String,
      collection: v['collection'] as String,
      kind: v['kind'] as String,
      inputHash: v['input'] as String,
      knownId: v['id'] as int?,
    );
    if (result.encode() != raw) {
      throw const FormatException('Noncanonical creation marker');
    }
    return result;
  }
}

/// The generation-wide lease and serial queue cover the entire read/write/flush/
/// readback sequence. A durable unknown is a one-time authorization, never an
/// idempotent put. Loaded records expose only inspect/cleanup, not submit.
final class Owned15CreationJournal {
  Owned15CreationJournal({
    required this.owner,
    required this.isCurrent,
    required Future<String?> Function(String) readValue,
    required Future<void> Function(String, String) writeValue,
    required Future<void> Function(String) deleteValue,
    required this.flush,
  }) : _records = SecureRecordStore(
         prefix: prefix,
         namespace: owner,
         readValue: readValue,
         writeValue: writeValue,
         deleteValue: deleteValue,
       ) {
    if (!Owned15CreationMarker.hex64.hasMatch(owner)) {
      throw ArgumentError('Opaque owner required');
    }
    if (_leases.containsKey(owner)) {
      throw StateError('Generation creation already open');
    }
    _leases[owner] = _lease;
  }
  static const prefix = Owned15CreationMarkerMetadata.prefix;
  final String owner;
  final bool Function() isCurrent;
  final Future<void> Function() flush;
  final SecureRecordStore _records;
  final Object _lease = Object();
  static final _leases = <String, Object>{};
  static final _tails = <String, Future<void>>{};
  bool _retired = false, _submitted = false;
  Future<void>? _closing;
  String? _removed;
  bool get current {
    try {
      return !_retired && identical(_leases[owner], _lease) && isCurrent();
    } catch (_) {
      return false;
    }
  }

  void _guard() {
    if (!current) throw StateError('Creation owner retired');
  }

  Future<T> _ordered<T>(Future<T> Function() work) {
    final next = (_tails[owner] ?? Future<void>.value()).then((_) async {
      _guard();
      return work();
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[owner] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[owner], tail)) _tails.remove(owner);
      }),
    );
    return next;
  }

  Future<Owned15CreationMarker?> load() => _ordered(() async {
    final raw = await _records.readRecord(0);
    _guard();
    return raw == null ? null : Owned15CreationMarker.decode(raw, owner);
  });
  Future<void> claim(Owned15CreationMarker marker) {
    _guard();
    if (_submitted || marker.owner != owner || marker.knownId != null) {
      throw StateError('Creation cannot be submitted again');
    }
    // Synchronous consumption also prevents retry following an uncertain write.
    _submitted = true;
    final canonical = Owned15CreationMarker.decode(
      marker.encode(),
      owner,
    ).encode();
    return _ordered(() async {
      if (await _records.readRecord(0) != null) {
        throw StateError('Unresolved creation exists');
      }
      _guard();
      await _records.writeRecord(0, canonical);
      await flush();
      final actual = await _records.readRecord(0);
      _guard();
      if (actual != canonical) {
        throw StateError('Creation claim was not durable');
      }
    });
  }

  Future<void> acknowledge(Owned15CreationMarker expected, int id) =>
      _ordered(() async {
        if (id <= 0 ||
            expected.owner != owner ||
            expected.knownId != null && expected.knownId != id) {
          throw ArgumentError('Exact actual receipt ID required');
        }
        final desired = Owned15CreationMarker(
          owner: owner,
          operation: expected.operation,
          collection: expected.collection,
          kind: expected.kind,
          inputHash: expected.inputHash,
          knownId: id,
        ).encode();
        final actual = await _records.readRecord(0);
        _guard();
        if (actual != expected.encode() && actual != desired) {
          throw StateError('Creation record changed or missing');
        }
        if (actual != desired) await _records.writeRecord(0, desired);
        await flush();
        final checked = await _records.readRecord(0);
        _guard();
        if (checked != desired) {
          throw StateError('Creation acknowledgement was not durable');
        }
      });

  /// Caller supplies fresh receipt+full-tuple evidence after origin retirement.
  /// true must mean exact known ID/current fingerprint, or unknown+no receipt
  /// following explicit cancellation. No SQL mutation occurs here.
  Future<void> clearReviewed(
    Owned15CreationMarker expected, {
    required Future<bool> Function() revalidate,
  }) => _ordered(() async {
    final canonical = expected.encode();
    final initial = await _records.readRecord(0);
    if (initial != canonical && !(initial == null && _removed == canonical)) {
      throw StateError('Creation record changed');
    }
    _guard();
    if (!await revalidate()) throw StateError('Creation review changed');
    _guard();
    final fresh = await _records.readRecord(0);
    _guard();
    if (fresh != canonical && !(fresh == null && _removed == canonical)) {
      throw StateError('Creation record changed');
    }
    if (fresh != null) {
      await _records.removeRecord(0);
      _removed = canonical;
    }
    await flush();
    final remaining = await _records.readRecord(0);
    _guard();
    if (remaining != null) {
      throw StateError('Creation record removal was not durable');
    }
  });
  Future<void> retire() {
    _retired = true;
    return _closing ??= () async {
      await (_tails[owner] ?? Future<void>.value());
      if (identical(_leases[owner], _lease)) _leases.remove(owner);
    }();
  }
}
