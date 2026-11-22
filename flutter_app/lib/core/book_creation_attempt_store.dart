import 'dart:async';
import 'dart:convert';
import 'book_creation_attempt.dart';

class BookCreationOwnerRetired implements Exception {
  const BookCreationOwnerRetired();
}

class BookCreationStorageUnconfirmed implements Exception {
  const BookCreationStorageUnconfirmed();
}

/// Full write+flush+readback is one queue item. Scope/key never read dynamically
/// from global session state. Root must inject real native durability barrier.
class BookCreationAttemptStore {
  BookCreationAttemptStore({
    required this.scope,
    required this.attemptKey,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    required this.flush,
    required this.isCurrent,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(attemptKey)) {
      throw ArgumentError('Invalid attempt key');
    }
  }
  static const prefix = 'bookstark.book-create.v1.';
  static final _tails = <String, Future<void>>{};
  static final _leases = <String, Object>{};
  static final _retiredKeys = <String>{};
  void acquireSubmission(Object token) {
    guard();
    if (_leases.containsKey(metadataKey) ||
        _retiredKeys.contains(metadataKey)) {
      throw const BookCreationStorageUnconfirmed();
    }
    _leases[metadataKey] = token;
  }

  void releaseSubmission(Object token) {
    if (identical(_leases[metadataKey], token)) _leases.remove(metadataKey);
  }

  void _lease(Object token) {
    guard();
    if (!identical(_leases[metadataKey], token)) {
      throw const BookCreationStorageUnconfirmed();
    }
  }

  Future<void> claimSubmission(BookCreationAttempt pending, Object token) =>
      _ordered(() async {
        _lease(token);
        _identity(pending);
        if (pending.state != BookAttemptState.pending) {
          throw StateError('Pending claim required');
        }
        final before = await readValue(metadataKey);
        _lease(token);
        if (before != pending.encode()) {
          throw const BookCreationStorageUnconfirmed();
        }
        final raw = pending.unknown().encode();
        await writeValue(metadataKey, raw);
        _lease(token);
        await flush();
        _lease(token);
        if (await readValue(metadataKey) != raw) {
          throw const BookCreationStorageUnconfirmed();
        }
        _lease(token);
      });
  final BookCreationScope scope;
  final String attemptKey;
  final Future<String?> Function(String key) readValue;
  final Future<void> Function(String key, String value) writeValue;
  final Future<void> Function(String key) deleteValue;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  String get metadataKey =>
      prefix +
      base64Url.encode(utf8.encode(jsonEncode([scope.toJson(), attemptKey])));
  void guard() {
    if (!isCurrent()) throw const BookCreationOwnerRetired();
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    final key = metadataKey, previous = _tails[metadataKey];
    Future<T> run() async {
      guard();
      return action();
    }

    final next = previous == null
        ? Future<T>.sync(run)
        : previous.then((_) => run());
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return next;
  }

  void _identity(BookCreationAttempt value) {
    if (value.key != attemptKey || value.scope.identity != scope.identity) {
      throw const FormatException('Book attempt owner mismatch');
    }
  }

  Future<BookCreationAttempt?> read() => _ordered(() async {
    final raw = await readValue(metadataKey);
    guard();
    if (raw == null) return null;
    final result = BookCreationAttempt.decode(raw);
    _identity(result);
    return result;
  });
  Future<void> put(
    BookCreationAttempt value, {
    BookCreationAttempt? expected,
  }) => _ordered(() async {
    _identity(value);
    final raw = value.encode();
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Book record exceeds bound');
    }
    if (expected != null) _identity(expected);
    guard();
    final before = await readValue(metadataKey);
    guard();
    if (before == null &&
        (expected != null || _retiredKeys.contains(metadataKey))) {
      throw const BookCreationStorageUnconfirmed();
    }
    if (before != null) {
      final actual = BookCreationAttempt.decode(before);
      _identity(actual);
      if (expected == null && actual.fingerprint != value.fingerprint) {
        throw const BookCreationStorageUnconfirmed();
      }
      if (value.state == BookAttemptState.pending &&
          actual.state != BookAttemptState.pending) {
        throw const BookCreationStorageUnconfirmed();
      }
      if (actual.fingerprint != value.fingerprint &&
          actual.fingerprint != expected?.fingerprint) {
        throw const BookCreationStorageUnconfirmed();
      }
    }
    await writeValue(metadataKey, raw);
    guard();
    await flush();
    guard();
    final observed = await readValue(metadataKey);
    guard();
    if (observed != raw) throw const BookCreationStorageUnconfirmed();
  });
  Future<void> clearKnown(BookCreationAttempt expected) => _ordered(() async {
    _identity(expected);
    if (expected.state != BookAttemptState.knownID) {
      throw StateError('Unknown create record must be retained');
    }
    final raw = await readValue(metadataKey);
    guard();
    if (raw != null && raw != expected.encode()) {
      throw const BookCreationStorageUnconfirmed();
    }
    // Tombstone before deletion also prevents same-process late initial writers.
    // Root must never reuse attempt keys, including after a cold restart.
    _retiredKeys.add(metadataKey);
    if (raw != null) {
      await deleteValue(metadataKey);
      guard();
    }
    await flush();
    guard();
    if (await readValue(metadataKey) != null) {
      throw const BookCreationStorageUnconfirmed();
    }
    guard();
  });
}
