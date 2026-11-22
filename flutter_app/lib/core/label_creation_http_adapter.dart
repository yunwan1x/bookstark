import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'label_creation_attempt.dart';
import 'label_creation_controller.dart';

class LabelCreationHttpAdapter {
  LabelCreationHttpAdapter({
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
      throw StateError('Label creation initiating scope retired');
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
      throw const FormatException('Global label metadata unavailable');
    }
    return Map<String, Object?>.from(root['data'] as Map);
  }

  Future<void> _actor() async {
    guard();
    final actor = _data(
      await client.boundedCurrentOwnerJson(
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      ),
    );
    guard();
    if (memberId <= 0 || actor['member_id'] != memberId) {
      throw const FormatException('Label initiating account differs');
    }
  }

  void _identity(LabelCreationAttempt a) {
    guard();
    if (a.scope != scope) {
      throw const FormatException('Label creation scope differs');
    }
  }

  Future<PreparedAuthenticatedJsonRequest> prepare(
    LabelCreationAttempt a,
  ) async {
    _identity(a);
    await _actor();
    _identity(a);
    final request = await client.prepareLabelCreationJson(
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

  Future<LabelCreationReview> inspect(LabelCreationAttempt a, int id) async {
    _identity(a);
    if (id <= 0) throw const FormatException('Actual global label ID required');
    await _actor();
    _identity(a);
    final row = _data(
      await client.readLabelCreationReviewJson(
        id,
        expectedSessionRevision: revision,
        ownerGuard: guard,
        abortTrigger: _abort.future,
      ),
    );
    _identity(a);
    const fields = {
      'label_id',
      'label_name',
      'book_count',
      'blog_count',
      'bookmark_count',
      'document_count',
      'relation_count',
      'relations',
    };
    if (row.length != fields.length ||
        !row.keys.toSet().containsAll(fields) ||
        row['label_id'] != id ||
        row['label_name'] is! String ||
        row['relations'] is! List ||
        (row['relations'] as List).length > 500) {
      throw const FormatException(
        'Complete bounded global label metadata required',
      );
    }
    // No resource member_id exists: current profile identifies the initiator only.
    LabelCreationAttempt(
      scope: scope,
      key: a.key,
      body: {'label_name': row['label_name']},
    );
    final counts = {'book': 0, 'blog': 0, 'bookmark': 0, 'document': 0};
    final relations = <Map<String, Object?>>[];
    var previous = 0;
    for (final value in row['relations'] as List) {
      if (value is! Map) {
        throw const FormatException('Complete relation identity required');
      }
      final r = Map<String, Object?>.from(value);
      if (r.length != 4 ||
          !r.keys.toSet().containsAll({
            'id',
            'resource_id',
            'relation_type',
            'created_at',
          }) ||
          r['id'] is! int ||
          (r['id'] as int) <= previous ||
          r['resource_id'] is! int ||
          (r['resource_id'] as int) <= 0 ||
          !counts.containsKey(r['relation_type']) ||
          r['created_at'] is! String ||
          (r['created_at'] as String).length > 64 ||
          DateTime.tryParse(r['created_at'] as String) == null) {
        throw const FormatException(
          'Invalid bounded complete relation metadata',
        );
      }
      previous = r['id'] as int;
      final type = r['relation_type'] as String;
      counts[type] = counts[type]! + 1;
      relations.add({
        'id': r['id'],
        'resource_id': r['resource_id'],
        'relation_type': type,
        'created_at': r['created_at'],
      });
    }
    if (row['relation_count'] != relations.length) {
      throw const FormatException(
        'Truncated relation metadata is not reviewable',
      );
    }
    for (final entry in counts.entries) {
      if (row['${entry.key}_count'] != entry.value) {
        throw const FormatException('Inconsistent actual relation count');
      }
    }
    final keys = row.keys.toList()..sort();
    final canonical = {
      for (final key in keys) key: key == 'relations' ? relations : row[key],
    };
    return LabelCreationReview(
      id: id,
      fingerprint: sha256
          .convert(utf8.encode(jsonEncode(canonical)))
          .toString(),
      display: const JsonEncoder.withIndent('  ').convert(canonical),
      matchesFrozenInput: row['label_name'] == a.body['label_name'],
      wire: Map.unmodifiable(canonical),
    );
  }
}
