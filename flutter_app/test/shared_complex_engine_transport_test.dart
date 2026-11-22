import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';

void main() {
  test(
    'explicit shared complex option loads editable exact source and grants only source I/O',
    () async {
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '\ufeff<p>共享😀</p>\r\n',
      );
      var received = 0;
      Map<Object?, Object?>? options;
      final chunks = <int>[];
      final transport = ComplexEditorTransport((name, args) async {
        switch (name) {
          case 'beginLoad':
            options = Map<Object?, Object?>.from(args[3] as Map);
            return {
              'id': 'load',
              'bytes': document.byteLength,
              'chunkBytes': 262144,
            };
          case 'appendLoad':
            final bytes = base64Decode(args[2] as String);
            chunks.addAll(bytes);
            received += bytes.length;
            return {'id': 'load', 'index': args[1], 'received': received};
          case 'commitLoad':
            return {
              'ready': true,
              'kind': 'html',
              'readOnly': false,
              'generation': 1,
            };
          case 'sourceIoIdentity':
            return {'lease': 'real-native-lease-fixture', 'generation': 1};
          default:
            throw StateError('Unexpected command');
        }
      });
      await transport.load(
        document,
        readOnly: false,
        sharedComplexEditing: true,
        publicResourceRoot: Uri.parse('https://example.test/mount'),
      );
      // Dart utf8.decode consumes a BOM; verify the transmitted bytes first,
      // then use the production preserving decoder for the exact source assertion.
      expect(chunks, orderedEquals(utf8.encode(document.source)));
      expect(chunks.take(3), orderedEquals([0xef, 0xbb, 0xbf]));
      expect(
        ComplexEditorDocument.fromBytes(document.kind, chunks).source,
        document.source,
      );
      expect(options!['sharedComplexEditing'], true);
      expect(options!['publicComplexReadOnly'], isNull);
      expect(options!['sharedMarkdownEditing'], isNull);
      expect((await transport.sourceIoIdentity())['generation'], 1);
      expect(
        transport.readingBinding,
        isNull,
      ); // Never counterfeit a book/doc reading identity.
    },
  );
  test(
    'shared mode refuses missing root, Markdown and mixed readonly capability before native',
    () async {
      var calls = 0;
      final transport = ComplexEditorTransport((_, _) async {
        calls++;
        return null;
      });
      final html = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '<p>safe</p>',
      );
      await expectLater(
        transport.load(html, readOnly: false, sharedComplexEditing: true),
        throwsArgumentError,
      );
      await expectLater(
        transport.load(
          html,
          readOnly: false,
          sharedComplexEditing: true,
          publicComplexReadOnly: true,
          publicResourceRoot: Uri.parse('https://example.test'),
        ),
        throwsArgumentError,
      );
      final md = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        '# safe',
      );
      await expectLater(
        transport.load(
          md,
          readOnly: false,
          sharedComplexEditing: true,
          publicResourceRoot: Uri.parse('https://example.test'),
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );
}
