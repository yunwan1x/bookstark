import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/markdown_creation_host.dart';

void main() {
  test(
    'invalid insertion never crosses the bridge or consumes its source snapshot',
    () async {
      final host = MarkdownCreationHost();
      var insertCalls = 0;
      final transport = ComplexEditorTransport((name, args) async {
        if (name == 'insertMarkdownSnapshot') insertCalls++;
        return host.call(name, args);
      });
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, '# Exact'),
        readOnly: false,
        sharedMarkdownEditing: true,
        publicResourceRoot: Uri.parse('https://example.test'),
      );
      final snapshot = await transport.capture();
      await expectLater(
        transport.insertMarkdown(snapshot, text: ''),
        throwsArgumentError,
      );
      await expectLater(
        transport.insertMarkdown(snapshot, text: 'x' * 65537),
        throwsArgumentError,
      );
      await expectLater(
        transport.insertMarkdown(snapshot, text: String.fromCharCode(0xd800)),
        throwsFormatException,
      );
      expect(insertCalls, 0);
      await transport.release(snapshot);
      expect(host.transfers, isEmpty);
      await transport.retire();
    },
  );

  test(
    'shared Markdown purpose explicitly authorizes editable anonymous transport and exact source',
    () async {
      final host = MarkdownCreationHost();
      Map? options;
      final transport = ComplexEditorTransport((method, args) async {
        if (method == 'beginLoad') options = Map.from(args[3] as Map);
        return host.call(method, args);
      });
      const text = '\ufeff# Shared\r\n\r\n- exact source\r\n';
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, text),
        readOnly: false,
        sharedMarkdownEditing: true,
        publicResourceRoot: Uri.parse('https://example.test/base'),
      );
      expect(options!['readOnly'], isFalse);
      expect(options!['sharedMarkdownEditing'], isTrue);
      expect(options!['publicResourceRoot'], 'https://example.test/base');
      final captured = await transport.capture();
      expect(captured.document.source, text);
      await transport.release(captured);
      await transport.retire();
    },
  );
  test(
    'shared purpose cannot omit its anonymous root or load a different document type',
    () async {
      var calls = 0;
      final transport = ComplexEditorTransport((_, _) async {
        calls++;
        return null;
      });
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        '# Shared',
      );
      await expectLater(
        transport.load(doc, sharedMarkdownEditing: true, readOnly: false),
        throwsArgumentError,
      );
      await expectLater(
        transport.load(
          ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>HTML</p>'),
          sharedMarkdownEditing: true,
          readOnly: false,
          publicResourceRoot: Uri.parse('https://example.test'),
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
      await transport.retire();
    },
  );
  test(
    'shared editable purpose keeps the public four MiB loading bound',
    () async {
      var calls = 0;
      final transport = ComplexEditorTransport((_, _) async {
        calls++;
        return null;
      });
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        'x' * (4 * 1024 * 1024 + 1),
      );
      await expectLater(
        transport.load(
          doc,
          readOnly: false,
          sharedMarkdownEditing: true,
          publicResourceRoot: Uri.parse('https://example.test'),
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
      await transport.retire();
    },
  );
}
