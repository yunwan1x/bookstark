import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/markdown_snapshot_selection.dart';

void main() {
  ComplexEditorDocument document(String text) =>
      ComplexEditorDocument.parse(ComplexEditorKind.markdown, text);

  test(
    'selection insertion preserves BOM, CRLF and reversed UTF-16 selection',
    () {
      final original = document('\ufeff甲\r\n😀ABC\r\n尾');
      final selection = MarkdownSnapshotSelection.parse({
        'anchor': 8,
        'head': 6,
      }, original);
      final inserted = selection.insert(
        original,
        '[文件](<bookstark-attachment:///aa/name>)',
      );
      expect(
        inserted.source,
        '\ufeff甲\r\n😀[文件](<bookstark-attachment:///aa/name>)C\r\n尾',
      );
      expect(original.source, '\ufeff甲\r\n😀ABC\r\n尾');
    },
  );

  test('a changed source cannot consume a prior insertion selection', () {
    final original = document('ABC');
    final selection = MarkdownSnapshotSelection.parse({
      'anchor': 1,
      'head': 1,
    }, original);
    expect(() => selection.insert(document('ABD'), 'X'), throwsStateError);
    expect(selection.insert(original, 'X').source, 'AXBC');
  });

  test('surrogate and CRLF splitting offsets are rejected', () {
    final original = document('\ufeff甲\r\n😀尾');
    for (final bad in [-1, 3, 5, 99, 1.5, '1', null]) {
      expect(
        () => MarkdownSnapshotSelection.parse({
          'anchor': bad,
          'head': 0,
        }, original),
        throwsFormatException,
      );
    }
  });

  test('both empty-document edges and astral boundaries are valid', () {
    final empty = document('');
    final atStart = MarkdownSnapshotSelection.parse({
      'anchor': 0,
      'head': 0,
    }, empty);
    expect(atStart.insert(empty, '😀\r\n').source, '😀\r\n');
    final astral = document('😀');
    final atEnd = MarkdownSnapshotSelection.parse({
      'anchor': 2,
      'head': 2,
    }, astral);
    expect(atEnd.insert(astral, '尾').source, '😀尾');
  });

  test('insertion rejects malformed Unicode and wrong document types', () {
    final original = document('source');
    final selection = MarkdownSnapshotSelection.parse({
      'anchor': 0,
      'head': 0,
    }, original);
    expect(
      () => selection.insert(original, String.fromCharCode(0xd800)),
      throwsFormatException,
    );
    final html = ComplexEditorDocument.parse(ComplexEditorKind.html, 'source');
    expect(
      () => MarkdownSnapshotSelection.parse({'anchor': 0, 'head': 0}, html),
      throwsFormatException,
    );
    expect(() => selection.insert(html, 'text'), throwsStateError);
  });
}
