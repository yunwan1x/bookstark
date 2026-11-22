import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'bookmark_creation_attempt.dart';
import 'bookmark_creation_controller.dart';

class BookmarkCreationHttpAdapter {
  BookmarkCreationHttpAdapter({
    required this.client,
    required this.memberId,
    required String namespace,
    required this.isCurrent,
  }) : revision = client.sessionRevision,
       scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([client.baseUri.toString(), memberId, namespace]),
             ),
           )
           .toString();
  final BookstarkClient client;
  final int memberId, revision;
  final String scope;
  final bool Function() isCurrent;
  final _abort = Completer<void>();
  bool _closed = false;
  void guard() {
    if (_closed || !isCurrent() || client.sessionRevision != revision) {
      throw StateError('Bookmark creation owner retired');
    }
  }

  void retire() {
    if (!_closed) {
      _closed = true;
      _abort.complete();
    }
  }

  Map<String, Object?> _data(Map<String, Object?> root) {
    if (root['code'] != 0 || root['data'] is! Map) {
      throw const FormatException('Owned bookmark unavailable');
    }
    return Map<String, Object?>.from(root['data'] as Map);
  }

  Future<void> _owner() async {
    guard();
    final profile = _data(
      await client.boundedCurrentOwnerJson(
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (memberId <= 0 || profile['member_id'] != memberId) {
      throw const FormatException('Bookmark owner differs');
    }
  }

  void _identity(BookmarkCreationAttempt a) {
    guard();
    if (a.scope != scope) {
      throw const FormatException('Bookmark creation scope differs');
    }
  }

  Future<PreparedAuthenticatedJsonRequest> prepare(
    BookmarkCreationAttempt a,
  ) async {
    _identity(a);
    await _owner();
    _identity(a);
    final request = await client.prepareBookmarkCreationJson(
      a.body,
      expectedSessionRevision: revision,
      ownerGuard: guard,
      abortTrigger: _abort.future,
    );
    try {
      _identity(a);
      return request;
    } catch (_) {
      request.retire();
      rethrow;
    }
  }

  /// Read-only duplicate detection, never an acknowledgement for this attempt.
  Future<Map<String, Object?>?> checkURL(String url) async {
    await _owner();
    guard();
    final result = _data(
      await client.checkBookmarkCreationURLJson(
        url,
        expectedSessionRevision: revision,
        ownerGuard: guard,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (result.length != 2 ||
        result['found'] is! bool ||
        !result.keys.toSet().containsAll({'found', 'bookmark'})) {
      throw const FormatException('Complete duplicate check required');
    }
    if (result['found'] == false) {
      if (result['bookmark'] != null) {
        throw const FormatException('Inconsistent duplicate check');
      }
      return null;
    }
    if (result['bookmark'] is! Map) {
      throw const FormatException('Actual duplicate missing');
    }
    final row = Map<String, Object?>.from(result['bookmark'] as Map);
    _validate(row);
    if (row['url'] != url) throw const FormatException('Duplicate URL differs');
    return Map.unmodifiable(row);
  }

  void _validate(Map<String, Object?> row) {
    const fields = {
      'bookmark_id',
      'title',
      'url',
      'description',
      'favicon',
      'order_sort',
      'label',
      'labels',
      'member_id',
      'is_public',
      'is_pinned',
      'nav_visible',
      'create_time',
      'modify_time',
    };
    if (row.length != fields.length ||
        !row.keys.toSet().containsAll(fields) ||
        row['bookmark_id'] is! int ||
        (row['bookmark_id'] as int) <= 0 ||
        row['member_id'] != memberId ||
        row['order_sort'] is! int ||
        row['is_public'] is! bool ||
        row['is_pinned'] is! bool ||
        row['nav_visible'] is! bool ||
        row['label'] is! String ||
        utf8.encode(row['label'] as String).length > 65536 + 100) {
      throw const FormatException('Complete actual bookmark metadata required');
    }
    for (final field in ['create_time', 'modify_time']) {
      if (row[field] is! String ||
          DateTime.tryParse(row[field] as String) == null) {
        throw const FormatException('Actual bookmark version unavailable');
      }
    }
    // Reuse identical byte/Unicode/URL/label bounds without pretending ID or URL proves creation.
    BookmarkCreationAttempt(
      scope: scope,
      key: List.filled(32, '0').join(),
      body: {
        for (final key in [
          'title',
          'url',
          'description',
          'favicon',
          'is_public',
          'labels',
        ])
          key: row[key],
      },
    );
  }

  Future<BookmarkCreationReview> inspect(
    BookmarkCreationAttempt a,
    int id,
  ) async {
    _identity(a);
    if (id <= 0) throw const FormatException('Actual bookmark ID required');
    await _owner();
    _identity(a);
    final row = _data(
      await client.readBookmarkCreationReviewJson(
        id,
        expectedSessionRevision: revision,
        ownerGuard: guard,
        abortTrigger: _abort.future,
      ),
    );
    _identity(a);
    _validate(row);
    if (row['bookmark_id'] != id) {
      throw const FormatException('Actual bookmark ID differs');
    }
    final actualLabels = (row['labels'] as List).cast<String>().toSet(),
        frozenLabels = (a.body['labels'] as List).cast<String>().toSet();
    final matches =
        [
          'title',
          'url',
          'description',
          'is_public',
        ].every((k) => row[k] == a.body[k]) &&
        ((a.body['favicon'] as String).isEmpty ||
            row['favicon'] == a.body['favicon']) &&
        actualLabels.length == frozenLabels.length &&
        actualLabels.containsAll(frozenLabels);
    final keys = row.keys.toList()..sort();
    // Relation iteration order is not metadata identity; exact names remain unchanged.
    final labels = actualLabels.toList()..sort();
    final canonical = {
      for (final key in keys) key: key == 'labels' ? labels : row[key],
    };
    return BookmarkCreationReview(
      id: id,
      fingerprint: sha256
          .convert(utf8.encode(jsonEncode(canonical)))
          .toString(),
      display: const JsonEncoder.withIndent('  ').convert(row),
      matchesFrozenInput: matches,
      wire: Map.unmodifiable(row),
    );
  }
}
