import 'dart:convert';
import 'spreadsheet_document.dart';

/// Minimal, data-only protocol for the native calculator. Original snapshots
/// and all metadata stay in Dart; formula results are never treated as a save.
class SpreadsheetCalculationInput {
  SpreadsheetCalculationInput._(this.document, this.payload, this.formulas);
  final SpreadsheetDocument document;
  final String payload;
  final Map<String, String> formulas;
  factory SpreadsheetCalculationInput.fromDocument(
    SpreadsheetDocument document,
  ) {
    final formulas = <String, String>{};
    var count = 0;
    final sheets = <Map<String, Object?>>[];
    for (final sheet in document.sheets) {
      final cells = <Map<String, Object?>>[];
      final matrix = sheet.raw['cellData'];
      if (matrix is Map) {
        for (final row in matrix.entries) {
          if (row.value is! Map) continue;
          for (final entry in (row.value as Map).entries) {
            if (entry.value == null) continue;
            final address = SheetAddress(
              int.parse(row.key as String),
              int.parse(entry.key as String),
            );
            final cell = sheet.cell(address);
            if (cell.hasOpaqueInput || cell.hasSharedFormula) {
              throw UnsupportedError('Unsupported cell kind or shared formula');
            }
            if (cell.value == null &&
                cell.formula == null &&
                !cell.requiresRichTextEditor) {
              continue;
            }
            if (++count > 30000) {
              throw UnsupportedError('Calculation cell limit exceeded');
            }
            final formula = cell.formula;
            if (formula != null) {
              if (formulas.length >= 10000 || formula.length > 16384) {
                throw UnsupportedError('Calculation formula limit exceeded');
              }
              formulas[jsonEncode([sheet.id, address.row, address.column])] =
                  formula;
            }
            cells.add({
              'r': address.row,
              'c': address.column,
              if (formula != null)
                'f': formula
              else
                'v': cell.requiresRichTextEditor ? cell.text : cell.value,
            });
          }
        }
      }
      sheets.add({'id': sheet.id, 'name': sheet.name, 'cells': cells});
    }
    final payload = jsonEncode({'version': 1, 'sheets': sheets});
    if (utf8.encode(payload).length > spreadsheetMaxBytes) {
      throw UnsupportedError('Calculation payload limit exceeded');
    }
    return SpreadsheetCalculationInput._(
      document,
      payload,
      Map.unmodifiable(formulas),
    );
  }

  SpreadsheetCalculationResult decode(String source) {
    if (utf8.encode(source).length > 10 * 1024 * 1024) {
      throw const FormatException('Calculation response too large');
    }
    final value = jsonDecode(source);
    if (value is! Map || value['ok'] != true) {
      throw UnsupportedError(
        'Native calculation could not process this workbook',
      );
    }
    final data = value['data'];
    if (data is! Map || data['version'] != 1 || data['results'] is! List) {
      throw const FormatException('Invalid calculation response');
    }
    final results = <String, SpreadsheetFormulaResult>{};
    for (final entry in data['results'] as List) {
      if (entry is! Map ||
          entry['sheet'] is! String ||
          entry['r'] is! int ||
          entry['c'] is! int ||
          entry['error'] is! bool) {
        throw const FormatException('Invalid calculated address');
      }
      final key = jsonEncode([entry['sheet'], entry['r'], entry['c']]);
      if (!formulas.containsKey(key) || results.containsKey(key)) {
        throw const FormatException('Unbound or duplicate formula result');
      }
      final scalar = entry['v'];
      if (scalar != null &&
              scalar is! String &&
              scalar is! num &&
              scalar is! bool ||
          scalar is num && !scalar.isFinite) {
        throw const FormatException('Invalid calculated scalar');
      }
      results[key] = SpreadsheetFormulaResult(
        value: scalar,
        error: entry['error'] as bool,
      );
    }
    if (results.length != formulas.length) {
      throw const FormatException('Incomplete calculation result');
    }
    return SpreadsheetCalculationResult._(document, Map.unmodifiable(results));
  }
}

class SpreadsheetFormulaResult {
  const SpreadsheetFormulaResult({required this.value, required this.error});
  final Object? value;
  final bool error;
}

class SpreadsheetCalculationResult {
  SpreadsheetCalculationResult._(this.document, this.results);
  final SpreadsheetDocument document;
  final Map<String, SpreadsheetFormulaResult> results;
  SpreadsheetFormulaResult? at(String sheetId, SheetAddress address) =>
      results[jsonEncode([sheetId, address.row, address.column])];
  bool get hasUnsupportedFormula =>
      results.values.any((r) => r.error && r.value == '#NAME?');
}
