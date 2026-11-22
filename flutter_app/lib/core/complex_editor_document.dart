import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'spreadsheet_document.dart';

enum ComplexEditorKind {
  markdown,
  html,
  spreadsheet,
  drawing,
  mindmap,
  richdoc,
  presentation;

  int get maxBytes =>
      (this == presentation || this == markdown ? 20 : 5) * 1024 * 1024;
  static ComplexEditorKind parse(String value) => values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => throw const FormatException('Unknown complex editor type'),
  );
}

/// Exact source identity and validation before an existing web engine sees it.
/// Invalid legacy content remains an error, never a replacement blank document.
class ComplexEditorDocument {
  ComplexEditorDocument._(this.kind, this.source, this.byteLength, this.digest);
  final ComplexEditorKind kind;
  final String source, digest;
  final int byteLength;

  /// Validate metadata text without changing its type or allocating a document.
  static void validateText(String text) => _unicode(text);

  factory ComplexEditorDocument.fromBytes(
    ComplexEditorKind kind,
    List<int> bytes,
  ) {
    if (bytes.length > kind.maxBytes) {
      throw const FormatException('Complex document exceeds byte limit');
    }
    var offset = 0;
    var bomCount = 0;
    while (offset + 2 < bytes.length &&
        bytes[offset] == 239 &&
        bytes[offset + 1] == 187 &&
        bytes[offset + 2] == 191) {
      offset += 3;
      bomCount++;
    }
    // Dart's UTF-8 decoder consumes one leading BOM. Restore every leading
    // BOM explicitly after strict decoding so fromBytes preserves exact text.
    final text = utf8.decode(
      offset == 0 ? bytes : bytes.sublist(offset),
      allowMalformed: false,
    );
    final prefix = ''.padLeft(bomCount, '\ufeff');
    return ComplexEditorDocument.parse(kind, '$prefix$text');
  }
  factory ComplexEditorDocument.parse(ComplexEditorKind kind, String source) {
    _unicode(source);
    final bytes = utf8.encode(source);
    if (bytes.length > kind.maxBytes) {
      throw const FormatException('Complex document exceeds byte limit');
    }
    if (kind == ComplexEditorKind.spreadsheet) {
      SpreadsheetDocument.parse(source);
    } else if (kind != ComplexEditorKind.html &&
        kind != ComplexEditorKind.markdown) {
      _depth(source);
      final data = jsonDecode(source);
      _scalars(data);
      switch (kind) {
        case ComplexEditorKind.drawing:
          final elements = data is List
              ? data
              : data is Map
              ? data['elements']
              : null;
          if (elements is! List || elements.any((e) => e is! Map)) {
            throw const FormatException('Invalid drawing elements');
          }
        case ComplexEditorKind.mindmap:
          final node = data is Map ? data['nodeData'] : null;
          if (node is! Map ||
              node['topic'] is! String ||
              node['id'] is! String ||
              (node['id'] as String).isEmpty) {
            throw const FormatException('Invalid mindmap root');
          }
        case ComplexEditorKind.richdoc:
          if (data is! Map ||
              data['schema'] != 'bookstark-richdoc' ||
              data['schema_version'] != 1 ||
              data['data'] is! Map ||
              (data['data'] as Map)['main'] is! List) {
            throw const FormatException('Invalid rich-document envelope');
          }
        case ComplexEditorKind.presentation:
          if (data is! Map ||
              !_positive(data['width']) ||
              !_positive(data['height']) ||
              data['slides'] is! List ||
              (data['slides'] as List).isEmpty) {
            throw const FormatException('Invalid presentation canvas');
          }
          final ids = <String>{};
          for (final slide in data['slides'] as List) {
            if (slide is! Map ||
                slide['id'] is! String ||
                (slide['id'] as String).isEmpty ||
                !ids.add(slide['id'] as String) ||
                slide['elements'] is! List) {
              throw const FormatException(
                'Invalid presentation slide identity',
              );
            }
          }
        case ComplexEditorKind.markdown:
        case ComplexEditorKind.html:
        case ComplexEditorKind.spreadsheet:
          throw StateError('Source validated by a different branch');
      }
    }
    return ComplexEditorDocument._(
      kind,
      source,
      bytes.length,
      sha256.convert(bytes).toString(),
    );
  }
  bool same(ComplexEditorDocument other) =>
      kind == other.kind && digest == other.digest && source == other.source;
  ComplexEditorDocument withSource(String value) =>
      value == source ? this : ComplexEditorDocument.parse(kind, value);
}

bool _positive(Object? value) => value is num && value.isFinite && value > 0;
void _unicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= text.length ||
          text.codeUnitAt(i) < 0xdc00 ||
          text.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid source Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid source Unicode');
    }
  }
}

void _scalars(Object? value) {
  if (value is num && !value.isFinite) {
    throw const FormatException('Invalid document number');
  }
  if (value is String) _unicode(value);
  if (value is Map) {
    for (final item in value.entries) {
      _unicode(item.key as String);
      _scalars(item.value);
    }
  }
  if (value is List) {
    for (final item in value) {
      _scalars(item);
    }
  }
}

void _depth(String text) {
  var depth = 0, quoted = false, escaped = false;
  for (final unit in text.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    } else if (unit == 91 || unit == 123) {
      if (++depth > 64) {
        throw const FormatException('Document depth exceeds limit');
      }
    } else if (unit == 93 || unit == 125) {
      depth--;
    }
  }
}
