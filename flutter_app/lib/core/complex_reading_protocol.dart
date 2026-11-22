import 'complex_reading_selection.dart';
import 'dart:convert';
import 'complex_editor_document.dart';

class ComplexReadingIdentity {
  const ComplexReadingIdentity({
    required this.bookId,
    required this.documentId,
    required this.kind,
    required this.fullFingerprint,
    required this.sourceDigest,
  });
  final int bookId, documentId;
  final ComplexEditorKind kind;
  final String fullFingerprint, sourceDigest;
  Map<String, Object?> toJson() => {
    'version': 1,
    'bookId': bookId,
    'documentId': documentId,
    'kind': kind.name,
    'fullFingerprint': fullFingerprint,
    'sourceDigest': sourceDigest,
  };
  void validate() {
    if (bookId <= 0 ||
        documentId <= 0 ||
        bookId > 9007199254740991 ||
        documentId > 9007199254740991 ||
        kind == ComplexEditorKind.markdown ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fullFingerprint) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest)) {
      throw const FormatException('Invalid reading identity');
    }
  }

  bool same(ComplexReadingIdentity other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

class ComplexReadingBinding {
  ComplexReadingBinding(
    this.identity, {
    required this.runtimeLease,
    required this.generation,
  }) {
    identity.validate();
    if (runtimeLease.length < 16 ||
        runtimeLease.length > 128 ||
        generation < 1) {
      throw const FormatException('Invalid runtime binding');
    }
  }
  final ComplexReadingIdentity identity;
  final String runtimeLease;
  final int generation;
  Map<String, Object?> toJson() => {
    ...identity.toJson(),
    'runtimeLease': runtimeLease,
    'generation': generation,
  };
  void verify(Object? raw) {
    if (raw is! Map ||
        raw.length != toJson().length ||
        !toJson().entries.every((e) => raw[e.key] == e.value)) {
      throw const FormatException('Reading result belongs to another runtime');
    }
  }
}

int _number(Object? value, [int max = 1000000000]) {
  if (value is! int || value < 0 || value > max) {
    throw const FormatException('Invalid reading coordinate');
  }
  return value;
}

num _signed(Object? v) {
  if (v is! num || !v.isFinite || v.abs() > 1000000000) {
    throw const FormatException('Invalid viewport coordinate');
  }
  return v;
}

num _scale(Object? v) {
  if (v is! num || !v.isFinite || v < .1 || v > 30) {
    throw const FormatException('Invalid viewport scale');
  }
  return v;
}

List<String> _ids(Object? v) {
  if (v is! List ||
      v.length > 128 ||
      v.any((n) => n is! String || n.isEmpty || n.length > 256)) {
    throw const FormatException('Invalid selected IDs');
  }
  final out = List<String>.from(v);
  if (out.toSet().length != out.length) {
    throw const FormatException('Duplicate selected IDs');
  }
  return out;
}

/// No generic URL/selector/script payload: only per-engine validated coordinates.
class ComplexReadingAnchor {
  ComplexReadingAnchor._(this.kind, this.value);
  final ComplexEditorKind kind;
  final Map<String, Object?> value;
  factory ComplexReadingAnchor.parse(ComplexEditorKind kind, Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid reading anchor');
    late final Map<String, Object?> v;
    try {
      if (utf8.encode(jsonEncode(raw)).length > 16384) {
        throw const FormatException('Invalid reading anchor');
      }
      v = Map<String, Object?>.from(raw);
    } on FormatException {
      rethrow;
    } on JsonUnsupportedObjectError {
      throw const FormatException('Invalid reading anchor');
    } on TypeError {
      throw const FormatException('Invalid reading anchor');
    }
    final type = v['type'];
    if (kind == ComplexEditorKind.html && type == 'htmlDomScroll') {
      if (v.keys.toSet().difference({'type', 'scrolls'}).isNotEmpty ||
          v['scrolls'] is! List ||
          (v['scrolls'] as List).length > 32) {
        throw const FormatException('Invalid DOM reading anchor');
      }
      final rows = <Object?>[];
      for (final rawRow in v['scrolls'] as List) {
        if (rawRow is! Map ||
            rawRow.keys.toSet().difference({
              'path',
              'top',
              'left',
            }).isNotEmpty ||
            rawRow['path'] is! List ||
            (rawRow['path'] as List).length > 64) {
          throw const FormatException('Invalid DOM path');
        }
        rows.add({
          'path': [for (final n in rawRow['path'] as List) _number(n, 100000)],
          'top': _number(rawRow['top']),
          'left': _number(rawRow['left']),
        });
      }
      return ComplexReadingAnchor._(kind, {'type': type, 'scrolls': rows});
    }
    if (kind == ComplexEditorKind.richdoc &&
        type == 'richdocViewport' &&
        v.keys.toSet().difference({'type', 'top', 'left'}).isEmpty) {
      return ComplexReadingAnchor._(kind, {
        'type': type,
        'top': _number(v['top']),
        'left': _number(v['left']),
      });
    }
    if (kind == ComplexEditorKind.spreadsheet && type == 'sheetViewportCell') {
      if (v.keys.toSet().difference({
            'type',
            'sheetId',
            'row',
            'column',
            'range',
          }).isNotEmpty ||
          v['sheetId'] is! String ||
          (v['sheetId'] as String).isEmpty ||
          (v['sheetId'] as String).length > 256) {
        throw const FormatException('Invalid sheet anchor');
      }
      Map<String, Object?>? range;
      if (v['range'] != null) {
        if (v['range'] is! Map) {
          throw const FormatException('Invalid sheet range');
        }
        final r = Map<String, Object?>.from(v['range'] as Map);
        if (r.keys.toSet().difference({
          'startRow',
          'endRow',
          'startColumn',
          'endColumn',
        }).isNotEmpty) {
          throw const FormatException('Invalid sheet range');
        }
        range = {
          'startRow': _number(r['startRow'], 1048575),
          'endRow': _number(r['endRow'], 1048575),
          'startColumn': _number(r['startColumn'], 16383),
          'endColumn': _number(r['endColumn'], 16383),
        };
        if ((range['startRow'] as int) > (range['endRow'] as int) ||
            (range['startColumn'] as int) > (range['endColumn'] as int)) {
          throw const FormatException('Invalid sheet range order');
        }
      }
      return ComplexReadingAnchor._(kind, {
        'type': type,
        'sheetId': v['sheetId'],
        'row': _number(v['row'], 1048575),
        'column': _number(v['column'], 16383),
        'range': range,
      });
    }
    if (kind == ComplexEditorKind.drawing &&
        type == 'drawingViewport' &&
        v.keys.toSet().difference({
          'type',
          'x',
          'y',
          'zoom',
          'elementIds',
        }).isEmpty) {
      return ComplexReadingAnchor._(kind, {
        'type': type,
        'x': _signed(v['x']),
        'y': _signed(v['y']),
        'zoom': _scale(v['zoom']),
        'elementIds': _ids(v['elementIds']),
      });
    }
    if (kind == ComplexEditorKind.mindmap &&
        type == 'mindmapViewport' &&
        v.keys.toSet().difference({
          'type',
          'x',
          'y',
          'scale',
          'nodeIds',
        }).isEmpty) {
      return ComplexReadingAnchor._(kind, {
        'type': type,
        'x': _signed(v['x']),
        'y': _signed(v['y']),
        'scale': _scale(v['scale']),
        'nodeIds': _ids(v['nodeIds']),
      });
    }
    if (kind == ComplexEditorKind.presentation &&
        type == 'presentationSlide' &&
        v.keys.toSet().difference({'type', 'slideId'}).isEmpty &&
        v['slideId'] is String &&
        (v['slideId'] as String).isNotEmpty &&
        (v['slideId'] as String).length <= 256) {
      return ComplexReadingAnchor._(kind, {
        'type': type,
        'slideId': v['slideId'],
      });
    }
    throw const FormatException('Unsupported engine reading anchor');
  }
}

enum ComplexReadingSelectionKind { text, cells, elements, nodes, slide, none }

class ComplexReadingCapture {
  const ComplexReadingCapture({
    required this.text,
    required this.anchor,
    required this.supported,
    this.selectionKind = ComplexReadingSelectionKind.text,
    this.selection,
  });
  final String text;
  final ComplexReadingAnchor? anchor;
  final bool supported;
  final ComplexReadingSelectionKind selectionKind;
  final ComplexReadingSelection? selection;
  factory ComplexReadingCapture.parse(
    ComplexReadingBinding binding,
    Object? raw,
  ) {
    if (raw is! Map ||
        (raw.length != 5 && raw.length != 6) ||
        raw.keys.toSet().difference({
          'binding',
          'text',
          'anchor',
          'supported',
          'selectionKind',
          'selection',
        }).isNotEmpty ||
        utf8.encode(jsonEncode(raw)).length > 65536) {
      throw const FormatException('Reading result too large');
    }
    binding.verify(raw['binding']);
    final text = raw['text'];
    if (text is! String ||
        utf8.encode(text).length > 32768 ||
        raw['supported'] is! bool) {
      throw const FormatException('Invalid selected text');
    }
    ComplexEditorDocument.validateText(text);
    final supported = raw['supported'] as bool;
    final expected = supported
        ? switch (binding.identity.kind) {
            ComplexEditorKind.html || ComplexEditorKind.richdoc => 'text',
            ComplexEditorKind.spreadsheet => 'cells',
            ComplexEditorKind.drawing => 'elements',
            ComplexEditorKind.mindmap => 'nodes',
            ComplexEditorKind.presentation => 'slide',
            _ => 'none',
          }
        : 'none';
    if (raw['selectionKind'] != expected) {
      throw const FormatException('Wrong engine selection kind');
    }
    final selectionKind = ComplexReadingSelectionKind.values.byName(expected);
    if (!supported && (text.isNotEmpty || raw['anchor'] != null)) {
      throw const FormatException(
        'Unsupported reading capability returned data',
      );
    }
    return ComplexReadingCapture(
      text: text,
      supported: supported,
      selectionKind: selectionKind,
      selection: raw['selection'] == null
          ? null
          : ComplexReadingSelection.parse(
              binding.identity.kind,
              raw['selection'],
            ),
      anchor: raw['anchor'] == null
          ? null
          : ComplexReadingAnchor.parse(binding.identity.kind, raw['anchor']),
    );
  }
}
