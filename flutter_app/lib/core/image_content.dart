import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';

String? imageContentMime(Uint8List bytes) {
  bool prefix(List<int> signature) =>
      bytes.length >= signature.length &&
      List.generate(
        signature.length,
        (index) => bytes[index] == signature[index],
      ).every((value) => value);
  if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (prefix([255, 216, 255])) return 'image/jpeg';
  if (prefix(ascii.encode('GIF87a')) || prefix(ascii.encode('GIF89a'))) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  final head = utf8
      .decode(bytes.take(4096).toList(), allowMalformed: true)
      .replaceFirst('\uFEFF', '')
      .trimLeft();
  if ((head.startsWith('<svg') ||
          head.startsWith('<?xml') ||
          head.toUpperCase().startsWith('<!DOCTYPE SVG')) &&
      RegExp(r'<(?:[A-Za-z_][\w.-]*:)?svg(?:\s|/|>)').hasMatch(head)) {
    return 'image/svg+xml';
  }
  return null;
}

class NativeSvgData {
  const NativeSvgData(this.bytes, this.embeddedImages);
  final Uint8List bytes;
  final List<Uint8List> embeddedImages;
}

/// Prepares a preview copy only. Stored/uploaded/shared originals are untouched.
NativeSvgData prepareNativeSvg(Uint8List bytes) {
  if (bytes.length > 2 * 1024 * 1024) {
    throw const FormatException(
      'SVG超过原生预览2MiB上限 / SVG exceeds the 2 MiB preview bound',
    );
  }
  final text = utf8.decode(bytes);
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    throw const FormatException(
      'SVG包含不支持的DTD或实体 / SVG DTDs and entities are unsupported',
    );
  }
  final document = XmlDocument.parse(text);
  if (document.rootElement.name.local != 'svg' ||
      (document.rootElement.name.namespaceUri != null &&
          document.rootElement.name.namespaceUri !=
              'http://www.w3.org/2000/svg')) {
    throw const FormatException('不是有效的SVG文档 / Invalid SVG document');
  }
  if (document.descendants.any((node) => node is XmlProcessing)) {
    throw const FormatException(
      'SVG外部处理指令不受支持 / SVG processing instructions are unsupported',
    );
  }
  final embedded = <Uint8List>[];
  final ids = <String>{};
  final graph = <String, Set<String>>{'@root': {}};
  final stack = <(XmlElement, int, String)>[(document.rootElement, 0, '@root')];
  var count = 0;
  void reference(String from, String value) {
    if (!value.startsWith('#') || value.length < 2) {
      throw const FormatException(
        'SVG不允许加载外部资源 / SVG external resources are not loaded',
      );
    }
    graph.putIfAbsent(from, () => {}).add(value.substring(1));
  }

  void css(String from, String value) {
    if (value.contains('\\') ||
        RegExp(
          r'@\s*(import|font-face)',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const FormatException(
        'SVG包含不支持的外部CSS / External SVG CSS is unsupported',
      );
    }
    for (final match in RegExp(
      r'url\s*\((.*?)\)',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(value)) {
      var target = match.group(1)!.trim();
      if (target.length >= 2 &&
          ((target.startsWith('"') && target.endsWith('"')) ||
              (target.startsWith("'") && target.endsWith("'")))) {
        target = target.substring(1, target.length - 1);
      }
      reference(from, target);
    }
  }

  while (stack.isNotEmpty) {
    final (element, depth, parent) = stack.removeLast();
    if (++count > 50000 || depth > 256) {
      throw const FormatException(
        'SVG结构超过预览上限 / SVG structure exceeds preview limits',
      );
    }
    final name = element.name.local.toLowerCase();
    if ({
          'script',
          'foreignobject',
          'filter',
          'animatemotion',
          'animatetransform',
          'animate',
          'set',
          'discard',
        }.contains(name) ||
        name.startsWith('fe')) {
      throw const FormatException(
        'SVG包含暂不支持的脚本、滤镜或动画 / SVG scripts, filters or animation are unsupported',
      );
    }
    final id = element.getAttribute('id');
    var owner = parent;
    if (id != null && id.isNotEmpty) {
      if (!ids.add(id)) {
        throw const FormatException('SVG包含重复ID / Duplicate SVG IDs');
      }
      graph.putIfAbsent(parent, () => {}).add(id);
      graph.putIfAbsent(id, () => {});
      owner = id;
    }
    final remove = <XmlAttribute>[];
    for (final attribute in element.attributes) {
      final key = attribute.name.local.toLowerCase(),
          value = attribute.value.trim();
      if (key.startsWith('on') ||
          (key == 'base' && attribute.name.prefix == 'xml')) {
        throw const FormatException(
          'SVG包含不支持的事件或基地址 / SVG events and base references are unsupported',
        );
      }
      if (key == 'filter' && value.isNotEmpty && value != 'none') {
        throw const FormatException('SVG滤镜尚不支持 / SVG filters are unsupported');
      }
      if (key == 'href') {
        if (name == 'a') {
          remove.add(attribute);
          continue;
        }
        if (value.startsWith('#')) {
          reference(owner, value);
        } else if (name == 'image') {
          final match = RegExp(
            r'^data:image/(png|jpeg|gif|webp);base64,([A-Za-z0-9+/=\s]+)$',
            caseSensitive: false,
          ).firstMatch(value);
          if (match == null) {
            throw const FormatException(
              'SVG不允许加载外部图片 / External SVG images are not loaded',
            );
          }
          final data = base64.decode(
            match.group(2)!.replaceAll(RegExp(r'\s'), ''),
          );
          if (imageContentMime(data) !=
              'image/${match.group(1)!.toLowerCase()}') {
            throw const FormatException(
              'SVG内嵌图片格式不匹配 / Embedded SVG image type mismatch',
            );
          }
          embedded.add(data.asUnmodifiableView());
        } else {
          throw const FormatException(
            'SVG不允许加载外部引用 / External SVG references are not loaded',
          );
        }
      }
      css(owner, value);
    }
    element.attributes.removeWhere(remove.contains);
    if (name == 'style') css(owner, element.innerText);
    for (final child in element.childElements) {
      stack.add((child, depth + 1, owner));
    }
  }
  final colors = <String, int>{};
  void visit(String id, int depth) {
    if (depth > 256) {
      throw const FormatException(
        'SVG引用层级过深 / SVG reference nesting exceeds limit',
      );
    }
    if (colors[id] == 1) {
      throw const FormatException('SVG包含循环引用 / SVG contains cyclic references');
    }
    if (colors[id] == 2) return;
    colors[id] = 1;
    for (final next in graph[id] ?? <String>{}) {
      if (graph.containsKey(next)) visit(next, depth + 1);
    }
    colors[id] = 2;
  }

  visit('@root', 0);
  return NativeSvgData(
    Uint8List.fromList(
      utf8.encode(document.toXmlString()),
    ).asUnmodifiableView(),
    List.unmodifiable(embedded),
  );
}
