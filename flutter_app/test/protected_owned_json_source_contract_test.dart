import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';

void main() {
  test(
    'drawing preserves valid CRLF JSON and rejects BOM without normalization',
    () {
      const source = '{"elements":[]}\r\n';
      expect(
        ComplexEditorDocument.parse(ComplexEditorKind.drawing, source).source,
        source,
      );
      expect(
        () => ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          '\uFEFF$source',
        ),
        throwsFormatException,
      );
    },
  );
}
