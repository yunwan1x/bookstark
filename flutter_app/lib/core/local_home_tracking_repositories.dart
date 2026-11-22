import 'books_repository.dart';
import 'documents_repository.dart';
import 'local_books_repository.dart';
import 'local_documents_repository.dart';
import 'notes_repository.dart';

typedef LocalHomeResourceOpened = Future<void> Function(String kind, int id);

Future<void> _record(
  LocalHomeResourceOpened callback,
  String kind,
  int id,
) async {
  // Optional visit metadata must never prevent access to the original resource.
  // A preferences failure is surfaced by the home preferences reader/reset UI.
  try {
    await callback(kind, id);
  } catch (_) {}
}

/// Keep the actual LocalNotesRepository type: complex editor dispatch relies on
/// it to select the existing local WebView engines instead of native Markdown.
class HomeLocalNotesRepository extends LocalNotesRepository {
  HomeLocalNotesRepository(
    super.store, {
    super.collection,
    required this.onOpened,
  });
  final LocalHomeResourceOpened onOpened;
  @override
  Future<String> editorTypeOf(int id) async {
    final type = await super.editorTypeOf(id);
    await _record(onOpened, collection.name, id);
    return type;
  }

  @override
  Future<Note> read(int id) async {
    try {
      final note = await super.read(id);
      await _record(onOpened, collection.name, id);
      return note;
    } on DedicatedEditorRequired {
      await _record(onOpened, collection.name, id);
      rethrow;
    }
  }
}

class HomeLocalBooksRepository extends LocalBooksRepository {
  HomeLocalBooksRepository(super.store, {required this.onOpened});
  final LocalHomeResourceOpened onOpened;
  @override
  Future<BookItem> read(int id) async {
    final value = await super.read(id);
    await _record(onOpened, 'book', id);
    return value;
  }
}

class HomeLocalDocumentsRepository extends LocalDocumentsRepository {
  HomeLocalDocumentsRepository(super.store, {required this.onOpened});
  final LocalHomeResourceOpened onOpened;
  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) async {
    final value = await super.readBounded(
      id,
      bookId: bookId,
      maxMarkdownReadBytes: maxMarkdownReadBytes,
    );
    await _record(onOpened, 'document', id);
    return value;
  }

  @override
  Future<DocumentItem> read(int id) async {
    final value = await super.read(id);
    await _record(onOpened, 'document', id);
    return value;
  }
}
