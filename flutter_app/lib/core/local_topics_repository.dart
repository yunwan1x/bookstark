import 'dart:convert';
import 'dart:typed_data';
import 'bounded_note_text_reader.dart';
import 'package:sqflite/sqflite.dart';
import 'local_store.dart';
import 'tasks_repository.dart';
import 'topics_repository.dart';

class LocalTopicsRepository implements TopicsRepository, SummaryContentWriter {
  LocalTopicsRepository(this.store);
  final LocalStore store;
  @override
  int get memberId => 1;
  void _id(int id) {
    if (id <= 0) throw const FormatException('Invalid topic resource ID');
  }

  static const _topics = '''SELECT t.*,
    (SELECT COUNT(*) FROM topic_summaries s WHERE s.topic_id = t.topic_id) AS summary_count,
    (SELECT COUNT(*) FROM topic_resources r WHERE r.topic_id = t.topic_id) AS resource_count,
    (SELECT COUNT(*) FROM tasks k WHERE k.topic_id = t.topic_id AND k.deleted = 0) AS task_count FROM topics t''';
  TopicItem _item(Map row) => TopicItem.fromJson({
    ...row,
    'member_id': memberId,
    'is_pinned': row['is_pinned'] == 1,
  });
  Future<TopicItem> _topic(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        _id(id);
        final rows = await db.rawQuery(
          '$_topics WHERE t.topic_id = ? AND t.deleted = 0',
          [id],
        );
        if (rows.isEmpty) throw StateError('主题不存在 / Topic no longer exists');
        return _item(rows.single);
      });

  Future<void> _touch(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        await db.update(
          'topics',
          {'modify_time': DateTime.now().toIso8601String()},
          where: 'topic_id = ?',
          whereArgs: [id],
        );
      });

  @override
  Future<TopicPageResult> list(
    TopicQuery query,
  ) => store.maintenance.use(() async {
    query.parameters();
    final where = ['t.deleted = 0'];
    final args = <Object?>[];
    if (query.keyword.trim().isNotEmpty) {
      final pattern =
          '%${query.keyword.trim().replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      where.add(
        """(t.title LIKE ? ESCAPE '\\' OR t.question LIKE ? ESCAPE '\\'
        OR EXISTS (SELECT 1 FROM topic_summaries s WHERE s.topic_id = t.topic_id AND s.content LIKE ? ESCAPE '\\')
        OR EXISTS (SELECT 1 FROM topic_resources r WHERE r.topic_id = t.topic_id AND (r.title_snapshot LIKE ? ESCAPE '\\' OR r.desc_snapshot LIKE ? ESCAPE '\\'))
        OR EXISTS (SELECT 1 FROM tasks k WHERE k.topic_id = t.topic_id AND k.deleted = 0 AND k.content LIKE ? ESCAPE '\\'))""",
      );
      args.addAll(List.filled(6, pattern));
    }
    if (query.date.isNotEmpty) {
      where.add(
        '''(substr(t.modify_time, 1, 10) = ?
        OR EXISTS (SELECT 1 FROM topic_summaries s WHERE s.topic_id = t.topic_id AND substr(s.modify_time, 1, 10) = ?)
        OR EXISTS (SELECT 1 FROM topic_resources r WHERE r.topic_id = t.topic_id AND substr(r.create_time, 1, 10) = ?)
        OR EXISTS (SELECT 1 FROM tasks k WHERE k.topic_id = t.topic_id AND k.deleted = 0 AND substr(k.modify_time, 1, 10) = ?))''',
      );
      args.addAll(List.filled(4, query.date));
    }
    return (await store.database).transaction((txn) async {
      final conditions = where.join(' AND ');
      final total = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM topics t WHERE $conditions',
          args,
        ),
      )!;
      final rows = await txn.rawQuery(
        '$_topics WHERE $conditions ORDER BY t.is_pinned DESC, t.modify_time DESC, t.topic_id DESC LIMIT 20 OFFSET ?',
        [...args, (query.page - 1) * 20],
      );
      return TopicPageResult(
        List.unmodifiable(rows.map(_item)),
        total,
        query.page,
        20,
      );
    });
  });

  @override
  Future<int> save(TopicItem topic) => store.maintenance.use(() async {
    final body = topic.writeBody();
    return (await store.database).transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final values = {
        'title': body['title'],
        'question': body['question'],
        'is_pinned': topic.isPinned ? 1 : 0,
        'modify_time': now,
      };
      if (topic.id == null) {
        return txn.insert('topics', {...values, 'create_time': now});
      }
      await _topic(txn, topic.id!);
      await txn.update(
        'topics',
        values,
        where: 'topic_id = ?',
        whereArgs: [topic.id],
      );
      return topic.id!;
    });
  });

  @override
  Future<void> setPinned(int id, bool value) => store.maintenance.use(() async {
    await (await store.database).transaction((txn) async {
      await _topic(txn, id);
      await txn.update(
        'topics',
        {
          'is_pinned': value ? 1 : 0,
          'modify_time': DateTime.now().toIso8601String(),
        },
        where: 'topic_id = ?',
        whereArgs: [id],
      );
    });
  });

  @override
  Future<TopicDetail> read(int id) => store.maintenance.use(
    () async => (await store.database).transaction((txn) async {
      final topic = await _topic(txn, id);
      final summaries = await txn.rawQuery(
        "SELECT s.*, (SELECT COUNT(*) FROM topic_comments c WHERE c.topic_id = s.topic_id AND c.target_type = 'summary' AND c.target_id = s.summary_id) AS comment_count FROM topic_summaries s WHERE s.topic_id = ? ORDER BY s.order_sort, s.summary_id",
        [id],
      );
      final resources = await txn.rawQuery(
        "SELECT r.*, (SELECT COUNT(*) FROM topic_comments c WHERE c.topic_id = r.topic_id AND c.target_type = 'resource' AND c.target_id = r.topic_resource_id) AS comment_count FROM topic_resources r WHERE r.topic_id = ? ORDER BY r.order_sort, r.topic_resource_id",
        [id],
      );
      final enriched = <TopicResource>[];
      for (final resource in resources) {
        final source = await _source(
          txn,
          TopicResourceType.values.byName(resource['resource_type'] as String),
          resource['target_id'] as int,
        );
        enriched.add(
          TopicResource.fromJson({
            ...resource,
            'resource_missing': source == null,
          }),
        );
      }
      final comments = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM topic_comments WHERE topic_id = ?',
          [id],
        ),
      )!;
      return TopicDetail(
        topic: topic,
        summaries: List.unmodifiable(summaries.map(TopicSummary.fromJson)),
        resources: List.unmodifiable(enriched),
        loadedTasks: (await _tasks(txn, id, 1)).items,
        commentCount: comments,
      );
    }),
  );
  Future<TopicSummary> _summaryForEditing(
    DatabaseExecutor tx,
    int topicId,
    int summaryId,
  ) async {
    _id(topicId);
    _id(summaryId);
    await _topic(tx, topicId);
    final rows = await tx.rawQuery(
      "SELECT s.summary_id,s.topic_id,s.summary_type,s.order_sort,s.create_time,s.modify_time,"
      "length(CAST(s.content AS BLOB)) AS source_bytes,"
      "(SELECT COUNT(*) FROM topic_comments c WHERE c.topic_id=s.topic_id AND c.target_type='summary' "
      "AND c.target_id=s.summary_id) AS comment_count FROM topic_summaries s WHERE s.topic_id=? AND s.summary_id=?",
      [topicId, summaryId],
    );
    if (rows.length != 1) throw StateError('Summary no longer exists');
    final size = rows.single['source_bytes'];
    if (size is! int || size < 0 || size > 80000) {
      throw const FormatException('Summary source exceeds edit byte budget');
    }
    final body = (await tx.rawQuery(
      'SELECT CAST(content AS BLOB) AS source FROM topic_summaries '
      'WHERE topic_id=? AND summary_id=?',
      [topicId, summaryId],
    )).single['source'];
    if (body is! List<int> || body.length != size) {
      throw const FormatException('Summary source changed');
    }
    return TopicSummary.fromJson({
      ...rows.single,
      'content': BoundedNoteTextReader.decodeUtf8PreservingBom(
        Uint8List.fromList(body),
      ),
    });
  }

  @override
  Future<TopicSummary> readSummaryForEditing(int topicId, int summaryId) =>
      store.maintenance.use(
        () async => (await store.database).transaction(
          (tx) => _summaryForEditing(tx, topicId, summaryId),
        ),
      );
  @override
  Future<TopicSummary> saveSummaryContent(
    TopicSummary baseline,
    String content,
  ) => store.maintenance.use(() async {
    final id = baseline.id;
    if (id == null) throw const FormatException('Existing summary required');
    final canonical =
        TopicSummary(
              topicId: baseline.topicId,
              content: content,
            ).writeBody()['content']
            as String;
    return (await store.database).transaction((tx) async {
      final current = await _summaryForEditing(tx, baseline.topicId, id);
      if (current.content != baseline.content) {
        throw StateError('Summary body changed; review current version');
      }
      final count = await tx.update(
        'topic_summaries',
        {'content': canonical, 'modify_time': DateTime.now().toIso8601String()},
        where: 'topic_id=? AND summary_id=?',
        whereArgs: [baseline.topicId, id],
      );
      if (count != 1) throw StateError('Summary no longer exists');
      await _touch(tx, baseline.topicId);
      return _summaryForEditing(tx, baseline.topicId, id);
    });
  });

  @override
  Future<TopicSummary> saveSummary(TopicSummary summary) =>
      store.maintenance.use(() async {
        final body = summary.writeBody();
        return (await store.database).transaction((txn) async {
          await _topic(txn, summary.topicId);
          final now = DateTime.now().toIso8601String();
          final values = {...body, 'modify_time': now};
          final int id;
          if (summary.id == null) {
            id = await txn.insert('topic_summaries', {
              ...values,
              'topic_id': summary.topicId,
              'create_time': now,
            });
          } else {
            id = summary.id!;
            final count = await txn.update(
              'topic_summaries',
              values,
              where: 'summary_id = ? AND topic_id = ?',
              whereArgs: [id, summary.topicId],
            );
            if (count != 1) {
              throw StateError('小结不存在 / Summary no longer exists');
            }
          }
          await _touch(txn, summary.topicId);
          return TopicSummary.fromJson(
            (await txn.query(
              'topic_summaries',
              where: 'summary_id = ?',
              whereArgs: [id],
            )).single,
          );
        });
      });

  @override
  Future<void> removeSummary(int topicId, int summaryId) =>
      store.maintenance.use(
        () async => _removeTarget(
          topicId,
          summaryId,
          'topic_summaries',
          'summary_id',
          'summary',
        ),
      );
  Future<void> _removeTarget(
    int topicId,
    int id,
    String table,
    String column,
    String target,
  ) => store.maintenance.use(() async {
    _id(id);
    await (await store.database).transaction((txn) async {
      await _topic(txn, topicId);
      final count = await txn.delete(
        table,
        where: '$column = ? AND topic_id = ?',
        whereArgs: [id, topicId],
      );
      if (count != 1) throw StateError('关联内容不存在 / Item no longer exists');
      await txn.delete(
        'topic_comments',
        where: 'topic_id = ? AND target_type = ? AND target_id = ?',
        whereArgs: [topicId, target, id],
      );
      await _touch(txn, topicId);
    });
  });

  Future<void> _sort(
    int topicId,
    Map<int, int> order,
    String table,
    String column,
  ) => store.maintenance.use(() async {
    if (order.isEmpty || order.keys.any((id) => id <= 0)) {
      throw const FormatException('Invalid sort');
    }
    await (await store.database).transaction((txn) async {
      await _topic(txn, topicId);
      for (final entry in order.entries) {
        final count = await txn.update(
          table,
          {'order_sort': entry.value},
          where: 'topic_id = ? AND $column = ?',
          whereArgs: [topicId, entry.key],
        );
        if (count != 1) throw StateError('排序项不存在 / Sort item no longer exists');
      }
      await _touch(txn, topicId);
    });
  });

  @override
  Future<void> sortSummaries(int topicId, Map<int, int> order) => store
      .maintenance
      .use(() async => _sort(topicId, order, 'topic_summaries', 'summary_id'));
  @override
  Future<void> sortResources(int topicId, Map<int, int> order) =>
      store.maintenance.use(
        () async =>
            _sort(topicId, order, 'topic_resources', 'topic_resource_id'),
      );
  Future<({String title, String description})?> _source(
    DatabaseExecutor db,
    TopicResourceType type,
    int id,
  ) => store.maintenance.use(() async {
    final (sql, args) = switch (type) {
      TopicResourceType.document => (
        'SELECT document_name AS title, \'\' AS description FROM documents WHERE document_id = ? AND deleted = 0',
        <Object?>[id],
      ),
      TopicResourceType.bookmark => (
        'SELECT title, description FROM bookmarks WHERE bookmark_id = ? AND deleted = 0',
        <Object?>[id],
      ),
      TopicResourceType.note || TopicResourceType.article => (
        'SELECT title, substr(content, 1, 200) AS description FROM notes WHERE id = ? AND collection = ? AND deleted = 0',
        <Object?>[id, type == TopicResourceType.note ? 'note' : 'article'],
      ),
      TopicResourceType.task => (
        'SELECT substr(content, 1, 500) AS title, \'\' AS description FROM tasks WHERE task_id = ? AND deleted = 0',
        <Object?>[id],
      ),
    };
    final rows = await db.rawQuery(sql, args);
    return rows.isEmpty
        ? null
        : (
            title: (rows.single['title'] as String).trim(),
            description: (rows.single['description'] as String).trim(),
          );
  });

  @override
  Future<TopicResource> addResource(TopicResource resource) =>
      store.maintenance.use(() async {
        if (resource.id != null) {
          throw const FormatException('Resource references cannot be updated');
        }
        final body = resource.writeBody();
        return (await store.database).transaction((txn) async {
          await _topic(txn, resource.topicId);
          final source = await _source(txn, resource.type, resource.targetId);
          if (source == null) {
            throw StateError('源资料不存在 / Source no longer exists');
          }
          final values = {
            ...body,
            'topic_id': resource.topicId,
            'create_time': DateTime.now().toIso8601String(),
          };
          if (resource.title.trim().isEmpty) {
            values['title_snapshot'] = source.title.isEmpty
                ? '未命名资料'
                : source.title;
          }
          if (resource.description.trim().isEmpty) {
            values['desc_snapshot'] = source.description;
          }
          final id = await txn.insert('topic_resources', values);
          await _touch(txn, resource.topicId);
          return TopicResource.fromJson(
            (await txn.query(
              'topic_resources',
              where: 'topic_resource_id = ?',
              whereArgs: [id],
            )).single,
          );
        });
      });

  @override
  Future<void> removeResource(int topicId, int resourceId) =>
      store.maintenance.use(
        () async => _removeTarget(
          topicId,
          resourceId,
          'topic_resources',
          'topic_resource_id',
          'resource',
        ),
      );
  Future<TaskPage> _tasks(DatabaseExecutor db, int topicId, int page) =>
      store.maintenance.use(() async {
        final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE topic_id = ? AND deleted = 0',
            [topicId],
          ),
        )!;
        final rows = await db.rawQuery(
          '''SELECT t.*,
      (SELECT COUNT(*) FROM tasks c WHERE c.parent_id = t.task_id AND c.deleted = 0) AS child_total,
      (SELECT COUNT(*) FROM tasks c WHERE c.parent_id = t.task_id AND c.deleted = 0 AND c.done = 1) AS child_done
      FROM tasks t WHERE t.topic_id = ? AND t.deleted = 0 ORDER BY t.done, t.due_date, t.modify_time DESC, t.task_id DESC LIMIT 100 OFFSET ?''',
          [topicId, (page - 1) * 100],
        );
        return TaskPage(
          items: rows
              .map(
                (row) => TaskItem.fromJson({...row, 'done': row['done'] == 1}),
              )
              .toList(),
          total: total,
          page: page,
          pageSize: 100,
        );
      });

  @override
  Future<TaskPage> tasks(int topicId, {int page = 1}) =>
      store.maintenance.use(() async {
        if (page < 1) throw const FormatException('Invalid page');
        return (await store.database).transaction((txn) async {
          await _topic(txn, topicId);
          return _tasks(txn, topicId, page);
        });
      });

  Future<void> _target(
    DatabaseExecutor db,
    int topicId,
    TopicCommentTarget target,
    int targetId,
  ) => store.maintenance.use(() async {
    _id(targetId);
    final (table, column) = switch (target) {
      TopicCommentTarget.summary => ('topic_summaries', 'summary_id'),
      TopicCommentTarget.resource => ('topic_resources', 'topic_resource_id'),
      TopicCommentTarget.task => ('tasks', 'task_id'),
    };
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE topic_id = ? AND $column = ?${target == TopicCommentTarget.task ? ' AND deleted = 0' : ''}',
        [topicId, targetId],
      ),
    )!;
    if (count != 1) {
      throw StateError('评论目标不存在 / Comment target no longer exists');
    }
  });

  TopicComment _comment(Map row) => TopicComment.fromJson({
    ...row,
    'member_id': memberId,
    'author_name': 'local',
  });
  @override
  Future<TopicCommentPage> comments(
    int topicId, {
    TopicCommentTarget? target,
    int? targetId,
    int page = 1,
  }) => store.maintenance.use(() async {
    if (page < 1 || ((target == null) != (targetId == null))) {
      throw const FormatException('Invalid comment query');
    }
    return (await store.database).transaction((txn) async {
      await _topic(txn, topicId);
      if (target != null) await _target(txn, topicId, target, targetId!);
      final where =
          'topic_id = ?${target == null ? '' : ' AND target_type = ? AND target_id = ?'}';
      final args = <Object?>[
        topicId,
        if (target != null) ...[target.name, targetId],
      ];
      final total = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM topic_comments WHERE $where',
          args,
        ),
      )!;
      final rows = await txn.query(
        'topic_comments',
        where: where,
        whereArgs: args,
        orderBy: 'create_time, comment_id',
        limit: 100,
        offset: (page - 1) * 100,
      );
      return TopicCommentPage(
        List.unmodifiable(rows.map(_comment)),
        total,
        page,
        100,
      );
    });
  });

  @override
  Future<TopicComment> saveComment(
    TopicComment comment,
  ) => store.maintenance.use(() async {
    final body = comment.writeBody(updating: comment.id != null);
    return (await store.database).transaction((txn) async {
      await _topic(txn, comment.topicId);
      await _target(txn, comment.topicId, comment.target, comment.targetId);
      final now = DateTime.now().toIso8601String();
      final int id;
      if (comment.id == null) {
        id = await txn.insert('topic_comments', {
          'topic_id': comment.topicId,
          'target_type': comment.target.name,
          'target_id': comment.targetId,
          'content': body['content'],
          'create_time': now,
          'modify_time': now,
        });
      } else {
        id = comment.id!;
        final count = await txn.update(
          'topic_comments',
          {'content': body['content'], 'modify_time': now},
          where:
              'comment_id = ? AND topic_id = ? AND target_type = ? AND target_id = ?',
          whereArgs: [
            id,
            comment.topicId,
            comment.target.name,
            comment.targetId,
          ],
        );
        if (count != 1) {
          throw StateError('评论不存在或目标变化 / Comment missing or target changed');
        }
      }
      return _comment(
        (await txn.query(
          'topic_comments',
          where: 'comment_id = ?',
          whereArgs: [id],
        )).single,
      );
    });
  });

  @override
  Future<void> removeComment(int topicId, int commentId) =>
      store.maintenance.use(() async {
        _id(commentId);
        await (await store.database).transaction((txn) async {
          await _topic(txn, topicId);
          if (await txn.delete(
                'topic_comments',
                where: 'topic_id = ? AND comment_id = ?',
                whereArgs: [topicId, commentId],
              ) !=
              1) {
            throw StateError('Comment no longer exists');
          }
        });
      });

  @override
  Future<void> remove(int id) => store.maintenance.use(() async {
    await (await store.database).transaction((txn) async {
      final topic = await _topic(txn, id);
      final raw = (await txn.query(
        'topics',
        where: 'topic_id = ?',
        whereArgs: [id],
      )).single;
      final payload = <String, Object?>{'version': 1, 'topic': raw};
      for (final entry in {
        'summaries': 'topic_summaries',
        'resources': 'topic_resources',
        'comments': 'topic_comments',
        'tasks': 'tasks',
      }.entries) {
        payload[entry.key] = await txn.query(
          entry.value,
          where:
              'topic_id = ?${entry.key == 'tasks' ? ' AND deleted = 0' : ''}',
          whereArgs: [id],
        );
      }
      await txn.insert('trash_entries', {
        'resource_type': 'topic',
        'resource_id': id,
        'name': topic.title,
        'payload': jsonEncode(payload),
        'deleted_at': DateTime.now().toIso8601String(),
      });
      await txn.update(
        'tasks',
        {'deleted': 1},
        where: 'topic_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      for (final table in [
        'topic_summaries',
        'topic_resources',
        'topic_comments',
      ]) {
        await txn.delete(table, where: 'topic_id = ?', whereArgs: [id]);
      }
      await txn.update(
        'topics',
        {'deleted': 1},
        where: 'topic_id = ?',
        whereArgs: [id],
      );
    });
  });

  @override
  Future<List<TopicDailyCount>> dailyCounts(
    int year,
    int month,
  ) => store.maintenance.use(() async {
    if (year < 1970 || year > 9999 || month < 1 || month > 12) {
      throw const FormatException('Invalid topic calendar month');
    }
    final start =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';
    final end =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-31';
    final rows = await (await store.database).rawQuery(
      '''WITH events AS (
      SELECT substr(modify_time,1,10) AS date,1 AS topics,0 AS summaries,0 AS resources,0 AS tasks FROM topics WHERE deleted = 0
      UNION ALL SELECT substr(s.modify_time,1,10),0,1,0,0 FROM topic_summaries s JOIN topics t ON s.topic_id=t.topic_id WHERE t.deleted=0
      UNION ALL SELECT substr(r.create_time,1,10),0,0,1,0 FROM topic_resources r JOIN topics t ON r.topic_id=t.topic_id WHERE t.deleted=0
      UNION ALL SELECT substr(modify_time,1,10),0,0,0,1 FROM tasks WHERE topic_id>0 AND deleted=0)
      SELECT date,SUM(topics+summaries+resources+tasks) AS count,SUM(topics) AS topic_count,SUM(summaries) AS summary_count,SUM(resources) AS resource_count,SUM(tasks) AS task_count
      FROM events WHERE date BETWEEN ? AND ? GROUP BY date ORDER BY date''',
      [start, end],
    );
    return List.unmodifiable(rows.map(TopicDailyCount.fromJson));
  });
}
