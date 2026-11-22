import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/attachments.dart';
import '../../core/draft_vault.dart';
import '../../core/document_excerpt_request.dart';
import '../../core/notes_repository.dart';
import '../../core/remote_markdown_creation_vault.dart';
import '../notes/remote_markdown_creation_factory.dart';
import '../notes/remote_markdown_creation_editor_page.dart';

/// One existing owner/collection creation slot. No legacy save(null) fallback.
Future<void> openRemoteBookExcerpt(
  BuildContext context, {
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required DocumentExcerptRequest request,
  required NotesRepository repository,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  DraftVault? drafts,
  List<DraftVault> additionalLegacyDrafts = const [],
  AttachmentRepository? attachments,
  bool english = false,
  void Function(int)? onSaved,
}) async {
  final revision = client.sessionRevision,
      token = client.exportSession()['token'];
  bool current() {
    try {
      return context.mounted &&
          isCurrent() &&
          request.isCurrentSource() &&
          client.sessionRevision == revision &&
          client.exportSession()['token'] == token;
    } catch (_) {
      return false;
    }
  }

  if (!current()) return;
  final initial = MarkdownCreationInput(
    title: request.note.title,
    content: request.note.content,
    labels: request.note.labels,
  );
  RemoteMarkdownCreationEditorPage? prepared;
  try {
    final verified = await request.verifyCurrentSource();
    if (!current()) return;
    if (!verified) throw StateError('Excerpt source changed');
    final page = await createRemoteMarkdownCreationEditor(
      client: client,
      memberId: memberId,
      namespace: namespace,
      collection: NoteCollection.note,
      repository: repository,
      initial: initial,
      initialExcerptOrigin: request.origin,
      drafts: drafts,
      additionalLegacyDrafts: additionalLegacyDrafts,
      attachments: attachments,
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
      isCurrent: current,
      english: english,
      onSaved: onSaved,
    );
    prepared = page;
    if (!current()) return;
    final retained = page.controller.record;
    final sameSource = retained.excerptOrigin?.same(request.origin) == true;
    final sameInput = retained.input.matches(initial);
    if (!sameInput || !sameSource) {
      if (!context.mounted) return;
      final keepExisting = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(english ? 'Retained note draft' : '已有笔记草稿'),
          content: Text(
            english
                ? 'A previous draft or unresolved save must be handled first. This selection has not replaced it. Continue the retained draft or return to the document.'
                : '需要先处理已有草稿或未确认的保存。新选区没有覆盖它。可继续已有草稿，或返回原文。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(english ? 'Back' : '返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(english ? 'Continue retained draft' : '继续已有草稿'),
            ),
          ],
        ),
      );
      if (keepExisting != true || !current()) return;
    } else if (page.controller.canEdit) {
      // Durable excerpt+origin before UI handoff; storage-only, never POST.
      await page.controller.edit(initial);
      if (!current()) return;
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => page));
  } catch (_) {
    if (!current()) return;
    throw StateError(
      english
          ? 'Excerpt could not be opened. The original and retained draft are preserved.'
          : '暂时无法打开摘录，原文和已有草稿仍已保留。',
    );
  } finally {
    if (prepared != null) retireRemoteMarkdownCreationEditor(prepared);
  }
}
