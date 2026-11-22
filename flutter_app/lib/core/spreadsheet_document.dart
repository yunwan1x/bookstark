import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

const spreadsheetMaxBytes = 5 * 1024 * 1024;
const spreadsheetMaxRows = 1048576;
const spreadsheetMaxColumns = 16384;

class SheetAddress {
  const SheetAddress(this.row, this.column);
  final int row, column;
  factory SheetAddress.parse(String text) {
    final match = RegExp(
      r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})$',
    ).firstMatch(text);
    if (match == null) throw const FormatException('Invalid cell address');
    var column = 0;
    for (final unit in match[1]!.toUpperCase().codeUnits) {
      column = column * 26 + unit - 64;
    }
    final row = int.parse(match[2]!);
    if (row > spreadsheetMaxRows || column > spreadsheetMaxColumns) {
      throw const FormatException('Cell address exceeds workbook bounds');
    }
    return SheetAddress(row - 1, column - 1);
  }
  String get a1 {
    if (row < 0 || row >= spreadsheetMaxRows) {
      throw RangeError.range(row, 0, spreadsheetMaxRows - 1);
    }
    return '${columnName(column)}${row + 1}';
  }

  static String columnName(int index) {
    if (index < 0 || index >= spreadsheetMaxColumns) {
      throw RangeError.range(index, 0, spreadsheetMaxColumns - 1);
    }
    var value = index + 1, result = '';
    while (value > 0) {
      value--;
      result = String.fromCharCode(65 + value % 26) + result;
      value ~/= 26;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SheetAddress && row == other.row && column == other.column;
  @override
  int get hashCode => Object.hash(row, column);
}

class SheetRange {
  const SheetRange(
    this.startRow,
    this.endRow,
    this.startColumn,
    this.endColumn,
  );
  factory SheetRange.between(SheetAddress a, SheetAddress b) => SheetRange(
    math.min(a.row, b.row),
    math.max(a.row, b.row),
    math.min(a.column, b.column),
    math.max(a.column, b.column),
  );
  final int startRow, endRow, startColumn, endColumn;
  bool contains(SheetAddress address) =>
      address.row >= startRow &&
      address.row <= endRow &&
      address.column >= startColumn &&
      address.column <= endColumn;
  SheetAddress get anchor => SheetAddress(startRow, startColumn);
}

bool _wellFormed(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length) return false;
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid workbook object');
  }
  return value;
}

String _identifier(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 2000 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid workbook identity');
  }
  return value;
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Invalid workbook dimension');
  }
  return value;
}

int _index(String key, int maximum) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(key)) {
    throw const FormatException('Invalid sparse cell index');
  }
  return _integer(int.tryParse(key), 0, maximum - 1);
}

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, child) {
        if (!_wellFormed(key)) {
          throw const FormatException('Invalid workbook Unicode');
        }
        return MapEntry(key, _freeze(child));
      }),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value is String && !_wellFormed(value) ||
      value is num && !value.isFinite) {
    throw const FormatException('Invalid workbook scalar');
  }
  return value;
}

void _checkSource(String source) {
  if (!_wellFormed(source) ||
      utf8.encode(source).length > spreadsheetMaxBytes) {
    throw const FormatException('Workbook exceeds source bounds');
  }
  var depth = 0, quoted = false, escaped = false;
  for (final unit in source.codeUnits) {
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
    } else if (unit == 123 || unit == 91) {
      if (++depth > 64) {
        throw const FormatException('Workbook nesting exceeds bound');
      }
    } else if (unit == 125 || unit == 93) {
      depth--;
    }
  }
}

class SpreadsheetCell {
  const SpreadsheetCell(this.raw);
  final Map<String, Object?> raw;
  Object? get value => raw['v'];
  String? get formula => raw['f'] is String && (raw['f'] as String).isNotEmpty
      ? raw['f'] as String
      : null;
  bool get requiresRichTextEditor => raw['p'] != null;
  bool get hasSharedFormula => raw['si'] != null && raw['si'] != '';
  bool get hasOpaqueInput =>
      value != null && value is! String && value is! num && value is! bool ||
      raw['f'] != null && raw['f'] is! String ||
      raw['t'] != null && !const {1, 2, 3, 4}.contains(raw['t']);
  String get text {
    final rich = raw['p'];
    if (rich is Map && rich['body'] is Map) {
      final stream = (rich['body'] as Map)['dataStream'];
      if (stream is String) {
        return stream.endsWith('\r\n')
            ? stream.substring(0, stream.length - 2)
            : stream;
      }
    }
    final scalar = value;
    if (scalar == null) return '';
    if (scalar is bool) return scalar ? 'TRUE' : 'FALSE';
    return scalar is String || scalar is num ? scalar.toString() : '';
  }
}

