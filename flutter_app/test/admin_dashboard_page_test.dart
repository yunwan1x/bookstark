import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';

import 'package:bookstark_flutter/features/admin/admin_dashboard_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_page.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _DashboardHttp extends MockClient {
  _DashboardHttp(this.respond) : super((_) async => http.Response('', 500));
  final Future<http.Response> Function(http.Request request) respond;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    requests.add(copy);
    final response = await respond(copy);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _stats(int count) => {
  'code': 0,
  'data': {'total_visits': count, 'unique_ips': count ~/ 2},
};
Map<String, Object?> _trend(int count) => {
  'code': 0,
  'data': [
    {'time': '2026-11-01', 'page_views': count, 'unique_ips': count ~/ 2},
    {
      'time': '2026-11-02',
      'page_views': count + 1,
      'unique_ips': count ~/ 2 + 1,
    },
  ],
};
String _path(int page) =>
    '/a/${List.filled(14, 'long-segment').join('/')}/$page';
String _account() =>
    'reader@example.test ${List.filled(8, 'long-account-segment').join(' ')}';

Map<String, Object?> _longLogs() {
  final result = _logs(1);
  final row = (result['data'] as List).single as Map<String, Object?>;
  row['member_id'] = 7;
  row['ip'] = '203.0.113.200';
  row['path'] = _path(2);
  row['account'] = _account();
  return result;
}

Map<String, Object?> _logs(int page) => {
  'code': 0,
  'data': [
    {
      'visit_id': page,
      'ip': '192.0.2.$page',
      'path': _path(page),
      'member_id': page == 1 ? 0 : 7,
      'visit_time': '2026-11-07T01:02:03Z',
      'account': page == 1 ? '' : _account(),
    },
  ],
  'total': 41,
  'page': page,
  'page_size': 20,
  'total_pages': 3,
};

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String phase = 'condition',
}) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Dashboard did not reach $phase');
}

