import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_read_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/spreadsheet/spreadsheet_read_page.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  late String source;
  const savedAt = 1793923200000;
  const labelsJson = '["literal,label","标签😀"]';

  setUp(() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    directory = await Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    ).createTemp('local-complex-read-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    final workbook = SpreadsheetDocument.empty(
      workbookId: 'exact-workbook',
      sheetId: 'sheet-a',
    ).source;
    source = '{"futureOpaque":"${'扩展😀' * 200000}",${workbook.substring(1)}';
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<int> insert({
    required String title,
    required String content,
    required String editorType,
    int updatedAt = savedAt,
    String labels = labelsJson,
  }) async => (await store.database).insert('notes', {
    'title': title,
    'content': content,
    'updated_at': updatedAt,
    'labels': labels,
    'collection': 'note',
    'editor_type': editorType,
  });

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  Future<bool?> openTypedNote(
    WidgetTester tester,
    int id,
    List<Object> errors,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open typed note'),
              onPressed: () async {
                try {
                  result = await openNativeNoteEditor(
                    context,
                    repository: LocalNotesRepository(store),
                    id: id,
                  );
                } catch (error) {
                  errors.add(error);
                }
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open typed note'));
    await waitFor(
      tester,
      () =>
          find.byType(LocalComplexReadPage).evaluate().isNotEmpty ||
          errors.isNotEmpty,
    );
    expect(errors, isEmpty);
    expect(find.byType(LocalComplexReadPage), findsOneWidget);
    return result;
  }

  testWidgets(
    'typed local spreadsheet uses the Linux read-only fallback and preserves all saved row bytes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final id = (await tester.runAsync(
        () =>
            insert(title: '原始工作簿', content: source, editorType: 'spreadsheet'),
      ))!;
      final otherId = (await tester.runAsync(
        () => insert(
          title: 'Other typed note',
          content: '{"nodeData":{"id":"root","topic":"map"}}',
          editorType: 'mindmap',
          updatedAt: savedAt + 1,
          labels: '["other"]',
        ),
      ))!;
      final before = (await tester.runAsync(
        () async => (await store.database).query('notes', orderBy: 'id'),
      ))!;
      final errors = <Object>[];
      await openTypedNote(tester, id, errors);
      await waitFor(
        tester,
        () => find.byType(ComplexEditorBrowser).evaluate().isNotEmpty,
      );
      expect(find.byType(ComplexEditorBrowser), findsOneWidget);
      expect(find.byType(LocalSpreadsheetReadPage), findsNothing);
      expect(find.text('本地空间 · 表格 · 只读'), findsOneWidget);
      // On the non-Android widget host, ComplexEditorBrowser shows its unavailable
      // state; presence here verifies route selection, not native WebView execution.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final after = (await tester.runAsync(
        () async => (await store.database).query('notes', orderBy: 'id'),
      ))!;
      expect(after, before);
      expect(after.map((row) => row['id']), containsAll([id, otherId]));
      expect(after.firstWhere((row) => row['id'] == id), {
        ...before.firstWhere((row) => row['id'] == id),
      });
      expect(errors, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'invalid typed source never mounts browser or rewrites the original row',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      const invalid = '{not a workbook';
      final id = (await tester.runAsync(
        () => insert(
          title: 'Invalid workbook',
          content: invalid,
          editorType: 'spreadsheet',
        ),
      ))!;
      final before = (await tester.runAsync(() => store.readNote(id)))!;
      final errors = <Object>[];
      await openTypedNote(tester, id, errors);
      await waitFor(
        tester,
        () => find.text('无法读取文档，原始内容已保留。').evaluate().isNotEmpty,
      );
      expect(find.byType(ComplexEditorBrowser), findsNothing);
      expect(find.text('无法读取文档，原始内容已保留。'), findsOneWidget);
      expect(await tester.runAsync(() => store.readNote(id)), before);
      expect(errors, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'identity and editor type mismatches remain read errors without mounting Browser',
    (tester) async {
      final good = SpreadsheetDocument.empty(
        workbookId: 'w',
        sheetId: 's',
      ).source;
      for (final row in [
        {
          'id': 8,
          'collection': 'note',
          'editor_type': 'spreadsheet',
          'title': 'Mismatch',
          'content': good,
        },
        {
          'id': 7,
          'collection': 'article',
          'editor_type': 'spreadsheet',
          'title': 'Mismatch',
          'content': good,
        },
        {
          'id': 7,
          'collection': 'note',
          'editor_type': 'drawing',
          'title': 'Mismatch',
          'content': good,
        },
      ]) {
        await tester.runAsync(() async {
          final db = await store.database;
          await db.delete('notes');
          await db.insert('notes', {
            ...row,
            'updated_at': savedAt,
            'deleted': 0,
            'labels': '[]',
          });
        });
        await tester.pumpWidget(
          MaterialApp(
            home: LocalComplexReadPage(
              key: UniqueKey(),
              store: store,
              id: 7,
              collection: 'note',
              kind: ComplexEditorKind.spreadsheet,
            ),
          ),
        );
        await waitFor(
          tester,
          () => find.text('无法读取文档，原始内容已保留。').evaluate().isNotEmpty,
        );
        expect(find.byType(ComplexEditorBrowser), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
