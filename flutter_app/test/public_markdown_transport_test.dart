import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/markdown_creation_host.dart';

void main() {
  test(
    'public read-only context preserves exact source through bounded transport',
    () async {
      final host = MarkdownCreationHost();
      Map? options;
      final transport = ComplexEditorTransport((method, args) async {
        if (method == 'beginLoad') options = Map.from(args[3] as Map);
        return host.call(method, args);
      });
      const text = '\ufeff\ufeff# Public\r\n- Exact source\r\n';
      final doc = ComplexEditorDocument.parse(ComplexEditorKind.markdown, text);
      await transport.load(
        doc,
        publicResourceRoot: Uri.parse('https://example.invalid/bookstark'),
      );
      expect(options!['readOnly'], isTrue);
      expect(
        options!['publicResourceRoot'],
        'https://example.invalid/bookstark',
      );
      final snapshot = await transport.capture();
      expect(snapshot.document.source, text);
      await transport.release(snapshot);
      await transport.retire();
    },
  );

  test(
    'public mode rejects wrong type, editable input and malformed roots before any command',
    () async {
      var calls = 0;
      final transport = ComplexEditorTransport((_, _) async {
        calls++;
        return null;
      });
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        '# Read only',
      );
      for (final root in [
        Uri.parse('/relative'),
        Uri.parse('file:///article'),
        Uri.parse('https://forbidden@example.invalid'),
        Uri.parse('https://example.invalid?secret=blocked'),
        Uri.parse('https://example.invalid#fragment'),
        Uri.parse('https://example.invalid:65536'),
        Uri(
          scheme: 'https',
          host: 'example.invalid',
          pathSegments: ['bad/scope'],
        ),
        Uri(
          scheme: 'https',
          host: 'example.invalid',
          pathSegments: ['bad\\scope'],
        ),
      ]) {
        await expectLater(
          transport.load(doc, publicResourceRoot: root),
          throwsArgumentError,
          reason: root.toString(),
        );
      }
      final root = Uri.parse('https://example.invalid');
      await expectLater(
        transport.load(doc, readOnly: false, publicResourceRoot: root),
        throwsArgumentError,
      );
      await expectLater(
        transport.load(
          ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>HTML</p>'),
          publicResourceRoot: root,
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
      await transport.retire();
    },
  );

  test('public content cap does not narrow local Markdown transport', () async {
    final host = MarkdownCreationHost();
    var calls = 0;
    final transport = ComplexEditorTransport((name, args) async {
      calls++;
      return host.call(name, args);
    });
    final doc = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      'x' * (4 * 1024 * 1024 + 1),
    );
    await expectLater(
      transport.load(
        doc,
        publicResourceRoot: Uri.parse('http://example.invalid/prefix'),
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
    await transport.load(doc);
    expect(host.source.length, doc.source.length);
    await transport.retire();
  });
}
