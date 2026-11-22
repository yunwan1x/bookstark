import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/features/spreadsheet/spreadsheet_editor.dart';

SpreadsheetDocument spreadsheetFixtureDocument() {
  final raw =
      jsonDecode(
            SpreadsheetDocument.empty(
              workbookId: 'visual-workbook',
              sheetId: 'budget',
              sheetName: '预算',
            ).source,
          )
          as Map<String, dynamic>;
  final sheet = raw['sheets']['budget'] as Map<String, dynamic>;
  sheet['defaultRowHeight'] = 38;
  sheet['defaultColumnWidth'] = 108;
  sheet['cellData'] = {
    '0': {
      '0': {'v': '项目', 't': 1},
      '1': {'v': '预算', 't': 1},
      '2': {'v': '已用', 't': 1},
    },
    '1': {
      '0': {'v': '设计', 't': 1},
      '1': {'v': 1200, 't': 2},
      '2': {'v': 800, 't': 2},
    },
    '2': {
      '0': {'v': '开发', 't': 1},
      '1': {'v': 3600, 't': 2},
      '2': {'v': 2400, 't': 2},
    },
    '3': {
      '0': {'v': '合计', 't': 1},
      '1': {'v': 4800, 't': 2, 'f': '=SUM(B2:B3)'},
      '2': {'v': 3200, 't': 2, 'f': '=SUM(C2:C3)'},
    },
  };
  var document = SpreadsheetDocument.parse(jsonEncode(raw));
  for (var c = 0; c < 3; c++) {
    document = document.withCellStyle('budget', SheetAddress(0, c), {
      'bl': 1,
      'bg': {'rgb': '#e8efff'},
    });
  }
  return document.addSheet(sheetId: 'notes', name: '说明');
}

class SpreadsheetVisualFixture extends StatefulWidget {
  const SpreadsheetVisualFixture({super.key});
  @override
  State<SpreadsheetVisualFixture> createState() =>
      _SpreadsheetVisualFixtureState();
}

class _SpreadsheetVisualFixtureState extends State<SpreadsheetVisualFixture> {
  late SpreadsheetDocument document = spreadsheetFixtureDocument();
  bool changed = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff1f5ff),
    appBar: AppBar(
      title: const Text('表格'),
      actions: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(changed ? '未保存' : '示例'),
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '项目预算',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: SpreadsheetEditor(
            document: document,
            onChanged: (next) => setState(() {
              document = next;
              changed = true;
            }),
          ),
        ),
      ],
    ),
  );
}
