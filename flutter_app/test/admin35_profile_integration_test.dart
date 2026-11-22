import 'dart:async';

import 'package:bookstark_flutter/features/admin/admin_dashboard_page.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'profile_root_test.dart' show Server, seed, click;

http.Response response(int status, String body) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});
Map<String, Object?> profile(int role) => {
  'member_id': 7,
  'account': 'root-profile-fixture',
  'email': 'old@example.test',
  'role': role,
  'default_home': 'home',
};
void main() {
  testWidgets('root Profile exposes admin dashboard and calls read-only APIs', (
    tester,
  ) async {
    seed();
    final server = Server();
    var reads = 0;
    server.extra = (r) async {
      if (r.url.path == '/api/profile') {
        reads++;
        return server.data(profile(0));
      }
      if (r.url.path.endsWith('/stats')) {
        return server.data({'total_visits': 4, 'unique_ips': 3});
      }
      if (r.url.path.endsWith('/trend')) {
        return response(200, '{"code":0,"data":[]}');
      }
      if (r.url.path.endsWith('/logs')) {
        return response(
          200,
          '{"code":0,"data":[],"total":0,"page":1,"page_size":20,"total_pages":1}',
        );
      }
      return null;
    };
    await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    await click(tester, find.text('访问统计'));
    expect(reads, greaterThanOrEqualTo(2));
    expect(find.byType(AdminDashboardPage), findsOneWidget);
    expect(
      server.paths
          .where((p) => p.startsWith('GET /api/admin/dashboard/'))
          .length,
      3,
    );
    expect(server.paths.every((p) => p.startsWith('GET ')), isTrue);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('nonadmin hides dashboard and makes no admin requests', (
    tester,
  ) async {
    seed();
    final server = Server();
    await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('访问统计'), findsNothing);
    expect(
      server.paths.where((p) => p.contains('/api/admin/dashboard/')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('fresh role demotion blocks route and endpoint requests', (
    tester,
  ) async {
    seed();
    final server = Server();
    var demoted = false;
    server.extra = (r) async {
      if (r.url.path == '/api/profile') {
        return server.data(profile(demoted ? 1 : 0));
      }
      return null;
    };
    await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('访问统计'), findsOneWidget);
    demoted = true;
    await click(tester, find.text('访问统计'));
    expect(find.byType(AdminDashboardPage), findsNothing);
    expect(
      server.paths.where((p) => p.contains('/api/admin/dashboard/')),
      isEmpty,
    );
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final status in [401, 403]) {
    testWidgets('server permission response $status clears dashboard data', (
      tester,
    ) async {
      seed();
      final server = Server();
      server.extra = (r) async {
        if (r.url.path == '/api/profile') return server.data(profile(0));
        if (r.url.path.startsWith('/api/admin/dashboard/')) {
          return response(status, '{"code":$status,"message":"denied"}');
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('访问统计'));
      expect(find.byKey(const ValueKey('dashboard-return')), findsOneWidget);
      expect(find.text('会话已失效或管理员权限已撤销。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dashboard-return')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'late dashboard responses after account teardown cannot restore dashboard route',
    (tester) async {
      seed();
      final server = Server();
      final pending = <Completer<http.Response>>[];
      server.extra = (r) async {
        if (r.url.path == '/api/profile') return server.data(profile(0));
        if (r.url.path.startsWith('/api/admin/dashboard/')) {
          final c = Completer<http.Response>();
          pending.add(c);
          return c.future;
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      final dashboardEntry = find.text('访问统计');
      await tester.ensureVisible(dashboardEntry);
      await tester.tap(dashboardEntry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminDashboardPage), findsOneWidget);
      expect(pending, hasLength(3));
      await tester.tap(
        find.descendant(
          of: find.byType(AdminDashboardPage),
          matching: find.byIcon(Icons.arrow_back),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await click(tester, find.text('退出服务器空间'));
      await click(tester, find.text('确认退出'));
      expect(find.byType(ConnectionPage), findsOneWidget);
      for (final c in pending) {
        if (!c.isCompleted) {
          c.complete(server.data({'total_visits': 99, 'unique_ips': 99}));
        }
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AdminDashboardPage), findsNothing);
      expect(find.byType(ConnectionPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
