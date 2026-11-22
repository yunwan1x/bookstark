import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_presentation_image_references.dart';

const image =
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/actual.png';
ComplexEditorDocument source(
  List<Map<String, Object?>> slides, {
  Map<String, Object?> extra = const {},
}) => ComplexEditorDocument.parse(
  ComplexEditorKind.presentation,
  jsonEncode({'width': 1000, 'height': 562.5, 'slides': slides, ...extra}),
);
Map<String, Object?> slide(List<Object?> elements, {Object? background}) => {
  'id': 'slide-actual',
  'elements': elements,
  if (background != null) 'background': background,
};
void main() {
  test(
    'actual element and background src grant one exact UUID, metadata none',
    () {
      final document = source(
        [
          slide(
            [
              {'id': 'image-1', 'type': 'image', 'src': image},
              {'id': 'text-1', 'type': 'text', 'content': image},
              {'id': 'audio-1', 'type': 'audio', 'src': image},
            ],
            background: {
              'type': 'image',
              'image': {'src': image, 'size': 'cover'},
            },
          ),
        ],
        extra: {
          'unknown': {'type': 'image', 'src': image},
        },
      );
      final parsed = LocalPresentationImageReferences.capture(document);
      expect(parsed.complete, isTrue);
      expect(parsed.references.length, 1);
      expect(parsed.attachmentUris, {Uri.parse(image)});
      expect(parsed.sourceDigest, document.digest);
      expect(jsonDecode(document.source)['unknown'], {
        'type': 'image',
        'src': image,
      });
      expect(() => parsed.references.clear(), throwsUnsupportedError);
    },
  );
  test(
    '33 occurrences of one exact URI do not consume 33 separate resources',
    () {
      final parsed = LocalPresentationImageReferences.capture(
        source([
          slide(
            List.generate(
              33,
              (i) => {'id': 'image-$i', 'type': 'image', 'src': image},
            ),
          ),
        ]),
      );
      expect(parsed.references.length, 1);
      expect(parsed.complete, isTrue);
    },
  );
  test(
    'prose, notes, arbitrary group children and video do not acquire resources',
    () {
      final parsed = LocalPresentationImageReferences.capture(
        source(
          [
            slide([
              {'id': 'text-1', 'type': 'text', 'content': image},
              {'id': 'video-1', 'type': 'video', 'src': image},
              {
                'id': 'group-1',
                'type': 'group',
                'elements': [
                  {'type': 'image', 'src': image},
                ],
              },
            ]),
          ],
          extra: {'notes': image},
        ),
      );
      expect(parsed.references, isEmpty);
      expect(parsed.attachmentUris, isEmpty);
    },
  );
  test(
    'external src unavailable while complete original source remains unchanged',
    () {
      final document = source(
        [
          slide([
            {
              'id': 'image-1',
              'type': 'image',
              'src': 'https://outside.invalid/denied.png',
            },
          ]),
        ],
        extra: {'unknown': 'retain'},
      );
      final before = document.source;
      final parsed = LocalPresentationImageReferences.capture(document);
      expect(parsed.complete, isFalse);
      expect(parsed.references, isEmpty);
      expect(parsed.unavailableSourceKeys, isNotEmpty);
      expect(document.source, before);
    },
  );
  test(
    'missing actual image src is unavailable, not an empty successful image',
    () {
      final parsed = LocalPresentationImageReferences.capture(
        source([
          slide([
            {'id': 'bad', 'type': 'image'},
          ]),
        ]),
      );
      expect(parsed.complete, isFalse);
      expect(parsed.references, isEmpty);
    },
  );
  test(
    'more than 32 distinct actual sources fails discovery without normalization',
    () {
      final document = source([
        slide(
          List.generate(
            33,
            (i) => {
              'id': 'image-$i',
              'type': 'image',
              'src':
                  'bookstark-attachment:///' +
                  i.toRadixString(16).padLeft(32, '0') +
                  '/a.png',
            },
          ),
        ),
      ]);
      final before = document.source;
      expect(
        () => LocalPresentationImageReferences.capture(document),
        throwsFormatException,
      );
      expect(document.source, before);
    },
  );
  test('another kind cannot become a presentation image inventory', () {
    expect(
      () => LocalPresentationImageReferences.capture(
        ComplexEditorDocument.parse(ComplexEditorKind.html, '<img src="a">'),
      ),
      throwsFormatException,
    );
  });
}
