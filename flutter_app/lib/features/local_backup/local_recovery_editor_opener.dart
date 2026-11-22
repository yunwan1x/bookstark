import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/book_draft_vault.dart';
import '../../core/bookmark_draft_vault.dart';
import '../../core/bookmarks_repository.dart';
import '../../core/books_repository.dart';
import '../../core/document_creation.dart';
import '../../core/draft_vault.dart';
import '../../core/file_draft_vault.dart';
import '../../core/local_attachments.dart';
import '../../core/local_bookmarks_repository.dart';
import '../../core/local_books_repository.dart';
import '../../core/local_documents_repository.dart';
import '../../core/local_drive_repository.dart';
import '../../core/labels_repository.dart';
import '../../core/local_recovery_resolver.dart';
import '../../core/local_store.dart';
import '../../core/local_tasks_repository.dart';
import '../../core/local_topics_repository.dart';
import '../../core/notes_repository.dart';
import '../../core/reading_position_vault.dart';
import '../../core/task_draft_vault.dart';
import '../../core/tasks_repository.dart';
import '../../core/topic_draft_vault.dart';
import '../../core/topics_repository.dart';
import '../bookmarks/bookmark_editor_page.dart';
import '../assistant/open_local_assistant_recovery.dart';
import '../../core/local_assistant_write_journal.dart';
import '../books/book_editor_page.dart';
import '../books/document_reader_page.dart';
import '../drive/file_editor_page.dart';
import '../html/open_local_html_note.dart';
import '../html/open_new_local_html_note.dart';
import '../notes/notes_page.dart';
import '../complex_editors/open_local_article_draft_archive.dart';
import '../complex_editors/open_local_article_creation.dart';
import '../public_feed/resource_create_coordinator.dart';
import '../public_feed/resource_create_page.dart';
import '../tasks/task_editor_page.dart';
import '../topics/topic_editor_page.dart';

