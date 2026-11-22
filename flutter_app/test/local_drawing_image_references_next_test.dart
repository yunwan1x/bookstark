import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_drawing_image_references.dart';

const uri =
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/actual.png';
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGOQPboYiBggFAAoggYVl8fDYAAAAABJRU5ErkJggg==';
ComplexEditorDocument drawing(Object value, {bool bom = false}) =>
    ComplexEditorDocument.parse(
      ComplexEditorKind.drawing,
      (bom ? '\uFEFF' : '') + jsonEncode(value),
    );
Map<String, Object?> graph({
  Object? value = uri,
  bool deleted = false,
  Map<String, Object?> extra = const {},
}) => {
  'elements': [
    {
      'id': 'actual-element',
      'type': 'image',
      'fileId': 'actual-file',
      'isDeleted': deleted,
    },
  ],
  'files': {
    'actual-file': {'dataURL': value, 'mimeType': 'image/png'},
  },
  'customData': extra,
};
void main() {
  test(
    'only live real image fileId grants its exact UUID; unknown metadata inert',
    () {
      final doc = drawing(
        graph(
          extra: {
            'inert':
                'bookstark-attachment:///bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/secret.png',
          },
        ),
      );
      final refs = LocalDrawingImageReferences.capture(doc);
      expect(refs.complete, isTrue);
      expect(refs.sourceDigest, doc.digest);
      expect(refs.attachmentUris, {Uri.parse(uri)});
      expect(refs.files.keys, ['actual-file']);
      expect(
        refs.files['actual-file']!.resourceId,
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
    },
  );
  test('deleted element and unused files do not authorize a read', () {
    final refs = LocalDrawingImageReferences.capture(
      drawing(graph(deleted: true)),
    );
    expect(refs.complete, isTrue);
    expect(refs.files, isEmpty);
  });
  test('valid whitespace/source/unknown fields remain byte exact', () {
    final doc = ComplexEditorDocument.parse(
      ComplexEditorKind.drawing,
      '\r\n  ' +
          jsonEncode(
            graph(
              extra: {
                'unknown': [1, 2, 3],
              },
            ),
          ) +
          '\r\n',
    );
    final before = doc.source;
    final digest = doc.digest;
    final refs = LocalDrawingImageReferences.capture(doc);
    expect(refs.complete, isTrue);
    expect(doc.source, before);
    expect(doc.source.startsWith('\r\n  '), isTrue);
    expect(doc.digest, digest);
  });
  test('missing file and HTTP source remain explicit blocked full source', () {
    final doc = drawing(
      graph(value: 'https://not-authorized.invalid/image.png'),
    );
    final before = doc.source;
    final refs = LocalDrawingImageReferences.capture(doc);
    expect(refs.complete, isFalse);
    expect(refs.files, isEmpty);
    expect(refs.unavailableFileIds, {'actual-file'});
    expect(doc.source, before);
  });
  test(
    'bounded actual inline raster retained without filesystem authority',
    () {
      final refs = LocalDrawingImageReferences.capture(
        drawing(graph(value: 'data:image/png;base64,' + png)),
      );
      expect(refs.complete, isTrue);
      expect(refs.attachmentUris, isEmpty);
      expect(refs.files['actual-file']!.inlineBytes, base64Decode(png));
      expect(refs.files['actual-file']!.inlineMime, 'image/png');
    },
  );
  test('inline MIME lie is unavailable; no source rewriting', () {
    final doc = drawing(graph(value: 'data:image/jpeg;base64,' + png));
    final before = doc.source;
    expect(LocalDrawingImageReferences.capture(doc).complete, isFalse);
    expect(doc.source, before);
  });
  test('33 distinct rendered file IDs exceed authority budget', () {
    final value = {
      'elements': List.generate(
        33,
        (i) => {'id': 'e$i', 'type': 'image', 'fileId': 'f$i'},
      ),
      'files': {
        for (var i = 0; i < 33; i++) 'f$i': {'dataURL': uri},
      },
    };
    expect(
      () => LocalDrawingImageReferences.capture(drawing(value)),
      throwsFormatException,
    );
  });
  test(
    'legacy array text source remains readable with no fake image permissions',
    () {
      final doc = drawing([
        {'id': 'text', 'type': 'text', 'text': 'Original'},
      ]);
      final before = doc.source;
      final refs = LocalDrawingImageReferences.capture(doc);
      expect(refs.complete, isTrue);
      expect(refs.files, isEmpty);
      expect(doc.source, before);
    },
  );
  test('other kind cannot acquire drawing source authority', () {
    final doc = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      'plain text',
    );
    expect(
      () => LocalDrawingImageReferences.capture(doc),
      throwsFormatException,
    );
  });
}
