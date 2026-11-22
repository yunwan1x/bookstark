import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'fixtures/native_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled native PDFium parses, extracts and rasterizes actual PDF bytes offline',
    () async {
      final root = Directory(
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
      );
      await root.create(recursive: true);
      final directory = await root.createTemp('native-pdf-');
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        if (Platform.isLinux) {
          // flutter_test's native-assets.yaml is empty; use the hook's real host library only in this test process.
          final hooks = Directory(
            '.dart_tool/hooks_runner/shared/pdfium_dart/build',
          );
          final libraries = await hooks
              .list(recursive: true, followLinks: false)
              .where(
                (file) =>
                    file is File &&
                    file.path.endsWith('/linux-x64/libpdfium.so'),
              )
              .toList();
          expect(libraries, isNotEmpty);
          Pdfrx.pdfiumModulePath = libraries.first.path;
        }
        await pdfrxFlutterInitialize();
        final document = await PdfDocument.openData(
          nativePdfFixture(),
          sourceName: 'original-native-fixture.pdf',
        );
        try {
          expect(document.pages.length, 1);
          final page = document.pages.single;
          expect(page.width, 200);
          expect(page.height, 300);
          expect(
            (await page.loadText())!.fullText,
            contains('Native PDF proof'),
          );
          final image = await page.render(
            width: 200,
            height: 300,
            fullWidth: 200,
            fullHeight: 300,
            backgroundColor: 0xffffffff,
          );
          expect(image, isNotNull);
          try {
            expect(image!.width, 200);
            expect(image.height, 300);
            expect(image.pixels.length, 200 * 300 * 4);
            expect(image.pixels.any((value) => value < 100), isTrue);
          } finally {
            image?.dispose();
          }
        } finally {
          await document.dispose();
        }
      } finally {
        Pdfrx.cacheDirectoryPath = null;
        await directory.delete(recursive: true);
      }
    },
  );
}
