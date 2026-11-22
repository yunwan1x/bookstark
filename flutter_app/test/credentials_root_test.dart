import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/main.dart';
import 'package:bookstark_flutter/features/credentials/api_tokens_page.dart';
import 'package:bookstark_flutter/features/credentials/webdav_password_page.dart';
import 'profile_root_test.dart' as root;
import 'api_tokens_repository_test.dart' as tokens;
import 'profile_repository_test.dart' as response;
import 'webdav_password_repository_test.dart' as dav;

Future<void> click(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, root.Server server) async {
  root.seed();
  await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await click(tester, find.text('API与应用密码'));
}

void main() {
  testWidgets(
    'real root credential chooser reaches owned token repository and never replaces primary session with created token',
    (tester) async {
      final server = root.Server();
      String? name;
      var creates = 0, revokes = 0;
      server.extra = (r) async {
        if (r.url.path == '/api/api-tokens') {
          if (r.method == 'POST') {
            creates++;
            name = (jsonDecode(r.body) as Map)['name'] as String;
            return response.data({
              'data': tokens.entry(name: name!),
              'token': tokens.secret,
            });
          }
          return tokens.list(name == null ? [] : [tokens.entry(name: name!)]);
        }
        if (r.url.path == '/api/api-tokens/1' && r.method == 'DELETE') {
          revokes++;
          name = null;
          return http.Response(
            '{"code":0,"message":"revoked"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      };
      await open(tester, server);
      await click(tester, find.text('API令牌'));
      expect(find.byType(ApiTokensPage), findsOneWidget);
      expect(creates, 0);
      await click(tester, find.text('创建令牌'));
      await tester.enterText(find.byType(TextFormField), 'root tool');
      await click(tester, find.text('创建'));
      expect(find.text('令牌已创建'), findsOneWidget);
      expect(creates, 1);
      await click(tester, find.text('关闭并清除本次显示'));
      expect(find.text(tokens.secret), findsNothing);
      await click(tester, find.text('撤销'));
      await click(tester, find.text('撤销令牌'));
      expect(revokes, 1);
      final stored = (await const FlutterSecureStorage().read(
        key: 'bookstark.flutter.session',
      ))!;
      expect(stored, contains('fixture-session'));
      expect(stored, isNot(contains(tokens.secret)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'real root reaches DAV reset/probe/revoke with exact new Basic credentials and unchanged primary session',
    (tester) async {
      final server = root.Server();
      var has = false, resets = 0, revokes = 0, probes = 0;
      String? basic;
      server.extra = (r) async {
        if (r.url.path == '/api/webdav/profile') {
          return response.data({
            'built_in': true,
            'account': 'root-profile-fixture',
            'endpoint': 'https://example.test/dav',
            'has_app_password': has,
          });
        }
        if (r.url.path == '/api/webdav/app-password/reset' &&
            r.method == 'POST') {
          resets++;
          has = true;
          return response.data({'app_password': dav.generated});
        }
        if (r.url.path == '/api/webdav/app-password' && r.method == 'DELETE') {
          revokes++;
          has = false;
          return http.Response(
            '{"code":0,"message":"revoked"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path == '/dav' && r.method == 'PROPFIND') {
          probes++;
          basic = r.headers['authorization'];
          return http.Response(
            dav.xml(href: '/dav/'),
            207,
            headers: {'content-type': 'text/xml'},
          );
        }
        return null;
      };
      await open(tester, server);
      await click(tester, find.text('WebDAV应用密码'));
      expect(find.byType(WebdavPasswordPage), findsOneWidget);
      expect(resets, 0);
      await click(tester, find.text('生成新的应用密码'));
      await click(tester, find.text('确认生成新密码'));
      expect(find.text('应用密码已核对'), findsOneWidget);
      expect([resets, probes], [1, 1]);
      expect(
        utf8.decode(base64Decode(basic!.substring(6))),
        'root-profile-fixture:${dav.generated}',
      );
      await click(tester, find.text('关闭并清除本次显示'));
      await click(tester, find.text('撤销应用密码'));
      await click(tester, find.text('确认撤销'));
      expect(revokes, 1);
      expect(find.text('尚未设置应用密码'), findsOneWidget);
      final stored = (await const FlutterSecureStorage().read(
        key: 'bookstark.flutter.session',
      ))!;
      expect(stored, contains('fixture-session'));
      expect(stored, isNot(contains(dav.generated)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
