import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/topic_creation_attempt.dart';
import 'package:bookstark_flutter/core/topic_creation_http_adapter.dart';

http.Response response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'held real CSRF precedes durable claim and owner retirement sends zero POST',
    () async {
      final csrfEntered = Completer<void>(), release = Completer<void>();
      var active = true, posts = 0, claims = 0;
      final client = BookstarkClient(
        'https://fixture.invalid/prefix',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return response({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.url.path.endsWith('/csrf-token')) {
            csrfEntered.complete();
            await release.future;
            return response({'code': 0, 'csrf_token': 'fixture-csrf'});
          }
          posts++;
          return response({
            'code': 0,
            'data': {'topic_id': 12},
          });
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      final adapter = TopicCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'fixture-owner',
        isCurrent: () => active,
      );
      final a = TopicCreationAttempt(
        scope: adapter.scope,
        key: 'b' * 32,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        body: {'title': 'Exact', 'question': 'Question', 'is_pinned': false},
      );
      try {
        final operation = () async {
          final prepared = await adapter.prepare(a);
          await prepared.sendAfter(
            onSubmit: () async {
              claims++;
            },
          );
        }();
        final rejected = expectLater(operation, throwsStateError);
        await csrfEntered.future;
        active = false;
        release.complete();
        await rejected;
        expect(posts, 0);
        expect(claims, 0);
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
  test(
    'actual prepared POST cannot run until awaited durable claim completes',
    () async {
      final durableEntered = Completer<void>(), release = Completer<void>();
      final events = <String>[];
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return response({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          expect(r.method, 'POST');
          expect(r.url.path, '/api/topics');
          events.add('post');
          return response({
            'code': 0,
            'data': {'topic_id': 12},
          });
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = TopicCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'fixture-owner',
        isCurrent: () => true,
      );
      final a = TopicCreationAttempt(
        scope: adapter.scope,
        key: 'c' * 32,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        body: {
          'title': 'Exact',
          'question': '\ufeffQuestion\r\n😀',
          'is_pinned': false,
        },
      );
      try {
        final prepared = await adapter.prepare(a);
        final sending = prepared.sendAfter(
          onSubmit: () async {
            durableEntered.complete();
            await release.future;
            events.add('durable');
          },
        );
        await durableEntered.future;
        expect(events, isEmpty);
        release.complete();
        await sending;
        expect(events, ['durable', 'post']);
        await expectLater(
          prepared.sendAfter(onSubmit: () async {}),
          throwsA(isA<ApiFailure>()),
        );
        expect(events, ['durable', 'post']);
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
  test(
    'owner retiring inside awaited durable boundary blocks actual send',
    () async {
      var active = true, posts = 0, claims = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return response({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          posts++;
          return response({
            'code': 0,
            'data': {'topic_id': 12},
          });
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = TopicCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'fixture-owner',
        isCurrent: () => active,
      );
      final a = TopicCreationAttempt(
        scope: adapter.scope,
        key: 'e' * 32,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        body: {'title': 'Exact', 'question': 'Question', 'is_pinned': false},
      );
      try {
        final prepared = await adapter.prepare(a);
        await expectLater(
          prepared.sendAfter(
            onSubmit: () async {
              claims++;
              await Future<void>.value();
              active = false;
            },
          ),
          throwsStateError,
        );
        expect(claims, 1);
        expect(posts, 0);
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
  test(
    'complete actual-ID review retains BOM and rejects wrong parent or oversize body',
    () async {
      var wrongParent = false, oversize = false;
      final exact = '\ufeffExact\r\n😀';
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/profile')) {
            return response({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          expect(r.url.path, '/api/topic-creation-review/summary/12');
          return response({
            'code': 0,
            'data': {
              'summary_id': 12,
              'topic_id': wrongParent ? 10 : 9,
              'member_id': 7,
              'content': oversize ? 'a' * 80001 : exact,
              'summary_type': 'manual',
              'order_sort': 3,
              'comment_count': 0,
              'create_time': '2026-11-11T01:00:00Z',
              'modify_time': '2026-11-11T01:00:00Z',
            },
          });
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      final adapter = TopicCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'fixture-owner',
        isCurrent: () => true,
      );
      final a = TopicCreationAttempt(
        scope: adapter.scope,
        key: 'd' * 32,
        kind: TopicCreationKind.summary,
        topicId: 9,
        target: '',
        targetId: 0,
        body: {'content': exact, 'summary_type': 'manual', 'order_sort': 3},
      );
      try {
        final actual = await adapter.inspect(a, 12);
        expect(actual.matchesFrozenInput, isTrue);
        expect(actual.wire['content'], exact);
        expect(actual.display, contains('order_sort'));
        wrongParent = true;
        await expectLater(adapter.inspect(a, 12), throwsFormatException);
        wrongParent = false;
        oversize = true;
        await expectLater(adapter.inspect(a, 12), throwsFormatException);
      } finally {
        adapter.retire();
        client.close();
      }
    },
  );
}
