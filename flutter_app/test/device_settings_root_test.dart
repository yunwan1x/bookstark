import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:bookstark_flutter/features/settings/device_settings_page.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'profile_root_test.dart' as root;

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    160,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          paths,
          (_) async =>
              '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files/device-settings45-root',
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
  });

  testWidgets(
    'home settings uses actual current client for explicit profile check',
    (tester) async {
      root.seed();
      final server = root.Server();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      final before = server.paths.where((p) => p == 'GET /api/profile').length;
      await _tap(tester, '设置');
      expect(find.byType(DeviceSettingsPage), findsOneWidget);
      expect(server.paths.where((p) => p == 'GET /api/profile').length, before);
      await _tap(tester, '连接管理');
      expect(find.text('未验证'), findsOneWidget);
      await _tap(tester, '检查连接');
      expect(find.text('已验证'), findsOneWidget);
      expect(
        server.paths.where((p) => p == 'GET /api/profile').length,
        before + 1,
      );
      expect(server.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings persists actual app language across root restart and retains session',
    (tester) async {
      root.seed();
      final server = root.Server();
      const storage = FlutterSecureStorage();
      final original = await storage.read(key: 'bookstark.flutter.session');
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await _tap(tester, '设置');
      await _tap(tester, '语言');
      expect(find.text('Settings'), findsOneWidget);
      expect(await storage.read(key: 'bookstark.flutter.language'), 'en');
      expect(await storage.read(key: 'bookstark.flutter.session'), original);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(find.text('Settings'), findsOneWidget);
      expect(await storage.read(key: 'bookstark.flutter.session'), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings logout requires confirmation then clears the real saved session',
    (tester) async {
      root.seed();
      final server = root.Server();
      const storage = FlutterSecureStorage();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await _tap(tester, '设置');
      await _tap(tester, '连接管理');
      await _tap(tester, '退出当前账号');
      await _tap(tester, '取消');
      expect(await storage.read(key: 'bookstark.flutter.session'), isNotNull);
      await _tap(tester, '退出当前账号');
      await _tap(tester, '退出登录');
      expect(find.byType(ConnectionPage), findsOneWidget);
      expect(await storage.read(key: 'bookstark.flutter.session'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
