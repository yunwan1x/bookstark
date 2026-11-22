import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runTopicsContract(BookstarkClient client, int memberId) async {
  final topics = RemoteTopicsRepository(client, memberId: memberId);
  final bookmarks = RemoteBookmarksRepository(client, memberId: memberId);
  final tasks = RemoteTasksRepository(client);
  final id = await topics.save(
    const TopicItem(
      title: ' Flutter 专题回归 ',
      question: ' 如何形成知识闭环？ ',
      isPinned: true,
    ),
  );
  var detail = await topics.read(id);
  require(
    detail.topic.title == 'Flutter 专题回归' &&
        detail.topic.question == '如何形成知识闭环？' &&
        detail.topic.isPinned,
    'Topic create normalizes like actual Go',
  );
  require(
    (await topics.list(const TopicQuery(keyword: '知识闭环'))).items.single.id ==
        id,
    'Topic question search',
  );
  await topics.setPinned(id, false);
  detail = await topics.read(id);
  require(!detail.topic.isPinned, 'Topic pin is explicit and idempotent');
  final summary = await topics.saveSummary(
    TopicSummary(
      topicId: id,
      content: '# 阅读小结\n\n- 形成行动',
      type: 'ai',
      order: 5,
    ),
  );
  final edited = await topics.saveSummary(
    TopicSummary(
      id: summary.id,
      topicId: id,
      content: '# 修改的小结',
      type: summary.type,
      order: summary.order,
    ),
  );
  require(
    edited.type == 'ai' && edited.order == 5,
    'Summary update preserves AI type and order',
  );
  await topics.sortSummaries(id, {summary.id!: 11});
  require((await topics.read(id)).summaries.single.order == 11, 'Summary sort');
  final bookmarkId = await bookmarks.save(
    const BookmarkItem(
      title: '主题资料',
      url: 'https://example.invalid/topic-contract',
      description: '保留源资料',
    ),
  );
  final resource = await topics.addResource(
    TopicResource(
      topicId: id,
      type: TopicResourceType.bookmark,
      targetId: bookmarkId,
    ),
  );
  require(
    resource.title == '主题资料' && resource.description == '保留源资料',
    'Resource snapshot resolves real source',
  );
  try {
    await topics.addResource(
      TopicResource(
        topicId: id,
        type: TopicResourceType.bookmark,
        targetId: bookmarkId,
      ),
    );
    throw StateError('Duplicate reference accepted');
  } on ApiFailure catch (error) {
    require(error.status == 409, 'Duplicate reference conflict');
  }
  await topics.sortResources(id, {resource.id!: 7});
  require((await topics.read(id)).resources.single.order == 7, 'Resource sort');
  final comment = await topics.saveComment(
    TopicComment(
      topicId: id,
      target: TopicCommentTarget.summary,
      targetId: summary.id!,
      content: '**评论**',
    ),
  );
  await topics.saveComment(
    TopicComment(
      id: comment.id,
      topicId: id,
      target: comment.target,
      targetId: comment.targetId,
      content: '已修改评论',
    ),
  );
  require(
    (await topics.comments(
          id,
          target: TopicCommentTarget.summary,
          targetId: summary.id,
        )).items.single.content ==
        '已修改评论',
    'Comment edit and exact target',
  );
  require((await topics.comments(id)).total == 1, 'Topic-wide comments read');
  final taskIds = <int>[];
  for (var i = 0; i < 101; i++) {
    taskIds.add(
      await tasks.save(
        TaskItem(content: '专题分页任务$i', dueDate: '2026-11-04', topicId: id),
      ),
    );
  }
  detail = await topics.read(id);
  require(
    detail.loadedTasks.length == 100,
    'Actual Go detail task cap is explicit',
  );
  final first = await topics.tasks(id),
      second = await topics.tasks(id, page: 2);
  require(
    first.total == 101 &&
        first.items.length == 100 &&
        first.hasMore &&
        second.items.length == 1 &&
        !second.hasMore,
    'Authoritative topic task pagination beyond 100',
  );
  require(
    (await topics.list(
          const TopicQuery(keyword: '专题分页任务100'),
        )).items.single.taskCount ==
        101,
    'Topic task search and real list count',
  );
  final modified = DateTime.parse(detail.topic.modifiedOn);
  final calendar = await topics.dailyCounts(modified.year, modified.month);
  require(
    calendar.isNotEmpty &&
        calendar.any((day) => day.tasks > 0 && day.total >= day.tasks),
    'Topic calendar has real activity counters',
  );
  await topics.removeResource(id, resource.id!);
  require(
    (await topics.read(id)).resources.isEmpty &&
        await bookmarks.findByUrl('https://example.invalid/topic-contract') !=
            null,
    'Removing association preserves source bookmark',
  );
  await topics.removeComment(id, comment.id!);
  require((await topics.comments(id)).total == 0, 'Comment deletion');
  await topics.remove(id);
  require(
    (await topics.list(const TopicQuery(keyword: 'Flutter 专题回归'))).total == 0,
    'Topic deletion',
  );
  try {
    await tasks.read(taskIds.first);
    throw StateError('Topic-owned task survived deletion');
  } on ApiFailure catch (error) {
    require(error.status == 404, 'Topic deletion includes owned tasks');
  }
  require(
    await bookmarks.findByUrl('https://example.invalid/topic-contract') != null,
    'Topic deletion preserves source resource',
  );
  await bookmarks.remove(bookmarkId);
}
