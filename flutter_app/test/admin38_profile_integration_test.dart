import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/features/admin/admin_friend_links_page.dart';
import 'package:bookstark_flutter/features/admin/admin_share_comments_page.dart';
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
  for (final route in [
    (
      label: '友情链接',
      path: '/api/admin/friend-links',
      page: AdminFriendLinksPage,
      envelope: <String, Object?>{
        'code': 0,
        'data': {'items': [], 'simple_mode': false},
      },
    ),
    (
      label: '评论管理',
      path: '/api/admin/share-comments',
      page: AdminShareCommentsPage,
      envelope: <String, Object?>{
        'code': 0,
        'data': [],
        'total': 0,
        'page': 1,
        'page_size': 20,
        'total_pages': 1,
      },
    ),
  ]) {
    final label = route.label;
    http.Response response() => http.Response(
      jsonEncode(route.envelope),
      200,
      headers: {'content-type': 'application/json'},
    );
    testWidgets('root opens $label only after a fresh administrator read', (
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
        if (request.url.path == route.path) return response();
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text(label));
      expect(find.byType(route.page), findsOneWidget);
      expect(profiles, greaterThanOrEqualTo(3));
      expect(
        server.paths.where((path) => path == 'GET ${route.path}'),
        hasLength(1),
      );
      expect(server.paths.every((path) => path.startsWith('GET ')), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'root hides $label for members and blocks a freshly demoted account',
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
        expect(find.text('友情链接'), findsNothing);
        expect(find.text('评论管理'), findsNothing);
        role = 0;
        await tester.tap(find.byIcon(Icons.refresh).last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        role = 1;
        await click(tester, find.text(label));
        expect(find.byType(route.page), findsNothing);
        expect(find.byType(ProfilePage), findsOneWidget);
        expect(
          server.paths.where(
            (path) =>
                path.contains('/api/admin/friend-links') ||
                path.contains('/api/admin/share-comments'),
          ),
          isEmpty,
        );
        expect(find.text('友情链接'), findsNothing);
        expect(find.text('评论管理'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets('root logout cannot be undone by a late $label read', (
      tester,
    ) async {
      seed();
      final server = Server();
      final pending = Completer<http.Response>();
      server.extra = (request) async {
        if (request.url.path == '/api/profile') return server.data(profile(0));
        if (request.url.path == route.path) return pending.future;
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      final entry = find.text(label);
      await tester.scrollUntilVisible(
        entry,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(route.page), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(route.page),
          matching: find.byTooltip('返回'),
        ),
      );
      await tester.pumpAndSettle();
      await click(tester, find.text('退出服务器空间'));
      await click(tester, find.text('确认退出'));
      expect(find.byType(ConnectionPage), findsOneWidget);
      pending.complete(response());
      await tester.pumpAndSettle();
      expect(find.byType(route.page), findsNothing);
      expect(find.byType(ConnectionPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
