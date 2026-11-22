import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/features/drive/file_public_page.dart';
import '../tool/fixtures/drive.dart';

class LostPublic extends DriveFixture {
  bool lost = true;
  @override
  Future<Uri> publish(
    DriveNode file,
    String path, {
    AttachmentCancellation? cancellation,
  }) async {
    final result = await super.publish(file, path, cancellation: cancellation);
    if (lost) {
      lost = false;
      throw const ApiFailure(502, 'Acknowledgement lost');
    }
    return result;
  }
}

class ReadFailureAfterWrite extends DriveFixture {
  bool fail = true;
  @override
  Future<DriveNode?> lookup(
    String path, {
    AttachmentCancellation? cancellation,
  }) async {
    if (publishes > 0 && fail) {
      fail = false;
      throw const ApiFailure(403, 'Read permission temporarily changed');
    }
    return super.lookup(path, cancellation: cancellation);
  }
}

Future<void> drainPublic(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> tapPublic(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await drainPublic(tester);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    DriveFixture repo, {
    String path = '阅读清单.md',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: FilePublicPage(
          repository: repo,
          file: repo.nodes[path]!,
          english: true,
        ),
      ),
    );
    await drainPublic(tester);
  }

  testWidgets(
    'opening is read-only and explicit publish copies only a confirmed server public address',
    (tester) async {
      final repo = DriveFixture();
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await show(tester, repo);
      expect(repo.publishes, 0);
      expect(find.text('Copy public address'), findsNothing);
      await tester.enterText(find.byType(TextField), 'diagrams/reading% ?.md');
      await tapPublic(tester, find.text('Confirm publish'));
      expect(repo.publishes, 1);
      expect(repo.nodes['阅读清单.md']!.publicPath, 'diagrams/reading% ?.md');
      await tester.scrollUntilVisible(
        find.text('Copy public address'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tapPublic(tester, find.text('Copy public address'));
      expect(
        copied,
        'https://fixture.invalid/dav-public/reader/diagrams/reading%25%20%3F.md',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown publication is verified read-only and never automatically resubmitted',
    (tester) async {
      final repo = LostPublic();
      await show(tester, repo);
      await tapPublic(tester, find.text('Confirm publish'));
      expect(repo.publishes, 1);
      expect(find.text('Verify last operation first'), findsOneWidget);
      await tapPublic(tester, find.text('Verify last operation first'));
      expect(repo.publishes, 1);
      expect(find.text('Copy public address'), findsOneWidget);
      expect(find.text('Submit again explicitly'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'known write acknowledgement followed by read denial still requires verification',
    (tester) async {
      final repo = ReadFailureAfterWrite();
      await show(tester, repo);
      await tapPublic(tester, find.text('Confirm publish'));
      expect(repo.publishes, 1);
      expect(find.text('Verify last operation first'), findsOneWidget);
      await tapPublic(tester, find.text('Verify last operation first'));
      expect(repo.publishes, 1);
      expect(find.text('Copy public address'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'public paths reject hidden and reserved components before sending any mutation',
    (tester) async {
      final repo = DriveFixture();
      await show(tester, repo);
      for (final path in [
        '.hidden/a',
        'a/.hidden',
        'dav/a',
        'a/dav-public/b',
        'a/../b',
      ]) {
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), path);
        await tapPublic(tester, find.text('Confirm publish'));
      }
      expect(repo.publishes, 0);
      expect(repo.nodes['阅读清单.md']!.isPublic, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unpublish needs confirmation and refreshes the actual private state',
    (tester) async {
      final repo = DriveFixture();
      await show(tester, repo, path: '插图/知识框架.svg');
      await tester.scrollUntilVisible(
        find.text('Unpublish'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tapPublic(tester, find.text('Unpublish'));
      expect(find.text('Unpublish file?'), findsOneWidget);
      await tapPublic(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Confirm'),
        ),
      );
      expect(repo.nodes['插图/知识框架.svg']!.isPublic, isFalse);
      expect(find.text('Copy public address'), findsNothing);
      expect(find.text('Confirm publish'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('public settings remain scrollable at 320dp and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, DriveFixture(), scale: 2);
    await tester.scrollUntilVisible(
      find.text('Confirm publish'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
