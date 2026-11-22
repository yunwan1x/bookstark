import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_trash_repository.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/local_topics_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  Future<LocalStore> setup() async {
    final directory = await Directory.systemTemp.createTemp('bookstark-trash-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    return store;
  }

  test(
    'legacy soft-deleted notes and articles list without invented deletion time, restore exact original ID/body/labels',
    () async {
      final store = await setup();
      final id = await store.createNote('旧笔记', '# 原始正文', labels: ['保留']);
      await store.deleteNote(id);
      final article = await store.createNote(
        '旧文章',
        '文章内容',
        collection: 'article',
      );
      await store.deleteNote(article, collection: 'article');
      final r = LocalTrashRepository(store);
      final data = await r.read(type: 'blog');
      expect(data.total, 2);
      expect(data.entries.every((v) => v.id < 0 && v.deletedAt.isEmpty), true);
      await r.apply(
        data.entries.singleWhere((v) => v.id == -id),
        TrashOperation.restore,
      );
      final actual = await store.readNote(id);
      expect(actual['content'], '# 原始正文');
      expect(actual['labels'], '["保留"]');
      await r.apply(
        data.entries.singleWhere((v) => v.id == -article),
        TrashOperation.delete,
      );
      expect(
        (await (await store.database).query(
          'notes',
          where: 'id = ?',
          whereArgs: [article],
        )),
        isEmpty,
      );
      r.dispose();
    },
  );
  test(
    'article name conflict rolls back restoration and retains original trash row and body',
    () async {
      final store = await setup();
      final old = await store.createNote('同名', '旧正文', collection: 'article');
      await store.deleteNote(old, collection: 'article');
      final active = await store.createNote(
        '同名',
        '活跃正文',
        collection: 'article',
      );
      final r = LocalTrashRepository(store);
      final row = (await r.read()).entries.single;
      await expectLater(
        r.apply(row, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await r.isAbsent(row), false);
      expect(
        (await store.readNote(active, collection: 'article'))['content'],
        '活跃正文',
      );
      r.dispose();
    },
  );
  test(
    'whole book restore retains original document tree IDs, Markdown, labels and accurate counts',
    () async {
      final store = await setup();
      final books = LocalBooksRepository(store),
          docs = LocalDocumentsRepository(store);
      final book = await books.save(
        const BookItem(name: '整书', labels: ['真实标签']),
      );
      final parent = await docs.create(book, '章');
      final child = await docs.create(book, '节', parentId: parent.id);
      await docs.saveMarkdown(child.id, '# 保留树');
      await books.remove(book);
      final r = LocalTrashRepository(store);
      final row = (await r.read(type: 'book')).entries.single;
      await r.apply(row, TrashOperation.restore);
      expect(await r.isAbsent(row), true);
      expect((await books.read(book)).documentCount, 3);
      expect((await books.read(book)).labels, ['真实标签']);
      expect((await docs.read(child.id)).markdown, '# 保留树');
      expect((await docs.read(child.id)).parentId, parent.id);
      r.dispose();
    },
  );
  test(
    'document restore rejects missing parent then succeeds after parent restore and recomputes count',
    () async {
      final store = await setup();
      final books = LocalBooksRepository(store),
          docs = LocalDocumentsRepository(store);
      final book = await books.save(const BookItem(name: '依赖'));
      final parent = await docs.create(book, '章');
      final child = await docs.create(book, '节', parentId: parent.id);
      await docs.remove(child.id);
      await docs.remove(parent.id);
      final r = LocalTrashRepository(store);
      final rows = (await r.read(type: 'document')).entries;
      final childRow = rows.singleWhere((v) => v.name == '节'),
          parentRow = rows.singleWhere((v) => v.name == '章');
      await expectLater(
        r.apply(childRow, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await r.isAbsent(childRow), false);
      await r.apply(parentRow, TrashOperation.restore);
      await r.apply(childRow, TrashOperation.restore);
      expect((await books.read(book)).documentCount, 3);
      r.dispose();
    },
  );
  test(
    'task subtree restores original IDs and parent relationships then permanent delete removes only deleted subtree',
    () async {
      final store = await setup();
      final tasks = LocalTasksRepository(store);
      final root = await tasks.save(
        const TaskItem(content: '根', dueDate: '2026-11-05'),
      );
      final child = await tasks.save(
        TaskItem(content: '子', dueDate: '2026-11-05', parentId: root),
      );
      final survivor = await tasks.save(
        const TaskItem(content: '保留', dueDate: '2026-11-05'),
      );
      await tasks.remove(root);
      final r = LocalTrashRepository(store);
      await r.apply(
        (await r.read(type: 'task')).entries.single,
        TrashOperation.restore,
      );
      expect((await tasks.read(child)).parentId, root);
      await tasks.remove(root);
      await r.apply(
        (await r.read(type: 'task')).entries.single,
        TrashOperation.delete,
      );
      expect(
        (await (await store.database).query(
          'tasks',
          where: 'task_id IN (?,?)',
          whereArgs: [root, child],
        )),
        isEmpty,
      );
      expect((await tasks.read(survivor)).content, '保留');
      r.dispose();
    },
  );
  test(
    'topic restore recreates summaries resources comments and tasks with original IDs transactionally',
    () async {
      final store = await setup();
      final topics = LocalTopicsRepository(store),
          tasks = LocalTasksRepository(store),
          bookmarks = LocalBookmarksRepository(store);
      final source = await bookmarks.save(
        const BookmarkItem(title: '来源', url: 'https://example.test/'),
      );
      final topic = await topics.save(const TopicItem(title: '专题'));
      final summary = await topics.saveSummary(
        TopicSummary(topicId: topic, content: '# 原文'),
      );
      final resource = await topics.addResource(
        TopicResource(
          topicId: topic,
          type: TopicResourceType.bookmark,
          targetId: source,
        ),
      );
      final comment = await topics.saveComment(
        TopicComment(
          topicId: topic,
          target: TopicCommentTarget.resource,
          targetId: resource.id!,
          content: '**批注**',
        ),
      );
      final task = await tasks.save(
        TaskItem(content: '关联任务', dueDate: '2026-11-05', topicId: topic),
      );
      await topics.remove(topic);
      final r = LocalTrashRepository(store);
      await r.apply(
        (await r.read(type: 'topic')).entries.single,
        TrashOperation.restore,
      );
      final actual = await topics.read(topic);
      expect(actual.summaries.single.id, summary.id);
      expect(actual.summaries.single.content, '# 原文');
      expect(actual.resources.single.id, resource.id);
      expect((await topics.comments(topic)).items.single.id, comment.id);
      expect((await tasks.read(task)).topicId, topic);
      expect((await bookmarks.read(source)).title, '来源');
      r.dispose();
    },
  );
  test(
    'bookmark uniqueness conflict and changed active snapshot never overwrite live records',
    () async {
      final store = await setup();
      final bookmarks = LocalBookmarksRepository(store);
      final old = await bookmarks.save(
        const BookmarkItem(title: '旧', url: 'https://example.test/'),
      );
      await bookmarks.remove(old);
      final active = await bookmarks.save(
        const BookmarkItem(title: '新', url: 'https://example.test/'),
      );
      final r = LocalTrashRepository(store);
      final row = (await r.read(type: 'bookmark')).entries.single;
      await expectLater(
        r.apply(row, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await r.isAbsent(row), false);
      expect((await bookmarks.read(active)).title, '新');
      await (await store.database).update(
        'bookmarks',
        {'deleted': 0, 'url': 'https://other.test/'},
        where: 'bookmark_id = ?',
        whereArgs: [old],
      );
      await expectLater(
        r.apply(row, TrashOperation.delete),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect((await bookmarks.read(old)).title, '旧');
      r.dispose();
    },
  );
}
