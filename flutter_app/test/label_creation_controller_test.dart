import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/label_creation_attempt.dart';
import 'package:bookstark_flutter/core/label_creation_controller.dart';
import 'package:bookstark_flutter/core/label_creation_http_adapter.dart';
import 'package:bookstark_flutter/core/label_creation_store.dart';
import 'package:bookstark_flutter/core/label_creation_slot.dart';

http.Response response(Object body) => http.Response(
  jsonEncode({'code': 0, 'data': body}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  for (final loseAck in [true, false]) {
    test(
      loseAck
          ? 'cold changed name and global relation changes never replay unknown POST'
          : 'actual positive label ACK retries only storage after flush failure',
      () async {
        final values = <String, String>{};
        var posts = 0, extra = false, flushes = 0, failAck = !loseAck;
        final frozen = {'label_name': ' 研究/Flutter '};
        Map<String, Object?> actual() => {
          'label_id': 42,
          'label_name': frozen['label_name'],
          'book_count': extra ? 2 : 1,
          'blog_count': 0,
          'bookmark_count': 0,
          'document_count': 0,
          'relation_count': extra ? 2 : 1,
          'relations': [
            {
              'id': 3,
              'resource_id': 8,
              'relation_type': 'book',
              'created_at': '2026-11-11T01:00:00Z',
            },
            if (extra)
              {
                'id': 4,
                'resource_id': 9,
                'relation_type': 'book',
                'created_at': '2026-11-11T02:00:00Z',
              },
          ],
        };
        final client = BookstarkClient(
          'https://fixture.invalid',
          transport: MockClient((r) async {
            if (r.url.path.endsWith('/profile')) {
              return response({'member_id': 7});
            }
            if (r.method == 'POST') {
              posts++;
              expect(r.url.path, '/api/labels');
              expect(jsonDecode(r.body), frozen);
              if (loseAck) {
                throw http.ClientException(
                  'synthetic actual insert with lost reply',
                );
              }
              return response({
                'label_id': 42,
                'label_name': frozen['label_name'],
              });
            }
            expect(r.url.path, '/api/label-creation-review/42');
            return response(actual());
          }),
        );
        client.restoreSession({
          'token': 'fixture-token',
          'csrf_token': 'fixture-csrf',
        });
        final adapter = LabelCreationHttpAdapter(
          client: client,
          memberId: 7,
          namespace: 'fixture-owner',
          isCurrent: () => true,
        );
        final key = (loseAck ? 'b' : 'c') * 32;
        LabelCreationStore store() => LabelCreationStore(
          scope: adapter.scope,
          key: key,
          read: (k) async => values[k],
          write: (k, v) async {
            values[k] = v;
          },
          remove: (k) async {
            values.remove(k);
          },
          flush: () async {
            flushes++;
            if (failAck && flushes == 3) {
              throw StateError('synthetic flush failure');
            }
          },
          isCurrent: () => true,
        );
        LabelCreationController make() => LabelCreationController(
          store: store(),
          prepare: adapter.prepare,
          inspect: adapter.inspect,
        );
        var c = make();
        try {
          await c.begin(
            LabelCreationAttempt(scope: adapter.scope, key: key, body: frozen),
          );
          await c.submit();
          expect(posts, 1);
          expect(c.record!.phase, LabelCreationPhase.unknown);
          if (!loseAck) {
            expect(c.hasKnownAcknowledgement, isTrue);
            failAck = false;
            await c.retryAcknowledgement();
            expect(posts, 1);
            expect(c.record!.actualId, 42);
            expect(c.record!.origin, LabelCreationOrigin.postAcknowledgement);
            expect(
              LabelCreationAttempt.decode(values.values.single).origin,
              LabelCreationOrigin.postAcknowledgement,
            );
          } else {
            c.dispose();
            c = make();
            await c.reload();
            await c.submit();
            expect(posts, 1);
            final before = values.values.single;
            await c.begin(
              LabelCreationAttempt(
                scope: adapter.scope,
                key: key,
                body: {'label_name': 'changed-name'},
              ),
            );
            expect(values.values.single, before);
            expect(posts, 1);
            await c.reload();
            await c.review(42);
            final old = c.reviewed!;
            expect(old.wire.containsKey('member_id'), isFalse);
            expect(old.wire['relations'], hasLength(1));
            extra = true;
            await c.adopt(old);
            expect(c.record!.phase, LabelCreationPhase.unknown);
            expect(posts, 1);
            await c.review(42);
            await c.adopt(c.reviewed!);
            expect(c.record!.actualId, 42);
            expect(posts, 1);
            expect(c.record!.origin, LabelCreationOrigin.manualExisting);
            expect(
              LabelCreationAttempt.decode(values.values.single).origin,
              LabelCreationOrigin.manualExisting,
            );
          }
          final captured = c.record!;
          await c.end(captured);
          expect(values, isEmpty);
          expect(posts, 1);
        } finally {
          c.dispose();
          adapter.retire();
          client.close();
        }
      },
    );
  }
  test(
    'strict journal and account slot retain unknown across renamed intent',
    () async {
      final values = <String, String>{}, scope = 'e' * 64;
      LabelCreationSlot slot() => LabelCreationSlot(
        scope: scope,
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
      final first = await slot().open(), cold = await slot().open();
      expect(first.created, isTrue);
      expect(cold.created, isFalse);
      expect(cold.key, first.key);
      final a = LabelCreationAttempt(
        scope: scope,
        key: first.key,
        body: {'label_name': ' 研究/Flutter '},
      );
      expect(utf8.encode(a.body['label_name'] as String).length, 16);
      final raw = a.encode(),
          duplicate = '${raw.substring(0, raw.length - 1)},"phase":"unknown"}';
      expect(
        () => LabelCreationAttempt.decode(duplicate),
        throwsFormatException,
      );
      expect(
        () => a.next(LabelCreationPhase.knownID, 42),
        throwsFormatException,
      );
      final manual = a.next(
        LabelCreationPhase.knownID,
        42,
        LabelCreationOrigin.manualExisting,
      );
      expect(
        LabelCreationAttempt.decode(manual.encode()).origin,
        LabelCreationOrigin.manualExisting,
      );
      final store = LabelCreationStore(
        scope: scope,
        key: first.key,
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
      final lease = Object();
      store.acquire(lease);
      try {
        await store.insert(a, lease);
        await store.claim(a, lease);
        await expectLater(
          store.claim(a, lease),
          throwsA(isA<LabelCreationStorageUnconfirmed>()),
        );
        final unknown = a.next(LabelCreationPhase.unknown);
        await store.end(unknown, lease);
        await expectLater(
          store.acknowledge(
            unknown,
            42,
            lease,
            origin: LabelCreationOrigin.postAcknowledgement,
          ),
          throwsA(isA<LabelCreationStorageUnconfirmed>()),
        );
        expect(values.containsKey(store.metadataKey), isFalse);
      } finally {
        store.release(lease);
      }
      await slot().clear(first.key);
      expect((await slot().open()).key, isNot(first.key));
    },
  );
}