class SpreadsheetSheet {
  SpreadsheetSheet._(this.id, this.raw) {
    _identifier(raw['id']);
    if (raw['id'] != id) {
      throw const FormatException('Worksheet identity changed');
    }
    name = _identifier(raw['name']);
    rowCount = _integer(raw['rowCount'], 1, spreadsheetMaxRows);
    columnCount = _integer(raw['columnCount'], 1, spreadsheetMaxColumns);
    final matrix = raw['cellData'] == null
        ? const <String, Object?>{}
        : _map(raw['cellData']);
    var count = 0;
    for (final row in matrix.entries) {
      _index(row.key, rowCount);
      if (row.value == null) continue;
      for (final cell in _map(row.value).entries) {
        _index(cell.key, columnCount);
        if (++count > 250000) {
          throw const FormatException('Too many stored cells');
        }
        if (cell.value != null) _map(cell.value);
      }
    }
    final mergeData = raw['mergeData'];
    if (mergeData != null && mergeData is! List) {
      throw const FormatException('Invalid merge data');
    }
    merges = List<SheetRange>.unmodifiable(
      (mergeData as List? ?? const []).map((value) {
        final range = _map(value);
        final sr = _integer(range['startRow'], 0, rowCount - 1),
            er = _integer(range['endRow'], 0, rowCount - 1),
            sc = _integer(range['startColumn'], 0, columnCount - 1),
            ec = _integer(range['endColumn'], 0, columnCount - 1);
        if (sr > er || sc > ec) {
          throw const FormatException('Invalid merged cell bounds');
        }
        return SheetRange(sr, er, sc, ec);
      }),
    );
    _validateMerges(merges);
    _mergeIndex = _MergeIndex.build(merges);
    final freeze = raw['freeze'] == null
        ? const <String, Object?>{}
        : _map(raw['freeze']);
    frozenRows = _integer(freeze['ySplit'] ?? 0, 0, rowCount);
    frozenColumns = _integer(freeze['xSplit'] ?? 0, 0, columnCount);
  }
  final String id;
  final Map<String, Object?> raw;
  late final String name;
  late final int rowCount, columnCount, frozenRows, frozenColumns;
  late final List<SheetRange> merges;
  late final _MergeIndex? _mergeIndex;
  bool get hidden =>
      raw['hidden'] == 1 || raw['hidden'] == true || raw['hidden'] == 2;
  SpreadsheetCell cell(SheetAddress address) {
    if (address.row < 0 ||
        address.row >= rowCount ||
        address.column < 0 ||
        address.column >= columnCount) {
      throw const FormatException('Cell is outside worksheet');
    }
    final data = raw['cellData'];
    if (data is! Map) return const SpreadsheetCell({});
    final row = data[address.row.toString()];
    if (row is! Map) return const SpreadsheetCell({});
    final value = row[address.column.toString()];
    return SpreadsheetCell(value == null ? const {} : _map(value));
  }

  SheetRange? mergeAt(SheetAddress address) => _mergeIndex?.find(address);
}

void _validateMerges(List<SheetRange> ranges) {
  final ordered = List<SheetRange>.of(ranges)
    ..sort((a, b) => a.startRow.compareTo(b.startRow));
  final active = SplayTreeMap<int, SheetRange>(),
      ends = SplayTreeMap<int, Set<int>>();
  for (final range in ordered) {
    while (ends.isNotEmpty && ends.firstKey()! < range.startRow) {
      for (final column in ends.remove(ends.firstKey())!) {
        active.remove(column);
      }
    }
    final before = active.lastKeyBefore(range.startColumn + 1),
        after = active.firstKeyAfter(range.startColumn - 1);
    if (before != null && active[before]!.endColumn >= range.startColumn ||
        after != null && after <= range.endColumn) {
      throw const FormatException('Overlapping merged cells');
    }
    active[range.startColumn] = range;
    (ends[range.endRow] ??= <int>{}).add(range.startColumn);
  }
}

class _MergeIndex {
  _MergeIndex(this.center, this.middle, this.left, this.right);
  final int center;
  final List<SheetRange> middle;
  final _MergeIndex? left, right;
  static _MergeIndex? build(List<SheetRange> ranges) {
    if (ranges.isEmpty) return null;
    final centers = ranges.map((r) => (r.startRow + r.endRow) ~/ 2).toList()
      ..sort();
    final center = centers[centers.length ~/ 2];
    final left = <SheetRange>[],
        right = <SheetRange>[],
        middle = <SheetRange>[];
    for (final r in ranges) {
      if (r.endRow < center) {
        left.add(r);
      } else if (r.startRow > center) {
        right.add(r);
      } else {
        middle.add(r);
      }
    }
    middle.sort((a, b) => a.startColumn.compareTo(b.startColumn));
    return _MergeIndex(center, middle, build(left), build(right));
  }

