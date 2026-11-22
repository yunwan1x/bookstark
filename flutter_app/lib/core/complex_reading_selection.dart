import 'dart:convert';
import 'complex_editor_document.dart';

int _i(Object? n, [int max = 1000000]) {
  if (n is! int || n < 0 || n > max) {
    throw const FormatException('Invalid engine selection index');
  }
  return n;
}

List<int> _path(Object? p) {
  if (p is! List || p.length > 64) {
    throw const FormatException('Invalid DOM selection path');
  }
  return [for (final n in p) _i(n, 100000)];
}

String _id(Object? id) {
  if (id is! String || id.isEmpty || id.length > 256) {
    throw const FormatException('Invalid selection ID');
  }
  ComplexEditorDocument.validateText(id);
  return id;
}

List<String> _ids(Object? ids) {
  if (ids is! List || ids.isEmpty || ids.length > 128) {
    throw const FormatException('Invalid selected IDs');
  }
  final result = [for (final id in ids) _id(id)];
  if (result.toSet().length != result.length) {
    throw const FormatException('Repeated selected ID');
  }
  return result;
}

/// Actual engine coordinates, separate from its reading viewport anchor.
class ComplexReadingSelection {
  ComplexReadingSelection._(this.kind, this.value);
  final ComplexEditorKind kind;
  final Map<String, Object?> value;
  bool same(ComplexReadingSelection other) =>
      kind == other.kind && jsonEncode(value) == jsonEncode(other.value);
  factory ComplexReadingSelection.parse(ComplexEditorKind kind, Object? raw) {
    if (raw is! Map || utf8.encode(jsonEncode(raw)).length > 32768) {
      throw const FormatException('Invalid engine selection');
    }
    final v = Map<String, Object?>.from(raw), type = v['type'];
    bool keys(Set<String> allowed) =>
        v.keys.toSet().difference(allowed).isEmpty &&
        allowed.difference(v.keys.toSet()).isEmpty;
    if (kind == ComplexEditorKind.html &&
        type == 'htmlDomRange' &&
        keys({'type', 'startPath', 'startOffset', 'endPath', 'endOffset'})) {
      return ComplexReadingSelection._(kind, {
        'type': type,
        'startPath': _path(v['startPath']),
        'startOffset': _i(v['startOffset'], 100000000),
        'endPath': _path(v['endPath']),
        'endOffset': _i(v['endOffset'], 100000000),
      });
    }
    if (kind == ComplexEditorKind.richdoc && type == 'canvasRange') {
      const allowed = {
        'type',
        'startIndex',
        'endIndex',
        'zone',
        'tableId',
        'startTdIndex',
        'endTdIndex',
        'startTrIndex',
        'endTrIndex',
        'isCrossRowCol',
      };
      if (v.keys.toSet().difference(allowed).isNotEmpty ||
          !{'main', 'header', 'footer'}.contains(v['zone'])) {
        throw const FormatException('Invalid canvas selection');
      }
      final start = _i(v['startIndex']), end = _i(v['endIndex']);
      if (end <= start) throw const FormatException('Empty canvas selection');
      final out = <String, Object?>{
        'type': type,
        'startIndex': start,
        'endIndex': end,
        'zone': v['zone'],
      };
      for (final key in [
        'startTdIndex',
        'endTdIndex',
        'startTrIndex',
        'endTrIndex',
      ]) {
        if (v[key] != null) out[key] = _i(v[key]);
      }
      if (v['tableId'] != null) out['tableId'] = _id(v['tableId']);
      if (v.containsKey('isCrossRowCol')) {
        if (v['isCrossRowCol'] is! bool) {
          throw const FormatException('Invalid table selection');
        }
        out['isCrossRowCol'] = v['isCrossRowCol'];
      }
      return ComplexReadingSelection._(kind, out);
    }
    if (kind == ComplexEditorKind.spreadsheet &&
        type == 'sheetRange' &&
        keys({
          'type',
          'sheetId',
          'startRow',
          'endRow',
          'startColumn',
          'endColumn',
        })) {
      final sr = _i(v['startRow'], 1048575),
          er = _i(v['endRow'], 1048575),
          sc = _i(v['startColumn'], 16383),
          ec = _i(v['endColumn'], 16383);
      if (er < sr || ec < sc || (er - sr + 1) * (ec - sc + 1) > 4096) {
        throw const FormatException('Invalid bounded cell selection');
      }
      return ComplexReadingSelection._(kind, {
        'type': type,
        'sheetId': _id(v['sheetId']),
        'startRow': sr,
        'endRow': er,
        'startColumn': sc,
        'endColumn': ec,
      });
    }
    if ((kind == ComplexEditorKind.drawing && type == 'drawingElements' ||
            kind == ComplexEditorKind.mindmap && type == 'mindmapNodes') &&
        keys({'type', 'ids'})) {
      return ComplexReadingSelection._(kind, {
        'type': type,
        'ids': _ids(v['ids']),
      });
    }
    if (kind == ComplexEditorKind.presentation &&
        type == 'presentationSlide' &&
        keys({'type', 'slideId'})) {
      return ComplexReadingSelection._(kind, {
        'type': type,
        'slideId': _id(v['slideId']),
      });
    }
    throw const FormatException('Unsupported actual engine selection');
  }
}
