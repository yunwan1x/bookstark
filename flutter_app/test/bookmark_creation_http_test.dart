import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmark_creation_attempt.dart';
import 'package:bookstark_flutter/core/bookmark_creation_http_adapter.dart';

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
            'data': {'bookmark_id': 12},
          });
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      final adapter = BookmarkCreationHttpAdapter(
        client: client,
        memberId: 7,
        namespace: 'fixture-owner',
        isCurrent: () => active,
      );
      final a = BookmarkCreationAttempt(
        scope: adapter.scope,
        key: 'b' * 32,
        body: {
          'title': 'Exact',
          'url': 'https://example.test/',
          'description': '',
          'favicon': '',
          'is_public': false,
          'labels': <String>[],
        },
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
          expect(r.url.path, '/api/bookmarks/create-owned');
          events.add('post');
          return response({
            'code': 0,
            'data': {'bookmark_id': 12},
          });
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
      final a = BookmarkCreationAttempt(
        scope: adapter.scope,
        key: 'c' * 32,
        body: {
          'title': 'Exact',
          'url': 'https://example.test/',
          'description': '\ufeffQuestion\r\n😀',
          'favicon': '',
          'is_public': false,
          'labels': <String>[],
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
            'data': {'bookmark_id': 12},
          });
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
        isCurrent: () => active,
      );
      final a = BookmarkCreationAttempt(
        scope: adapter.scope,
        key: 'e' * 32,
        body: {
          'title': 'Exact',
          'url': 'https://example.test/',
          'description': '',
          'favicon': '',
          'is_public': false,
          'labels': <String>[],
        },
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
}