/// Opens verified owned destinations. Bodies are read only after an explicit
/// editor/archive action; article draft transfer requires a confirmed handoff.
class LocalRecoveryEditorOpener {
  LocalRecoveryEditorOpener({
    required this.store,
    this.english = false,
    this.isCurrentScope,
    this.drainOriginatingAssistantSave,
    this.onResumeAssistantEditor,
    this.onResumeSavedAssistantEditor,
    this.onOpenAssistantResource,
  });
  final LocalStore store;
  final bool english;
  final bool Function()? isCurrentScope;
  final Future<void> Function(LocalAssistantWriteMarker)?
  drainOriginatingAssistantSave;
  final ResumeLocalAssistantEditor? onResumeAssistantEditor;
  final ResumeSavedLocalAssistantEditor? onResumeSavedAssistantEditor;
  final OpenLocalAssistantResource? onOpenAssistantResource;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  Future<String?> _read(String key) => _storage.read(key: key);
  Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value);
  Future<void> _delete(String key) => _storage.delete(key: key);
  DraftVault _draft(String namespace) => DraftVault(
    namespace: namespace,
    maintenance: store.maintenance,
    readValue: _read,
    writeValue: _write,
    deleteValue: _delete,
  );
  BookDraftVault _book(String namespace) => BookDraftVault(
    namespace: namespace,
    maintenance: store.maintenance,
    readValue: _read,
    writeValue: _write,
    deleteValue: _delete,
  );
  BookmarkDraftVault _bookmark(String namespace) => BookmarkDraftVault(
    namespace: namespace,
    maintenance: store.maintenance,
    readValue: _read,
    writeValue: _write,
    deleteValue: _delete,
  );

  Future<void> open(
    BuildContext context,
    LocalRecoveryDestination destination,
  ) async {
    final namespace = store.dataPaths!.draftNamespace;
    if (store.maintenance.retired) {
      throw StateError('Storage session has retired');
    }
    if (destination.kind == 'ai-create' || destination.kind == 'ai-editor') {
      final drain = drainOriginatingAssistantSave;
      final resume = onResumeAssistantEditor;
      final openResource = onOpenAssistantResource;
      if (drain == null || resume == null || openResource == null) {
        throw StateError('Assistant recovery coordinator is unavailable');
      }
      await LocalAssistantRecovery.secure(
        store: store,
        drainOriginatingSave: drain,
        isCurrent: isCurrentScope,
      ).open(
        context,
        destination,
        onResumeEditor: resume,
        onResumeSavedEditor: onResumeSavedAssistantEditor,
        onOpenResource: openResource,
        english: english,
      );
      return;
    }
    if (destination.kind == 'article-create') {
      if (destination.namespace != namespace ||
          destination.id != null ||
          destination.collection != 'article') {
        throw StateError('Invalid owned article creation destination');
      }
      await openLocalArticleCreation(
        context,
        store: store,
        legacyDrafts: _draft(jsonEncode([namespace, 'article'])),
        english: english,
        isCurrentScope: isCurrentScope,
      );
      return;
    }
    if (destination.kind == 'article-create-archive') {
      if (destination.id != null || destination.collection != 'article') {
        throw StateError('Invalid archived article creation destination');
      }
      await openLocalArticleCreationArchive(
        context,
        store: store,
        namespace: destination.namespace,
        english: english,
        isCurrentScope: isCurrentScope,
      );
      return;
    }
    if (destination.kind == 'article-archive') {
      final id = destination.id;
      if (id == null || id <= 0 || destination.collection != 'article') {
        throw StateError('Invalid old article destination');
      }
      await openLocalArticleDraftArchive(
        context,
        store: store,
        namespace: destination.namespace,
        id: id,
        english: english,
        isCurrentScope: isCurrentScope,
      );
      return;
    }
    final labels = LocalLabelsRepository(store);
    final notes = LocalNotesRepository(store);
    final articles = LocalNotesRepository(
      store,
      collection: NoteCollection.article,
    );
    final books = LocalBooksRepository(store);
    final documents = LocalDocumentsRepository(store);
    final bookmarks = LocalBookmarksRepository(store);
    final media = LocalAttachments(
      store.dataPaths!.attachments,
      maintenance: store.maintenance,
    );
    try {
      final id = destination.id;
      switch (destination.kind) {
        case 'note':
        case 'excerpt':
        case 'complex':
          await openNativeNoteEditor(
            context,
            repository: destination.collection == 'article' ? articles : notes,
            id: id,
            collection: destination.collection == 'article'
                ? NoteCollection.article
                : NoteCollection.note,
            drafts: _draft(
              destination.collection == 'article' && id != null
                  ? jsonEncode([namespace, 'article'])
                  : destination.namespace,
            ),
            isCurrentScope: isCurrentScope,
            forceLegacyArticleDraftReview:
                destination.kind == 'note' &&
                destination.collection == 'article' &&
                id != null,
            attachments: media,
            english: english,
          );
        case 'html':
          await openLocalHtmlNote(
            context,
            store: store,
            id: id!,
            collection: destination.collection,
            english: english,
          );
        case 'html-create':
          await openNewLocalHtmlNote(
            context,
            store: store,
            collection: destination.collection,
            english: english,
          );
        case 'task':
          final repository = LocalTasksRepository(store);
          final task = id == null
              ? const TaskItem(content: '', dueDate: '')
              : await repository.read(id);
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => TaskEditorPage(
                repository: repository,
                task: task,
                english: english,
                attachments: media,
                vault: TaskDraftVault(
                  namespace: destination.namespace,
                  maintenance: store.maintenance,
                  readValue: _read,
                  writeValue: _write,
                  deleteValue: _delete,
                ),
              ),
            ),
          );
        case 'bookmark':
          final bookmark = id == null
              ? const BookmarkItem(title: '', url: '')
              : await bookmarks.read(id);
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => BookmarkEditorPage(
                repository: bookmarks,
                bookmark: bookmark,
                labelsRepository: labels,
                vault: _bookmark(destination.namespace),
                local: true,
                english: english,
              ),
            ),
          );
        case 'book':
          final book = id == null
              ? const BookItem(name: '')
              : await books.read(id);
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => BookEditorPage(
                repository: books,
                book: book,
                labelsRepository: labels,
                vault: _book(destination.namespace),
                english: english,
              ),
            ),
          );
        case 'topic':
          final repository = LocalTopicsRepository(store);
          final topic = id == null
              ? const TopicItem(title: '')
              : (await repository.read(id)).topic;
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => TopicEditorPage(
                repository: repository,
                topic: topic,
                english: english,
                vault: TopicDraftVault(
                  namespace: destination.namespace,
                  maintenance: store.maintenance,
                  readValue: _read,
                  writeValue: _write,
                  deleteValue: _delete,
                ),
              ),
            ),
          );
        case 'file':
          final repository = LocalDriveRepository(
            store,
            store.dataPaths!.driveBlobs,
          );
          try {
            final rows = await store.maintenance.use(
              () async => (await store.database).query(
                'local_drive_nodes',
                columns: ['parent_path'],
                where: 'node_id = ? AND directory = 0',
                whereArgs: [id],
              ),
            );
            if (rows.length != 1) {
              throw StateError('File recovery resource unavailable');
            }
            final files = await repository.list(
              rows.single['parent_path'] as String,
            );
            final file = files.where((file) => file.id == id).single;
            if (!context.mounted) return;
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FileEditorPage(
                  repository: repository,
                  file: file,
                  vault: FileDraftVault(
                    namespace: destination.namespace,
                    maintenance: store.maintenance,
                    readValue: _read,
                    writeValue: _write,
                    deleteValue: _delete,
                  ),
                ),
              ),
            );
          } finally {
            repository.dispose();
          }
        case 'document':
          final document = await documents.read(id!);
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => DocumentReaderPage(
                bookId: document.bookId,
                documentId: id,
                books: books,
                documents: documents,
                attachments: media,
                drafts: _draft(destination.namespace),
                english: english,
                positions: ReadingPositionVault(
                  namespace: namespace,
                  maintenance: store.maintenance,
                  readValue: _read,
                  writeValue: _write,
                  deleteValue: _delete,
                ),
              ),
            ),
          );
        case 'document-create':
          await ResourceCreateCoordinator(
            notes: notes,
            articles: articles,
            bookmarks: bookmarks,
            books: books,
            documents: documents,
            labels: labels,
            noteDrafts: _draft(namespace),
            articleDrafts: _draft(jsonEncode([namespace, 'article'])),
            documentDrafts: _draft(jsonEncode([namespace, 'document'])),
            bookmarkDrafts: _bookmark(namespace),
            bookDrafts: _book(namespace),
            documentCreationVault: DocumentCreationVault(
              namespace: namespace,
              maintenance: store.maintenance,
              readValue: _read,
              writeValue: _write,
              deleteValue: _delete,
            ),
            attachments: media,
            local: true,
            english: english,
          ).open(context, initialKind: ResourceCreateKind.document);
        default:
          throw StateError('Unsupported recovery destination');
      }
    } finally {
      media.close();
    }
  }
}
