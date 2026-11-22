import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'book_creation_attempt.dart';
import 'book_creation_transport.dart';

class BookCreationHttpAdapter {
  BookCreationHttpAdapter({
    required this.client,
    required this.scope,
    required this.isCurrent,
  }) : revision = client.sessionRevision,
       _token = client.exportSession()['token'] {
    if (client.baseUri.toString() != scope.server) {
      throw const FormatException('Book server scope mismatch');
    }
  }
  final BookstarkClient client;
  final BookCreationScope scope;
  final bool Function() isCurrent;
  final int revision;
  final String? _token;
  final _abort = Completer<void>();
  bool _closed = false;
  void guard() {
    if (_closed ||
        !isCurrent() ||
        client.sessionRevision != revision ||
        _token == null ||
        _token.isEmpty ||
        client.exportSession()['token'] != _token) {
      throw StateError('Book owner retired');
    }
  }

  void retire() {
    if (_closed) return;
    _closed = true;
    _abort.complete();
  }

  ExactBookCreationTransport get transport => ExactBookCreationTransport(
    scope: scope,
    prepare: prepare,
    read: readExisting,
    isCurrent: () =>
        !_closed &&
        isCurrent() &&
        client.sessionRevision == revision &&
        _token != null &&
        _token.isNotEmpty &&
        client.exportSession()['token'] == _token,
  );
  Map _data(Map<String, Object?> root) {
    if (root['code'] != 0 || root['data'] is! Map) {
      throw const FormatException('Book metadata unavailable');
    }
    return root['data'] as Map;
  }

  Future<void> _owner() async {
    guard();
    final row = _data(
      await client.boundedCurrentOwnerJson(
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (row['member_id'] is! int || row['member_id'] != scope.memberId) {
      throw const FormatException('Book owner mismatch');
    }
  }

  Future<PreparedBookCreationPost> prepare(BookCreationInput input) async {
    guard();
    await _owner();
    guard();
    final prepared = await client.prepareBookCreateJson(
      input.toBook().writeBody(),
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    guard();
    return PreparedBookCreationPost(
      uri: prepared.uri,
      inputDigest: input.digest,
      ownerIdentity: scope.identity,
      send: () async {
        guard();
        final row = _data(await prepared.sendOnce());
        guard();
        if (row['book_id'] is! int ||
            (row['book_id'] as int) <= 0 ||
            row['member_id'] is! int ||
            row['member_id'] != scope.memberId ||
            row['book_name'] != input.name ||
            row['description'] != input.description ||
            row['identify'] is! String ||
            (row['identify'] as String).isEmpty) {
          throw const FormatException('Book receipt mismatch');
        }
        return BookCreateReceipt(row['book_id'] as int);
      },
    );
  }

  Map<String, Object?> _metadata(Map row, int id) {
    if (row['book_id'] is! int ||
        row['book_id'] != id ||
        row['member_id'] is! int ||
        row['member_id'] != scope.memberId ||
        row['book_name'] is! String ||
        row['description'] is! String ||
        row['identify'] is! String ||
        (row['identify'] as String).isEmpty ||
        row['doc_count'] is! int ||
        (row['doc_count'] as int) < 0 ||
        row['modify_time'] != null && row['modify_time'] is! String) {
      throw const FormatException('Owned full book metadata required');
    }
    for (final key in ['book_name', 'description', 'identify']) {
      validateBookRecoveryText(row[key] as String);
    }
    return {
      'book_id': id,
      'member_id': row['member_id'],
      'book_name': row['book_name'],
      'description': row['description'],
      'identify': row['identify'],
      'doc_count': row['doc_count'],
      'modify_time': row['modify_time'],
    };
  }

  Future<List<String>> _labels(int id) async {
    guard();
    final root = await client.boundedBookLabelsJson(
      id,
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    guard();
    if (root['code'] != 0 || !root.containsKey('data')) {
      throw const FormatException('Book labels unavailable');
    }
    final data = root['data'];
    if (data == null) return const [];
    if (data is! List || data.length > 100 || data.any((v) => v is! String)) {
      throw const FormatException('Book labels unavailable');
    }
    final values = List<String>.unmodifiable(data.cast<String>());
    for (final value in values) {
      validateBookRecoveryText(value);
    }
    if (utf8.encode(jsonEncode(values)).length > 96 * 1024) {
      throw const FormatException('Book labels exceed bound');
    }
    return values;
  }

  Future<BookItem> readExisting(int id) async {
    guard();
    if (id <= 0) throw const FormatException('Positive book ID required');
    await _owner();
    final before = _metadata(
      _data(
        await client.boundedBookDetailJson(
          id,
          expectedSessionRevision: revision,
          abortTrigger: _abort.future,
        ),
      ),
      id,
    );
    guard();
    final labels1 = await _labels(id);
    final labels2 = await _labels(id);
    final after = _metadata(
      _data(
        await client.boundedBookDetailJson(
          id,
          expectedSessionRevision: revision,
          abortTrigger: _abort.future,
        ),
      ),
      id,
    );
    guard();
    if (jsonEncode(before) != jsonEncode(after) ||
        jsonEncode(labels1) != jsonEncode(labels2)) {
      throw const FormatException('Book changed during review');
    }
    final rawTime = after['modify_time'];
    final modified = rawTime == null
        ? null
        : DateTime.tryParse(rawTime as String);
    if (rawTime != null && modified == null) {
      throw const FormatException('Book version timestamp unavailable');
    }
    return BookItem(
      id: id,
      name: after['book_name'] as String,
      description: after['description'] as String,
      identify: after['identify'] as String,
      documentCount: after['doc_count'] as int,
      labels: labels2,
      labelsLoaded: true,
      modifiedAt: modified,
    );
  }
}
