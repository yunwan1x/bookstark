import 'complex_editor_document.dart';

/// UTF-16 offsets in the exact exported source, including original CRLF/BOM.
/// Captured before native selection and rebound only to the identical source.
class MarkdownSnapshotSelection {
  const MarkdownSnapshotSelection._(this.anchor, this.head, this.sourceDigest);
  final int anchor, head;
  final String sourceDigest;

  static MarkdownSnapshotSelection parse(
    Object? value,
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.markdown || value is! Map) {
      throw const FormatException('Markdown selection required');
    }
    final anchor = value['anchor'], head = value['head'];
    bool boundary(Object? offset) {
      if (offset is! int || offset < 0 || offset > document.source.length) {
        return false;
      }
      if (offset > 0 && offset < document.source.length) {
        final previous = document.source.codeUnitAt(offset - 1);
        final next = document.source.codeUnitAt(offset);
        if ((previous >= 0xd800 &&
                previous <= 0xdbff &&
                next >= 0xdc00 &&
                next <= 0xdfff) ||
            (previous == 13 && next == 10)) {
          return false;
        }
      }
      return true;
    }

    if (!boundary(anchor) || !boundary(head)) {
      throw const FormatException('Invalid Markdown selection boundary');
    }
    return MarkdownSnapshotSelection._(
      anchor as int,
      head as int,
      document.digest,
    );
  }

  ComplexEditorDocument insert(ComplexEditorDocument document, String text) {
    if (document.kind != ComplexEditorKind.markdown ||
        document.digest != sourceDigest ||
        text.isEmpty) {
      throw StateError('Markdown insertion source changed');
    }
    ComplexEditorDocument.parse(ComplexEditorKind.markdown, text);
    final from = anchor < head ? anchor : head;
    final to = anchor > head ? anchor : head;
    return ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      document.source.substring(0, from) + text + document.source.substring(to),
    );
  }
}
