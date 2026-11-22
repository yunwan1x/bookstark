import 'dart:async';

import 'package:bookstark_flutter/features/admin/admin_members_page.dart';
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
  testWidgets('root Profile opens members only after fresh administrator read', (
    tester,
  ) async {
    seed();
    final server = Server();
    var profiles = 0;
    server.extra = (request) async {
      if (request.url.path == '/api/profile') {
        profiles++;
        return server.data(profile(0));
      }
      if (request.url.path == '/api/admin/members') {
        return http.Response(
          '{"code":0,"data":[],"total":0,"page":1,"page_size":20,"total_pages":1}',
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
    await click(tester, find.text('用户管理'));
    expect(find.byType(AdminMembersPage), findsOneWidget);
    expect(profiles, greaterThanOrEqualTo(3));
    expect(
      server.paths.where((path) => path == 'GET /api/admin/members'),
      hasLength(1),
    );
    expect(server.paths.every((path) => path.startsWith('GET ')), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'root non-admin hides system members and fresh demotion blocks opening',
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
      expect(find.text('用户管理'), findsNothing);
      role = 0;
      await tester.tap(find.byIcon(Icons.refresh).last);
      await tester.pumpAndSettle();
      expect(find.text('用户管理'), findsOneWidget);
      role = 1;
      await click(tester, find.text('用户管理'));
      expect(find.byType(AdminMembersPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(
        server.paths.where((path) => path.contains('/api/admin/members')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('root logout cannot be undone by a late members read', (
    tester,
  ) async {
    seed();
    final server = Server();
    final pending = Completer<http.Response>();
    server.extra = (request) async {
      if (request.url.path == '/api/profile') return server.data(profile(0));
      if (request.url.path == '/api/admin/members') return pending.future;
      return null;
    };
    await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    final entry = find.text('用户管理');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AdminMembersPage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AdminMembersPage),
        matching: find.byTooltip('返回'),
      ),
    );
    await tester.pumpAndSettle();
    await click(tester, find.text('退出服务器空间'));
    await click(tester, find.text('确认退出'));
    expect(find.byType(ConnectionPage), findsOneWidget);
    pending.complete(
      http.Response(
        '{"code":0,"data":[],"total":0,"page":1,"page_size":20,"total_pages":1}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminMembersPage), findsNothing);
    expect(find.byType(ConnectionPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
