import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/resource_labels.dart';

import 'remote_markdown_creation_controller.dart';
import 'remote_markdown_creation_vault.dart';

typedef MarkdownCreateJson =
    Future<Map<String, Object?>> Function(
      Map<String, Object?> body, {
      required void Function() onSubmit,
      required Future<void> abortTrigger,
    });
typedef MarkdownReadJson =
    Future<Map<String, Object?>> Function(
      int id, {
      required Future<void> abortTrigger,
    });

/// createJson = client.createMarkdownNoteJson; readFullJson =
/// client.boundedOwnedMarkdownJson; readLabelsJson =
/// client.boundedResourceLabelsJson (all return ORIGINAL root envelope).
/// These callbacks are mandatory because BookstarkClient.post has no precise
/// submission hook and generic get does not provide bounded Markdown reads.
/// Never wire createJson to client.post and call onSubmit before it: CSRF and
/// validation run before send. Hook must run immediately before transport.send.
class BookstarkMarkdownCreationTransport
    implements RemoteMarkdownCreationTransport {
  BookstarkMarkdownCreationTransport({
    required this.client,
    required this.scope,
    required this.createJson,
    required this.readFullJson,
    required this.readLabelsJson,
    required this.isCurrent,
    this.deadline = const Duration(seconds: 20),
  }) : _session = client.exportSession()['token'],
       _sessionRevision = client.sessionRevision {
    if (scope.server.toString() !=
            BookstarkClient.normalizeServer(
              client.baseUri.toString(),
            ).toString() ||
        deadline <= Duration.zero) {
      throw const FormatException('Wrong owned transport scope');
    }
  }
  final BookstarkClient client;
  @override
  final MarkdownCreationScope scope;
  final MarkdownCreateJson createJson;
  final MarkdownReadJson readFullJson, readLabelsJson;
  final bool Function() isCurrent;
  final Duration deadline;
  final String? _session;
  final int _sessionRevision;
  final _stopped = Completer<void>();
  @override
  void retire() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  void _guard() {
    if (_stopped.isCompleted ||
        !isCurrent() ||
        _session == null ||
        _session.isEmpty ||
        client.exportSession()['token'] != _session ||
        client.sessionRevision != _sessionRevision) {
      throw StateError('Creation owner retired');
    }
  }

  Future<T> _call<T>(Future<T> Function(Future<void>) work) async {
    _guard();
    final local = Completer<void>();
    final stop = Future.any<void>([local.future, _stopped.future]);
    try {
      final value = await work(stop).timeout(
        deadline,
        onTimeout: () {
          if (!local.isCompleted) local.complete();
          throw TimeoutException('Creation operation timed out');
        },
      );
      _guard();
      return value;
    } finally {
      if (!local.isCompleted) local.complete();
    }
  }

  Future<void> _owner() async {
    final owner = await _call(
      (abort) => client.profileSettingsJson(abortTrigger: abort),
    );
    if (owner['member_id'] != scope.memberId) {
      throw StateError('Wrong authenticated owner');
    }
  }

  @override
  Future<int> submit(
    MarkdownCreationInput input, {
    required void Function() onSubmit,
  }) async {
    if (input.title.trim().isEmpty) {
      throw const FormatException('Title required');
    }
    await _owner();
    _guard();
    var submitted = false;
    final envelope = await _call(
      (abort) => createJson(
        {
          'blog_title': input.title,
          'blog_content': input.content,
          'labels': encodeResourceLabels(input.labels),
          'blog_type': scope.collection,
          'editor_type': 'markdown',
          'visibility': 0,
        },
        abortTrigger: abort,
        onSubmit: () {
          _guard();
          if (submitted) throw StateError('POST replay blocked');
          submitted = true;
          onSubmit();
        },
      ),
    );
    final row = _object(envelope);
    final id = row['blog_id'];
    if (!submitted ||
        id is! int ||
        id <= 0 ||
        row['member_id'] != scope.memberId ||
        row['blog_type'] != scope.collection ||
        row['editor_type'] != 'markdown' ||
        row['visibility'] != 0 ||
        row['blog_title'] != input.title ||
        row['blog_content'] != input.content) {
      throw const FormatException(
        'Missing matching private Markdown creation receipt',
      );
    }
    return id;
  }

  Map<String, Object?> _object(Map<String, Object?> envelope) {
    if (envelope['code'] != 0 || envelope['data'] is! Map) {
      throw const FormatException('Invalid creation/read envelope');
    }
    return Map<String, Object?>.from(envelope['data'] as Map);
  }

  Map<String, Object?> _metadata(Map<String, Object?> row, int id) {
    if (row['blog_id'] != id ||
        row['member_id'] != scope.memberId ||
        row['blog_type'] != scope.collection ||
        row['editor_type'] != 'markdown' ||
        row['visibility'] != 0 ||
        row['has_password'] != false ||
        row['blog_title'] is! String ||
        row['version'] is! int ||
        (row['version'] as int) < 0 ||
        row['modify_at'] is! int ||
        (row['modify_at'] as int) < 0) {
      throw const FormatException(
        'Not an owned private ordinary Markdown resource',
      );
    }
    return {
      for (final k in [
        'blog_id',
        'member_id',
        'blog_type',
        'editor_type',
        'visibility',
        'has_password',
        'blog_title',
        'version',
        'modify_at',
      ])
        k: row[k],
    };
  }

  List<String> _labels(Map<String, Object?> row) {
    final labels = row['data'];
    // Label endpoint has List data and therefore remains an envelope in client.
    if (row['code'] == 0 && row.containsKey('data') && labels == null) {
      return const [];
    }
    if (row['code'] != 0 ||
        labels is! List ||
        labels.any((v) => v is! String)) {
      throw const FormatException('Missing complete label receipt');
    }
    return List<String>.from(labels);
  }

  @override
  Future<MarkdownCreationObserved> inspect(int id) async {
    if (id <= 0) throw const FormatException('Positive explicit ID required');
    await _owner();
    final before = _metadata(
      await _call((abort) => client.articleMetadata(id, abortTrigger: abort)),
      id,
    );
    final firstLabels = _labels(
      await _call((abort) => readLabelsJson(id, abortTrigger: abort)),
    );
    // Do not fetch raw source before metadata denies complex/protected/foreign.
    final fullEnvelope = await _call(
      (abort) => readFullJson(id, abortTrigger: abort),
    );
    final full = _object(fullEnvelope);
    final fullMeta = _metadata(full, id);
    if (creationDigest(before) != creationDigest(fullMeta) ||
        full['blog_content'] is! String) {
      throw StateError('Server resource changed');
    }
    final lastLabels = _labels(
      await _call((abort) => readLabelsJson(id, abortTrigger: abort)),
    );
    final after = _metadata(
      await _call((abort) => client.articleMetadata(id, abortTrigger: abort)),
      id,
    );
    if (creationDigest(before) != creationDigest(after) ||
        firstLabels.length != lastLabels.length ||
        !firstLabels.toSet().containsAll(lastLabels)) {
      throw StateError('Server resource changed');
    }
    final input = MarkdownCreationInput(
      title: full['blog_title'] as String,
      content: full['blog_content'] as String,
      labels: firstLabels,
    );
    return MarkdownCreationObserved(
      scope: scope,
      id: id,
      version: after['version'] as int,
      modifiedAt: after['modify_at'] as int,
      input: input,
      editorType: 'markdown',
      isProtected: false,
    );
  }
}
