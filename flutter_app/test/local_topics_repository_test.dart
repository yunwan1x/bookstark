import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_topics_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    final directory = await Directory.systemTemp.createTemp(
      'bookstark-topics-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    return store;
  }

  test(
    'local topic search includes summaries and task content with literal wildcards',
    () async {
      final store = await setup();
      final repo = LocalTopicsRepository(store);
      final id = await repo.save(
        const TopicItem(title: ' 阅读 ', question: ' 问题 ', isPinned: true),
      );
      await repo.saveSummary(
        TopicSummary(topicId: id, content: '小结100%_保留', type: 'ai', order: 5),
      );
      await LocalTasksRepository(
        store,
      ).save(TaskItem(content: '实际关联的任务', dueDate: '2026-11-04', topicId: id));
      expect(
        (await repo.list(const TopicQuery(keyword: '%_'))).items.single.id,
        id,
      );
      expect(
        (await repo.list(
          const TopicQuery(keyword: '实际关联'),
        )).items.single.taskCount,
        1,
      );
      await store.close();
      final detail = await repo.read(id);
      expect(detail.topic.title, '阅读');
      expect(detail.summaries.single.type, 'ai');
      expect(detail.summaries.single.order, 5);
      await repo.sortSummaries(id, {detail.summaries.single.id!: 12});
      expect((await repo.read(id)).summaries.single.order, 12);
    },
  );
  test(
    'resource association and comment deletion preserve source records',
    () async {
      final store = await setup();
      final repo = LocalTopicsRepository(store);
      final bookmarks = LocalBookmarksRepository(store);
      final sourceId = await bookmarks.save(
        const BookmarkItem(
          title: '源书签',
          url: 'https://example.test/',
          description: '来源说明',
        ),
      );
      final id = await repo.save(const TopicItem(title: '主题'));
      final resource = await repo.addResource(
        TopicResource(
          topicId: id,
          type: TopicResourceType.bookmark,
          targetId: sourceId,
        ),
      );
      expect(resource.title, '源书签');
      expect(resource.description, '来源说明');
      await expectLater(
        repo.addResource(
          TopicResource(
            topicId: id,
            type: TopicResourceType.bookmark,
            targetId: sourceId,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      final comment = await repo.saveComment(
        TopicComment(
          topicId: id,
          target: TopicCommentTarget.resource,
          targetId: resource.id!,
          content: '**记录**',
        ),
      );
      expect((await repo.read(id)).resources.single.commentCount, 1);
      await repo.saveComment(
        TopicComment(
          id: comment.id,
          topicId: id,
          target: comment.target,
          targetId: comment.targetId,
          content: '更改内容',
        ),
      );
      expect((await repo.comments(id)).items.single.content, '更改内容');
      await repo.removeResource(id, resource.id!);
      expect((await repo.comments(id)).total, 0);
      expect(await bookmarks.findByUrl('https://example.test/'), isNotNull);
      await expectLater(
        repo.saveComment(
          TopicComment(
            topicId: id,
            target: comment.target,
            targetId: resource.id!,
            content: '失效目标',
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'topic deletion snapshots everything and rolls back on trash failure',
    () async {
      final store = await setup();
      final repo = LocalTopicsRepository(store);
      final id = await repo.save(const TopicItem(title: '需要完整快照'));
      final other = await repo.save(const TopicItem(title: '不应受影响'));
      final summary = await repo.saveSummary(
        TopicSummary(topicId: id, content: '# 原文'),
      );
      await repo.saveComment(
        TopicComment(
          topicId: id,
          target: TopicCommentTarget.summary,
          targetId: summary.id!,
          content: '原评论',
        ),
      );
      final tasks = LocalTasksRepository(store);
      final taskId = await tasks.save(
        TaskItem(content: '主题内任务', dueDate: '2026-11-04', topicId: id),
      );
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER reject_topic_trash BEFORE INSERT ON trash_entries BEGIN SELECT RAISE(ABORT,'test snapshot failure'); END",
      );
      await expectLater(repo.remove(id), throwsA(isA<DatabaseException>()));
      expect((await repo.read(id)).summaries.single.id, summary.id);
      expect((await tasks.read(taskId)).topicId, id);
      expect((await repo.comments(id)).total, 1);
      await db.execute('DROP TRIGGER reject_topic_trash');
      await repo.remove(id);
      await expectLater(repo.read(id), throwsStateError);
      await expectLater(tasks.read(taskId), throwsStateError);
      expect((await repo.read(other)).topic.title, '不应受影响');
      final payload =
          jsonDecode(
                (await db.query('trash_entries')).single['payload'] as String,
              )
              as Map;
      expect((payload['summaries'] as List).length, 1);
      expect((payload['comments'] as List).length, 1);
      expect((payload['tasks'] as List).length, 1);
    },
  );
  test(
    'local topic tasks exceed detail cap and calendar counts actual activity',
    () async {
      final store = await setup();
      final repo = LocalTopicsRepository(store);
      final id = await repo.save(const TopicItem(title: '大量任务'));
      final tasks = LocalTasksRepository(store);
      for (var i = 0; i < 101; i++) {
        await tasks.save(
          TaskItem(content: '任务$i', dueDate: '2026-11-04', topicId: id),
        );
      }
      expect((await repo.read(id)).loadedTasks.length, 100);
      expect((await repo.tasks(id, page: 2)).items.length, 1);
      expect((await repo.tasks(id)).total, 101);
      final now = DateTime.now();
      final day = (await repo.dailyCounts(now.year, now.month)).single;
      expect(day.tasks, 101);
      expect(day.topics, 1);
      expect(day.total, 102);
    },
  );
  test(
    'v7 upgrade preserves actual bookmarks and earlier collections',
    () async {
      final store = await setup();
      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        store.path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            for (final table in [
              'notes',
              'tasks',
              'books',
              'documents',
              'bookmarks',
            ]) {
              await db.execute(
                'CREATE TABLE $table (id INTEGER PRIMARY KEY, value TEXT)',
              );
              await db.insert(table, {'id': 1, 'value': '保留$table'});
            }
          },
        ),
      );
      await old.close();
      final db = await store.database;
      expect(await db.getVersion(), 16);
      for (final table in [
        'notes',
        'tasks',
        'books',
        'documents',
        'bookmarks',
      ]) {
        expect((await db.query(table)).single['value'], '保留$table');
      }
      expect(await db.query('topics'), isEmpty);
      expect(await db.query('topic_comments'), isEmpty);
    },
  );
}
