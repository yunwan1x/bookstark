import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_http_adapter.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> taskRow({int member = 7}) => {
  'task_id': 41,
  'member_id': member,
  'content': 'Actual',
  'due_date': '2026-11-20',
  'done': true,
  'parent_id': 3,
  'topic_id': 9,
  'complete_time': '2026-11-11T08:00:00Z',
  'create_time': '2026-11-11T07:00:00Z',
  'modify_time': '2026-11-11T08:00:00Z',
  'child_total': 0,
  'child_done': 0,
  'comment_count': 0,
};
TaskCreationAttempt attempt(TaskCreationHttpAdapter a) => TaskCreationAttempt(
  scope: a.scope,
  key: 'a' * 32,
  body: {
    'content': 'Actual',
    'due_date': '2026-11-20',
    'done': true,
    'parent_id': 3,
    'topic_id': 9,
  },
);
void main() {
  test(
    'prepared real task POST awaits durable barrier; failure sends zero mutations',
    () async {
      var posts = 0;
      final entered = Completer<void>(), release = Completer<void>();
      final client = BookstarkClient(
        'https://fixture.invalid/prefix',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          posts++;
          expect(r.method, 'POST');
          expect(r.url.path, '/prefix/api/tasks');
          return reply({'code': 0, 'data': taskRow()});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = TaskCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'test-space',
        isCurrent: () => true,
      );
      try {
        final prepared = await adapter.prepare(attempt(adapter));
        try {
          final work = prepared.sendAfter(
            onSubmit: () async {
              entered.complete();
              await release.future;
              throw StateError('flush failed');
            },
          );
          final rejected = expectLater(work, throwsStateError);
          await entered.future;
          expect(posts, 0);
          release.complete();
          await rejected;
          expect(posts, 0);
        } finally {
          prepared.retire();
        }
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
  test(
    'readable admin foreign owner is not adopted as initiating member task',
    () async {
      var reads = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          expect(r.method, 'GET');
          expect(r.url.path, '/api/tasks/41');
          reads++;
          return reply({'code': 0, 'data': taskRow(member: 8)});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = TaskCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'test-space',
        isCurrent: () => true,
      );
      try {
        await expectLater(
          adapter.inspect(attempt(adapter), 41),
          throwsFormatException,
        );
        expect(reads, 1);
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
  test(
    'fresh same-ID task includes date completion parent topic and actual version',
    () async {
      var version = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          final row = taskRow();
          if (version++ > 0) row['modify_time'] = '2026-11-11T09:00:00Z';
          return reply({'code': 0, 'data': row});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = TaskCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'test-space',
        isCurrent: () => true,
      );
      try {
        final first = await adapter.inspect(attempt(adapter), 41);
        final fresh = await adapter.inspect(attempt(adapter), 41);
        expect(first.matchesFrozenInput, true);
        expect(fresh.matchesFrozenInput, true);
        expect(first.fingerprint, isNot(fresh.fingerprint));
        expect(first.wire['parent_id'], 3);
        expect(first.wire['topic_id'], 9);
        expect(first.wire['done'], true);
        expect(first.wire['due_date'], '2026-11-20');
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
}
