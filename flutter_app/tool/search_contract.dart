import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runSearchContract(BookstarkClient client, int memberId) async {
  const q = '搜索契约';
  final search = RemoteSearchRepository(client),
      labels = RemoteLabelManagementRepository(client, canManage: true);
  final books = RemoteBooksRepository(client),
      documents = RemoteDocumentsRepository(client);
  final notes = RemoteNotesRepository(client),
      articles = RemoteNotesRepository(
        client,
        collection: NoteCollection.article,
      );
  final bookmarks = RemoteBookmarksRepository(
        client,
        memberId: memberId,
        isAdmin: true,
      ),
      tasks = RemoteTasksRepository(client),
      topics = RemoteTopicsRepository(client, memberId: memberId);
  final label = await labels.save(q);
  final bookId = await books.save(const BookItem(name: '搜索契约书籍', labels: [q]));
  final documentId = (await documents.tree(bookId)).single.id;
  await documents.saveMarkdown(documentId, '# 搜索契约文档正文');
  final noteId = await notes.save(const Note(title: '搜索契约笔记', content: '正文'));
  final articleId = await articles.save(
    const Note(title: '搜索契约文章', content: '正文'),
  );
  final bookmarkId = await bookmarks.save(
    const BookmarkItem(
      title: '搜索契约书签',
      url: 'https://example.invalid/search-contract',
    ),
  );
  final topicId = await topics.save(
    const TopicItem(title: '普通主题', question: '搜索契约问题'),
  );
  final taskId = await tasks.save(
    TaskItem(content: '搜索契约待办', dueDate: '2026-11-08', topicId: topicId),
  );
  final result = await search.search(q);
  _require(
    result.loaded == 8 && result.groups.values.every((rows) => rows.isNotEmpty),
    'Search returns seven real types and only loaded counts',
  );
  _require(
    result.groups[SearchKind.blog]!
        .map((row) => row.blogType)
        .toSet()
        .containsAll({'note', 'article'}),
    'Search distinguishes actual blog collections',
  );
  _require(
    result.groups[SearchKind.document]!.single.id == documentId &&
        result.groups[SearchKind.label]!.single.id == label.id,
    'Search retains actual document and global label IDs',
  );
  final literalId = await notes.save(
    const Note(title: '字面100%_\\保留', content: '正文'),
  );
  final literal = await search.search('%_\\');
  _require(
    literal.groups[SearchKind.blog]!.single.id == literalId,
    'Go search escapes literal percent, underscore and backslash',
  );
  final protectedId = await notes.save(
    const Note(title: '受保护检索契约', content: 'privateSearchNeedle'),
  );
  await client.mutate('PUT', '/api/blogs/$protectedId', {
    'blog_title': '受保护检索契约',
    'blog_content': 'privateSearchNeedle',
    'new_password': 'fixture-only',
  });
  _require(
    (await client.get('/api/blogs/$protectedId'))['has_password'] == true,
    'Fixture is actually encrypted before testing search exclusion',
  );
  _require(
    (await search.search(
      'privateSearchNeedle',
    )).groups[SearchKind.blog]!.isEmpty,
    'Encrypted note content cannot match global search',
  );
  final masked = (await search.search(
    '受保护检索契约',
  )).groups[SearchKind.blog]!.single;
  _require(
    masked.id == protectedId && masked.snippet.isEmpty,
    'Protected title may match but encrypted snippet stays empty',
  );
  final cappedIds = <int>[];
  for (var i = 0; i < 21; i++) {
    cappedIds.add(
      await tasks.save(TaskItem(content: '截断契约$i', dueDate: '2026-11-08')),
    );
  }
  final capped = await search.search('截断契约');
  _require(
    capped.groups[SearchKind.task]!.length == 20 && capped.loaded == 20,
    'Actual Go caps each group at twenty without total-page metadata',
  );
  for (final id in cappedIds) {
    await tasks.remove(id);
  }
  await notes.remove(literalId);
  await notes.remove(protectedId);
  await notes.remove(noteId);
  await articles.remove(articleId);
  await bookmarks.remove(bookmarkId);
  await books.remove(bookId);
  await tasks.remove(taskId);
  await topics.remove(topicId);
  await labels.remove(label.id);
}
