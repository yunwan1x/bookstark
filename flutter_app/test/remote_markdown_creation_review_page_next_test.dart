import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_review_page.dart';
import 'remote_markdown_creation_controller_next_test.dart' show Fixture;

Finder recoveryListScroll() => find
    .descendant(
      of: find
          .descendant(
            of: find.byType(RemoteMarkdownCreationReviewPage),
            matching: find.byType(ListView),
          )
          .first,
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> revealRecovery(
  WidgetTester tester,
  Finder target, {
  double delta = 200,
}) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: recoveryListScroll(),
    );
  }
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'unknown result disables create, exact ID read never submits again',
    (tester) async {
      final f = Fixture();
      f.transport.drop = true;
      final c = await f.open();
      addTearDown(c.retire);
      await c.save();
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteMarkdownCreationReviewPage(controller: c, english: true),
        ),
      );
      await tester.pumpAndSettle();
      final create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create again'),
      );
      expect(create.onPressed, isNull);
      await revealRecovery(tester, find.text('Check an existing ID'));
      await tester.tap(find.text('Check an existing ID'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '318');
      await revealRecovery(tester, find.text('Read note'), delta: -200);
      await tester.tap(find.text('Read note'));
      await tester.pumpAndSettle();
      expect(find.text('Review both versions'), findsOneWidget);
      expect(c.phase, MarkdownCreationPhase.review);
      await revealRecovery(tester, find.text('Use this saved note'));
      expect(f.transport.posts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this saved note'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('both full snapshots must be explicitly viewed before adoption', (
    tester,
  ) async {
    final f = Fixture();
    f.transport.drop = true;
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    await c.inspect(318);
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteMarkdownCreationReviewPage(controller: c, english: true),
      ),
    );
    await tester.pumpAndSettle();
    for (var n = 0; n < 2; n++) {
      final button = find.text('View full snapshot').at(n);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final done = find.text('I reviewed the complete snapshot');
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
    }
    final use = find.text('Use this saved note');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(c.phase, MarkdownCreationPhase.finished);
    expect(f.transport.posts, 1);
    expect(await f.vault.read(), isNull);
  });
  testWidgets(
    'cleanup button performs storage only and back keeps unresolved record',
    (tester) async {
      final f = Fixture();
      f.deleteFails = true;
      final c = await f.open();
      addTearDown(c.retire);
      await c.save();
      final reads = f.transport.reads;
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteMarkdownCreationReviewPage(controller: c, english: true),
        ),
      );
      await tester.pumpAndSettle();
      f.deleteFails = false;
      await tester.tap(find.text('Retry cleanup only'));
      await tester.pumpAndSettle();
      expect(c.phase, MarkdownCreationPhase.finished);
      expect(f.transport.reads, reads);
      expect(f.transport.posts, 1);
    },
  );
  testWidgets('EN320 200percent with keyboard retains scrollable ID controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = Fixture();
    f.transport.drop = true;
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 180),
          ),
          child: child!,
        ),
        home: RemoteMarkdownCreationReviewPage(controller: c, english: true),
      ),
    );
    await tester.pumpAndSettle();
    await revealRecovery(tester, find.text('Check an existing ID'));
    await tester.tap(find.text('Check an existing ID'));
    await tester.pumpAndSettle();
    await revealRecovery(tester, find.text('Read note'), delta: -200);
    expect(find.text('Read note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(f.transport.posts, 1);
  });
}
