import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/labels/labels_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/label_management.dart';

void main() {
  testWidgets(
    'search statistics describe matching labels and opening sends real ID',
    (tester) async {
      final repo = LabelManagementFixture();
      int? id;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelsPage(
            repository: repo,
            onOpenLabel: (label) async {
              id = label.id;
            },
            onMerge: (_) async {},
            onRecommendations: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '待整理');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('统计仅含当前搜索匹配标签'), findsOneWidget);
      await tester.ensureVisible(
        find.descendant(of: find.byType(Card), matching: find.text('待整理')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('待整理')),
      );
      await tester.pumpAndSettle();
      expect(id, 4);
      expect(repo.saveCalls, 0);
      expect(repo.mergeCalls, 0);
    },
  );
  testWidgets(
    'ordinary member sees creation but no global destructive actions',
    (tester) async {
      final repo = LabelManagementFixture(canManage: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelsPage(
            repository: repo,
            onOpenLabel: (_) async {},
            onMerge: (_) async {},
            onRecommendations: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('标签操作'), findsNothing);
      expect(find.byTooltip('管理操作'), findsNothing);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'English label list supports small screen with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = LabelManagementFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LabelsPage(
            repository: repo,
            english: true,
            onOpenLabel: (_) async {},
            onMerge: (_) async {},
            onRecommendations: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Flutter'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
