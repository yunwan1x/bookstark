import 'package:bookstark_flutter/features/admin/admin_assets_catalog_page.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;

void main() {
  late base.Harness h;
  late AdminAssetsController c;
  var created = 0,
      hostOpened = 0,
      credentialEdited = 0,
      revealed = 0,
      deleted = 0;
  setUp(() {
    h = base.Harness();
    c = AdminAssetsController(h.repo, base.owner);
    created = hostOpened = credentialEdited = revealed = deleted = 0;
  });
  tearDown(() {
    c.dispose();
    h.close();
  });
  Widget page({
    AdminAssetCatalog catalog = AdminAssetCatalog.hosts,
    bool english = false,
    double scale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),

    home: AdminAssetsCatalogPage(
      controller: c,
      catalog: catalog,
      english: english,
      onCatalog: (_) {},
      onReturn: () {},
      onSettings: () {},
      onCreate: () {
        created++;
      },
      onHost: (row) {
        hostOpened = row.id;
      },
      onCredential: (row) {
        credentialEdited = row.id;
      },
      onRevealCredential: (row) {
        revealed = row.id;
      },
      onDeleteCredential: (row) {
        deleted = row.id;
      },
    ),
  );
  testWidgets(
    'host load and actual status-chip click read only; detail uses real ID',
    (tester) async {
      await tester.runAsync(() => c.load(AdminAssetCatalog.hosts));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('owned synthetic response secret'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '离线'));
      await tester.pumpAndSettle();
      final latest = h.calls.lastWhere(
        (r) => r.url.path.endsWith('/ssh-hosts'),
      );
      expect(latest.method, 'GET');
      expect(latest.url.queryParameters['status'], 'offline');
      await tester.scrollUntilVisible(
        find.text('查看主机'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看主机'));
      await tester.pump();
      expect(hostOpened, 5);
      expect(h.calls.map((r) => r.method), everyElement('GET'));
    },
  );
  testWidgets(
    'credential edit and explicit view/delete menu carry exact ID without rendering secret',
    (tester) async {
      await tester.runAsync(() => c.load(AdminAssetCatalog.credentials));
      await tester.pumpWidget(page(catalog: AdminAssetCatalog.credentials));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('owned synthetic response secret'),
        findsNothing,
      );
      await tester.tap(find.text('编辑凭据'));
      await tester.pump();
      expect(credentialEdited, 9);
      await tester.tap(find.byTooltip('凭据操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看凭据'));
      await tester.pumpAndSettle();
      expect(revealed, 9);
      await tester.tap(find.byTooltip('凭据操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除凭据'));
      await tester.pumpAndSettle();
      expect(deleted, 9);
      expect(h.calls.map((r) => r.method), everyElement('GET'));
    },
  );
  testWidgets(
    'failed catalog does not claim zero results and real refresh retries GET only',
    (tester) async {
      h.credentialsStatus = 503;
      await tester.runAsync(() => c.load(AdminAssetCatalog.credentials));
      await tester.pumpWidget(page(catalog: AdminAssetCatalog.credentials));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前数量未知'), findsOneWidget);
      expect(find.textContaining('当前显示'), findsNothing);
      h.credentialsStatus = 200;
      await tester.tap(find.byTooltip('刷新资料'));
      await tester.pumpAndSettle();
      expect(find.text('当前显示 1 项'), findsOneWidget);
      expect(h.calls.map((r) => r.method), everyElement('GET'));
    },
  );
  testWidgets(
    'search submitted through text field preserves Go wildcard query',
    (tester) async {
      await tester.runAsync(() => c.load(AdminAssetCatalog.hosts));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  %_  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(c.appliedQuery, '%_');
      expect(h.calls.last.url.queryParameters['q'], '%_');
      expect(h.calls.last.method, 'GET');
    },
  );
  testWidgets(
    'unknown result blocks create until read and explicit finish review',
    (tester) async {
      c.operation = AdminAssetOperationState.unknown;
      c.unknownReviewCatalog = AdminAssetCatalog.credentials;
      await tester.runAsync(() => c.load(AdminAssetCatalog.credentials));
      await tester.pumpWidget(page(catalog: AdminAssetCatalog.credentials));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '新增凭据'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('结束本次核对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增凭据'));
      await tester.pump();
      expect(created, 1);
      expect(h.calls.map((r) => r.method), everyElement('GET'));
    },
  );
  testWidgets('320dp English at 200 percent reaches create without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => c.load(AdminAssetCatalog.credentials));
    await tester.pumpWidget(
      page(catalog: AdminAssetCatalog.credentials, english: true, scale: 2),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(AdminAssetsCatalogPage)),
      ).scale(16),
      32,
    );
    await tester.scrollUntilVisible(
      find.text('Add credential'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add credential'));
    await tester.pump();
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });
}
