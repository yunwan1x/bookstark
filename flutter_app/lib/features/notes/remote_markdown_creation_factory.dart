import '../../core/document_excerpt_origin.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import '../../core/attachments.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/remote_markdown_creation_controller.dart';
import '../../core/remote_markdown_creation_transport.dart';
import '../../core/remote_markdown_creation_vault.dart';
import 'remote_markdown_creation_editor_page.dart';

/// Actual new remote Markdown route factory; never creates an existing-ID editor.
/// Opening is storage-only, so an authenticated retained draft remains usable
/// offline. Profile/CSRF/full-source requests occur only on explicit actions.
Future<RemoteMarkdownCreationEditorPage> createRemoteMarkdownCreationEditor({
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required NoteCollection collection,
  required NotesRepository repository,
  required Future<String?> Function(String key) readValue,
  required Future<void> Function(String key, String value) writeValue,
  required Future<void> Function(String key) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  MarkdownCreationInput? initial,
  DocumentExcerptOrigin? initialExcerptOrigin,
  DraftVault? drafts,
  List<DraftVault> additionalLegacyDrafts = const [],
  AttachmentRepository? attachments,
  Future<XFile?> Function(bool imagesOnly)? pickFile,
  Future<void> Function(Attachment attachment, Uint8List bytes)? shareFile,
  bool english = false,
  // Open/refresh event only: manual adoption is not proof of a new creation.
  void Function(int id)? onSaved,
}) async {
  if (collection != NoteCollection.note) {
    throw UnsupportedError('Articles require their server WebView editor');
  }
  final binding = await createRemoteMarkdownCreationBinding(
    client: client,
    memberId: memberId,
    namespace: namespace,
    collection: collection,
    repository: repository,
    readValue: readValue,
    writeValue: writeValue,
    deleteValue: deleteValue,
    flush: flush,
    isCurrent: isCurrent,
    initial: initial,
    initialExcerptOrigin: initialExcerptOrigin,
    drafts: drafts,
    additionalLegacyDrafts: additionalLegacyDrafts,
    attachments: attachments,
    pickFile: pickFile,
    shareFile: shareFile,
    english: english,
    onSaved: onSaved,
  );
  return binding.notePage();
}

/// Shared actual durability/HTTP setup; only this layer handles legacy drafts.
/// The caller chooses a note or article surface, never a different collection.
class RemoteMarkdownCreationBinding {
  const RemoteMarkdownCreationBinding({
    required this.controller,
    required this.repository,
    required this.isCurrent,
    required this.collection,
    required this.english,
    this.drafts,
    this.attachments,
    this.pickFile,
    this.shareFile,
    this.onSaved,
    this.beforeOpenSaved,
  });
  final RemoteMarkdownCreationController controller;
  final NotesRepository repository;
  final bool Function() isCurrent;
  final NoteCollection collection;
  final bool english;
  final DraftVault? drafts;
  final AttachmentRepository? attachments;
  final Future<XFile?> Function(bool imagesOnly)? pickFile;
  final Future<void> Function(Attachment attachment, Uint8List bytes)?
  shareFile;
  final void Function(int id)? onSaved;
  final Future<void> Function()? beforeOpenSaved;
  RemoteMarkdownCreationEditorPage notePage() {
    if (collection != NoteCollection.note) {
      throw StateError('Articles require WebView');
    }
    return RemoteMarkdownCreationEditorPage(
      controller: controller,
      repository: repository,
      isCurrent: isCurrent,
      collection: collection,
      english: english,
      drafts: drafts,
      attachments: attachments,
      pickFile: pickFile,
      shareFile: shareFile,
      onSaved: onSaved,
      beforeOpenSaved: beforeOpenSaved,
    );
  }
}

