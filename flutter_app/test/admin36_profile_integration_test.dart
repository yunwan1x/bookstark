import 'dart:async';

import 'package:bookstark_flutter/features/admin/admin_settings_hub_page.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'profile_root_test.dart' show Server, seed, click;

Map<String, Object?> profile(int role) => {
  'member_id': 7,
  'account': 'root-profile-fixture',
  'email': 'old@example.test',
  'role': role,
  'default_home': 'home',
};
void main() {
  testWidgets(
    'root Profile opens settings only after fresh administrator read',
    (tester) async {
      seed();
      final server = Server();
      var profiles = 0;
      server.extra = (request) async {
        if (request.url.path == '/api/profile') {
          profiles++;
          return server.data(profile(0));
        }
        if (request.url.path == '/api/admin/settings') {
          return http.Response(
            '{"code":0,"data":[]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('系统设置'));
      expect(find.byType(AdminSettingsHubPage), findsOneWidget);
      expect(profiles, greaterThanOrEqualTo(3));
      expect(
        server.paths.where((path) => path == 'GET /api/admin/settings'),
        hasLength(1),
      );
      expect(server.paths.every((path) => path.startsWith('GET ')), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'root non-admin hides system settings and fresh demotion blocks opening',
    (tester) async {
      seed();
      final server = Server();
      var role = 1;
      server.extra = (request) async {
        if (request.url.path == '/api/profile') {
          return server.data(profile(role));
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      expect(find.text('系统设置'), findsNothing);
      role = 0;
      await tester.tap(find.byIcon(Icons.refresh).last);
      await tester.pumpAndSettle();
      expect(find.text('系统设置'), findsOneWidget);
      role = 1;
      await click(tester, find.text('系统设置'));
      expect(find.byType(AdminSettingsHubPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(
        server.paths.where((path) => path.contains('/api/admin/settings')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('root logout cannot be undone by a late settings read', (
    tester,
  ) async {
    seed();
    final server = Server();
    final pending = Completer<http.Response>();
    server.extra = (request) async {
      if (request.url.path == '/api/profile') return server.data(profile(0));
      if (request.url.path == '/api/admin/settings') return pending.future;
      return null;
    };
    await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    final entry = find.text('系统设置');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AdminSettingsHubPage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AdminSettingsHubPage),
        matching: find.byTooltip('返回'),
      ),
    );
    await tester.pumpAndSettle();
    await click(tester, find.text('退出服务器空间'));
    await click(tester, find.text('确认退出'));
    expect(find.byType(ConnectionPage), findsOneWidget);
    pending.complete(
      http.Response(
        '{"code":0,"data":[]}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminSettingsHubPage), findsNothing);
    expect(find.byType(ConnectionPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
