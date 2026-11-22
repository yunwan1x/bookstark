import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:bookstark_flutter/widgets/native_pdf.dart';
import 'fixtures/native_pdf.dart';

Future<void> drainPdf(WidgetTester tester) async {
  for (var n = 0; n < 24; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await root.create(recursive: true);
    directory = await root.createTemp('native-pdf-widget-');
    Pdfrx.cacheDirectoryPath = directory.path;
    if (Platform.isLinux) {
      final libraries =
          await Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build')
              .list(recursive: true, followLinks: false)
              .where(
                (file) =>
                    file is File &&
                    file.path.endsWith('/linux-x64/libpdfium.so'),
              )
              .toList();
      Pdfrx.pdfiumModulePath = libraries.first.path;
    }
    await pdfrxFlutterInitialize();
  });
  tearDownAll(() async {
    Pdfrx.cacheDirectoryPath = null;
    await directory.delete(recursive: true);
  });
  testWidgets(
    'PDF uses real page count and native pixels, navigates boundaries and exposes extracted text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativePdf(
              bytes: nativePdfFixture(),
              sourceName: 'real.pdf',
              english: true,
            ),
          ),
        ),
      );
      await drainPdf(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('/ 1'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Previous page',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Next page',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '2');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1',
      );
      await tester.tap(find.byTooltip('Read page text'));
      await drainPdf(tester);
      expect(find.textContaining('Native PDF proof'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainPdf(tester);
    },
  );
  testWidgets(
    'invalid PDF reports a retryable error and replacing the source clears stale error and pixels',
    (tester) async {
      Widget page(Uint8List bytes, String name) => MaterialApp(
        home: Scaffold(
          body: NativePdf(bytes: bytes, sourceName: name, english: true),
        ),
      );
      await tester.pumpWidget(page(Uint8List.fromList([0, 1, 2]), 'bad.pdf'));
      await drainPdf(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(page(nativePdfFixture(), 'fixed.pdf'));
      await drainPdf(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainPdf(tester);
    },
  );
  testWidgets(
    'native PDF controls wrap at 320dp and double text without hiding the document',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: NativePdf(
              bytes: nativePdfFixture(),
              sourceName: 'small.pdf',
              english: true,
            ),
          ),
        ),
      );
      await drainPdf(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainPdf(tester);
    },
  );
}
