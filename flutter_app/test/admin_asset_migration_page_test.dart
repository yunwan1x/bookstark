import 'package:bookstark_flutter/features/admin/admin_asset_migration_page.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_asset_migration_test.dart' as fixture;

void main() {
  late fixture.MigrationHarness h;
  late AdminAssetsController c;
  var returned = 0, bound = 0;
  setUp(() {
    h = fixture.MigrationHarness();
    c = AdminAssetsController(h.repo, base.owner);
    returned = bound = 0;
  });
  tearDown(() {
    c.dispose();
    h.close();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() => c.load(AdminAssetCatalog.hosts));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetMigrationPage(
          controller: c,
          host: c.hosts!.single,
          onReturn: () {
            returned++;
          },
          onBound: () {
            bound++;
          },
        ),
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
    'actual buttons create once then separately verify and bind actual ID',
    (tester) async {
      await open(tester);
      expect(h.writes, isEmpty);
      await tap(tester, '确认迁移');
      expect(h.writes.map((r) => r.method), ['POST']);
      expect(h.cid, 0);
      expect(find.textContaining('owned synthetic first'), findsNothing);
      expect(find.text('1  凭据已创建，ID 10'), findsOneWidget);
      await tap(tester, '核对并绑定本主机');
      expect(h.writes.map((r) => r.method), ['POST', 'PUT']);
      expect(h.cid, 10);
      expect(bound, 1);
      await close(tester);
    },
  );
  testWidgets('cancel before confirmation sends no write', (tester) async {
    await open(tester);
    await tap(tester, '取消');
    expect(returned, 1);
    expect(h.writes, isEmpty);
    await close(tester);
  });
  testWidgets(
    'background after creation disables binding and retains safe partial receipt',
    (tester) async {
      await open(tester);
      await tap(tester, '确认迁移');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('核对并绑定本主机'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '核对并绑定本主机'))
            .onPressed,
        isNull,
      );
      expect(c.migrationCreated!.credential.id, 10);
      expect(h.writes, hasLength(1));
      await close(tester);
    },
  );
}
