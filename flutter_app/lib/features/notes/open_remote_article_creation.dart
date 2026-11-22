import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/core/resource_creation_result.dart';
import 'remote_markdown_article_creation_factory.dart';
import 'article_creation_retained_record.dart';
import 'article_creation_retained_page.dart';

/// Typed outcome comes from the persisted creation receipt provenance, never a
/// Navigator boolean or a known-ID open callback.
Future<ResourceCreationResult?> openRemoteArticleCreation(
  BuildContext context, {
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required NotesRepository repository,
  required Future<String?> Function(String key) readValue,
  required Future<void> Function(String key, String value) writeValue,
  required Future<void> Function(String key) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  required Future<void> Function(int id, MarkdownKnownIDOrigin origin)
  openKnown,
  required ComplexSourceIoScope? sourceIoScope,
  DraftVault? drafts,
  List<DraftVault> additionalLegacyDrafts = const [],
  bool english = false,
}) async {
  final revision = client.sessionRevision,
      token = client.exportSession()['token'];
  final server = BookstarkClient.normalizeServer(client.baseUri.toString());
  bool current() {
    try {
      return isCurrent() &&
          client.sessionRevision == revision &&
          client.exportSession()['token'] == token &&
          BookstarkClient.normalizeServer(client.baseUri.toString()) == server;
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted || !current()) return null;
  final retained = await inspectArticleCreationRetention(
    client: client,
    memberId: memberId,
    namespace: namespace,
    isCurrent: current,
    readValue: readValue,
    flush: flush,
    legacyDrafts: [?drafts, ...additionalLegacyDrafts],
  );
  if (!context.mounted || !current()) return null;
  if (retained != null) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArticleCreationRetainedPage(
          record: retained,
          isCurrent: current,
          sourceIoScope: sourceIoScope,
          english: english,
        ),
      ),
    );
    return null;
  }
  final page = await createRemoteMarkdownArticleCreationEditor(
    client: client,
    memberId: memberId,
    namespace: namespace,
    repository: repository,
    readValue: readValue,
    writeValue: writeValue,
    deleteValue: deleteValue,
    flush: flush,
    isCurrent: current,
    openKnown: openKnown,
    sourceIoScope: sourceIoScope,
    drafts: drafts,
    additionalLegacyDrafts: additionalLegacyDrafts,
    english: english,
  );
  final controller = page.binding.controller;
  if (!context.mounted || !page.binding.isCurrent()) {
    controller.retire();
    return null;
  }
  try {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (!context.mounted || !current()) return null;
    final record = controller.record, id = record.knownId;
    if (id == null ||
        record.knownIDOrigin == MarkdownKnownIDOrigin.unknownLegacy) {
      return null;
    }
    final observed = controller.observed;
    final adopted =
        record.knownIDOrigin == MarkdownKnownIDOrigin.manualExisting;
    if (adopted &&
        (observed == null ||
            observed.id != id ||
            observed.scope.namespace != controller.vault.scope.namespace)) {
      return null;
    }
    return ResourceCreationResult(
      kind: CreatedResourceKind.article,
      id: id,
      title: adopted ? observed!.input.title : record.input.title,
      created: record.knownIDOrigin == MarkdownKnownIDOrigin.postReceipt,
      metadataComplete: controller.phase == MarkdownCreationPhase.finished,
    );
  } finally {
    controller.retire();
  }
}
