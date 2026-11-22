import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/drive_download.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/file_export.dart';
import 'package:bookstark_flutter/features/drive/file_preview_page.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'package:bookstark_flutter/widgets/native_image.dart';
import '../tool/fixtures/drive.dart';

Future<void> drainFile(WidgetTester tester) async {
  for (var n = 0; n < 24; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitForFileWidget(WidgetTester tester, Finder finder) async {
  final timer = Stopwatch()..start();
  while (finder.evaluate().isEmpty &&
      timer.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    finder,
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join(' | '),
  );
}

Future<void> waitForFileAction(
  WidgetTester tester,
  bool Function() complete,
) async {
  final timer = Stopwatch()..start();
  while (!complete() && timer.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(complete(), isTrue, reason: 'Actual file action did not complete');
}

Future<void> waitForFileCleanup(
  WidgetTester tester,
  Directory directory,
) async {
  final timer = Stopwatch()..start();
  var empty = false;
  while (!empty && timer.elapsed < const Duration(seconds: 5)) {
    final files = await tester.runAsync(
      () => directory
          .list(recursive: true)
          .where((entry) => entry is File)
          .toList(),
    );
    empty = files != null && files.isEmpty;
    if (!empty) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  expect(empty, isTrue, reason: 'Disposed preview cache did not close');
}

Future<void> tapFile(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await drainFile(tester);
}

void main() {
  late Directory directory;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await root.create(recursive: true);
    directory = await root.createTemp('file-preview-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Widget preview(
    DriveFixture repo,
    DriveNode file, {
    Future<FileExportOutcome> Function(DriveDownloadedFile)? save,
    Future<void> Function(DriveDownloadedFile)? share,
    bool failFirst = false,
    double scale = 1,
  }) {
    var attempts = 0;
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FilePreviewPage(
        repository: repo,
        file: file,
        english: true,
        save: save,
        share: share,
        download: (cancel, progress) async {
          attempts++;
          if (failFirst && attempts == 1) {
            throw StateError('fixture read failure');
          }
          return downloadDriveFile(
            repo,
            file,
            cancellation: cancel,
            onReceived: progress,
            cacheDirectory: () async => directory,
          );
        },
      ),
    );
  }

  testWidgets(
    'Markdown file uses the shared native renderer and saving cancellation produces no success',
    (tester) async {
      final repo = DriveFixture(), node = repo.nodes['阅读清单.md']!;
      var saved = false, shares = 0, saveCalls = 0;
      await tester.pumpWidget(
        preview(
          repo,
          node,
          save: (file) async {
            expect(file.node.name, node.name);
            expect(file.hash, node.etag);
            saveCalls++;
            return saved
                ? FileExportOutcome.saved
                : FileExportOutcome.cancelled;
          },
          share: (file) async {
            expect(await file.file.readAsBytes(), repo.data[node.path]);
            shares++;
          },
        ),
      );
      await waitForFileWidget(tester, find.byType(BookstarkMarkdown));
      expect(find.byType(BookstarkMarkdown), findsOneWidget);
      expect(find.text('本周阅读清单'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Save to device'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tapFile(tester, find.text('Save to device'));
      await waitForFileAction(tester, () => saveCalls == 1);
      expect(find.text('Saved to the selected location'), findsNothing);
      saved = true;
      await tapFile(tester, find.text('Save to device'));
      await waitForFileWidget(
        tester,
        find.text('Saved to the selected location'),
      );
      expect(find.text('Saved to the selected location'), findsOneWidget);
      await tapFile(tester, find.widgetWithText(OutlinedButton, 'Share file'));
      await waitForFileAction(tester, () => shares == 1);
      expect(shares, 1);
      expect(repo.saves, 0);
      expect(repo.uploads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await waitForFileCleanup(tester, directory);
      expect(
        await tester.runAsync(
          () => directory
              .list(recursive: true)
              .where((entry) => entry is File)
              .toList(),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'SVG preview is native, retains true public state and actual bytes for sharing',
    (tester) async {
      final repo = DriveFixture(), node = repo.nodes['插图/知识框架.svg']!;
      var shares = 0;
      await tester.pumpWidget(
        preview(
          repo,
          node,
          share: (file) async {
            expect(await file.file.readAsBytes(), repo.data[node.path]);
            shares++;
          },
        ),
      );
      await waitForFileWidget(tester, find.byType(NativeImage));
      expect(find.byType(NativeImage), findsOneWidget);
      expect(find.text('Public file'), findsOneWidget);
      await tapFile(tester, find.byTooltip('Share file'));
      await waitForFileAction(tester, () => shares == 1);
      expect(shares, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await waitForFileCleanup(tester, directory);
    },
  );
  testWidgets(
    'read failure retries actual source and does not claim the missing cache is ready',
    (tester) async {
      final repo = DriveFixture(), node = repo.nodes['阅读清单.md']!;
      await tester.pumpWidget(preview(repo, node, failFirst: true));
      await waitForFileWidget(tester, find.text('Retry loading'));
      expect(find.text('Retry loading'), findsOneWidget);
      expect(find.text('Save to device'), findsNothing);
      await tapFile(tester, find.text('Retry loading'));
      // The retry traverses real cache create/write/flush/rename/header/read
      // operations. Fixed frame draining does not acknowledge their completion.
      await waitForFileWidget(tester, find.byType(BookstarkMarkdown));
      expect(find.byType(BookstarkMarkdown), findsOneWidget);
      expect(
        tester.widget<BookstarkMarkdown>(find.byType(BookstarkMarkdown)).data,
        DriveText.decode(node, repo.data[node.path]!).content,
      );
      expect(find.text('Save to device'), findsOneWidget);
      expect(repo.saves, 0);
      expect(repo.uploads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await waitForFileCleanup(tester, directory);
    },
  );
  testWidgets(
    'binary file is not executed as HTML and remains saveable as original bytes',
    (tester) async {
      final repo = DriveFixture(seed: false),
          node = repo.addFile('binary.html', [0, 255, 1, 2], 'text/html');
      var saved = false;
      await tester.pumpWidget(
        preview(
          repo,
          node,
          save: (file) async {
            expect(await file.file.readAsBytes(), [0, 255, 1, 2]);
            saved = true;
            return FileExportOutcome.saved;
          },
        ),
      );
      await waitForFileWidget(
        tester,
        find.textContaining('cannot be previewed'),
      );
      expect(find.byType(BookstarkMarkdown), findsNothing);
      expect(find.byType(NativeImage), findsNothing);
      expect(find.textContaining('cannot be previewed'), findsOneWidget);
      await tapFile(tester, find.text('Save to device'));
      await waitForFileAction(tester, () => saved);
      expect(saved, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await waitForFileCleanup(tester, directory);
    },
  );
  testWidgets(
    'file info and actions fit 320dp with double text and stay scrollable',
    (tester) async {
      final repo = DriveFixture();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final child = preview(repo, repo.nodes['阅读清单.md']!, scale: 2);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child,
        ),
      );
      await waitForFileWidget(tester, find.byType(BookstarkMarkdown));
      await tester.scrollUntilVisible(
        find.text('Save to device'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await waitForFileCleanup(tester, directory);
    },
  );
}
