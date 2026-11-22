import 'dart:convert';
import 'complex_editor_document.dart';
import 'local_markdown_resources.dart';

/// Actual canvas-editor image elements only. Parsing never edits original JSON.
final class LocalRichdocImageReferences {
  LocalRichdocImageReferences._(this.sourceDigest, this.references);
  final String sourceDigest;
  final Set<Uri> references;

  /// Resource discovery failure never replaces or rejects a valid editor body.
  /// Empty authority is explicit; source and its digest remain unchanged.
  factory LocalRichdocImageReferences.unavailable(
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.richdoc) {
      throw const FormatException('Actual rich-document source required');
    }
    return LocalRichdocImageReferences._(document.digest, const <Uri>{});
  }

  factory LocalRichdocImageReferences.capture(ComplexEditorDocument document) {
    if (document.kind != ComplexEditorKind.richdoc) {
      throw const FormatException('Rich-document image source required');
    }
    final decoded = jsonDecode(document.source);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('Rich-document data required');
    }
    final data = decoded['data'] as Map;
    final references = <Uri>{};
    void image(String raw) {
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme != 'bookstark-attachment') return;
      LocalMarkdownResources.identity(uri);
      references.add(uri);
      if (references.length > 32) {
        throw const FormatException('Rich-document image count bound');
      }
    }

    var nodes = 0;
    void walk(Object? node, int depth) {
      if (++nodes > 50000 || depth > 32) {
        throw const FormatException('Rich-document image tree bound');
      }
      if (node is List) {
        for (final child in node) {
          walk(child, depth + 1);
        }
      } else if (node is Map) {
        if (node['type'] == 'image' && node['value'] is String) {
          image(node['value'] as String);
        }
        // Canvas-editor containers: table rows/cells, hyperlinks and inline
        // groups. Unknown metadata strings cannot grant attachment access.
        for (final key in ['valueList', 'trList', 'tdList', 'value']) {
          final child = node[key];
          if (child is List) walk(child, depth + 1);
        }
      }
    }

    for (final zone in ['header', 'main', 'footer']) {
      final content = data[zone];
      if (content is List) walk(content, 0);
    }
    // Actual canvas-editor rendered option fields, not arbitrary metadata.
    final options = decoded['options'];
    if (options is Map) {
      final background = options['background'];
      if (background is Map && background['image'] is String) {
        image(background['image'] as String);
      }
      final watermark = options['watermark'];
      if (watermark is Map &&
          watermark['type'] == 'image' &&
          watermark['data'] is String) {
        image(watermark['data'] as String);
      }
    }
    return LocalRichdocImageReferences._(
      document.digest,
      Set<Uri>.unmodifiable(references),
    );
  }
}
