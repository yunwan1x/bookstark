import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/core/spreadsheet_calculator.dart';

void main() {
  final path = Platform.environment['BOOKSTARK_CALC_HOST_LIBRARY'];
  if (path == null) {
    throw StateError(
      'Provide the actual host calculation library; no mocked pass',
    );
  }
  SpreadsheetDocument source() {
    final raw =
        jsonDecode(
              SpreadsheetDocument.empty(
                workbookId: 'w',
                sheetId: 's',
                sheetName: '预算',
              ).source,
            )
            as Map<String, dynamic>;
    raw['sheets']['s']['cellData'] = {
      '0': {
        '0': {'v': 1200, 't': 2},
      },
      '1': {
        '0': {'v': 3600, 't': 2},
      },
      '2': {
        '0': {
          'f': '=SUM(A1:A2)',
          'v': -999,
          't': 2,
          's': {'bl': 1},
          'future': true,
        },
      },
    };
    return SpreadsheetDocument.parse(jsonEncode(raw));
  }

  test(
    'real FFI dependency recalculation returns fresh values without altering original caches',
    () async {
      final original = source(), before = source().source;
      final first = await calculateSpreadsheet(original, libraryPath: path);
      expect(first.at('s', const SheetAddress(2, 0))!.value, 4800);
      final edited = original.withCellValue(
        's',
        const SheetAddress(0, 0),
        2000,
      );
      final second = await calculateSpreadsheet(edited, libraryPath: path);
      expect(second.at('s', const SheetAddress(2, 0))!.value, 5600);
      expect(original.source, before);
      expect(original.sheet('s').cell(const SheetAddress(2, 0)).value, -999);
      expect(
        second.document.sheet('s').cell(const SheetAddress(2, 0)).raw['future'],
        isTrue,
      );
    },
  );
  test(
    'real FFI formula editing, error classification and repeated allocation cleanup',
    () async {
      final original = source();
      for (var i = 0; i < 12; i++) {
        final changed = original.withCellValue(
          's',
          const SheetAddress(2, 0),
          null,
          formula: '=A1*${i + 1}',
        );
        final result = await calculateSpreadsheet(changed, libraryPath: path);
        expect(result.at('s', const SheetAddress(2, 0))!.value, 1200 * (i + 1));
      }
      final unknown = original.withCellValue(
        's',
        const SheetAddress(2, 0),
        null,
        formula: '=BOOKSTARK_UNKNOWN(1)',
      );
      expect(
        (await calculateSpreadsheet(
          unknown,
          libraryPath: path,
        )).hasUnsupportedFormula,
        isTrue,
      );
      final divided = original.withCellValue(
        's',
        const SheetAddress(2, 0),
        null,
        formula: '=1/0',
      );
      final result = await calculateSpreadsheet(divided, libraryPath: path);
      expect(result.at('s', const SheetAddress(2, 0))!.error, isTrue);
      expect(result.at('s', const SheetAddress(2, 0))!.value, '#DIV/0!');
    },
  );
}
