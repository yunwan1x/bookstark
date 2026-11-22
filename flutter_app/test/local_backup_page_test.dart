import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_page.dart';

void main() {
  var created = 0, picked = 0, pendingOpened = 0, reviewOpened = 0;
  Widget page({double scale = 1, bool english = false}) => MaterialApp(
    theme: bookstarkTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: LocalBackupPage(
      english: english,
      createExport: () async {
        created++;
        throw PendingLocalRecovery(
          LocalRecoverySummary(
            references: [],
            complexKeys: ['a' * 64],
            unknown: 0,
            activeTransfers: 0,
            overflow: false,
          ),
        );
      },
      saveExport: (_) async =>
          throw StateError('Must not save pending recovery'),
      inspectPicked: () async {
        picked++;
        return null;
      },
      apply: (_) async =>
          throw StateError('Must not restore without validated candidate'),
      openRecovery: () async {
        reviewOpened++;
      },
      openPending: (summary) async {
        expect(summary.needsAttention, isTrue);
        pendingOpened++;
      },
      openRetained: () async {},
      openLegacyMigration: () async {},
    ),
  );
  setUp(() {
    created = 0;
    picked = 0;
    pendingOpened = 0;
    reviewOpened = 0;
  });

  testWidgets(
    'export requires scope review then routes real pending metadata without saving',
    (tester) async {
      await tester.pumpWidget(page());
      await tester.tap(find.text('导出备份'));
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(find.text('不包含账户凭据与登录状态'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('创建并导出'), 200);
      await tester.tap(find.text('创建并导出'));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(pendingOpened, 1);
      expect(find.text('备份已保存到所选位置'), findsNothing);
    },
  );
  testWidgets('picker cancellation does not expose restore confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.scrollUntilVisible(find.text('选择备份文件'), 200);
    await tester.tap(find.text('选择备份文件'));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.text('确认恢复'), findsNothing);
    expect(find.text('本地备份与迁移'), findsOneWidget);
  });
  testWidgets(
    '320 wide and double text keep all entry controls reachable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(page(scale: 2));
      await tester.scrollUntilVisible(find.text('核对恢复状态'), 220);
      await tester.tap(find.text('核对恢复状态'));
      await tester.pumpAndSettle();
      expect(reviewOpened, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'English export cancellation returns to entry without creating a file',
    (tester) async {
      await tester.pumpWidget(page(english: true));
      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cancel'), 220);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Local backup and migration'), findsOneWidget);
      expect(created, 0);
    },
  );
}
