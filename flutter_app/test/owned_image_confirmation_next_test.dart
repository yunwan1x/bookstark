import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned_complex_image_picker_action.dart';
import 'package:bookstark_flutter/features/complex_editors/owned_image_upload_confirmation.dart';

void main() {
  for (final english in [false, true]) {
    for (final accept in [false, true]) {
      testWidgets(
        'real confirmation ${english ? 'EN' : 'ZH'} 320dp font2 keyboard ${accept ? 'explicit accept' : 'cancel'}',
        (tester) async {
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = const Size(640, 1280);
          tester.view.viewInsets = const FakeViewPadding(bottom: 360);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          bool? result;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await confirmOwnedImageUpload(
                        context,
                        const OwnedImageConfirmation(
                          name: 'actual-selected-image.png',
                          bytes: 84000,
                          width: 640,
                          height: 480,
                        ),
                        english: english,
                        protectedDocument: true,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(
            find.textContaining(
              english ? 'not protected by the note password' : '不受笔记密码保护',
            ),
            findsOneWidget,
          );
          if (accept) {
            final checkbox = find.byType(Checkbox);
            await tester.ensureVisible(checkbox);
            await tester.pump();
            expect(checkbox.hitTestable(), findsOneWidget);
            await tester.tap(checkbox.hitTestable());
            await tester.pump();
            expect(tester.widget<Checkbox>(checkbox).value, true);
            expect(
              tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
              isNotNull,
            );
            await tester.ensureVisible(find.byType(FilledButton));
            await tester.tap(find.byType(FilledButton));
          } else {
            final cancel = find.text(english ? 'Keep editing' : '继续编辑');
            await tester.ensureVisible(cancel);
            await tester.tap(cancel);
          }
          await tester.pumpAndSettle();
          expect(result, accept);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
