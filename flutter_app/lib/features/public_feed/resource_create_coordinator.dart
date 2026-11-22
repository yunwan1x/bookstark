import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/book_draft_vault.dart';
import '../../core/bookmark_draft_vault.dart';
import '../../core/bookmarks_repository.dart';
import '../../core/books_repository.dart';
import '../../core/document_creation.dart';
import '../../core/document_editor_repository.dart';
import '../../core/documents_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../core/notes_repository.dart';
import '../../core/resource_creation_result.dart';
import '../bookmarks/bookmark_editor_page.dart';
import '../books/book_editor_page.dart';
import '../books/chapters_page.dart';
import '../books/document_reader_page.dart';
import '../notes/notes_page.dart';
import 'document_create_page.dart';
import 'resource_create_page.dart';

/// The selector itself never writes. Existing native editors own writes and
/// their privacy/drafts. Capture only actual acknowledgements, including IDs
/// whose metadata needs retry; never infer creation from a boolean route result.
class ResourceCreateCoordinator {
  ResourceCreateCoordinator({
    required this.notes,
    required this.articles,
    required this.bookmarks,
    required this.books,
    required this.documents,
    required this.labels,
    required this.noteDrafts,
    required this.articleDrafts,
    required this.documentDrafts,
    required this.bookmarkDrafts,
    required this.bookDrafts,
    required this.documentCreationVault,
    this.attachments,
    this.onCreateNote,
    this.onCreateArticle,
    this.isCurrent,
    this.english = false,
    this.local = false,
  });
  final NotesRepository notes, articles;
  final BookmarksRepository bookmarks;
  final BooksRepository books;
  final DocumentsRepository documents;
  final LabelsRepository labels;
  final DraftVault noteDrafts, articleDrafts, documentDrafts;
  final BookmarkDraftVault bookmarkDrafts;
  final BookDraftVault bookDrafts;
  final DocumentCreationVault documentCreationVault;
  final AttachmentRepository? attachments;
  final bool english, local;
  final Future<ResourceCreationResult?> Function(BuildContext)? onCreateNote,
      onCreateArticle;
  final bool Function()? isCurrent;
  bool current() => isCurrent?.call() ?? true;
  bool _busy = false;

  Future<ResourceCreationResult?> open(
    BuildContext context, {
    ResourceCreateKind? initialKind,
  }) async {
    if (_busy || !current()) return null;
    _busy = true;
    try {
      final kind =
          initialKind ??
          await Navigator.of(context).push<ResourceCreateKind>(
            MaterialPageRoute(
              builder: (_) => ResourceCreatePage(english: english),
            ),
          );
      if (kind == null || !context.mounted || !current()) return null;
      ResourceCreationResult? receipt;
      if (kind == ResourceCreateKind.note ||
          kind == ResourceCreateKind.article) {
        final article = kind == ResourceCreateKind.article;
        final create = article ? onCreateArticle : onCreateNote;
        if (create != null) {
          final result = await create(context);
          return context.mounted && current() ? result : null;
        }
        // There is no native article fallback: production must provide its
        // genuine WebView/retained-creation entry.
        if (article) {
          throw StateError('Article WebView creation entry required');
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => NoteEditorPage(
              repository: article ? articles : notes,
              note: const Note(title: '', content: ''),
              collection: article
                  ? NoteCollection.article
                  : NoteCollection.note,
              drafts: article ? articleDrafts : noteDrafts,
              attachments: attachments,
              english: english,
              onSaveAcknowledged: (saved, complete, created) {
                final previous = receipt;
                receipt = ResourceCreationResult(
                  kind: article
                      ? CreatedResourceKind.article
                      : CreatedResourceKind.note,
                  id: saved.id!,
                  title: saved.title,
                  created:
                      created ||
                      previous?.id == saved.id && previous?.created == true,
                  metadataComplete: complete,
                );
              },
            ),
          ),
        );
        return receipt;
      }
      if (kind == ResourceCreateKind.bookmark) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BookmarkEditorPage(
              repository: bookmarks,
              bookmark: const BookmarkItem(title: '', url: ''),
              labelsRepository: labels,
              vault: bookmarkDrafts,
              local: local,
              english: english,
              onSaveAcknowledged: (saved, complete, created) {
                final previous = receipt;
                receipt = ResourceCreationResult(
                  kind: CreatedResourceKind.bookmark,
                  id: saved.id!,
                  title: saved.title,
                  description: saved.description,
                  created:
                      created ||
                      previous?.id == saved.id && previous?.created == true,
                  metadataComplete: complete,
                );
              },
            ),
          ),
        );
        return receipt;
      }
      return await Navigator.of(context).push<ResourceCreationResult>(
        MaterialPageRoute(
          builder: (_) => DocumentCreatePage(
            controller: DocumentCreationController(
              vault: documentCreationVault,
              books: books,
              documents: documents,
            ),
            english: english,
            onOpenEditor: (context, acknowledged) async {
              // Reading is a separate navigation step. Failure keeps the known
              // created ID in the creation page, so it can only reopen that ID.
              final actual = await documents.read(acknowledged.id);
              if (actual.bookId != acknowledged.bookId ||
                  actual.type != 'markdown') {
                throw StateError(
                  'Created document is no longer editable as Markdown',
                );
              }
              final book = await books.read(actual.bookId);
              if (!context.mounted) return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => NoteEditorPage(
                    repository: DocumentEditorRepository(
                      documents,
                      actual.bookId,
                    ),
                    note: Note(
                      id: actual.id,
                      title: actual.name,
                      content: actual.markdown,
                    ),
                    documentPath: '${book.name} / ${actual.name}',
                    drafts: documentDrafts,
                    attachments: attachments,
                    english: english,
                  ),
                ),
              );
            },
            onReviewBook: _reviewBook,
          ),
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _reviewBook(BuildContext context, int bookId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChaptersPage(
          bookId: bookId,
          books: books,
          documents: documents,
          english: english,
          onSettings: (context, book) async {
            await Navigator.of(context).push<bool>(
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
          onOpen: (context, id) async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => DocumentReaderPage(
                  bookId: bookId,
                  documentId: id,
                  books: books,
                  documents: documents,
                  drafts: documentDrafts,
                  attachments: attachments,
                  english: english,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
