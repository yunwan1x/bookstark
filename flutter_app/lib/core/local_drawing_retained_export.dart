import 'complex_editor_document.dart';
import 'owned_article_review_export.dart';

/// Exact existing local drawing source. Export authority never creates a
/// drawing editor, claims SDK readiness, or writes/deletes a recovery record.
final class LocalDrawingRetainedExport {
  LocalDrawingRetainedExport({
    required ComplexEditorDocument document,
    required this.verifyFresh,
  }) : source = document.source,
       export = OwnedArticleReviewExport(
         source: document.source,
         mime: 'application/json',
         name: 'retained-drawing.json',
       ) {
    if (document.kind != ComplexEditorKind.drawing) {
      throw ArgumentError('Existing drawing source required');
    }
  }
  final String source;
  final OwnedArticleReviewExport export;
  final Future<void> Function() verifyFresh;
  bool get renderable =>
      export.bytes.length <= ComplexEditorKind.markdown.maxBytes;
}