Future<void> _pumpLoaded(
  WidgetTester tester,
  AdminDashboardController controller,
) => _pumpUntil(
  tester,
  () =>
      controller.logs.state == DashboardLoadState.loaded &&
      controller.trend.state == DashboardLoadState.loaded &&
      controller.stats.state != DashboardLoadState.loading &&
      controller.stats.state != DashboardLoadState.idle,
  phase: 'section completion',
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    260,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'initial view loads real sections and exposes daily trend values',
    (tester) async {
      final httpClient = _DashboardHttp((request) async {
        if (request.url.path.endsWith('/stats')) return _json(_stats(12));
        if (request.url.path.endsWith('/trend')) return _json(_trend(12));
        return _json(_logs(1));
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      )..restoreSession({'token': 'fake'});
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardPage(controller: controller, onReturn: () {}),
        ),
      );
      expect(
        find.byKey(const ValueKey('dashboard-stats-retry-total')),
        findsNothing,
      );
      await _pumpLoaded(tester, controller);

      expect(find.text('12'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dashboard-range-semantics')),
        findsOneWidget,
      );
      expect(find.byTooltip('范围包含服务器起始日全天；UV按日累计，不是整个区间去重。'), findsOneWidget);
      expect(
        find.text('12 PV · 6 UV'),
        findsNothing,
      ); // Selected detail includes its date prefix.
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-daily-detail-toggle')),
      );
      await tester.tap(
        find.byKey(const ValueKey('dashboard-daily-detail-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trend-selected-values')),
        findsOneWidget,
      );
      expect(find.textContaining('2026-11-02 · 13 PV · 7 UV'), findsOneWidget);
      await _scrollTo(tester, find.text('游客'));
      expect(find.text('游客'), findsOneWidget);
      expect(find.text(_path(1)), findsOneWidget);
      expect(
        httpClient.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets(
    'range change only reloads stats and trend, not logs pagination',
    (tester) async {
      final requests = <http.Request>[];
      final httpClient = _DashboardHttp((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/stats')) return _json(_stats(20));
        if (request.url.path.endsWith('/trend')) return _json(_trend(20));
        return _json(_logs(1));
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      );
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardPage(controller: controller, onReturn: () {}),
        ),
      );
      await _pumpLoaded(tester, controller);
      final logsBefore = requests
          .where((request) => request.url.path.endsWith('/logs'))
          .length;

      await tester.tap(find.byKey(const ValueKey('range-30d')));
      await _pumpUntil(
        tester,
        () =>
            controller.stats.state == DashboardLoadState.loaded &&
            controller.trend.state == DashboardLoadState.loaded,
        phase: 'new range results',
      );

      expect(requests.where((r) => r.url.path.endsWith('/stats')).length, 2);
      expect(requests.where((r) => r.url.path.endsWith('/trend')).length, 2);
      expect(
        requests.where((r) => r.url.path.endsWith('/logs')).length,
        logsBefore,
      );
      expect(
        requests.where((r) => r.url.queryParameters['range'] == '30d').length,
        2,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('stats retry is independent from good trend and logs', (
    tester,
  ) async {
    var failStats = true;
    final httpClient = _DashboardHttp((request) async {
      if (request.url.path.endsWith('/stats')) {
        return failStats
            ? _json({'code': 500, 'message': 'failed'}, status: 500)
            : _json(_stats(9));
      }
      if (request.url.path.endsWith('/trend')) return _json(_trend(9));
      return _json(_logs(1));
    });
    final client = BookstarkClient(
      'https://dashboard.test',
      transport: httpClient,
    );
    final controller = AdminDashboardController(
      AdminDashboardRepository(client),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardPage(controller: controller, onReturn: () {}),
      ),
    );
    await _pumpLoaded(tester, controller);
    expect(find.byKey(const ValueKey('dashboard-trend-retry')), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard-stats-retry-total')),
      findsOneWidget,
    );
    failStats = false;
    await tester.tap(find.byKey(const ValueKey('dashboard-stats-retry-total')));
    await _pumpUntil(
      tester,
      () => controller.stats.state == DashboardLoadState.loaded,
      phase: 'stats retry',
    );
    expect(find.text('9'), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-trend-retry')), findsNothing);
    expect(
      httpClient.requests.where((r) => r.url.path.endsWith('/trend')).length,
      1,
    );
    expect(
      httpClient.requests.where((r) => r.url.path.endsWith('/logs')).length,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
    'logs pagination is independent and next is disabled at final page',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final httpClient = _DashboardHttp((request) async {
        if (request.url.path.endsWith('/stats')) return _json(_stats(8));
        if (request.url.path.endsWith('/trend')) return _json(_trend(8));
        final page = int.parse(request.url.queryParameters['page']!);
        return _json(_logs(page));
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      );
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardPage(controller: controller, onReturn: () {}),
        ),
      );
      await _pumpLoaded(tester, controller);
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      await tester.tap(find.byKey(const ValueKey('dashboard-next')));
      await _pumpUntil(
        tester,
        () =>
            controller.logs.state == DashboardLoadState.loaded &&
            controller.logs.value?.page == 2,
        phase: 'logs page 2',
      );
      expect(find.text('192.0.2.2'), findsOneWidget);
      expect(find.text(_account()), findsOneWidget);
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      await tester.tap(find.byKey(const ValueKey('dashboard-next')));
      await _pumpUntil(
        tester,
        () =>
            controller.logs.state == DashboardLoadState.loaded &&
            controller.logs.value?.page == 3,
        phase: 'final logs page',
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('dashboard-next')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('dashboard-previous')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        httpClient.requests.where((r) => r.url.path.endsWith('/logs')).length,
        3,
      );
      expect(
        httpClient.requests.where((r) => r.url.path.endsWith('/stats')).length,
        1,
      );
      expect(
        httpClient.requests.where((r) => r.url.path.endsWith('/trend')).length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets(
    '401/403 clears every rendered sensitive value and offers return',
    (tester) async {
      var denied = false;
      final httpClient = _DashboardHttp((request) async {
        if (denied) {
          return _json({'code': 403, 'message': 'forbidden'}, status: 403);
        }
        if (request.url.path.endsWith('/stats')) return _json(_stats(8));
        if (request.url.path.endsWith('/trend')) return _json(_trend(8));
        return _json(_logs(1));
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      );
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardPage(
            controller: controller,
            english: true,
            onReturn: () => returned = true,
          ),
        ),
      );
      await _pumpLoaded(tester, controller);
      await _scrollTo(tester, find.text(_path(1)));
      expect(find.text(_path(1)), findsOneWidget);

      denied = true;
      await tester.tap(find.byKey(const ValueKey('dashboard-refresh')));
      await _pumpUntil(
        tester,
        () => controller.sessionRevoked,
        phase: 'permission revocation',
      );
      expect(
        find.text('Your session expired or administrator access was revoked.'),
        findsOneWidget,
      );
      expect(find.text(_path(1)), findsNothing);
      expect(find.text('192.0.2.1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dashboard-return')));
      expect(returned, isTrue);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('obsolete range completion cannot replace newer stats or trend', (
    tester,
  ) async {
    final oldStatsStarted = Completer<void>();
    final releaseOldStats = Completer<void>();
    var holdFirstStats = true;
    final httpClient = _DashboardHttp((request) async {
      if (request.url.path.endsWith('/stats')) {
        if (request.url.queryParameters['range'] == '7d' && holdFirstStats) {
          holdFirstStats = false;
          oldStatsStarted.complete();
          await releaseOldStats.future;
          return _json(_stats(7));
        }
        return _json(
          _stats(request.url.queryParameters['range'] == '30d' ? 30 : 70),
        );
      }
      if (request.url.path.endsWith('/trend')) {
        return _json(
          _trend(request.url.queryParameters['range'] == '30d' ? 30 : 70),
        );
      }
      return _json(_logs(1));
    });
    final client = BookstarkClient(
      'https://dashboard.test',
      transport: httpClient,
    );
    final controller = AdminDashboardController(
      AdminDashboardRepository(client),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardPage(controller: controller, onReturn: () {}),
      ),
    );
    await oldStatsStarted.future;
    await _pumpUntil(
      tester,
      () =>
          controller.trend.state == DashboardLoadState.loaded &&
          controller.logs.state == DashboardLoadState.loaded,
      phase: 'parallel initial sections',
    );
    await tester.tap(find.byKey(const ValueKey('range-30d')));
    await _pumpUntil(
      tester,
      () =>
          controller.stats.state == DashboardLoadState.loaded &&
          controller.trend.state == DashboardLoadState.loaded,
      phase: 'replacement range',
    );
    releaseOldStats.complete();
    await tester.pump();
    expect(find.text('30'), findsOneWidget);
    expect(find.text('7'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
    '320dp and 200 percent text keeps all sections inside a scrollable surface',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final httpClient = _DashboardHttp((request) async {
        if (request.url.path.endsWith('/stats')) return _json(_stats(1000));
        if (request.url.path.endsWith('/trend')) return _json(_trend(1000));
        return _json(_longLogs());
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      );
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AdminDashboardPage(
            controller: controller,
            english: true,
            onReturn: () {},
          ),
        ),
      );
      await _pumpLoaded(tester, controller);
      final subtitle = tester.renderObject<RenderParagraph>(
        find.text('Administrator · Server space'),
      );
      expect(subtitle.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
      await _scrollTo(tester, find.text(_account()));
      await _scrollTo(tester, find.text(_path(2)));
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      expect(find.byKey(const ValueKey('dashboard-next')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  testWidgets('loading does not invent zero metric placeholders', (
    tester,
  ) async {
    final gate = Completer<void>();
    final httpClient = _DashboardHttp((request) async {
      await gate.future;
      if (request.url.path.endsWith('/stats')) return _json(_stats(0));
      if (request.url.path.endsWith('/trend')) {
        return _json({'code': 0, 'data': null});
      }
      return _json({
        'code': 0,
        'data': <Object?>[],
        'total': 0,
        'page': 1,
        'page_size': 20,
        'total_pages': 1,
      });
    });
    final client = BookstarkClient(
      'https://dashboard.test',
      transport: httpClient,
    );
    final controller = AdminDashboardController(
      AdminDashboardRepository(client),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardPage(controller: controller, onReturn: () {}),
      ),
    );
    expect(find.byKey(const ValueKey('dashboard-stats')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dashboard-stats')),
        matching: find.text('0'),
      ),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    gate.complete();
    await _pumpLoaded(tester, controller);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('401 revokes page generation and clears sensitive values', (
    tester,
  ) async {
    final httpClient = _DashboardHttp((request) async {
      if (request.url.path.endsWith('/stats')) {
        return _json({'code': 401, 'message': 'expired'}, status: 401);
      }
      if (request.url.path.endsWith('/trend')) return _json(_trend(8));
      return _json(_logs(1));
    });
    final client = BookstarkClient(
      'https://dashboard.test',
      transport: httpClient,
    );
    final controller = AdminDashboardController(
      AdminDashboardRepository(client),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardPage(
          controller: controller,
          english: true,
          onReturn: () {},
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => controller.sessionRevoked,
      phase: '401 handling',
    );
    expect(controller.stats.value, isNull);
    expect(controller.trend.value, isNull);
    expect(controller.logs.value, isNull);
    expect(find.text(_path(1)), findsNothing);
    expect(
      find.text('Your session expired or administrator access was revoked.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
  testWidgets(
    'failed log page retries the same page without reloading other sections',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pageTwoFails = true;
      final requestedPages = <int>[];
      final httpClient = _DashboardHttp((request) async {
        if (request.url.path.endsWith('/stats')) return _json(_stats(8));
        if (request.url.path.endsWith('/trend')) return _json(_trend(8));
        final page = int.parse(request.url.queryParameters['page']!);
        requestedPages.add(page);
        if (page == 2 && pageTwoFails) {
          return _json({'code': 500, 'message': 'failed'}, status: 500);
        }
        return _json(_logs(page));
      });
      final client = BookstarkClient(
        'https://dashboard.test',
        transport: httpClient,
      );
      final controller = AdminDashboardController(
        AdminDashboardRepository(client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardPage(controller: controller, onReturn: () {}),
        ),
      );
      await _pumpLoaded(tester, controller);
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
      await tester.tap(find.byKey(const ValueKey('dashboard-next')));
      await _pumpUntil(
        tester,
        () => controller.logs.state == DashboardLoadState.failed,
        phase: 'logs page failure',
      );
      expect(requestedPages, [1, 2]);

      pageTwoFails = false;
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('dashboard-logs-retry')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-logs-retry')),
      );
      await tester.tap(find.byKey(const ValueKey('dashboard-logs-retry')));
      await _pumpUntil(
        tester,
        () =>
            controller.logs.state == DashboardLoadState.loaded &&
            controller.logs.value?.page == 2,
        phase: 'logs page retry',
      );
      expect(requestedPages, [1, 2, 2]);
      expect(
        httpClient.requests.where((r) => r.url.path.endsWith('/stats')).length,
        1,
      );
      expect(
        httpClient.requests.where((r) => r.url.path.endsWith('/trend')).length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('out-of-range log response offers return to first page', (
    tester,
  ) async {
    final requestedPages = <int>[];
    final httpClient = _DashboardHttp((request) async {
      if (request.url.path.endsWith('/stats')) return _json(_stats(8));
      if (request.url.path.endsWith('/trend')) return _json(_trend(8));
      final page = int.parse(request.url.queryParameters['page']!);
      requestedPages.add(page);
      if (page == 1) return _json(_logs(1));
      return _json({
        'code': 0,
        'data': <Object?>[],
        'total': 0,
        'page': 2,
        'page_size': 20,
        'total_pages': 1,
      });
    });
    final client = BookstarkClient(
      'https://dashboard.test',
      transport: httpClient,
    );
    final controller = AdminDashboardController(
      AdminDashboardRepository(client),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardPage(controller: controller, onReturn: () {}),
      ),
    );
    await _pumpLoaded(tester, controller);
    await _scrollTo(tester, find.byKey(const ValueKey('dashboard-next')));
    await tester.ensureVisible(find.byKey(const ValueKey('dashboard-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dashboard-next')));
    await _pumpUntil(
      tester,
      () =>
          controller.logs.state == DashboardLoadState.loaded &&
          controller.logs.value?.page == 2,
      phase: 'out-of-range response',
    );
    expect(
      find.byKey(const ValueKey('dashboard-logs-page-out-of-range')),
      findsOneWidget,
    );
    expect(find.text('第 2 / 1 页'), findsNothing);
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('dashboard-logs-first-page')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('dashboard-logs-first-page')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dashboard-logs-first-page')));
    await _pumpUntil(
      tester,
      () =>
          controller.logs.state == DashboardLoadState.loaded &&
          controller.logs.value?.page == 1,
      phase: 'return to first page',
    );
    expect(requestedPages, [1, 2, 1]);
    expect(
      find.byKey(const ValueKey('dashboard-logs-page-out-of-range')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
}
