import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/labels/label_merge_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/label_management.dart';

Future<void> mount(WidgetTester tester, LabelManagementFixture repo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    LabelMergePage(repository: repo, target: repo.records[1]!),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester) async {
  final item = find.widgetWithText(CheckboxListTile, '学习方法');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('检查并合并'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'selection and cancellation never mutate; explicit merge retains target and pops',
    (tester) async {
      final repo = LabelManagementFixture();
      await mount(tester, repo);
      await choose(tester);
      expect(repo.mergeCalls, 0);
      await tester.tap(find.text('检查并合并'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repo.mergeCalls, 0);
      expect(repo.records.containsKey(2), isTrue);
      await tester.tap(find.text('检查并合并'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认合并'));
      await tester.pumpAndSettle();
      expect(repo.mergeCalls, 1);
      expect(repo.records.containsKey(1), isTrue);
      expect(repo.records.containsKey(2), isFalse);
      expect(find.byType(LabelMergePage), findsNothing);
    },
  );
  testWidgets(
    'unknown transaction result requires canonical recheck and cannot auto-submit again',
    (tester) async {
      final repo = LabelManagementFixture()..failAfterMerge = true;
      await mount(tester, repo);
      await choose(tester);
      await tester.tap(find.text('检查并合并'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认合并'));
      await tester.pumpAndSettle();
      expect(repo.mergeCalls, 1);
      final verify = find.text('重新核对目标和源标签');
      await tester.ensureVisible(verify);
      await tester.pumpAndSettle();
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(repo.mergeCalls, 1);
      expect(repo.records.containsKey(2), isFalse);
      await tester.ensureVisible(find.text('检查并合并'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '检查并合并'))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('源标签已不存在'), findsOneWidget);
    },
  );
}
