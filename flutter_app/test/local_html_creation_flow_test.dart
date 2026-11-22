import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/html/html_create_page.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'html_note_page_fake_surface_test_support.dart';
import 'package:bookstark_flutter/features/html/html_version_view.dart';
import 'package:bookstark_flutter/features/html/open_local_html_note.dart';
import 'package:bookstark_flutter/features/html/open_new_local_html_note.dart';
import 'local_html_creation_controller_test.dart' show CreationMemory;

void main() {
  late Directory directory;
  late LocalStore store;
  late CreationMemory memory;
  late HtmlRecoveryVault noteVault;
  late FakeHtmlSurfaceControl sourceSurface;
  final errors = <Object>[];
  setUp(() async {
    installFakeHtmlSessionChannel();
    sourceSurface = FakeHtmlSurfaceControl();
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    );
    await base.create(recursive: true);
    directory = await base.createTemp('html-create-flow-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    memory = CreationMemory();
    errors.clear();
    noteVault = HtmlRecoveryVault(
      server: localHtmlRecoveryScope(store.path),
      memberId: 1,
      collection: 'note',
      localDatabase: true,
      readValue: (k) async => memory.values[k],
      writeValue: (k, v) async {
        memory.values[k] = v;
      },
      deleteValue: (k) async {
        memory.values.remove(k);
      },
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(errors, isEmpty);
    expect(ready(), true);
    await tester.pumpAndSettle();
  }

  Future<List<Map<String, Object?>>> rows(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => (await store.database).query('notes'),
      ))!;
  Future<void> mount(
    WidgetTester tester, {
    bool notes = false,
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: notes
            ? NotesPage(
                repository: LocalNotesRepository(store),
                english: true,
                htmlCreationVault: memory.vault(),
                htmlRecoveryVault: noteVault,
                htmlSourceSurfaceBuilder: fakeHtmlSourceSurface(sourceSurface),
                htmlReadOnlySourceSurfaceBuilder: fakeReadOnlyHtmlCodeSurface(),
              )
            : Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      try {
                        await openNewLocalHtmlNote(
                          context,
                          store: store,
                          collection: 'note',
                          english: true,
                          creationVault: memory.vault(),
                          noteRecoveryVault: noteVault,
                          readOnlySourceSurfaceBuilder:
                              fakeReadOnlyHtmlCodeSurface(),
                          sourceSurfaceBuilder: fakeHtmlSourceSurface(
                            sourceSurface,
                          ),
                        );
                      } catch (e) {
                        errors.add(e);
                      }
                    },
                    child: const Text('Create HTML'),
                  ),
                ),
              ),
      ),
    );
    if (notes) {
      await waitFor(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
    }
  }

  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.text('Create HTML'));
    await waitFor(
      tester,
      () =>
          find.byType(HtmlCreatePage).evaluate().isNotEmpty ||
          errors.isNotEmpty,
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local format chooser cancellation creates nothing and Markdown still opens its original editor',
    (tester) async {
      await mount(tester, notes: true);
      await tester.tap(find.byTooltip('New note'));
      await tester.pumpAndSettle();
      expect(find.text('Markdown note'), findsOneWidget);
      expect(find.text('HTML note'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await rows(tester), isEmpty);
      expect(memory.values, isEmpty);
      await tester.tap(find.byTooltip('New note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPage), findsOneWidget);
      expect(find.byType(HtmlCreatePage), findsNothing);
      expect(await rows(tester), isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'HTML choice creates one typed note and opens that same saved ID',
    (tester) async {
      await mount(tester, notes: true);
      await tester.tap(find.byTooltip('New note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HTML note'));
      await waitFor(
        tester,
        () => find.byType(HtmlCreatePage).evaluate().isNotEmpty,
      );
      final source = sourceSurface.source!;
      await tester.enterText(
        find.byKey(const ValueKey('html-create-title')),
        'Created through Flutter',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await waitFor(
        tester,
        () =>
            find.byType(HtmlNotePage).evaluate().isNotEmpty ||
            errors.isNotEmpty,
      );
      final actual = (await rows(tester)).single;
      expect(actual['editor_type'], 'html');
      expect(actual['title'], 'Created through Flutter');
      expect(actual['content'], source);
      expect(memory.values, isEmpty);
      expect(find.text('Created through Flutter'), findsOneWidget);
      expect(find.text('Local space'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'continuing an immediate leave stores the new draft across route destruction without inserting',
    (tester) async {
      await mount(tester);
      await openNew(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-create-title')),
        'New draft across routes',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        (await memory.vault().read())!.edit.title,
        'New draft across routes',
      );
      await close(tester);
      await mount(tester);
      await openNew(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('html-create-title')))
            .controller!
            .text,
        'New draft across routes',
      );
      expect(await rows(tester), isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(memory.values, isEmpty);
      expect(await rows(tester), isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'restored unknown creation is read-only and adopts an existing note only after full review',
    (tester) async {
      final draft = HtmlNoteEdit(
        title: 'Lost creation result',
        source: '<!doctype html>\r\n<p>完整正文🧪</p>',
        labels: ['one,literal,label'],
      );
      final key = newHtmlCreationKey(), repo = LocalHtmlNotesRepository(store);
      final created = (await tester.runAsync(
        () => repo.createOnce(draft, creationKey: key),
      ))!.note;
      await memory.vault().write(
        HtmlCreationRecord(
          key: key,
          memberId: 1,
          collection: 'note',
          edit: draft,
          pending: true,
        ),
      );
      await mount(tester);
      await openNew(tester);
      expect(find.text('Creation result unresolved'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(sourceSurface.loadedReadOnly, false);
      expect(sourceSurface.inputLocked, true);
      await tester.ensureVisible(find.text('Verify device creation'));
      await tester.tap(find.text('Verify device creation'));
      await waitFor(
        tester,
        () =>
            find.text('Adopt reviewed note and continue').evaluate().isNotEmpty,
      );
      var adopt = find.widgetWithText(
        FilledButton,
        'Adopt reviewed note and continue',
      );
      expect(tester.widget<FilledButton>(adopt).onPressed, isNull);
      final full = find.text(
        'Note ID ${created.metadata.id} · View full version',
      );
      await tester.ensureVisible(full);
      await tester.tap(full);
      await tester.pumpAndSettle();
      expect(find.byType(HtmlVersionViewPage), findsOneWidget);
      expect(find.text('one,literal,label'), findsOneWidget);
      await tester.ensureVisible(find.text('Source'));
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(sourceSurface.source, draft.source);
      await tester.pageBack();
      await tester.pumpAndSettle();
      adopt = find.widgetWithText(
        FilledButton,
        'Adopt reviewed note and continue',
      );
      expect(tester.widget<FilledButton>(adopt).onPressed, isNotNull);
      await tester.ensureVisible(adopt);
      await tester.tap(adopt);
      await waitFor(
        tester,
        () => find.byType(HtmlNotePage).evaluate().isNotEmpty,
      );
      expect((await rows(tester)).single['id'], created.metadata.id);
      expect(
        (await rows(tester)).single['updated_at'],
        created.metadata.version,
      );
      expect(memory.values, isEmpty);
      expect(
        find.text(
          'Device content verified; the previous result was not received',
        ),
        findsOneWidget,
      );
      repo.dispose();
      await close(tester);
    },
  );
  testWidgets(
    'known creation cleanup failure exposes storage-only retry and never a second Save',
    (tester) async {
      memory.failRemove = true;
      await mount(tester);
      await openNew(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-create-title')),
        'Cleanup once',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await waitFor(
        tester,
        () => find.text('Retry device cleanup').evaluate().isNotEmpty,
      );
      expect(find.text('Save'), findsNothing);
      expect((await rows(tester)).length, 1);
      final id = (await rows(tester)).single['id'];
      memory.failRemove = false;
      await tester.ensureVisible(find.text('Retry device cleanup'));
      await tester.tap(find.text('Retry device cleanup'));
      await waitFor(
        tester,
        () => find.byType(HtmlNotePage).evaluate().isNotEmpty,
      );
      expect((await rows(tester)).single['id'], id);
      expect(memory.values, isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'English320dp doubled text new HTML source and leave actions stay accessible',
    (tester) async {
      await mount(tester, small: true);
      await openNew(tester);
      expect(find.text('Local space'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('html-create-title')),
        'Narrow local draft',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Keep draft and leave'));
      await tester.tap(find.text('Keep draft and leave'));
      await tester.pumpAndSettle();
      expect((await memory.vault().read())!.edit.title, 'Narrow local draft');
      expect(await rows(tester), isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
