// Prepared widget drafts; NOT RUN. No browser/Native/layout PASS claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/book_creation_attempt.dart';
import 'package:bookstark_flutter/features/book_creation_recovery_page.dart';
import 'book_creation_recovery_test.dart' show Env, input;

Widget host(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(320, 640),
      textScaler: TextScaler.linear(2),
      viewInsets: EdgeInsets.only(bottom: 180),
    ),
    child: child,
  ),
);
void main() {
  testWidgets(
    'English320/200% keyboard180 explicit existing-ID flow remains reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final e = Env()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      await tester.pumpWidget(
        host(BookCreationRecoveryPage(controller: c, english: true)),
      );
      final begin = find.text('Review an existing book ID');
      await tester.scrollUntilVisible(
        begin,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(begin);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '208');
      final read = find.widgetWithText(OutlinedButton, 'Read without writing');
      await tester.ensureVisible(read);
      await tester.pumpAndSettle();
      expect(read.hitTestable(), findsOneWidget);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(c.review, isNotNull);
      final confirm = find.text('Confirm link to existing book');
      await tester.scrollUntilVisible(
        confirm,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Confirm link to existing book',
              ),
            )
            .onPressed,
        isNull,
      );
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(c.attempt!.origin, BookIDOrigin.manualExisting);
      expect(c.attempt!.knownID, 208);
      expect(e.posts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('known-ID storage retry action performs no additional creation', (
    tester,
  ) async {
    final e = Env()..failKnownWrite = true, c = e.controller();
    addTearDown(c.dispose);
    await c.start(input());
    await c.submit();
    await tester.pumpWidget(
      host(BookCreationRecoveryPage(controller: c, english: true)),
    );
    final retry = find.text('Retry device storage only');
    await tester.scrollUntilVisible(
      retry,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(e.posts, 1);
    expect(c.knownDurable, true);
    expect(find.text('#208'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