  SheetRange? find(SheetAddress address) {
    var low = 0, high = middle.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (middle[mid].startColumn <= address.column) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 && middle[low - 1].contains(address)) return middle[low - 1];
    return address.row < center
        ? left?.find(address)
        : address.row > center
        ? right?.find(address)
        : null;
  }
}

class SpreadsheetDocument {
  SpreadsheetDocument._(this.source, this.raw) {
    id = _identifier(raw['id']);
    final order = raw['sheetOrder'], all = _map(raw['sheets']);
    if (order is! List || order.isEmpty || order.length > 256) {
      throw const FormatException('Invalid worksheet order');
    }
    final ids = <String>{};
    sheets = List<SpreadsheetSheet>.unmodifiable(
      order.map((value) {
        final key = _identifier(value);
        if (!ids.add(key) || !all.containsKey(key)) {
          throw const FormatException('Invalid worksheet membership');
        }
        return SpreadsheetSheet._(key, _map(all[key]));
      }),
    );
    if (raw['styles'] != null) _map(raw['styles']);
  }
  factory SpreadsheetDocument.parse(String source) {
    _checkSource(source);
    return SpreadsheetDocument._(source, _map(_freeze(jsonDecode(source))));
  }
  factory SpreadsheetDocument.empty({
    required String workbookId,
    required String sheetId,
    String sheetName = 'Sheet1',
    String locale = 'zhCN',
  }) => SpreadsheetDocument.parse(
    jsonEncode({
      'id': workbookId,
      'name': '',
      'appVersion': '0.25.1',
      'locale': locale,
      'styles': {},
      'sheetOrder': [sheetId],
      'sheets': {
        sheetId: {
          'id': sheetId,
          'name': sheetName,
          'tabColor': '',
          'hidden': 0,
          'rowCount': 1000,
          'columnCount': 26,
          'zoomRatio': 1,
          'freeze': {
            'startRow': -1,
            'startColumn': -1,
            'ySplit': 0,
            'xSplit': 0,
          },
          'scrollTop': 0,
          'scrollLeft': 0,
          'defaultColumnWidth': 73,
          'defaultRowHeight': 23,
          'mergeData': [],
          'cellData': {},
          'rowData': {},
          'columnData': {},
          'showGridlines': 1,
          'rightToLeft': 0,
        },
      },
    }),
  );
  final String source;
  final Map<String, Object?> raw;
  late final String id;
  late final List<SpreadsheetSheet> sheets;
  SpreadsheetSheet sheet(String id) => sheets.firstWhere(
    (s) => s.id == id,
    orElse: () =>
        throw const FormatException('Worksheet is not in workbook order'),
  );

  /// Inline styles are accepted by Univer; resolve named styles without
  /// mutating the shared style table or dropping unknown style properties.
  Map<String, Object?> cellStyle(String sheetId, SheetAddress address) {
    final value = sheet(sheetId).cell(address).raw['s'];
    if (value is Map<String, Object?>) return value;
    final styles = raw['styles'];
    if (value is String &&
        styles is Map &&
        styles[value] is Map<String, Object?>) {
      return styles[value] as Map<String, Object?>;
    }
    return const {};
  }

  SpreadsheetDocument withCellStyle(
    String sheetId,
    SheetAddress address,
    Map<String, Object?> patch,
  ) {
    if (patch.isEmpty) return this;
    final target = sheet(sheetId);
    final merged = target.mergeAt(address);
    if (merged != null && merged.anchor != address) {
      throw const FormatException('Style merged anchor only');
    }
    final old = target.cell(address);
    final style = Map<String, Object?>.of(cellStyle(sheetId, address));
    for (final item in patch.entries) {
      if (item.value == null) {
        style.remove(item.key);
      } else {
        style[item.key] = item.value;
      }
    }
    final matrix = Map<String, Object?>.of(
      target.raw['cellData'] as Map<String, Object?>? ?? const {},
    );
    final key = address.row.toString();
    final row = Map<String, Object?>.of(
      matrix[key] as Map<String, Object?>? ?? const {},
    );
    row[address.column.toString()] = {...old.raw, 's': style};
    matrix[key] = row;
    return _replaceSheet(sheetId, {...target.raw, 'cellData': matrix});
  }

  SpreadsheetDocument _replaceSheet(
    String sheetId,
    Map<String, Object?> value,
  ) => SpreadsheetDocument.parse(
    jsonEncode({
      ...raw,
      'sheets': {..._map(raw['sheets']), sheetId: value},
    }),
  );

