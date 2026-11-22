import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/task_action_drafts.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_remote_actions.dart';

const task = TaskItem(
  id: 17,
  content: 'Original',
  dueDate: '2026-11-11',
  parentId: 3,
  topicId: 5,
  done: true,
  childTotal: 4,
  childDone: 2,
  modifiedAt: '2026-11-10T12:00:00+08:00',
  completedAt: '2026-11-11T12:00:00+08:00',
);
String frame(Object value) => 'data: ${jsonEncode(value)}\n\n';
String text(String value) => frame({
  'choices': [
    {
      'delta': {'content': value},
    },
  ],
});
void main() {
  Future<(BookstarkClient, List<http.Request>)> client(
    String sse, {
    Object? owner = 3,
  }) async {
    final requests = <http.Request>[];
    final api = BookstarkClient(
      'https://example.test/mount',
      transport: MockClient((r) async {
        requests.add(r);
        if (r.method == 'GET' && r.url.path.endsWith('/csrf-token')) {
          return http.Response(
            '{}',
            200,
            headers: {'set-cookie': 'csrf_token=c; Path=/'},
          );
        }
        if (r.method == 'GET' && r.url.path.endsWith('/tasks/17')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'task_id': 17,
                'member_id': owner,
                'content': 'Original',
                'done': true,
                'due_date': '2026-11-11',
                'parent_id': 3,
                'topic_id': 5,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.method == 'POST' && r.url.path.endsWith('/ai/complete')) {
          return http.Response(
            sse,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        throw StateError('Unexpected endpoint or mutation');
      }),
    )..restoreSession({'token': 'owned'});
    return (api, requests);
  }

  TaskActionSnapshot origin() =>
      TaskActionSnapshot(scope: 'owner-space', memberId: 3, task: task);
  test(
    'complete scene task suggestion stays draft-only and preserves every field',
    () async {
      final (api, requests) = await client(
        '${text('Suggested')}data: [DONE]\n\n',
      );
      final actions = await TaskEditorRemoteActions.create(
        client: api,
        memberId: 3,
        scope: 'owner-space',
        isCurrent: () => true,
      );
      final suggestion = await actions.bindings.generateSuggestion!(origin());
      final sent = requests.where((r) => r.method == 'POST').single;
      final body = jsonDecode(sent.body) as Map;
      expect(body['scene'], 'task');
      expect(body.containsKey('tools'), isFalse);
      expect(sent.url.path, '/mount/api/ai/complete');
      final updated = suggestion.applyToDraft(origin());
      expect(updated.content, 'Suggested');
      expect(updated.id, task.id);
      expect(updated.dueDate, task.dueDate);
      expect(updated.parentId, task.parentId);
      expect(updated.topicId, task.topicId);
      expect(updated.done, task.done);
      expect(updated.childTotal, task.childTotal);
      expect(updated.childDone, task.childDone);
      expect(updated.modifiedAt, task.modifiedAt);
      expect(updated.completedAt, task.completedAt);
      expect(task.content, 'Original');
      actions.retire();
      api.close();
    },
  );
  test(
    'EOF and truncated/tool streams cannot produce applicable suggestions',
    () async {
      for (final sse in [
        text('Partial'),
        '${text('Partial')}${frame({
          'choices': [
            {'delta': {}, 'finish_reason': 'length'},
          ],
        })}data: [DONE]\n\n',
        '${frame({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {'name': 'propose_task'},
                ],
              },
            },
          ],
        })}data: [DONE]\n\n',
      ]) {
        final (api, requests) = await client(sse);
        final actions = await TaskEditorRemoteActions.create(
          client: api,
          memberId: 3,
          scope: 'owner-space',
          isCurrent: () => true,
        );
        await expectLater(
          actions.generateSuggestion(origin()),
          throwsA(anything),
        );
        expect(requests.where((r) => r.method == 'POST').length, 1);
        actions.retire();
        api.close();
      }
    },
  );
  test(
    'member must come from actual raw row before any completion request',
    () async {
      for (final owner in [null, 4]) {
        final (api, requests) = await client(
          '${text('No')}data: [DONE]\n\n',
          owner: owner,
        );
        final actions = await TaskEditorRemoteActions.create(
          client: api,
          memberId: 3,
          scope: 'owner-space',
          isCurrent: () => true,
        );
        await expectLater(
          actions.generateSuggestion(origin()),
          throwsA(anything),
        );
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
        actions.retire();
        api.close();
      }
    },
  );
  test(
    'retired and same-token replacement scopes cannot submit suggestions',
    () async {
      final (api, requests) = await client('${text('No')}data: [DONE]\n\n');
      final actions = await TaskEditorRemoteActions.create(
        client: api,
        memberId: 3,
        scope: 'owner-space',
        isCurrent: () => true,
      );
      api.restoreSession(
        api.exportSession(),
      ); // same token and csrf, NEW revision
      await expectLater(
        actions.generateSuggestion(origin()),
        throwsA(anything),
      );
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      actions.retire();
      api.close();
    },
  );
  test(
    'topic source uses same actual owner and cannot run after retirement',
    () async {
      final (api, _) = await client('');
      final actions = await TaskEditorRemoteActions.create(
        client: api,
        memberId: 3,
        scope: 'owner-space',
        isCurrent: () => true,
      );
      expect(actions.bindings.topicSource!.memberId, 3);
      expect(actions.bindings.topicSource!.scope, 'owner-space');
      actions.retire();
      await expectLater(
        actions.bindings.topicSource!.list('', 1),
        throwsA(anything),
      );
      api.close();
    },
  );
  test(
    'late completed response after retirement is never applicable',
    () async {
      final started = Completer<void>(), reply = Completer<http.Response>();
      final api = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.method == 'GET' && r.url.path == '/api/tasks/17') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'task_id': 17,
                  'member_id': 3,
                  'content': 'Original',
                  'done': true,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (r.method == 'POST' && r.url.path == '/api/ai/complete') {
            started.complete();
            return reply.future;
          }
          throw StateError('No task saves or proposal requests allowed');
        }),
      )..restoreSession({'token': 'owned', 'csrf_token': 'c'});
      final actions = TaskEditorRemoteActions(
        client: api,
        memberId: 3,
        scope: 'owner-space',
        isCurrent: () => true,
      );
      final pending = actions.generateSuggestion(origin());
      await started.future;
      actions.retire();
      reply.complete(
        http.Response(
          '${text('Late')}data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      await expectLater(pending, throwsA(anything));
      api.close();
    },
  );
}
