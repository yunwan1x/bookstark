import 'dart:async';
import 'dart:collection';

class LocalStorageRetired implements Exception {
  const LocalStorageRetired();
  @override
  String toString() => 'Local storage session has been retired';
}

/// Coordinates complete local operations, including their SQL and blob work.
/// Shared operations may overlap; a queued maintenance operation blocks later
/// shared operations. Every repository for one storage identity must share this.
class LocalDataMaintenance {
  LocalDataMaintenance();

  static final _storage = <String, LocalDataMaintenance>{};
  static final Object _zoneKey = Object();

  factory LocalDataMaintenance.forStorage(String identity) {
    if (identity.isEmpty) {
      throw ArgumentError.value(
        identity,
        'identity',
        'Storage identity required',
      );
    }
    return _storage.putIfAbsent(identity, LocalDataMaintenance.new);
  }

  /// Used only after an explicit durable native source reentry receipt. Old
  /// repositories keep their retired object and can never access this new gate.
  static LocalDataMaintenance renewRetiredStorage(String identity) {
    final previous = _storage[identity];
    if (previous == null || !previous.retired) {
      throw StateError('Only a retired storage session can be renewed');
    }
    final replacement = LocalDataMaintenance();
    _storage[identity] = replacement;
    return replacement;
  }

  final _waiting = Queue<_Request>();
  int _shared = 0;
  bool _exclusive = false;
  bool _retired = false;
  bool get retired => _retired;

  /// Opaque identity for the currently held exclusive operation. A snapshot
  /// bound to this identity cannot be reused after ordinary writers resume.
  Object? get exclusiveIdentity {
    if (_retired) return null;
    final leases = Zone.current[_zoneKey] as Map<LocalDataMaintenance, _Lease>?;
    final lease = leases?[this];
    if (lease == null || lease.released || !lease.exclusive) return null;
    return lease.identity;
  }

  bool get exclusiveOperationDrained {
    if (exclusiveIdentity == null) return false;
    final leases = Zone.current[_zoneKey] as Map<LocalDataMaintenance, _Lease>;
    return leases[this]!.references == 1;
  }

  bool get maintenanceActive => _exclusive;
  bool get maintenanceRequested =>
      _exclusive || _waiting.any((request) => request.exclusive);

  /// Close the old database first, then seal it immediately before leaving the
  /// exclusive activation operation. Old queued callbacks must never reopen it.
  void retire() {
    final leases = Zone.current[_zoneKey] as Map<LocalDataMaintenance, _Lease>?;
    final lease = leases?[this];
    if (_retired ||
        lease == null ||
        lease.released ||
        !lease.exclusive ||
        lease.references != 1) {
      throw StateError(
        'Retirement requires an exclusive, fully drained operation',
      );
    }
    _retired = true;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().ready.completeError(const LocalStorageRetired());
    }
  }

  Future<T> use<T>(FutureOr<T> Function() operation) => _run(false, operation);

  Future<T> exclusive<T>(FutureOr<T> Function() operation) =>
      _run(true, operation);

  Future<T> _run<T>(bool exclusive, FutureOr<T> Function() operation) async {
    if (_retired) throw const LocalStorageRetired();
    final leases = Zone.current[_zoneKey] as Map<LocalDataMaintenance, _Lease>?;
    final inherited = leases?[this];
    if (inherited != null &&
        identical(inherited.owner, this) &&
        !inherited.released) {
      if (exclusive && !inherited.exclusive) {
        throw StateError(
          'Cannot upgrade a local operation to exclusive maintenance',
        );
      }
      return _invoke(inherited, operation);
    }
    final request = _Request(exclusive);
    _waiting.add(request);
    _drain();
    final lease = await request.ready.future;
    return runZoned(
      () => _invoke(lease, operation),
      zoneValues: {
        _zoneKey: <LocalDataMaintenance, _Lease>{...?leases, this: lease},
      },
    );
  }

  Future<T> _invoke<T>(_Lease lease, FutureOr<T> Function() operation) async {
    lease.references++;
    try {
      return await operation();
    } finally {
      lease.references--;
      if (lease.references == 0) {
        lease.released = true;
        if (lease.exclusive) {
          _exclusive = false;
        } else {
          _shared--;
        }
        _drain();
      }
    }
  }

  void _drain() {
    if (_exclusive || _waiting.isEmpty) return;
    if (_waiting.first.exclusive) {
      if (_shared != 0) return;
      _exclusive = true;
      _waiting.removeFirst().ready.complete(_Lease(this, true));
      return;
    }
    while (_waiting.isNotEmpty && !_waiting.first.exclusive) {
      _shared++;
      _waiting.removeFirst().ready.complete(_Lease(this, false));
    }
  }
}

class _Request {
  _Request(this.exclusive);
  final bool exclusive;
  final ready = Completer<_Lease>();
}

class _Lease {
  _Lease(this.owner, this.exclusive);
  final LocalDataMaintenance owner;
  final bool exclusive;
  final Object identity = Object();
  int references = 0;
  bool released = false;
}
