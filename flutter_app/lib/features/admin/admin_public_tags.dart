import 'dart:convert';

enum AdminPublicTagKind {
  article('article', '文章'),
  note('note', '笔记'),
  book('book', '书籍'),
  bookmark('bookmark', '书签');

  const AdminPublicTagKind(this.value, this.label);
  final String value, label;
  String get key => 'public_feed_tags_$value';
}

/// Parses exactly the server's config shape; unknown object fields are retained.
class AdminPublicTagConfig {
  AdminPublicTagConfig._(this.raw, this._object, this.labels);
  final String raw;
  final Map<String, Object?> _object;
  final List<String> labels;
  String get mode => _object['mode']! as String;
  bool get multilineLabels =>
      labels.any((label) => label.contains('\r') || label.contains('\n'));

  factory AdminPublicTagConfig.parse(String raw) {
    if (utf8.encode(raw).length > 32000) {
      throw const FormatException('标签配置不能超过 32000 字节。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('标签配置不是有效 JSON，请核对原文。');
    }
    if (decoded is! Map<String, Object?> ||
        !{'auto', 'manual'}.contains(decoded['mode'])) {
      throw const FormatException('展示方式必须为 auto 或 manual。');
    }
    final rawLabels = decoded['labels'];
    if (rawLabels != null && rawLabels is! List) {
      throw const FormatException('labels 必须为数组或 null。');
    }
    final labels = <String>[];
    final seen = <String>{};
    for (final value in (rawLabels as List? ?? const [])) {
      if (value is! String ||
          value.isEmpty ||
          utf8.encode(value).length > 200 ||
          !seen.add(value)) {
        throw const FormatException('标签不能为空、重复或超过 200 字节。');
      }
      labels.add(value);
    }
    if (labels.length > 100) {
      throw const FormatException('标签最多 100 项。');
    }
    return AdminPublicTagConfig._(
      raw,
      Map.unmodifiable(decoded),
      List.unmodifiable(labels),
    );
  }

  factory AdminPublicTagConfig.decodeForEditing(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> ||
          !{'auto', 'manual'}.contains(decoded['mode'])) {
        throw const FormatException('展示方式无效。');
      }
      final values = decoded['labels'];
      if (values != null &&
          (values is! List || values.any((value) => value is! String))) {
        throw const FormatException('标签数组无效。');
      }
      return AdminPublicTagConfig._(
        raw,
        Map.unmodifiable(decoded),
        List<String>.unmodifiable(values as List? ?? const []),
      );
    } catch (_) {
      throw const FormatException('配置结构无法使用普通表单，请在高级原文中修正。');
    }
  }

  static String create(String mode) {
    if (!{'auto', 'manual'}.contains(mode)) {
      throw const FormatException('展示方式无效。');
    }
    return jsonEncode({'mode': mode, 'labels': <String>[]});
  }

  String changeMode(String mode) {
    if (!{'auto', 'manual'}.contains(mode)) {
      throw const FormatException('展示方式无效。');
    }
    if (this.mode == mode) return raw;
    return jsonEncode({..._object, 'mode': mode});
  }

  String changeLabels(String text) {
    final lines = text.split(RegExp(r'\r\n|\n|\r'));
    // One final line separator terminates the editor; interior blanks are errors.
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final labels = text.isEmpty ? <String>[] : lines;
    final changed = jsonEncode({..._object, 'labels': labels});
    return changed;
  }

  @override
  String toString() => 'AdminPublicTagConfig(values: [redacted])';
}
