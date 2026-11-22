import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';

Map<String, dynamic> sample() {
  final data =
      jsonDecode(
            SpreadsheetDocument.empty(
              workbookId: 'workbook',
              sheetId: 'budget',
              sheetName: '预算',
            ).source,
          )
          as Map<String, dynamic>;
  data['future'] = {
    'nested': [
      'unchanged',
      {'version': 7},
    ],
  };
  data['styles'] = {
    'bold': {
      'bl': 1,
      'cl': {'rgb': '#123456'},
      'futureStyle': true,
    },
  };
  final sheet = (data['sheets'] as Map)['budget'] as Map;
  sheet['cellData'] = {
    '0': {
      '0': {
        'v': '项目',
        't': 1,
        's': 'bold',
        'futureCell': {'keep': true},
      },
      '1': {'v': 1200, 't': 2},
    },
    '1': {
      '1': {'v': 3600, 't': 2},
    },
    '2': {
      '1': {'f': '=SUM(B1:B2)', 'v': 4800, 't': 2, 's': 'bold'},
    },
    '3': null,
  };
  sheet['rowData'] = {
    '0': {'h': 32, 'futureRow': 9},
  };
  sheet['columnData'] = {
    '1': {'w': 100, 'futureColumn': 10},
  };
  return data;
}

