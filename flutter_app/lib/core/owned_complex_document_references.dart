import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'complex_editor_document.dart';

/// Reference discovery never edits source. The resource reader independently
/// canonicalizes and denies every URL outside the exact owned server prefix.
class OwnedComplexDocumentReferences {
  OwnedComplexDocumentReferences._(
    this.sourceDigest,
    this.fullFingerprint,
    this.references,
  );
  final String sourceDigest, fullFingerprint;
  final Set<Uri> references;
  factory OwnedComplexDocumentReferences.capture(
    ComplexEditorDocument document, {
    required String fullFingerprint,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fullFingerprint)) {
      throw const FormatException('Verified source fingerprint required');
    }
    final references = <Uri>{};
    void candidate(String raw) {
      var text = raw.trim();
      if (text.length >= 2 &&
          (text.codeUnitAt(0) == 34 || text.codeUnitAt(0) == 39) &&
          text.codeUnitAt(text.length - 1) == text.codeUnitAt(0)) {
        text = text.substring(1, text.length - 1);
      }
      if (text.isEmpty || text.length > 8192) return;
      final uri = Uri.tryParse(text);
      if (uri == null ||
          (!uri.path.contains('/upload-files/') &&
              !uri.path.contains('/static/'))) {
        return;
      }
      references.add(uri);
      if (references.length > 32) {
        throw const FormatException('Document references exceed limit');
      }
    }

    void text(String value) {
      candidate(value);
      for (final match in RegExp(
        'url\\(([^)]+)\\)',
        caseSensitive: false,
      ).allMatches(value)) {
        candidate(match.group(1)!);
      }
    }

    if (document.kind == ComplexEditorKind.html) {
      var tags = 0;
      for (var i = 0; i < document.source.length; i++) {
        if (document.source.codeUnitAt(i) == 60 && ++tags > 20000) {
          throw const FormatException('HTML reference tree bound');
        }
      }
      final parsed = html.parse(document.source);
      for (final node in parsed.querySelectorAll('*')) {
        for (final name in ['src', 'href', 'poster', 'background', 'style']) {
          final value = node.attributes[name];
          if (value != null) text(value);
        }
        final srcset = node.attributes['srcset'];
        if (srcset != null) {
          for (final part in srcset.split(',')) {
            candidate(part.trim().split(RegExp(r'\s+')).first);
          }
        }
        if (node.localName == 'style') text(node.text);
      }
    } else {
      if (document.kind == ComplexEditorKind.markdown) {
        throw const FormatException('Complex source required');
      }
      // ComplexEditorDocument already validated full JSON. Scan its string
      // tokens without decoding a second 20MiB presentation object graph.
      final source = document.source;
      for (var i = 0; i < source.length; i++) {
        if (source.codeUnitAt(i) != 34) continue;
        final start = i++;
        while (i < source.length) {
          final unit = source.codeUnitAt(i);
          if (unit == 92) {
            i += 2;
            continue;
          }
          if (unit == 34) break;
          i++;
        }
        if (i >= source.length) {
          throw const FormatException('Validated source string missing');
        }
        if (i - start <= 32768) {
          final value = jsonDecode(source.substring(start, i + 1));
          if (value is String) text(value);
        }
      }
    }
    return OwnedComplexDocumentReferences._(
      document.digest,
      fullFingerprint,
      Set.unmodifiable(references),
    );
  }
}
