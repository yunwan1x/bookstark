import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'task dates reject normalized overflow, year zero and non-leap February',
    () {
      for (final value in [
        '2026-02-29',
        '2100-02-29',
        '0000-01-01',
        '2026-13-01',
        '2026-04-31',
        '2026-1-01',
        '',
      ]) {
        expect(validTaskDate(value), isFalse, reason: value);
      }
      expect(validTaskDate('2024-02-29'), isTrue);
      expect(validTaskDate('2000-02-29'), isTrue);
      expect(taskDate(DateTime(2026, 11, 4)), '2026-11-04');
    },
  );
  test(
    'task writes count Unicode codepoints and preserve parent/topic fields',
    () {
      final content = List.filled(1000, '📖').join();
      final item = TaskItem(
        id: 3,
        content: content,
        dueDate: '2026-11-08',
        parentId: 2,
        topicId: 9,
      );
      expect(item.writeBody()['content'], content);
      expect(
        item.copyWith(done: true).writeBody(),
        containsPair('parent_id', 2),
      );
      expect(
        item.copyWith(content: '更新正文').writeBody(),
        containsPair('topic_id', 9),
      );
      expect(
        () => item.copyWith(content: '$content📖').writeBody(),
        throwsFormatException,
      );
      expect(
        () => item.copyWith(content: ' \n ').writeBody(),
        throwsFormatException,
      );
      expect(
        () => const TaskItem(
          id: 2,
          content: '循环',
          dueDate: '2026-11-08',
          parentId: 2,
        ).writeBody(),
        throwsFormatException,
      );
      expect(
        const TaskItem(
          content: '根任务',
          dueDate: '2026-11-08',
        ).writeBody().containsKey('topic_id'),
        isFalse,
      );
    },
  );
  test(
    'all status query omits done and calendar modification filter differs from due date',
    () {
      const query = TaskQuery(
        keyword: '阅读 & 中文',
        dueOn: '2026-11-08',
        modifiedOn: '2026-11-04',
        page: 3,
      );
      final parameters = query.parameters();
      expect(parameters.containsKey('done'), isFalse);
      expect(parameters.containsKey('parent_id'), isFalse);
      expect(parameters['due_on'], '2026-11-08');
      expect(parameters['date'], '2026-11-04');
      expect(
        const TaskQuery(done: false, parentId: 0).parameters(),
        containsPair('done', '0'),
      );
      expect(
        () => const TaskQuery(pageSize: 101).parameters(),
        throwsFormatException,
      );
      expect(
        () => const TaskQuery(dueOn: '2026-02-29').parameters(),
        throwsFormatException,
      );
    },
  );
  test(
    'remote tasks decode real pagination, preserve child relation and PATCH completion',
    () async {
      final requests = <http.Request>[];
      final row = {
        'task_id': 7,
        'content': '完整正文',
        'due_date': '2026-11-08',
        'done': false,
        'parent_id': 2,
        'topic_id': 9,
        'child_total': 0,
        'child_done': 0,
        'modify_time': '2026-11-04T23:00:00+08:00',
        'complete_time': null,
      };
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          if (request.url.path.endsWith('/tasks') && request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'data': [row],
                'total': 61,
                'page': 2,
                'page_size': 30,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({'data': row}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final repository = RemoteTasksRepository(client);
      final page = await repository.list(const TaskQuery(page: 2, done: false));
      expect(page.hasMore, isTrue);
      expect(page.total, 61);
      expect(requests.first.url.path, '/base/api/tasks');
      expect(requests.first.url.queryParameters['done'], '0');
      final item = await repository.read(7);
      expect(item.modifiedAt, '2026-11-04T23:00:00+08:00');
      await repository.save(item.copyWith(content: '保存原父关联'));
      final body =
          jsonDecode(
                requests.singleWhere((request) => request.method == 'PUT').body,
              )
              as Map;
      expect(body['parent_id'], 2);
      expect(body['topic_id'], 9);
      await repository.setDone(7, true);
      final patch = requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(patch.url.path, '/base/api/tasks/7/done');
      expect(jsonDecode(patch.body), {'done': true});
      expect(patch.headers['x-csrf-token'], 'x');
    },
  );
  test(
    'calendar counts validate actual totals and server date without device conversion',
    () {
      final count = TaskDailyCount.fromJson({
        'date': '2026-11-04',
        'count': 3,
        'done_count': 1,
        'active_count': 2,
      });
      expect(count.date, '2026-11-04');
      expect(count.active, 2);
      expect(
        () => TaskDailyCount.fromJson({
          'date': '2026-11-04',
          'count': 1,
          'done_count': 1,
          'active_count': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => TaskItem.fromJson({'task_id': 0, 'content': '', 'done': false}),
        throwsFormatException,
      );
    },
  );
}