void main() {
  test(
    'inline formatting resolves named style without changing neighbors or unknown attributes',
    () {
      final doc = SpreadsheetDocument.parse(jsonEncode(sample()));
      final next = doc.withCellStyle('budget', const SheetAddress(0, 0), {
        'it': 1,
      });
      expect(next.cellStyle('budget', const SheetAddress(0, 0)), {
        ...doc.cellStyle('budget', const SheetAddress(0, 0)),
        'it': 1,
      });
      expect(next.raw['styles'], doc.raw['styles']);
      expect(
        next.sheet('budget').cell(const SheetAddress(0, 0)).raw['futureCell'],
        {'keep': true},
      );
      expect(
        next.sheet('budget').cell(const SheetAddress(2, 1)).raw,
        doc.sheet('budget').cell(const SheetAddress(2, 1)).raw,
      );
      expect(
        identical(
          doc.withCellStyle('budget', const SheetAddress(0, 0), {}),
          doc,
        ),
        isTrue,
      );
    },
  );
  test(
    'sheet additions preserve identity, enforce names and never rewrite old formulas',
    () {
      final doc = SpreadsheetDocument.parse(jsonEncode(sample()));
      final added = doc.addSheet(sheetId: 'notes', name: '说明');
      expect(added.sheets.map((s) => s.id), ['budget', 'notes']);
      expect(added.sheet('budget').raw, doc.sheet('budget').raw);
      expect(() => added.renameSheet('budget', '新预算'), throwsUnsupportedError);
      expect(
        () => added.addSheet(sheetId: 'bad', name: '预算'),
        throwsFormatException,
      );
      expect(
        () => added.addSheet(sheetId: 'bad', name: 'bad/name'),
        throwsFormatException,
      );
      expect(
        () => added.addSheet(sheetId: 'budget', name: '新表'),
        throwsFormatException,
      );
      final hidden = added.setSheetHidden('budget', true);
      expect(hidden.sheet('budget').hidden, isTrue);
      expect(() => hidden.setSheetHidden('notes', true), throwsFormatException);
      expect(
        hidden.setSheetHidden('budget', false).sheet('budget').raw['cellData'],
        doc.sheet('budget').raw['cellData'],
      );
    },
  );

  test(
    'future structured cell values and kinds remain intact and cannot be flattened',
    () {
      final data = sample();
      (data['sheets'] as Map)['budget']['cellData']['5'] = {
        '0': {
          'v': {'future': 1},
          't': 99,
          'f': {'futureFormula': true},
        },
      };
      final doc = SpreadsheetDocument.parse(jsonEncode(data));
      expect(doc.sheet('budget').cell(const SheetAddress(5, 0)).raw['v'], {
        'future': 1,
      });
      expect(
        () => doc.withCellValue('budget', const SheetAddress(5, 0), 'replace'),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'A1 addresses support absolute references, Z to AA and exact Excel limits',
    () {
      expect(SheetAddress.parse('A1'), const SheetAddress(0, 0));
      expect(SheetAddress.parse(r'$AA$9').a1, 'AA9');
      expect(SheetAddress.columnName(25), 'Z');
      expect(SheetAddress.columnName(26), 'AA');
      expect(
        SheetAddress.parse('XFD1048576'),
        const SheetAddress(1048575, 16383),
      );
      for (final invalid in [
        '',
        'A0',
        'A01',
        'XFE1',
        'A1048577',
        'A-1',
        'A1:B2',
        'Sheet1!A1',
      ]) {
        expect(() => SheetAddress.parse(invalid), throwsFormatException);
      }
      expect(() => const SheetAddress(-1, 0).a1, throwsRangeError);
    },
  );
  test(
    'snapshot parsing preserves exact source, identities and every unknown field',
    () {
      final source = const JsonEncoder.withIndent('  ').convert(sample());
      final document = SpreadsheetDocument.parse(source);
      expect(document.source, source);
      expect(document.id, 'workbook');
      expect(document.sheets.single.id, 'budget');
      expect(document.raw['future'], sample()['future']);
      expect(
        document.sheet('budget').raw['rowData'],
        (sample()['sheets'] as Map)['budget']['rowData'],
      );
      expect(
        document.sheet('budget').cell(const SheetAddress(2, 1)).formula,
        '=SUM(B1:B2)',
      );
      expect(
        document.sheet('budget').cell(const SheetAddress(2, 1)).text,
        '4800',
      );
      expect(
        document.sheet('budget').cell(const SheetAddress(99, 25)).text,
        '',
      );
    },
  );
  test('workbook, cells and nested plugin metadata are deeply immutable', () {
    final doc = SpreadsheetDocument.parse(jsonEncode(sample()));
    expect(() => doc.raw['id'] = 'changed', throwsUnsupportedError);
    expect(
      () => ((doc.raw['future'] as Map)['nested'] as List).add('changed'),
      throwsUnsupportedError,
    );
    expect(
      () => doc.sheet('budget').cell(const SheetAddress(0, 0)).raw['v'] =
          'changed',
      throwsUnsupportedError,
    );
  });
  test(
    'editing one scalar preserves styles, formula neighbors, sparse metadata and source baseline',
    () {
      final original = SpreadsheetDocument.parse(jsonEncode(sample()));
      final changed = original.withCellValue(
        'budget',
        const SheetAddress(0, 1),
        1500,
      );
      expect(
        changed.sheet('budget').cell(const SheetAddress(0, 1)).value,
        1500,
      );
      expect(
        original.sheet('budget').cell(const SheetAddress(0, 1)).value,
        1200,
      );
      expect(changed.raw['future'], original.raw['future']);
      expect(changed.raw['styles'], original.raw['styles']);
      expect(
        changed.sheet('budget').cell(const SheetAddress(0, 0)).raw,
        original.sheet('budget').cell(const SheetAddress(0, 0)).raw,
      );
      expect(
        changed.sheet('budget').cell(const SheetAddress(2, 1)).raw,
        original.sheet('budget').cell(const SheetAddress(2, 1)).raw,
      );
      expect(
        changed.sheet('budget').raw['columnData'],
        original.sheet('budget').raw['columnData'],
      );
      expect(
        identical(
          original.withCellValue('budget', const SheetAddress(0, 1), 1200),
          original,
        ),
        isTrue,
      );
    },
  );
  test(
    'formula replacement can drop old cached values and clearing retains cell formatting',
    () {
      final doc = SpreadsheetDocument.parse(jsonEncode(sample()));
      final formula = doc.withCellValue(
        'budget',
        const SheetAddress(2, 1),
        null,
        formula: '=SUM(B1:B2)*2',
      );
      final cell = formula.sheet('budget').cell(const SheetAddress(2, 1));
      expect(cell.value, isNull);
      expect(cell.formula, '=SUM(B1:B2)*2');
      expect(cell.raw['s'], 'bold');
      final cleared = doc
          .withCellValue('budget', const SheetAddress(2, 1), null)
          .sheet('budget')
          .cell(const SheetAddress(2, 1));
      expect(cleared.formula, isNull);
      expect(cleared.value, isNull);
      expect(cleared.raw['s'], 'bold');
    },
  );
  test(
    'rich text and shared formulas cannot be flattened by plain scalar editing',
    () {
      final data = sample();
      final cells = (data['sheets'] as Map)['budget']['cellData'] as Map;
      cells['4'] = {
        '0': {
          'p': {
            'body': {
              'dataStream': 'Keep\nline\r\n',
              'textRuns': [
                {
                  'st': 0,
                  'ed': 4,
                  'ts': {'bl': 1},
                },
              ],
            },
          },
        },
        '1': {'si': 'shared-1', 'v': 8},
      };
      final doc = SpreadsheetDocument.parse(jsonEncode(data));
      expect(
        doc.sheet('budget').cell(const SheetAddress(4, 0)).text,
        'Keep\nline',
      );
      expect(
        () => doc.withCellValue('budget', const SheetAddress(4, 0), 'replace'),
        throwsUnsupportedError,
      );
      expect(
        () => doc.withCellValue('budget', const SheetAddress(4, 1), 9),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'merged cells are found offscreen and covered cells cannot overwrite anchors',
    () {
      final data = sample(), sheet = (data['sheets'] as Map)['budget'] as Map;
      sheet['rowCount'] = 2000;
      sheet['mergeData'] = [
        for (var i = 0; i < 500; i++)
          {
            'startRow': i * 2,
            'endRow': i * 2,
            'startColumn': 3,
            'endColumn': 4,
          },
      ];
      final doc = SpreadsheetDocument.parse(jsonEncode(data));
      final target = doc.sheet('budget');
      expect(
        target.mergeAt(const SheetAddress(986, 4))!.anchor,
        const SheetAddress(986, 3),
      );
      expect(target.mergeAt(const SheetAddress(987, 4)), isNull);
      expect(
        () =>
            doc.withCellValue('budget', const SheetAddress(986, 4), 'covered'),
        throwsFormatException,
      );
      expect(
        doc
            .withCellValue('budget', const SheetAddress(986, 3), 'anchor')
            .sheet('budget')
            .cell(const SheetAddress(986, 3))
            .value,
        'anchor',
      );
    },
  );
  test(
    'overlapping merges are rejected while tall ranges in separate columns remain valid',
    () {
      final data = sample(), sheet = (data['sheets'] as Map)['budget'] as Map;
      sheet['mergeData'] = [
        {'startRow': 0, 'endRow': 999, 'startColumn': 3, 'endColumn': 3},
        {'startRow': 1, 'endRow': 2, 'startColumn': 4, 'endColumn': 5},
      ];
      final doc = SpreadsheetDocument.parse(jsonEncode(data));
      expect(
        doc.sheet('budget').mergeAt(const SheetAddress(1, 5))!.anchor,
        const SheetAddress(1, 4),
      );
      (sheet['mergeData'] as List).add({
        'startRow': 2,
        'endRow': 4,
        'startColumn': 3,
        'endColumn': 4,
      });
      expect(
        () => SpreadsheetDocument.parse(jsonEncode(data)),
        throwsFormatException,
      );
    },
  );
  test(
    'empty workbook is sparse; hidden sheets, frozen dimensions and orphan metadata are retained',
    () {
      final data = sample();
      final all = data['sheets'] as Map;
      all['budget']['hidden'] = 1;
      all['budget']['freeze'] = {'xSplit': 2, 'ySplit': 3};
      all['orphan'] = {'future': 'preserved'};
      final doc = SpreadsheetDocument.parse(jsonEncode(data));
      expect(doc.sheet('budget').hidden, isTrue);
      expect(doc.sheet('budget').frozenColumns, 2);
      expect(doc.raw['sheets'], all);
      expect(() => doc.sheet('orphan'), throwsFormatException);
      final empty = SpreadsheetDocument.empty(
        workbookId: 'new',
        sheetId: 'sheet',
      );
      expect(empty.sheets.single.raw['cellData'], isEmpty);
      expect(empty.sheets.single.rowCount, 1000);
    },
  );
  test(
    'malformed identity, dimensions, sparse index and input never produce a new blank workbook',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (data) => data['sheetOrder'] = ['budget', 'budget'],
        (data) => (data['sheets'] as Map)['budget']['id'] = 'different',
        (data) => (data['sheets'] as Map)['budget']['rowCount'] = 0,
        (data) => (data['sheets'] as Map)['budget']['cellData'] = {'-1': {}},
        (data) => (data['sheets'] as Map)['budget']['cellData'] = {
          '0': {'01': {}},
        },
      ]) {
        final data = sample();
        mutate(data);
        expect(
          () => SpreadsheetDocument.parse(jsonEncode(data)),
          throwsFormatException,
        );
      }
      for (final source in ['', '[]', '{broken}', '{"id":"x"}']) {
        expect(() => SpreadsheetDocument.parse(source), throwsFormatException);
      }
    },
  );
  test('byte/depth and Unicode bounds reject before data replacement', () {
    final doc = SpreadsheetDocument.parse(jsonEncode(sample()));
    expect(
      () => doc.withCellValue(
        'budget',
        const SheetAddress(0, 1),
        'x' * spreadsheetMaxBytes,
      ),
      throwsFormatException,
    );
    expect(doc.sheet('budget').cell(const SheetAddress(0, 1)).value, 1200);
    expect(
      () => SpreadsheetDocument.parse('[' * 65 + ']' * 65),
      throwsFormatException,
    );
    expect(
      () => SpreadsheetDocument.parse('{"id":"\\ud800"}'),
      throwsFormatException,
    );
    expect(
      () => doc.withCellValue(
        'budget',
        const SheetAddress(0, 1),
        double.infinity,
      ),
      throwsFormatException,
    );
  });
}
