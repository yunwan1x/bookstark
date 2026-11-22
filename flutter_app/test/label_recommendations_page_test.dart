import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/labels/label_recommendations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/label_management.dart';

void main() {
  testWidgets(
    'preview is read-only until explicit save and rejected size preserves inputs',
    (tester) async {
      final repo = LabelManagementFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelRecommendationsPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.scrollUntilVisible(
        find.text('预览推荐'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('预览推荐'));
      await tester.pumpAndSettle();
      expect(repo.previewCalls, 1);
      expect(repo.settingsWrites, 0);
      expect(repo.settings.pageSize, 10);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.settingsWrites, 1);
      expect(repo.settings.pageSize, 3);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '51');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.settingsWrites, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '51',
      );
      await tester.scrollUntilVisible(
        find.textContaining('推荐数量1—50'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('推荐数量1—50'), findsOneWidget);
    },
  );
  testWidgets(
    'ordinary member can preview real settings but cannot submit changes',
    (tester) async {
      final repo = LabelManagementFixture(canManage: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelRecommendationsPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.scrollUntilVisible(
        find.text('预览推荐'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('预览推荐'));
      await tester.pumpAndSettle();
      expect(repo.previewCalls, 1);
      expect(repo.settingsWrites, 0);
    },
  );
  testWidgets('English small 200 percent settings scroll without overflow', (
    tester,
  ) async {
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
        home: LabelRecommendationsPage(repository: repo, english: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Preview recommendations'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Preview recommendations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview recommendations'));
    await tester.pumpAndSettle();
    expect(repo.previewCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
