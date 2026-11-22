import 'dart:convert';
import 'package:bookstark_flutter/core/spreadsheet_calculation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/features/spreadsheet/spreadsheet_editor.dart';
import 'package:bookstark_flutter/features/spreadsheet/spreadsheet_grid.dart';

SpreadsheetDocument workbook({
  bool formula = false,
  bool merged = false,
  int rows = 1000,
}) {
  final raw =
      jsonDecode(
            SpreadsheetDocument.empty(
              workbookId: 'w',
              sheetId: 's',
              sheetName: '预算',
            ).source,
          )
          as Map<String, dynamic>;
  final sheet = raw['sheets']['s'] as Map<String, dynamic>;
  sheet['rowCount'] = rows;
  sheet['defaultRowHeight'] = 36;
  sheet['defaultColumnWidth'] = 100;
  sheet['cellData'] = {
    '0': {
      '0': {'v': '项目', 't': 1},
      '1': {'v': 1200, 't': 2},
    },
    if (formula)
      '1': {
        '1': {'f': '=B1*2', 'v': 2400, 't': 2},
      },
    '99': {
      '0': {'v': '远处单元格', 't': 1},
    },
  };
  if (merged) {
    sheet['mergeData'] = [
      {'startRow': 0, 'endRow': 8, 'startColumn': 0, 'endColumn': 2},
    ];
  }
  return SpreadsheetDocument.parse(jsonEncode(raw));
}

Future<void> mount(
  WidgetTester tester,
  SpreadsheetDocument doc,
  List<SpreadsheetDocument> changes, {
  bool readOnly = false,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: SpreadsheetEditor(
            document: doc,
            readOnly: readOnly,
            onChanged: changes.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'computed values retain large exponents and cannot leak into a different snapshot',
    (tester) async {
      final doc = workbook(formula: true);
      final result = SpreadsheetCalculationInput.fromDocument(doc).decode(
        jsonEncode({
          'ok': true,
          'data': {
            'version': 1,
            'results': [
              {'sheet': 's', 'r': 1, 'c': 1, 'v': 1e100, 'error': false},
            ],
          },
        }),
      );
      Future<void> show(SpreadsheetDocument source) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SpreadsheetGrid(
                document: source,
                sheetId: 's',
                selected: const SheetAddress(0, 0),
                calculation: result,
                onSelect: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(doc);
      expect(find.text('1e+100'), findsOneWidget);
      expect(find.text('2400'), findsNothing);
      await show(SpreadsheetDocument.parse(doc.source));
      expect(find.text('1e+100'), findsNothing);
      expect(find.text('2400'), findsOneWidget);
    },
  );

  testWidgets(
    'native scalar edit, explicit cancel, undo and redo preserve typed workbook',
    (tester) async {
      final changes = <SpreadsheetDocument>[];
      final doc = workbook();
      await mount(tester, doc, changes);
      await tester.enterText(
        find.byKey(const Key('sheet-formula-input')),
        '已修改',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('取消输入'));
      await tester.pump();
      expect(changes, isEmpty);
      await tester.enterText(
        find.byKey(const Key('sheet-formula-input')),
        '已修改',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('应用输入'));
      await tester.pumpAndSettle();
      expect(
        changes.last.sheet('s').cell(const SheetAddress(0, 0)).text,
        '已修改',
      );
      expect(
        changes.last.sheet('s').cell(const SheetAddress(0, 1)).value,
        1200,
      );
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(identical(changes.last, doc), isTrue);
      await tester.tap(find.byTooltip('重做'));
      await tester.pumpAndSettle();
      expect(
        changes.last.sheet('s').cell(const SheetAddress(0, 0)).text,
        '已修改',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'format cancellation is inert; apply changes style and undo restores source',
    (tester) async {
      final changes = <SpreadsheetDocument>[];
      final doc = workbook();
      await mount(tester, doc, changes);
      await tester.tap(find.text('格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'B'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await tester.tap(find.text('格式'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'B'));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(changes.last.cellStyle('s', const SheetAddress(0, 0))['bl'], 1);
      expect(changes.last.sheet('s').cell(const SheetAddress(0, 0)).text, '项目');
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(changes.last.source, doc.source);
    },
  );
  testWidgets(
    'formula caches are visible but cannot be invalidated before evaluator integration',
    (tester) async {
      final changes = <SpreadsheetDocument>[];
      await mount(tester, workbook(formula: true), changes);
      expect(find.text('2400'), findsOneWidget);
      final input = tester.widget<TextField>(
        find.byKey(const Key('sheet-formula-input')),
      );
      expect(input.readOnly, isTrue);
      expect(changes, isEmpty);
    },
  );
  testWidgets(
    'million row workbook is lazy and address locator moves the viewport',
    (tester) async {
      final changes = <SpreadsheetDocument>[];
      await mount(tester, workbook(rows: 1048576), changes);
      expect(find.byType(TableViewCell).evaluate().length, lessThan(300));
      expect(find.text('远处单元格'), findsNothing);
      await tester.tap(find.text('A1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'A1'), 'A100');
      await tester.tap(find.text('定位'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '远处单元格'),
        findsOneWidget,
      );
      expect(find.byType(TableViewCell).evaluate().length, lessThan(300));
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('merged cells survive scrolling their anchor out of view', (
    tester,
  ) async {
    final doc = workbook(merged: true),
        vertical = ScrollController(),
        horizontal = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpreadsheetGrid(
            document: doc,
            sheetId: 's',
            selected: const SheetAddress(0, 0),
            onSelect: (_) {},
            verticalController: vertical,
            horizontalController: horizontal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    vertical.jumpTo(180);
    horizontal.jumpTo(110);
    await tester.pumpAndSettle();
    expect(find.text('项目'), findsOneWidget);
    final cell = tester.widget<TableViewCell>(
      find
          .ancestor(of: find.text('项目'), matching: find.byType(TableViewCell))
          .first,
    );
    expect(cell.rowMergeStart, 1);
    expect(cell.rowMergeSpan, 9);
    expect(cell.columnMergeSpan, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    vertical.dispose();
    horizontal.dispose();
  });
  testWidgets(
    'read only and 320dp doubled text preserve usable grid without write controls',
    (tester) async {
      final changes = <SpreadsheetDocument>[];
      await mount(
        tester,
        workbook(),
        changes,
        readOnly: true,
        width: 320,
        scale: 2,
      );
      expect(find.text('格式'), findsNothing);
      expect(find.byTooltip('撤销'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sheet-formula-input')))
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byTooltip('工作表管理'));
      await tester.pumpAndSettle();
      expect(find.text('新建工作表'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
