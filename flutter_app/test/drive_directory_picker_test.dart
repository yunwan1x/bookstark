import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/drive/drive_directory_picker.dart';
import '../tool/fixtures/drive.dart';

void main() {
  testWidgets(
    'excluded initial subtree returns to parent and cannot be selected',
    (tester) async {
      final repo = DriveFixture(seed: false)
        ..addDirectory('source')
        ..addDirectory('source/child')
        ..addDirectory('other');
      await tester.pumpWidget(
        MaterialApp(
          home: DriveDirectoryPicker(
            repository: repo,
            initial: 'source/child',
            exclude: 'source',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      expect(find.text('source'), findsNothing);
      expect(find.text('child'), findsNothing);
      expect(repo.uploads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('directory picker remains usable at 320dp and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = DriveFixture(seed: false)
      ..addDirectory('资料')
      ..addDirectory('资料/插图');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: DriveDirectoryPicker(
          repository: repo,
          initial: '资料',
          exclude: 'other',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('选择此目录'), findsOneWidget);
    await tester.ensureVisible(find.text('返回上一级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回上一级'));
    await tester.pumpAndSettle();
    expect(find.text('全部文件 / 资料'), findsNothing);
    expect(find.text('全部文件'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
