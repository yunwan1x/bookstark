// Draft only; NOT RUN or browser/Native evidence.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/drive_operation_record.dart';
import 'package:bookstark_flutter/core/drive_operation_recovery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/drive_operation_recovery_page.dart';
import 'drive_operation_recovery_test.dart' show DriveEnv;

Finder pageScroll() => find
    .descendant(
      of: find
          .descendant(
            of: find.byType(DriveOperationRecoveryPage),
            matching: find.byType(ListView),
          )
          .first,
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> revealMain(
  WidgetTester tester,
  Finder target, {
  double delta = 100,
}) async {
  await tester.scrollUntilVisible(target, delta, scrollable: pageScroll());
  // A jump/drag changes layout. Flush it before taking a hit-test coordinate.
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'English 320dp/200 percent/inset recovery scroll and EndRecord confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final e = DriveEnv()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      await c.beginAndSubmit(e.pending());
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 180),
            ),
            child: SizedBox(
              width: 320,
              height: 640,
              child: DriveOperationRecoveryPage(controller: c, english: true),
            ),
          ),
        ),
      );
      final review = find.text('Review source and target (read only)');
      await revealMain(tester, review, delta: 100);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(c.review, isNotNull);
      final end = find.text('End device record');
      await revealMain(tester, end, delta: 100);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'End record'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'End record'));
      await tester.pumpAndSettle();
      expect(c.record, isNull);
      expect(e.sends, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'controller replacement listens to B and late A observation cannot repaint B',
    (tester) async {
      final a = DriveEnv()..drop = true, b = DriveEnv()..drop = true;
      final ca = a.controller(), cb = b.controller();
      addTearDown(ca.dispose);
      addTearDown(cb.dispose);
      await ca.load();
      await ca.beginAndSubmit(a.pending());
      await ca.load();
      await cb.load();
      await cb.beginAndSubmit(
        b.pending(key: 'cccccccccccccccccccccccccccccccc'),
      );
      var current = ca;
      late StateSetter swap;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              swap = set;
              return DriveOperationRecoveryPage(
                controller: current,
                english: true,
              );
            },
          ),
        ),
      );
      final held = Completer<DriveOperationObservation>(),
          entered = Completer<void>();
      a.readHook = (path) {
        if (!entered.isCompleted) entered.complete();
        return held.future;
      };
      final lateRead = ca.inspect();
      await entered.future;
      swap(() => current = cb);
      await tester.pump();
      await cb.load();
      await tester.pump();
      expect(find.text('Review source and target (read only)'), findsOneWidget);
      held.complete(
        DriveOperationObservation(
          path: 'a.md',
          state: DriveObservationState.missing,
        ),
      );
      await lateRead;
      await tester.pump();
      expect(cb.review, isNull);
      await cb.inspect();
      await tester.pump();
      expect(
        find.text(
          'Current observations do not prove this operation succeeded.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('A confirmation cannot end B record after controller swap', (
    tester,
  ) async {
    final a = DriveEnv()..drop = true, b = DriveEnv()..drop = true;
    final ca = a.controller(), cb = b.controller();
    addTearDown(ca.dispose);
    addTearDown(cb.dispose);
    await ca.load();
    await ca.beginAndSubmit(a.pending());
    await ca.load();
    await cb.load();
    await cb.beginAndSubmit(b.pending(key: 'dddddddddddddddddddddddddddddddd'));
    await cb.load();
    final rawA = a.values[a.store.metadataKey],
        rawB = b.values[b.store.metadataKey];
    DriveOperationRecoveryController current = ca;
    late StateSetter swap;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            swap = set;
            return DriveOperationRecoveryPage(
              controller: current,
              english: true,
            );
          },
        ),
      ),
    );
    await revealMain(tester, find.text('End device record'), delta: 100);
    await tester.tap(find.text('End device record'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    swap(() => current = cb);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'End record'));
    await tester.pumpAndSettle();
    expect(a.values[a.store.metadataKey], rawA);
    expect(b.values[b.store.metadataKey], rawB);
    expect(ca.record, isNotNull);
    expect(cb.record, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed claim marker shows reload and requires fresh unknown before EndRecord',
    (tester) async {
      final e = DriveEnv(), c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      e.claimFlushFails = true;
      await c.beginAndSubmit(e.pending());
      await tester.pumpWidget(
        MaterialApp(
          home: DriveOperationRecoveryPage(controller: c, english: true),
        ),
      );
      final end = find.widgetWithText(OutlinedButton, 'End device record');
      await revealMain(tester, end, delta: 100);
      expect(tester.widget<OutlinedButton>(end).onPressed, isNull);
      final reload = find.text('Reload device record');
      await revealMain(tester, reload, delta: -100);
      await tester.tap(reload);
      await tester.pumpAndSettle();
      expect(c.record!.state, DriveOperationState.unknown);
      expect(c.storageUnconfirmed, false);
      await revealMain(tester, end, delta: 100);
      expect(tester.widget<OutlinedButton>(end).onPressed, isNotNull);
      expect(e.sends, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'applied delete with failed flush offers storage-only reload to empty',
    (tester) async {
      final e = DriveEnv()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      await c.beginAndSubmit(e.pending());
      await c.load();
      e.endFlushFails = true;
      await c.endRecord(
        expectedFingerprint: c.record!.fingerprint,
        explicitlyConfirmed: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DriveOperationRecoveryPage(controller: c, english: true),
        ),
      );
      expect(c.storageUnconfirmed, true);
      final reload = find.text('Reload device record');
      await revealMain(tester, reload, delta: 100);
      await tester.tap(reload);
      await tester.pumpAndSettle();
      expect(
        find.text('No retained operation record was found.'),
        findsOneWidget,
      );
      expect(c.blocked, false);
      expect(e.sends, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
