import 'package:markdown/markdown.dart' as md;
import 'dart:convert';

List<String> speechSegments(String markdown) {
  // Explicit whole-input budget, no silent truncation. UTF16 early check avoids
  // encoding an already oversized string; UTF8 then enforces exact wire bytes.
  const maxTextBytes = 20 * 1024 * 1024;
  if (markdown.length > maxTextBytes ||
      utf8.encode(markdown).length > maxTextBytes) {
    throw const FormatException(
      '朗读原文超过20MiB，请按章节选择 / Speech text exceeds 20MiB; select chapters',
    );
  }
  final stripped = markdown
      .replaceAll(
        RegExp(
          r'<(script|style|pre|code|svg|math|iframe)\b[^>]*>[\s\S]*?(?:</\1\s*>|$)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '');
  final nodes = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(stripped.split('\n'));
  String text(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is! md.Element ||
        {'pre', 'code', 'img', 'script', 'style'}.contains(node.tag)) {
      return '';
    }
    final value = (node.children ?? []).map(text).join();
    return {
          'p',
          'li',
          'blockquote',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'tr',
        }.contains(node.tag)
        ? '$value\n'
        : value;
  }

  final readable = nodes
      .map(text)
      .join('\n')
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (readable.isEmpty) {
    throw const FormatException('没有可朗读文字 / No readable text');
  }
  final segments = <String>[];
  // At most 200 Unicode scalars in the splitting scratch buffer, including a
  // single 20MiB paragraph. Never build whole-paragraph List<int>.
  for (final paragraph in readable.split(RegExp(r'\n+'))) {
    final pending = <int>[];
    void emit(int end) {
      final value = String.fromCharCodes(pending.take(end)).trim();
      if (value.isNotEmpty) segments.add(value);
      pending.removeRange(0, end);
    }

    for (final scalar in paragraph.runes) {
      pending.add(scalar);
      if (pending.length == 200) {
        var end = 200;
        for (var at = 199; at >= 79; at--) {
          if (RegExp(
            r'[。！？.!?；;\s]',
          ).hasMatch(String.fromCharCode(pending[at]))) {
            end = at + 1;
            break;
          }
        }
        emit(end);
      }
    }
    if (pending.isNotEmpty) emit(pending.length);
  }
  return List.unmodifiable(segments);
}
