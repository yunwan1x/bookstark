import 'package:bookstark_flutter/features/admin/admin_asset_delete_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;

void main() {
  testWidgets(
    'cancel does not invoke deletion; confirmation cannot repeat on retained page',
    (tester) async {
      var deletes = 0, cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminAssetDeletePage(
            credential: AdminAssetCredentialMetadata.parse(base.credential(9)),
            onConfirm: () async {
              deletes++;
            },
            onCancel: () {
              cancels++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('取消'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(cancels, 1);
      expect(deletes, 0);
      await tester.tap(find.text('确认删除凭据'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认删除凭据'))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('owned synthetic response secret'),
        findsNothing,
      );
    },
  );
}
