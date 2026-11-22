import 'dart:async';
import 'bookmark_creation_attempt.dart';

class BookmarkCreationStorageUnconfirmed implements Exception {
  const BookmarkCreationStorageUnconfirmed();
}

class BookmarkCreationStore {
  BookmarkCreationStore({
    required this.scope,
    required this.key,
    required this.read,
    required this.write,
    required this.remove,
    required this.flush,
    required this.isCurrent,
  });
  static const prefix = 'bookstark.bookmark-create.v1.';
  static final _tails = <String, Future<void>>{};
  static final _leases = <String, Object>{};
  static final _ended = <String>{};
  final String scope, key;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final Future<void> Function(String) remove;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  String get metadataKey => '$prefix$scope.$key';
  void guard() {
    if (!isCurrent()) throw StateError('Bookmark creation owner retired');
  }

  void acquire(Object lease) {
    guard();
    if (_leases.containsKey(metadataKey)) {
      throw const BookmarkCreationStorageUnconfirmed();
    }
    _leases[metadataKey] = lease;
  }

  void release(Object lease) {
    if (identical(_leases[metadataKey], lease)) _leases.remove(metadataKey);
  }

  void _owned(Object lease) {
    guard();
    if (!identical(_leases[metadataKey], lease)) {
      throw const BookmarkCreationStorageUnconfirmed();
    }
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

  void _identity(BookmarkCreationAttempt a) {
    if (a.scope != scope || a.key != key) {
      throw const FormatException('Creation scope mismatch');
    }
  }

  Future<BookmarkCreationAttempt?> load() => _ordered(() async {
    guard();
    final raw = await read(metadataKey);
    guard();
    if (raw == null) return null;
    final a = BookmarkCreationAttempt.decode(raw);
    _identity(a);
    return a;
  });
  Future<void> _persist(BookmarkCreationAttempt a, Object lease) async {
    final raw = a.encode();
    await write(metadataKey, raw);
    _owned(lease);
    await flush();
    _owned(lease);
    if (await read(metadataKey) != raw) {
      throw const BookmarkCreationStorageUnconfirmed();
    }
    _owned(lease);
  }

  Future<void> insert(BookmarkCreationAttempt a, Object lease) =>
      _ordered(() async {
        _owned(lease);
        _identity(a);
        if (a.phase != BookmarkCreationPhase.pending ||
            _ended.contains(metadataKey) ||
            await read(metadataKey) != null) {
          throw const BookmarkCreationStorageUnconfirmed();
        }
        _owned(lease);
        await _persist(a, lease);
      });

  /// Strict single transition; idempotence must never grant another POST.
  Future<void> claim(BookmarkCreationAttempt a, Object lease) =>
      _ordered(() async {
        _owned(lease);
        _identity(a);
        if (a.phase != BookmarkCreationPhase.pending ||
            await read(metadataKey) != a.encode()) {
          throw const BookmarkCreationStorageUnconfirmed();
        }
        _owned(lease);
        await _persist(a.next(BookmarkCreationPhase.unknown), lease);
      });

  /// Known ACK retries storage only.
  Future<void> acknowledge(
    BookmarkCreationAttempt expected,
    int id,
    Object lease,
  ) => _ordered(() async {
    _owned(lease);
    _identity(expected);
    if (id <= 0 || expected.phase == BookmarkCreationPhase.pending) {
      throw StateError('Submitted attempt required');
    }
    final raw = await read(metadataKey);
    _owned(lease);
    final known = expected.next(BookmarkCreationPhase.knownID, id);
    if (raw != expected.encode() && raw != known.encode()) {
      throw const BookmarkCreationStorageUnconfirmed();
    }
    await _persist(known, lease);
  });
  Future<void> end(BookmarkCreationAttempt expected, Object lease) =>
      _ordered(() async {
        _owned(lease);
        _identity(expected);
        if (await read(metadataKey) != expected.encode()) {
          throw const BookmarkCreationStorageUnconfirmed();
        }
        _owned(lease);
        _ended.add(metadataKey);
        await remove(metadataKey);
        _owned(lease);
        await flush();
        _owned(lease);
        if (await read(metadataKey) != null) {
          throw const BookmarkCreationStorageUnconfirmed();
        }
        _owned(lease);
      });
}
