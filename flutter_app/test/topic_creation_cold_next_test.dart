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
    'applied POST dropped ACK cold reentry never replays; explicit fresh ID adopts storage only',
    () async {
      var posts = 0, created = false, changed = false;
      final values = <String, String>{};
      http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return json({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.method == 'POST') {
            posts++;
            created = true;
            throw http.ClientException('Dropped actual ACK');
          }
          expect(created, isTrue);
          expect(r.url.path, '/api/topic-creation-review/topic/128');
          return json({
            'code': 0,
            'data': {
              'topic_id': 128,
              'member_id': 7,
              'title': 'Exact',
              'question': changed ? 'External change' : '\ufeffExact\r\n😀',
              'is_pinned': 0,
              'create_time': '2026-11-11T01:00:00Z',
              'modify_time': '2026-11-11T01:00:00Z',
            },
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
      TopicCreationStore store() => TopicCreationStore(
        scope: adapter.scope,
        key: '9' * 32,
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
      TopicCreationController make() => TopicCreationController(
        store: store(),
        prepare: adapter.prepare,
        inspect: adapter.inspect,
      );
      var c = make();
      try {
        await c.begin(
          TopicCreationAttempt(
            scope: adapter.scope,
            key: '9' * 32,
            kind: TopicCreationKind.topic,
            topicId: 0,
            target: '',
            targetId: 0,
            body: {
              'title': 'Exact',
              'question': '\ufeffExact\r\n😀',
              'is_pinned': false,
            },
          ),
        );
        await c.submit();
        expect(posts, 1);
        expect(c.record!.phase, TopicCreationPhase.unknown);
        c.dispose();
        c = make();
        await c.reload();
        expect(c.record!.phase, TopicCreationPhase.unknown);
        await c.submit();
        expect(posts, 1); // no automatic or explicit unknown POST
        await c.review(128);
        final reviewed = c.reviewed!;
        expect(reviewed.display, contains('modify_time'));
        changed = true;
        await c.adopt(reviewed);
        expect(c.record!.phase, TopicCreationPhase.unknown);
        expect(posts, 1);
        changed = false;
        await c.review(128);
        await c.adopt(c.reviewed!);
        expect(c.record!.phase, TopicCreationPhase.knownID);
        expect(c.record!.actualId, 128);
        expect(posts, 1);
        expect(await c.verifyKnown(c.reviewed!), isTrue);
        final bytes = values.values.single;
        expect(
          TopicCreationAttempt.decode(bytes).body['question'],
          '\ufeffExact\r\n😀',
        );
      } finally {
        c.dispose();
        adapter.retire();
        client.close();
      }
    },
  );
}
