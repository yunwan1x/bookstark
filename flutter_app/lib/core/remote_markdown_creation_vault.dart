import 'document_excerpt_origin.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

String creationDigest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
void _unicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Malformed Unicode');
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw const FormatException('Malformed Unicode');
    }
  }
}

class MarkdownCreationScope {
  MarkdownCreationScope({
    required Uri server,
    required this.memberId,
    required this.collection,
  }) : server = BookstarkClient.normalizeServer(server.toString()) {
    if (memberId <= 0 || !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Owned Markdown scope required');
    }
  }
  final Uri server;
  final int memberId;
  final String collection;
  String get namespace =>
      jsonEncode([server.toString(), memberId, collection, 'markdown', 'new']);
}

class MarkdownCreationInput {
  MarkdownCreationInput({
    required this.title,
    required this.content,
    required List<String> labels,
  }) : labels = List.unmodifiable(labels) {
    for (final value in [title, content, ...labels]) {
      _unicode(value);
    }
    if (utf8.encode(title).length > 200 ||
        utf8.encode(content).length > 4 * 1024 * 1024 ||
        labels.length > 100 ||
        labels.toSet().length != labels.length ||
        labels.any((v) => v.isEmpty) ||
        utf8.encode(jsonEncode(labels)).length > 60 * 1024) {
      throw const FormatException('Markdown snapshot exceeds bounds');
    }
  }
  final String title, content;
  final List<String> labels;
  Map<String, Object?> toJson() => {
    'title': title,
    'content': content,
    'labels': labels,
  };
  String get fingerprint => creationDigest(toJson());
  bool matches(MarkdownCreationInput other) =>
      title == other.title &&
      content == other.content &&
      labels.length == other.labels.length &&
      labels.toSet().containsAll(other.labels);
  factory MarkdownCreationInput.parse(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        value.keys.toSet().difference({
          'title',
          'content',
          'labels',
        }).isNotEmpty ||
        value['title'] is! String ||
        value['content'] is! String ||
        value['labels'] is! List ||
        (value['labels'] as List).any((v) => v is! String)) {
      throw const FormatException('Invalid full Markdown snapshot');
    }
    return MarkdownCreationInput(
      title: value['title'] as String,
      content: value['content'] as String,
      labels: (value['labels'] as List).cast<String>(),
    );
  }
}

enum MarkdownKnownIDOrigin { postReceipt, manualExisting, unknownLegacy }

class MarkdownCreationRecord {
  MarkdownCreationRecord({
    required this.scope,
    required this.key,
    required this.input,
    required this.pending,
    this.knownId,
    this.knownIDOrigin = MarkdownKnownIDOrigin.unknownLegacy,
    this.excerptOrigin,
  }) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(key) ||
        knownId != null && (knownId! <= 0 || !pending) ||
        knownId == null &&
            knownIDOrigin != MarkdownKnownIDOrigin.unknownLegacy) {
      throw const FormatException('Invalid creation journal identity');
    }
  }
  factory MarkdownCreationRecord.fresh(
    MarkdownCreationScope scope,
    MarkdownCreationInput input, {
    DocumentExcerptOrigin? excerptOrigin,
  }) => MarkdownCreationRecord(
    scope: scope,
    input: input,
    excerptOrigin: excerptOrigin,
    pending: false,
    key: List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
  );
  final MarkdownCreationScope scope;
  final String key;
  final MarkdownCreationInput input;
  final bool pending;
  final int? knownId;
  final MarkdownKnownIDOrigin knownIDOrigin;
  final DocumentExcerptOrigin? excerptOrigin;
  MarkdownCreationRecord copy({
    MarkdownCreationInput? input,
    bool? pending,
    int? knownId,
    MarkdownKnownIDOrigin? knownIDOrigin,
  }) => MarkdownCreationRecord(
    scope: scope,
    key: key,
    input: input ?? this.input,
    pending: pending ?? this.pending,
    knownId: knownId ?? this.knownId,
    knownIDOrigin: knownIDOrigin ?? this.knownIDOrigin,
    excerptOrigin: excerptOrigin,
  );
  Map<String, Object?> toJson() => {
    'schema': 1,
    'scope': scope.namespace,
    'format': 'markdown',
    'key': key,
    'input': input.toJson(),
    'input_hash': input.fingerprint,
    'pending': pending,
    'known_id': knownId,
    'known_id_origin': knownIDOrigin.name,
    if (excerptOrigin != null) 'excerpt_origin': excerptOrigin!.toJson(),
  };
  String get fingerprint => creationDigest(toJson());
  factory MarkdownCreationRecord.parse(
    Object? value,
    MarkdownCreationScope scope,
  ) {
    const keys = {
      'schema',
      'scope',
      'format',
      'key',
      'input',
      'input_hash',
      'pending',
      'known_id',
      'known_id_origin',
      'excerpt_origin',
    };
    if (value is! Map ||
        (value.length < keys.length - 2 || value.length > keys.length) ||
        keys.difference(value.keys.toSet()).difference({
          'known_id_origin',
          'excerpt_origin',
        }).isNotEmpty ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value['schema'] != 1 ||
        value['scope'] != scope.namespace ||
        value['format'] != 'markdown' ||
        value['key'] is! String ||
        value['pending'] is! bool ||
        value['known_id'] != null && value['known_id'] is! int ||
        value.containsKey('known_id_origin') &&
            !MarkdownKnownIDOrigin.values.any(
              (v) => v.name == value['known_id_origin'],
            )) {
      throw const FormatException('Invalid scoped creation journal');
    }
    final input = MarkdownCreationInput.parse(value['input']);
    if (input.fingerprint != value['input_hash']) {
      throw const FormatException('Draft digest mismatch');
    }
    return MarkdownCreationRecord(
      scope: scope,
      key: value['key'] as String,
      input: input,
      pending: value['pending'] as bool,
      knownId: value['known_id'] as int?,
      excerptOrigin: value.containsKey('excerpt_origin')
          ? DocumentExcerptOrigin.parse(value['excerpt_origin'])
          : null,
      knownIDOrigin: value.containsKey('known_id_origin')
          ? MarkdownKnownIDOrigin.values.singleWhere(
              (v) => v.name == value['known_id_origin'],
            )
          : MarkdownKnownIDOrigin.unknownLegacy,
    );
  }
}

