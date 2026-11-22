import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_page.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scroll = find.byType(Scrollable).first;
  expect(scroll, findsOneWidget);
  for (
    var step = 0;
    step < 100 && target.hitTestable().evaluate().isEmpty;
    step++
  ) {
    final box = tester.getRect(scroll);
    await tester.dragFrom(
      Offset(box.left + 8, box.center.dy),
      const Offset(0, -100),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'English320/200% keyboard keeps historical-plaintext notice before export action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var creates = 0, saves = 0;
      const notice =
          'The backup retains original protection and encryption and may contain historical plaintext. The current unlock password is not included. Choose a trusted location.';
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 180),
            ),
            child: child!,
          ),
          home: LocalBackupPage(
            english: true,
            exportNotice: notice,
            createExport: () async {
              creates++;
              throw StateError('No export requested in visual notice test');
            },
            saveExport: (_) async {
              saves++;
              throw StateError('No system chooser in host test');
            },
            inspectPicked: () async => null,
            apply: (_) async {},
            openRecovery: () async {},
            openPending: (_) async {},
            openRetained: () async {},
            openLegacyMigration: () async {},
          ),
        ),
      );
      await reveal(tester, find.text('Export backup'));
      await tester.tap(find.text('Export backup'));
      await tester.pump();
      await reveal(tester, find.text(notice));
      expect(find.text(notice), findsOneWidget);
      expect(creates, 0);
      expect(saves, 0);
      await reveal(tester, find.text('Create and export'));
      expect(find.text('Create and export').hitTestable(), findsOneWidget);
      expect(creates, 0);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
