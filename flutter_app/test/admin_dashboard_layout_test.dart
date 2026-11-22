import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_page.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_repository.dart';

DashboardTrendPoint point(int pv, int uv) => DashboardTrendPoint(
  bucketLabel: '2026-11-06',
  pageViews: pv,
  uniqueIps: uv,
);

void main() {
  test(
    'PV and UV share a numeric axis rather than each filling its own height',
    () {
      final painter = DashboardTrendPainter([point(100, 10), point(20, 10)]);
      const plot = Rect.fromLTWH(10, 20, 200, 100);
      expect(painter.maximum, 100);
      expect(painter.pointOffset(plot, 0, 100).dy, 20);
      expect(painter.pointOffset(plot, 0, 10).dy, 110);
      expect(painter.pointOffset(plot, 1, 20).dy, 100);
      expect(
        painter.pointOffset(plot, 0, 10).dy,
        painter.pointOffset(plot, 1, 10).dy,
      );
    },
  );

  test(
    'UV-dominant and zero single-day plots remain bounded on the common axis',
    () {
      final painter = DashboardTrendPainter([point(2, 20)]);
      const plot = Rect.fromLTWH(0, 0, 200, 100);
      expect(painter.maximum, 20);
      expect(painter.pointOffset(plot, 0, 2), const Offset(100, 90));
      expect(painter.pointOffset(plot, 0, 20), const Offset(100, 0));
      final zero = DashboardTrendPainter([point(0, 0)]);
      expect(zero.pointOffset(plot, 0, 0), const Offset(100, 100));
    },
  );

  for (final config in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'prototype metrics remain aligned and readable at width ${config.$1} scale ${config.$2}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(config.$1, 1600);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = BookstarkClient(
          'https://fixture.invalid',
          transport: MockClient((request) async {
            final Object body;
            if (request.url.path.endsWith('/stats')) {
              body = {
                'code': 0,
                'data': {'total_visits': 12480, 'unique_ips': 2160},
              };
            } else if (request.url.path.endsWith('/trend')) {
              body = {
                'code': 0,
                'data': [
                  {'time': '2026-11-05', 'page_views': 100, 'unique_ips': 10},
                  {'time': '2026-11-06', 'page_views': 20, 'unique_ips': 10},
                ],
              };
            } else {
              body = {
                'code': 0,
                'data': [],
                'total': 0,
                'page': 1,
                'page_size': 20,
                'total_pages': 1,
              };
            }
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final controller = AdminDashboardController(
          AdminDashboardRepository(client),
        );
        addTearDown(controller.dispose);
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(config.$2)),
              child: child!,
            ),
            home: AdminDashboardPage(controller: controller, onReturn: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        try {
          expect(find.bySemanticsLabel('12,480'), findsOneWidget);
          expect(controller.stats.state, DashboardLoadState.loaded);
          expect(find.text('12,480'), findsOneWidget);
          expect(find.text('2,160'), findsOneWidget);
          final a = tester.getRect(
            find.byKey(const ValueKey('dashboard-stats')),
          );
          final b = tester.getRect(
            find.byKey(const ValueKey('dashboard-unique-ips')),
          );
          if (config.$2 == 1) {
            expect(a.top, closeTo(b.top, .1));
            expect(a.bottom, closeTo(b.bottom, .1));
            expect(a.right, lessThan(b.left));
            expect(a.width, greaterThan(160));
          } else {
            expect(a.left, closeTo(b.left, .1));
            expect(a.width, closeTo(config.$1 - 32, .1));
            expect(b.top, greaterThan(a.bottom));
          }
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            Colors.white,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
