import 'package:bookstark_flutter/core/books_repository.dart';
import 'book_creation_attempt.dart';

class BookCreateNotSubmitted implements Exception {
  const BookCreateNotSubmitted();
}

class BookCreateReceipt {
  BookCreateReceipt(this.id) {
    if (id <= 0) {
      throw const FormatException('Actual positive book ID receipt required');
    }
  }
  final int id;
}

/// Root implements exact boundary AFTER auth/CSRF/body preparation, immediately
/// BEFORE one actual POST /api/books. It MUST await onSubmit before sending.
/// If onSubmit throws, no POST may run. No auto retry, no follow-up label PUT/GET
/// that could obscure a received positive ID. Legacy BooksRepository.save cannot
/// satisfy this exact boundary and is deliberately NOT adapted by pretending.
abstract interface class BookCreationTransport {
  Future<BookCreateReceipt> create(
    BookCreationInput input, {
    required Future<void> Function() onSubmit,
  });

  /// Current authenticated owner read-only requests only. Validate the strict
  /// raw book envelope AND independently successful labels GET, bracketed by
  /// fresh source verification. Old repository.read labelsLoaded is insufficient
  /// because missing/error labels can become an apparently empty list.
  /// No writes, list/name inference, or partial detail accepted.
  Future<BookItem> readExisting(int id);
}

class PreparedBookCreationPost {
  PreparedBookCreationPost({
    required this.uri,
    required this.inputDigest,
    required this.ownerIdentity,
    required this._send,
  });
  final Uri uri;
  final String inputDigest, ownerIdentity;
  final Future<BookCreateReceipt> Function() _send;
  bool _used = false;
  Future<BookCreateReceipt> sendOnce() {
    if (_used) throw StateError('Prepared book POST cannot be replayed');
    _used = true;
    return _send();
  }
}

/// Narrow adapter Root can bind to prepared API request internals without
/// copying api_client.dart. prepare MUST finish auth/CSRF/serialization and
/// MUST NOT send the POST. Its send closure sends that same fixed prepared
/// request once, returns the positive-ID receipt immediately, with no labels PUT.
class ExactBookCreationTransport implements BookCreationTransport {
  ExactBookCreationTransport({
    required this.scope,
    required this.prepare,
    required this.read,
    required this.isCurrent,
  });
  final BookCreationScope scope;
  final Future<PreparedBookCreationPost> Function(BookCreationInput input)
  prepare;
  final Future<BookItem> Function(int id) read;
  final bool Function() isCurrent;
  void _current() {
    if (!isCurrent()) throw const BookCreateNotSubmitted();
  }

  @override
  Future<BookCreateReceipt> create(
    BookCreationInput input, {
    required Future<void> Function() onSubmit,
  }) async {
    _current();
    final prepared = await prepare(input);
    _current();
    final base = Uri.parse(scope.server);
    final expected = base.replace(path: '${base.path}/api/books');
    if (prepared.uri != expected ||
        prepared.ownerIdentity != scope.identity ||
        prepared.inputDigest != input.digest) {
      throw const BookCreateNotSubmitted();
    }
    await onSubmit();
    _current();
    return prepared.sendOnce();
  }

  @override
  Future<BookItem> readExisting(int id) async {
    _current();
    if (id <= 0) {
      throw const FormatException('Positive existing book ID required');
    }
    final actual = await read(id);
    _current();
    if (actual.id != id) {
      throw const FormatException('Existing book ID mismatch');
    }
    return actual;
  }
}
