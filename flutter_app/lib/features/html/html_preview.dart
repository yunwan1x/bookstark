import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// An inert native view. Parsing never creates a browser, runs script, submits
/// forms or fetches images. The source is never modified by preview filtering.
class NativeHtmlPreview extends StatefulWidget {
  const NativeHtmlPreview({
    super.key,
    required this.source,
    this.english = false,
    this.onOpenLink,
  });
  final String source;
  final bool english;
  final ValueChanged<Uri>? onOpenLink;
  @override
  State<NativeHtmlPreview> createState() => _NativeHtmlPreviewState();
}

class _NativeHtmlPreviewState extends State<NativeHtmlPreview> {
  dom.Element? _body;
  bool _limited = false, _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  static const blocked = {
    'head',
    'script',
    'style',
    'link',
    'meta',
    'base',
    'iframe',
    'object',
    'embed',
    'template',
    'canvas',
    'svg',
    'input',
    'button',
    'select',
    'textarea',
    'video',
    'audio',
  };
  static const blocks = {
    'html',
    'body',
    'article',
    'section',
    'main',
    'div',
    'header',
    'footer',
    'aside',
    'nav',
    'figure',
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'pre',
    'blockquote',
    'table',
    'hr',
    'form',
    'details',
    'summary',
    'img',
  };
  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant NativeHtmlPreview old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _parse();
    }
  }

  void _parse() {
    _body = null;
    _limited = false;
    _failed = false;
    if (widget.source.length > 500000) {
      _limited = true;
      return;
    }
    try {
      final body = parser.parse(widget.source).body;
      if (body == null) {
        _failed = true;
        return;
      }
      final pending = <(dom.Node, int)>[(body, 0)];
      var count = 0;
      while (pending.isNotEmpty) {
        final (node, depth) = pending.removeLast();
        if (++count > 5000 || depth > 48) {
          _limited = true;
          return;
        }
        if (node is dom.Element &&
            (blocked.contains(node.localName) ||
                node.attributes.containsKey('hidden'))) {
          continue;
        }
        for (final child in node.nodes) {
          pending.add((child, depth + 1));
        }
      }
      _body = body;
    } catch (_) {
      _failed = true;
    }
  }

  bool skip(dom.Node node) =>
      node is dom.Element &&
      (blocked.contains(node.localName) ||
          node.attributes.containsKey('hidden'));
  Uri? link(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        raw.trim().isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasScheme &&
            !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.hasScheme && uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  List<InlineSpan> inline(Iterable<dom.Node> nodes, {int depth = 0}) {
    if (depth > 48) {
      return const [];
    }
    return nodes.map<InlineSpan>((node) {
      if (skip(node)) {
        return const TextSpan();
      }
      if (node is dom.Text) {
        return TextSpan(text: node.data.replaceAll(RegExp(r'\s+'), ' '));
      }
      if (node is! dom.Element) {
        return const TextSpan();
      }
      final tag = node.localName;
      if (tag == 'br') {
        return const TextSpan(text: '\n');
      }
      if (tag == 'img') {
        return TextSpan(
          text:
              '[${t('图片未加载', 'Image not loaded')}: ${node.attributes['alt'] ?? ''}]',
        );
      }
      if (tag == 'a') {
        final uri = link(node.attributes['href'] ?? '');
        if (uri == null || widget.onOpenLink == null) {
          return TextSpan(
            children: inline(node.nodes, depth: depth + 1),
            style: const TextStyle(decoration: TextDecoration.underline),
          );
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: TextButton(
            onPressed: () => widget.onOpenLink?.call(uri),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(48, 48),
            ),
            child: Text(node.text),
          ),
        );
      }
      final style = switch (tag) {
        'strong' || 'b' => const TextStyle(fontWeight: FontWeight.bold),
        'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
        's' || 'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'u' => const TextStyle(decoration: TextDecoration.underline),
        'code' => const TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xffeef2f8),
        ),
        _ => null,
      };
      return TextSpan(
        style: style,
        children: inline(node.nodes, depth: depth + 1),
      );
    }).toList();
  }

  Widget rich(Iterable<dom.Node> nodes, {TextStyle? style}) =>
      Text.rich(TextSpan(style: style, children: inline(nodes)));
  List<Widget> children(Iterable<dom.Node> nodes, int depth) {
    final widgets = <Widget>[], buffer = <dom.Node>[];
    void flush() {
      if (buffer.any(
        (v) =>
            (v.text ?? '').trim().isNotEmpty ||
            v is dom.Element && v.localName == 'br',
      )) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: rich(buffer.toList()),
          ),
        );
      }
      buffer.clear();
    }

    for (final node in nodes) {
      if (skip(node)) {
        continue;
      }
      if (node is dom.Element && blocks.contains(node.localName)) {
        flush();
        final next = block(node, depth + 1);
        if (next != null) {
          widgets.add(next);
        }
      } else {
        buffer.add(node);
      }
    }
    flush();
    return widgets;
  }

  Widget? block(dom.Element node, int depth) {
    if (depth > 48 || skip(node)) {
      return null;
    }
    final tag = node.localName;
    if (tag == 'hr') {
      return const Divider(height: 24);
    }
    if (tag == 'img') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '${t('图片未加载', 'Image not loaded')}: ${node.attributes['alt'] ?? ''}',
        ),
      );
    }
    if (tag == 'pre') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        color: const Color(0xffeef2f8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            node.text,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      );
    }
    if (tag == 'table') {
      return table(node);
    }
    if (tag == 'ul' || tag == 'ol') {
      final items = node.children.where((v) => v.localName == 'li').toList();
      final start = (int.tryParse(node.attributes['start'] ?? '') ?? 1).clamp(
        1,
        10000,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tag == 'ol' ? '${start + i}. ' : '• '),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children(items[i].nodes, depth + 1),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (tag == 'blockquote') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xff0b4eff), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children(node.nodes, depth + 1),
        ),
      );
    }
    if (tag == 'details') {
      final summary = node.children
          .where((v) => v.localName == 'summary')
          .firstOrNull;
      return ExpansionTile(
        initiallyExpanded: node.attributes.containsKey('open'),
        title: Text(summary?.text ?? t('展开内容', 'Expand content')),
        children: children(
          node.nodes.where((v) => !identical(v, summary)),
          depth + 1,
        ),
      );
    }
    if (tag == 'form') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('表单未启用', 'Form is inactive')),
          ...children(node.nodes, depth + 1),
        ],
      );
    }
    if (tag == 'p' || RegExp(r'^h[1-6]$').hasMatch(tag ?? '')) {
      final heading = tag != 'p';
      final sizes = {
        'h1': 28.0,
        'h2': 25.0,
        'h3': 22.0,
        'h4': 20.0,
        'h5': 18.0,
        'h6': 16.0,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: rich(
          node.nodes,
          style: heading
              ? TextStyle(fontSize: sizes[tag], fontWeight: FontWeight.bold)
              : null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children(node.nodes, depth + 1),
    );
  }

  Widget table(dom.Element element) {
    final rows = element.querySelectorAll('tr').where((row) {
      var parent = row.parent;
      while (parent != null && parent.localName != 'table') {
        parent = parent.parent;
      }
      return identical(parent, element);
    }).toList();
    final cells = rows
        .map(
          (row) => row.children
              .where((v) => v.localName == 'td' || v.localName == 'th')
              .toList(),
        )
        .toList();
    final width = cells.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (rows.length > 100 ||
        width > 8 ||
        cells.any(
          (row) => row.any(
            (v) =>
                v.text.length > 512 ||
                v.attributes.containsKey('rowspan') ||
                v.attributes.containsKey('colspan'),
          ),
        )) {
      return Text(t('此表格需在HTML源码中查看。', 'View this table in the HTML source.'));
    }
    if (width == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: const Color(0xffd5dce8)),
          children: [
            for (final row in cells)
              TableRow(
                children: [
                  for (var i = 0; i < width; i++)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: i < row.length
                          ? rich(
                              row[i].nodes,
                              style: row[i].localName == 'th'
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            )
                          : const Text(''),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _limited) {
      return Text(
        _limited
            ? t(
                '内容较大或结构复杂，请切换HTML源码查看完整内容。',
                'This content is large or complex. Open HTML source to view all of it.',
              )
            : t(
                '未能生成原生预览，HTML源码仍可查看。',
                'Native preview could not be created. HTML source remains available.',
              ),
      );
    }
    final content = children(_body?.nodes ?? [], 0);
    return SelectionArea(
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content.isEmpty
              ? [
                  Text(
                    t(
                      '预览没有可显示的内容，请查看HTML源码。',
                      'No content to display in preview. Open HTML source.',
                    ),
                  ),
                ]
              : content,
        ),
      ),
    );
  }
}
