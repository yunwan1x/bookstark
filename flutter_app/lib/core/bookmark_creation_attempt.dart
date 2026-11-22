import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_json.dart';

enum BookmarkCreationPhase { pending, unknown, knownID }

/// Exact frozen creation input; URL is not a receipt or the attempt identity.
class BookmarkCreationAttempt {
  BookmarkCreationAttempt({
    required this.scope,
    required this.key,
    required Map<String, Object?> body,
    this.phase = BookmarkCreationPhase.pending,
    this.actualId,
  }) : body = Map.unmodifiable({
         ...body,
         'labels': List<String>.unmodifiable(
           (body['labels'] as List).cast<String>(),
         ),
       }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        (phase == BookmarkCreationPhase.knownID
            ? (actualId ?? 0) <= 0
            : actualId != null)) {
      throw const FormatException('Invalid bookmark creation identity');
    }
    const fields = {
      'title',
      'url',
      'description',
      'favicon',
      'is_public',
      'labels',
    };
    if (body.length != fields.length ||
        !body.keys.toSet().containsAll(fields) ||
        body['is_public'] is! bool ||
        body['labels'] is! List) {
      throw const FormatException('Invalid frozen bookmark fields');
    }
    const limits = {
      'title': 500,
      'url': 2048,
      'description': 2000,
      'favicon': 4096,
    };
    for (final entry in limits.entries) {
      final value = body[entry.key];
      if (value is! String) {
        throw const FormatException('Bookmark text required');
      }
      _unicode(value);
      if (utf8.encode(value).length > entry.value) {
        throw const FormatException('Bookmark field exceeds byte budget');
      }
    }
    if ((body['title'] as String).trim().isEmpty) {
      throw const FormatException('Bookmark title required');
    }
    final url = body['url'] as String,
        uri = Uri.tryParse(body['url'] as String);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(url)) {
      throw const FormatException('Invalid bookmark URL');
    }
    try {
      if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
        throw const FormatException('Invalid port');
      }
    } on FormatException {
      rethrow;
    }
    final labels = body['labels'] as List;
    if (labels.length > 100 || labels.any((v) => v is! String)) {
      throw const FormatException('Invalid exact labels');
    }
    var total = 0;
    final unique = <String>{};
    for (final label in labels.cast<String>()) {
      _unicode(label);
      final bytes = utf8.encode(label).length;
      total += bytes;
      if (bytes > 4096 || total > 65536 || !unique.add(label)) {
        throw const FormatException('Invalid exact label budget or duplicate');
      }
    }
    if (utf8.encode(jsonEncode(this.body)).length > 512 * 1024) {
      throw const FormatException('Bookmark input exceeds byte budget');
    }
  }
  static void _unicode(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        if (i + 1 >= value.length) {
          throw const FormatException('Invalid Unicode');
        }
        final low = value.codeUnitAt(++i);
        if (low < 0xdc00 || low > 0xdfff) {
          throw const FormatException('Invalid Unicode');
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        throw const FormatException('Invalid Unicode');
      }
    }
  }

  final String scope, key;
  final Map<String, Object?> body;
  final BookmarkCreationPhase phase;
  final int? actualId;
  String get inputDigest =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();
  String get path => '/api/bookmarks/create-owned';
  BookmarkCreationAttempt next(BookmarkCreationPhase value, [int? id]) =>
      BookmarkCreationAttempt(
        scope: scope,
        key: key,
        body: body,
        phase: value,
        actualId: id,
      );
  String encode() => jsonEncode({
    'version': 1,
    'scope': scope,
    'key': key,
    'body': body,
    'phase': phase.name,
    'actualId': actualId,
  });
  static BookmarkCreationAttempt decode(String raw) {
    if (raw.length > 768 * 1024 || utf8.encode(raw).length > 768 * 1024) {
      throw const FormatException('Bounded bookmark creation record required');
    }
    _unicode(raw);
    final r = decodeLegacyJson(
      utf8.encode(raw),
      limits: const LegacyJsonLimits(
        maxBytes: 768 * 1024,
        maxStringBytes: 65536,
        maxEncodedStringCharacters: 768 * 1024,
        maxDepth: 8,
        maxNodes: 1024,
        maxObjectMembers: 16,
        maxArrayLength: 100,
      ),
    );
    const fields = {'version', 'scope', 'key', 'body', 'phase', 'actualId'};
    if (r is! Map ||
        r.length != fields.length ||
        !r.keys.toSet().containsAll(fields) ||
        r['version'] != 1) {
      throw const FormatException('Invalid bookmark creation record');
    }
    return BookmarkCreationAttempt(
      scope: r['scope'] as String,
      key: r['key'] as String,
      body: Map<String, Object?>.from(r['body'] as Map),
      phase: BookmarkCreationPhase.values.byName(r['phase'] as String),
      actualId: r['actualId'] as int?,
    );
  }
}
