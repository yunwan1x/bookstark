import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/complex_editors/remote_article_creation_page.dart';
import 'remote_markdown_creation_factory.dart';

/// Storage-only open; the existing typed transport submits only after the real
/// WebView's complete source has passed its durable checkpoint.
Future<RemoteArticleCreationPage> createRemoteMarkdownArticleCreationEditor({
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
  MarkdownCreationInput? initial,
  DraftVault? drafts,
  List<DraftVault> additionalLegacyDrafts = const [],
  bool english = false,
  void Function(int id)? onSaved,
}) async {
  final binding = await createRemoteMarkdownCreationBinding(
    client: client,
    memberId: memberId,
    namespace: namespace,
    collection: NoteCollection.article,
    repository: repository,
    readValue: readValue,
    writeValue: writeValue,
    deleteValue: deleteValue,
    flush: flush,
    isCurrent: isCurrent,
    initial: initial,
    drafts: drafts,
    additionalLegacyDrafts: additionalLegacyDrafts,
    english: english,
    onSaved: onSaved,
  );
  if (!binding.isCurrent()) {
    binding.controller.retire();
    throw StateError('Article owner retired before route open');
  }
  return RemoteArticleCreationPage(
    binding: binding,
    openKnown: openKnown,
    sourceIoScope: sourceIoScope,
  );
}
