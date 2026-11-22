import 'dart:ffi';
import 'dart:io';

import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late LocalStore store;

  setUp(() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    directory = await Directory.systemTemp.createTemp('open-local-complex-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('bookstark/complex_recovery'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    debugDefaultTargetPlatformOverride = null;
    await store.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'Android typed-note entry opens the editable route without writing or losing source bytes',
    (tester) async {
      final source =
          SpreadsheetDocument.empty(
            workbookId: 'preserve-workbook',
            sheetId: 'sheet-a',
          ).source.replaceFirst(
            '"sheetName":"Sheet1"',
            '"sheetName":"表格😀","futurePadding":"opaque"',
          );
      final id = (await tester.runAsync(
        () async => (await store.database).insert('notes', {
          'title': '本地 HTML',
          'content': source,
          'updated_at': 1793923200000,
          'labels': '["中文","tag"]',
          'collection': 'note',
          'editor_type': 'spreadsheet',
        }),
      ))!;
      final before = (await tester.runAsync(
        () async => (await store.database).query('notes'),
      ))!;
      final recoveryCalls = <MethodCall>[];
      final sessionCalls = <MethodCall>[];
      final viewCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('bookstark/complex_recovery'),
        (call) async {
          recoveryCalls.add(call);
          if (call.method == 'beginRead') return null;
          fail('Unexpected recovery command ${call.method}');
        },
      );
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        sessionCalls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        viewCalls.add(call);
        if (call.method == 'create') return 701;
        return null;
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Object? error;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await openNativeNoteEditor(
                      context,
                      repository: LocalNotesRepository(store),
                      id: id,
                    );
                  } catch (caught) {
                    error = caught;
                  }
                },
                child: const Text('Open typed local note'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open typed local note'));
      for (
        var i = 0;
        i < 100 && find.byType(LocalComplexNotePage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(error, isNull);
      expect(find.byType(LocalComplexNotePage), findsOneWidget);
      expect(sessionCalls.map((call) => call.method), contains('openLocal'));
      expect(recoveryCalls.map((call) => call.method), contains('beginRead'));
      expect(viewCalls.map((call) => call.method), contains('create'));

      await tester.pageBack();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      final after = (await tester.runAsync(
        () async => (await store.database).query('notes'),
      ))!;
      expect(after, before);
      expect(after.single['content'], source);
      expect(after.single['title'], '本地 HTML');
      expect(after.single['labels'], '["中文","tag"]');
      expect(tester.takeException(), isNull);
    },
  );
}
