import 'dart:convert';
import '../../core/api_client.dart';
import '../html/html_preview_document.dart';

/// Only presentation gets a base. Raw shared/editor content is never rewritten.
String publicHtmlPreviewDocument(String source, Uri server) {
  final root = BookstarkClient.normalizeServer(server.toString());
  final base =
      '<base href="${const HtmlEscape(HtmlEscapeMode.attribute).convert('$root/')}">';
  if (utf8.encode(base).length > 8 * 1024) {
    throw const FormatException('Public preview base too long');
  }
  final document = buildHtmlPreviewDocument(source, server: root);
  var cursor = document.startsWith('\ufeff') ? 1 : 0, fallback = cursor;
  int tagEnd(int start) {
    String? quote;
    for (var index = start; index < document.length; index++) {
      final char = document[index];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '>') {
        return index + 1;
      }
    }
    return -1;
  }

  while (cursor < document.length) {
    while (cursor < document.length &&
        const {9, 10, 12, 13, 32}.contains(document.codeUnitAt(cursor))) {
      cursor++;
    }
    if (document.startsWith('<!--', cursor)) {
      final end = document.indexOf('-->', cursor + 4);
      if (end < 0) break;
      cursor = end + 3;
      continue;
    }
    final tail = document
        .substring(
          cursor,
          cursor + 16 < document.length ? cursor + 16 : document.length,
        )
        .toLowerCase();
    if (tail.startsWith('<!doctype')) {
      final end = tagEnd(cursor + 2);
      if (end < 0) break;
      fallback = end;
      cursor = end;
      continue;
    }
    final tag = RegExp(
      r'^<(html|head)(?=[\s>])',
      caseSensitive: false,
    ).firstMatch(tail);
    if (tag == null) break;
    final end = tagEnd(cursor + tag.end);
    if (end < 0) break;
    if (tag[1]!.toLowerCase() == 'head') {
      return '${document.substring(0, end)}$base${document.substring(end)}';
    }
    fallback = end;
    cursor = end;
  }
  // Implicit heads are valid HTML. Insert before body/script instead of parsing
  // or serializing the user's document (including script strings containing tags).
  return '${document.substring(0, fallback)}<head>$base</head>${document.substring(fallback)}';
}
