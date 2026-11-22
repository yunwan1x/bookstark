import 'dart:convert';
import 'complex_editor_document.dart';
import 'local_markdown_resources.dart';

/// Only actual MindElixir node.image.url fields grant local raster reads.
/// Unknown strings and topic HTML never become attachment authority.
final class LocalMindmapImageReferences {
  LocalMindmapImageReferences._(this.sourceDigest, this.references);
  final String sourceDigest;
  final Set<Uri> references;
  factory LocalMindmapImageReferences.unavailable(
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.mindmap) {
      throw const FormatException('Actual mind-map source required');
    }
    return LocalMindmapImageReferences._(document.digest, const <Uri>{});
  }
  factory LocalMindmapImageReferences.capture(ComplexEditorDocument document) {
    if (document.kind != ComplexEditorKind.mindmap) {
      throw const FormatException('Actual mind-map image source required');
    }
    final source = document.source;
    final decoded = jsonDecode(
      source.startsWith('\uFEFF') ? source.substring(1) : source,
    );
    if (decoded is! Map || decoded['nodeData'] is! Map) {
      throw const FormatException('Actual MindElixir nodeData required');
    }
    final references = <Uri>{};
    var nodes = 0;
    void walk(Map node, int depth) {
      if (++nodes > 50000 || depth > 32) {
        throw const FormatException('Mind-map image tree bound');
      }
      final image = node['image'];
      if (image is Map && image['url'] is String) {
        final uri = Uri.tryParse(image['url'] as String);
        if (uri != null && uri.scheme == 'bookstark-attachment') {
          LocalMarkdownResources.identity(uri);
          references.add(uri);
          if (references.length > 32) {
            throw const FormatException('Mind-map image count bound');
          }
        }
      }
      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is! Map)
            throw const FormatException('Invalid MindElixir child');
          walk(child, depth + 1);
        }
      }
    }

    walk(decoded['nodeData'] as Map, 0);
    return LocalMindmapImageReferences._(
      document.digest,
      Set<Uri>.unmodifiable(references),
    );
  }
}
