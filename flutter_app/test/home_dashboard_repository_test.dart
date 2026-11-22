import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:bookstark_flutter/core/home_dashboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonReply(
  Object value, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);
http.Response csrf() =>
    jsonReply({'code': 0}, headers: {'set-cookie': 'csrf_token=owned; Path=/'});

void main() {
  test(
    'load retains server prefix and typed filters without trusting URL hints',
    () async {
      late Uri seen;
      final client = BookstarkClient(
        'https://books.example/team',
        transport: MockClient((request) async {
          seen = request.url;
          return jsonReply({
            'code': 0,
            'sections': [
              {
                'key': 'notes',
                'total': 1,
                'items': [
                  {
                    'id': 7,
                    'title': 'Actual note',
                    'url': 'javascript:alert(1)',
                  },
                ],
              },
            ],
            'recent': [
              {
                'type': 'article',
                'id': 8,
                'title': 'Actual article',
                'url': 'https://other.invalid/steal',
              },
            ],
            'layout': null,
            'activity': {'2024-02-29': 2},
          });
        }),
      );
      addTearDown(client.close);
      final value = await RemoteHomeDashboardRepository(client).load(
        HomeQuery(
          month: DateTime(2024, 2),
          end: '2024-02-29',
          limit: 20,
          order: 'created',
        ),
      );
      expect(seen.path, '/team/api/home');
      expect(seen.queryParameters['end'], '2024-02-29');
      expect(seen.queryParameters['limit'], '20');
      expect(value.recent.single.route, 'blog/8');
      expect(value.sections.single.items.single.id, 7);
      expect(value.layout.length, 9);
    },
  );
  test(
    'saving visible changes retains hidden unavailable module settings and uses CSRF',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://books.example/team',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/csrf-token')) return csrf();
          expect(request.method, 'PUT');
          expect(request.url.path, '/team/api/home/layout');
          expect(request.headers['X-CSRF-Token'], 'owned');
          writes++;
          final body = jsonDecode(request.body) as Map;
          final items = body['layout'] as List;
          expect(items.length, 9);
          expect(items.first, {'key': 'assets', 'width': 3, 'hidden': true});
          return jsonReply({'code': 0, 'layout': items});
        }),
      );
      addTearDown(client.close);
      final result = await RemoteHomeDashboardRepository(client).saveLayout([
        const HomeLayoutItem(key: 'assets', width: 3, hidden: true),
        const HomeLayoutItem(key: 'notes', width: 2),
      ]);
      expect(writes, 1);
      expect(result.first.hidden, true);
      expect(result[1].width, 2);
    },
  );
  test(
    'invalid desired layout fails locally before any HTTP request',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((_) async {
          requests++;
          return csrf();
        }),
      );
      addTearDown(client.close);
      await expectLater(
        RemoteHomeDashboardRepository(client).saveLayout([
          const HomeLayoutItem(key: 'notes'),
          const HomeLayoutItem(key: 'notes'),
        ]),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );
  test(
    'missing save receipt remains unknown and is never automatically replayed',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((request) async {
          if (request.method == 'GET') return csrf();
          writes++;
          return jsonReply({'code': 0});
        }),
      );
      addTearDown(client.close);
      await expectLater(
        RemoteHomeDashboardRepository(client).saveLayout(readHomeLayout(null)),
        throwsA(isA<HomeWriteUnconfirmed>()),
      );
      expect(writes, 1);
    },
  );
  test(
    'clear visits preserves explicit permission rejection rather than unknown success',
    () async {
      var deletes = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((request) async {
          if (request.method == 'GET') return csrf();
          deletes++;
          return jsonReply({'code': 403, 'message': 'Denied'}, status: 403);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        RemoteHomeDashboardRepository(client).clearVisits(),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)),
      );
      expect(deletes, 1);
    },
  );
  test(
    'write timeout retires the request and never schedules another mutation',
    () async {
      final reply = Completer<http.Response>();
      var writes = 0;
      final client = BookstarkClient(
        'https://books.example',
        transport: MockClient((request) async {
          if (request.method == 'GET') return csrf();
          writes++;
          return reply.future;
        }),
      );
      addTearDown(client.close);
      final repository = RemoteHomeDashboardRepository(
        client,
        deadline: const Duration(milliseconds: 30),
      );
      await expectLater(
        repository.clearVisits(),
        throwsA(isA<HomeWriteUnconfirmed>()),
      );
      reply.complete(jsonReply({'code': 0}));
      await Future<void>.delayed(Duration.zero);
      expect(writes, 1);
    },
  );
}
