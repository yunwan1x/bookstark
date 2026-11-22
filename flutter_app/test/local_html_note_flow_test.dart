import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'package:bookstark_flutter/features/html/open_local_html_note.dart';
import 'html_note_page_fake_surface_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  late Directory directory;
  late LocalStore store;
  late LocalHtmlNotesRepository repo;
  late HtmlNote initial;
  late Map<String, String> values;
  late HtmlRecoveryVault vault;
  final errors = <Object>[];
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
    ).createTemp('local-html-ui-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalHtmlNotesRepository(store);
    initial = await repo.create(
      HtmlNoteEdit(
        title: 'Local HTML',
        source: '<p>你好</p>\r\n<!-- 🧪 -->',
        labels: ['one,literal,label'],
      ),
    );
    values = {};
    errors.clear();
    vault = HtmlRecoveryVault(
      localDatabase: true,
      server: localHtmlRecoveryScope(store.path),
      memberId: 1,
      collection: 'note',
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
  });
  tearDown(() async {
    repo.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester) async {
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
                    id: initial.metadata.id,
                    english: true,
                    htmlRecoveryVault: vault,
                    htmlSourceSurfaceBuilder: fakeHtmlSourceSurface(
                      FakeHtmlSurfaceControl(),
                    ),
                  );
                } catch (e) {
                  errors.add(e);
                }
              },
              child: const Text('Open local'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      // SQLite file futures require real I/O time outside fake widget clocks.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(errors, isEmpty);
    expect(ready(), true);
    await tester.pumpAndSettle();
  }

  Future<void> openNote(WidgetTester tester) async {
    await tester.tap(find.text('Open local'));
    await waitFor(
      tester,
      () =>
          find.byType(HtmlNotePage).evaluate().isNotEmpty ||
          find.text('Unsaved HTML draft found').evaluate().isNotEmpty ||
          errors.isNotEmpty,
    );
  }

  Future<void> source(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Source'));
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'normal local note opener dispatches HTML and saves in SQLite without authenticated cookies',
    (tester) async {
      await mount(tester);
      await openNote(tester);
      expect(find.byType(HtmlNotePage), findsOneWidget);
      expect(find.text('Local space'), findsOneWidget);
      expect(find.text('Full preview'), findsNothing);
      expect(find.text('one,literal,label'), findsOneWidget);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Saved local HTML',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await waitFor(
        tester,
        () => find.text('Saved').evaluate().isNotEmpty || errors.isNotEmpty,
      );
      final actual = (await tester.runAsync(
        () => repo.read(initial.metadata.id),
      ))!;
      expect(actual.metadata.title, 'Saved local HTML');
      expect(actual.source, initial.source);
      expect(actual.labels, initial.labels);
      expect(values, isEmpty);
      expect(errors, isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'ordinary local HTML draft restores through real opener without changing saved row',
    (tester) async {
      await mount(tester);
      await openNote(tester);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Local unsaved draft',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep draft and leave'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(
          () => repo.read(initial.metadata.id),
        ))!.metadata.title,
        'Local HTML',
      );
      await openNote(tester);
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await source(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('html-title')))
            .controller!
            .text,
        'Local unsaved draft',
      );
      expect(errors, isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'unknown local transaction is explicitly observed without rewriting its saved revision',
    (tester) async {
      final draft = HtmlNoteEdit(
        title: 'Applied before restart',
        source: initial.source,
        labels: initial.labels,
      );
      await vault.write(
        HtmlRecoveryRecord.capture(initial, draft, pending: true),
      );
      final applied = (await tester.runAsync(
        () => repo.save(initial, draft),
      ))!.note;
      await mount(tester);
      await openNote(tester);
      expect(find.text('Content save result unknown'), findsOneWidget);
      await tester.ensureVisible(find.text('Verify device save'));
      await tester.tap(find.text('Verify device save'));
      await waitFor(tester, () => values.isEmpty || errors.isNotEmpty);
      expect(
        (await tester.runAsync(
          () => repo.read(initial.metadata.id),
        ))!.metadata.version,
        applied.metadata.version,
      );
      expect(values, isEmpty);
      expect(errors, isEmpty);
      await close(tester);
    },
  );
}
