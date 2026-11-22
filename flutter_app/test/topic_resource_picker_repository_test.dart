import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/topic_resource_picker_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/books.dart';
import '../tool/fixtures/bookmarks.dart';
import '../tool/fixtures/tasks.dart';

class MetadataNotes implements NotesRepository {
  MetadataNotes(this.rows);
  final List<Note> rows;
  int reads = 0, writes = 0;
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async =>
      page == 1
      ? rows.where((row) => row.title.contains(keyword)).toList()
      : [];
  @override
  Future<Note> read(int id) async {
    reads++;
    throw StateError('Picker must not read or unlock content');
  }

  @override
  Future<int> save(Note note) async {
    writes++;
    throw StateError('Picker must not save notes');
  }

  @override
  Future<void> remove(int id) async {
    writes++;
    throw StateError('Picker must not delete notes');
  }
}

void main() {
  test(
    'resource picker uses metadata without unlocking protected content or writing sources',
    () async {
      final notes = MetadataNotes([
        const Note(id: 11, title: '普通笔记', content: '真实正文📖'),
        const Note(
          id: 12,
          title: '受保护',
          content: 'CIPHERTEXT',
          isProtected: true,
        ),
      ]);
      final articles = MetadataNotes([
        const Note(id: 21, title: '文章', content: '文章正文'),
      ]);
      final repo = ExistingTopicResourcePickerRepository(
        notes: notes,
        articles: articles,
        bookRepository: BooksFixture(),
        documents: DocumentsFixture(),
        bookmarks: BookmarksFixture(),
        tasks: TaskFixture(),
      );
      final result = await repo.list(TopicResourceType.note);
      expect(result.items.first.description, '真实正文📖');
      expect(result.total, isNull);
      expect(result.hasMore, isTrue);
      final protected = result.items.last;
      expect(protected.protected, isTrue);
      expect(protected.description, isEmpty);
      expect(
        protected.forTopic(4).writeBody()['desc_snapshot'],
        '受保护笔记 / Protected note',
      );
      expect(notes.reads, 0);
      expect(notes.writes, 0);
      expect(
        (await repo.list(TopicResourceType.note, page: 2)).hasMore,
        isFalse,
      );
      expect((await repo.list(TopicResourceType.article)).items.single.id, 21);
      expect(articles.reads, 0);
    },
  );
  test(
    'document candidates require a real book and come from actual chapter tree',
    () async {
      final empty = MetadataNotes([]);
      final repo = ExistingTopicResourcePickerRepository(
        notes: empty,
        articles: empty,
        bookRepository: BooksFixture(),
        documents: DocumentsFixture(),
        bookmarks: BookmarksFixture(),
        tasks: TaskFixture(),
      );
      await expectLater(
        repo.list(TopicResourceType.document),
        throwsFormatException,
      );
      final books = await repo.books(keyword: '阅读');
      expect(books.items, isNotEmpty);
      final result = await repo.list(TopicResourceType.document, bookId: 1);
      expect(result.items, isNotEmpty);
      expect(result.hasMore, isFalse);
      expect(
        result.items.every(
          (item) => item.type == TopicResourceType.document && item.id > 0,
        ),
        isTrue,
      );
      expect(result.total, result.items.length);
      final bookmarks = await repo.list(TopicResourceType.bookmark);
      expect(bookmarks.total, 3);
      expect(
        bookmarks.items.singleWhere((item) => item.id == 1).title,
        'Flutter 开发文档',
      );
    },
  );
}
