import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/features/navigation/native_resource_opener.dart';
import '../tool/fixtures/books.dart';
import '../tool/fixtures/bookmarks.dart';
import '../tool/fixtures/tasks.dart';

class _UnreadArticles extends NotesRepository {
  int reads = 0;
  @override
  Future<Note> read(int id) async {
    reads++;
    throw StateError('Article must not enter native Markdown repository');
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<int> save(Note note) async => throw StateError('Unexpected save');
  @override
  Future<void> remove(int id) async => throw StateError('Unexpected delete');
}

void main() {
  testWidgets(
    'article/topic and resolved label use typed callback before native read',
    (tester) async {
      late BuildContext context;
      final articles = _UnreadArticles();
      final opened = <int>[];
      final opener = NativeResourceOpener(
        notes: _UnreadArticles(),
        articles: articles,
        books: BooksFixture(),
        documents: DocumentsFixture(),
        tasks: TaskFixture(),
        bookmarks: BookmarksFixture(),
        labels: LabelsFixture(),
        server: Uri.parse('https://example.test'),
        openArticle: (_, id) async => opened.add(id),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      await opener.open(context, TopicResourceType.article, 19);
      await opener.openLabel(
        context,
        const LabelResource(
          id: 20,
          type: LabelResourceType.blog,
          title: 'Article',
        ),
        resolveCollection: (_) async => NoteCollection.article,
      );
      expect(opened, [19, 20]);
      expect(articles.reads, 0);
      await expectLater(
        opener.open(context, TopicResourceType.article, -1),
        throwsFormatException,
      );
      expect(opened, [19, 20]);
    },
  );
}
