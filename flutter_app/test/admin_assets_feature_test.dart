import 'dart:convert';
import 'package:bookstark_flutter/features/admin/admin_assets_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_credential_editor_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_private_key_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_assets_mutations_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late fixture.Harness h;
  late AdminAssetsController c;
  late AdminAssetsScope scope;
  final calls = <MethodCall>[];
  setUp(() {
    h = fixture.Harness();
    c = AdminAssetsController(h.repo, base.owner);
    scope = AdminAssetsScope(h.client, base.owner);
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    scope.dispose();
    h.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetsFeature(scope: scope, controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'real catalog navigation opens new credential and one save returns with real creation ID',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('凭据'));
      await tester.pumpAndSettle();
      expect(find.text('新增凭据'), findsOneWidget);
      expect(find.text('新增主机'), findsNothing);
      await tap(tester, '新增凭据');
      expect(find.byType(AdminAssetCredentialEditorPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('asset-credential-name')),
        'owned new',
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-credential-username')),
        'owned-user',
      );
      final password = find.byKey(const ValueKey('asset-credential-password'));
      await tester.scrollUntilVisible(
        password,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(password, ' owned 临时密码 ');
      await tap(tester, '保存凭据');
      expect(h.writes, hasLength(1));
      expect(h.writes.single.method, 'POST');
      expect(jsonDecode(h.writes.single.body)['credential'], ' owned 临时密码 ');
      expect(find.byType(AdminAssetCredentialEditorPage), findsNothing);
      expect(find.text('新增凭据'), findsOneWidget);
      expect(c.savedCredential!.id, 10);
      expect(find.textContaining('owned 临时密码'), findsNothing);
      expect(h.transport.closes, 0);
      await close(tester);
    },
  );
  testWidgets(
    'closing owner scope removes nested key input and releases both secure leases',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('凭据'));
      await tester.pumpAndSettle();
      await tap(tester, '新增凭据');
      await tester.tap(find.byType(DropdownButtonFormField<AdminAssetAuth>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SSH 私钥').last);
      await tester.pumpAndSettle();
      await tap(tester, '编辑私钥');
      expect(find.byType(AdminAssetPrivateKeyPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('asset-private-key-input')),
        'owned transient key\nsecond line',
      );
      scope.close();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AdminAssetPrivateKeyPage), findsNothing);
      expect(calls.where((call) => call.method == 'acquire'), hasLength(2));
      expect(calls.where((call) => call.method == 'release'), hasLength(2));
      expect(h.writes, isEmpty);
      expect(h.transport.closes, 0);
      await close(tester);
    },
  );
  testWidgets(
    'fresh role loss closes pushed credential page and clears owned state',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('凭据'));
      await tester.pumpAndSettle();
      await tap(tester, '新增凭据');
      h.role = 1;
      await tester.runAsync(() => c.load(AdminAssetCatalog.hosts));
      await tester.pumpAndSettle();
      expect(scope.closed, isTrue);
      expect(c.closed, isTrue);
      expect(find.byType(AdminAssetCredentialEditorPage), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(h.writes, isEmpty);
      expect(h.transport.closes, 0);
      await close(tester);
    },
  );
  testWidgets('role loss from show-secret closes viewer and owner scope', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('凭据操作'));
    await tester.pumpAndSettle();
    await tap(tester, '查看凭据');
    expect(find.text('显示秘密'), findsOneWidget);
    h.role = 1;
    await tap(tester, '显示秘密');
    expect(scope.closed, isTrue);
    expect(find.text('显示秘密'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(h.writes, isEmpty);
    expect(h.transport.closes, 0);
    await close(tester);
  });
}
