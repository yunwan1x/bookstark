import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_draft_namespace.dart';
import 'package:bookstark_flutter/core/task_creation_session.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/topic_tasks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'task_editor_test.dart' show EditorTasks;
import 'task_creation_http_next_test.dart' show taskRow;

void main() {
  test(
    'namespace only accepts root or canonical same-owner same-topic path',
    () {
      final valid = jsonEncode(['owner-root', 'topic-tasks', 9]);
      expect(taskCreationDraftNamespace('owner-root', 9, valid), valid);
      expect(
        taskCreationDraftNamespace('owner-root', 9, 'owner-root'),
        'owner-root',
      );
      for (final invalid in [
        jsonEncode(['foreign-owner', 'topic-tasks', 9]),
        jsonEncode(['owner-root', 'topic-tasks', 8]),
        jsonEncode(['owner-root', 'topic-summary', 9]),
        ' ' + valid,
      ]) {
        expect(
          () => taskCreationDraftNamespace('owner-root', 9, invalid),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'v2 retains exact draft namespace through unknown and known transitions',
    () {
      final input = TaskCreationAttempt(
        scope: List.filled(64, 'a').join(),
        key: List.filled(32, 'b').join(),
        draftNamespace: jsonEncode(['owner-root', 'topic-tasks', 9]),
        body: const {
          'content': 'Actual',
          'due_date': '2026-11-20',
          'done': true,
          'parent_id': 0,
          'topic_id': 9,
        },
      );
      final known = input
          .next(TaskCreationPhase.unknown)
          .next(
            TaskCreationPhase.knownID,
            41,
            TaskCreationOrigin.manualExisting,
          );
      expect(
        TaskCreationAttempt.decode(known.encode()).draftNamespace,
        input.draftNamespace,
      );
      final old = Map<String, Object?>.from(jsonDecode(input.encode()) as Map);
      old['version'] = 1;
      old.remove('draftNamespace');
      expect(
        TaskCreationAttempt.decode(jsonEncode(old)).draftNamespace,
        isNull,
      );
    },
  );
  test(
    'Topic wrapper sends actual vault and cold cleanup preserves full differences at same ID',
    () async {
      final values = <String, String>{};
      var posts = 0, puts = 0;
      http.Response reply(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          if (r.method == 'POST') posts++;
          if (r.method == 'PUT') puts++;
          return reply({'code': 0, 'data': taskRow()..['parent_id'] = 0});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      TaskDraftVault vault(String namespace) => TaskDraftVault(
        namespace: namespace,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final root = vault('topic-context-root');
      final topic = vault(jsonEncode(['topic-context-root', 'topic-tasks', 9]));
      const differences = TaskItem(
        content: 'Full unsaved topic draft',
        dueDate: '2026-11-21',
        done: false,
        parentId: 0,
        topicId: 9,
      );
      await topic.write(differences);
      await root.write(
        const TaskItem(
          content: 'Other root draft',
          dueDate: '2026-11-22',
          done: false,
          parentId: 0,
          topicId: 0,
        ),
      );
      TaskCreationSession owner() => TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'topic-context-root',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        draftVault: root,
      );
      final first = owner();
      try {
        final wrapped = TopicTasksRepository(first.wrap(EditorTasks()), 9);
        expect(
          await wrapped.saveWithDraft(
            const TaskItem(
              content: 'Actual',
              dueDate: '2026-11-20',
              done: true,
              parentId: 0,
              topicId: 9,
            ),
            topic,
          ),
          41,
        );
        expect(first.controller!.record!.draftNamespace, topic.namespace);
      } finally {
        await first.retire();
      }
      final cold = owner();
      try {
        final c = await cold.open();
        expect(c.record!.draftNamespace, topic.namespace);
        await c.end(c.record!);
        await cold.clearEndedSlot();
        expect(await topic.read(null, parentId: 0), isNull);
        final retained = (await topic.read(41, parentId: 0))!;
        expect(retained.content, differences.content);
        expect(retained.dueDate, differences.dueDate);
        expect(retained.done, differences.done);
        expect(retained.topicId, 9);
        expect(
          (await root.read(null, parentId: 0))!.content,
          'Other root draft',
        );
        expect(posts, 1);
        expect(puts, 0);
      } finally {
        await cold.retire();
        client.close();
      }
    },
  );
  test(
    'v1 nonzero-topic ambiguity cannot bind or delete an unrelated root draft',
    () async {
      final values = <String, String>{};
      http.Response reply(Object value) => http.Response(
        jsonEncode(value),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          return reply({'code': 0, 'data': taskRow()..['parent_id'] = 0});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final root = TaskDraftVault(
        namespace: 'legacy-topic-root',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      await root.write(
        const TaskItem(
          content: 'Unrelated root draft',
          dueDate: '2026-11-22',
          done: false,
          parentId: 0,
        ),
      );
      TaskCreationSession owner() => TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'legacy-topic-root',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        draftVault: root,
      );
      final first = owner();
      try {
        final repository = first.wrap(EditorTasks());
        expect(
          await repository.save(
            const TaskItem(
              content: 'Actual',
              dueDate: '2026-11-20',
              done: true,
              parentId: 0,
              topicId: 9,
            ),
          ),
          41,
        );
      } finally {
        await first.retire();
      }
      final records = values.entries
          .where(
            (e) =>
                e.value.startsWith('{') &&
                (jsonDecode(e.value) as Map)['scope'] != null,
          )
          .toList();
      expect(records, hasLength(1));
      final old = Map<String, Object?>.from(
        jsonDecode(records.single.value) as Map,
      );
      old['version'] = 1;
      old.remove('draftNamespace');
      values[records.single.key] = jsonEncode(old);
      final before = Map<String, String>.of(values);
      final cold = owner();
      try {
        final c = await cold.open();
        expect(c.record!.draftNamespace, isNull);
        await c.end(c.record!);
        expect(c.error, isNotNull);
        expect(c.endedDurably, isFalse);
        expect(values, before);
        expect(
          (await root.read(null, parentId: 0))!.content,
          'Unrelated root draft',
        );
        expect(await root.read(41, parentId: 0), isNull);
      } finally {
        await cold.retire();
        client.close();
      }
    },
  );
}
