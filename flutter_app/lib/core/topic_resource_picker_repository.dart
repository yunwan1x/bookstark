import 'books_repository.dart';
import 'bookmarks_repository.dart';
import 'documents_repository.dart';
import 'notes_repository.dart';
import 'note_list_source.dart';
import 'note_list_query.dart';
import 'tasks_repository.dart';
import 'topics_repository.dart';

class TopicResourceCandidate {
  const TopicResourceCandidate({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    this.protected = false,
  });
  final int id;
  final TopicResourceType type;
  final String title, description;
  final bool protected;
  (TopicResourceType, int) get key => (type, id);
  TopicResource forTopic(int topicId) => TopicResource(
    topicId: topicId,
    type: type,
    targetId: id,
    title: title,
    // A protected note is selected by metadata; never trigger decryption or
    // let the server substitute an encrypted blog_content fragment as preview.
    description: protected ? '受保护笔记 / Protected note' : description,
  );
}

class TopicResourceCandidatesPage {
  const TopicResourceCandidatesPage(
    this.items, {
    required this.hasMore,
    this.total,
  });
  final List<TopicResourceCandidate> items;
  final bool hasMore;
  final int? total;
}

abstract interface class TopicResourcePickerRepository {
  Future<BooksPageResult> books({String keyword = '', int page = 1});
  Future<TopicResourceCandidatesPage> list(
    TopicResourceType type, {
    String keyword = '',
    int page = 1,
    int? bookId,
  });
}

class ExistingTopicResourcePickerRepository
    implements TopicResourcePickerRepository {
  ExistingTopicResourcePickerRepository({
    required this.notes,
    required this.articles,
    required this.bookRepository,
    required this.documents,
    required this.bookmarks,
    required this.tasks,
    this.noteMetadata,
    this.articleMetadata,
  });
  final NotesRepository notes, articles;
  final NoteListSource? noteMetadata, articleMetadata;
  final BooksRepository bookRepository;
  final DocumentsRepository documents;
  final BookmarksRepository bookmarks;
  final TasksRepository tasks;
  @override
  Future<BooksPageResult> books({String keyword = '', int page = 1}) =>
      bookRepository.list(keyword: keyword, page: page);
  @override
  Future<TopicResourceCandidatesPage> list(
    TopicResourceType type, {
    String keyword = '',
    int page = 1,
    int? bookId,
  }) async {
    if (page < 1) throw const FormatException('Invalid picker page');
    switch (type) {
      case TopicResourceType.note:
      case TopicResourceType.article:
        final metadata = type == TopicResourceType.note
            ? noteMetadata
            : articleMetadata;
        if (metadata != null) {
          final result = await metadata.list(
            NoteListQuery(
              collection: type == TopicResourceType.note ? 'note' : 'article',
              keyword: keyword,
            ),
            page: page,
          );
          if (result.page != page ||
              result.items.any((row) => row.id <= 0) ||
              result.items.map((row) => row.id).toSet().length !=
                  result.items.length) {
            throw const FormatException('Invalid note metadata candidate page');
          }
          return TopicResourceCandidatesPage(
            List.unmodifiable([
              for (final row in result.items)
                TopicResourceCandidate(
                  id: row.id,
                  type: type,
                  title: row.title,
                  description: row.isProtected
                      ? ''
                      : String.fromCharCodes(
                          row.contentPreview.runes.take(200),
                        ),
                  protected: row.isProtected,
                ),
            ]),
            hasMore: result.hasMore,
            total: result.total,
          );
        }
        final rows = await (type == TopicResourceType.note ? notes : articles)
            .list(keyword: keyword, page: page);
        if (rows.any((row) => row.id == null || row.id! <= 0)) {
          throw const FormatException('Invalid note candidate');
        }
        return TopicResourceCandidatesPage(
          List.unmodifiable(
            rows.map(
              (row) => TopicResourceCandidate(
                id: row.id!,
                type: type,
                title: row.title,
                description: row.isProtected
                    ? ''
                    : String.fromCharCodes(row.content.runes.take(200)),
                protected: row.isProtected,
              ),
            ),
          ),
          hasMore: rows.isNotEmpty,
        );
      case TopicResourceType.bookmark:
        final result = await bookmarks.list(
          BookmarkQuery(keyword: keyword, page: page),
        );
        if (result.items.any(
          (row) =>
              row.id == null ||
              row.id! <= 0 ||
              row.memberId != bookmarks.memberId,
        )) {
          throw const FormatException('Invalid owned bookmark candidate');
        }
        return TopicResourceCandidatesPage(
          List.unmodifiable(
            result.items.map(
              (row) => TopicResourceCandidate(
                id: row.id!,
                type: type,
                title: row.title,
                description: row.description,
              ),
            ),
          ),
          hasMore: result.hasMore,
          total: result.total,
        );
      case TopicResourceType.task:
        final result = await tasks.list(
          TaskQuery(keyword: keyword, page: page, pageSize: 100),
        );
        return TopicResourceCandidatesPage(
          List.unmodifiable(
            result.items.map(
              (row) => TopicResourceCandidate(
                id: row.id!,
                type: type,
                title: String.fromCharCodes(row.content.runes.take(500)),
              ),
            ),
          ),
          hasMore: result.hasMore,
          total: result.total,
        );
      case TopicResourceType.document:
        if (bookId == null || bookId <= 0) {
          throw const FormatException('请先选择书籍 / Choose a book first');
        }
        if (page > 1) {
          throw const FormatException('Document candidates are not paginated');
        }
        final roots = await documents.tree(bookId);
        final rows = <TopicResourceCandidate>[];
        void walk(List<DocumentNode> nodes, List<String> path, int depth) {
          if (depth > 256) {
            throw const FormatException('Document tree too deep');
          }
          for (final node in nodes) {
            if (node.name.toLowerCase().contains(keyword.toLowerCase())) {
              rows.add(
                TopicResourceCandidate(
                  id: node.id,
                  type: type,
                  title: node.name,
                  description: path.join(' / '),
                ),
              );
            }
            walk(node.children, [...path, node.name], depth + 1);
          }
        }
        walk(roots, [], 0);
        return TopicResourceCandidatesPage(
          List.unmodifiable(rows),
          hasMore: false,
          total: rows.length,
        );
    }
  }
}
