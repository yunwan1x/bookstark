import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_richdoc_image_references.dart';

ComplexEditorDocument source(
  Map<String, Object?> data, {
  Map<String, Object?> extra = const {},
}) => ComplexEditorDocument.parse(
  ComplexEditorKind.richdoc,
  jsonEncode({
    'schema': 'bookstark-richdoc',
    'schema_version': 1,
    'data': data,
    ...extra,
  }),
);
void main() {
  const image =
      'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.png';
  test(
    'actual image elements in zones/table/group; prose and metadata grant none',
    () {
      final document = source(
        {
          'main': [
            {'type': 'text', 'value': image},
            {'type': 'image', 'value': image},
            {
              'type': 'table',
              'trList': [
                {
                  'tdList': [
                    {
                      'value': [
                        {'type': 'image', 'value': image},
                      ],
                    },
                  ],
                },
              ],
            },
            {
              'type': 'hyperlink',
              'valueList': [
                {'type': 'image', 'value': image},
              ],
            },
          ],
          'header': [
            {'type': 'image', 'value': image},
          ],
          'footer': [],
        },
        extra: {
          'unknown': {'type': 'image', 'value': image},
        },
      );
      final before = document.source;
      final result = LocalRichdocImageReferences.capture(document);
      expect(result.references, {Uri.parse(image)});
      expect(result.sourceDigest, document.digest);
      expect(document.source, before);
      expect(() => result.references.clear(), throwsUnsupportedError);
      final unrelated = source(
        {
          'main': [
            {'value': image},
          ],
        },
        extra: {
          'unknown': {'type': 'image', 'value': image},
        },
      );
      expect(
        LocalRichdocImageReferences.capture(unrelated).references,
        isEmpty,
      );
    },
  );
  test('malformed local image URI and 33 actual image refs fail closed', () {
    expect(
      () => LocalRichdocImageReferences.capture(
        source({
          'main': [
            {'type': 'image', 'value': '$image?x=1'},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalRichdocImageReferences.capture(
        source({
          'main': List.generate(
            33,
            (i) => {
              'type': 'image',
              'value':
                  'bookstark-attachment:///${i.toRadixString(16).padLeft(32, '0')}/a.png',
            },
          ),
        }),
      ),
      throwsFormatException,
    );
  });
  test(
    'remote URLs and arbitrary kind cannot activate local attachment reader',
    () {
      expect(
        LocalRichdocImageReferences.capture(
          source({
            'main': [
              {'type': 'image', 'value': 'https://example.com/image.png'},
            ],
          }),
        ).references,
        isEmpty,
      );
      expect(
        () => LocalRichdocImageReferences.capture(
          ComplexEditorDocument.parse(ComplexEditorKind.html, '<img src="a">'),
        ),
        throwsFormatException,
      );
    },
  );
}
