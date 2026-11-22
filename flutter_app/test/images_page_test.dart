import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/features/images/images_page.dart';
import 'package:bookstark_flutter/features/images/image_preview_page.dart';
import '../tool/fixtures/images.dart';

Uint8List svg(int value) => Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="blue"/><title>$value</title></svg>',
  ),
);

class Library extends ImagesFixture {
  final denied = <int>{}, uncertain = <int>{};
  int verifies = 0;
  @override
  Future<ImageRemovalResult> remove(ManagedImage item) async {
    if (denied.contains(item.id)) {
      removeCalls++;
      throw const ApiFailure(403, 'Not your image');
    }
    if (uncertain.remove(item.id)) {
      await super.remove(item);
      throw const ApiFailure(502, 'Reply lost');
    }
    return super.remove(item);
  }

  @override
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item) {
    verifies++;
    return super.verifyRemoval(item);
  }
}

Library library(int count) {
  final repo = Library();
  for (var n = 0; n < count; n++) {
    repo.recordPayload(
      ImageUploadPayload.fromBytes(
        name: 'image-$n.svg',
        bytes: svg(n),
        category: n.isEven ? ImageCategory.editor : ImageCategory.note,
      ),
    );
  }
  return repo;
}

Future<void> drain(WidgetTester tester) async {
  await tester.pump();
  for (var n = 0; n < 8; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> show(WidgetTester tester, Widget page, {double scale = 1}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    ),
  );
  await drain(tester);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await drain(tester);
}

void main() {
  testWidgets(
    'gallery paginates actual IDs, filters and retains global main-file bytes',
    (tester) async {
      final repo = library(23);
      await show(tester, ImagesPage(repository: repo, english: true));
      expect(find.text('Loaded 20 / 23 images'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Load more'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Load more'));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(0);
      await drain(tester);
      expect(find.text('Loaded 23 / 23 images'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Note'));
      expect(find.text('Loaded 11 / 11 images'), findsOneWidget);
      expect(find.textContaining('Total image files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'batch deletion preserves denied selection and verifies lost acknowledgement without deleting again',
    (tester) async {
      final repo = library(3);
      repo.denied.add(101);
      repo.uncertain.add(102);
      await show(tester, ImagesPage(repository: repo, english: true));
      await tapVisible(tester, find.text('Select'));
      await tapVisible(tester, find.text('Select loaded'));
      await tapVisible(tester, find.text('Delete selected 3'));
      await tapVisible(tester, find.text('Confirm'));
      expect(repo.removeCalls, 3);
      expect(repo.records.keys, [101]);
      expect(find.text('Delete selected 1'), findsOneWidget);
      await tapVisible(tester, find.text('Verify 1 deletion results'));
      expect(repo.verifies, 1);
      expect(repo.removeCalls, 3);
      expect(find.text('Delete selected 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('changing filters asks before losing selected actual IDs', (
    tester,
  ) async {
    final repo = library(2);
    await show(tester, ImagesPage(repository: repo, english: true));
    await tapVisible(tester, find.text('Select'));
    await tapVisible(tester, find.text('Select loaded'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Note'));
    expect(find.text('Clear selection?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancel'));
    expect(find.text('Delete selected 2'), findsOneWidget);
    expect(repo.removeCalls, 0);
  });
  testWidgets('gallery fits narrow screens at double text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(
      tester,
      ImagesPage(repository: library(2), english: true),
      scale: 2,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await drain(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'preview copies escaped Markdown and shares actual original SVG bytes',
    (tester) async {
      final repo = library(1), original = svg(0);
      String? copied, name;
      Uint8List? shared;
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
      final old = repo.records.values.single;
      final item = ManagedImage(
        id: old.id,
        name: 'a[b].jpg',
        uri: old.uri,
        mime: 'image/svg+xml',
      );
      await show(
        tester,
        ImagePreviewPage(
          repository: repo,
          image: item,
          english: true,
          share: (data, file) async {
            shared = data;
            name = file;
          },
        ),
      );
      await tapVisible(tester, find.byTooltip('Share image file'));
      expect(shared, original);
      expect(name, 'a[b].svg');
      await tester.scrollUntilVisible(
        find.text('Copy Markdown'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Copy Markdown'));
      expect(copied, contains(r'a\[b\].jpg'));
      expect(copied, contains(item.uri.toString()));
      expect(repo.removeCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'export file extension follows stored bytes rather than input filename',
    () {
      expect(imageShareName('photo.jpeg', 'image/webp'), 'photo.webp');
      expect(imageShareName('photo.jpeg', 'image/jpeg'), 'photo.jpeg');
    },
  );
}