  String _validatedSheetName(String sheetId, String name) {
    name = name.trim();
    if (name.isEmpty ||
        name.length > 31 ||
        !_wellFormed(name) ||
        RegExp(r'[\\/?:*\[\]\x00-\x1f]').hasMatch(name) ||
        sheets.any(
          (s) => s.id != sheetId && s.name.toLowerCase() == name.toLowerCase(),
        )) {
      throw const FormatException('Invalid or duplicate worksheet name');
    }
    return name;
  }

  SpreadsheetDocument renameSheet(String sheetId, String name) {
    name = _validatedSheetName(sheetId, name);
    final target = sheet(sheetId);
    if (target.name == name) return this;
    // Renaming references requires the formula engine. Never leave a dangling
    // reference by rewriting only the tab label.
    if (sheets.any((s) => _hasFormulas(s))) {
      throw UnsupportedError('Formula-aware worksheet rename is required');
    }
    return target.name == name
        ? this
        : _replaceSheet(sheetId, {...target.raw, 'name': name});
  }

  static bool _hasFormulas(SpreadsheetSheet sheet) {
    final matrix = sheet.raw['cellData'];
    if (matrix is! Map) return false;
    for (final row in matrix.values) {
      if (row is! Map) continue;
      for (final cell in row.values) {
        if (cell is Map && (cell['f'] != null || cell['si'] != null)) {
          return true;
        }
      }
    }
    return false;
  }

  SpreadsheetDocument setSheetHidden(String sheetId, bool hidden) {
    final target = sheet(sheetId);
    if (hidden &&
        !target.hidden &&
        sheets.where((s) => !s.hidden).length <= 1) {
      throw const FormatException('At least one worksheet must remain visible');
    }
    return _replaceSheet(sheetId, {...target.raw, 'hidden': hidden ? 1 : 0});
  }

  SpreadsheetDocument addSheet({
    required String sheetId,
    required String name,
  }) {
    _identifier(sheetId);
    if (_map(raw['sheets']).containsKey(sheetId) || sheets.length >= 256) {
      throw const FormatException('Worksheet identity or count is invalid');
    }
    name = _validatedSheetName(sheetId, name);
    final fresh = SpreadsheetDocument.empty(
      workbookId: id,
      sheetId: sheetId,
      sheetName: name,
    ).sheets.single;
    final result = SpreadsheetDocument.parse(
      jsonEncode({
        ...raw,
        'sheetOrder': [...sheets.map((s) => s.id), sheetId],
        'sheets': {..._map(raw['sheets']), sheetId: fresh.raw},
      }),
    );
    return result;
  }

  SpreadsheetDocument withCellValue(
    String sheetId,
    SheetAddress address,
    Object? value, {
    String? formula,
  }) {
    if (value != null && value is! String && value is! num && value is! bool ||
        value is num && !value.isFinite ||
        value is String && !_wellFormed(value) ||
        formula != null &&
            (!_wellFormed(formula) || !formula.startsWith('='))) {
      throw const FormatException('Invalid cell input');
    }
    final target = sheet(sheetId), old = target.cell(address);
    if (old.value == value && old.formula == formula) return this;
    if (old.requiresRichTextEditor ||
        old.hasSharedFormula ||
        old.hasOpaqueInput) {
      throw UnsupportedError(
        'This cell requires its original rich/shared formula editor',
      );
    }
    final merge = target.mergeAt(address);
    if (merge != null && merge.anchor != address) {
      throw const FormatException('Edit merged anchor only');
    }
    final cell = Map<String, Object?>.of(old.raw);
    if (formula == null) {
      cell.remove('f');
    } else {
      cell['f'] = formula;
    }
    if (value == null) {
      cell.remove('v');
      cell.remove('t');
    } else {
      cell['v'] = value;
      cell['t'] = value is String
          ? 1
          : value is bool
          ? 3
          : 2;
    }
    final matrix = Map<String, Object?>.of(
      target.raw['cellData'] == null ? const {} : _map(target.raw['cellData']),
    );
    final key = address.row.toString();
    final row = Map<String, Object?>.of(
      matrix[key] == null ? const {} : _map(matrix[key]),
    );
    row[address.column.toString()] = cell;
    matrix[key] = row;
    final updated = Map<String, Object?>.of(target.raw)..['cellData'] = matrix;
    final all = Map<String, Object?>.of(_map(raw['sheets']))
      ..[sheetId] = updated;
    final root = Map<String, Object?>.of(raw)..['sheets'] = all;
    return SpreadsheetDocument.parse(jsonEncode(root));
  }
}
