import 'dart:convert';
import '../../core/api_client.dart';

/// Preview-only wrapping, matching the original HTML editor. Never use this
/// document as saved source: full documents stay byte-for-byte unchanged, and
/// fragments are wrapped without parsing, sanitizing or rewriting their script.
String buildHtmlPreviewDocument(
  String source, {
  Uri? server,
  bool bare = false,
}) {
  if (utf8.encode(source).length > 5 * 1024 * 1024) {
    throw const FormatException('HTML preview exceeds source limit');
  }
  final trimmed = source.trimLeft();
  if (RegExp(
    r'^(?:<!doctype\s+html\b|<html(?:\s|>))',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return source;
  }
  const meta =
      '<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">';
  var head = meta;
  if (!bare) {
    if (server != null) {
      final base = BookstarkClient.normalizeServer(server.toString());
      final stylesheet = base.replace(
        path: '${base.path}/static/css/modern-normalize.css',
      );
      final href = const HtmlEscape(
        HtmlEscapeMode.attribute,
      ).convert(stylesheet.toString());
      head += '<link rel="stylesheet" href="$href">';
    }
    head +=
        '<style>body{font-family:system-ui,-apple-system,sans-serif;line-height:1.6;padding:24px}img,svg,video,canvas{max-width:100%;height:auto}</style>';
  }
  return '<!DOCTYPE html><html><head>$head</head><body>$source</body></html>';
}
