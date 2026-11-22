import 'dart:convert';
import 'package:markdown/markdown.dart' as md;

/// Removes complete parsed link/image uses of [uri], retaining definitions,
/// code, bare URLs and unrelated source bytes. Every candidate is reparsed to
/// prove that only target uses disappear and remaining Markdown is unchanged.
String removeMarkdownAttachmentUses(String source, Uri uri) {
  final original = _ParsedAttachments(source, uri, capture: true);
  if (original.count == 0) return source;
  final ranges = <(int, int), String>{};
  for (final entry in original.syntax.entries) {
    final syntax = entry.key;
    final pattern = RegExp(
      syntax.split('\n').map(RegExp.escape).join(r'\r?\n'),
    );
    for (final match in pattern.allMatches(source)) {
      ranges[(match.start, match.end)] = entry.value;
    }
  }
  final ordered = ranges.keys.toList()
    ..sort((a, b) {
      final start = a.$1.compareTo(b.$1);
      return start != 0 ? start : b.$2.compareTo(a.$2);
    });
  var outerEnd = -1;
  ordered.removeWhere((range) {
    if (range.$1 < outerEnd) return true;
    outerEnd = range.$2;
    return false;
  });
  ordered.sort((a, b) => b.$1.compareTo(a.$1));
  // Ordinary documents need only one verification parse, even for many uses.
  var batch = source;
  for (final range in ordered) {
    batch = batch.replaceRange(range.$1, range.$2, ranges[range]!);
  }
  final batchParsed = _ParsedAttachments(batch, uri);
  if (batchParsed.count == 0 && batchParsed.signature == original.signature) {
    return batch;
  }
  var result = source, count = original.count;
  var laterStart = source.length;
  for (final range in ordered) {
    if (range.$2 > laterStart) continue;
    final candidate = result.replaceRange(range.$1, range.$2, ranges[range]!);
    final parsed = _ParsedAttachments(candidate, uri);
    if (parsed.count < count && parsed.signature == original.signature) {
      result = candidate;
      count = parsed.count;
      laterStart = range.$1;
      if (count == 0) break;
    }
  }
  return result;
}

class _ParsedAttachments {
  _ParsedAttachments(String source, this.uri, {bool capture = false}) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: capture
          ? [
              _CaptureAttachmentSyntax(this, image: true),
              _CaptureAttachmentSyntax(this, image: false),
            ]
          : null,
    );
    signature = jsonEncode(_children(document.parse(source)));
  }
  final Uri uri;
  final syntax = <String, String>{};
  int count = 0;
  late final String signature;
  bool target(md.Node node) {
    if (node is! md.Element) return false;
    final url = node.tag == 'img'
        ? node.attributes['src']
        : node.tag == 'a'
        ? node.attributes['href']
        : null;
    return url != null && Uri.tryParse(url) == uri;
  }

  bool otherUse(md.Node node) {
    if (node is! md.Element) return false;
    if ((node.tag == 'a' || node.tag == 'img') && !target(node)) return true;
    return node.children?.any(otherUse) ?? false;
  }

  List<Object?> _children(List<md.Node> nodes) {
    final result = <Object?>[];
    for (final node in nodes) {
      if (target(node)) {
        count++;
        // An attachment image may itself be the label of a target link.
        // Unwrap that link rather than deleting a different attachment.
        if (node is md.Element &&
            node.tag == 'a' &&
            (node.children?.any(otherUse) ?? false)) {
          for (final value in _children(node.children!)) {
            if (value is String && result.isNotEmpty && result.last is String) {
              result[result.length - 1] = (result.last as String) + value;
            } else {
              result.add(value);
            }
          }
        }
        continue;
      }
      if (node is md.Text) {
        if (node.text.isEmpty) continue;
        if (result.isNotEmpty && result.last is String) {
          result[result.length - 1] = (result.last as String) + node.text;
        } else {
          result.add(node.text);
        }
      } else if (node is md.Element) {
        final children = _children(node.children ?? []);
        // Paragraph parsing trims the line end after a removed final use.
        // Ignore only the same non-rendering trailing whitespace, never code.
        if ({
              'p',
              'li',
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
            }.contains(node.tag) &&
            children.isNotEmpty &&
            children.last is String) {
          children[children.length - 1] = (children.last as String).trimRight();
        }
        if ({
              'p',
              'li',
              'ul',
              'ol',
              'blockquote',
              'strong',
              'em',
              'del',
              'a',
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
            }.contains(node.tag) &&
            children.every(
              (value) => value is String && value.trim().isEmpty,
            )) {
          continue;
        }
        result.add([node.tag, node.attributes, children]);
      } else {
        result.add(['unknown', node.textContent]);
      }
    }
    return result;
  }
}

class _CaptureAttachmentSyntax extends md.LinkSyntax {
  _CaptureAttachmentSyntax(this.owner, {required this.image})
    : super(pattern: image ? r'!\[' : r'\[', startCharacter: image ? 33 : 91);
  final _ParsedAttachments owner;
  final bool image;
  @override
  md.Node createNode(
    String destination,
    String? title, {
    required List<md.Node> Function() getChildren,
  }) => image
      ? md.ImageSyntax().createNode(
          destination,
          title,
          getChildren: getChildren,
        )
      : super.createNode(destination, title, getChildren: getChildren);
  @override
  Iterable<md.Node>? close(
    md.InlineParser parser,
    covariant md.SimpleDelimiter opener,
    md.Delimiter? closer, {
    String? tag,
    required List<md.Node> Function() getChildren,
  }) {
    final labelEnd = parser.pos;
    final nodes = super
        .close(parser, opener, closer, tag: tag, getChildren: getChildren)
        ?.toList();
    if (nodes != null && nodes.any(owner.target)) {
      final unwrap = nodes.any(
        (node) =>
            node is md.Element &&
            node.tag == 'a' &&
            (node.children?.any(owner.otherUse) ?? false),
      );
      owner.syntax[parser.source.substring(
        opener.endPos - opener.length,
        parser.pos + 1,
      )] = unwrap
          ? parser.source.substring(opener.endPos, labelEnd)
          : '';
    }
    return nodes;
  }
}
