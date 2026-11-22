import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/core/spreadsheet_calculation.dart';
import 'package:bookstark_flutter/features/spreadsheet/spreadsheet_read_page.dart';

class Store extends LocalStore {
  Store(this.row) : super(path: ':memory:', factory: databaseFactoryFfi);
  Map<String, Object?> row;
  int reads = 0;
  @override
  Future<Map<String, Object?>> readNote(
    int id, {
    String collection = 'note',
  }) async {
    reads++;
    return row;
  }
}

void main() {
  Store store({String type = 'spreadsheet', String? source}) {
    final doc = SpreadsheetDocument.empty(
      workbookId: 'w',
      sheetId: 's',
    ).withCellValue('s', const SheetAddress(0, 0), -999, formula: '=1+2');
    return Store({
      'id': 7,
      'collection': 'note',
      'editor_type': type,
      'title': '实际工作簿',
      'content': source ?? doc.source,
    });
  }

  SpreadsheetCalculationResult calculated(SpreadsheetDocument doc) =>
      SpreadsheetCalculationInput.fromDocument(doc).decode(
        jsonEncode({
          'ok': true,
          'data': {
            'version': 1,
            'results': [
              {'sheet': 's', 'r': 0, 'c': 0, 'v': 3, 'error': false},
            ],
          },
        }),
      );
  testWidgets(
    'typed local read shows fresh native-protocol values and exposes no write action',
    (tester) async {
      final local = store();
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSpreadsheetReadPage(
            store: local,
            id: 7,
            collection: 'note',
            calculator: (doc) async => calculated(doc),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('实际工作簿'), findsOneWidget);
      expect(find.text('只读'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.text('-999'), findsNothing);
      expect(find.text('格式'), findsNothing);
      expect(find.text('保存'), findsNothing);
      expect(local.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changed type and malformed source never become a new empty spreadsheet',
    (tester) async {
      for (final local in [store(type: 'markdown'), store(source: '{bad')]) {
        await tester.pumpWidget(
          MaterialApp(
            home: LocalSpreadsheetReadPage(
              key: UniqueKey(),
              store: local,
              id: 7,
              collection: 'note',
              calculator: (doc) async => calculated(doc),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('表格无法读取或已更改，原始内容未修改'), findsOneWidget);
        expect(find.text('实际工作簿'), findsNothing);
      }
    },
  );
  testWidgets(
    'pending calculation cannot spawn duplicate jobs and late completion is ignored after disposal',
    (tester) async {
      final local = store();
      final pending = Completer<SpreadsheetCalculationResult>();
      SpreadsheetDocument? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSpreadsheetReadPage(
            store: local,
            id: 7,
            collection: 'note',
            calculator: (doc) {
              captured = doc;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '刷新',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('正在重算 · 网格暂为已保存缓存'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.complete(calculated(captured!));
      await tester.pump();
      expect(local.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
