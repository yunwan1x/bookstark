import '../speech/local_speech_provider_page.dart';
import '../tasks/task_editor_action_route.dart';
import '../../core/document_excerpt_request.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/book_draft_vault.dart';
import '../../core/label_management_repository.dart';
import '../books/book_editor_page.dart';
import '../books/chapters_page.dart';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/bookmark_draft_vault.dart';
import '../../core/bookmarks_repository.dart';
import '../../core/books_repository.dart';
import '../../core/documents_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../core/notes_repository.dart';
import '../../core/reading_position_vault.dart';
import '../../core/task_draft_vault.dart';
import '../../core/tasks_repository.dart';
import '../../core/topics_repository.dart';
import '../bookmarks/bookmark_editor_page.dart';
import '../books/document_reader_page.dart';
import '../notes/notes_page.dart';
import '../tasks/task_editor_page.dart';

/// Typed resource navigation shared by topic associations and future source
/// links. Server-provided open_url is never interpreted as an app route.
class NativeResourceOpener {
  const NativeResourceOpener({
    required this.notes,
    required this.articles,
    required this.books,
    required this.documents,
    required this.tasks,
    required this.bookmarks,
    required this.labels,
    this.bookDrafts,
    this.noteDrafts,
    this.articleDrafts,
    this.documentDrafts,
    this.excerptDrafts,
    this.taskDrafts,
    this.bookmarkDrafts,
    this.attachments,
    this.positions,
    this.server,
    this.onSpeak,
    this.onSpeakSelection,
    this.openArticle,
    this.openOwnedComplexNote,
    this.beforeOpenOwnedBlog,
    this.taskActionsFactory,
    this.recoverTaskCreation,
    this.sourceIoScope,
    this.boundedDocuments,
    this.readingFingerprint,
    this.onCreateExcerpt,
    this.inspectDocument,
    this.isCurrentScope,
    this.onEditComplexDocument,
    this.english = false,
  });
  final Future<void> Function(BuildContext, DocumentExcerptRequest)?
  onCreateExcerpt;
  final ComplexSourceIoScope? sourceIoScope;
  final BoundedDocumentsReader? boundedDocuments;
  final Future<String?> Function(TypedDocumentRead)? readingFingerprint;
  final Future<DocumentItem> Function(int id)? inspectDocument;
  final bool Function()? isCurrentScope;
  final Future<void> Function(BuildContext, int, DocumentItem)?
  onEditComplexDocument;
  final OpenOwnedComplexNote? openOwnedComplexNote;
  final Future<bool> Function(
    BuildContext context,
    int id,
    NoteCollection collection,
  )?
  beforeOpenOwnedBlog;
  final TaskEditorActionsFactory? taskActionsFactory;
  final Future<void> Function()? recoverTaskCreation;
  final NotesRepository notes, articles;
  final BooksRepository books;
  final DocumentsRepository documents;
  final TasksRepository tasks;
  final BookmarksRepository bookmarks;
  final LabelsRepository labels;
  final BookDraftVault? bookDrafts;
  final DraftVault? noteDrafts, articleDrafts, documentDrafts;
  final DraftVault Function(int documentId)? excerptDrafts;
  final TaskDraftVault? taskDrafts;
  final BookmarkDraftVault? bookmarkDrafts;
  final AttachmentRepository? attachments;
  final ReadingPositionVault? positions;
  final Uri? server;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final bool english;
  final Future<void> Function(BuildContext context, int id)? openArticle;
  Future<void> openLabel(
    BuildContext context,
    LabelResource resource, {
    required Future<NoteCollection> Function(int id) resolveCollection,
  }) async {
    if (resource.id <= 0) throw const FormatException('Invalid resource ID');
    switch (resource.type) {
      case LabelResourceType.book:
        await books.read(resource.id);
        if (!context.mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ChaptersPage(
              bookId: resource.id,
              books: books,
              documents: documents,
              english: english,
              onOpen: (context, id) =>
                  open(context, TopicResourceType.document, id),
              onSettings: (context, book) async {
                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookEditorPage(
                      repository: books,
                      book: book,
                      labelsRepository: labels,
                      vault: bookDrafts,
                      english: english,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      case LabelResourceType.blog:
        final collection = await resolveCollection(resource.id);
        if (!context.mounted) return;
        await open(
          context,
          collection == NoteCollection.article
              ? TopicResourceType.article
              : TopicResourceType.note,
          resource.id,
        );
      case LabelResourceType.bookmark:
        await open(context, TopicResourceType.bookmark, resource.id);
      case LabelResourceType.document:
        await open(context, TopicResourceType.document, resource.id);
    }
  }

  Future<void> open(
    BuildContext context,
    TopicResourceType type,
    int id,
  ) async {
    if (id <= 0) throw const FormatException('Invalid resource ID');
    switch (type) {
      case TopicResourceType.note:
      case TopicResourceType.article:
        final article = type == TopicResourceType.article;
        final gate = beforeOpenOwnedBlog;
        if (gate != null) {
          final allowed = await gate(
            context,
            id,
            article ? NoteCollection.article : NoteCollection.note,
          );
          if (!allowed ||
              !context.mounted ||
              !(isCurrentScope?.call() ?? true)) {
            return;
          }
        }
        if (article && openArticle != null) {
          await openArticle!(context, id);
          return;
        }
        await openNativeNoteEditor(
          context,
          repository: article ? articles : notes,
          onOpenOwnedComplex: article ? null : openOwnedComplexNote,
          isCurrentScope: isCurrentScope,
          sourceIoScope: sourceIoScope,
          id: id,
          collection: article ? NoteCollection.article : NoteCollection.note,
          drafts: article ? articleDrafts : noteDrafts,
          attachments: attachments,
          english: english,
        );
      case TopicResourceType.task:
        if (!(isCurrentScope?.call() ?? true)) return;
        final task = await tasks.read(id);
        if (!context.mounted || !(isCurrentScope?.call() ?? true)) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ownedTaskEditorRoute(
              factory: taskActionsFactory,
              english: english,
              builder: (actions) => TaskEditorPage(
                onCreationRecovery: recoverTaskCreation,
                actions: actions,
                repository: tasks,
                task: task,
                vault: taskDrafts,
                attachments: attachments,
                english: english,
              ),
            ),
          ),
        );
      case TopicResourceType.bookmark:
        final bookmark = await bookmarks.read(id);
        if (!context.mounted) return;
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => BookmarkEditorPage(
              repository: bookmarks,
              bookmark: bookmark,
              labelsRepository: labels,
              vault: bookmarkDrafts,
              english: english,
              local: server == null,
            ),
          ),
        );
      case TopicResourceType.document:
        if (!(isCurrentScope?.call() ?? true)) return;
        final document =
            await (inspectDocument?.call(id) ?? documents.read(id));
        if (!context.mounted || !(isCurrentScope?.call() ?? true)) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentReaderPage(
              bookId: document.bookId,
              onEditComplex: onEditComplexDocument == null
                  ? null
                  : (context, item) =>
                        onEditComplexDocument!(context, document.bookId, item),
              documentId: id,
              boundedReader: boundedDocuments,
              readingFingerprint: readingFingerprint,
              onExcerptRequest: onCreateExcerpt,
              isCurrentScope: isCurrentScope,
              books: books,
              documents: documents,
              attachments: attachments,
              drafts: documentDrafts,
              server: server,
              positions: positions,
              onSpeak: onSpeak,
              onSpeakSelection: onSpeakSelection,
              english: english,
              onExcerpt: (context, note, documentId) async {
                await openNativeNoteEditor(
                  context,
                  repository: notes,
                  initial: note,
                  drafts: excerptDrafts?.call(documentId),
                  attachments: attachments,
                  english: english,
                );
              },
            ),
          ),
        );
    }
  }
}
