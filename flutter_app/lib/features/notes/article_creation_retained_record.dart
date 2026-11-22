import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/owned_article_review_export.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';

class ArticleCreationRetainedRecord {
  const ArticleCreationRetainedRecord({
    required this.source,
    required this.reason,
    required this.export,
    required this.verifyFresh,
  });
  final String source, reason;
  final OwnedArticleReviewExport export;
  final Future<void> Function() verifyFresh;
  bool get renderable =>
      export.bytes.length <= ComplexEditorKind.markdown.maxBytes;
}

/// Read-only preflight. An invalid existing record blocks new creation without
/// deleting, rewriting, normalizing, or reclassifying it as an unsubmitted draft.
Future<ArticleCreationRetainedRecord?> inspectArticleCreationRetention({
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required bool Function() isCurrent,
  required Future<String?> Function(String key) readValue,
  required Future<void> Function() flush,
  required List<DraftVault> legacyDrafts,
}) async {
  final revision = client.sessionRevision,
      token = client.exportSession()['token'];
  final base = BookstarkClient.normalizeServer(client.baseUri.toString());
  if (token == null || token.isEmpty) {
    throw StateError('Authenticated retained owner required');
  }
  void guard() {
    if (!isCurrent() ||
        client.sessionRevision != revision ||
        client.exportSession()['token'] != token ||
        BookstarkClient.normalizeServer(client.baseUri.toString()) != base) {
      throw StateError('Article retention owner retired');
    }
  }

  guard();
  await flush();
  guard();
  final scope = MarkdownCreationScope(
    server: base,
    memberId: memberId,
    collection: 'article',
  );
  final vault = RemoteMarkdownCreationVault(
    scope: scope,
    readValue: (key) async {
      guard();
      final value = await readValue(jsonEncode([namespace, key]));
      guard();
      return value;
    },
    writeValue: (_, _) async => throw StateError('Read-only preflight'),
    deleteValue: (_) async => throw StateError('Read-only preflight'),
    flush: flush,
  );
  Future<ArticleCreationRetainedRecord> retained(
    String raw,
    Future<String?> Function() reread,
    String reason,
  ) async {
    ComplexEditorDocument.validateText(raw);
    final record = OwnedArticleReviewExport(
      source: raw,
      mime: 'application/json',
      name: 'article-recovery-record.json',
    );
    return ArticleCreationRetainedRecord(
      source: raw,
      reason: reason,
      export: record,
      verifyFresh: () async {
        guard();
        final current = await reread();
        guard();
        if (current != raw) throw StateError('Retained record changed');
      },
    );
  }

  final raw = await vault.readRecord('new');
  guard();
  if (raw != null) {
    try {
      if (utf8.encode(raw).length > 32 * 1024 * 1024) {
        throw const FormatException('Oversized journal');
      }
      MarkdownCreationRecord.parse(jsonDecode(raw), scope);
    } on FormatException {
      return retained(raw, () => vault.readRecord('new'), 'creation-record');
    }
  }
  final seen = <String>{};
  for (final draft in legacyDrafts) {
    if (!seen.add(draft.metadataKey(null))) continue;
    guard();
    final raw = await draft.readRecord(null);
    guard();
    if (raw == null) continue;
    try {
      final note = await draft.read(null);
      guard();
      if (note == null) throw const FormatException('Missing legacy record');
      MarkdownCreationInput(
        title: note.title,
        content: note.content,
        labels: note.labels,
      );
    } catch (error) {
      // Ownership failures never become a generic export record.
      guard();
      if (error is! FormatException && error is! TypeError) rethrow;
      return retained(raw, () => draft.readRecord(null), 'legacy-record');
    }
  }
  return null;
}
