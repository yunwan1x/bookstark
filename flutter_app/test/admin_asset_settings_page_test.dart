import 'package:bookstark_flutter/features/admin/admin_asset_settings_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_settings.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_asset_settings_test.dart' as settings;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late settings.SettingsHarness h;
  late AdminAssetsController c;
  var saved = 0;
  setUp(() {
    h = settings.SettingsHarness();
    c = AdminAssetsController(h.repo, base.owner);
    saved = 0;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
  });
  tearDown(() {
    c.dispose();
    h.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() => c.load(AdminAssetCatalog.settings));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetSettingsPage(
          controller: c,
          initial: c.settings!,
          onReturn: () {},
          onSaved: () {
            saved++;
          },
          onRevealKey: () {},
          onMigrate: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> enterKey(WidgetTester tester) async {
    for (final id in ['asset-settings-key', 'asset-settings-key-confirm']) {
      final field = find.byKey(ValueKey(id));
      await tester.scrollUntilVisible(
        field,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, ' owned replacement key ');
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'default keep changes only terminal policy without reading key into fields',
    (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('asset-settings-key')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('asset-settings-idle')),
        '2400',
      );
      await tap(tester, '保存设置');
      expect(saved, 1);
      expect(h.writes, hasLength(1));
      expect(h.writes.single.url.path, '/root/api/admin/settings');
      expect(h.writes.single.body, isNot(contains(h.secret)));
      await close(tester);
    },
  );
  testWidgets(
    'replacement requires separate summary confirmation and return sends nothing',
    (tester) async {
      await open(tester);
      await tap(tester, '更换密钥');
      await enterKey(tester);
      await tap(tester, '保存设置');
      expect(find.text('确认更换密钥'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('owned replacement key'), findsNothing);
      expect(h.writes, isEmpty);
      await tap(tester, '返回核对');
      expect(h.writes, isEmpty);
      await tap(tester, '保存设置');
      await tap(tester, '确认保存');
      expect(saved, 1);
      expect(h.writes, hasLength(1));
      expect(h.secret, 'owned replacement key');
      expect(c.settingsReceipt!.action, AdminAssetKeyAction.replace);
      await close(tester);
    },
  );
  testWidgets(
    'disable cancellation never submits and confirmation is explicit',
    (tester) async {
      await open(tester);
      await tap(tester, '关闭加密');
      await tap(tester, '保存设置');
      expect(find.text('关闭凭据加密'), findsOneWidget);
      expect(h.writes, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.writes, isEmpty);
      await tap(tester, '保存设置');
      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();
      expect(h.writes, hasLength(1));
      expect(h.secret, '');
      expect(c.settingsReceipt!.action, AdminAssetKeyAction.disable);
      await close(tester);
    },
  );
  testWidgets(
    'background clears replacement while preserving explicit replace mode',
    (tester) async {
      await open(tester);
      await tap(tester, '更换密钥');
      await enterKey(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tap(tester, '保存设置');
      expect(h.writes, isEmpty);
      expect(saved, 0);
      expect(find.text('确认更换密钥'), findsNothing);
      final field = find.byKey(const ValueKey('asset-settings-key-confirm'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await close(tester);
    },
  );
}
