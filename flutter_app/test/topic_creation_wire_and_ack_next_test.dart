import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/topic_creation_attempt.dart';
import 'package:bookstark_flutter/core/topic_creation_controller.dart';
import 'package:bookstark_flutter/core/topic_creation_http_adapter.dart';
import 'package:bookstark_flutter/core/topic_creation_store.dart';

void main() {
  test(
    'persisted attempt rejects duplicate phase and malformed Unicode but preserves exact source',
    () {
      final a = TopicCreationAttempt(
        scope: 'd' * 64,
        key: '3' * 32,
        kind: TopicCreationKind.summary,
        topicId: 9,
        target: '',
        targetId: 0,
        body: {
          'content': '\ufeffActual\r\n😀',
          'summary_type': 'manual',
          'order_sort': 0,
        },
      );
      final raw = a.encode();
      expect(
        TopicCreationAttempt.decode(raw).body['content'],
        a.body['content'],
      );
      final duplicate =
          '${raw.substring(0, raw.length - 1)},"phase":"unknown"}';
      expect(
        () => TopicCreationAttempt.decode(duplicate),
        throwsFormatException,
      );
      final malformed = raw.replaceFirst('Actual', r'\ud800');
      expect(
        () => TopicCreationAttempt.decode(malformed),
        throwsFormatException,
      );
    },
  );
  test(
    'positive ACK survives failed follow-up read and retry is strictly storage only',
    () async {
      final values = <String, String>{};
      var posts = 0;
      http.Response response(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return response({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.method == 'POST') {
            posts++;
            return response({
              'code': 0,
              'data': {'topic_id': 92},
            });
          }
          throw http.ClientException('synthetic follow-up read failure');
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
      final store = TopicCreationStore(
        scope: adapter.scope,
        key: '7' * 32,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final c = TopicCreationController(
        store: store,
        prepare: adapter.prepare,
        inspect: adapter.inspect,
      );
      try {
        await c.begin(
          TopicCreationAttempt(
            scope: adapter.scope,
            key: '7' * 32,
            kind: TopicCreationKind.topic,
            topicId: 0,
            target: '',
            targetId: 0,
            body: {
              'title': 'Exact',
              'question': 'question',
              'is_pinned': false,
            },
          ),
        );
        await c.submit();
        expect(posts, 1);
        expect(c.hasKnownAcknowledgement, isTrue);
        expect(c.record!.phase, TopicCreationPhase.unknown);
        await c.retryAcknowledgement();
        expect(posts, 1);
        expect(c.record!.phase, TopicCreationPhase.knownID);
        expect(c.record!.actualId, 92);
        await c.review(92);
        expect(c.reviewed, isNull);
        expect(c.error, isNotNull);
        expect(
          posts,
          1,
        ); // A missing read never supplies fake content or another POST.
      } finally {
        c.dispose();
        adapter.retire();
        client.close();
      }
    },
  );
}
