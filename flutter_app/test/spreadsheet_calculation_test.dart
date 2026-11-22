import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/core/spreadsheet_calculation.dart';

void main() {
  SpreadsheetCalculationInput input() {
    var doc = SpreadsheetDocument.empty(workbookId: 'w', sheetId: 's');
    doc = doc.withCellValue('s', const SheetAddress(0, 0), '0012');
    doc = doc.withCellValue(
      's',
      const SheetAddress(1, 0),
      999,
      formula: '=LEN(A1)',
    );
    return SpreadsheetCalculationInput.fromDocument(doc);
  }

  String response(List<Object?> values) => jsonEncode({
    'ok': true,
    'data': {'version': 1, 'results': values},
  });
  Map<String, Object?> result({
    String sheet = 's',
    int row = 1,
    Object? value = 4,
  }) => {'sheet': sheet, 'r': row, 'c': 0, 'v': value, 'error': false};
  test(
    'data-only payload excludes unknown snapshot metadata and stale caches',
    () {
      final request = input(), payload = jsonDecode(input().payload);
      final cells = payload['sheets'][0]['cells'] as List;
      expect(cells[0]['v'], '0012');
      expect(cells[1]['f'], '=LEN(A1)');
      expect(cells[1].containsKey('v'), isFalse);
      final value = request.decode(response([result()]));
      expect(identical(value.document, request.document), isTrue);
      expect(value.at('s', const SheetAddress(1, 0))!.value, 4);
      expect(
        request.document.sheet('s').cell(const SheetAddress(1, 0)).value,
        999,
      );
    },
  );
  test(
    'response must bind every exact formula once and reject invented cells or structured values',
    () {
      final request = input();
      for (final rows in [
        <Object?>[],
        [result(sheet: 'other')],
        [result(row: 0)],
        [result(), result()],
        [
          result(value: {'bad': 1}),
        ],
      ]) {
        expect(() => request.decode(response(rows)), throwsFormatException);
      }
      expect(() => request.decode('{"ok":false}'), throwsUnsupportedError);
    },
  );
}