/// Native callers inject encrypted storage and NativeRecoveryStorage.flush.
/// No platform secrets, bodies or passwords are logged by this module.
class RemoteMarkdownCreationVault extends SecureRecordStore {
  RemoteMarkdownCreationVault({
    required this.scope,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
    required this.flush,
  }) : super(
         prefix: 'bookstark.markdown-create.v1',
         namespace: scope.namespace,
       );
  final MarkdownCreationScope scope;
  final Future<void> Function() flush;
  static final _queues = <String, Future<void>>{};
  Future<T> _serial<T>(Future<T> Function() work) {
    final key = namespace;
    final result = (_queues[key] ?? Future<void>.value()).then((_) => work());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[key], tail)) _queues.remove(key);
      }),
    );
    return result;
  }

  Future<MarkdownCreationRecord?> _read() async {
    final raw = await readRecord('new');
    if (raw == null) return null;
    if (utf8.encode(raw).length > 32 * 1024 * 1024) {
      throw const FormatException('Oversized journal');
    }
    return MarkdownCreationRecord.parse(jsonDecode(raw), scope);
  }

  Future<MarkdownCreationRecord?> read() => _serial(_read);
  Future<void> compareAndWrite(
    MarkdownCreationRecord? expected,
    MarkdownCreationRecord next, {
    required void Function() guard,
  }) => _serial(() async {
    guard();
    if (next.scope.namespace != namespace) throw StateError('Scope mismatch');
    final before = await _read();
    guard();
    if (before?.fingerprint != expected?.fingerprint) {
      throw StateError('Creation journal changed');
    }
    await writeRecord('new', jsonEncode(next.toJson()));
    guard();
    await flush();
    guard();
    final actual = await _read();
    guard();
    if (actual?.fingerprint != next.fingerprint) {
      throw StateError('Journal readback failed');
    }
  });
  Future<void> compareAndRemove(
    MarkdownCreationRecord expected, {
    required void Function() guard,
  }) => _serial(() async {
    guard();
    final before = await _read();
    guard();
    if (before?.fingerprint != expected.fingerprint) {
      throw StateError('Creation journal changed');
    }
    try {
      await removeRecord('new');
      guard();
      await flush();
      guard();
      final actual = await _read();
      guard();
      if (actual != null) throw StateError('Cleanup readback failed');
    } catch (_) {
      // Restore an applied delete with a lost acknowledgement where possible.
      // Guard prevents resurrecting records after logout. Permanent storage
      // failure remains unknown; caller must not report success.
      guard();
      final actual = await _read();
      guard();
      if (actual == null) {
        await writeRecord('new', jsonEncode(expected.toJson()));
        guard();
        await flush();
        guard();
        final restored = await _read();
        guard();
        if (restored?.fingerprint != expected.fingerprint) {
          throw StateError('Cleanup restoration unknown');
        }
      }
      rethrow;
    }
  });
}
