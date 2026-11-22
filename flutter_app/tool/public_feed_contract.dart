import 'package:bookstark_flutter/core/document_creation.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/public_feed_models.dart';
import 'package:bookstark_flutter/core/public_feed_repository.dart';

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runPublicFeedContract(BookstarkClient client, int memberId) async {
  final books = RemoteBooksRepository(client);
  final documents = RemoteDocumentsRepository(client);
  final bookId = await books.save(const BookItem(name: '文档创建状态契约'));
  try {
    final parent = (await documents.tree(bookId)).single;
    final values = <String, String>{};
    final vault = DocumentCreationVault(
      namespace: 'disposable-contract',
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    final creation = DocumentCreationController(
      vault: vault,
      books: books,
      documents: documents,
    );
    await creation.initialize(
      initial: DocumentCreationDraft(
        bookId: bookId,
        parentId: parent.id,
        name: '实际文档 📚 & %2F',
      ),
    );
    final actual = await creation.create();
    _require(
      actual.id > 0 &&
          actual.bookId == bookId &&
          actual.parentId == parent.id &&
          actual.name == '实际文档 📚 & %2F',
      'Actual document create receipt and parent identity',
    );
    final restored = DocumentCreationController(
      vault: vault,
      books: books,
      documents: documents,
    );
    await restored.initialize();
    _require(
      restored.acknowledged.id == actual.id,
      'Actual created ID survives secure record restore',
    );
    var blocked = false;
    try {
      await restored.create();
    } on StateError {
      blocked = true;
    }
    _require(
      blocked && flattenDocuments(await documents.tree(bookId)).length == 2,
      'Acknowledged creation cannot POST again',
    );
    stdout.writeln(
      'PASS production document creation: actual nested receipt, literal Unicode name, durable ID and no duplicate create after restore',
    );
  } finally {
    await books.remove(bookId);
  }
  final feed = RemotePublicFeedRepository(client);
  final notes = RemoteNotesRepository(client);
  final articles = RemoteNotesRepository(
    client,
    collection: NoteCollection.article,
  );
  final bookmarks = RemoteBookmarksRepository(
    client,
    memberId: memberId,
    isAdmin: true,
  );
  const label = '广场精确&标签📚';
  const commaLabel = '书签,精确&标签📚';
  final noteId = await notes.save(
    const Note(title: '公开广场契约笔记', content: '实际公开正文', labels: [label]),
  );
  final articleId = await articles.save(
    const Note(title: '公开广场契约文章', content: '实际文章摘要', labels: [label]),
  );
  final bookmarkId = await bookmarks.save(
    const BookmarkItem(
      title: '公开广场契约书签',
      url: 'https://example.invalid/public-feed',
      labels: [label, commaLabel],
      isPublic: true,
    ),
  );
  try {
    for (final id in [noteId, articleId]) {
      final visibility = await client.mutate(
        'PATCH',
        '/api/blogs/$id/visibility',
        {},
      );
      _require(
        visibility['visibility'] == 1,
        'Public fixture visibility is real',
      );
    }
    for (final kind in PublicFeedKind.values) {
      for (final sort in PublicFeedSort.values) {
        final page = await feed.load(
          PublicFeedQuery(kind: kind, sort: sort, label: label),
        );
        _require(page.query.sort == sort, 'Actual public sort retained');
        _require(
          page.categories.any((c) => c.label.isEmpty),
          'Actual global unfiltered category',
        );
        if (kind != PublicFeedKind.book) {
          _require(
            page.items.length == 1 && page.items.single.labels.contains(label),
            'Actual type and exact Unicode comma ampersand label filtering: $kind',
          );
          _require(
            page.categories.any((c) => c.label == label && c.selected),
            'Actual global exact category',
          );
        }
      }
    }
    final commaPage = await feed.load(
      PublicFeedQuery(kind: PublicFeedKind.bookmark, label: commaLabel),
    );
    _require(
      commaPage.items.length == 1 &&
          commaPage.items.single.labels.contains(commaLabel),
      'Actual bookmark comma label remains one category',
    );
    final searched = await feed.load(
      PublicFeedQuery(kind: PublicFeedKind.note, keyword: '公开广场契约笔记'),
    );
    _require(
      searched.items.length == 1 && searched.items.single.title == '公开广场契约笔记',
      'Actual public notes JSON title and keyword',
    );
    await client.mutate('PUT', '/api/blogs/$noteId', {
      'new_password': 'fixture-only',
    });
    final locked = await feed.load(
      PublicFeedQuery(kind: PublicFeedKind.note, keyword: '公开广场契约笔记'),
    );
    _require(
      locked.items.length == 1 &&
          locked.items.single.locked &&
          locked.items.single.excerpt.isEmpty &&
          locked.items.single.labels.isEmpty,
      'Actual encrypted public notes have no protected fields',
    );
    stdout.writeln(
      'PASS production public feed: four real HTML type branches, exact Unicode/comma/ampersand category, both sort requests, keyword, inert note JSON and encrypted-field exclusion',
    );
  } finally {
    await notes.remove(noteId);
    await articles.remove(articleId);
    await bookmarks.remove(bookmarkId);
  }
}
