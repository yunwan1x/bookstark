import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bookstark_flutter/widgets/native_image.dart';
import 'package:bookstark_flutter/widgets/attachment_image.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

class SvgMedia extends AttachmentRepository {
  @override
  Future<Uint8List> read(
    Uri uri, {
    int maxBytes = 64 * 1024 * 1024,
  }) async => Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="100" height="50" fill="blue"/></svg>',
    ),
  );
  @override
  bool owns(Uri uri) => true;
  @override
  Future<Attachment> add(
    dynamic file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async => throw UnimplementedError();
}

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<Uint8List> png() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 20, 10),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(20, 10);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets(
    'animated GIF renders distinct native frames rather than a static first frame',
    (tester) async {
      // Two synthetic red/blue 16x8 frames, generated with FFmpeg lavfi; no user data.
      final bytes = base64Decode(
        'R0lGODlhEAAIAPcfMQAAACQAAEgAAGwAAJAAALQAANgAAPwAAAAkACQkAEgkAGwkAJAkALQkANgkAPwkAABIACRIAEhIAGxIAJBIALRIANhIAPxIAABsACRsAEhsAGxsAJBsALRsANhsAPxsAACQACSQAEiQAGyQAJCQALSQANiQAPyQAAC0ACS0AEi0AGy0AJC0ALS0ANi0APy0AADYACTYAEjYAGzYAJDYALTYANjYAPzYAAD8ACT8AEj8AGz8AJD8ALT8ANj8APz8AAAAVSQAVUgAVWwAVZAAVbQAVdgAVfwAVQAkVSQkVUgkVWwkVZAkVbQkVdgkVfwkVQBIVSRIVUhIVWxIVZBIVbRIVdhIVfxIVQBsVSRsVUhsVWxsVZBsVbRsVdhsVfxsVQCQVSSQVUiQVWyQVZCQVbSQVdiQVfyQVQC0VSS0VUi0VWy0VZC0VbS0Vdi0Vfy0VQDYVSTYVUjYVWzYVZDYVbTYVdjYVfzYVQD8VST8VUj8VWz8VZD8VbT8Vdj8Vfz8VQAAqiQAqkgAqmwAqpAAqrQAqtgAqvwAqgAkqiQkqkgkqmwkqpAkqrQkqtgkqvwkqgBIqiRIqkhIqmxIqpBIqrRIqthIqvxIqgBsqiRsqkhsqmxsqpBsqrRsqthsqvxsqgCQqiSQqkiQqmyQqpCQqrSQqtiQqvyQqgC0qiS0qki0qmy0qpC0qrS0qti0qvy0qgDYqiTYqkjYqmzYqpDYqrTYqtjYqvzYqgD8qiT8qkj8qmz8qpD8qrT8qtj8qvz8qgAA/yQA/0gA/2wA/5AA/7QA/9gA//wA/wAk/yQk/0gk/2wk/5Ak/7Qk/9gk//wk/wBI/yRI/0hI/2xI/5BI/7RI/9hI//xI/wBs/yRs/0hs/2xs/5Bs/7Rs/9hs//xs/wCQ/ySQ/0iQ/2yQ/5CQ/7SQ/9iQ//yQ/wC0/yS0/0i0/2y0/5C0/7S0/9i0//y0/wDY/yTY/0jY/2zY/5DY/7TY/9jY//zY/wD8/yT8/0j8/2z8/5D8/7T8/9j8//z8/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQEFAAfACwAAAAAEAAIAAAIGgAPCBxIsKDBgwgTDjRwkKHChxAjQnRYkGJAACH5BAUUAAAALAAAAAAQAAgAAAgaAAEBG0gQmMCCCBMqXMiwIcODCCE6nEhxYkAAOw==',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NativeImage(bytes: bytes, label: 'Animated GIF'),
        ),
      );
      final colors = <String>{};
      for (var n = 0; n < 16; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final raw = find.byType(RawImage);
        if (raw.evaluate().isNotEmpty) {
          final image = tester.widget<RawImage>(raw.first).image;
          if (image != null) {
            final data = await tester.runAsync(() => image.toByteData());
            if (data != null) {
              colors.add(data.buffer.asUint8List().take(4).join(','));
            }
          }
        }
      }
      expect(colors.length, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'raster decode preserves aspect ratio and clamps requested decode resolution',
    (tester) async {
      final bytes = await tester.runAsync(png);
      await tester.pumpWidget(
        MaterialApp(
          home: NativeImage(bytes: bytes!, label: '真实图片', maxDecodeSide: 10),
        ),
      );
      await drain(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.semanticLabel, '真实图片');
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      expect(resize.width, 10);
      expect(resize.height, 5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'SVG renders natively and attachment preview reuses the same renderer',
    (tester) async {
      final repo = SvgMedia();
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentImage(
              repository: repo,
              uri: Uri.parse(
                'bookstark-attachment:///0123456789abcdef0123456789abcdef/diagram.svg',
              ),
              label: 'SVG流程',
            ),
          ),
        ),
      );
      await drain(tester);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byType(InkWell).first);
      await drain(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unsupported external SVG fails visibly before a renderer can fetch it',
    (tester) async {
      final bytes = Uint8List.fromList(
        utf8.encode(
          '<svg><image href="https://other.test/private.png"/></svg>',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NativeImage(bytes: bytes, label: '外部SVG'),
        ),
      );
      await drain(tester);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.textContaining('图片预览失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
