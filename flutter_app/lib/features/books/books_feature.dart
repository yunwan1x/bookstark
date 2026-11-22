import '../speech/local_speech_provider_page.dart';
import '../../core/document_excerpt_request.dart';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/books_repository.dart';
import '../../core/book_draft_vault.dart';
import '../../core/documents_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../core/notes_repository.dart';
import '../../core/reading_position_vault.dart';
import '../notes/notes_page.dart';
import 'book_editor_page.dart';
import 'books_page.dart';
import 'chapters_page.dart';
import 'document_reader_page.dart';

class BooksFeature extends StatelessWidget {
  const BooksFeature({
    super.key,
    required this.books,
    required this.documents,
    required this.labels,
    this.bookDrafts,
    this.documentDrafts,
    this.attachments,
    this.english = false,
    this.notes,
    this.excerptDrafts,
    this.positions,
    this.server,
    this.onSpeak,
    this.onSpeakSelection,
    this.onShareBook,
    this.onShareDocument,
    this.onCreateBook,
    this.ownerScope,
    this.isCurrentScope,
    this.onEditComplexDocument,
    this.boundedReader,
    this.readingFingerprint,
    this.onCreateExcerpt,
  });
  final Future<void> Function(BuildContext, BookItem)? onShareBook;
  final Future<void> Function(BuildContext, DocumentItem)? onShareDocument;
  final Future<void> Function(
    BuildContext,
    BooksRepository,
    LabelsRepository,
    BookDraftVault?,
  )?
  onCreateBook;
  final Object? ownerScope;
  final bool Function()? isCurrentScope;
  final Future<void> Function(BuildContext, int bookId, DocumentItem)?
  onEditComplexDocument;
  final BoundedDocumentsReader? boundedReader;
  final Future<String?> Function(TypedDocumentRead)? readingFingerprint;
  final Future<void> Function(BuildContext, DocumentExcerptRequest)?
  onCreateExcerpt;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final BooksRepository books;
  final DocumentsRepository documents;
  final LabelsRepository labels;
  final BookDraftVault? bookDrafts;
  final DraftVault? documentDrafts;
  final AttachmentRepository? attachments;
  final bool english;
  final NotesRepository? notes;
  final DraftVault Function(int documentId)? excerptDrafts;
  final ReadingPositionVault? positions;
  final Uri? server;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  @override
  Widget build(BuildContext context) => BooksPage(
    repository: books,
    onCreate: onCreateBook == null
        ? null
        : (context) => onCreateBook!(context, books, labels, bookDrafts),
    onShareSettings: onShareBook,
    labelsRepository: labels,
    vault: bookDrafts,
    english: english,
    onOpen: (context, book) async {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChaptersPage(
            isCurrentScope: isCurrentScope,
            bookId: book.id!,
            books: books,
            documents: documents,
            english: english,
            onSettings: (context, detail) async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => BookEditorPage(
                    repository: books,
                    ownerScope: ownerScope,
                    isCurrentScope: isCurrentScope,
                    book: detail,
                    labelsRepository: labels,
                    vault: bookDrafts,
                    english: english,
                  ),
                ),
              );
            },
            onOpen: (context, id) async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentReaderPage(
                    bookId: book.id!,
                    onEditComplex: onEditComplexDocument == null
                        ? null
                        : (context, item) =>
                              onEditComplexDocument!(context, book.id!, item),
                    documentId: id,
                    boundedReader: boundedReader,
                    readingFingerprint: readingFingerprint,
                    onExcerptRequest: onCreateExcerpt,
                    isCurrentScope: isCurrentScope,
                    onShareSettings: onShareDocument == null
                        ? null
                        : (item) => onShareDocument!(context, item),
                    onSpeak: onSpeak,
                    onSpeakSelection: onSpeakSelection,
                    positions: positions,
                    server: server,
                    onExcerpt: notes == null
                        ? null
                        : (context, note, id) async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NoteEditorPage(
                                  repository: notes!,
                                  note: note,
                                  drafts: excerptDrafts?.call(id),
                                  attachments: attachments,
                                  english: english,
                                ),
                              ),
                            );
                          },
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
    },
  );
}
