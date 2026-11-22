import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_assets_catalog_page.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'profile_root_test.dart' show Server, seed, click;
import 'admin38_profile_integration_test.dart' show profile;

http.Response emptyAssets() => http.Response(
  '{"code":0,"data":[]}',
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  testWidgets(
    'root asset entry performs fresh bounded admin checks and loads hosts only',
    (tester) async {
      seed();
      final server = Server();
      var profiles = 0;
      final redirects = <bool>[];
      server.extra = (request) async {
        if (request.url.path == '/api/profile') {
          profiles++;
          redirects.add(request.followRedirects);
          return server.data(profile(0));
        }
        if (request.url.path == '/api/admin/assets/ssh-hosts') {
          return emptyAssets();
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('资产管理'));
      expect(find.byType(AdminAssetsCatalogPage), findsOneWidget);
      expect(profiles, greaterThanOrEqualTo(3));
      expect(redirects.reversed.take(2), everyElement(isFalse));
      expect(
        server.paths.where((path) => path == 'GET /api/admin/assets/ssh-hosts'),
        hasLength(1),
      );
      expect(
        server.paths.where((path) => path.contains('/api/admin/settings')),
        isEmpty,
      );
      expect(server.paths, everyElement(startsWith('GET ')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'root hides assets for members and denies freshly demoted cached admin',
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
      expect(find.text('资产管理'), findsNothing);
      role = 0;
      await tester.tap(find.byIcon(Icons.refresh).last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('资产管理'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      role = 1;
      await click(tester, find.text('资产管理'));
      expect(find.byType(AdminAssetsCatalogPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(
        server.paths.where((path) => path.contains('/api/admin/assets/')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'late owned host read cannot restore asset routes after real logout',
    (tester) async {
      seed();
      final server = Server();
      final pending = Completer<http.Response>();
      server.extra = (request) async {
        if (request.url.path == '/api/profile') return server.data(profile(0));
        if (request.url.path == '/api/admin/assets/ssh-hosts') {
          return pending.future;
        }
        return null;
      };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('资产管理'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('资产管理'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminAssetsCatalogPage), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AdminAssetsCatalogPage),
          matching: find.byTooltip('返回'),
        ),
      );
      await tester.pumpAndSettle();
      await click(tester, find.text('退出服务器空间'));
      await click(tester, find.text('确认退出'));
      expect(find.byType(ConnectionPage), findsOneWidget);
      pending.complete(emptyAssets());
      await tester.pumpAndSettle();
      expect(find.byType(AdminAssetsCatalogPage), findsNothing);
      expect(find.byType(ConnectionPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
