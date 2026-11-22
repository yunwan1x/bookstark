import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';

void main() {
  for (final operation in ['create', 'update', 'done', 'remove']) {
    for (final retire in ['barrier', 'same-token-restore']) {
      test(
        '$operation pending CSRF then $retire never sends mutation',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          var current = true, writes = 0, csrf = 0;
          final client = BookstarkClient(
            'https://task.test/prefix',
            transport: MockClient((request) async {
              if (request.method == 'GET' &&
                  request.url.path == '/prefix/api/csrf-token') {
                csrf++;
                entered.complete();
                await release.future;
                return http.Response(
                  '{"code":0,"data":{}}',
                  200,
                  headers: {
                    'content-type': 'application/json',
                    'set-cookie': 'csrf_token=fixture-csrf; Path=/',
                  },
                );
              }
              writes++;
              throw StateError('Retired task mutation reached HTTP');
            }),
          );
          client.restoreSession({'token': 'fixture-only'});
          addTearDown(client.close);
          final repository = RemoteTasksRepository(
            client,
            isCurrent: () => current,
          );
          final Future<Object?> work = switch (operation) {
            'create' => repository.save(
              const TaskItem(content: 'Exact task', dueDate: '2026-11-11'),
            ),
            'update' => repository.save(
              const TaskItem(
                id: 19,
                content: 'Exact task',
                dueDate: '2026-11-11',
              ),
            ),
            'done' => repository.setDone(19, true).then<Object?>((_) => null),
            _ => repository.remove(19).then<Object?>((_) => null),
          };
          final rejected = expectLater(work, throwsStateError);
          await entered.future;
          if (retire == 'barrier') {
            current = false;
          } else {
            client.restoreSession({'token': 'fixture-only'});
          }
          release.complete();
          await rejected;
          expect(csrf, 1);
          expect(writes, 0);
        },
      );
    }
  }
  for (final stopKind in ['scope', 'abort']) {
    test(
      'SSE $stopKind during CSRF rejects at actual pre-send hook with zero POST',
      () async {
        final entered = Completer<void>(),
            release = Completer<void>(),
            abort = Completer<void>();
        var current = true, posts = 0, hooks = 0;
        final client = BookstarkClient(
          'https://task.test',
          transport: MockClient((request) async {
            if (request.method == 'GET') {
              entered.complete();
              await release.future;
              return http.Response(
                '{"code":0,"data":{}}',
                200,
                headers: {
                  'content-type': 'application/json',
                  'set-cookie': 'csrf_token=fixture-csrf; Path=/',
                },
              );
            }
            posts++;
            return http.Response(
              'data: [DONE]\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        );
        client.restoreSession({'token': 'fixture-only'});
        addTearDown(client.close);
        final future = client
            .postEvents(
              '/api/ai/complete',
              {'scene': 'task', 'messages': <Object>[]},
              abortTrigger: abort.future,
              beforeSubmit: () {
                hooks++;
                if (!current || abort.isCompleted) {
                  throw StateError('Task scope retired');
                }
              },
            )
            .toList();
        final failed = expectLater(
          future,
          throwsA(anyOf(isA<StateError>(), isA<http.ClientException>())),
        );
        await entered.future;
        if (stopKind == 'scope') {
          current = false;
        } else {
          abort.complete();
        }
        release.complete();
        await failed;
        expect(posts, 0);
        expect(hooks, lessThanOrEqualTo(1));
      },
    );
  }
}
