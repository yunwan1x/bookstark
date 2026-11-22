import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/local_restore_coordinator.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_retention_catalog_page.dart';
import 'support/local_backup_fixture.dart';

void main() {
  late LocalBackupFixture fixture;
  setUp(() async {
    final oldPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = oldPolicy);
    fixture = await LocalBackupFixture.create();
  });
  tearDown(() async {
    await fixture.dispose();
  });
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  Future<void> confirmScope(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('核对并继续'), 200);
    await tester.tap(find.text('核对并继续'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认恢复'))
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(find.byType(Checkbox), -200);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('确认恢复'), 200);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '确认恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();
  }

  Widget backup({
    required Future<void> Function() apply,
    required Future<void> Function() review,
    Future<void> Function(LocalRecoverySummary)? pending,
  }) => MaterialApp(
    home: LocalBackupPage(
      initialCandidate: fixture.candidate,
      createExport: () async => throw StateError('Not exporting'),
      saveExport: (_) async => throw StateError('Not saving'),
      inspectPicked: () async => null,
      apply: (_) => apply(),
      openRecovery: review,
      openPending: pending ?? (_) async {},
      openRetained: () async {},
      openLegacyMigration: () async {},
    ),
  );

  testWidgets(
    'actual validated counts require checkbox; unknown result cannot replay confirmation',
    (tester) async {
      var applies = 0, reviews = 0;
      await tester.pumpWidget(
        backup(
          apply: () async {
            applies++;
            throw const LocalControlUnconfirmed('switched');
          },
          review: () async {
            reviews++;
          },
        ),
      );
      final row = find.ancestor(
        of: find.text('笔记与文章（含已删除）'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('文件完整性检查通过'), findsOneWidget);
      await confirmScope(tester);
      expect(applies, 1);
      expect(reviews, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认恢复'))
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(find.text('核对恢复结果'), 200);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, '核对恢复结果'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对恢复结果'));
      await tester.pumpAndSettle();
      expect(applies, 1);
      expect(reviews, 2);
      final raw = await tester.runAsync(
        () async => (await fixture.store.database).rawQuery(
          'SELECT CAST(content AS BLOB) AS body FROM notes WHERE id = 1',
        ),
      );
      expect(raw!.single['body'], utf8.encode('\uFEFF# 原文\r\n'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'known preflight refusal opens pending editor flow without false result review',
    (tester) async {
      var reviews = 0, pending = 0;
      await tester.pumpWidget(
        backup(
          apply: () async => throw LocalRestoreNotStarted(
            PendingLocalRecovery(
              LocalRecoverySummary(
                references: [],
                complexKeys: ['a' * 64],
                unknown: 0,
                activeTransfers: 0,
                overflow: false,
              ),
            ),
          ),
          review: () async {
            reviews++;
          },
          pending: (_) async {
            pending++;
          },
        ),
      );
      await confirmScope(tester);
      expect(pending, 1);
      expect(reviews, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认恢复'))
            .onPressed,
        isNotNull,
      );
      expect(find.text('核对恢复结果'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'readonly narrow catalog fully checks retained archive and offers scope without restore',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final control = NativeLocalDataControl(
        invoke: (_, _) async => {
          'format': 1,
          'retentions': [fixture.retention.encode()],
          'unknown': 1,
          'overflow': false,
          'metadataOnly': true,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: LocalRetentionCatalogPage(
            load: control.listRetained,
            canRestore: false,
            inspect: fixture.importer.inspectRetained,
            restore: (_) async =>
                throw StateError('Read-only catalog cannot restore'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('检查此快照'), 200);
      expect(find.text('从此快照恢复'), findsNothing);
      await tester.tap(find.text('检查此快照'));
      await tester.pump();
      await settle(tester, () => find.text('查看范围').evaluate().isNotEmpty);
      await tester.scrollUntilVisible(find.text('查看范围'), 200);
      await tester.ensureVisible(find.widgetWithText(TextButton, '查看范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看范围'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('笔记及文章 2'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('不包含账户'), findsOneWidget);
      expect(find.text('从此快照恢复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('failed archive inspection never exposes a restore action', (
    tester,
  ) async {
    final control = NativeLocalDataControl(
      invoke: (_, _) async => {
        'format': 1,
        'retentions': [fixture.retention.encode()],
        'unknown': 0,
        'overflow': false,
        'metadataOnly': true,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LocalRetentionCatalogPage(
          load: control.listRetained,
          canRestore: true,
          inspect: (_) async => throw const FormatException('Corrupt'),
          restore: (_) async =>
              throw StateError('Unverified copy cannot restore'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查此快照'));
    await tester.pumpAndSettle();
    expect(find.textContaining('快照未能完成检查'), findsOneWidget);
    expect(find.text('从此快照恢复'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
