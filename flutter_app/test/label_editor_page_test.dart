import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/features/labels/label_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/label_management.dart';

void main() {
  testWidgets(
    'unverified create is adopted only after canonical lookup and never reposted',
    (tester) async {
      final repo = LabelManagementFixture()..failAfterCreate = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelEditorPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新标签');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 1);
      expect(find.text('核对创建结果'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.tap(find.text('核对创建结果'));
      await tester.pumpAndSettle();
      expect(find.text('核对创建结果'), findsNothing);
      expect(find.text('编辑标签'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 2);
      expect(repo.records.values.where((row) => row.name == '新标签').length, 1);
    },
  );
  testWidgets(
    'draft cleanup failure retains actual newly created ID for later update',
    (tester) async {
      final repo = LabelManagementFixture();
      final vault = DraftVault(
        namespace: 'label-test',
        readValue: (_) async => null,
        writeValue: (_, value) async {},
        deleteValue: (_) async => throw StateError('Storage failed'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelEditorPage(repository: repo, vault: vault),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '初稿');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Storage failed'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '终稿');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.records[20]!.name, '终稿');
      expect(repo.records.length, 5);
      expect(repo.saveCalls, 2);
    },
  );
  testWidgets(
    'UTF8 limit rejects before create and non-admin existing form is read only',
    (tester) async {
      final repo = LabelManagementFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelEditorPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        List.filled(34, '书').join(),
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 0);
      expect(find.textContaining('100字节'), findsWidgets);
      final member = LabelManagementFixture(canManage: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelEditorPage(
            key: const ValueKey('member'),
            repository: member,
            label: member.records[1],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull,
      );
    },
  );
}
