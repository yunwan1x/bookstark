// Prepared scratch only. Pure data; no body/password/token fields.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/books_repository.dart';

enum BookAttemptState { pending, submittedUnknown, knownID }

enum BookIDOrigin { postReceipt, manualExisting }

void _unicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid book Unicode');
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw const FormatException('Invalid book Unicode');
    }
  }
}

void validateBookRecoveryText(String value) => _unicode(value);

void _keys(Map row, Set<String> expected) {
  if (row.length != expected.length ||
      row.keys.any((key) => key is! String || !expected.contains(key))) {
    throw const FormatException('Unknown or missing book creation field');
  }
}

class BookCreationScope {
  BookCreationScope({
    required this.server,
    required this.memberId,
    required this.binding,
  }) {
    final uri = Uri.parse(server);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        server.endsWith('/') ||
        uri.toString() != server ||
        memberId <= 0 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(binding)) {
      throw const FormatException('Invalid book creation owner');
    }
  }
  final String server, binding;
  final int memberId;
  Map<String, Object?> toJson() => {
    'server': server,
    'member_id': memberId,
    'binding': binding,
  };
  String get identity => jsonEncode(toJson());
  factory BookCreationScope.fromJson(Map row) {
    _keys(row, {'server', 'member_id', 'binding'});
    if (row['server'] is! String ||
        row['member_id'] is! int ||
        row['binding'] is! String) {
      throw const FormatException('Invalid book creation owner');
    }
    return BookCreationScope(
      server: row['server'] as String,
      memberId: row['member_id'] as int,
      binding: row['binding'] as String,
    );
  }
}

class BookCreationInput {
  BookCreationInput({
    required this.name,
    required this.description,
    required List<String> labels,
  }) : labels = List.unmodifiable(labels) {
    _unicode(name);
    _unicode(description);
    for (final value in labels) {
      _unicode(value);
    }
    if (labels.length > 100 ||
        labels.toSet().length != labels.length ||
        utf8.encode(jsonEncode(labels)).length > 96 * 1024) {
      throw const FormatException('Invalid exact book labels');
    }
    // Existing byte/legacy label encoding validation. Do not trim/dedup here.
    toBook().writeBody();
  }
  final String name, description;
  final List<String> labels;
  BookItem toBook() =>
      BookItem(name: name, description: description, labels: labels);
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'labels': labels,
  };
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  factory BookCreationInput.fromJson(Map row) {
    _keys(row, {'name', 'description', 'labels'});
    if (row['name'] is! String ||
        row['description'] is! String ||
        row['labels'] is! List ||
        (row['labels'] as List).any((x) => x is! String)) {
      throw const FormatException('Invalid book creation input');
    }
    return BookCreationInput(
      name: row['name'] as String,
      description: row['description'] as String,
      labels: (row['labels'] as List).cast<String>(),
    );
  }
}

class BookCreationAttempt {
  BookCreationAttempt({
    required this.key,
    required this.scope,
    required this.input,
    required this.state,
    this.submitBoundaryArmed = false,
    this.knownID,
    this.origin,
    this.labelsNeedReview = false,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        state == BookAttemptState.pending && submitBoundaryArmed ||
        state == BookAttemptState.knownID &&
            (knownID == null || knownID! <= 0 || origin == null) ||
        state != BookAttemptState.knownID &&
            (knownID != null || origin != null || labelsNeedReview)) {
      throw const FormatException('Invalid book creation state');
    }
  }
  final String key;
  final BookCreationScope scope;
  final BookCreationInput input;
  final BookAttemptState state;
  final bool submitBoundaryArmed, labelsNeedReview;
  final int? knownID;
  final BookIDOrigin? origin;
  BookCreationAttempt unknown() => BookCreationAttempt(
    key: key,
    scope: scope,
    input: input,
    state: BookAttemptState.submittedUnknown,
    submitBoundaryArmed: true,
  );
  BookCreationAttempt known(int id, BookIDOrigin source) => BookCreationAttempt(
    key: key,
    scope: scope,
    input: input,
    state: BookAttemptState.knownID,
    submitBoundaryArmed: submitBoundaryArmed,
    knownID: id,
    origin: source,
    labelsNeedReview: source == BookIDOrigin.postReceipt,
  );
  BookCreationAttempt pending() => BookCreationAttempt(
    key: key,
    scope: scope,
    input: input,
    state: BookAttemptState.pending,
  );
  String encode() => jsonEncode({
    'schema': 1,
    'kind': 'book',
    'attempt_key': key,
    'scope': scope.toJson(),
    'state': state.name,
    'input': input.toJson(),
    'input_sha256': input.digest,
    'submit_boundary_armed': submitBoundaryArmed,
    'known_id': knownID,
    'origin': origin?.name,
    'labels_need_review': labelsNeedReview,
  });
  String get fingerprint => sha256.convert(utf8.encode(encode())).toString();
  factory BookCreationAttempt.decode(String value) {
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Book record exceeds bound');
    }
    final row = jsonDecode(value);
    if (row is! Map) throw const FormatException('Invalid book record');
    _keys(row, {
      'schema',
      'kind',
      'attempt_key',
      'scope',
      'state',
      'input',
      'input_sha256',
      'submit_boundary_armed',
      'known_id',
      'origin',
      'labels_need_review',
    });
    if (row['schema'] is! int ||
        row['schema'] != 1 ||
        row['kind'] != 'book' ||
        row['scope'] is! Map ||
        row['input'] is! Map ||
        row['attempt_key'] is! String ||
        row['submit_boundary_armed'] is! bool ||
        row['labels_need_review'] is! bool ||
        row['known_id'] != null && row['known_id'] is! int) {
      throw const FormatException('Invalid book record schema');
    }
    final input = BookCreationInput.fromJson(row['input'] as Map);
    if (row['input_sha256'] != input.digest) {
      throw const FormatException('Book input changed');
    }
    final states = BookAttemptState.values
        .where((s) => s.name == row['state'])
        .toList();
    final origins = BookIDOrigin.values
        .where((s) => s.name == row['origin'])
        .toList();
    if (states.length != 1 || row['origin'] != null && origins.length != 1) {
      throw const FormatException('Unknown book record state');
    }
    return BookCreationAttempt(
      key: row['attempt_key'] as String,
      scope: BookCreationScope.fromJson(row['scope'] as Map),
      input: input,
      state: states.single,
      submitBoundaryArmed: row['submit_boundary_armed'] as bool,
      knownID: row['known_id'] as int?,
      origin: origins.isEmpty ? null : origins.single,
      labelsNeedReview: row['labels_need_review'] as bool,
    );
  }
}
