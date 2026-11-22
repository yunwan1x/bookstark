import 'documents_repository.dart';
import 'notes_repository.dart';

/// Reuse the tested Markdown editor's attachments, drafts and race handling.
/// Document writes keep their own API and never acquire blog labels or type.
class DocumentEditorRepository implements NotesRepository {
  DocumentEditorRepository(
    this.documents,
    this.bookId, {
    this.boundedReader,
    this.isCurrentScope,
  });
  final BoundedDocumentsReader? boundedReader;
  final bool Function()? isCurrentScope;
  void _guard() {
    if (!(isCurrentScope?.call() ?? true)) {
      throw StateError('Document editor scope retired');
    }
  }

  final DocumentsRepository documents;
  final int bookId;
  @override
  Future<Note> read(int id) async {
    _guard();
    final item = boundedReader == null
        ? await documents.read(id)
        : (await boundedReader!.readBounded(
            id,
            bookId: bookId,
            maxMarkdownReadBytes: documentMarkdownEditBytes,
          )).item;
    _guard();
    if (item.bookId != bookId || item.type != 'markdown') {
      throw StateError('Invalid Markdown document');
    }
    return Note(id: id, title: item.name, content: item.markdown);
  }

  @override
  Future<int> save(Note note) async {
    _guard();
    final id = note.id;
    if (id == null) {
      throw StateError('Create the document from its chapter first');
    }
    validateDocumentName(note.title);
    final previous = await read(id);
    try {
      _guard();
      if (previous.title != note.title) await documents.rename(id, note.title);
      _guard();
      if (previous.content != note.content) {
        await documents.saveMarkdown(id, note.content);
      }
      _guard();
      final actual = await read(id);
      if (actual.title != note.title || actual.content != note.content) {
        throw StateError('文档保存核对失败 / Saved document verification failed');
      }
    } catch (error) {
      throw NoteSaveFailure(id, error.toString());
    }
    return id;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async =>
      throw UnsupportedError('Documents are listed by chapter, not as notes');
  @override
  Future<void> remove(int id) async =>
      throw UnsupportedError('Delete documents from the chapter menu');
}
