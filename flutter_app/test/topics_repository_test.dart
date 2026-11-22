import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
BookstarkClient clientWith(
  Future<http.Response> Function(http.Request) action,
) {
  final client = BookstarkClient(
    'https://example.test/base',
    transport: MockClient((request) async {
      if (request.url.path.endsWith('/csrf-token')) {
        return http.Response(
          '{}',
          200,
          headers: {'set-cookie': 'csrf_token=test'},
        );
      }
      return action(request);
    }),
  );
  addTearDown(client.close);
  return client;
}

Map<String, Object?> topic(int id, {int member = 7}) => {
  'topic_id': id,
  'member_id': member,
  'title': '阅读与知识整理',
  'question': '如何将阅读转化为行动？',
  'is_pinned': true,
};
void main() {
  test('topic calendar day preserves server offset across UTC midnight', () {
    final value = TopicItem.fromJson({
      ...topic(4),
      'modify_time': '2026-11-04T00:15:00+08:00',
    });
    expect(value.modifiedOn, '2026-11-04');
    expect(value.copyWith(title: '更名').modifiedOn, '2026-11-04');
  });
  test('topic and summary limits use Unicode code points, not bytes', () {
    expect(
      TopicItem(title: List.filled(200, '📖').join()).writeBody()['title'],
      hasLength(400),
    );
    expect(
      () => TopicItem(title: List.filled(201, '📖').join()).writeBody(),
      throwsFormatException,
    );
    expect(const TopicItem(title: ' 名称 ', question: ' 问题 ').writeBody(), {
      'title': '名称',
      'question': '问题',
      'is_pinned': false,
    });
    expect(
      () => const TopicItem(title: ' ').writeBody(),
      throwsFormatException,
    );
    expect(
      TopicSummary(
        topicId: 1,
        content: List.filled(20000, '📖').join(),
        type: 'ai',
        order: 18,
      ).writeBody()['order_sort'],
      18,
    );
    expect(
      () => TopicSummary(
        topicId: 1,
        content: List.filled(20001, '📖').join(),
      ).writeBody(),
      throwsFormatException,
    );
    expect(
      () => const TopicSummary(
        topicId: 1,
        content: 'x',
        type: 'unknown',
      ).writeBody(),
      throwsFormatException,
    );
  });
  test('list respects real pagination and rejects foreign owner', () async {
    var foreign = false;
    final client = clientWith((request) async {
      expect(request.url.queryParameters, {
        'keyword': '阅读 &',
        'date': '2026-11-04',
        'page': '2',
      });
      return reply({
        'data': [topic(4, member: foreign ? 8 : 7)],
        'total': 23,
        'page': 2,
        'page_size': 20,
      });
    });
    final repository = RemoteTopicsRepository(client, memberId: 7);
    final result = await repository.list(
      const TopicQuery(keyword: ' 阅读 & ', date: '2026-11-04', page: 2),
    );
    expect(result.total, 23);
    expect(result.hasMore, isFalse);
    foreign = true;
    await expectLater(
      repository.list(
        const TopicQuery(keyword: '阅读 &', date: '2026-11-04', page: 2),
      ),
      throwsStateError,
    );
    expect(
      () => const TopicQuery(date: '2026-02-30').parameters(),
      throwsFormatException,
    );
  });
  test(
    'topic update only submits editable fields and checks returned identity',
    () async {
      final client = clientWith((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/base/api/topics/4');
        expect(jsonDecode(request.body), {
          'title': '新主题',
          'question': '问题',
          'is_pinned': true,
        });
        return reply({'data': topic(4)});
      });
      final repository = RemoteTopicsRepository(client, memberId: 7);
      expect(
        await repository.save(
          const TopicItem(
            id: 4,
            memberId: 7,
            title: ' 新主题 ',
            question: '问题',
            isPinned: true,
          ),
        ),
        4,
      );
      await expectLater(
        repository.save(const TopicItem(id: 4, memberId: 8, title: '别人')),
        throwsStateError,
      );
    },
  );
  test(
    'summary editing preserves AI type and order, checks real topic',
    () async {
      final client = clientWith((request) async {
        expect(jsonDecode(request.body), {
          'content': '# 小结',
          'summary_type': 'ai',
          'order_sort': 18,
        });
        return reply({
          'summary_id': 9,
          'topic_id': 4,
          'content': '# 小结',
          'summary_type': 'ai',
          'order_sort': 18,
        });
      });
      final saved = await RemoteTopicsRepository(client, memberId: 7)
          .saveSummary(
            const TopicSummary(
              id: 9,
              topicId: 4,
              content: '# 小结',
              type: 'ai',
              order: 18,
            ),
          );
      expect(saved.type, 'ai');
      expect(saved.order, 18);
    },
  );
  test(
    'detail never treats its capped task array as authoritative total',
    () async {
      final client = clientWith((request) async {
        if (request.url.path.endsWith('/topics/4')) {
          return reply({
            'topic': topic(4),
            'summaries': null,
            'resources': null,
            'tasks': null,
            'stats': {'task_count': 100, 'comment_count': 2},
          });
        }
        expect(request.url.queryParameters, {
          'topic_id': '4',
          'page': '2',
          'page_size': '100',
        });
        return reply({'data': null, 'total': 151, 'page': 2, 'page_size': 100});
      });
      final repository = RemoteTopicsRepository(client, memberId: 7);
      expect((await repository.read(4)).loadedTasks, isEmpty);
      final page = await repository.tasks(4, page: 2);
      expect(page.total, 151);
      expect(page.pageSize, 100);
    },
  );
  test('comment create has one level; edit cannot move target', () async {
    final calls = <Map>[];
    final client = clientWith((request) async {
      calls.add(jsonDecode(request.body) as Map);
      return reply({
        'comment_id': 8,
        'topic_id': 4,
        'target_type': 'summary',
        'target_id': 9,
        'member_id': 7,
        'content': '评论',
      });
    });
    final repository = RemoteTopicsRepository(client, memberId: 7);
    await repository.saveComment(
      const TopicComment(
        topicId: 4,
        target: TopicCommentTarget.summary,
        targetId: 9,
        content: ' 评论 ',
      ),
    );
    await repository.saveComment(
      const TopicComment(
        id: 8,
        topicId: 4,
        target: TopicCommentTarget.summary,
        targetId: 9,
        content: '评论',
      ),
    );
    expect(calls.first, {
      'content': '评论',
      'target_type': 'summary',
      'target_id': 9,
      'parent_comment_id': 0,
    });
    expect(calls.last, {'content': '评论'});
    await expectLater(
      repository.comments(4, target: TopicCommentTarget.summary),
      throwsFormatException,
    );
  });
  test('resource references use whitelisted type and real positive target', () {
    expect(
      const TopicResource(
        topicId: 4,
        type: TopicResourceType.bookmark,
        targetId: 9,
      ).writeBody()['resource_type'],
      'bookmark',
    );
    expect(
      () => const TopicResource(
        topicId: 4,
        type: TopicResourceType.bookmark,
        targetId: 0,
      ).writeBody(),
      throwsFormatException,
    );
    expect(
      () => TopicResource(
        topicId: 4,
        type: TopicResourceType.note,
        targetId: 9,
        title: List.filled(501, '📖').join(),
      ).writeBody(),
      throwsFormatException,
    );
  });
  test('calendar is activity sum, rejects inconsistent counters', () {
    final result = TopicDailyCount.fromJson({
      'date': '2026-11-04',
      'count': 7,
      'topic_count': 1,
      'summary_count': 2,
      'resource_count': 3,
      'task_count': 1,
    });
    expect(result.total, 7);
    expect(result.topics, 1);
    expect(
      () => TopicDailyCount.fromJson({
        'date': '2026-11-04',
        'count': 1,
        'topic_count': 1,
        'summary_count': 2,
        'resource_count': 3,
        'task_count': 1,
      }),
      throwsFormatException,
    );
  });
}
