import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmark_creation_attempt.dart';
import 'package:bookstark_flutter/core/bookmark_creation_controller.dart';
import 'package:bookstark_flutter/core/bookmark_creation_http_adapter.dart';
import 'package:bookstark_flutter/core/bookmark_creation_store.dart';

http.Response reply(Object data) => http.Response(
  jsonEncode({'code': 0, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final loseAck in [true, false]) {
    test(
      loseAck
          ? 'lost ACK survives cold and changed URL never replays'
          : 'known ID storage failure retries storage only',
      () async {
        final data = <String, String>{};
        var posts = 0, order = 4, flushes = 0, failAck = !loseAck;
        final frozen = <String, Object?>{
          'title': ' exact 😀',
          'url': 'https://example.test/',
          'description': '\ufeffBody\r\n',
          'favicon': 'https://example.test/icon.png',
          'is_public': false,
          'labels': ['comma,label', ' spaced ', ''],
        };
        Map<String, Object?> row() => {
          'bookmark_id': 91,
          ...frozen,
          'label': 'comma,label, spaced ,',
          'member_id': 7,
          'order_sort': order,
          'is_pinned': true,
          'nav_visible': true,
          'create_time': '2026-11-11T01:00:00Z',
          'modify_time': '2026-11-11T02:00:00Z',
        };
        final client = BookstarkClient(
          'https://fixture.invalid',
          transport: MockClient((r) async {
            if (r.url.path.endsWith('/profile')) return reply({'member_id': 7});
            if (r.method == 'POST') {
              expect(r.url.path, '/api/bookmarks/create-owned');
              posts++;
              expect(jsonDecode(r.body), frozen);
              if (loseAck) {
                throw http.ClientException('synthetic applied response lost');
              }
              return reply(row());
            }
            expect(r.url.path, '/api/bookmarks/91/creation-review');
            return reply(row());
          }),
        );
        client.restoreSession({
          'token': 'fixture-token',
          'csrf_token': 'fixture-csrf',
        });
        final adapter = BookmarkCreationHttpAdapter(
          client: client,
          memberId: 7,
          namespace: 'fixture-owner',
          isCurrent: () => true,
        );
        final key = (loseAck ? 'e' : 'f') * 32;
        BookmarkCreationStore store() => BookmarkCreationStore(
          scope: adapter.scope,
          key: key,
          read: (k) async => data[k],
          write: (k, v) async {
            data[k] = v;
          },
          remove: (k) async {
            data.remove(k);
          },
          flush: () async {
            flushes++;
            if (failAck && flushes == 3) {
              throw StateError('synthetic ACK flush failure');
            }
          },
          isCurrent: () => true,
        );
        BookmarkCreationController make() => BookmarkCreationController(
          store: store(),
          prepare: adapter.prepare,
          inspect: adapter.inspect,
        );
        var c = make();
        try {
          final input = BookmarkCreationAttempt(
            scope: adapter.scope,
            key: key,
            body: frozen,
          );
          await c.begin(input);
          await c.submit();
          expect(posts, 1);
          expect(c.record!.phase, BookmarkCreationPhase.unknown);
          if (!loseAck) {
            expect(c.hasKnownAcknowledgement, isTrue);
            failAck = false;
            await c.retryAcknowledgement();
            expect(posts, 1);
            expect(c.record!.actualId, 91);
            expect(c.storageUnconfirmed, isFalse);
          } else {
            c.dispose();
            c = make();
            await c.reload();
            await c.submit();
            expect(posts, 1);
            expect(c.record!.phase, BookmarkCreationPhase.unknown);
            final originalBytes = data.values.single;
            await c.begin(
              BookmarkCreationAttempt(
                scope: adapter.scope,
                key: key,
                body: {...frozen, 'url': 'https://different.test/'},
              ),
            );
            expect(data.values.single, originalBytes);
            expect(posts, 1);
            await c.reload();
            await c.review(91);
            final old = c.reviewed!;
            expect(old.wire['description'], frozen['description']);
            expect(old.wire['is_pinned'], isTrue);
            expect(old.wire['nav_visible'], isTrue);
            // Full actual metadata changed after review: adoption refuses, zero POST.
            order++;
            await c.adopt(old);
            expect(c.record!.phase, BookmarkCreationPhase.unknown);
            expect(posts, 1);
            await c.review(91);
            await c.adopt(c.reviewed!);
            expect(c.record!.actualId, 91);
            expect(posts, 1);
          }
          final actual = c.record!;
          await c.end(actual);
          expect(data, isEmpty);
          expect(c.endedDurably, isTrue);
          expect(posts, 1);
        } finally {
          c.dispose();
          adapter.retire();
          client.close();
        }
      },
    );
  }
}
