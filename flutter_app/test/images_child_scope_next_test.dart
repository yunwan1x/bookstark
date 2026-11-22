import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';
import 'package:bookstark_flutter/features/images/image_library_owner.dart';
import 'package:bookstark_flutter/features/images/image_preview_page.dart';
import 'package:bookstark_flutter/features/images/image_upload_page.dart';
import '../tool/fixtures/images.dart';

Uint8List imageBytes() => Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
  ),
);

class ChildLibrary extends ImagesFixture {
  Completer<Uint8List>? readGate;
  @override
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  }) =>
      readGate?.future ?? super.bytes(uri, maxBytes: maxBytes, reload: reload);
}

class LocalShareLibrary extends ChildLibrary implements LocalImagesRepository {
  final shareGate = Completer<XFile>();
  int localShareCalls = 0;
  @override
  bool get publicLinks => false;
  @override
  Future<XFile> localShareFile(ManagedImage item) {
    localShareCalls++;
    return shareGate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ManagedImage add(ImagesFixture repository) {
  final ref = repository.recordPayload(
    ImageUploadPayload.fromBytes(
      name: 'private.svg',
      bytes: imageBytes(),
      category: ImageCategory.note,
    ),
  );
  return repository.records[ref.id]!;
}

Future<void> click(WidgetTester tester, String label) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    // Both production child pages use a lazy ListView. Build the actual action
    // by scrolling its outer list before trying to resolve an element.
    final list = find.byType(ListView).first;
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets(
    'retiring preview shields image and ignores prior delete confirmation',
    (tester) async {
      final repo = ChildLibrary(), owner = ImageLibraryOwner();
      final image = add(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewPage(
            repository: repo,
            image: image,
            owner: owner,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await click(tester, 'Delete image');
      final drained = owner.retireAndDrain();
      await tester.pump();
      await click(tester, 'Delete');
      await tester.pumpAndSettle();
      await drained;
      expect(repo.removeCalls, 0);
      expect(find.text('private.svg'), findsNothing);
      expect(find.textContaining('This preview is closed.'), findsOneWidget);
    },
  );
  testWidgets('preview leave drains only pending bytes, not route lifetime', (
    tester,
  ) async {
    final repo = ChildLibrary()..readGate = Completer<Uint8List>();
    final owner = ImageLibraryOwner(), image = add(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          repository: repo,
          image: image,
          owner: owner,
          english: true,
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var finished = false;
    final drain = owner.retireAndDrain().then((_) {
      finished = true;
    });
    await tester.pump();
    expect(finished, isFalse);
    repo.readGate!.complete(imageBytes());
    await tester.pump();
    await drain;
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'delayed file picker cannot enqueue files after scope retirement',
    (tester) async {
      final repo = ChildLibrary(), owner = ImageLibraryOwner();
      final picker = Completer<List<XFile>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ImageUploadPage(
            repository: repo,
            owner: owner,
            english: true,
            pickFiles: () => picker.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Exact visible label is supplied by the existing upload page.
      final button = find.widgetWithIcon(
        OutlinedButton,
        Icons.add_photo_alternate_outlined,
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      final drain = owner.retireAndDrain();
      picker.complete([
        XFile.fromData(
          imageBytes(),
          name: 'private.svg',
          mimeType: 'image/svg+xml',
        ),
      ]);
      await tester.pumpAndSettle();
      await drain;
      expect(repo.hashCalls, 0);
      expect(repo.uploadCalls, 0);
      expect(find.textContaining('Upload queue closed.'), findsOneWidget);
    },
  );
  testWidgets(
    'local share keeps actual LocalImagesRepository branch and drains file read',
    (tester) async {
      final repo = LocalShareLibrary(), owner = ImageLibraryOwner();
      final image = add(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewPage(
            repository: repo,
            image: image,
            owner: owner,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share image file'));
      await tester.pump();
      expect(repo.localShareCalls, 1);
      var finished = false;
      final drain = owner.retireAndDrain().then((_) {
        finished = true;
      });
      await tester.pump();
      expect(finished, isFalse);
      repo.shareGate.complete(
        XFile.fromData(imageBytes(), name: 'private.svg'),
      );
      await tester.pumpAndSettle();
      await drain;
      expect(finished, isTrue);
      // No platform share is invoked after retirement; no plugin mock is needed.
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late upload progress and receipt stay hidden after retirement', (
    tester,
  ) async {
    final repo = ChildLibrary(), owner = ImageLibraryOwner();
    final receipt = Completer<UploadedImageReference>();
    void Function(int, int)? progress;
    ImageUploadPayload? submitted;
    repo.uploadOverride = (payload, cancellation, onSent) {
      submitted = payload;
      progress = onSent;
      return receipt.future;
    };
    await tester.pumpWidget(
      MaterialApp(
        home: ImageUploadPage(
          repository: repo,
          owner: owner,
          english: true,
          initialFiles: [
            XFile.fromData(
              imageBytes(),
              name: 'private.svg',
              mimeType: 'image/svg+xml',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await click(tester, 'Process 1 items');
    // Run preparation/hash lookup microtasks without waiting on the receipt.
    for (var n = 0; n < 8 && submitted == null; n++) {
      await tester.pump();
    }
    expect(submitted, isNotNull);
    var drained = false;
    final drain = owner.retireAndDrain().then((_) {
      drained = true;
    });
    await tester.pump();
    expect(drained, isFalse);
    progress?.call(100, 100);
    receipt.complete(repo.recordPayload(submitted!));
    await tester.pumpAndSettle();
    await drain;
    expect(find.textContaining('Upload queue closed.'), findsOneWidget);
    expect(find.text('private.svg'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
