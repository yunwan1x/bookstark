import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_mindmap_image_references.dart';

const _uri =
    'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/actual.png';
ComplexEditorDocument source(Map<String, Object?> value) =>
    ComplexEditorDocument.parse(ComplexEditorKind.mindmap, jsonEncode(value));
void main() {
  test(
    'only real MindElixir recursive node image.url grants raster authority',
    () {
      final document = source({
        'nodeData': {
          'id': 'root',
          'topic': 'Root',
          'image': {'url': _uri, 'width': 1, 'height': 1},
          'children': [
            {
              'id': 'child',
              'topic': 'text ' + _uri,
              'image': {'url': _uri, 'width': 1, 'height': 1},
            },
          ],
        },
        'unknown': {
          'image': {
            'url':
                'bookstark-attachment:///bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/hidden.png',
          },
        },
      });
      final found = LocalMindmapImageReferences.capture(document);
      expect(found.sourceDigest, document.digest);
      expect(found.references, {Uri.parse(_uri)});
      expect(document.source, contains('hidden.png'));
    },
  );
  test(
    'network and topic references grant nothing and original bytes remain exact',
    () {
      const raw =
          '\r\n {"nodeData":{"id":"root","topic":"' +
          _uri +
          '","image":{"url":"https://outside.test/a.png","width":1,"height":1}}}';
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.mindmap,
        raw,
      );
      expect(LocalMindmapImageReferences.capture(document).references, isEmpty);
      expect(document.source, raw);
    },
  );
  test('reference budget is fail-closed without replacing complete source', () {
    final document = source({
      'nodeData': {
        'id': 'root',
        'topic': 'Root',
        'children': [
          for (var i = 0; i < 33; i++)
            {
              'id': 'node-' + i.toString(),
              'topic': 'Node',
              'image': {
                'url':
                    'bookstark-attachment:///' +
                    i.toRadixString(16).padLeft(32, '0') +
                    '/a.png',
                'width': 1,
                'height': 1,
              },
            },
        ],
      },
    });
    expect(
      () => LocalMindmapImageReferences.capture(document),
      throwsFormatException,
    );
    final closed = LocalMindmapImageReferences.unavailable(document);
    expect(closed.references, isEmpty);
    expect(closed.sourceDigest, document.digest);
    expect(document.source, contains('node-32'));
  });
}
