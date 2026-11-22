import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/summary_editor_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

http.Response jsonReply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'owned summary actual source transport bounds response and never follows redirect',
    () async {
      for (final redirect in [false, true]) {
        var calls = 0;
        final client = BookstarkClient(
          'https://summary.test',
          transport: MockClient((request) async {
            calls++;
            expect(request.url.host, 'summary.test');
            expect(request.url.path, '/api/topics/1/summaries/2/content');
            expect(request.followRedirects, isFalse);
            return redirect
                ? http.Response(
                    '',
                    302,
                    headers: {'location': 'https://foreign.test/'},
                  )
                : http.Response(
                    'x' * (256 * 1024 + 1),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
          }),
        );
        try {
          final repo = RemoteTopicsRepository(client, memberId: 7);
          await expectLater(
            repo.readSummaryForEditing(1, 2),
            throwsA(anyOf(isA<FormatException>(), isA<ApiFailure>())),
          );
          expect(calls, 1);
        } finally {
          client.close();
        }
      }
    },
  );
  test(
    'source-only summary mutation held at real CSRF cannot submit after owner retirement',
    () async {
      final reached = Completer<void>(), csrf = Completer<http.Response>();
      var current = true, writes = 0;
      final client = BookstarkClient(
        'https://summary.test',
        transport: MockClient((request) async {
          if (request.url.path == '/api/csrf-token') {
            reached.complete();
            return csrf.future;
          }
          writes++;
          return jsonReply({});
        }),
      );
      try {
        final repo = RemoteTopicsRepository(
          client,
          memberId: 7,
          isCurrent: () => current,
        );
        final rejected = expectLater(
          repo.saveSummaryContent(
            const TopicSummary(id: 2, topicId: 1, content: 'old'),
            'new',
          ),
          throwsA(isA<StateError>()),
        );
        await reached.future;
        current = false;
        csrf.complete(
          http.Response(
            '{}',
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'csrf_token=${'a' * 64}; Path=/',
            },
          ),
        );
        await rejected;
        expect(writes, 0);
      } finally {
        client.close();
      }
    },
  );
  test(
    'lost source-only PUT reply has no automatic replay and explicit read returns actual metadata',
    () async {
      var writes = 0, source = 'old body';
      final client = BookstarkClient(
        'https://summary.test',
        transport: MockClient((request) async {
          if (request.url.path == '/api/csrf-token') {
            return http.Response(
              '{}',
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=${'a' * 64}; Path=/',
              },
            );
          }
          expect(request.url.path, '/api/topics/1/summaries/2/content');
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map;
            expect(body.keys.toSet(), {'content', 'expected_source_sha256'});
            writes++;
            source = body['content'] as String;
            throw http.ClientException('owned lost reply');
          }
          return jsonReply({
            'code': 0,
            'data': {
              'summary_id': 2,
              'topic_id': 1,
              'content': source,
              'summary_type': 'ai',
              'order_sort': 99,
              'comment_count': 0,
              'create_time': '2026-11-11T11:00:00',
              'modify_time': '2026-11-11T12:00:00',
            },
          });
        }),
      );
      try {
        final repo = RemoteTopicsRepository(client, memberId: 7);
        final editor = SummaryEditorRepository(
          repo,
          const TopicSummary(id: 2, topicId: 1, content: 'old body'),
        );
        await expectLater(
          editor.save(const Note(id: 2, title: '', content: 'new body')),
          throwsA(anything),
        );
        await Future<void>.delayed(Duration.zero);
        expect(writes, 1);
        final actual = await editor.read(2);
        expect(actual.content, 'new body');
        expect(writes, 1);
        await expectLater(editor.read(3), throwsFormatException);
        expect(writes, 1);
      } finally {
        client.close();
      }
    },
  );

  test(
    'missing and oversized raw summary are rejected without writes or fake empty source',
    () async {
      for (final missing in [true, false]) {
        var calls = 0;
        final client = BookstarkClient(
          'https://summary.test',
          transport: MockClient((request) async {
            calls++;
            expect(request.method, 'GET');
            return jsonReply({
              'code': 0,
              'data': {
                'summary_id': 2,
                'topic_id': 1,
                if (!missing) 'content': 'x' * 80001,
                'summary_type': 'manual',
                'order_sort': 3,
                'comment_count': 0,
                'create_time': '2026-11-11T11:00:00',
                'modify_time': '2026-11-11T12:00:00',
              },
            });
          }),
        );
        try {
          final repo = RemoteTopicsRepository(client, memberId: 7);
          await expectLater(
            repo.readSummaryForEditing(1, 2),
            throwsFormatException,
          );
          expect(calls, 1);
        } finally {
          client.close();
        }
      }
    },
  );
}
