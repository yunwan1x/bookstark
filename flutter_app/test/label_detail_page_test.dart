import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/features/labels/label_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/label_management.dart';

void main() {
  testWidgets(
    'missing document title uses typed real ID and loaded search preserves source identity',
    (tester) async {
      final repo = LabelManagementFixture();
      LabelResource? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelDetailPage(
            repository: repo,
            labelId: 1,
            onOpenResource: (item) async {
              opened = item;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '41');
      await tester.pumpAndSettle();
      expect(find.text('文档 #41'), findsOneWidget);
      final open = find.byTooltip('打开资源');
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(opened!.type, LabelResourceType.document);
      expect(opened!.id, 41);
      expect((await repo.read(1)).items.length, 14);
    },
  );
  testWidgets(
    'unbind confirms and affects only exact label/resource association',
    (tester) async {
      final repo = LabelManagementFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: LabelDetailPage(
            repository: repo,
            labelId: 1,
            onOpenResource: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '41');
      await tester.pumpAndSettle();
      final unlink = find.byTooltip('解除关联');
      await tester.ensureVisible(unlink);
      await tester.pumpAndSettle();
      await tester.tap(unlink);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await repo.read(1)).items.length, 14);
      await tester.tap(unlink);
      await tester.pumpAndSettle();
      await tester.tap(find.text('解除关联'));
      await tester.pumpAndSettle();
      expect((await repo.read(1)).items.length, 13);
      expect(
        (await repo.read(2)).items.any(
          (item) => item.type == LabelResourceType.document && item.id == 41,
        ),
        isTrue,
      );
      expect(repo.records.containsKey(1), isTrue);
    },
  );
}
