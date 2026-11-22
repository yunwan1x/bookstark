import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/task_creation_session.dart';
import 'package:bookstark_flutter/core/task_creation_guarded_repository.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'task_editor_test.dart' show EditorTasks;
import 'task_creation_http_next_test.dart' show taskRow;

http.Response jsonReply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'actual POST commits then response drops; cold load never POSTs and manual ID is honest',
    () async {
      final values = <String, String>{};
      var posts = 0, serverRows = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return jsonReply({
              'code': 0,
              'data': {'member_id': 7},
            });
          if (r.method == 'POST') {
            posts++;
            serverRows++;
            expect(jsonDecode(r.body), {
              'content': 'Actual',
              'due_date': '2026-11-20',
              'done': true,
              'parent_id': 3,
              'topic_id': 9,
            });
            throw StateError('response deliberately lost after commit');
          }
          expect(r.url.path, '/api/tasks/41');
          return jsonReply({'code': 0, 'data': taskRow()});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      TaskCreationSession create() => TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'ordinary-task',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
      );
      final ordinary = EditorTasks();
      const draft = TaskItem(
        content: 'Actual',
        dueDate: '2026-11-20',
        done: true,
        parentId: 3,
        topicId: 9,
      );
      var owner = create();
      try {
        final repo = owner.wrap(ordinary);
        await expectLater(
          repo.save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        expect(posts, 1);
        expect(serverRows, 1);
        expect(ordinary.calls, isEmpty);
        expect(owner.controller!.record!.phase, TaskCreationPhase.unknown);
        await owner.retire();
        owner = create();
        final c = await owner.open();
        expect(c.record!.body['parent_id'], 3);
        await expectLater(
          owner.wrap(ordinary).save(draft),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        expect(posts, 1);
        expect(serverRows, 1);
        await c.review(41);
        await c.adopt(c.reviewed!);
        expect(c.record!.origin, TaskCreationOrigin.manualExisting);
        expect(c.record!.actualId, 41);
        expect(posts, 1);
        final captured = c.record!;
        await c.end(captured);
        await owner.clearEndedSlot();
        expect(values, isEmpty);
        expect(serverRows, 1);
        expect(posts, 1);
      } finally {
        await owner.retire();
        client.close();
      }
    },
  );
  test(
    'positive actual POST ACK durability retry performs storage only',
    () async {
      final values = <String, String>{};
      var posts = 0, gets = 0, failKnown = true;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return jsonReply({
              'code': 0,
              'data': {'member_id': 7},
            });
          if (r.method == 'POST')
            posts++;
          else
            gets++;
          return jsonReply({'code': 0, 'data': taskRow()});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final owner = TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'storage-only-task',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {
          if (failKnown &&
              values.values.any((v) => v.contains('"phase":"knownID"'))) {
            throw StateError('known storage barrier');
          }
        },
      );
      try {
        final repo = owner.wrap(EditorTasks());
        await expectLater(
          repo.save(
            const TaskItem(
              content: 'Actual',
              dueDate: '2026-11-20',
              done: true,
              parentId: 3,
              topicId: 9,
            ),
          ),
          throwsA(isA<TaskCreationNeedsReview>()),
        );
        expect(posts, 1);
        expect(gets, 1);
        final c = owner.controller!;
        expect(c.hasKnownAcknowledgement, true);
        failKnown = false;
        await c.retryAcknowledgement();
        expect(c.record!.actualId, 41);
        expect(c.storageUnconfirmed, false);
        expect(posts, 1);
        expect(gets, 1);
      } finally {
        await owner.retire();
        client.close();
      }
    },
  );
}
