import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';

import 'package:bookstark_flutter/features/admin/admin_dashboard_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FixtureClient extends MockClient {
  _FixtureClient(this.reply) : super((_) async => http.Response('', 500));
  final Future<http.Response> Function(http.Request) reply;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw StateError('Expected JSON request');
    }
    requests.add(request);
    final response = await reply(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'uses same-origin authenticated GETs and approved range/page parameters',
    () async {
      final transport = _FixtureClient((request) async {
        switch (request.url.path) {
          case '/prefix/api/admin/dashboard/stats':
            return jsonResponse({
              'code': 0,
              'data': {'total_visits': 12, 'unique_ips': 8},
            });
          case '/prefix/api/admin/dashboard/trend':
            return jsonResponse({
              'code': 0,
              'data': [
                {'time': '2026-11-07', 'page_views': 12, 'unique_ips': 8},
              ],
            });
          case '/prefix/api/admin/dashboard/logs':
            return jsonResponse({
              'code': 0,
              'data': [
                {
                  'visit_id': 5,
                  'ip': '192.0.2.8',
                  'path': '/notes',
                  'member_id': 0,
                  'visit_time': '2026-11-07T01:02:03Z',
                  'account': '',
                  'ip_info_url': 'https://ipinfo.io/192.0.2.8',
                },
              ],
              'total': 1,
              'page': 1,
              'page_size': 20,
              'total_pages': 1,
            });
          default:
            return jsonResponse({
              'code': 404,
              'message': 'unexpected',
            }, status: 404);
        }
      });
      final client = BookstarkClient(
        'https://example.test/prefix',
        transport: transport,
      )..restoreSession({'token': 'test-token'});
      final repository = AdminDashboardRepository(client);

      expect((await repository.stats(DashboardRange.days7)).totalVisits, 12);
      expect(
        (await repository.trend(DashboardRange.hours24)).single.bucketLabel,
        '2026-11-07',
      );
      final logs = await repository.logs(1);
      expect(logs.items.single.anonymous, isTrue);

      expect(transport.requests, hasLength(3));
      expect(
        transport.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        transport.requests.every(
          (request) => request.url.host == 'example.test',
        ),
        isTrue,
      );
      expect(transport.requests.map((request) => request.url.path).toList(), [
        '/prefix/api/admin/dashboard/stats',
        '/prefix/api/admin/dashboard/trend',
        '/prefix/api/admin/dashboard/logs',
      ]);
      expect(transport.requests[0].url.queryParameters['range'], '7d');
      expect(transport.requests[1].url.queryParameters['range'], '24h');
      expect(transport.requests[2].url.queryParameters, {
        'page': '1',
        'pageSize': '20',
      });
      expect(
        transport.requests.every(
          (request) =>
              request.headers['cookie']?.contains('token=test-token') ?? false,
        ),
        isTrue,
      );
      client.close();
    },
  );

  test(
    'strict metric, trend date and log timestamp parsing rejects bad types and impossible dates',
    () {
      expect(
        () => DashboardStats.fromJson({'total_visits': 1.0, 'unique_ips': 0}),
        throwsFormatException,
      );
      expect(
        () => DashboardStats.fromJson({'total_visits': -1, 'unique_ips': 0}),
        throwsFormatException,
      );
      expect(
        () => DashboardTrendPoint.fromJson({
          'time': '2026-02-30',
          'page_views': 2,
          'unique_ips': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => DashboardTrendPoint.fromJson({
          'time': '2026-11-07 25:00',
          'page_views': 2,
          'unique_ips': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => DashboardVisitLog.fromJson({
          'visit_id': 1,
          'ip': '203.0.113.9',
          'path': '/',
          'member_id': 2,
          'visit_time': '2026-11-07T01:02:03',
          'account': 'reader',
        }),
        throwsFormatException,
      );
      for (final invalidTime in [
        '2026-02-30T01:02:03Z',
        '2026-13-01T01:02:03Z',
        '2026-11-07T25:02:03Z',
        '2026-11-07T01:60:03Z',
        '2026-11-07T01:02:60Z',
        '2026-11-07T01:02:03+24:00',
        '2026-11-07T01:02:03-00:60',
      ]) {
        expect(
          () => DashboardVisitLog.fromJson({
            'visit_id': 1,
            'ip': '203.0.113.9',
            'path': '/',
            'member_id': 2,
            'visit_time': invalidTime,
            'account': 'reader',
          }),
          throwsFormatException,
          reason: invalidTime,
        );
      }
      expect(
        DashboardVisitLog.fromJson({
          'visit_id': 1,
          'ip': '203.0.113.9',
          'path': '/',
          'member_id': 2,
          'visit_time': '2026-11-07T01:02:03.123456789+23:59',
          'account': 'reader',
        }).visitTime,
        isA<DateTime>(),
      );
    },
  );

  test(
    'strict pagination validates page identity, bounds and server page-count semantics',
    () {
      final base = {
        'code': 0,
        'data': <Object?>[],
        'total': 0,
        'page': 1,
        'page_size': 20,
        'total_pages': 1,
      };
      expect(
        DashboardLogPage.fromEnvelope(base, requestedPage: 1).totalPages,
        1,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'page': 2,
        }, requestedPage: 1),
        throwsFormatException,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'total_pages': 0,
        }, requestedPage: 1),
        throwsFormatException,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'page_size': 101,
          'total_pages': 1,
        }, requestedPage: 1),
        throwsFormatException,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'page_size': 10,
          'total_pages': 1,
        }, requestedPage: 1),
        throwsFormatException,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'page_size': 21,
          'total_pages': 1,
        }, requestedPage: 1),
        throwsFormatException,
      );
      expect(
        () => DashboardLogPage.fromEnvelope({
          ...base,
          'total': 41,
          'total_pages': 1,
        }, requestedPage: 1),
        throwsFormatException,
      );
    },
  );

  test(
    'API permission and server failures remain ApiFailure with status',
    () async {
      final transport = _FixtureClient(
        (request) async =>
            jsonResponse({'code': 403, 'message': '需要管理员权限'}, status: 403),
      );
      final client = BookstarkClient(
        'https://example.test',
        transport: transport,
      );
      await expectLater(
        AdminDashboardRepository(client).stats(DashboardRange.days7),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 403),
        ),
      );
      expect(transport.requests.single.method, 'GET');
      client.close();
    },
  );

  test(
    'nil Go trend slice is a valid empty result while malformed values fail',
    () async {
      final transport = _FixtureClient(
        (request) async => jsonResponse({'code': 0, 'data': null}),
      );
      final client = BookstarkClient(
        'https://example.test',
        transport: transport,
      );
      expect(
        await AdminDashboardRepository(client).trend(DashboardRange.days7),
        isEmpty,
      );
      client.close();

      expect(
        () => DashboardTrendPoint.fromJson({
          'time': 'not-a-date',
          'page_views': 0,
          'unique_ips': 0,
        }),
        throwsFormatException,
      );
    },
  );

  test('range enum sends only the server allowlist', () {
    expect(DashboardRange.values.map((range) => range.queryValue), [
      '24h',
      '7d',
      '30d',
      '90d',
    ]);
  });

  test('24 hour source still documents day granularity', () {
    expect(DashboardRange.hours24.bucketDescription, 'daily');
  });
}