Future<RemoteMarkdownCreationBinding> createRemoteMarkdownCreationBinding({
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required NoteCollection collection,
  required NotesRepository repository,
  required Future<String?> Function(String key) readValue,
  required Future<void> Function(String key, String value) writeValue,
  required Future<void> Function(String key) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  MarkdownCreationInput? initial,
  DocumentExcerptOrigin? initialExcerptOrigin,
  DraftVault? drafts,
  List<DraftVault> additionalLegacyDrafts = const [],
  AttachmentRepository? attachments,
  Future<XFile?> Function(bool imagesOnly)? pickFile,
  Future<void> Function(Attachment attachment, Uint8List bytes)? shareFile,
  bool english = false,
  // Open/refresh event only: manual adoption is not proof of a new creation.
  void Function(int id)? onSaved,
}) async {
  if (initial == null && initialExcerptOrigin != null) {
    throw ArgumentError('Excerpt origin needs its full initial input');
  }
  // Validate scalar Unicode as well as byte bounds; distinct namespace strings
  // must not collapse under UTF-8 replacement encoding.
  MarkdownCreationInput(title: '', content: namespace, labels: const []);
  if (namespace.isEmpty || utf8.encode(namespace).length > 4096) {
    throw const FormatException('Owned storage namespace required');
  }
  final revision = client.sessionRevision;
  final token = client.exportSession()['token'];
  final base = BookstarkClient.normalizeServer(client.baseUri.toString());
  if (token == null || token.isEmpty) {
    throw StateError('Authenticated owner required');
  }
  final scope = MarkdownCreationScope(
    server: base,
    memberId: memberId,
    collection: collection.name,
  );
  bool current() {
    try {
      return isCurrent() &&
          client.sessionRevision == revision &&
          client.exportSession()['token'] == token &&
          BookstarkClient.normalizeServer(client.baseUri.toString()) == base;
    } catch (_) {
      return false;
    }
  }

  void guard() {
    if (!current()) throw StateError('Markdown creation owner retired');
  }

  String storageKey(String key) => jsonEncode([namespace, key]);
  final vault = RemoteMarkdownCreationVault(
    scope: scope,
    readValue: (key) async {
      guard();
      final value = await readValue(storageKey(key));
      guard();
      return value;
    },
    writeValue: (key, value) async {
      guard();
      await writeValue(storageKey(key), value);
      guard();
    },
    deleteValue: (key) async {
      guard();
      await deleteValue(storageKey(key));
      guard();
    },
    flush: () async {
      guard();
      await flush();
      guard();
    },
  );
  final transport = BookstarkMarkdownCreationTransport(
    client: client,
    scope: scope,
    isCurrent: current,
    // These methods return ORIGINAL root envelopes. The typed transport owns
    // strict code/data validation. Its articleMetadata/profileSettingsJson
    // calls return the API's separately validated unwrapped metadata maps.
    createJson: (body, {required onSubmit, required abortTrigger}) =>
        client.createMarkdownNoteJson(
          body,
          onSubmit: onSubmit,
          abortTrigger: abortTrigger,
        ),
    readFullJson: (id, {required abortTrigger}) =>
        client.boundedOwnedMarkdownJson(id, abortTrigger: abortTrigger),
    readLabelsJson: (id, {required abortTrigger}) =>
        client.boundedResourceLabelsJson(id, abortTrigger: abortTrigger),
  );
  RemoteMarkdownCreationController? controller;
  try {
    guard();
    // Absence only unlocks a new attempt after a real durability barrier.
    await vault.flush();
    guard();
    final legacyRecords = <(DraftVault, Note)>[];
    final seenLegacyKeys = <String>{};
    Note? candidateLegacy;
    for (final source in <DraftVault>[?drafts, ...additionalLegacyDrafts]) {
      if (!seenLegacyKeys.add(source.metadataKey(null))) continue;
      guard();
      final value = await source.read(null);
      guard();
      if (value == null) continue;
      final previous = candidateLegacy;
      if (previous != null &&
          !MarkdownCreationInput(
            title: previous.title,
            content: previous.content,
            labels: previous.labels,
          ).matches(
            MarkdownCreationInput(
              title: value.title,
              content: value.content,
              labels: value.labels,
            ),
          )) {
        throw StateError('Multiple unrelated legacy drafts require review');
      }
      candidateLegacy ??= value;
      legacyRecords.add((source, value));
    }
    final legacy = candidateLegacy;
    final stored = await vault.read();
    guard();
    if (legacy != null &&
        stored != null &&
        !stored.input.matches(
          MarkdownCreationInput(
            title: legacy.title,
            content: legacy.content,
            labels: legacy.labels,
          ),
        )) {
      throw StateError('Unrelated legacy Markdown draft requires review');
    }
    if (legacy != null && stored == null) {
      // A pre-journal null-ID draft is never proof that no POST was sent.
      final input = MarkdownCreationInput(
        title: legacy.title,
        content: legacy.content,
        labels: legacy.labels,
      );
      final retained = MarkdownCreationRecord.fresh(
        scope,
        input,
      ).copy(pending: true);
      await vault.compareAndWrite(null, retained, guard: guard);
    }
    guard();
    controller = await RemoteMarkdownCreationController.open(
      transport: transport,
      vault: vault,
      isCurrent: current,
      initial:
          initial ??
          MarkdownCreationInput(title: '', content: '', labels: const []),
      initialExcerptOrigin: initialExcerptOrigin,
    );
    guard();
    return RemoteMarkdownCreationBinding(
      controller: controller,
      repository: repository,
      isCurrent: current,
      drafts: drafts,
      attachments: attachments,
      pickFile: pickFile,
      shareFile: shareFile,
      collection: collection,
      english: english,
      onSaved: onSaved,
      beforeOpenSaved: legacyRecords.isEmpty
          ? null
          : () async {
              for (final captured in legacyRecords) {
                final source = captured.$1, expectedNote = captured.$2;
                guard();
                final fresh = await source.read(null);
                guard();
                if (fresh == null) continue;
                final expected = MarkdownCreationInput(
                  title: expectedNote.title,
                  content: expectedNote.content,
                  labels: expectedNote.labels,
                );
                final observed = MarkdownCreationInput(
                  title: fresh.title,
                  content: fresh.content,
                  labels: fresh.labels,
                );
                if (!expected.matches(observed)) {
                  throw StateError('Legacy draft changed');
                }
                await source.remove(null);
                guard();
                await flush();
                guard();
                if (await source.read(null) != null) {
                  throw StateError('Legacy draft cleanup unconfirmed');
                }
                guard();
              }
            },
    );
  } catch (_) {
    controller?.retire();
    transport.retire();
    rethrow;
  }
}

/// Retire an asynchronously prepared page if its route was abandoned.
void retireRemoteMarkdownCreationEditor(RemoteMarkdownCreationEditorPage page) {
  page.controller.retire();
}
